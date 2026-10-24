import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/approvals/approvals_routes.dart';
import 'package:xpd/src/api/artifacts/artifacts_routes.dart';
import 'package:xpd/src/api/credentials/credentials_routes.dart';
import 'package:xpd/src/api/events_route.dart';
import 'package:xpd/src/api/github/github_token_routes.dart';
import 'package:xpd/src/api/jobs/job_logs_route.dart';
import 'package:xpd/src/api/jobs/jobs_routes.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/projects/projects_routes.dart';
import 'package:xpd/src/api/releases/releases_routes.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/runners/runner_connect_route.dart';
import 'package:xpd/src/api/runners/runners_routes.dart';
import 'package:xpd/src/api/runs/runs_routes.dart';
import 'package:xpd/src/api/storage/storage_routes.dart';
import 'package:xpd/src/api/system_routes.dart';
import 'package:xpd/src/api/tests/tests_routes.dart';
import 'package:xpd/src/api/workflows/workflows_routes.dart';

/// Routes that need no device token: a client can probe an engine, and read
/// its version, before it has been paired; a runner exchanges its pairing
/// token for a credential.
const publicPaths = {'/health', '/version', '/runners/pair'};

/// The whole HTTP API of the engine as one shelf handler.
///
/// Every route but [publicPaths] needs a device token. [onError] hears about
/// exceptions that became `500` responses.
Handler buildApiHandler({
  required TokenService tokens,
  required EventsRoute events,
  required ProjectService projects,
  required JobControl jobs,
  required JobLogsRoute jobLogs,
  required ArtifactService artifacts,
  required TestRunService tests,
  required CredentialService credentials,
  required GitHubTokenService githubToken,
  required WorkflowService workflows,
  required WorkflowDispatcher dispatcher,
  required RunService runs,
  required ApprovalService approvals,
  required ReleaseService releases,
  required ReleaseNotesService releaseNotes,
  required HousekeepingService housekeeping,
  required RunnerService runners,
  required RunnerConnectRoute runnerConnect,
  required RunnerArtifacts runnerArtifacts,
  required RunnerBundles runnerBundles,
  required String engineVersion,
  void Function(Object error, StackTrace stackTrace)? onError,
  void Function(String address, String why)? onRunnerRefused,
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
        ..get('/jobs/<id>/logs', jobLogs.handle)
        ..get('/runners/connect', runnerConnect.handle);
  ProjectsRoutes(projects).addTo(router);
  JobsRoutes(jobs).addTo(router);
  ArtifactsRoutes(artifacts).addTo(router);
  TestsRoutes(tests).addTo(router);
  CredentialsRoutes(credentials).addTo(router);
  GitHubTokenRoutes(githubToken).addTo(router);
  WorkflowsRoutes(workflows, dispatcher).addTo(router);
  RunsRoutes(runs, projects).addTo(router);
  ApprovalsRoutes(approvals).addTo(router);
  ReleasesRoutes(releases, releaseNotes).addTo(router);
  StorageRoutes(housekeeping).addTo(router);
  RunnersRoutes(runners, runnerArtifacts, runnerBundles).addTo(router);
  return const Pipeline()
      .addMiddleware(errorMiddleware(onError: onError))
      .addMiddleware(runnerRefusalMiddleware(onRunnerRefused ?? (_, _) {}))
      .addMiddleware(authMiddleware(tokens, publicPaths: publicPaths))
      .addMiddleware(runnerScopeMiddleware())
      .addHandler(router.call);
}
