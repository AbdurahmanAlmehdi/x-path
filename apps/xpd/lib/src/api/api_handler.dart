import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/artifacts/artifacts_routes.dart';
import 'package:xpd/src/api/events_route.dart';
import 'package:xpd/src/api/jobs/job_logs_route.dart';
import 'package:xpd/src/api/jobs/jobs_routes.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/projects/projects_routes.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/system_routes.dart';
import 'package:xpd/src/api/tests/tests_routes.dart';

/// Routes that need no device token: a client can probe an engine, and read
/// its version, before it has been paired.
const publicPaths = {'/health', '/version'};

/// The whole HTTP API of the engine as one shelf handler.
///
/// Every route but [publicPaths] needs a device token. [onError] hears about
/// exceptions that became `500` responses.
Handler buildApiHandler({
  required TokenService tokens,
  required EventsRoute events,
  required ProjectService projects,
  required JobRunner jobs,
  required JobLogsRoute jobLogs,
  required ArtifactService artifacts,
  required TestRunService tests,
  required String engineVersion,
  void Function(Object error, StackTrace stackTrace)? onError,
}) {
  final router =
      Router(
          notFoundHandler: (request) => errorResponse(
            ApiErrorCode.notFound,
            'No route for ${request.method} ${request.requestedUri.path}.',
          ),
        )
        ..get('/health', health)
        ..get('/version', version(engineVersion))
        ..get('/events', events.handle)
        ..get('/jobs/<id>/logs', jobLogs.handle);
  ProjectsRoutes(projects).addTo(router);
  JobsRoutes(jobs).addTo(router);
  ArtifactsRoutes(artifacts).addTo(router);
  TestsRoutes(tests).addTo(router);
  return const Pipeline()
      .addMiddleware(errorMiddleware(onError: onError))
      .addMiddleware(authMiddleware(tokens, publicPaths: publicPaths))
      .addHandler(router.call);
}
