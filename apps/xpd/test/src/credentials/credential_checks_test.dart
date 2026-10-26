import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';
import 'package:xp_fake_firebase/xp_fake_firebase.dart';
import 'package:xp_fake_play/xp_fake_play.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/credential_fakes.dart';

const _bundleId = 'com.mataa.app';

final _owner = DeviceToken(
  id: 'tok_app',
  name: 'Mac',
  kind: DeviceTokenKind.app,
  hash: 'h',
  createdAt: DateTime.utc(2026),
);

/// The whole of the credential checks against the fake stores: the real
/// clients, the real SQLite repository and the real verifiers, with the
/// programs (`altool`, `keytool`, `shorebird`) behind a fake process runner.
void main() {
  late ManualClock clock;
  late Directory data;
  late SqliteDatabase database;
  late BytesSecretStore secrets;
  late RecordingMasker masker;
  late InMemoryEventLog events;
  late FakeAscServer asc;
  late FakePlayServer play;
  late FakeFirebaseServer firebaseServer;
  late HttpServer github;
  late FakeProcessRunner runner;
  late AppleStores apple;
  late PlayStores playStores;
  late FirebaseStores firebase;
  late CredentialChecks checks;

  Future<Credential> save(Map<String, Object?> material) async =>
      (await checks.service.saveForFlavor(
        'prj_1',
        SaveCredentialRequest(
          flavor: 'prod',
          kind: CredentialKind.fromWire(material['kind']! as String)!,
          material: {...material}..remove('kind'),
        ),
        by: _owner,
      )).credential;

  Map<String, Object?> ascKey({String keyId = fakeAscKeyId}) => {
    'kind': 'asc_key',
    'keyId': keyId,
    'issuerId': fakeAscIssuerId,
    'privateKey': fakeAscPrivateKeyPem,
  };

  GuardRequest guardRequest({List<CredentialKind> kinds = const []}) =>
      GuardRequest(
        input: GuardInput(
          checks: const [GuardCheckName.credentials],
          worktree: const ReleaseWorktree(
            path: '/work/job_1',
            mirror: GitMirror(key: '1', path: '/mirrors/1.git'),
            sha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
          flavorId: 'flv_prod',
          credentialKinds: kinds,
        ),
        workspace: InMemoryWorkspace({}),
        git: _NoGit(),
      );

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 12));
    data = Directory.systemTemp.createTempSync('xpath-credentials-');
    addTearDown(() => data.deleteSync(recursive: true));
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection
      ..execute(
        'INSERT INTO project (id, host, source_key, github_repo_id, remote, '
        "default_base_branch) VALUES ('prj_1', 'github.com', '1', 1, "
        "'https://github.com/a/b.git', 'main')",
      )
      ..execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        "VALUES ('app_1', 'prj_1', '.', 'flutter', 'sa')",
      )
      ..execute(
        'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id, '
        'android_app_id) VALUES '
        "('flv_prod', 'app_1', 'prod', 'lib/main.dart', '$_bundleId', "
        "'$_bundleId')",
      );
    final projects = InMemoryProjectRepository();
    await projects.add(
      ProjectRecord(
        id: 'prj_1',
        host: 'github.com',
        sourceKey: '1',
        githubRepoId: 1,
        fullName: 'o/r',
        remote: 'x',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: clock.now(),
      ),
    );
    secrets = BytesSecretStore();
    masker = RecordingMasker();
    events = InMemoryEventLog(clock: clock);
    asc = await FakeAscServer.start(now: clock.now);
    addTearDown(asc.close);
    asc.addApp(_bundleId);
    play = await FakePlayServer.start(now: clock.now);
    addTearDown(play.close);
    play.addApp(_bundleId);
    firebaseServer = await FakeFirebaseServer.start(now: clock.now);
    addTearDown(firebaseServer.close);
    github = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => github.close(force: true));
    github.listen((request) async {
      final bearer = request.headers.value('authorization');
      request.response
        ..statusCode = bearer == 'Bearer ghp_good' ? 200 : 401
        ..write(jsonEncode({'login': 'octocat'}));
      await request.response.close();
    });
    runner = FakeProcessRunner(
      (call) => const ProcessOutput(exitCode: 0, stdout: 'ok'),
    );
    apple = AppleStores(
      database: database,
      secrets: secrets,
      clock: clock,
      ascBaseUrl: asc.baseUrl,
      itunesBaseUrl: asc.baseUrl,
    );
    addTearDown(apple.close);
    playStores = PlayStores(
      database: database,
      secrets: secrets,
      clock: clock,
      apiBaseUrl: play.baseUrl,
      uploadBaseUrl: play.baseUrl,
    );
    addTearDown(playStores.close);
    firebase = FirebaseStores(clock: clock, baseUrl: firebaseServer.baseUrl);
    addTearDown(firebase.close);
    checks = CredentialChecks(
      database: database,
      secrets: secrets,
      projects: projects,
      runner: runner,
      masker: masker,
      events: events,
      clock: clock,
      apple: apple,
      play: playStores,
      firebase: firebase,
      dataDir: data.path,
      isMacOS: true,
      githubBaseUrl: Uri.parse('http://localhost:${github.port}'),
    );
    addTearDown(checks.close);
  });

  test(
    'keeps the files of keystores under tmp/credentials of the data dir',
    () {
      expect(checks.temporaryFiles.root, '${data.path}/tmp/credentials');
    },
  );

  group('an ASC key', () {
    test('is saved when App Store Connect accepts it', () async {
      final credential = await save(ascKey());

      expect(credential.status, CredentialStatus.verified);
      expect(credential.account, fakeAscKeyId);
      final stored = (await checks.repository.get(credential.id))!;
      expect(
        AscKey.fromSecret(secrets.text(stored.secretKey)!).keyId,
        fakeAscKeyId,
      );
      // The same secret serves the upload steps: the source finds it here.
      expect(
        (await apple.credentials.forBundleId(_bundleId))?.keyId,
        fakeAscKeyId,
      );
      // The key on its own, then the key for the flavor's app.
      expect(asc.requests, hasLength(3));
      expect(asc.requests.first.uri.queryParameters['limit'], '1');
      expect(
        asc.requests.last.uri.queryParameters['filter[bundleId]'],
        _bundleId,
      );
    });

    test('is refused with a fix when Apple does not know the key', () async {
      await expectLater(
        save(ascKey(keyId: 'WRONGKEY01')),
        throwsA(
          isA<CredentialRejectedException>().having(
            (e) => e.described,
            'described',
            allOf(contains('WRONGKEY01'), contains('Create a new key')),
          ),
        ),
      );
      expect(await checks.repository.list(), isEmpty);
      expect(secrets.values, isEmpty);
    });

    test('fails preflight once Apple revokes it, before any build', () async {
      await save(ascKey());
      expect(
        (await checks.guardCheck.run(guardRequest())).status,
        GuardStatus.passed,
      );

      asc.failNext(401, code: 'NOT_AUTHORIZED', title: 'Revoked');
      clock.advance(const Duration(days: 1));
      await checks.health.runNow();
      final result = await checks.guardCheck.run(guardRequest());

      expect(result.status, GuardStatus.failed);
      expect(result.message, contains('asc_key'));
      expect(result.fix, contains('Create a new key in App Store Connect'));
      await expectLater(
        events.subscribe(after: 0).map((e) => e.event),
        emitsThrough(isA<CredentialExpired>()),
      );
    });
  });

  group('an Apple Distribution identity (ADR 0014)', () {
    Map<String, Object?> identity() => {
      'kind': 'apple_distribution',
      'privateKey':
          '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n',
      'certificate': fakeDistributionCertificate,
    };

    void listCertificate() => asc.certificates['cert-1'] = FakeAscCertificate(
      id: 'cert-1',
      serialNumber: fakeDistributionSerial,
      certificateType: 'DISTRIBUTION',
      content: base64.decode(fakeDistributionCertificate),
    );

    test('is accepted for a flavor when its team lists the certificate, and '
        'the engine makes its profile', () async {
      await save(ascKey());
      listCertificate();
      asc.bundleIds[_bundleId] = 'bundle-1';

      final credential = await save(identity());
      final stored = (await checks.repository.get(credential.id))!;
      final profile = await checks.profiles.profile(
        'prj_1',
        AppStoreProfiles.keyFor(stored.secretKey, _bundleId),
      );

      expect(credential.status, CredentialStatus.verified);
      expect(credential.account, 'Apple Distribution: XPath Test (TEAM123456)');
      expect(utf8.decode(profile), contains('bundle-1 cert-1'));
      expect(asc.profiles.values.single.name, 'XPath $_bundleId A1B2C3D4E5F');
    });

    test('is refused for a flavor when the certificate was revoked', () async {
      await save(ascKey());

      final credential = await save(identity());

      expect(credential.status, CredentialStatus.rejected);
      expect(credential.message, contains('it was revoked'));
    });
  });

  group('an Apple ID', () {
    Map<String, Object?> appleId() => {
      'kind': 'apple_id',
      'appleId': 'dev@example.com',
      'password': 'abcd-efgh-ijkl-mnop',
    };

    test(
      'is checked with altool, the password only in the environment',
      () async {
        final credential = await save(appleId());

        expect(credential.status, CredentialStatus.verified);
        expect(credential.account, 'dev@example.com');
        final call = runner.calls.single;
        expect(call.arguments.join(' '), isNot(contains('abcd-efgh')));
        expect(call.environment, {
          'XPATH_ASC_APP_PASSWORD': 'abcd-efgh-ijkl-mnop',
        });
        expect(masker.secrets, contains('abcd-efgh-ijkl-mnop'));
      },
    );

    test('fails preflight once the app-specific password is revoked', () async {
      await save(appleId());
      runner.handler = (call) => const ProcessOutput(
        exitCode: 1,
        stderr: 'ERROR: Unable to authenticate. (-22938)',
      );
      clock.advance(const Duration(days: 1));

      await checks.health.runNow();
      final result = await checks.guardCheck.run(
        guardRequest(kinds: [CredentialKind.appleId]),
      );

      expect(result.status, GuardStatus.failed);
      expect(result.fix, contains('Create a new app-specific password'));
    });
  });

  group('service accounts', () {
    test('a Play account must be accepted by Google and the app', () async {
      final credential = await save({
        'kind': 'play_sa',
        'serviceAccount': play.serviceAccountJson(),
      });

      expect(credential.status, CredentialStatus.verified);
      expect(credential.account, fakePlayClientEmail);
      expect(
        (await playStores.credentials.forAndroidAppId(_bundleId))?.clientEmail,
        fakePlayClientEmail,
      );
    });

    test('a Play account Google does not know is refused', () async {
      await expectLater(
        save({
          'kind': 'play_sa',
          'serviceAccount': play.serviceAccountJson(
            privateKeyPem: fakePlayOtherPrivateKeyPem,
          ),
        }),
        throwsA(isA<CredentialRejectedException>()),
      );
    });

    test('a Firebase account must be accepted by Google', () async {
      final credential = await save({
        'kind': 'firebase_sa',
        'serviceAccount': firebaseServer.serviceAccountJson(),
      });

      expect(credential.status, CredentialStatus.verified);
      expect(credential.account, fakePlayClientEmail);
    });

    test('a deleted Firebase key is found by the health check', () async {
      final credential = await save({
        'kind': 'firebase_sa',
        'serviceAccount': firebaseServer.serviceAccountJson(),
      });
      // The key is deleted in Google Cloud: the stored file no longer works.
      secrets.values['credential.${credential.id}'] = utf8.encode(
        firebaseServer.serviceAccountJson(
          privateKeyPem: fakePlayOtherPrivateKeyPem,
        ),
      );
      clock.advance(const Duration(days: 1));

      await checks.health.runNow();

      final record = (await checks.repository.get(credential.id))!;
      expect(record.status, CredentialStatus.rejected);
      expect(record.check.message, contains('Google refused'));
    });
  });

  group('a keystore', () {
    test('is checked with keytool on a private temporary file', () async {
      final credential = await save({
        'kind': 'keystore',
        'keystore': base64.encode([1, 2, 3]),
        'storePassword': 'store-pass',
        'keyAlias': 'upload',
      });

      expect(credential.status, CredentialStatus.verified);
      expect(credential.account, 'upload');
      final call = runner.calls.single;
      expect(call.executable, 'keytool');
      expect(call.arguments, contains('-storepass:env'));
      expect(call.arguments.join(' '), isNot(contains('store-pass')));
      expect(
        Directory('${data.path}/tmp/credentials').listSync(),
        isEmpty,
        reason: 'the file is deleted after the check',
      );
    });
  });

  group('a Shorebird key', () {
    test('is checked with the CLI, the key in the environment', () async {
      runner.handler = (call) => const ProcessOutput(
        exitCode: 0,
        stdout: '{"status": "success", "data": {"email": "dev@example.com"}}',
      );

      final credential = await save({
        'kind': 'shorebird',
        'token': 'sb_api_abc',
      });

      expect(credential.account, 'dev@example.com');
      expect(runner.calls.single.environment?['SHOREBIRD_TOKEN'], 'sb_api_abc');
    });

    test('is refused without the sb_api_ prefix', () async {
      await expectLater(
        save({'kind': 'shorebird', 'token': 'old-login-token'}),
        throwsA(isA<CredentialRejectedException>()),
      );
      expect(runner.calls, isEmpty);
    });
  });

  group('a GitHub token', () {
    test('is checked with GET /user', () async {
      final credential = await save({'kind': 'github', 'token': 'ghp_good'});

      expect(credential.account, 'octocat');
      expect(secrets.text(githubTokenSecretKey), 'ghp_good');
    });

    test('is refused when GitHub says 401', () async {
      await expectLater(
        save({'kind': 'github', 'token': 'ghp_bad'}),
        throwsA(isA<CredentialRejectedException>()),
      );
    });
  });

  group('a Slack webhook', () {
    test('only has its shape checked', () async {
      final credential = await save({
        'kind': 'slack',
        'webhookUrl': 'https://hooks.slack.com/services/T/B/X',
      });

      expect(credential.status, CredentialStatus.verified);
      await expectLater(
        save({'kind': 'slack', 'webhookUrl': 'https://example.com/x'}),
        throwsA(isA<CredentialRejectedException>()),
      );
    });
  });

  group('the health check', () {
    test('checks the credentials that are due when it starts', () async {
      final credential = await save(ascKey());
      clock.advance(const Duration(days: 1));
      asc.failNext(401);

      await checks.health.start();

      final record = (await checks.repository.get(credential.id))!;
      expect(record.status, CredentialStatus.rejected);
      expect(checks.health.isRunning, isTrue);
      checks.close();
      expect(checks.health.isRunning, isFalse);
    });

    test('a named key shared by flavors is checked for each app', () async {
      database.connection.execute(
        'INSERT INTO flavor (id, app_id, name, entrypoint, ios_bundle_id) '
        "VALUES ('flv_dev', 'app_1', 'dev', 'lib/main.dart', 'com.other.app')",
      );
      final key = await checks.service.create(
        CreateCredentialRequest(
          name: 'Personal Apple Dev Account',
          kind: CredentialKind.ascKey,
          material: {...ascKey()}..remove('kind'),
        ),
        by: _owner,
      );

      final assigned = await checks.service.assign(
        'prj_1',
        app: '.',
        flavor: 'prod',
        kind: CredentialKind.ascKey,
        request: AssignCredentialRequest(
          credentialId: key.id,
          allFlavors: true,
        ),
        by: _owner,
      );

      expect(
        {
          for (final credential in assigned.assigned)
            credential.flavor: credential.assignmentStatus,
        },
        {'dev': CredentialStatus.rejected, 'prod': CredentialStatus.verified},
      );
      expect(
        (await checks.guardCheck.run(guardRequest())).status,
        GuardStatus.passed,
      );
    });

    test('checks every day', () {
      expect(checks.health.interval, const Duration(hours: 24));
    });
  });
}

class _NoGit implements GitService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('The credentials check does not use git.');
}
