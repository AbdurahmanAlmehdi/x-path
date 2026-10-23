import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/xp_repositories.dart';

import 'helpers/helpers.dart';

final _job = Job(
  id: 'job_1',
  projectId: 'prj_1',
  workflowVersionId: 'wfv_1',
  state: JobState.running,
  createdAt: at,
  steps: const [],
);

final _run = Run(
  id: 'run_1',
  projectId: 'prj_1',
  workflowId: 'wf_1',
  workflowVersionId: 'wfv_1',
  sha: '9a3bc0d',
  state: RunState.values.first,
  locksProject: false,
  createdAt: at,
  jobs: const [],
);

final _release = Release(
  id: 'rel_1',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  version: '5.4.1',
  build: 3283,
  state: ReleaseState.inReview,
  stores: const [],
  builds: const [],
  mergeEnabled: false,
  createdAt: at,
  updatedAt: at,
);

final _approval = Approval(
  id: 'apr_1',
  projectId: 'prj_1',
  action: 'store_submission',
  sha: '9a3bc0d',
  state: ApprovalState.pending,
  createdAt: at,
  expiresAt: at,
);

final _runner = Runner(
  id: 'rnr_1',
  name: 'linux-builder-01',
  status: RunnerStatus.online,
  capabilities: const ['android'],
  slots: 4,
  jobIds: const [],
  createdAt: at,
);

const _credential = Credential(
  id: 'crd_1',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
);

const _named = NamedCredential(
  id: 'crd_1',
  name: 'Team key',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
);

/// One event of each credential kind of event.
const _credentialEvents = <EngineEvent>[
  CredentialSaved(
    credentialId: 'crd_1',
    kind: CredentialKind.ascKey,
    replaced: false,
  ),
  CredentialVerified(
    credentialId: 'crd_1',
    kind: CredentialKind.ascKey,
    status: CredentialStatus.verified,
  ),
  CredentialExpired(
    credentialId: 'crd_1',
    kind: CredentialKind.ascKey,
    message: 'Expired.',
  ),
  CredentialRemoved(credentialId: 'crd_9', kind: CredentialKind.ascKey),
  CredentialRenamed(
    credentialId: 'crd_1',
    kind: CredentialKind.ascKey,
    name: 'Renamed',
  ),
  CredentialAssigned(
    credentialId: 'crd_1',
    projectId: 'prj_9',
    app: '.',
    flavor: 'prod',
    kind: CredentialKind.ascKey,
  ),
  CredentialUnassigned(
    credentialId: 'crd_1',
    projectId: 'prj_9',
    app: '.',
    flavor: 'prod',
    kind: CredentialKind.ascKey,
  ),
];

const _decidedBy = DecidedBy(
  tokenId: 'tok_1',
  name: 'My Mac',
  kind: DeviceTokenKind.app,
);

const _counts = TestCounts(
  total: 3,
  passed: 2,
  failed: 1,
  errored: 0,
  skipped: 0,
);

final _baseline = TestBaseline(
  appPath: '.',
  branch: 'main',
  jobId: 'job_1',
  createdAt: at,
  counts: _counts,
);

final _testRun = TestRunResponse(
  run: TestRun(
    id: 'tst_1',
    jobId: 'job_2',
    branch: 'feature',
    appPath: '.',
    baseline: false,
    createdAt: at,
    counts: _counts,
    diff: const TestRunDiff(
      comparedTo: 'job_1',
      newFailures: [TestRef(suite: 'test/a_test.dart', name: 'a')],
      fixed: [],
      missing: [],
      stillFailing: 0,
    ),
  ),
  total: 1,
  offset: 0,
  tests: const [
    TestCase(
      suite: 'test/a_test.dart',
      name: 'a',
      status: TestStatus.failed,
      message: 'Expected: 1',
    ),
  ],
);

TestRunCompleted _completed({
  String jobId = 'job_2',
  String projectId = 'prj_1',
  bool baseline = false,
}) => TestRunCompleted(
  jobId: jobId,
  projectId: projectId,
  branch: 'main',
  baseline: baseline,
  failures: 1,
  newFailures: 0,
);

