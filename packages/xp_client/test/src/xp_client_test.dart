import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../helpers/fake_engine.dart';
import '../helpers/samples.dart' as sample;

/// One endpoint: what the client sends and what it makes of the answer.
class _Endpoint {
  const new(
    this.name, {
    required this.method,
    required this.path,
    required this.call,
    required this.response,
    required this.expected,
    this.status = 200,
    this.query = const {},
    this.body,
  });

  final String name;
  final String method;
  final String path;
  final int status;
  final Object? response;
  final Future<Object?> Function(XpClient client) call;
  final Object? expected;
  final Map<String, String> query;
  final Map<String, dynamic>? body;
}

final _createdToken = CreatedToken(
  info: TokenInfo(
    id: 'tok_1',
    name: 'xp',
    kind: DeviceTokenKind.cli,
    createdAt: DateTime.utc(2026, 10, 25),
  ),
  token: 'xpt_x',
);

void main() {
  late FakeEngine engine;
  late XpClient client;

  setUp(() async {
    engine = await FakeEngine.start();
    client = XpClient(baseUrl: engine.url, token: 'xp_secret');
  });

  tearDown(() async {
    client.close();
    await engine.close();
  });

  final endpoints = <_Endpoint>[
    _Endpoint(
      'listProjects',
      method: 'GET',
      path: '/projects',
      response: const ProjectsResponse([sample.project]).toJson(),
      call: (client) => client.listProjects(),
      expected: const [sample.project],
    ),
    _Endpoint(
      'getProject',
      method: 'GET',
      path: '/projects/prj_1',
      response: sample.project.toJson(),
      call: (client) => client.getProject('prj_1'),
      expected: sample.project,
    ),
    _Endpoint(
      'addProject',
      method: 'POST',
      path: '/projects',
      status: 201,
      response: sample.project.toJson(),
      call: (client) =>
          client.addProject(const AddProjectRequest(remote: 'acme/app')),
      expected: sample.project,
      body: {'remote': 'acme/app'},
    ),
    _Endpoint(
      'scanProject',
      method: 'POST',
      path: '/projects/prj_1/scan',
      response: sample.project.toJson(),
      call: (client) => client.scanProject('prj_1'),
      expected: sample.project,
    ),
    _Endpoint(
      'updateProject',
      method: 'PATCH',
      path: '/projects/prj_1',
      response: sample.project.toJson(),
      call: (client) => client.updateProject(
        'prj_1',
        const ProfileEdits(defaultBaseBranch: 'develop'),
      ),
      expected: sample.project,
      body: const ProfileEdits(defaultBaseBranch: 'develop').toJson(),
    ),
    _Endpoint(
      'removeProject',
      method: 'DELETE',
      path: '/projects/prj_1',
      status: 204,
      response: null,
      call: (client) async {
        await client.removeProject('prj_1');
        return 'removed';
      },
      expected: 'removed',
    ),
    _Endpoint(
      'runAgain',
      method: 'POST',
      path: '/runs/run_1/run-again',
      status: 202,
      response: sample.run.toJson(),
      call: (client) => client.runAgain('run_1'),
      expected: sample.run,
    ),
    _Endpoint(
      'rerunFailed',
      method: 'POST',
      path: '/runs/run_1/rerun-failed',
      response: sample.run.toJson(),
      call: (client) => client.rerunFailed('run_1'),
      expected: sample.run,
    ),
    _Endpoint(
      'listRuns',
      method: 'GET',
      path: '/runs',
      query: {
        'project': 'prj_1',
        'workflow': 'wf_1',
        'state': 'failed',
        'before': 'run_9',
        'limit': '5',
      },
      response: const RunsResponse([]).toJson(),
      call: (client) => client.listRuns(
        projectId: 'prj_1',
        workflowId: 'wf_1',
        state: RunState.failed,
        before: 'run_9',
        limit: 5,
      ),
      expected: const RunsResponse([]),
    ),
    _Endpoint(
      'listWorkflowTemplates',
      method: 'GET',
      path: '/workflows/templates',
      response: const WorkflowTemplatesResponse([
        WorkflowTemplate(
          id: 'blank',
          title: 'Blank',
          description: 'One job.',
          yaml: 'schema: 1\n',
        ),
      ]).toJson(),
      call: (client) => client.listWorkflowTemplates(),
      expected: const [
        WorkflowTemplate(
          id: 'blank',
          title: 'Blank',
          description: 'One job.',
          yaml: 'schema: 1\n',
        ),
      ],
    ),
    _Endpoint(
      'getWorkflowSchema',
      method: 'GET',
      path: '/workflows/schema',
      response: const WorkflowSchema(
        schema: 1,
        steps: [StepType(kind: 'test')],
        gates: ['push'],
        capabilities: ['flutter'],
        matrixAxes: ['platform'],
        platforms: ['android'],
      ).toJson(),
      call: (client) => client.getWorkflowSchema(),
      expected: const WorkflowSchema(
        schema: 1,
        steps: [StepType(kind: 'test')],
        gates: ['push'],
        capabilities: ['flutter'],
        matrixAxes: ['platform'],
        platforms: ['android'],
      ),
    ),
    _Endpoint(
      'listWorkflows',
      method: 'GET',
      path: '/projects/prj_1/workflows',
      response: WorkflowsResponse([sample.workflowSummary]).toJson(),
      call: (client) => client.listWorkflows('prj_1'),
      expected: [sample.workflowSummary],
    ),
    _Endpoint(
      'getWorkflow',
      method: 'GET',
      path: '/projects/prj_1/workflows/wf_1',
      response: sample.workflow.toJson(),
      call: (client) => client.getWorkflow('prj_1', 'wf_1'),
      expected: sample.workflow,
    ),
    _Endpoint(
      'getWorkflow at a version',
      method: 'GET',
      path: '/projects/prj_1/workflows/wf_1',
      query: {'version': '2'},
      response: sample.workflow.toJson(),
      call: (client) => client.getWorkflow('prj_1', 'wf_1', version: 2),
      expected: sample.workflow,
    ),
    _Endpoint(
      'createWorkflow',
      method: 'POST',
      path: '/projects/prj_1/workflows',
      status: 201,
      response: sample.workflow.toJson(),
      call: (client) => client.createWorkflow(
        'prj_1',
        const CreateWorkflowRequest(name: 'dev-build', yaml: 'name: x\n'),
      ),
      expected: sample.workflow,
      body: {'name': 'dev-build', 'yaml': 'name: x\n'},
    ),
    _Endpoint(
      'validateWorkflow',
      method: 'POST',
      path: '/projects/prj_1/workflows/validate',
      response: const ValidateWorkflowResponse(
        valid: false,
        issues: [WorkflowIssue(line: 2, column: 3, message: 'bad')],
      ).toJson(),
      call: (client) => client.validateWorkflow('prj_1', 'name: x\n'),
      expected: const ValidateWorkflowResponse(
        valid: false,
        issues: [WorkflowIssue(line: 2, column: 3, message: 'bad')],
      ),
      body: {'yaml': 'name: x\n'},
    ),
    _Endpoint(
      'validateWorkflow without a project',
      method: 'POST',
      path: '/workflows/validate',
      response: const ValidateWorkflowResponse(valid: true).toJson(),
      call: (client) => client.validateWorkflow(null, 'name: x\n'),
      expected: const ValidateWorkflowResponse(valid: true),
      body: {'yaml': 'name: x\n'},
    ),
    _Endpoint(
      'saveWorkflow',
      method: 'PUT',
      path: '/projects/prj_1/workflows/wf_1',
      response: sample.workflow.toJson(),
      call: (client) => client.saveWorkflow('prj_1', 'wf_1', 'name: y\n'),
      expected: sample.workflow,
      body: {'yaml': 'name: y\n'},
    ),
    _Endpoint(
      'updateWorkflow',
      method: 'PATCH',
      path: '/projects/prj_1/workflows/wf_1',
      response: sample.workflow.toJson(),
      call: (client) => client.updateWorkflow(
        'prj_1',
        'wf_1',
        const UpdateWorkflowRequest(archived: true),
      ),
      expected: sample.workflow,
      body: {'archived': true},
    ),
    _Endpoint(
      'deleteWorkflow',
      method: 'DELETE',
      path: '/projects/prj_1/workflows/wf_1',
      status: 204,
      response: null,
      call: (client) async {
        await client.deleteWorkflow('prj_1', 'wf_1');
        return 'deleted';
      },
      expected: 'deleted',
    ),
    _Endpoint(
      'dispatchWorkflow',
      method: 'POST',
      path: '/projects/prj_1/workflows/wf_1/dispatch',
      status: 202,
      response: sample.run.toJson(),
      call: (client) => client.dispatchWorkflow(
        'prj_1',
        'wf_1',
        const DispatchRequest(flavors: ['prod'], bump: VersionBump.patch),
      ),
      expected: sample.run,
      body: const DispatchRequest(
        flavors: ['prod'],
        bump: VersionBump.patch,
      ).toJson(),
    ),
    _Endpoint(
      'planDispatch',
      method: 'POST',
      path: '/projects/prj_1/workflows/wf_1/dispatch',
      query: {'dryRun': 'true'},
      response: const DispatchPlan(
        flavors: ['prod'],
        platforms: ['ios'],
        build: 46,
      ).toJson(),
      call: (client) => client.planDispatch(
        'prj_1',
        'wf_1',
        const DispatchRequest(flavors: ['prod']),
      ),
      expected: const DispatchPlan(
        flavors: ['prod'],
        platforms: ['ios'],
        build: 46,
      ),
      body: const DispatchRequest(flavors: ['prod']).toJson(),
    ),
    _Endpoint(
      'getRun',
      method: 'GET',
      path: '/runs/run_1',
      response: sample.run.toJson(),
      call: (client) => client.getRun('run_1'),
      expected: sample.run,
    ),
    _Endpoint(
      'cancelRun',
      method: 'POST',
      path: '/runs/run_1/cancel',
      response: sample.run.toJson(),
      call: (client) => client.cancelRun('run_1'),
      expected: sample.run,
    ),
    _Endpoint(
      'getJob',
      method: 'GET',
      path: '/jobs/job_1',
      response: sample.job.toJson(),
      call: (client) => client.getJob('job_1'),
      expected: sample.job,
    ),
    _Endpoint(
      'cancelJob',
      method: 'POST',
      path: '/jobs/job_1/cancel',
      response: sample.job.toJson(),
      call: (client) => client.cancelJob('job_1'),
      expected: sample.job,
    ),
    _Endpoint(
      'resumeJob',
      method: 'POST',
      path: '/jobs/job_1/resume',
      status: 202,
      response: sample.job.toJson(),
      call: (client) => client.resumeJob('job_1'),
      expected: sample.job,
    ),
    _Endpoint(
      'resumeJob from a step',
      method: 'POST',
      path: '/jobs/job_1/resume',
      status: 202,
      response: sample.job.toJson(),
      call: (client) => client.resumeJob('job_1', fromStep: 3),
      expected: sample.job,
      body: {'fromStep': 3},
    ),
    _Endpoint(
      'listJobArtifacts',
      method: 'GET',
      path: '/jobs/job_1/artifacts',
      response: ArtifactsResponse([sample.artifact]).toJson(),
      call: (client) => client.listJobArtifacts('job_1'),
      expected: [sample.artifact],
    ),
    _Endpoint(
      'getJobTests',
      method: 'GET',
      path: '/jobs/job_1/tests',
      response: sample.testRunResponse.toJson(),
      call: (client) => client.getJobTests('job_1'),
      expected: sample.testRunResponse,
    ),
    _Endpoint(
      'getJobTests narrowed',
      method: 'GET',
      path: '/jobs/job_1/tests',
      query: {'status': 'failed,errored', 'limit': '10', 'offset': '20'},
      response: sample.testRunResponse.toJson(),
      call: (client) => client.getJobTests(
        'job_1',
        statuses: {TestStatus.failed, TestStatus.errored},
        limit: 10,
        offset: 20,
      ),
      expected: sample.testRunResponse,
    ),
    _Endpoint(
      'getTestBaselines',
      method: 'GET',
      path: '/projects/prj_1/tests/baseline',
      response: TestBaselinesResponse([sample.testBaseline]).toJson(),
      call: (client) => client.getTestBaselines('prj_1'),
      expected: [sample.testBaseline],
    ),
    _Endpoint(
      'getArtifact',
      method: 'GET',
      path: '/artifacts/art_1',
      response: sample.artifact.toJson(),
      call: (client) => client.getArtifact('art_1'),
      expected: sample.artifact,
    ),
    _Endpoint(
      'pinArtifact',
      method: 'POST',
      path: '/artifacts/art_1/pin',
      response: sample.artifact.toJson(),
      call: (client) => client.pinArtifact('art_1'),
      expected: sample.artifact,
    ),
    _Endpoint(
      'unpinArtifact',
      method: 'POST',
      path: '/artifacts/art_1/unpin',
      response: sample.artifact.toJson(),
      call: (client) => client.unpinArtifact('art_1'),
      expected: sample.artifact,
    ),
    _Endpoint(
      'listNamedCredentials',
      method: 'GET',
      path: '/credentials',
      response: const NamedCredentialsResponse([sample.namedCredential])
          .toJson(),
      call: (client) => client.listNamedCredentials(),
      expected: const [sample.namedCredential],
    ),
    _Endpoint(
      'getNamedCredential',
      method: 'GET',
      path: '/credentials/crd_1',
      response: sample.namedCredential.toJson(),
      call: (client) => client.getNamedCredential('crd_1'),
      expected: sample.namedCredential,
    ),
    _Endpoint(
      'createCredential',
      method: 'POST',
      path: '/credentials',
      status: 201,
      response: sample.namedCredential.toJson(),
      call: (client) => client.createCredential(
        const CreateCredentialRequest(
          name: 'Play publisher',
          kind: CredentialKind.playSa,
          material: {'serviceAccount': '{}'},
        ),
      ),
      expected: sample.namedCredential,
      body: {
        'name': 'Play publisher',
        'kind': 'play_sa',
        'serviceAccount': '{}',
      },
    ),
    _Endpoint(
      'renameCredential',
      method: 'PATCH',
      path: '/credentials/crd_1',
      response: sample.namedCredential.toJson(),
      call: (client) => client.renameCredential('crd_1', 'Play publisher'),
      expected: sample.namedCredential,
      body: {'name': 'Play publisher'},
    ),
    _Endpoint(
      'replaceCredentialSecret',
      method: 'PUT',
      path: '/credentials/crd_1',
      response: sample.namedCredential.toJson(),
      call: (client) => client.replaceCredentialSecret(
        'crd_1',
        const ReplaceCredentialRequest({'serviceAccount': '{}'}),
      ),
      expected: sample.namedCredential,
      body: {'serviceAccount': '{}'},
    ),
    _Endpoint(
      'verifyNamedCredential',
      method: 'POST',
      path: '/credentials/crd_1/verify',
      response: sample.namedCredential.toJson(),
      call: (client) => client.verifyNamedCredential('crd_1'),
      expected: sample.namedCredential,
    ),
    _Endpoint(
      'deleteNamedCredential',
      method: 'DELETE',
      path: '/credentials/crd_1',
      status: 204,
      response: null,
      call: (client) async {
        await client.deleteNamedCredential('crd_1');
        return 'deleted';
      },
      expected: 'deleted',
    ),
    _Endpoint(
      'deleteNamedCredential with force',
      method: 'DELETE',
      path: '/credentials/crd_1',
      query: {'force': 'true'},
      status: 204,
      response: null,
      call: (client) async {
        await client.deleteNamedCredential('crd_1', force: true);
        return 'deleted';
      },
      expected: 'deleted',
    ),
    _Endpoint(
      'assignCredential',
      method: 'PUT',
      path: '/projects/prj_1/flavors/prod/credentials/play_sa',
      response: const AssignCredentialResponse(assigned: [sample.credential])
          .toJson(),
      call: (client) => client.assignCredential(
        'prj_1',
        flavor: 'prod',
        kind: CredentialKind.playSa,
        request: const AssignCredentialRequest(credentialId: 'crd_1'),
      ),
      expected: const AssignCredentialResponse(assigned: [sample.credential]),
      body: {'credentialId': 'crd_1', 'allFlavors': false, 'replace': false},
    ),
    _Endpoint(
      'assignCredential of an app below the root',
      method: 'PUT',
      path: '/projects/prj_1/flavors/prod/credentials/play_sa',
      query: {'app': 'apps/shop'},
      response: const AssignCredentialResponse(assigned: [sample.credential])
          .toJson(),
      call: (client) => client.assignCredential(
        'prj_1',
        app: 'apps/shop',
        flavor: 'prod',
        kind: CredentialKind.playSa,
        request: const AssignCredentialRequest(
          credentialId: 'crd_1',
          allFlavors: true,
        ),
      ),
      expected: const AssignCredentialResponse(assigned: [sample.credential]),
      body: {'credentialId': 'crd_1', 'allFlavors': true, 'replace': false},
    ),
    _Endpoint(
      'unassignCredential',
      method: 'DELETE',
      path: '/projects/prj_1/flavors/prod/credentials/play_sa',
      status: 204,
      response: null,
      call: (client) async {
        await client.unassignCredential(
          'prj_1',
          flavor: 'prod',
          kind: CredentialKind.playSa,
        );
        return 'unassigned';
      },
      expected: 'unassigned',
    ),
    _Endpoint(
      'unassignCredential of an app below the root',
      method: 'DELETE',
      path: '/projects/prj_1/flavors/prod/credentials/play_sa',
      query: {'app': 'apps/shop'},
      status: 204,
      response: null,
      call: (client) async {
        await client.unassignCredential(
          'prj_1',
          app: 'apps/shop',
          flavor: 'prod',
          kind: CredentialKind.playSa,
        );
        return 'unassigned';
      },
      expected: 'unassigned',
    ),
    _Endpoint(
      'listCredentials',
      method: 'GET',
      path: '/projects/prj_1/credentials',
      response: const CredentialsResponse([sample.credential]).toJson(),
      call: (client) => client.listCredentials('prj_1'),
      expected: const [sample.credential],
    ),
    _Endpoint(
      'listCredentials of a flavor',
      method: 'GET',
      path: '/projects/prj_1/credentials',
      query: {'app': '.', 'flavor': 'prod'},
      response: const CredentialsResponse([sample.credential]).toJson(),
      call: (client) =>
          client.listCredentials('prj_1', app: '.', flavor: 'prod'),
      expected: const [sample.credential],
    ),
    _Endpoint(
      'saveCredential',
      method: 'PUT',
      path: '/projects/prj_1/credentials',
      status: 201,
      response: sample.credential.toJson(),
      call: (client) => client.saveCredential(
        'prj_1',
        const SaveCredentialRequest(
          flavor: 'prod',
          kind: CredentialKind.shorebird,
          material: {'apiKey': 'sb_api_x'},
        ),
      ),
      expected: sample.credential,
      body: {
        'app': '.',
        'flavor': 'prod',
        'kind': 'shorebird',
        'apiKey': 'sb_api_x',
      },
    ),
    _Endpoint(
      'verifyCredential',
      method: 'POST',
      path: '/projects/prj_1/credentials/crd_1/verify',
      response: sample.credential.toJson(),
      call: (client) => client.verifyCredential('prj_1', 'crd_1'),
      expected: sample.credential,
    ),
    _Endpoint(
      'deleteCredential',
      method: 'DELETE',
      path: '/projects/prj_1/credentials/crd_1',
      status: 204,
      response: null,
      call: (client) async {
        await client.deleteCredential('prj_1', 'crd_1');
        return 'deleted';
      },
      expected: 'deleted',
    ),
    _Endpoint(
      'getGitHubToken',
      method: 'GET',
      path: '/github-token',
      response: const GitHubTokenStatus(stored: false).toJson(),
      call: (client) => client.getGitHubToken(),
      expected: const GitHubTokenStatus(stored: false),
    ),
    _Endpoint(
      'setGitHubToken',
      method: 'PUT',
      path: '/github-token',
      response: const GitHubTokenStatus(stored: true, login: 'octo').toJson(),
      call: (client) => client.setGitHubToken('ghp_x'),
      expected: const GitHubTokenStatus(stored: true, login: 'octo'),
      body: const SetGitHubTokenRequest('ghp_x').toJson(),
    ),
    _Endpoint(
      'importGitHubToken',
      method: 'POST',
      path: '/github-token/import',
      response: const GitHubTokenStatus(stored: true).toJson(),
      call: (client) => client.importGitHubToken(),
      expected: const GitHubTokenStatus(stored: true),
    ),
    _Endpoint(
      'deleteGitHubToken',
      method: 'DELETE',
      path: '/github-token',
      status: 204,
      response: null,
      call: (client) async {
        await client.deleteGitHubToken();
        return 'deleted';
      },
      expected: 'deleted',
    ),
    _Endpoint(
      'createToken',
      method: 'POST',
      path: '/tokens',
      status: 201,
      response: _createdToken.toJson(),
      call: (client) =>
          client.createToken(name: 'xp', kind: DeviceTokenKind.cli),
      expected: _createdToken,
      body: const CreateTokenRequest(
        name: 'xp',
        kind: DeviceTokenKind.cli,
      ).toJson(),
    ),
    _Endpoint(
      'status',
      method: 'GET',
      path: '/status',
      response: StatusResponse(
        token: _createdToken.info,
        secretsLocked: false,
      ).toJson(),
      call: (client) => client.status(),
      expected: StatusResponse(token: _createdToken.info, secretsLocked: false),
    ),
    _Endpoint(
      'doctor',
      method: 'GET',
      path: '/doctor',
      response: const DoctorResponse([
        EngineCheck(name: 'flutter', state: CheckState.ok),
      ]).toJson(),
      call: (client) => client.doctor(),
      expected: const DoctorResponse([
        EngineCheck(name: 'flutter', state: CheckState.ok),
      ]),
    ),
    _Endpoint(
      'listApprovals',
      method: 'GET',
      path: '/approvals',
      response: ApprovalsResponse([sample.approval]).toJson(),
      call: (client) => client.listApprovals(),
      expected: [sample.approval],
    ),
    _Endpoint(
      'listApprovals narrowed',
      method: 'GET',
      path: '/approvals',
      query: {'project': 'prj_1', 'state': 'pending'},
      response: ApprovalsResponse([sample.approval]).toJson(),
      call: (client) => client.listApprovals(
        projectId: 'prj_1',
        state: ApprovalState.pending,
      ),
      expected: [sample.approval],
    ),
    _Endpoint(
      'getApproval',
      method: 'GET',
      path: '/approvals/apr_1',
      response: sample.approval.toJson(),
      call: (client) => client.getApproval('apr_1'),
      expected: sample.approval,
    ),
    _Endpoint(
      'approve',
      method: 'POST',
      path: '/approvals/apr_1/approve',
      response: sample.approval.toJson(),
      call: (client) => client.approve('apr_1'),
      expected: sample.approval,
    ),
    _Endpoint(
      'approve with a reason',
      method: 'POST',
      path: '/approvals/apr_1/approve',
      response: sample.approval.toJson(),
      call: (client) => client.approve('apr_1', reason: 'looks good'),
      expected: sample.approval,
      body: {'reason': 'looks good'},
    ),
    _Endpoint(
      'deny',
      method: 'POST',
      path: '/approvals/apr_1/deny',
      response: sample.approval.toJson(),
      call: (client) => client.deny('apr_1', reason: 'wrong build'),
      expected: sample.approval,
      body: {'reason': 'wrong build'},
    ),
    _Endpoint(
      'getGates',
      method: 'GET',
      path: '/projects/prj_1/gates',
      response: const ProjectGates({'push': true}).toJson(),
      call: (client) => client.getGates('prj_1'),
      expected: const ProjectGates({'push': true}),
    ),
    _Endpoint(
      'setGates',
      method: 'PUT',
      path: '/projects/prj_1/gates',
      response: const ProjectGates({'push': true}).toJson(),
      call: (client) =>
          client.setGates('prj_1', const ProjectGates({'push': true})),
      expected: const ProjectGates({'push': true}),
      body: {
        'gates': {'push': true},
      },
    ),
    _Endpoint(
      'listReleases',
      method: 'GET',
      path: '/releases',
      response: ReleasesResponse([sample.release]).toJson(),
      call: (client) => client.listReleases(),
      expected: [sample.release],
    ),
    _Endpoint(
      'listReleases narrowed',
      method: 'GET',
      path: '/releases',
      query: {'project': 'prj_1', 'app': '.', 'state': 'in_review'},
      response: ReleasesResponse([sample.release]).toJson(),
      call: (client) => client.listReleases(
        projectId: 'prj_1',
        app: '.',
        state: ReleaseState.inReview,
      ),
      expected: [sample.release],
    ),
    _Endpoint(
      'getRelease',
      method: 'GET',
      path: '/releases/rel_1',
      response: sample.release.toJson(),
      call: (client) => client.getRelease('rel_1'),
      expected: sample.release,
    ),
    _Endpoint(
      'refreshRelease',
      method: 'POST',
      path: '/releases/rel_1/refresh',
      response: sample.release.toJson(),
      call: (client) => client.refreshRelease('rel_1'),
      expected: sample.release,
    ),
    _Endpoint(
      'setReleaseStoreStatus',
      method: 'POST',
      path: '/releases/rel_1/stores/apple/status',
      response: sample.release.toJson(),
      call: (client) => client.setReleaseStoreStatus(
        'rel_1',
        ReleaseStore.apple,
        StoreState.approved,
      ),
      expected: sample.release,
      body: {'state': 'approved'},
    ),
    _Endpoint(
      'startReleaseBuild',
      method: 'POST',
      path: '/releases/rel_1/builds',
      status: 202,
      response: sample.run.toJson(),
      call: (client) => client.startReleaseBuild('rel_1'),
      expected: sample.run,
    ),
    _Endpoint(
      'mergeRelease',
      method: 'POST',
      path: '/releases/rel_1/merge',
      status: 202,
      response: sample.run.toJson(),
      call: (client) => client.mergeRelease('rel_1'),
      expected: sample.run,
    ),
    _Endpoint(
      'requestRollout',
      method: 'POST',
      path: '/releases/rel_1/rollout',
      status: 202,
      response: sample.run.toJson(),
      call: (client) => client.requestRollout(
        'rel_1',
        const RolloutRequest(
          store: ReleaseStore.play,
          action: RolloutAction.fraction,
          userFraction: 0.2,
        ),
      ),
      expected: sample.run,
      body: {'store': 'play', 'action': 'fraction', 'userFraction': 0.2},
    ),
    _Endpoint(
      'abandonRelease',
      method: 'POST',
      path: '/releases/rel_1/abandon',
      response: sample.release.toJson(),
      call: (client) => client.abandonRelease('rel_1'),
      expected: sample.release,
    ),
    _Endpoint(
      'abandonRelease with a reason',
      method: 'POST',
      path: '/releases/rel_1/abandon',
      response: sample.release.toJson(),
      call: (client) =>
          client.abandonRelease('rel_1', reason: 'rejected twice'),
      expected: sample.release,
      body: {'reason': 'rejected twice'},
    ),
    _Endpoint(
      'getReleaseNotes',
      method: 'GET',
      path: '/releases/rel_1/notes',
      response: sample.releaseNotes.toJson(),
      call: (client) => client.getReleaseNotes('rel_1'),
      expected: sample.releaseNotes,
    ),
    _Endpoint(
      'getStorage',
      method: 'GET',
      path: '/storage',
      response: sample.storageReport.toJson(),
      call: (client) => client.getStorage(),
      expected: sample.storageReport,
    ),
    _Endpoint(
      'freeStorage',
      method: 'POST',
      path: '/storage/free',
      response: sample.freeSpaceResult.toJson(),
      call: (client) => client.freeStorage(const FreeSpaceRequest()),
      expected: sample.freeSpaceResult,
      body: const FreeSpaceRequest().toJson(),
    ),
    _Endpoint(
      'getRetention',
      method: 'GET',
      path: '/storage/retention',
      response: const RetentionSettings().toJson(),
      call: (client) => client.getRetention(),
      expected: const RetentionSettings(),
    ),
    _Endpoint(
      'setRetention',
      method: 'PUT',
      path: '/storage/retention',
      response: const RetentionSettings(keepPerFlavor: 3).toJson(),
      call: (client) =>
          client.setRetention(const RetentionSettings(keepPerFlavor: 3)),
      expected: const RetentionSettings(keepPerFlavor: 3),
      body: const RetentionSettings(keepPerFlavor: 3).toJson(),
    ),
  ];

  group('endpoints', () {
    for (final endpoint in endpoints) {
      test('${endpoint.name}: ${endpoint.method} ${endpoint.path}', () async {
        engine.json(
          endpoint.method,
          endpoint.path,
          endpoint.response,
          status: endpoint.status,
        );

        final result = await endpoint.call(client);

        expect(result, endpoint.expected);
        expect(engine.calls, hasLength(1));
        expect(engine.last.method, endpoint.method);
        expect(engine.last.path, endpoint.path);
        expect(engine.last.query, endpoint.query);
        if (endpoint.body == null) {
          expect(engine.last.body, isEmpty);
        } else {
          expect(engine.last.json, endpoint.body);
        }
      });
    }
  });

  group('requests', () {
    test('send the token and the user agent, and ask for JSON', () async {
      engine.json('GET', '/projects', const ProjectsResponse([]).toJson());

      await client.listProjects();

      expect(engine.last.headers['authorization'], 'Bearer xp_secret');
      expect(engine.last.headers['user-agent'], clientUserAgent());
      expect(engine.last.headers['accept'], 'application/json');
      expect(engine.last.headers, isNot(contains('content-type')));
    });

    test('with a body say that it is JSON', () async {
      engine.json('POST', '/projects', sample.project.toJson(), status: 201);

      await client.addProject(const AddProjectRequest(path: '/x'));

      expect(engine.last.headers['content-type'], contains('application/json'));
    });

    test('health and version send no token', () async {
      engine
        ..json('GET', '/health', const HealthResponse().toJson())
        ..json(
          'GET',
          '/version',
          const VersionResponse(version: '1.0.0', apiVersion: '1').toJson(),
        );

      expect(await client.health(), const HealthResponse());
      expect(
        await client.version(),
        const VersionResponse(version: '1.0.0', apiVersion: '1'),
      );
      for (final call in engine.calls) {
        expect(call.headers, isNot(contains('authorization')));
      }
    });

    test('keep a path prefix of the base URL', () async {
      engine.json(
        'GET',
        '/engine/projects',
        const ProjectsResponse([]).toJson(),
      );
      final proxied = XpClient(
        baseUrl: engine.url.replace(path: '/engine/'),
        token: 't',
      );
      addTearDown(proxied.close);

      expect(await proxied.listProjects(), isEmpty);
    });

    test('escape the ids in the path', () async {
      engine.json('GET', '/projects/a%20b', sample.project.toJson());

      await client.getProject('a b');

      expect(engine.last.path, '/projects/a%20b');
    });

    test('use the HTTP client they are given and leave it open', () async {
      final http = _RecordingClient();
      engine.json('GET', '/projects', const ProjectsResponse([]).toJson());
      final shared = XpClient(
        baseUrl: engine.url,
        token: 't',
        httpClient: http,
      );

      await shared.listProjects();
      shared.close();

      expect(http.sent, 1);
      expect(http.closed, isFalse);
    });
  });

  group('errors', () {
    test('an error envelope becomes a typed ApiException', () async {
      engine.error(
        'POST',
        '/approvals/apr_1/approve',
        ApiErrorCode.forbidden,
        'An mcp token cannot approve.',
      );

      await expectLater(
        client.approve('apr_1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.code, 'code', ApiErrorCode.forbidden)
              .having((e) => e.isForbidden, 'isForbidden', isTrue)
              .having(
                (e) => e.message,
                'message',
                'An mcp token cannot approve.',
              ),
        ),
      );
    });

    test('already_decided carries the approval as it stands', () async {
      final decided = Approval(
        id: 'apr_1',
        projectId: 'prj_1',
        action: 'prod_release',
        sha: 'a' * 40,
        state: ApprovalState.denied,
        createdAt: sample.at,
        expiresAt: sample.at,
      );
      engine.json('POST', '/approvals/apr_1/approve', {
        ...ErrorResponse.of(ApiErrorCode.alreadyDecided, 'Decided.').toJson(),
        'approval': decided.toJson(),
      }, status: 409);

      await expectLater(
        client.approve('apr_1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.alreadyDecided)
              .having((e) => e.approval, 'approval', decided),
        ),
      );
    });

    test('a 401 says the token is unauthorized', () async {
      engine.error('GET', '/projects', ApiErrorCode.unauthorized, 'Bad token.');

      await expectLater(
        client.listProjects(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    });

    test('a resync_required says so', () async {
      engine.error('GET', '/projects', ApiErrorCode.resyncRequired, 'Reload.');

      await expectLater(
        client.listProjects(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isResyncRequired,
            'isResyncRequired',
            isTrue,
          ),
        ),
      );
    });

    test('an answer that is not an envelope still gives the status', () async {
      engine.on('GET', '/projects', (request, _) {
        request.response
          ..statusCode = 502
          ..write('<html>Bad gateway</html>');
        return request.response.close();
      });

      await expectLater(
        client.listProjects(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.code, 'code', isNull)
              .having((e) => e.message, 'message', contains('502'))
              .having((e) => '$e', 'toString', contains('502')),
        ),
      );
    });

    test('a 2xx that is not JSON is a ConnectionException', () async {
      engine.on('GET', '/projects', (request, _) {
        request.response.write('not json');
        return request.response.close();
      });

      await expectLater(
        client.listProjects(),
        throwsA(isA<ConnectionException>()),
      );
    });

    test('an engine that is not there is a ConnectionException', () async {
      final url = engine.url;
      await engine.close();

      await expectLater(
        XpClient(baseUrl: url, token: 't').listProjects(),
        throwsA(
          isA<ConnectionException>()
              .having((e) => e.message, 'message', contains(url.toString()))
              .having(
                (e) => e.message,
                'message',
                contains('Is xpd running? Its health is at'),
              )
              .having((e) => e.cause, 'cause', isNotNull)
              .having(
                (e) => '$e',
                'toString',
                startsWith('ConnectionException'),
              ),
        ),
      );
    });

    test(
      'an engine that does not answer in time is a ConnectionException',
      () async {
        final hang = Completer<void>();
        addTearDown(hang.complete);
        engine.on('GET', '/projects', (request, _) => hang.future);
        final impatient = XpClient(
          baseUrl: engine.url,
          token: 't',
          requestTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(impatient.close);

        await expectLater(
          impatient.listProjects(),
          throwsA(
            isA<ConnectionException>().having(
              (e) => e.message,
              'message',
              contains('did not answer'),
            ),
          ),
        );
      },
    );

    test(
      'a connection that breaks mid-answer is a ConnectionException',
      () async {
        engine.on('GET', '/projects', (request, _) async {
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.write(
            'HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n'
            'content-length: 1000\r\n\r\n{"pro',
          );
          await socket.flush();
          socket.destroy();
        });

        await expectLater(
          client.listProjects(),
          throwsA(isA<ConnectionException>()),
        );
      },
    );

    test('a failure body that breaks off is a ConnectionException', () async {
      engine.on('GET', '/projects', (request, _) async {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write('HTTP/1.1 500 Oops\r\ncontent-length: 1000\r\n\r\n{"err');
        await socket.flush();
        socket.destroy();
      });

      await expectLater(
        client.listProjects(),
        throwsA(isA<ConnectionException>()),
      );
    });
  });

  group('downloadArtifact', () {
    test('streams the file and reports what the engine announced', () async {
      engine.on('GET', '/artifacts/art_1/download', (request, _) {
        request.response
          ..headers.set('X-Content-SHA256', 'ABC')
          ..headers.set('Content-Disposition', 'attachment; filename="app.apk"')
          ..headers.contentLength = 3
          ..add([1, 2, 3]);
        return request.response.close();
      });

      final download = await client.downloadArtifact('art_1');

      expect(download.sha256, 'abc');
      expect(download.length, 3);
      expect(download.fileName, 'app.apk');
      expect(await download.content.expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
      ]);
    });

    test('without announcements reports none', () async {
      engine.on('GET', '/artifacts/art_1/download', (request, _) {
        request.response
          ..headers.chunkedTransferEncoding = true
          ..add([1]);
        return request.response.close();
      });

      final download = await client.downloadArtifact('art_1');

      expect(download.sha256, isNull);
      expect(download.fileName, isNull);
      await download.content.drain<void>();
    });

    test('a Content-Disposition without a file name gives none', () async {
      engine.on('GET', '/artifacts/art_1/download', (request, _) {
        request.response.headers.set('Content-Disposition', 'attachment');
        return request.response.close();
      });

      final download = await client.downloadArtifact('art_1');

      expect(download.fileName, isNull);
      await download.content.drain<void>();
    });

    test('refused is an ApiException', () async {
      engine.error(
        'GET',
        '/artifacts/art_1/download',
        ApiErrorCode.notFound,
        'No.',
      );

      await expectLater(
        client.downloadArtifact('art_1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  test('close does not fail', () {
    expect(
      XpClient(baseUrl: Uri.parse('http://x'), token: 't').close,
      returnsNormally,
    );
  });

  test('an exception lists its class in toString', () {
    expect(const DownloadException('m').toString(), 'DownloadException: m');
  });
}

class _RecordingClient extends http.BaseClient {
  final _inner = http.Client();
  int sent = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent++;
    return _inner.send(request);
  }

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}
