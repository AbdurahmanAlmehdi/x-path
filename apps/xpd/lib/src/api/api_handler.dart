import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/allowed_origins.dart';
import 'package:xpd/src/api/api_router.dart';
import 'package:xpd/src/api/approvals/approvals_routes.dart';
import 'package:xpd/src/api/artifacts/artifacts_routes.dart';
import 'package:xpd/src/api/credentials/credentials_routes.dart';
import 'package:xpd/src/api/csrf_middleware.dart';
import 'package:xpd/src/api/events_route.dart';
import 'package:xpd/src/api/github/github_token_routes.dart';
import 'package:xpd/src/api/jobs/job_logs_route.dart';
import 'package:xpd/src/api/jobs/jobs_routes.dart';
import 'package:xpd/src/api/legacy_alias.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/people/people_routes.dart';
import 'package:xpd/src/api/permission_middleware.dart';
import 'package:xpd/src/api/projects/projects_routes.dart';
import 'package:xpd/src/api/releases/releases_routes.dart';
import 'package:xpd/src/api/responses.dart';
import 'package:xpd/src/api/runners/runner_connect_route.dart';
import 'package:xpd/src/api/runners/runners_routes.dart';
import 'package:xpd/src/api/runs/runs_routes.dart';
import 'package:xpd/src/api/session/me_routes.dart';
import 'package:xpd/src/api/session/session_routes.dart';
import 'package:xpd/src/api/settings/settings_routes.dart';
import 'package:xpd/src/api/storage/storage_routes.dart';
import 'package:xpd/src/api/system_routes.dart';
import 'package:xpd/src/api/tests/tests_routes.dart';
import 'package:xpd/src/api/tokens/tokens_routes.dart';
import 'package:xpd/src/api/workflows/workflows_routes.dart';

/// Routes that need no device token: a client can probe an engine, and read
/// its version, before it has been paired; a runner exchanges its pairing
/// token for a credential.
const publicPaths = {'/health', '/version', '/runners/pair'};

/// The whole HTTP API of the engine as one shelf handler, and the routes it
/// serves.
///
/// The API is served under `/api/v1`, and its root paths stay bearer-only
/// aliases ([legacyAlias], ADR 0018). Every route but [publicPaths] and
/// `POST /session` needs a device token (or, under `/api/v1`, a browser's
/// session cookie, whose requests that change something pass the CSRF
/// check), and every mutating route the permission `route_permissions.dart`
/// names for it. [onError] hears about exceptions that became `500`
/// responses.
({Handler handler, List<ApiRoute> routes}) buildApiHandler({
  required TokenService tokens,
  required PersonService people,
  required SignInCodeService signIn,
  required PublicUrlService publicUrl,
  required AllowedOrigins origins,
  required EventsRoute events,
  required ProjectService projects,
  required JobControl jobs,
  required JobLogsRoute jobLogs,
  required ArtifactService artifacts,
  required TestRunService tests,
  required CredentialService credentials,
  required DistributionCertificates certificates,
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
  required EngineDoctor engineDoctor,
  required SecretStore secrets,
  required String engineVersion,
  void Function(Object error, StackTrace stackTrace)? onError,
  void Function(String address, String why)? onRunnerRefused,
}) {
  final router =
      ApiRouter(
          notFoundHandler: (request) => errorResponse(
            ApiErrorCode.notFound,
            'No route for ${request.method} ${request.requestedUri.path}.',
          ),
        )
        ..get('/health', health)
        ..get('/version', version(engineVersion))
        ..get('/doctor', doctor(engineDoctor))
        ..get('/status', status(secrets))
        ..get('/events', events.handle)
        ..get('/jobs/<id>/logs', jobLogs.handle)
        ..get('/runners/connect', runnerConnect.handle);
  ProjectsRoutes(projects).addTo(router);
  JobsRoutes(jobs).addTo(router);
  ArtifactsRoutes(artifacts).addTo(router);
  TestsRoutes(tests).addTo(router);
  CredentialsRoutes(credentials, certificates).addTo(router);
  GitHubTokenRoutes(githubToken).addTo(router);
  WorkflowsRoutes(workflows, dispatcher).addTo(router);
  RunsRoutes(runs, projects, dispatcher).addTo(router);
  ApprovalsRoutes(approvals).addTo(router);
  ReleasesRoutes(releases, releaseNotes).addTo(router);
  StorageRoutes(housekeeping).addTo(router);
  RunnersRoutes(runners, runnerArtifacts, runnerBundles).addTo(router);
  TokensRoutes(tokens).addTo(router);
  PeopleRoutes(people).addTo(router);
  const MeRoutes().addTo(router);
  SessionRoutes(signIn: signIn, tokens: tokens, origins: origins).addTo(router);
  SettingsRoutes(publicUrl).addTo(router);
  final handler = const Pipeline()
      .addMiddleware(errorMiddleware(onError: onError))
      .addMiddleware(runnerRefusalMiddleware(onRunnerRefused ?? (_, _) {}))
      .addMiddleware(
        authMiddleware(
          tokens,
          publicPaths: publicPaths,
          publicRoutes: SessionRoutes.publicRoutes,
        ),
      )
      .addMiddleware(csrfMiddleware(origins))
      .addMiddleware(runnerScopeMiddleware())
      .addMiddleware(permissionMiddleware(router.routes))
      .addHandler(router.call);
  return (
    handler: legacyAlias(handler, publicPaths: publicPaths),
    routes: router.routes,
  );
}
