import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The storage endpoints (D-22): what the engine keeps on its disk, "free up
/// space", and the retention settings.
///
/// Anyone with a token may read the report and dry-run. Deleting
/// (`"dryRun": false`) is a gated action (D-13); a gate binds an approval to
/// one project and one commit, which housekeeping, across every project, does
/// not have, so it is for `app` and `cli` tokens only, as abandoning a release
/// is: the owner acting from the app or `xp` is the approval. Changing the
/// retention is for them too. An `mcp` or `runner` token that tries gets `403
/// forbidden`; the rules are the [HousekeepingService]'s.
class StorageRoutes {
  /// Creates the routes over [_housekeeping].
  const new(this._housekeeping);

  final HousekeepingService _housekeeping;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/storage', _report)
      ..post('/storage/free', _free)
      ..get('/storage/retention', _getRetention)
      ..put('/storage/retention', _putRetention);
  }

  Future<Response> _report(Request request) => _guard(() async {
    return jsonResponse((await _housekeeping.report()).toJson());
  });

  Future<Response> _free(Request request) => _guard(() async {
    final body = await readOptionalJsonBody(
      request,
      FreeSpaceRequest.fromJson,
      whenEmpty: const FreeSpaceRequest(),
    );
    final result = await _housekeeping.free(body, by: deviceTokenOf(request));
    return jsonResponse(result.toJson());
  });

  Future<Response> _getRetention(Request request) => _guard(() async {
    return jsonResponse((await _housekeeping.retention()).toJson());
  });

  Future<Response> _putRetention(Request request) => _guard(() async {
    final body = await readJsonBody(request, RetentionSettings.fromJson);
    final saved = await _housekeeping.setRetention(
      body,
      by: deviceTokenOf(request),
    );
    return jsonResponse(saved.toJson());
  });
}

/// Runs [action] and turns the failures a client can cause into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> _guard(Future<Response> Function() action) async {
  try {
    return await action();
  } on BadRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on HousekeepingForbiddenException catch (error) {
    return errorResponse(ApiErrorCode.forbidden, error.message);
  } on HousekeepingRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  }
}
