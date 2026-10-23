import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_repositories/xp_repositories.dart';

class MockXpClient extends Mock implements XpClient;

class MockEnginesRepository extends Mock implements EnginesRepository;

class MockProjectsRepository extends Mock implements ProjectsRepository;

class MockCredentialsRepository extends Mock implements CredentialsRepository;

class MockJobsRepository extends Mock implements JobsRepository;

class MockReleasesRepository extends Mock implements ReleasesRepository;

class MockRunnersRepository extends Mock implements RunnersRepository;

class MockWorkflowsRepository extends Mock implements WorkflowsRepository;

class MockApprovalsRepository extends Mock implements ApprovalsRepository;

class MockTestsRepository extends Mock implements TestsRepository;

class MockStorageRepository extends Mock implements StorageRepository;

class MockSettingsRepository extends Mock implements SettingsRepository;

/// A settings repository of an engine `0.0.1` that has its GitHub token.
MockSettingsRepository quietSettings({
  GitHubTokenStatus token = const GitHubTokenStatus(
    stored: true,
    status: CredentialStatus.verified,
    login: 'octo',
  ),
}) {
  final repository = MockSettingsRepository();
  when(repository.engineVersion).thenAnswer(
    (_) async => const VersionResponse(version: '0.0.1', apiVersion: '1'),
  );
  when(repository.gitHubToken).thenAnswer((_) async => token);
  return repository;
}

/// An approvals repository whose approvals never arrive.
MockApprovalsRepository quietApprovals() {
  final repository = MockApprovalsRepository();
  when(
    () => repository.watchApprovals(
      projectId: any(named: 'projectId'),
      state: any(named: 'state'),
    ),
  ).thenAnswer((_) => const Stream.empty());
  return repository;
}

/// A projects repository whose credentials never arrive.
MockProjectsRepository quietProjects() {
  final repository = MockProjectsRepository();
  when(() => repository.watchCredentials(any()))
      .thenAnswer((_) => const Stream.empty());
  return repository;
}

/// A credentials repository whose credentials never arrive.
MockCredentialsRepository quietCredentials() {
  final repository = MockCredentialsRepository();
  when(repository.watchCredentials).thenAnswer((_) => const Stream.empty());
  return repository;
}

/// A jobs repository whose runs never arrive.
MockJobsRepository quietJobs() {
  final repository = MockJobsRepository();
  when(() => repository.watchRunJobs(any()))
      .thenAnswer((_) => const Stream.empty());
  return repository;
}

/// A releases repository whose releases never arrive.
MockReleasesRepository quietReleases() {
  final repository = MockReleasesRepository();
  when(() => repository.watchReleases(projectId: any(named: 'projectId')))
      .thenAnswer((_) => const Stream.empty());
  return repository;
}

/// A runners repository whose runners never arrive.
MockRunnersRepository quietRunners() {
  final repository = MockRunnersRepository();
  when(repository.watchRunners).thenAnswer((_) => const Stream.empty());
  when(repository.runnerUrl).thenAnswer((_) async => const RunnerUrl());
  return repository;
}

/// A tests repository whose baselines and runs never arrive.
MockTestsRepository quietTests() {
  final repository = MockTestsRepository();
  when(() => repository.watchBaselines(any()))
      .thenAnswer((_) => const Stream.empty());
  when(() => repository.completedRuns(any()))
      .thenAnswer((_) => const Stream.empty());
  return repository;
}

/// A storage repository whose report never arrives.
MockStorageRepository quietStorage() {
  final repository = MockStorageRepository();
  when(repository.watchStorage).thenAnswer((_) => const Stream.empty());
  return repository;
}

final at = DateTime.utc(2026, 10, 13, 14, 2);

final localEngine = EngineProfile(
  id: localEngineId,
  name: 'This Mac',
  url: localEngineUrl,
);

final macMini = EngineProfile(
  id: 'mac-mini:7480',
  name: 'mac-mini',
  url: Uri.parse('http://mac-mini:7480'),
);

