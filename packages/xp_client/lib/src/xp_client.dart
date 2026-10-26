import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/src/artifact_download.dart';
import 'package:xp_client/src/event_feed.dart';
import 'package:xp_client/src/exceptions.dart';
import 'package:xp_client/src/log_feed.dart';
import 'package:xp_client/src/user_agent.dart';
import 'package:xp_client/src/web_socket_connector.dart';

/// Waits for [Duration]. [XpClient] uses it between reconnects; tests pass a
/// fake.
typedef Delay = Future<void> Function(Duration duration);

/// A client of the engine API (`packages/xp_api/openapi.yaml`).
///
/// One client holds one device token (D-06) and talks to one engine. Every
/// method throws an [ApiException] when the engine answers with an error and a
/// [ConnectionException] when it cannot be reached.
class XpClient {
  /// Creates a client of the engine at [baseUrl], for the owner of [token].
  ///
  /// [httpClient], [connectWebSocket] and [delay] are the HTTP client, the
  /// WebSocket opener and the clock of the reconnect back-off; they default to
  /// the real ones and exist for tests. A client given an [httpClient] does
  /// not close it.
  new({
    required this.baseUrl,
    required this.token,
    http.Client? httpClient,
    WebSocketConnector? connector,
    this.requestTimeout = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    Delay? delay,
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _connector = connector ?? connectWebSocket,
       _delay = delay ?? Future<void>.delayed;

  /// The engine, for example `http://127.0.0.1:7480`.
  final Uri baseUrl;

  /// The device token. It is sent as `Authorization: Bearer` to every route
  /// except `GET /health` and `GET /version`.
  final String token;

  /// How long to wait for the engine to answer a request.
  final Duration requestTimeout;

  /// The first wait before a stream reconnects; it doubles while the engine
  /// stays away.
  final Duration reconnectDelay;

  /// The longest wait before a stream reconnects.
  final Duration maxReconnectDelay;

  final http.Client _http;
  final bool _ownsHttp;
  final WebSocketConnector _connector;
  final Delay _delay;

  /// Releases the connections this client opened.
  void close() {
    if (_ownsHttp) _http.close();
  }

  // ---------------------------------------------------------------- system

  /// `GET /health`: whether the engine serves. Needs no token.
  Future<HealthResponse> health() async => HealthResponse.fromJson(
    await _json(await _send('GET', ['health'], authenticated: false)),
  );

  /// `GET /version`: the engine's and the API's version. Needs no token.
  Future<VersionResponse> version() async => VersionResponse.fromJson(
    await _json(await _send('GET', ['version'], authenticated: false)),
  );

  // -------------------------------------------------------------- projects

  /// `GET /projects`: every project, oldest first.
  Future<List<Project>> listProjects() async =>
      ProjectsResponse.fromJson(await _json(await _send('GET', ['projects'])))
          .projects;

  /// `GET /projects/{id}`.
  Future<Project> getProject(String id) async =>
      Project.fromJson(await _json(await _send('GET', ['projects', id])));

  /// `POST /projects`: adds a project and scans it.
  Future<Project> addProject(AddProjectRequest request) async =>
      Project.fromJson(
        await _json(await _send('POST', ['projects'], body: request.toJson())),
      );

  /// `POST /projects/{id}/scan`.
  Future<Project> scanProject(String id) async => Project.fromJson(
    await _json(await _send('POST', ['projects', id, 'scan'])),
  );

  /// `PATCH /projects/{id}`: edits the profile.
  Future<Project> updateProject(String id, ProfileEdits edits) async =>
      Project.fromJson(
        await _json(
          await _send('PATCH', ['projects', id], body: edits.toJson()),
        ),
      );

  /// `DELETE /projects/{id}`.
  Future<void> removeProject(String id) async {
    await _send('DELETE', ['projects', id]);
  }

  // ------------------------------------------------------------- workflows

  /// `GET /workflows/schema`: what a workflow document may name.
  Future<WorkflowSchema> getWorkflowSchema() async => WorkflowSchema.fromJson(
    await _json(await _send('GET', ['workflows', 'schema'])),
  );

  /// `GET /workflows/templates`: the documents a new workflow can start
  /// from.
  Future<List<WorkflowTemplate>> listWorkflowTemplates() async =>
      WorkflowTemplatesResponse.fromJson(
        await _json(await _send('GET', ['workflows', 'templates'])),
      ).templates;

  /// `GET /projects/{id}/workflows`.
  Future<List<WorkflowSummary>> listWorkflows(String projectId) async =>
      WorkflowsResponse.fromJson(
        await _json(await _send('GET', ['projects', projectId, 'workflows'])),
      ).workflows;

  /// `GET /projects/{id}/workflows/{workflowId}`, at [version] or the newest.
  Future<Workflow> getWorkflow(
    String projectId,
    String workflowId, {
    int? version,
  }) async => Workflow.fromJson(
    await _json(
      await _send(
        'GET',
        ['projects', projectId, 'workflows', workflowId],
        query: {'version': ?version?.toString()},
      ),
    ),
  );

  /// `POST /projects/{id}/workflows`.
  Future<Workflow> createWorkflow(
    String projectId,
    CreateWorkflowRequest request,
  ) async => Workflow.fromJson(
    await _json(
      await _send('POST', [
        'projects',
        projectId,
        'workflows',
      ], body: request.toJson()),
    ),
  );

  /// `POST /projects/{id}/workflows/validate`: checks [yaml] without saving.
  /// Without a [projectId], `POST /workflows/validate`: the check is the
  /// same for every project.
  Future<ValidateWorkflowResponse> validateWorkflow(
    String? projectId,
    String yaml,
  ) async => ValidateWorkflowResponse.fromJson(
    await _json(
      await _send('POST', [
        if (projectId != null) ...['projects', projectId],
        'workflows',
        'validate',
      ], body: WorkflowYamlRequest(yaml: yaml).toJson()),
    ),
  );

  /// `PUT /projects/{id}/workflows/{workflowId}`: saves a new version.
  Future<Workflow> saveWorkflow(
    String projectId,
    String workflowId,
    String yaml,
  ) async => Workflow.fromJson(
    await _json(
      await _send('PUT', [
        'projects',
        projectId,
        'workflows',
        workflowId,
      ], body: WorkflowYamlRequest(yaml: yaml).toJson()),
    ),
  );

  /// `PATCH /projects/{id}/workflows/{workflowId}`: renames, archives or
  /// unarchives a workflow, or catches a copy up with its built-in.
  Future<Workflow> updateWorkflow(
    String projectId,
    String workflowId,
    UpdateWorkflowRequest request,
  ) async => Workflow.fromJson(
    await _json(
      await _send('PATCH', [
        'projects',
        projectId,
        'workflows',
        workflowId,
      ], body: request.toJson()),
    ),
  );

  /// `DELETE /projects/{id}/workflows/{workflowId}`.
  Future<void> deleteWorkflow(String projectId, String workflowId) async {
    await _send('DELETE', ['projects', projectId, 'workflows', workflowId]);
  }

  /// `POST /projects/{id}/workflows/{workflowId}/dispatch`: runs a workflow.
  Future<Run> dispatchWorkflow(
    String projectId,
    String workflowId,
    DispatchRequest request,
  ) async => Run.fromJson(
    await _json(
      await _send('POST', [
        'projects',
        projectId,
        'workflows',
        workflowId,
        'dispatch',
      ], body: request.toJson()),
    ),
  );

  /// `POST /projects/{id}/workflows/{workflowId}/dispatch?dryRun=true`:
  /// what dispatching would start, planned by the engine; nothing starts and
  /// no build number is taken.
  Future<DispatchPlan> planDispatch(
    String projectId,
    String workflowId,
    DispatchRequest request,
  ) async => DispatchPlan.fromJson(
    await _json(
      await _send(
        'POST',
        ['projects', projectId, 'workflows', workflowId, 'dispatch'],
        query: {'dryRun': 'true'},
        body: request.toJson(),
      ),
    ),
  );

  // ------------------------------------------------------------- runs, jobs

  /// `GET /runs`: the runs newest first, of [projectId], of [workflowId]
  /// and in [state] when given, dispatched before the run [before] when
  /// given, at most [limit].
  Future<RunsResponse> listRuns({
    String? projectId,
    String? workflowId,
    RunState? state,
    String? before,
    int? limit,
  }) async => RunsResponse.fromJson(
    await _json(
      await _send(
        'GET',
        ['runs'],
        query: {
          'project': ?projectId,
          'workflow': ?workflowId,
          'state': ?state?.wire,
          'before': ?before,
          'limit': ?limit?.toString(),
        },
      ),
    ),
  );

  /// `GET /runs/{id}`.
  Future<Run> getRun(String id) async =>
      Run.fromJson(await _json(await _send('GET', ['runs', id])));

  /// `POST /runs/{id}/run-again`: a new run of the same version of the
  /// workflow, at the same commit, with the same request.
  Future<Run> runAgain(String id) async =>
      Run.fromJson(await _json(await _send('POST', ['runs', id, 'run-again'])));

  /// `POST /runs/{id}/rerun-failed`: runs the failed jobs of the run again,
  /// each from the step that failed.
  Future<Run> rerunFailed(String id) async => Run.fromJson(
    await _json(await _send('POST', ['runs', id, 'rerun-failed'])),
  );

  /// `POST /runs/{id}/cancel`.
  Future<Run> cancelRun(String id) async =>
      Run.fromJson(await _json(await _send('POST', ['runs', id, 'cancel'])));

  /// `GET /jobs/{id}`.
  Future<Job> getJob(String id) async =>
      Job.fromJson(await _json(await _send('GET', ['jobs', id])));

  /// `POST /jobs/{id}/cancel`.
  Future<Job> cancelJob(String id) async =>
      Job.fromJson(await _json(await _send('POST', ['jobs', id, 'cancel'])));

  /// `POST /jobs/{id}/resume`: goes on at the first unfinished step, or at
  /// [fromStep].
  Future<Job> resumeJob(String id, {int? fromStep}) async => Job.fromJson(
    await _json(
      await _send(
        'POST',
        ['jobs', id, 'resume'],
        body: fromStep == null
            ? null
            : ResumeJobRequest(fromStep: fromStep).toJson(),
      ),
    ),
  );

  /// `GET /jobs/{id}/artifacts`.
  Future<List<Artifact>> listJobArtifacts(String jobId) async =>
      ArtifactsResponse.fromJson(
        await _json(await _send('GET', ['jobs', jobId, 'artifacts'])),
      ).artifacts;

  /// `GET /jobs/{id}/tests`: the test run of a job. [statuses] default to the
  /// failures; [limit] and [offset] page through the tests.
  Future<TestRunResponse> getJobTests(
    String jobId, {
    Set<TestStatus>? statuses,
    int? limit,
    int? offset,
  }) async => TestRunResponse.fromJson(
    await _json(
      await _send(
        'GET',
        ['jobs', jobId, 'tests'],
        query: {
          'status': ?statuses?.map((status) => status.wire).join(','),
          'limit': ?limit?.toString(),
          'offset': ?offset?.toString(),
        },
      ),
    ),
  );

  /// `GET /projects/{id}/tests/baseline`.
  Future<List<TestBaseline>> getTestBaselines(String projectId) async =>
      TestBaselinesResponse.fromJson(
        await _json(
          await _send('GET', ['projects', projectId, 'tests', 'baseline']),
        ),
      ).baselines;

  /// Follows the log of a job: `GET /jobs/{id}/logs`.
  ///
  /// The stream replays the lines after `after` (all of them by default), then
  /// follows the job live, and ends with a [LogEndFrame] once the job has
  /// ended (or is waiting for a resume) and every line was sent. Each line
  /// arrives once and in order: when the connection drops the stream
  /// reconnects from the last line it passed on, and when the client reads too
  /// slowly it reads the lines it missed again. The stream fails with an
  /// [ApiException] when the engine refuses (a job that does not exist, an
  /// `after` beyond the log).
  Stream<LogFrame> followJobLogs(String jobId, {int after = 0}) => LogFeed(
    connect: (cursor) =>
        _openSocket(['jobs', jobId, 'logs'], query: {'after': '$cursor'}),
    after: after,
    delay: _delay,
    initialDelay: reconnectDelay,
    maxDelay: maxReconnectDelay,
  ).stream;

  // ------------------------------------------------------------- artifacts

  /// `GET /artifacts/{id}`.
  Future<Artifact> getArtifact(String id) async =>
      Artifact.fromJson(await _json(await _send('GET', ['artifacts', id])));

  /// `POST /artifacts/{id}/pin`: keeps the artifact when space is freed.
  Future<Artifact> pinArtifact(String id) async => Artifact.fromJson(
    await _json(await _send('POST', ['artifacts', id, 'pin'])),
  );

  /// `POST /artifacts/{id}/unpin`.
  Future<Artifact> unpinArtifact(String id) async => Artifact.fromJson(
    await _json(await _send('POST', ['artifacts', id, 'unpin'])),
  );

  /// `GET /artifacts/{id}/download`: the file, as a stream.
  Future<ArtifactDownload> downloadArtifact(String id) async {
    final response = await _open('GET', ['artifacts', id, 'download']);
    final disposition = response.headers['content-disposition'];
    return ArtifactDownload(
      content: response.stream,
      sha256: response.headers['x-content-sha256']?.toLowerCase(),
      length: response.contentLength,
      fileName: disposition == null ? null : _fileNameOf(disposition),
    );
  }

  // ----------------------------------------------------------- credentials

  /// `GET /credentials`: the named credentials of the engine, with the
  /// flavors that use each.
  Future<List<NamedCredential>> listNamedCredentials() async =>
      NamedCredentialsResponse.fromJson(
        await _json(await _send('GET', ['credentials'])),
      ).credentials;

  /// `GET /credentials/{id}`.
  Future<NamedCredential> getNamedCredential(String id) async =>
      NamedCredential.fromJson(
        await _json(await _send('GET', ['credentials', id])),
      );

  /// `POST /credentials`: verifies a credential and stores it under its
  /// name. No flavor uses it yet.
  Future<NamedCredential> createCredential(
    CreateCredentialRequest request,
  ) async => NamedCredential.fromJson(
    await _json(await _send('POST', ['credentials'], body: request.toJson())),
  );

  /// `PATCH /credentials/{id}`: renames the credential.
  Future<NamedCredential> renameCredential(String id, String name) async =>
      NamedCredential.fromJson(
        await _json(
          await _send('PATCH', [
            'credentials',
            id,
          ], body: RenameCredentialRequest(name).toJson()),
        ),
      );

  /// `PUT /credentials/{id}`: verifies a new secret for the credential and
  /// stores it. The name and the assignments stay.
  Future<NamedCredential> replaceCredentialSecret(
    String id,
    ReplaceCredentialRequest request,
  ) async => NamedCredential.fromJson(
    await _json(
      await _send('PUT', ['credentials', id], body: request.toJson()),
    ),
  );

  /// `POST /credentials/{id}/verify`: checks the credential and its
  /// assignments again.
  Future<NamedCredential> verifyNamedCredential(String id) async =>
      NamedCredential.fromJson(
        await _json(await _send('POST', ['credentials', id, 'verify'])),
      );

  /// `DELETE /credentials/{id}`. Throws an [ApiException] with
  /// `credential_in_use` and the flavors ([ApiException.usedBy]) when
  /// flavors use it, unless [force].
  Future<void> deleteNamedCredential(String id, {bool force = false}) async {
    await _send(
      'DELETE',
      ['credentials', id],
      query: {if (force) 'force': 'true'},
    );
  }

  /// `PUT /projects/{id}/flavors/{flavor}/credentials/{kind}`: the flavor
  /// [flavor] of the app at [app] uses the credential of [request] for
  /// [kind]; every flavor of the app with [AssignCredentialRequest.allFlavors].
  Future<AssignCredentialResponse> assignCredential(
    String projectId, {
    required String flavor,
    required CredentialKind kind,
    required AssignCredentialRequest request,
    String app = '.',
  }) async => AssignCredentialResponse.fromJson(
    await _json(
      await _send(
        'PUT',
        ['projects', projectId, 'flavors', flavor, 'credentials', kind.wire],
        query: {if (app != '.') 'app': app},
        body: request.toJson(),
      ),
    ),
  );

  /// `DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}`: the flavor
  /// stops using its credential of [kind].
  Future<void> unassignCredential(
    String projectId, {
    required String flavor,
    required CredentialKind kind,
    String app = '.',
  }) async {
    await _send(
      'DELETE',
      ['projects', projectId, 'flavors', flavor, 'credentials', kind.wire],
      query: {if (app != '.') 'app': app},
    );
  }

  /// `GET /projects/{id}/credentials`: the credential each flavor uses, of
  /// one [app] or [flavor] if given.
  Future<List<Credential>> listCredentials(
    String projectId, {
    String? app,
    String? flavor,
  }) async => CredentialsResponse.fromJson(
    await _json(
      await _send(
        'GET',
        ['projects', projectId, 'credentials'],
        query: {'app': ?app, 'flavor': ?flavor},
      ),
    ),
  ).credentials;

  /// `PUT /projects/{id}/credentials` (deprecated by the engine; use
  /// [createCredential] and [assignCredential]): verifies a credential and
  /// makes the flavor use it.
  Future<Credential> saveCredential(
    String projectId,
    SaveCredentialRequest request,
  ) async => Credential.fromJson(
    await _json(
      await _send('PUT', [
        'projects',
        projectId,
        'credentials',
      ], body: request.toJson()),
    ),
  );

  /// `POST /projects/{id}/credentials/{credentialId}/verify` (deprecated by
  /// the engine; use [verifyNamedCredential]).
  Future<Credential> verifyCredential(
    String projectId,
    String credentialId,
  ) async => Credential.fromJson(
    await _json(
      await _send('POST', [
        'projects',
        projectId,
        'credentials',
        credentialId,
        'verify',
      ]),
    ),
  );

  /// `DELETE /projects/{id}/credentials/{credentialId}` (deprecated by the
  /// engine; use [unassignCredential] and [deleteNamedCredential]).
  Future<void> deleteCredential(String projectId, String credentialId) async {
    await _send('DELETE', ['projects', projectId, 'credentials', credentialId]);
  }

  // ---------------------------------------------------------- github token

  /// `GET /github-token`: whether the engine has its GitHub token, and who
  /// GitHub says it belongs to.
  Future<GitHubTokenStatus> getGitHubToken() async =>
      GitHubTokenStatus.fromJson(
        await _json(await _send('GET', ['github-token'])),
      );

  /// `PUT /github-token`: checks [token] with GitHub, then stores it.
  Future<GitHubTokenStatus> setGitHubToken(String token) async =>
      GitHubTokenStatus.fromJson(
        await _json(
          await _send('PUT', [
            'github-token',
          ], body: SetGitHubTokenRequest(token).toJson()),
        ),
      );

  /// `POST /github-token/import`: takes the token of the GitHub CLI of the
  /// engine machine.
  Future<GitHubTokenStatus> importGitHubToken() async =>
      GitHubTokenStatus.fromJson(
        await _json(await _send('POST', ['github-token', 'import'])),
      );

  /// `DELETE /github-token`.
  Future<void> deleteGitHubToken() async {
    await _send('DELETE', ['github-token']);
  }

  // ---------------------------------------------------- tokens and doctor

  /// `POST /tokens`: makes a token called [name] for `xp` or `xp mcp`
  /// ([kind]); only an app token may. The answer holds its secret, shown
  /// this once.
  Future<CreatedToken> createToken({
    required String name,
    required DeviceTokenKind kind,
  }) async => CreatedToken.fromJson(
    await _json(
      await _send('POST', [
        'tokens',
      ], body: CreateTokenRequest(name: name, kind: kind).toJson()),
    ),
  );

  /// `GET /status`: the token this client holds, without its secret, and
  /// whether the engine can reach its secrets.
  Future<StatusResponse> status() async =>
      StatusResponse.fromJson(await _json(await _send('GET', ['status'])));

  /// `GET /doctor`: what the engine finds about the machine it runs on.
  Future<DoctorResponse> doctor() async =>
      DoctorResponse.fromJson(await _json(await _send('GET', ['doctor'])));

  // ------------------------------------------------------------- approvals

  /// `GET /approvals`, newest first, of one [projectId] or [state] if given.
  Future<List<Approval>> listApprovals({
    String? projectId,
    ApprovalState? state,
  }) async => ApprovalsResponse.fromJson(
    await _json(
      await _send(
        'GET',
        ['approvals'],
        query: {'project': ?projectId, 'state': ?state?.wire},
      ),
    ),
  ).approvals;

  /// `GET /approvals/{id}`. Any token kind may read it.
  Future<Approval> getApproval(String id) async =>
      Approval.fromJson(await _json(await _send('GET', ['approvals', id])));

  /// `POST /approvals/{id}/approve`. Only `app` and `cli` tokens may; a
  /// decision that lost the race throws an [ApiException] with
  /// [ApiErrorCode.alreadyDecided] and the [ApiException.approval].
  Future<Approval> approve(String id, {String? reason}) =>
      _decide(id, 'approve', reason);

  /// `POST /approvals/{id}/deny`. Like [approve].
  Future<Approval> deny(String id, {String? reason}) =>
      _decide(id, 'deny', reason);

  Future<Approval> _decide(String id, String decision, String? reason) async =>
      Approval.fromJson(
        await _json(
          await _send(
            'POST',
            ['approvals', id, decision],
            body: reason == null
                ? null
                : DecisionRequest(reason: reason).toJson(),
          ),
        ),
      );

  /// `GET /projects/{id}/gates`.
  Future<ProjectGates> getGates(String projectId) async =>
      ProjectGates.fromJson(
        await _json(await _send('GET', ['projects', projectId, 'gates'])),
      );

  /// `PUT /projects/{id}/gates`. Only an `app` token may loosen a gate.
  Future<ProjectGates> setGates(String projectId, ProjectGates gates) async =>
      ProjectGates.fromJson(
        await _json(
          await _send('PUT', [
            'projects',
            projectId,
            'gates',
          ], body: gates.toJson()),
        ),
      );

  // -------------------------------------------------------------- releases

  /// `GET /releases`, newest first, narrowed by [projectId], [app] and
  /// [state] if given.
  Future<List<Release>> listReleases({
    String? projectId,
    String? app,
    ReleaseState? state,
  }) async => ReleasesResponse.fromJson(
    await _json(
      await _send(
        'GET',
        ['releases'],
        query: {'project': ?projectId, 'app': ?app, 'state': ?state?.wire},
      ),
    ),
  ).releases;

  /// `GET /releases/{id}`.
  Future<Release> getRelease(String id) async =>
      Release.fromJson(await _json(await _send('GET', ['releases', id])));

  /// `POST /releases/{id}/refresh`: asks the stores now.
  Future<Release> refreshRelease(String id) async => Release.fromJson(
    await _json(await _send('POST', ['releases', id, 'refresh'])),
  );

  /// `POST /releases/{id}/stores/{store}/status`: says what a store did, by
  /// hand.
  Future<Release> setReleaseStoreStatus(
    String id,
    ReleaseStore store,
    StoreState state,
  ) async => Release.fromJson(
    await _json(
      await _send('POST', [
        'releases',
        id,
        'stores',
        store.wire,
        'status',
      ], body: StoreStatusRequest(state: state).toJson()),
    ),
  );

  /// `POST /releases/{id}/builds`: builds the same version again with a new
  /// build number. Returns the run that does it.
  Future<Run> startReleaseBuild(String id) async => Run.fromJson(
    await _json(await _send('POST', ['releases', id, 'builds'])),
  );

  /// `POST /releases/{id}/merge`: asks to merge the release pull request.
  /// Returns the run that does it.
  Future<Run> mergeRelease(String id) async =>
      Run.fromJson(await _json(await _send('POST', ['releases', id, 'merge'])));

  /// `POST /releases/{id}/rollout`: asks to change the rollout of the release
  /// in a store. Returns the run that does it, which waits for the owner.
  Future<Run> requestRollout(String id, RolloutRequest request) async =>
      Run.fromJson(
        await _json(
          await _send('POST', [
            'releases',
            id,
            'rollout',
          ], body: request.toJson()),
        ),
      );

  /// `GET /releases/{id}/history`: what happened to the release, oldest
  /// first.
  Future<ReleaseHistory> getReleaseHistory(String id) async =>
      ReleaseHistory.fromJson(
        await _json(await _send('GET', ['releases', id, 'history'])),
      );

  /// `PUT /releases/{id}/texts`: the texts the uploads of the release send.
  Future<Release> setReleaseTexts(String id, ReleaseTexts texts) async =>
      Release.fromJson(
        await _json(
          await _send('PUT', ['releases', id, 'texts'], body: texts.toJson()),
        ),
      );

  /// `POST /releases/{id}/patches/{number}/{action}`: asks to promote or roll
  /// back a Shorebird patch of the release. Returns the run that does it,
  /// which waits for the owner.
  Future<Run> moveReleasePatch(
    String id,
    int number,
    PatchAction action,
  ) async => Run.fromJson(
    await _json(
      await _send('POST', ['releases', id, 'patches', '$number', action.wire]),
    ),
  );

  /// `POST /releases/{id}/abandon`.
  Future<Release> abandonRelease(String id, {String? reason}) async =>
      Release.fromJson(
        await _json(
          await _send(
            'POST',
            ['releases', id, 'abandon'],
            body: reason == null
                ? null
                : AbandonRequest(reason: reason).toJson(),
          ),
        ),
      );

  /// `GET /releases/{id}/notes`.
  Future<ReleaseNotes> getReleaseNotes(String id) async =>
      ReleaseNotes.fromJson(
        await _json(await _send('GET', ['releases', id, 'notes'])),
      );

  // --------------------------------------------------------------- storage

  /// `GET /storage`.
  Future<StorageReport> getStorage() async =>
      StorageReport.fromJson(await _json(await _send('GET', ['storage'])));

  /// `POST /storage/free`: frees space, or only says how much would be freed
  /// (the default of [FreeSpaceRequest]).
  Future<FreeSpaceResult> freeStorage(FreeSpaceRequest request) async =>
      FreeSpaceResult.fromJson(
        await _json(
          await _send('POST', ['storage', 'free'], body: request.toJson()),
        ),
      );

  /// `GET /storage/retention`.
  Future<RetentionSettings> getRetention() async => RetentionSettings.fromJson(
    await _json(await _send('GET', ['storage', 'retention'])),
  );

  /// `PUT /storage/retention`. Only `app` and `cli` tokens may.
  Future<RetentionSettings> setRetention(RetentionSettings settings) async =>
      RetentionSettings.fromJson(
        await _json(
          await _send('PUT', ['storage', 'retention'], body: settings.toJson()),
        ),
      );

  // --------------------------------------------------------------- runners

  /// `GET /runners`: every runner, oldest first, revoked ones included.
  Future<List<Runner>> listRunners() async =>
      RunnersResponse.fromJson(await _json(await _send('GET', ['runners'])))
          .runners;

  /// `POST /runners/pairing-tokens`: makes a pairing token for a runner called
  /// [name]. Single use, valid for 15 minutes; shown once. Only `app` and `cli`
  /// tokens may.
  Future<PairingToken> createPairingToken(String name) async =>
      PairingToken.fromJson(
        await _json(
          await _send('POST', [
            'runners',
            'pairing-tokens',
          ], body: CreatePairingTokenRequest(name: name).toJson()),
        ),
      );

  /// `GET /settings/runner-url`: the address runners reach the engine at.
  Future<RunnerUrl> runnerUrl() async => RunnerUrl.fromJson(
    await _json(await _send('GET', ['settings', 'runner-url'])),
  );

  /// `PUT /settings/runner-url`: sets the runner URL to [url], or clears it
  /// for `null`. Only `app` and `cli` tokens may.
  Future<RunnerUrl> setRunnerUrl(String? url) async => RunnerUrl.fromJson(
    await _json(
      await _send('PUT', [
        'settings',
        'runner-url',
      ], body: SetRunnerUrlRequest(url: url).toJson()),
    ),
  );

  /// `POST /runners/pair`: exchanges the pairing token [pairingToken] for the
  /// runner and its credential. Needs no token, so this client's token is not
  /// sent.
  Future<PairRunnerResponse> pairRunner(String pairingToken) async =>
      PairRunnerResponse.fromJson(
        await _json(
          await _send(
            'POST',
            ['runners', 'pair'],
            body: PairRunnerRequest(pairingToken: pairingToken).toJson(),
            authenticated: false,
          ),
        ),
      );

  /// `POST /runners/{id}/revoke`. Only `app` and `cli` tokens may.
  Future<Runner> revokeRunner(String id) async => Runner.fromJson(
    await _json(await _send('POST', ['runners', id, 'revoke'])),
  );

  /// Opens the connection of a runner: `GET /runners/connect`. This client's
  /// token must be the runner's credential. The caller speaks the frames of
  /// the protocol (`RunnerFrame`, `EngineFrame`) over the channel and
  /// reconnects when it drops; a refusal is an [ApiException].
  Future<WebSocketChannel> connectRunner() =>
      _openSocket(['runners', 'connect']);

  /// `GET /runners/bundle`: the `xp` bundle of the engine's own version for a
  /// runner of [os] and [arch], as a `.tar.gz`. This client's token must be the
  /// runner's credential. The download carries the SHA-256 and the size the
  /// engine announced; [ArtifactDownload.saveTo] checks the file against them.
  /// Throws an [ApiException] when the engine has no bundle for the machine
  /// (`404`).
  Future<ArtifactDownload> downloadRunnerBundle({
    required String os,
    required String arch,
  }) async {
    final response = await _open(
      'GET',
      ['runners', 'bundle'],
      query: {'os': os, 'arch': arch},
    );
    return ArtifactDownload(
      content: response.stream,
      sha256: response.headers['x-content-sha256']?.toLowerCase(),
      length: response.contentLength,
    );
  }

  /// `PUT /runners/jobs/{id}/artifacts/{name}`: uploads a file a leased job
  /// produced. [size] and [sha256] declare what [content] is; the engine
  /// stores the file only if the bytes are what was declared, so a connection
  /// that breaks halfway leaves nothing behind. Throws an [ApiException] when
  /// it refuses (the lease is not held, the digest is wrong).
  Future<Artifact> uploadRunnerArtifact({
    required String jobId,
    required String name,
    required String leaseId,
    required ArtifactKind kind,
    required Stream<List<int>> content,
    required int size,
    required String sha256,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final request =
        http.StreamedRequest(
            'PUT',
            _uri(
              ['runners', 'jobs', jobId, 'artifacts', name],
              {'kind': kind.wire},
            ),
          )
          ..headers.addAll(_headers(authenticated: true))
          ..headers['x-content-sha256'] = sha256
          ..headers['x-lease-id'] = leaseId
          ..headers[HttpHeaders.contentTypeHeader] = 'application/octet-stream'
          ..contentLength = size;
    // The body is sent as it is read, as fast as the engine takes it. A source
    // that fails ends the request with that failure; a request the engine
    // already answered has no body to feed any more.
    unawaited(_feed(request.sink, content).catchError((Object _) {}));
    final response = await _dispatch(request, timeout: timeout);
    return Artifact.fromJson(await _json(await _collect(response)));
  }

  // ---------------------------------------------------------------- events

  /// Watches the engine's events: `GET /events`.
  ///
  /// With [after], the stream first replays the events after that `seq`; a
  /// listener that keeps the `seq` of the last event it handled resumes from
  /// there. The first item of every connection is the [StreamOpened] event.
  ///
  /// The stream reconnects by itself, with a growing delay, when the
  /// connection drops, and resumes from the last event it passed on, so the
  /// listener sees each event once and in order. When the engine cannot resume
  /// (`409 resync_required`, or the close code 4409: the cursor left the
  /// engine's window, or the engine restarted) the stream emits an
  /// [EventsResyncRequired], reconnects without a cursor and carries on with
  /// live events; the listener must reload its state. It ends with an error
  /// when the engine refuses the token ([ApiException]) and when the listener
  /// cancels.
  Stream<EventStreamItem> watchEvents({int? after}) => EventFeed(
    connect: (cursor) =>
        _openSocket(['events'], query: {'after': ?cursor?.toString()}),
    after: after,
    delay: _delay,
    initialDelay: reconnectDelay,
    maxDelay: maxReconnectDelay,
  ).stream;

  // ------------------------------------------------------------- transport

  Uri _uri(List<String> segments, Map<String, String> query) {
    final prefix = baseUrl.pathSegments.where((segment) => segment.isNotEmpty);
    return baseUrl.replace(
      pathSegments: [...prefix, ...segments],
      queryParameters: query.isEmpty ? null : query,
    );
  }

  Map<String, String> _headers({required bool authenticated}) => {
    HttpHeaders.userAgentHeader: clientUserAgent(),
    HttpHeaders.acceptHeader: 'application/json',
    if (authenticated) HttpHeaders.authorizationHeader: 'Bearer $token',
  };

  Future<WebSocketChannel> _openSocket(
    List<String> segments, {
    Map<String, String> query = const {},
  }) {
    final uri = _uri(segments, query);
    return _connector(
      uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws'),
      _headers(authenticated: true),
    );
  }

  Future<http.Response> _send(
    String method,
    List<String> segments, {
    Map<String, String> query = const {},
    Object? body,
    bool authenticated = true,
  }) async {
    final streamed = await _open(
      method,
      segments,
      query: query,
      body: body,
      authenticated: authenticated,
    );
    return await _collect(streamed);
  }

  Future<http.Response> _collect(http.StreamedResponse streamed) async {
    try {
      return await http.Response.fromStream(streamed);
    } on Object catch (error) {
      throw ConnectionException(
        'The connection to the engine broke: $error',
        cause: error,
      );
    }
  }

  /// Sends the request and returns the response if it is a 2xx; any other
  /// answer becomes an [ApiException].
  Future<http.StreamedResponse> _open(
    String method,
    List<String> segments, {
    Map<String, String> query = const {},
    Object? body,
    bool authenticated = true,
  }) async {
    final request = http.Request(method, _uri(segments, query))
      ..headers.addAll(_headers(authenticated: authenticated));
    if (body != null) {
      request
        ..headers[HttpHeaders.contentTypeHeader] = 'application/json'
        ..body = jsonEncode(body);
    }
    return await _dispatch(request);
  }

  Future<http.StreamedResponse> _dispatch(
    http.BaseRequest request, {
    Duration? timeout,
  }) async {
    final limit = timeout ?? requestTimeout;
    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(limit);
    } on TimeoutException catch (error) {
      throw ConnectionException(
        'The engine did not answer within ${limit.inSeconds} s.',
        cause: error,
      );
    } on Object catch (error) {
      throw ConnectionException(
        'Cannot reach the engine at $baseUrl. Is xpd running? Its health is '
        'at ${_uri(const ['health'], const {})}.',
        cause: error,
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    final failed = await _collect(response);
    throw ApiException.fromResponse(
      failed.statusCode,
      utf8.decode(failed.bodyBytes, allowMalformed: true),
    );
  }

  Future<Map<String, dynamic>> _json(http.Response response) async {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on Object catch (error) {
      throw ConnectionException(
        'The answer of the engine is not what XPath expects: $error',
        cause: error,
      );
    }
  }

  static String? _fileNameOf(String disposition) {
    final match = RegExp('filename="?([^";]+)"?').firstMatch(disposition);
    return match?.group(1);
  }
}

/// Sends [content] into the body of a request, and ends it.
Future<void> _feed(
  StreamSink<List<int>> sink,
  Stream<List<int>> content,
) async {
  try {
    await sink.addStream(content);
  } finally {
    await sink.close();
  }
}
