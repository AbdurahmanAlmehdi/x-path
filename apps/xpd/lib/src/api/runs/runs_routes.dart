import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/responses.dart';

/// The `/runs` endpoints: look at a run and cancel it.
class RunsRoutes {
  /// Creates the routes over [_runs].
  const new(this._runs);

  final RunService _runs;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/runs/<id>', _get)
      ..post('/runs/<id>/cancel', _cancel);
  }

  Future<Response> _get(Request request, String id) => _guard(() async {
    return jsonResponse((await _runs.get(id)).toJson());
  });

  Future<Response> _cancel(Request request, String id) => _guard(() async {
    return jsonResponse((await _runs.cancel(id)).toJson());
  });
}

Future<Response> _guard(Future<Response> Function() action) async {
  try {
    return await action();
  } on RunNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on RunStateException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on JobStateException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  }
}