final _report = StorageReport(
  generatedAt: at,
  categories: const [
    CategoryUsage(
      category: StorageCategory.artifacts,
      usedBytes: 100,
      reclaimableBytes: 40,
      items: 3,
    ),
  ],
  flavors: const [],
  retention: const RetentionSettings(),
);

/// How many values [stream] emits while [events] arrive: one per load.
Future<int> _loadsFor<T>({
  required Harness harness,
  required Stream<Snapshot<T>> stream,
  required List<EngineEvent> events,
}) async {
  final values = <Snapshot<T>>[];
  final subscription = stream.listen(values.add);
  await settle();
  for (final event in events) {
    harness.send(event);
    await settle();
  }
  await subscription.cancel();
  return values.length;
}

void main() {
  late Harness harness;

  setUp(() async {
    harness = Harness();
    await harness.session.start();
  });

  tearDown(() => harness.dispose());

  group('ProjectsRepository', () {
    late ProjectsRepository repository;

    setUp(() => repository = ProjectsRepository(harness.session));

    test('watches the projects through their events and the cache', () async {
      when(() => harness.client.listProjects())
          .thenAnswer((_) async => [project]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchProjects(),
        events: const [
          ProjectAdded(projectId: 'prj_2', fullName: 'a/b'),
          ProjectScanned(projectId: 'prj_1', errors: 0, warnings: 1),
          ProjectEdited(projectId: 'prj_1'),
          ProjectRemoved(projectId: 'prj_2'),
          RunnerPaired(runnerId: 'r', name: 'r'),
        ],
      );
      expect(loads, 5);
      final cached = await repository.watchProjects().first;
      expect(cached, const Snapshot([project], cached: true));
    });

    test('watches the credentials of one project through every credential '
        'event', () async {
      when(() => harness.client.listCredentials('prj_1'))
          .thenAnswer((_) async => [_credential]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchCredentials('prj_1'),
        events: [
          ..._credentialEvents,
          const ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 1 + _credentialEvents.length);
      expect(
        await repository.watchCredentials('prj_1').first,
        const Snapshot([_credential], cached: true),
      );
    });

    test('passes the commands to the engine', () async {
      final client = harness.client;
      const response = AssignCredentialResponse(
        assigned: [_credential],
        kept: [_credential],
      );
      when(() => client.getProject('prj_1')).thenAnswer((_) async => project);
      when(() => client.addProject(const AddProjectRequest(path: '/src/app')))
          .thenAnswer((_) async => project);
      when(() => client.scanProject('prj_1')).thenAnswer((_) async => project);
      when(() => client.removeProject('prj_1')).thenAnswer((_) async {});
      const edits = ProfileEdits(defaultBaseBranch: 'dev');
      when(() => client.updateProject('prj_1', edits))
          .thenAnswer((_) async => project);
      when(
        () => client.assignCredential(
          'prj_1',
          app: 'apps/x',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          request: const AssignCredentialRequest(
            credentialId: 'crd_1',
            allFlavors: true,
            replace: true,
          ),
        ),
      ).thenAnswer((_) async => response);
      when(
        () => client.unassignCredential(
          'prj_1',
          flavor: 'dev',
          kind: CredentialKind.slack,
        ),
      ).thenAnswer((_) async {});

      expect(await repository.getProject('prj_1'), project);
      expect(await repository.addProject('/src/app'), project);
      expect(await repository.scanProject('prj_1'), project);
      expect(await repository.editProject('prj_1', edits), project);
      await repository.removeProject('prj_1');
      expect(
        await repository.assignCredential(
          'prj_1',
          app: 'apps/x',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          credentialId: 'crd_1',
          allFlavors: true,
          replace: true,
        ),
        response,
      );
      await repository.unassignCredential(
        'prj_1',
        app: '.',
        flavor: 'dev',
        kind: CredentialKind.slack,
      );
      verify(() => client.removeProject('prj_1')).called(1);
      verify(
        () => client.unassignCredential(
          'prj_1',
          flavor: 'dev',
          kind: CredentialKind.slack,
        ),
      ).called(1);
    });
  });

  group('CredentialsRepository', () {
    late CredentialsRepository repository;

    setUp(() => repository = CredentialsRepository(harness.session));

    test(
      'watches the named credentials through every credential event',
      () async {
        when(() => harness.client.listNamedCredentials())
            .thenAnswer((_) async => [_named]);
        final loads = await _loadsFor(
          harness: harness,
          stream: repository.watchCredentials(),
          events: [
            ..._credentialEvents,
            const ProjectRemoved(projectId: 'prj_1'),
          ],
        );
        expect(loads, 1 + _credentialEvents.length);
        expect(
          await repository.watchCredentials().first,
          const Snapshot([_named], cached: true),
        );
      },
    );

    test('passes the commands to the engine', () async {
      final client = harness.client;
      const create = CreateCredentialRequest(
        name: 'Team key',
        kind: CredentialKind.shorebird,
        material: {'token': 'sb_api_fake'},
      );
      const replace = ReplaceCredentialRequest({'token': 'sb_api_fake2'});
      when(() => client.createCredential(create))
          .thenAnswer((_) async => _named);
      when(() => client.renameCredential('crd_1', 'New name'))
          .thenAnswer((_) async => _named);
      when(() => client.replaceCredentialSecret('crd_1', replace))
          .thenAnswer((_) async => _named);
      when(() => client.verifyNamedCredential('crd_1'))
          .thenAnswer((_) async => _named);
      when(() => client.deleteNamedCredential('crd_1', force: true))
          .thenAnswer((_) async {});

      expect(await repository.createCredential(create), _named);
      expect(await repository.renameCredential('crd_1', 'New name'), _named);
      expect(await repository.replaceSecret('crd_1', replace), _named);
      expect(await repository.verifyCredential('crd_1'), _named);
      await repository.deleteCredential('crd_1', force: true);
      verify(() => client.deleteNamedCredential('crd_1', force: true))
          .called(1);
    });

    test(
      'says which flavors keep a credential in use from being deleted',
      () async {
        const usage = CredentialUsage(
          projectId: 'prj_1',
          project: 'acme/app',
          app: '.',
          flavor: 'prod',
          status: CredentialStatus.verified,
        );
        when(() => harness.client.deleteNamedCredential('crd_1')).thenThrow(
          const ApiException(
            'It is in use.',
            statusCode: 409,
            code: ApiErrorCode.credentialInUse,
            usedBy: [usage],
          ),
        );
        await expectLater(
          repository.deleteCredential('crd_1'),
          throwsA(
            isA<CredentialInUse>()
                .having((error) => error.message, 'message', 'It is in use.')
                .having((error) => error.usedBy, 'usedBy', [usage]),
          ),
        );
      },
    );

    test('passes on any other refusal', () async {
      when(() => harness.client.deleteNamedCredential('crd_1'))
          .thenThrow(notFound);
      await expectLater(
        repository.deleteCredential('crd_1'),
        throwsA(notFound),
      );
    });
  });

  group('JobsRepository', () {
    late JobsRepository repository;

    setUp(() => repository = JobsRepository(harness.session));

    test('watches one job through its job and step events', () async {
      when(() => harness.client.getJob('job_1')).thenAnswer((_) async => _job);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchJob('job_1'),
        events: const [
          JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.succeeded,
          ),
          JobStepChanged(
            jobId: 'job_1',
            ordinal: 0,
            kind: 'guard',
            state: StepState.succeeded,
          ),
          RunnerLeaseLost(
            runnerId: 'rnr_1',
            jobId: 'job_1',
            projectId: 'prj_1',
            reason: 'lease lapsed',
            state: JobState.failed,
          ),
          JobStateChanged(
            jobId: 'job_2',
            projectId: 'prj_1',
            state: JobState.succeeded,
          ),
          ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 4);
      expect(
        await repository.watchJob('job_1').first,
        Snapshot(_job, cached: true),
      );
    });

    test('watches one run through the events of its project', () async {
      when(() => harness.client.getRun('run_1')).thenAnswer((_) async => _run);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchRun('run_1'),
        events: [
          const JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.running,
          ),
          ApprovalRequested(
            approvalId: 'apr_1',
            projectId: 'prj_1',
            action: 'prod_release',
            sha: '9a3bc0d',
            expiresAt: at,
          ),
          const ApprovalDecided(
            approvalId: 'apr_1',
            projectId: 'prj_1',
            action: 'prod_release',
            state: ApprovalState.approved,
            decidedBy: _decidedBy,
          ),
          const ApprovalExpired(
            approvalId: 'apr_2',
            projectId: 'prj_1',
            action: 'push',
          ),
          const JobStateChanged(
            jobId: 'job_9',
            projectId: 'prj_9',
            state: JobState.running,
          ),
          const ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 5);
      expect(
        await repository.watchRun('run_1').first,
        Snapshot(_run, cached: true),
      );
    });

    test('watches a run with its jobs through their events', () async {
      final run = Run(
        id: 'run_1',
        projectId: 'prj_1',
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: '9a3bc0d',
        state: RunState.running,
        locksProject: false,
        createdAt: at,
        jobs: const [
          RunJob(id: 'job_1', name: 'build', stage: 0, state: JobState.running),
        ],
      );
      when(() => harness.client.getRun('run_1')).thenAnswer((_) async => run);
      when(() => harness.client.getJob('job_1')).thenAnswer((_) async => _job);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchRunJobs('run_1'),
        events: [
          const JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.running,
          ),
          const JobStepChanged(
            jobId: 'job_1',
            ordinal: 0,
            kind: 'guard',
            state: StepState.running,
          ),
          const RunnerLeaseLost(
            runnerId: 'rnr_1',
            jobId: 'job_1',
            projectId: 'prj_1',
            reason: 'lease lapsed',
            state: JobState.interrupted,
          ),
          ApprovalRequested(
            approvalId: 'apr_1',
            projectId: 'prj_1',
            action: 'push',
            sha: '9a3bc0d',
            expiresAt: at,
          ),
          const ApprovalDecided(
            approvalId: 'apr_1',
            projectId: 'prj_1',
            action: 'push',
            state: ApprovalState.approved,
            decidedBy: _decidedBy,
          ),
          const ApprovalExpired(
            approvalId: 'apr_2',
            projectId: 'prj_1',
            action: 'push',
          ),
          const JobStepChanged(
            jobId: 'job_9',
            ordinal: 0,
            kind: 'guard',
            state: StepState.running,
          ),
          const ApprovalExpired(
            approvalId: 'apr_3',
            projectId: 'prj_9',
            action: 'push',
          ),
          const ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 7);
      final cached = await repository.watchRunJobs('run_1').first;
      expect(cached, Snapshot(RunJobs(run: run, jobs: [_job]), cached: true));
      expect(cached.value.job('job_1'), _job);
      expect(cached.value.job('job_2'), isNull);
    });

    test('passes the commands to the engine', () async {
      final client = harness.client;
      const artifacts = <Artifact>[];
      const frames = <LogFrame>[];
      when(() => client.cancelJob('job_1')).thenAnswer((_) async => _job);
      when(() => client.resumeJob('job_1', fromStep: 2))
          .thenAnswer((_) async => _job);
      when(() => client.cancelRun('run_1')).thenAnswer((_) async => _run);
      when(() => client.followJobLogs('job_1', after: 5))
          .thenAnswer((_) => Stream.fromIterable(frames));
      when(() => client.listJobArtifacts('job_1'))
          .thenAnswer((_) async => artifacts);

      expect(await repository.cancelJob('job_1'), _job);
      expect(await repository.resumeJob('job_1', fromStep: 2), _job);
      expect(await repository.cancelRun('run_1'), _run);
      expect(await repository.followLogs('job_1', after: 5).toList(), frames);
      expect(await repository.listArtifacts('job_1'), artifacts);
    });
  });

  group('WorkflowsRepository', () {
    late WorkflowsRepository repository;

    final version1 = WorkflowVersionInfo(
      id: 'wfv_1',
      version: 1,
      createdAt: at,
    );
    final version2 = WorkflowVersionInfo(
      id: 'wfv_2',
      version: 2,
      createdAt: at,
    );
    Workflow workflow(WorkflowVersionInfo version) => Workflow(
      id: 'wf_1',
      projectId: 'prj_1',
      name: 'Dev build',
      builtin: true,
      version: version,
      versions: [version1, version2],
      yaml: 'stages: []',
    );

    setUp(() => repository = WorkflowsRepository(harness.session));

    test('lists and reads workflows', () async {
      final client = harness.client;
      final summary = WorkflowSummary(
        id: 'wf_1',
        projectId: 'prj_1',
        name: 'Dev build',
        builtin: true,
        version: version2,
      );
      when(() => client.listWorkflows('prj_1'))
          .thenAnswer((_) async => [summary]);
      when(() => client.getWorkflow('prj_1', 'wf_1', version: 1))
          .thenAnswer((_) async => workflow(version1));
      expect(await repository.listWorkflows('prj_1'), [summary]);
      expect(
        await repository.getWorkflow('prj_1', 'wf_1', version: 1),
        workflow(version1),
      );
    });

    test('reads the schema, validates, creates and saves', () async {
      final client = harness.client;
      const schema = WorkflowSchema(
        schema: 1,
        steps: [StepType(kind: 'test')],
        gates: ['push'],
        capabilities: ['flutter'],
        matrixAxes: ['platform'],
        platforms: ['android'],
      );
      const issues = ValidateWorkflowResponse(
        valid: false,
        issues: [WorkflowIssue(line: 1, column: 1, message: 'm')],
      );
      when(client.getWorkflowSchema).thenAnswer((_) async => schema);
      when(() => client.validateWorkflow('prj_1', 'y'))
          .thenAnswer((_) async => issues);
      when(
        () => client.createWorkflow(
          'prj_1',
          const CreateWorkflowRequest(name: 'mine', yaml: 'y'),
        ),
      ).thenAnswer((_) async => workflow(version1));
      when(() => client.saveWorkflow('prj_1', 'wf_1', 'y'))
          .thenAnswer((_) async => workflow(version2));

      expect(await repository.schema(), schema);
      expect(await repository.validate('prj_1', 'y'), issues);
      expect(
        await repository.createWorkflow('prj_1', name: 'mine', yaml: 'y'),
        workflow(version1),
      );
      expect(
        await repository.saveWorkflow('prj_1', 'wf_1', 'y'),
        workflow(version2),
      );
    });

    test('reads the version of the workflow a run runs', () async {
      final client = harness.client;
      when(() => client.getWorkflow('prj_1', 'wf_1'))
          .thenAnswer((_) async => workflow(version2));
      when(() => client.getWorkflow('prj_1', 'wf_1', version: 1))
          .thenAnswer((_) async => workflow(version1));
      Run runOf(String versionId) => Run(
        id: 'run_1',
        projectId: 'prj_1',
        workflowId: 'wf_1',
        workflowVersionId: versionId,
        sha: '9a3bc0d',
        state: RunState.running,
        locksProject: false,
        createdAt: at,
        jobs: const [],
      );
      expect(await repository.workflowOf(runOf('wfv_2')), workflow(version2));
      expect(await repository.workflowOf(runOf('wfv_1')), workflow(version1));
      expect(await repository.workflowOf(runOf('wfv_9')), workflow(version2));
    });

    test('previews and dispatches a run', () async {
      final client = harness.client;
      const request = DispatchRequest(flavors: ['dev']);
      when(client.listRunners).thenAnswer((_) async => [_runner]);
      when(() => client.getGates('prj_1'))
          .thenAnswer((_) async => const ProjectGates({}));
      when(() => client.listCredentials('prj_1'))
          .thenAnswer((_) async => [_credential]);
      when(() => client.dispatchWorkflow('prj_1', 'wf_1', request))
          .thenAnswer((_) async => _run);
      final preview = await repository.preview(
        project: project,
        workflow: workflow(version2),
        request: request,
      );
      expect(
        preview,
        const DispatchPreview(flavors: [], platforms: [], stages: []),
      );
      expect(await repository.dispatch('prj_1', 'wf_1', request), _run);
    });
  });

  group('ReleasesRepository', () {
    late ReleasesRepository repository;

    setUp(() => repository = ReleasesRepository(harness.session));

    final events = <EngineEvent>[
      const ReleaseCreated(
        releaseId: 'rel_2',
        projectId: 'prj_1',
        flavor: 'prod',
        version: '5.4.2',
        build: 3290,
      ),
      const ReleaseStateChanged(
        releaseId: 'rel_1',
        projectId: 'prj_1',
        from: ReleaseState.uploaded,
        to: ReleaseState.inReview,
      ),
      const ReleaseStoreChanged(
        releaseId: 'rel_1',
        projectId: 'prj_1',
        store: ReleaseStore.apple,
        state: StoreState.inReview,
        source: StatusSource.api,
      ),
      const ReleaseStateChanged(
        releaseId: 'rel_9',
        projectId: 'prj_9',
        from: ReleaseState.uploaded,
        to: ReleaseState.inReview,
      ),
      const ProjectRemoved(projectId: 'prj_1'),
    ];

    test('watches every release', () async {
      when(() => harness.client.listReleases())
          .thenAnswer((_) async => [_release]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchReleases(),
        events: events,
      );
      expect(loads, 5);
      expect(
        await repository.watchReleases().first,
        Snapshot([_release], cached: true),
      );
    });

    test('watches the releases of one project', () async {
      when(() => harness.client.listReleases(projectId: 'prj_1'))
          .thenAnswer((_) async => [_release]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchReleases(projectId: 'prj_1'),
        events: events,
      );
      expect(loads, 4);
    });

    test('watches one release', () async {
      when(() => harness.client.getRelease('rel_1'))
          .thenAnswer((_) async => _release);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchRelease('rel_1'),
        events: events,
      );
      expect(loads, 3);
      expect(
        await repository.watchRelease('rel_1').first,
        Snapshot(_release, cached: true),
      );
    });

    test('passes the commands to the engine', () async {
      final client = harness.client;
      const notes = ReleaseNotes(
        releaseId: 'rel_1',
        version: '5.4.1',
        build: 3283,
        to: '9a3bc0d',
        commits: 0,
        groups: [],
        slack: '',
        whatsapp: '',
      );
      when(() => client.refreshRelease('rel_1'))
          .thenAnswer((_) async => _release);
      when(
        () => client.setReleaseStoreStatus(
          'rel_1',
          ReleaseStore.play,
          StoreState.live,
        ),
      ).thenAnswer((_) async => _release);
      when(() => client.startReleaseBuild('rel_1'))
          .thenAnswer((_) async => _run);
      when(() => client.mergeRelease('rel_1')).thenAnswer((_) async => _run);
      when(() => client.abandonRelease('rel_1', reason: 'no'))
          .thenAnswer((_) async => _release);
      when(() => client.getReleaseNotes('rel_1'))
          .thenAnswer((_) async => notes);

      expect(await repository.refresh('rel_1'), _release);
      expect(
        await repository.setStoreStatus(
          'rel_1',
          ReleaseStore.play,
          StoreState.live,
        ),
        _release,
      );
      expect(await repository.startBuild('rel_1'), _run);
      expect(await repository.merge('rel_1'), _run);
      expect(await repository.abandon('rel_1', reason: 'no'), _release);
      expect(await repository.notes('rel_1'), notes);
    });
  });

  group('ApprovalsRepository', () {
    late ApprovalsRepository repository;

    setUp(() => repository = ApprovalsRepository(harness.session));

    final events = <EngineEvent>[
      ApprovalRequested(
        approvalId: 'apr_1',
        projectId: 'prj_1',
        action: 'store_submission',
        sha: '9a3bc0d',
        expiresAt: at,
      ),
      const ApprovalDecided(
        approvalId: 'apr_1',
        projectId: 'prj_1',
        action: 'store_submission',
        state: ApprovalState.denied,
        decidedBy: _decidedBy,
      ),
      const ApprovalExpired(
        approvalId: 'apr_9',
        projectId: 'prj_9',
        action: 'push',
      ),
      const ProjectRemoved(projectId: 'prj_1'),
    ];

    test('watches every approval', () async {
      when(() => harness.client.listApprovals())
          .thenAnswer((_) async => [_approval]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchApprovals(),
        events: events,
      );
      expect(loads, 4);
      expect(
        await repository.watchApprovals().first,
        Snapshot([_approval], cached: true),
      );
    });

    test('watches the pending approvals of one project', () async {
      when(
        () => harness.client.listApprovals(
          projectId: 'prj_1',
          state: ApprovalState.pending,
        ),
      ).thenAnswer((_) async => [_approval]);
      final stream = repository.watchApprovals(
        projectId: 'prj_1',
        state: ApprovalState.pending,
      );
      final loads = await _loadsFor(
        harness: harness,
        stream: stream,
        events: events,
      );
      expect(loads, 3);
      expect(await harness.cache.read('approvals.prj_1.pending'), isNotNull);
    });

    test('passes the commands to the engine', () async {
      final client = harness.client;
      const gates = ProjectGates({'push': true});
      when(() => client.approve('apr_1', reason: 'ok'))
          .thenAnswer((_) async => _approval);
      when(() => client.deny('apr_1')).thenAnswer((_) async => _approval);
      when(() => client.getGates('prj_1')).thenAnswer((_) async => gates);
      when(() => client.setGates('prj_1', gates))
          .thenAnswer((_) async => gates);

      expect(await repository.approve('apr_1', reason: 'ok'), _approval);
      expect(await repository.deny('apr_1'), _approval);
      expect(await repository.getGates('prj_1'), gates);
      expect(await repository.setGates('prj_1', gates), gates);
    });

    test('watches one approval through its own events', () async {
      when(() => harness.client.getApproval('apr_1'))
          .thenAnswer((_) async => _approval);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchApproval('apr_1'),
        events: [
          ...events,
          const ApprovalExpired(
            approvalId: 'apr_1',
            projectId: 'prj_1',
            action: 'store_submission',
          ),
        ],
      );
      expect(loads, 3);
      expect(
        await repository.watchApproval('apr_1').first,
        Snapshot(_approval, cached: true),
      );
    });

    test('says when another device decided first', () async {
      final decided = Approval(
        id: 'apr_1',
        projectId: 'prj_1',
        action: 'store_submission',
        sha: '9a3bc0d',
        state: ApprovalState.approved,
        createdAt: at,
        expiresAt: at,
        decidedBy: _decidedBy,
      );
      when(() => harness.client.approve('apr_1')).thenThrow(
        ApiException(
          'The approval apr_1 was approved already.',
          statusCode: 409,
          code: ApiErrorCode.alreadyDecided,
          approval: decided,
        ),
      );
      when(() => harness.client.deny('apr_1')).thenThrow(notFound);

      await expectLater(
        repository.approve('apr_1'),
        throwsA(
          isA<ApprovalAlreadyDecided>()
              .having((error) => error.approval, 'approval', decided)
              .having(
                (error) => error.toString(),
                'toString',
                contains('approved already'),
              ),
        ),
      );
      await expectLater(repository.deny('apr_1'), throwsA(notFound));
    });
  });

  group('RunnersRepository', () {
    late RunnersRepository repository;

    setUp(() => repository = RunnersRepository(harness.session));

    test('watches the runners through runner and job events', () async {
      when(() => harness.client.listRunners())
          .thenAnswer((_) async => [_runner]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchRunners(),
        events: const [
          RunnerPaired(runnerId: 'rnr_1', name: 'a'),
          RunnerConnected(
            runnerId: 'rnr_1',
            name: 'a',
            capabilities: ['android'],
            slots: 4,
          ),
          RunnerDisconnected(runnerId: 'rnr_1', name: 'a'),
          RunnerRevoked(runnerId: 'rnr_1', name: 'a'),
          RunnerCapabilitiesChanged(
            runnerId: 'rnr_1',
            name: 'a',
            from: [],
            to: ['android'],
          ),
          RunnerLeaseLost(
            runnerId: 'rnr_1',
            jobId: 'job_1',
            projectId: 'prj_1',
            reason: 'lapsed',
            state: JobState.failed,
          ),
          JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.running,
          ),
          ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 8);
      expect(
        await repository.watchRunners().first,
        Snapshot([_runner], cached: true),
      );
    });

    test('passes the commands to the engine', () async {
      final client = harness.client;
      final token = PairingToken(token: 'xpp_1', name: 'a', expiresAt: at);
      when(() => client.createPairingToken('a')).thenAnswer((_) async => token);
      when(() => client.revokeRunner('rnr_1')).thenAnswer((_) async => _runner);
      const url = RunnerUrl(url: 'https://mac.tailnet.ts.net');
      when(client.runnerUrl).thenAnswer((_) async => url);
      when(() => client.setRunnerUrl('https://mac.tailnet.ts.net'))
          .thenAnswer((_) async => url);

      expect(await repository.createPairingToken('a'), token);
      expect(await repository.revoke('rnr_1'), _runner);
      expect(await repository.runnerUrl(), url);
      expect(await repository.setRunnerUrl('https://mac.tailnet.ts.net'), url);
    });
  });

  group('TestsRepository', () {
    late TestsRepository repository;

    setUp(() => repository = TestsRepository(harness.session));

    test('watches the baselines through the runs that become one', () async {
      when(() => harness.client.getTestBaselines('prj_1'))
          .thenAnswer((_) async => [_baseline]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchBaselines('prj_1'),
        events: [
          _completed(baseline: true),
          _completed(),
          _completed(baseline: true, projectId: 'prj_2'),
          const ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 2);
      expect(
        await repository.watchBaselines('prj_1').first,
        Snapshot([_baseline], cached: true),
      );
    });

    test('watches the run of a job through its own runs', () async {
      when(() => harness.client.getJobTests('job_2', limit: 1000))
          .thenAnswer((_) async => _testRun);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchRun('job_2'),
        events: [
          _completed(),
          _completed(jobId: 'job_3'),
          const ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 2);
      expect(
        await repository.watchRun('job_2').first,
        Snapshot(_testRun, cached: true),
      );
    });

    test('follows the runs of one project as they end', () async {
      final runs = <TestRunCompleted>[];
      final subscription = repository.completedRuns('prj_1').listen(runs.add);
      harness
        ..send(_completed())
        ..send(_completed(projectId: 'prj_2'))
        ..send(const ProjectRemoved(projectId: 'prj_1'));
      await settle();
      await subscription.cancel();
      expect(runs, [_completed()]);
    });
  });

  group('StorageRepository', () {
    late StorageRepository repository;

    setUp(() => repository = StorageRepository(harness.session));

    test('reads the storage once, whatever happens', () async {
      when(() => harness.client.getStorage()).thenAnswer((_) async => _report);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchStorage(),
        events: const [ProjectRemoved(projectId: 'prj_1')],
      );
      expect(loads, 1);
      expect(
        await repository.watchStorage().first,
        Snapshot(_report, cached: true),
      );
    });

    test('passes the commands to the engine', () async {
      final client = harness.client;
      const freed = FreeSpaceResult(dryRun: false, categories: []);
      const settings = RetentionSettings(keepPerFlavor: 3, logDays: 30);
      when(
        () => client.freeStorage(
          const FreeSpaceRequest(
            dryRun: false,
            categories: [StorageCategory.logs],
          ),
        ),
      ).thenAnswer((_) async => freed);
      when(() => client.setRetention(settings))
          .thenAnswer((_) async => settings);

      expect(await repository.freeSpace([StorageCategory.logs]), freed);
      expect(await repository.setRetention(settings), settings);
    });
  });

  group('SettingsRepository', () {
    late SettingsRepository repository;

    setUp(() => repository = SettingsRepository(harness.session));

    test('passes the requests to the engine', () async {
      final client = harness.client;
      const version = VersionResponse(version: '1.0.0', apiVersion: '1');
      const missing = GitHubTokenStatus(stored: false);
      const stored = GitHubTokenStatus(
        stored: true,
        status: CredentialStatus.verified,
        login: 'octo',
      );
      when(client.version).thenAnswer((_) async => version);
      when(client.getGitHubToken).thenAnswer((_) async => missing);
      when(() => client.setGitHubToken('ghp_x'))
          .thenAnswer((_) async => stored);
      when(client.importGitHubToken).thenAnswer((_) async => stored);
      when(client.deleteGitHubToken).thenAnswer((_) async {});

      expect(await repository.engineVersion(), version);
      expect(await repository.gitHubToken(), missing);
      expect(await repository.setGitHubToken('ghp_x'), stored);
      expect(await repository.importGitHubToken(), stored);
      await repository.clearGitHubToken();
      verify(client.deleteGitHubToken).called(1);
    });
  });
}
