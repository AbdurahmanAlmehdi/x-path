import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/api_router.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The settings of the engine that are not about one area: the public URL
/// (ADR 0018), the HTTPS address browsers reach the engine at through a
/// proxy. Anyone reads it; an admin sets it (`route_permissions.dart`).
class SettingsRoutes {
  /// Creates the routes over [_publicUrl].
  const new(this._publicUrl);

  final PublicUrlService _publicUrl;

  /// Registers the routes on [router].
  void addTo(ApiRouter router) {
    router
      ..get('/settings/public-url', _read)
      ..put('/settings/public-url', _set);
  }

  Future<Response> _read(Request request) async =>
      jsonResponse((await _publicUrl.read()).toJson());

  Future<Response> _set(Request request) async {
    try {
      final body = await readJsonBody(request, SetPublicUrlRequest.fromJson);
      final set = await _publicUrl.set(body.url, by: deviceTokenOf(request));
      return jsonResponse(set.toJson());
    } on PublicUrlForbiddenException catch (error) {
      return errorResponse(ApiErrorCode.forbidden, error.message);
    } on BadRequestException catch (error) {
      return errorResponse(ApiErrorCode.invalidRequest, error.message);
    } on PublicUrlInvalidException catch (error) {
      return errorResponse(ApiErrorCode.invalidRequest, error.message);
    }
  }
}