const mataa = Project(
  id: 'prj_1',
  githubRepoId: 1,
  fullName: 'acme/mataa_new_app',
  remote: 'git@github.com:acme/mataa_new_app.git',
  defaultBaseBranch: 'main',
  profile: ProjectProfile(
    apps: [
      AppProfile(
        name: 'Mataa customer app',
        path: '.',
        flutterVersion: '3.47.6',
        storeCountry: 'ly',
        hasIos: true,
        hasAndroid: true,
        flavors: [
          FlavorProfile(
            name: 'prod',
            entrypoint: 'lib/main_prod.dart',
            iosBundleId: 'com.sixdtec.mata',
            androidAppId: 'com.mataaa',
            shorebird: true,
            prod: true,
          ),
          FlavorProfile(
            name: 'dev',
            entrypoint: 'lib/main_dev.dart',
            iosBundleId: 'com.mataaa.dev',
          ),
        ],
      ),
    ],
  ),
  findings: [
    Finding(
      severity: FindingSeverity.info,
      code: 'shorebird_prod_only',
      message: 'Shorebird enabled for prod only',
      fix: 'Nothing to do.',
    ),
    Finding(
      severity: FindingSeverity.warning,
      code: 'bundle_id_mismatch',
      message: 'iOS dev bundle ID differs from Android',
      fix: 'Use the same ID on both.',
      path: 'ios/Runner.xcodeproj/project.pbxproj',
    ),
  ],
);

const captain = Project(
  id: 'prj_2',
  githubRepoId: 2,
  fullName: 'acme/mataa_captain',
  remote: 'git@github.com:acme/mataa_captain.git',
  defaultBaseBranch: 'main',
  profile: ProjectProfile(
    apps: [
      AppProfile(name: 'captain', path: 'apps/captain'),
      AppProfile(name: 'tablet', path: 'apps/tablet'),
    ],
  ),
  findings: [
    Finding(
      severity: FindingSeverity.error,
      code: 'no_asc_key',
      message: 'No App Store Connect API key',
      fix: 'Add one in Credentials.',
    ),
  ],
);

/// The credential `prod` of `mataa` uses for its App Store Connect key.
final ascKey = Credential(
  id: 'crd_1',
  name: 'Team App Store key',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
  account: 'ABC123DEF4',
  checkedAt: at,
  credentialStatus: CredentialStatus.verified,
  assignmentStatus: CredentialStatus.verified,
);

/// The same key for `dev`, which it cannot reach.
const devAscKey = Credential(
  id: 'crd_1',
  name: 'Team App Store key',
  projectId: 'prj_1',
  app: '.',
  flavor: 'dev',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.rejected,
  account: 'ABC123DEF4',
  message: 'The key cannot see com.mataaa.dev.',
  fix: 'Give the key access to the app.',
  credentialStatus: CredentialStatus.verified,
  assignmentStatus: CredentialStatus.rejected,
);

const playKey = Credential(
  id: 'crd_2',
  projectId: 'prj_1',
  app: 'apps/x',
  flavor: 'prod',
  kind: CredentialKind.playSa,
  status: CredentialStatus.rejected,
  message: 'The service account has no access.',
  fix: 'Give it the Release manager role.',
);

/// The named App Store Connect key, used by `prod` and `dev` of `mataa`.
final teamKey = NamedCredential(
  id: 'crd_1',
  name: 'Team App Store key',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
  account: 'ABC123DEF4',
  checkedAt: at,
  usedBy: const [
    CredentialUsage(
      projectId: 'prj_1',
      project: 'acme/mataa_new_app',
      app: '.',
      flavor: 'prod',
      status: CredentialStatus.verified,
    ),
    CredentialUsage(
      projectId: 'prj_1',
      project: 'acme/mataa_new_app',
      app: '.',
      flavor: 'dev',
      status: CredentialStatus.rejected,
      message: 'The key cannot see com.mataaa.dev.',
    ),
  ],
);

/// A named Play service account the store refuses, used by `captain`.
const playAccountKey = NamedCredential(
  id: 'crd_2',
  name: 'Play release manager',
  kind: CredentialKind.playSa,
  status: CredentialStatus.rejected,
  account: 'release@acme-fake.iam.gserviceaccount.com',
  message: 'The service account has no access.',
  fix: 'Give it the Release manager role.',
  usedBy: [
    CredentialUsage(
      projectId: 'prj_2',
      app: 'apps/captain',
      flavor: 'default',
      status: CredentialStatus.unverified,
    ),
  ],
);

