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

final ascKey = Credential(
  id: 'crd_1',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
  account: 'FANNAK',
  checkedAt: at,
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
  deviceName: 'MacBook',
);
