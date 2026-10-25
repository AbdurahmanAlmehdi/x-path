import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/workflows/workflows_routes.dart';

/// The `/runs` endpoints: list the runs, of every project or one, look at
/// a run, cancel it, run its failed jobs again or the whole run again.
class RunsRoutes {
  /// Creates the routes over [_runs]; [_projects] tells a project that is
  /// not there, and [_dispatcher] dispatches a run again.
  const new(this._runs, this._projects, this._dispatcher);

  final RunService _runs;
  final ProjectService _projects;
  final WorkflowDispatcher _dispatcher;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/runs', _list)
      ..get('/projects/<id>/runs', _listOfProject)
      ..get('/runs/<id>', _get)
      ..post('/runs/<id>/cancel', _cancel)
      ..post('/runs/<id>/rerun-failed', _rerunFailed)
      ..post('/runs/<id>/run-again', _again);
  }

  Future<Response> _list(Request request, {String? projectId}) =>
      _guard(() async {
        final query = request.url.queryParameters;
        final limitText = query['limit'];
        final limit = limitText == null ? 50 : int.tryParse(limitText);
        if (limit == null || limit < 1 || limit > 200) {
          return errorResponse(
            ApiErrorCode.invalidRequest,
            'limit must be a number from 1 to 200.',
          );
        }
        final stateText = query['state'];
        final state = stateText == null ? null : RunState.fromWire(stateText);
        if (stateText != null && state == null) {
          return errorResponse(
            ApiErrorCode.invalidRequest,
            'state must be one of '
            '${RunState.values.map((s) => s.wire).join(', ')}.',
          );
        }
        final page = await _runs.list(
          projectId: projectId ?? query['project'],
          workflowId: query['workflow'],
          state: state,
          before: query['before'],
          limit: limit,
        );
        return jsonResponse(page.toJson());
      });

  Future<Response> _listOfProject(Request request, String id) async {
    try {
      await _projects.get(id);
    } on ProjectNotFoundException catch (error) {
      return errorResponse(ApiErrorCode.notFound, error.message);
    }
    return await _list(request, projectId: id);
  }

  Future<Response> _get(Request request, String id) => _guard(() async {
    return jsonResponse((await _runs.get(id)).toJson());
  });

  Future<Response> _cancel(Request request, String id) => _guard(() async {
    return jsonResponse((await _runs.cancel(id)).toJson());
  });

  Future<Response> _rerunFailed(Request request, String id) => _guard(() async {
    return jsonResponse((await _runs.rerunFailed(id)).toJson());
  });

  /// A new run of the same workflow version: a dispatch, so it fails as a
  /// dispatch does.
  Future<Response> _again(Request request, String id) =>
      guardWorkflows(() async {
        final run = await _dispatcher.again(id);
        return jsonResponse(
          run.toJson(),
          statusCode: 202,
          headers: {'location': '/runs/${run.id}'},
        );
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
