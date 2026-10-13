import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The credential endpoints of a project: list, save (verified first), verify
/// again and delete.
///
/// The response never carries a secret. The body of a save does, so nothing
/// here logs a request, and a failure says which field is wrong but never what
/// it holds.
class CredentialsRoutes {
  /// Creates the routes over [_credentials].
  const new(this._credentials);

  final CredentialService _credentials;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/projects/<id>/credentials', _list)
      ..put('/projects/<id>/credentials', _save)
      ..post('/projects/<id>/credentials/<credentialId>/verify', _verify)
      ..delete('/projects/<id>/credentials/<credentialId>', _remove);
  }

  Future<Response> _list(Request request, String id) => _guard(() async {
    final query = request.requestedUri.queryParameters;
    final credentials = await _credentials.list(
      id,
      app: query['app'],
      flavor: query['flavor'],
    );
    return jsonResponse(CredentialsResponse(credentials).toJson());
  });

  Future<Response> _save(Request request, String id) => _guard(() async {
    final body = await readJsonBody(request, _parse);
    final saved = await _credentials.save(id, body);
    return jsonResponse(
      saved.credential.toJson(),
      statusCode: saved.created ? 201 : 200,
      headers: saved.created
          ? {'location': '/projects/$id/credentials/${saved.credential.id}'}
          : const {},
    );
  });

  Future<Response> _verify(Request request, String id, String credentialId) =>
      _guard(() async {
        return jsonResponse(
          (await _credentials.verify(id, credentialId)).toJson(),
        );
      });

  Future<Response> _remove(Request request, String id, String credentialId) =>
      _guard(() async {
        await _credentials.remove(id, credentialId);
        return Response(204);
      });

  /// Reads the body of a save. A malformed one is a `400` that names the
  /// field, not its value.
  static SaveCredentialRequest _parse(Map<String, dynamic> json) {
    try {
      return SaveCredentialRequest.fromJson(json);
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
  } on ProjectNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on CredentialNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on CredentialRejectedException catch (error) {
    return errorResponse(ApiErrorCode.credentialRejected, error.described);
  } on CredentialUnreachableException catch (error) {
    return errorResponse(
      ApiErrorCode.upstreamError,
      '${error.described} Nothing was stored.',
    );
  } on SecretsLockedException {
    return errorResponse(
      ApiErrorCode.secretsLocked,
      'The engine cannot read its secrets right now. Unlock them and retry.',
    );
  }
}