/// A named Slack webhook nobody uses, never checked.
const slackWebhook = NamedCredential(
  id: 'crd_3',
  name: 'Releases channel',
  kind: CredentialKind.slack,
  status: CredentialStatus.unreachable,
);

const slackHook = Credential(
  id: 'crd_3',
  projectId: 'prj_1',
  app: '.',
  flavor: 'dev',
  kind: CredentialKind.slack,
  status: CredentialStatus.unreachable,
);

/// A session over a [MockXpClient] whose events, heartbeat and answers the
/// test drives.
class SessionHarness {
  new(this.profile, {List<Project> projects = const []}) {
    when(client.watchEvents).thenAnswer((_) => events.stream);
    when(client.health).thenAnswer((_) async => const HealthResponse());
    when(client.listProjects).thenAnswer((_) async => projects);
    when(() => client.listCredentials(any())).thenAnswer((_) async => []);
    when(client.listNamedCredentials).thenAnswer((_) async => []);
    when(() => client.listReleases(projectId: any(named: 'projectId')))
        .thenAnswer((_) async => []);
    when(client.listRunners).thenAnswer((_) async => []);
    when(client.getStorage).thenAnswer(
      (_) async => StorageReport(
        generatedAt: at,
        categories: const [],
        flavors: const [],
        retention: const RetentionSettings(),
      ),
    );
    when(
      () => client.listApprovals(
        projectId: any(named: 'projectId'),
        state: any(named: 'state'),
      ),
    ).thenAnswer((_) async => []);
    session = EngineSession(
      profile: profile,
      client: client,
      cache: MemorySnapshotCache(),
      heartbeat: () => heartbeat.stream,
    );
  }

  final EngineProfile profile;
  final client = MockXpClient();
  final events = StreamController<EventStreamItem>.broadcast();
  final heartbeat = StreamController<void>.broadcast();
  late final EngineSession session;

  void send(EngineEvent event) =>
      events.add(EventReceived(SequencedEvent(seq: 1, at: at, event: event)));
}

/// An engine list that knows no engine and no token.
MockEnginesRepository noEngines() {
  final engines = MockEnginesRepository();
  when(engines.load).thenAnswer((_) async => const EngineList());
  when(() => engines.token(any())).thenAnswer((_) async => null);
  return engines;
}

/// Services for the app over fakes. [engines] defaults to a mock that knows
/// no engine.
AppServices testServices({
  EnginesRepository? engines,
  SessionFactory? openSession,
  FakeEngineAgent? agent,
  FakeCliLinker? linker,
  FakeToolChecker? tools,
  FakeLocalEngine? localEngine,
  FolderPicker? pickFolder,
  FilePicker? pickFile,
  FileSaver? saveFile,
  FileRevealer? revealFile,
  FakeNeedsYouAlerts? alerts,
  FakeRunningApp? runningApp,
  FakeAppMenu? appMenu,
  FakeKeychainWiper? keychainWiper,
  FakeDataWiper? dataWiper,
}) => AppServices(
  engines: engines ?? noEngines(),
  openSession:
      openSession ?? (profile, token) => SessionHarness(profile).session,
  agent: agent ?? FakeEngineAgent(),
  linker: linker ?? FakeCliLinker(),
  tools: tools ?? FakeToolChecker(),
  localEngine: localEngine ?? FakeLocalEngine(),
  pickFolder: pickFolder ?? () async => null,
  pickFile: pickFile ?? () async => null,
  saveFile: saveFile ?? (_, _) async => null,
  revealFile: revealFile ?? (_) async {},
  engineLog: '/Users/me/Library/Application Support/XPath/service-logs/xpd.log',
  deviceName: 'MacBook',
  alerts: alerts ?? FakeNeedsYouAlerts(),
  runningApp: runningApp ?? FakeRunningApp(),
  appMenu: appMenu ?? FakeAppMenu(),
  keychainWiper: keychainWiper ?? FakeKeychainWiper(),
  dataWiper: dataWiper ?? FakeDataWiper(),
);
