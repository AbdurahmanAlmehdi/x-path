import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
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

const _decidedBy = DecidedBy(
  tokenId: 'tok_1',
  name: 'My Mac',
  kind: DeviceTokenKind.app,
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
          ProjectRemoved(projectId: 'prj_2'),
          RunnerPaired(runnerId: 'r', name: 'r'),
        ],
      );
      expect(loads, 4);
      final cached = await repository.watchProjects().first;
      expect(cached, const Snapshot([project], cached: true));
    });

    test('watches the credentials of one project', () async {
      when(() => harness.client.listCredentials('prj_1'))
          .thenAnswer((_) async => [_credential]);
      final loads = await _loadsFor(
        harness: harness,
        stream: repository.watchCredentials('prj_1'),
        events: const [
          CredentialSaved(
            credentialId: 'crd_1',
            projectId: 'prj_1',
            kind: CredentialKind.ascKey,
            replaced: false,
          ),
          CredentialVerified(
            credentialId: 'crd_1',
            projectId: 'prj_1',
            kind: CredentialKind.ascKey,
            status: CredentialStatus.verified,
          ),
          CredentialExpired(
            credentialId: 'crd_1',
            projectId: 'prj_1',
            kind: CredentialKind.ascKey,
            message: 'Expired.',
          ),
          CredentialRemoved(
            credentialId: 'crd_1',
            projectId: 'prj_1',
            kind: CredentialKind.ascKey,
          ),
          CredentialRemoved(
            credentialId: 'crd_9',
            projectId: 'prj_9',
            kind: CredentialKind.ascKey,
          ),
          ProjectRemoved(projectId: 'prj_1'),
        ],
      );
      expect(loads, 5);
      expect(
        await repository.watchCredentials('prj_1').first,
        const Snapshot([_credential], cached: true),
      );
    });

    test('passes the commands to the engine', () async {
      final client = harness.client;
      const request = SaveCredentialRequest(
        flavor: 'prod',
        kind: CredentialKind.slack,
        material: {'webhookUrl': 'https://hooks.slack.com/services/T/B/X'},
      );
      when(() => client.getProject('prj_1')).thenAnswer((_) async => project);
      when(() => client.addProject(const AddProjectRequest(path: '/src/app')))
          .thenAnswer((_) async => project);
      when(() => client.scanProject('prj_1')).thenAnswer((_) async => project);
      when(() => client.removeProject('prj_1')).thenAnswer((_) async {});
      when(() => client.saveCredential('prj_1', request))
          .thenAnswer((_) async => _credential);
      when(() => client.verifyCredential('prj_1', 'crd_1'))
          .thenAnswer((_) async => _credential);
      when(() => client.deleteCredential('prj_1', 'crd_1'))
          .thenAnswer((_) async {});

      expect(await repository.getProject('prj_1'), project);
      expect(await repository.addProject('/src/app'), project);
      expect(await repository.scanProject('prj_1'), project);
      await repository.removeProject('prj_1');
      expect(await repository.saveCredential('prj_1', request), _credential);
      expect(await repository.verifyCredential('prj_1', 'crd_1'), _credential);
      await repository.deleteCredential('prj_1', 'crd_1');
      verify(() => client.removeProject('prj_1')).called(1);
      verify(() => client.deleteCredential('prj_1', 'crd_1')).called(1);
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

      expect(await repository.createPairingToken('a'), token);
      expect(await repository.revoke('rnr_1'), _runner);
    });
  });
}
