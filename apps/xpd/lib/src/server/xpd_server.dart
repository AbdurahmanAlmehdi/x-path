import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/api_handler.dart';
import 'package:xpd/src/api/events_route.dart';
import 'package:xpd/src/api/jobs/job_logs_route.dart';
import 'package:xpd/src/api/runners/runner_connect_route.dart';

/// A running engine HTTP server.
class XpdServer {
  new _(this._http, this._route, this._logRoute, this._runnerRoute)
    : uri = Uri(scheme: 'http', host: _http.address.host, port: _http.port);

  /// Binds [host]:[port] (port 0 picks a free one) and starts serving.
  ///
  /// Logs [EngineStarted] once the socket is bound. Loopback is the default:
  /// binding another address exposes the engine to the network.
  static Future<XpdServer> start({
    required TokenService tokens,
    required EventLog events,
    required ProjectService projects,
    required JobControl jobs,
    required JobLogs logs,
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
    required RunnerHub runnerHub,
    required RunnerArtifacts runnerArtifacts,
    required RunnerBundles runnerBundles,
    required Clock clock,
    required String engineVersion,
    String host = '127.0.0.1',
    int port = 0,
    void Function(Object error, StackTrace stackTrace)? onError,
    void Function(String address, String why)? onRunnerRefused,
  }) async {
    final route = EventsRoute(events: events, clock: clock);
    final logRoute = JobLogsRoute(jobs: jobs, logs: logs);
    final runnerRoute = RunnerConnectRoute(runners: runners, hub: runnerHub);
    final handler = buildApiHandler(
      tokens: tokens,
      events: route,
      projects: projects,
      jobs: jobs,
      jobLogs: logRoute,
      artifacts: artifacts,
      tests: tests,
      credentials: credentials,
      githubToken: githubToken,
      workflows: workflows,
      dispatcher: dispatcher,
      runs: runs,
      approvals: approvals,
      releases: releases,
      releaseNotes: releaseNotes,
      housekeeping: housekeeping,
      runners: runners,
      runnerConnect: runnerRoute,
      runnerArtifacts: runnerArtifacts,
      runnerBundles: runnerBundles,
      engineVersion: engineVersion,
      onError: onError,
      onRunnerRefused: onRunnerRefused,
    );
    final http = await shelf_io.serve(handler, host, port);
    events.append(
      EngineStarted(version: engineVersion, apiVersion: apiVersion),
    );
    return ._(http, route, logRoute, runnerRoute);
  }

  final HttpServer _http;
  final EventsRoute _route;
  final JobLogsRoute _logRoute;
  final RunnerConnectRoute _runnerRoute;

  /// The address clients connect to, for example `http://127.0.0.1:7480`.
  final Uri uri;

  /// Stops accepting connections and closes every event, log and runner
  /// stream with code 1000 (normal closure).
  Future<void> close() async {
    await _http.close();
    await _logRoute.closeSockets();
    await _runnerRoute.closeSockets();
    await _route.closeSockets();
  }
}
