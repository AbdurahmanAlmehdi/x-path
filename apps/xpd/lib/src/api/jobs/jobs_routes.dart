import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/request_body.dart';
import 'package:xpd/src/api/responses.dart';

/// The `/jobs` endpoints: read, cancel and resume a job. The log WebSocket is
/// `JobLogsRoute`.
///
/// Cancelling and resuming go through the scheduler in the engine, which
/// decides when a resumed job gets its place again.
class JobsRoutes {
  /// Creates the routes over [_jobs].
  const new(this._jobs);

  final JobControl _jobs;

  /// Registers the routes on [router].
  void addTo(Router router) {
    router
      ..get('/jobs/<id>', _get)
      ..post('/jobs/<id>/cancel', _cancel)
      ..post('/jobs/<id>/resume', _resume);
  }

  Future<Response> _get(Request request, String id) => guardJobs(() async {
    return jsonResponse((await _jobs.get(id)).toJson());
  });

  Future<Response> _cancel(Request request, String id) => guardJobs(() async {
    return jsonResponse((await _jobs.cancel(id)).toJson());
  });

  Future<Response> _resume(Request request, String id) => guardJobs(() async {
    final body = await request.readAsString();
    final fromStep = body.trim().isEmpty
        ? null
        : (await readJsonBody(
            request.change(body: body),
            ResumeJobRequest.fromJson,
          )).fromStep;
    final job = await _jobs.resume(id, fromStep: fromStep);
    return jsonResponse(job.toJson(), statusCode: 202);
  });
}

/// Runs [action] and turns the failures a client can cause into error
/// responses. Anything else is left to the error middleware (`500`).
Future<Response> guardJobs(Future<Response> Function() action) async {
  try {
    return await action();
  } on BadRequestException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  } on JobNotFoundException catch (error) {
    return errorResponse(ApiErrorCode.notFound, error.message);
  } on JobStateException catch (error) {
    return errorResponse(ApiErrorCode.conflict, error.message);
  } on JobInvalidException catch (error) {
    return errorResponse(ApiErrorCode.invalidRequest, error.message);
  }
}
