import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The GitHub token of the engine: one, shared by every project. Reading it
/// asks GitHub who it belongs to; setting it (pasted, or taken from the
/// GitHub CLI of the engine machine) checks it with GitHub first. Only `app`
/// and `cli` tokens may change it. No response, log or error carries the
/// token, and the request body that does is never logged.
class GitHubTokenRoutes {
  /// Creates the routes over [_service].
  const new(this._service);

  final GitHubTokenService _service;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/github-token', _status)
      ..put('/github-token', _save)
      ..delete('/github-token', _clear)
      ..post('/github-token/import', _import);
  }

  Future<Response> _status(Request request) => _guard(() async {
    return jsonResponse((await _service.status()).toJson());
  });

  Future<Response> _save(Request request) => _guard(() async {
    final body = await readJsonBody(request, _parse);
    final status = await _service.save(body.token, by: deviceTokenOf(request));
    return jsonResponse(status.toJson());
  });

  Future<Response> _import(Request request) => _guard(() async {
    final status = await _service.importFromCli(by: deviceTokenOf(request));
    return jsonResponse(status.toJson());
  });

  Future<Response> _clear(Request request) => _guard(() async {
    await _service.clear(by: deviceTokenOf(request));
    return Response(204);
  });

  /// Reads the body of a save. A malformed one is a `400` that never repeats
  /// what it holds.
  static SetGitHubTokenRequest _parse(Map<String, dynamic> json) {
    if (json['token'] is! String) {
      throw const BadRequestException('"token" must be a string.');
    }
    return SetGitHubTokenRequest.fromJson(json);
  }
}

/// Runs [action] and turns the failures a client can cause or fix into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> _guard(Future<Response> Function() action) async {
  try {
    return await action();
  } on BadRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on GitHubTokenForbiddenException catch (error) {
    return errorResponse(ApiErrorCode.forbidden, error.message);
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
