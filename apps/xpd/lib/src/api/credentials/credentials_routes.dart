import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The credential endpoints: the named credentials of the engine (list,
/// create, rename, replace the secret, verify, delete), the credentials each
/// flavor of a project uses (list, assign, unassign) and the deprecated
/// per-flavor routes of before credentials had names (ADR 0013).
///
/// Only `app` and `cli` tokens change credentials; `mcp` tokens read them.
/// The response never carries a secret. The body of a create, a replace or a
/// deprecated save does, so nothing here logs a request, and a failure says
/// which field is wrong but never what it holds.
class CredentialsRoutes {
  /// Creates the routes over [_credentials].
  const new(this._credentials);

  final CredentialService _credentials;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/credentials', _listNamed)
      ..post('/credentials', _create)
      ..get('/credentials/<credentialId>', _get)
      ..patch('/credentials/<credentialId>', _rename)
      ..put('/credentials/<credentialId>', _replace)
      ..delete('/credentials/<credentialId>', _delete)
      ..post('/credentials/<credentialId>/verify', _verifyNamed)
      ..get('/projects/<id>/credentials', _list)
      ..put('/projects/<id>/credentials', _save)
      ..put('/projects/<id>/flavors/<flavor>/credentials/<kind>', _assign)
      ..delete('/projects/<id>/flavors/<flavor>/credentials/<kind>', _unassign)
      ..post('/projects/<id>/credentials/<credentialId>/verify', _verify)
      ..delete('/projects/<id>/credentials/<credentialId>', _remove);
  }

  // ------------------------------------------------------- named credentials

  Future<Response> _listNamed(Request request) => _guard(
    () async => jsonResponse(
      NamedCredentialsResponse(await _credentials.list()).toJson(),
    ),
  );

  Future<Response> _create(Request request) => _guard(() async {
    final body = await readJsonBody(
      request,
      (json) => _parse(() => CreateCredentialRequest.fromJson(json)),
    );
    final created = await _credentials.create(body, by: deviceTokenOf(request));
    return jsonResponse(
      created.toJson(),
      statusCode: 201,
      headers: {'location': '/credentials/${created.id}'},
    );
  });

  Future<Response> _get(Request request, String credentialId) => _guard(
    () async => jsonResponse((await _credentials.get(credentialId)).toJson()),
  );

  Future<Response> _rename(Request request, String credentialId) =>
      _guard(() async {
        final body = await readJsonBody(
          request,
          (json) => _parse(() => RenameCredentialRequest.fromJson(json)),
        );
        return jsonResponse(
          (await _credentials.rename(
            credentialId,
            body.name,
            by: deviceTokenOf(request),
          )).toJson(),
        );
      });

  Future<Response> _replace(Request request, String credentialId) =>
      _guard(() async {
        final (kind, body) = await readJsonBody(
          request,
          (json) => (json['kind'], ReplaceCredentialRequest.fromJson(json)),
        );
        final current = await _credentials.get(credentialId);
        if (kind != null && kind != current.kind.wire) {
          throw BadRequestException(
            '"kind" must be the kind of the credential, '
            '${current.kind.wire}.',
          );
        }
        return jsonResponse(
          (await _credentials.replace(
            credentialId,
            body,
            by: deviceTokenOf(request),
          )).toJson(),
        );
      });

  Future<Response> _delete(Request request, String credentialId) => _guard(
    () async {
      final force = switch (request.requestedUri.queryParameters['force']) {
        null || 'false' => false,
        'true' => true,
        _ => throw const BadRequestException('"force" must be true or false.'),
      };
      await _credentials.remove(
        credentialId,
        force: force,
        by: deviceTokenOf(request),
      );
      return Response(204);
    },
  );

  Future<Response> _verifyNamed(Request request, String credentialId) => _guard(
    () async => jsonResponse(
      (await _credentials.verify(
        credentialId,
        by: deviceTokenOf(request),
      )).toJson(),
    ),
  );

  // ------------------------------------------------- what flavors use

  Future<Response> _list(Request request, String id) => _guard(() async {
    final query = request.requestedUri.queryParameters;
    final credentials = await _credentials.listForProject(
      id,
      app: query['app'],
      flavor: query['flavor'],
    );
    return jsonResponse(CredentialsResponse(credentials).toJson());
  });

  Future<Response> _assign(
    Request request,
    String id,
    String flavor,
    String kind,
  ) => _guard(() async {
    final body = await readJsonBody(
      request,
      (json) => _parse(() => AssignCredentialRequest.fromJson(json)),
    );
    final result = await _credentials.assign(
      id,
      app: _app(request),
      flavor: flavor,
      kind: _kind(kind),
      request: body,
      by: deviceTokenOf(request),
    );
    return jsonResponse(result.toJson());
  });

  Future<Response> _unassign(
    Request request,
    String id,
    String flavor,
    String kind,
  ) => _guard(() async {
    await _credentials.unassign(
      id,
      app: _app(request),
      flavor: flavor,
      kind: _kind(kind),
      by: deviceTokenOf(request),
    );
    return Response(204);
  });

  // ------------------------------------------------- deprecated routes

  Future<Response> _save(Request request, String id) => _guard(() async {
    final body = await readJsonBody(
      request,
      (json) => _parse(() => SaveCredentialRequest.fromJson(json)),
    );
    final saved = await _credentials.saveForFlavor(
      id,
      body,
      by: deviceTokenOf(request),
    );
    return jsonResponse(
      saved.credential.toJson(),
      statusCode: saved.created ? 201 : 200,
      headers: saved.created
          ? {'location': '/credentials/${saved.credential.id}'}
          : const {},
    );
  });

  Future<Response> _verify(Request request, String id, String credentialId) =>
      _guard(
        () async => jsonResponse(
          (await _credentials.verifyInProject(
            id,
            credentialId,
            by: deviceTokenOf(request),
          )).toJson(),
        ),
      );

  Future<Response> _remove(Request request, String id, String credentialId) =>
      _guard(() async {
        await _credentials.removeFromProject(
          id,
          credentialId,
          by: deviceTokenOf(request),
        );
        return Response(204);
      });

  // ---------------------------------------------------------------- helpers

  static String _app(Request request) {
    final app = request.requestedUri.queryParameters['app'];
    if (app == null) return '.';
    if (app.isEmpty) {
      throw const BadRequestException('"app" must be a non-empty string.');
    }
    return app;
  }

  static CredentialKind _kind(String wire) =>
      CredentialKind.fromWire(wire) ??
      (throw BadRequestException(
        'The kind must be one of '
        '${CredentialKind.values.map((kind) => kind.wire).join(', ')}.',
      ));

  /// Reads a body with [read]. A malformed one is a `400` that names the
  /// field, not its value.
  static T _parse<T>(T Function() read) {
    try {
      return read();
    } on FormatException catch (error) {
      throw BadRequestException(error.message);
    }
  }
}

/// Runs [action] and turns the failures a client can cause or fix into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> _guard(Future<Response> Function() action) async {
  try {
    return await action();
  } on BadRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on CredentialRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on CredentialForbiddenException catch (error) {
    return errorResponse(ApiErrorCode.forbidden, error.message);
  } on ProjectNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on CredentialNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on CredentialConflictException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on CredentialInUseException catch (error) {
    return Response(
      ApiErrorCode.credentialInUse.statusCode,
      body: jsonEncode({
        ...ErrorResponse.of(
          ApiErrorCode.credentialInUse,
          error.message,
        ).toJson(),
        'usedBy': [for (final usage in error.usedBy) usage.toJson()],
      }),
      headers: const {'content-type': 'application/json'},
    );
  } on CredentialRejectedException catch (error) {
    return errorResponse(ApiErrorCode.credentialRejected, error.described);
  } on CredentialUnreachableException catch (error) {
    return errorResponse(
      ApiErrorCode.upstreamError,
      '${error.described} Nothing was stored.',
    );
  } on SecretsLockedException {
    return secretsLockedResponse();
  }
}
