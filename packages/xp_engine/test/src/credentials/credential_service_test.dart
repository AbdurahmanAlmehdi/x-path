import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/credential_harness.dart';
import '../../helpers/job_harness.dart';

class _FailingRepository extends InMemoryCredentialRepository {
  new(super.flavors);

  bool failing = true;

  @override
  Future<void> save(CredentialRecord record) =>
      failing ? throw StateError('disk on fire') : super.save(record);
}

const _dev = CredentialFlavor(
  id: 'flv_2',
  projectId: 'prj_1',
  appPath: '.',
  name: 'dev',
  iosBundleId: 'com.mataa.app.dev',
  androidAppId: 'com.mataa.app.dev',
);

const _captain = CredentialFlavor(
  id: 'flv_3',
  projectId: 'prj_1',
  appPath: 'apps/captain',
  name: 'prod',
);

void main() {
  final owner = tokenOf(DeviceTokenKind.app);
  final cli = tokenOf(DeviceTokenKind.cli);
  final mcp = tokenOf(DeviceTokenKind.mcp);
  late InMemoryCredentialRepository repository;
  late InMemoryProjectRepository projects;
  late BytesSecretStore secrets;
  late ReplacingMasker masker;
  late InMemoryEventLog events;
  late ManualClock clock;
  late Map<CredentialKind, FakeCredentialVerifier> verifiers;
  late CredentialService service;

  CredentialService build([CredentialRepository? repo]) => CredentialService(
    repository: repo ?? repository,
    projects: projects,
    secrets: secrets,
    verifiers: verifiers.values,
    masker: masker,
    events: events,
    clock: clock,
  );

  CreateCredentialRequest create(
    CredentialKind kind, {
    String? name,
    Map<String, dynamic>? material,
  }) => CreateCredentialRequest(
    name: name ?? kind.label,
    kind: kind,
    material: material ?? credentialFields(kind),
  );

  SaveCredentialRequest legacy(
    CredentialKind kind, {
    String app = '.',
    String flavor = 'prod',
    String? name,
    Map<String, dynamic>? material,
  }) => SaveCredentialRequest(
    app: app,
    flavor: flavor,
    kind: kind,
    name: name,
    material: material ?? credentialFields(kind),
  );

  Future<AssignCredentialResponse> assign(
    String credentialId,
    CredentialKind kind, {
    String app = '.',
    String flavor = 'prod',
    bool allFlavors = false,
    bool replace = false,
    DeviceToken? by,
  }) => service.assign(
    'prj_1',
    app: app,
    flavor: flavor,
    kind: kind,
    request: AssignCredentialRequest(
      credentialId: credentialId,
      allFlavors: allFlavors,
      replace: replace,
    ),
    by: by ?? owner,
  );

  Future<List<EngineEvent>> logged() async {
    final entries = <EngineEvent>[];
    final subscription = events
        .subscribe(after: 0)
        .listen((entry) => entries.add(entry.event));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return entries;
  }

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    repository = InMemoryCredentialRepository([testFlavor, _dev, _captain]);
    projects = InMemoryProjectRepository();
    await projects.add(
      ProjectRecord(
        id: 'prj_1',
        host: 'github.com',
        sourceKey: '1',
        githubRepoId: 1,
        fullName: 'acme/shop',
        remote: 'https://github.com/acme/shop.git',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      ),
    );
    secrets = BytesSecretStore();
    masker = ReplacingMasker();
    events = InMemoryEventLog(clock: clock);
    verifiers = {
      for (final kind in CredentialKind.values)
        kind: FakeCredentialVerifier(kind),
    };
    service = build();
  });

  group('create', () {
    test('verifies on its own, stores the secret and the record', () async {
      final created = await service.create(
        create(CredentialKind.ascKey, name: ' Personal Apple Dev Account '),
        by: owner,
      );

      expect(created.id, startsWith('crd_'));
      expect(created.name, 'Personal Apple Dev Account');
      expect(created.kind, CredentialKind.ascKey);
      expect(created.status, CredentialStatus.verified);
      expect(created.account, 'ABC123DEF4');
      expect(created.verifiedAt, clock.now());
      expect(created.usedBy, isEmpty);
      final stored = (await repository.get(created.id))!;
      expect(stored.secretKey, 'credential.${created.id}');
      expect(
        AscKey.fromSecret(secrets.text(stored.secretKey)!).keyId,
        'ABC123DEF4',
      );
      expect(
        verifiers[CredentialKind.ascKey]!.targets.single,
        const CredentialTarget(),
      );
      expect(await logged(), [
        CredentialSaved(
          credentialId: created.id,
          name: 'Personal Apple Dev Account',
          kind: CredentialKind.ascKey,
          replaced: false,
        ),
      ]);
    });

    test('a cli token may create credentials too', () async {
      final created = await service.create(
        create(CredentialKind.slack),
        by: cli,
      );

      expect(created.kind, CredentialKind.slack);
    });

    test('keeps the account the check found out', () async {
      verifiers[CredentialKind.shorebird]!.answers.add(
        const VerificationResult.verified(account: 'dev@example.com'),
      );

      final created = await service.create(
        create(CredentialKind.shorebird),
        by: owner,
      );

      expect(created.account, 'dev@example.com');
    });

    test('lets the masker learn the secrets, refused ones too', () async {
      verifiers[CredentialKind.appleId]!.answers.add(
        const VerificationResult.rejected('No.'),
      );

      await expectLater(
        service.create(create(CredentialKind.appleId), by: owner),
        throwsA(isA<CredentialRejectedException>()),
      );
      await service.create(create(CredentialKind.keystore), by: owner);

      expect(masker.secrets, contains('abcd-efgh-ijkl-mnop'));
      expect(masker.secrets, contains('store-pass'));
    });

    test('stores nothing when the store refuses the credential', () async {
      verifiers[CredentialKind.ascKey]!.answers.add(
        const VerificationResult.rejected('Revoked.', fix: 'Make a new one.'),
      );

      await expectLater(
        service.create(create(CredentialKind.ascKey), by: owner),
        throwsA(
          isA<CredentialRejectedException>()
              .having((e) => e.message, 'message', 'Revoked.')
              .having((e) => e.fix, 'fix', 'Make a new one.'),
        ),
      );
      expect(await repository.list(), isEmpty);
      expect(secrets.values, isEmpty);
    });

    test('stores nothing when the check could not be made', () async {
      verifiers[CredentialKind.ascKey]!.answers.addAll([
        const VerificationResult.unreachable('Offline.', fix: 'Retry.'),
      ]);

      await expectLater(
        service.create(create(CredentialKind.ascKey), by: owner),
        throwsA(
          isA<CredentialUnreachableException>()
              .having((e) => e.message, 'message', 'Offline.')
              .having((e) => e.fix, 'fix', 'Retry.'),
        ),
      );
      expect(await repository.list(), isEmpty);
    });

    test('says so when the check gave no reason', () async {
      verifiers[CredentialKind.ascKey] = _AnsweringVerifier(
        CredentialKind.ascKey,
        const _Unverified(),
      );
      service = build();

      await expectLater(
        service.create(create(CredentialKind.ascKey), by: owner),
        throwsA(
          isA<CredentialUnreachableException>().having(
            (e) => e.message,
            'message',
            'The credential could not be checked.',
          ),
        ),
      );
    });

    test('refuses a kind it has no verifier for', () async {
      verifiers.remove(CredentialKind.slack);
      service = build();

      await expectLater(
        service.create(create(CredentialKind.slack), by: owner),
        throwsA(isA<CredentialRejectedException>()),
      );
    });

    test('refuses a GitHub token: the engine has one', () async {
      await expectLater(
        service.create(create(CredentialKind.github), by: owner),
        throwsA(
          isA<CredentialRequestException>().having(
            (e) => e.message,
            'message',
            contains('PUT /github-token'),
          ),
        ),
      );
    });

    test('refuses a name another credential has, in any case', () async {
      await service.create(
        create(CredentialKind.ascKey, name: 'Personal'),
        by: owner,
      );

      await expectLater(
        service.create(
          create(CredentialKind.shorebird, name: 'PERSONAL'),
          by: owner,
        ),
        throwsA(isA<CredentialConflictException>()),
      );
      expect(verifiers[CredentialKind.shorebird]!.checked, isEmpty);
    });

    test('refuses a name that cannot be one', () async {
      await expectLater(
        service.create(create(CredentialKind.slack, name: '  '), by: owner),
        throwsA(isA<CredentialRequestException>()),
      );
    });

    test('refuses malformed fields', () async {
      await expectLater(
        service.create(
          create(CredentialKind.shorebird, material: const {}),
          by: owner,
        ),
        throwsA(isA<CredentialRequestException>()),
      );
    });

    test('an mcp token may not add credentials', () async {
      await expectLater(
        service.create(create(CredentialKind.slack), by: mcp),
        throwsA(
          isA<CredentialForbiddenException>().having(
            (e) => e.message,
            'message',
            'A mcp token cannot add credentials: only the app or `xp` do.',
          ),
        ),
      );
    });

    test('erases the new secret when the record cannot be stored', () async {
      service = build(_FailingRepository([testFlavor]));

      await expectLater(
        service.create(create(CredentialKind.shorebird), by: owner),
        throwsStateError,
      );

      expect(secrets.values, isEmpty);
    });

    test('lets a locked secret store through', () async {
      secrets.failure = const SecretsLockedException('locked');

      await expectLater(
        service.create(create(CredentialKind.shorebird), by: owner),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(await repository.list(), isEmpty);
    });

    test('runs one change at a time', () async {
      final gate = Completer<void>();
      final slow = _SlowVerifier(gate.future);
      verifiers[CredentialKind.shorebird] = slow;
      service = build();

      final first = service.create(
        create(CredentialKind.shorebird, name: 'One'),
        by: owner,
      );
      final second = service.create(
        create(CredentialKind.shorebird, name: 'one'),
        by: owner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(slow.started, 1);
      gate.complete();

      expect((await first).name, 'One');
      await expectLater(second, throwsA(isA<CredentialConflictException>()));
    });
  });

  group('reads', () {
    late NamedCredential key;
    late NamedCredential slack;

    setUp(() async {
      key = await service.create(create(CredentialKind.ascKey), by: owner);
      slack = await service.create(create(CredentialKind.slack), by: owner);
      await assign(key.id, CredentialKind.ascKey, allFlavors: true);
      await assign(slack.id, CredentialKind.slack, app: 'apps/captain');
    });

    test('lists the credentials by name, with their usages', () async {
      final listed = await service.list();

      expect(listed.map((c) => c.name), [
        'App Store Connect API key',
        'Slack webhook',
      ]);
      expect(listed.first.usedBy.map((u) => '${u.app} ${u.flavor}'), [
        '. dev',
        '. prod',
      ]);
      expect(listed.last.usedBy.single.app, 'apps/captain');
    });

    test('gets one with its usages', () async {
      final got = await service.get(key.id);

      expect(got.usedBy, hasLength(2));
      await expectLater(
        service.get('crd_nope'),
        throwsA(isA<CredentialNotFoundException>()),
      );
    });

    test('lists what each flavor of a project uses', () async {
      final all = await service.listForProject('prj_1');

      expect(all.map((c) => '${c.app} ${c.flavor} ${c.kind.wire}'), [
        '. dev asc_key',
        '. prod asc_key',
        'apps/captain prod slack',
      ]);
      expect(all.first.name, 'App Store Connect API key');
      expect(all.first.credentialStatus, CredentialStatus.verified);
      expect(all.first.toJson().toString(), isNot(contains('MIGT')));
    });

    test('narrows to a flavor, the root app by default', () async {
      expect(
        (await service.listForProject('prj_1', flavor: 'dev')).single.flavor,
        'dev',
      );
      expect(
        (await service.listForProject(
          'prj_1',
          app: 'apps/captain',
          flavor: 'prod',
        )).single.kind,
        CredentialKind.slack,
      );
    });

    test('refuses an unknown project or flavor, and an app alone', () async {
      await expectLater(
        service.listForProject('prj_9'),
        throwsA(isA<ProjectNotFoundException>()),
      );
      await expectLater(
        service.listForProject('prj_1', flavor: 'staging'),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.listForProject('prj_1', app: '.'),
        throwsA(isA<CredentialRequestException>()),
      );
    });
  });

  group('rename', () {
    late NamedCredential key;

    setUp(() async {
      key = await service.create(create(CredentialKind.ascKey), by: owner);
      await assign(key.id, CredentialKind.ascKey);
    });

    test('keeps the id, the secret and the assignments', () async {
      final renamed = await service.rename(
        key.id,
        ' Mataa Apple Dev Account ',
        by: owner,
      );

      expect(renamed.id, key.id);
      expect(renamed.name, 'Mataa Apple Dev Account');
      expect(renamed.usedBy, hasLength(1));
      expect(
        (await repository.assignment(
          'flv_1',
          CredentialKind.ascKey,
        ))!.credential.name,
        'Mataa Apple Dev Account',
      );
      expect(
        (await logged()).last,
        CredentialRenamed(
          credentialId: key.id,
          kind: CredentialKind.ascKey,
          name: 'Mataa Apple Dev Account',
        ),
      );
    });

    test('may change only the case of its own name', () async {
      final renamed = await service.rename(
        key.id,
        'APP STORE CONNECT API KEY',
        by: owner,
      );

      expect(renamed.name, 'APP STORE CONNECT API KEY');
    });

    test('does nothing for the same name', () async {
      final before = (await logged()).length;

      await service.rename(key.id, key.name, by: owner);

      expect(await logged(), hasLength(before));
    });

    test('refuses a name another credential has', () async {
      await service.create(
        create(CredentialKind.slack, name: 'Team'),
        by: owner,
      );

      await expectLater(
        service.rename(key.id, 'team', by: owner),
        throwsA(isA<CredentialConflictException>()),
      );
    });

    test(
      'refuses a bad name, an unknown credential and an mcp token',
      () async {
        await expectLater(
          service.rename(key.id, '', by: owner),
          throwsA(isA<CredentialRequestException>()),
        );
        await expectLater(
          service.rename('crd_nope', 'x', by: owner),
          throwsA(isA<CredentialNotFoundException>()),
        );
        await expectLater(
          service.rename(key.id, 'x', by: mcp),
          throwsA(isA<CredentialForbiddenException>()),
        );
      },
    );
  });

  group('replace', () {
    late NamedCredential token;

    setUp(() async {
      token = await service.create(
        create(CredentialKind.shorebird, name: 'Studio'),
        by: owner,
      );
      await assign(token.id, CredentialKind.shorebird, allFlavors: true);
    });

    test('stores the new secret under the same id and name', () async {
      clock.advance(const Duration(hours: 1));

      final replaced = await service.replace(
        token.id,
        const ReplaceCredentialRequest({'token': 'sb_api_new'}),
        by: owner,
      );

      expect(replaced.id, token.id);
      expect(replaced.name, 'Studio');
      expect(replaced.checkedAt, clock.now());
      expect(replaced.usedBy, hasLength(2));
      expect(secrets.text('credential.${token.id}'), 'sb_api_new');
      expect(masker.secrets, contains('sb_api_new'));
      final logs = await logged();
      expect(
        logs,
        contains(
          CredentialSaved(
            credentialId: token.id,
            name: 'Studio',
            kind: CredentialKind.shorebird,
            replaced: true,
          ),
        ),
      );
      expect(
        replaced.usedBy.map((usage) => usage.checkedAt),
        everyElement(clock.now()),
      );
    });

    test('changes nothing when the new secret is refused', () async {
      verifiers[CredentialKind.shorebird]!.answers.add(
        const VerificationResult.rejected('Not a key.'),
      );

      await expectLater(
        service.replace(
          token.id,
          const ReplaceCredentialRequest({'token': 'nope'}),
          by: owner,
        ),
        throwsA(isA<CredentialRejectedException>()),
      );
      expect(secrets.text('credential.${token.id}'), 'sb_api_abc123');
    });

    test('refuses an unknown credential and an mcp token', () async {
      await expectLater(
        service.replace(
          'crd_nope',
          const ReplaceCredentialRequest({'token': 'x'}),
          by: owner,
        ),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.replace(
          token.id,
          const ReplaceCredentialRequest({'token': 'x'}),
          by: mcp,
        ),
        throwsA(isA<CredentialForbiddenException>()),
      );
    });
  });

  group('verify', () {
    late NamedCredential play;

    setUp(() async {
      verifiers[CredentialKind.playSa]!.checksTarget = true;
      play = await service.create(create(CredentialKind.playSa), by: owner);
      await assign(play.id, CredentialKind.playSa, allFlavors: true);
      verifiers[CredentialKind.playSa]!
        ..targets.clear()
        ..checked.clear();
    });

    test('checks the credential, then each flavor with its ids', () async {
      clock.advance(const Duration(hours: 1));
      verifiers[CredentialKind.playSa]!.answers.addAll([
        const VerificationResult.verified(),
        const VerificationResult.verified(),
        const VerificationResult.rejected(
          'Google Play does not know com.mataa.app.',
          fix: 'Invite the account.',
        ),
      ]);

      final checked = await service.verify(play.id, by: owner);

      expect(verifiers[CredentialKind.playSa]!.targets, [
        const CredentialTarget(),
        const CredentialTarget(
          iosBundleId: 'com.mataa.app.dev',
          androidAppId: 'com.mataa.app.dev',
        ),
        const CredentialTarget(
          iosBundleId: 'com.mataa.app',
          androidAppId: 'com.mataa.app',
        ),
      ]);
      expect(checked.status, CredentialStatus.verified);
      expect(checked.checkedAt, clock.now());
      expect(checked.usedBy.map((usage) => usage.status), [
        CredentialStatus.verified,
        CredentialStatus.rejected,
      ]);
      expect(checked.usedBy.last.message, contains('does not know'));
      final prod = (await service.listForProject(
        'prj_1',
        flavor: 'prod',
      )).single;
      expect(prod.status, CredentialStatus.rejected);
      expect(prod.fix, 'Invite the account.');
      final logs = await logged();
      expect(
        logs,
        contains(
          CredentialExpired(
            credentialId: play.id,
            name: play.name,
            projectId: 'prj_1',
            app: '.',
            flavor: 'prod',
            kind: CredentialKind.playSa,
            message:
                'Google Play does not know com.mataa.app. Invite the '
                'account.',
          ),
        ),
      );
      expect(
        logs,
        contains(
          CredentialVerified(
            credentialId: play.id,
            projectId: 'prj_1',
            app: '.',
            flavor: 'dev',
            kind: CredentialKind.playSa,
            status: CredentialStatus.verified,
          ),
        ),
      );
    });

    test('announces an expiry of the credential once', () async {
      verifiers[CredentialKind.playSa]!.answers.addAll([
        const VerificationResult.rejected('Deleted.', fix: 'Make a new one.'),
        const VerificationResult.rejected('Deleted.'),
      ]);

      final first = await service.verify(play.id, by: owner);
      await service.verify(play.id, by: owner);

      expect(first.status, CredentialStatus.rejected);
      expect(
        first.usedBy.map((usage) => usage.status),
        everyElement(CredentialStatus.rejected),
      );
      expect(first.usedBy.first.message, isNull);
      final expired = (await logged()).whereType<CredentialExpired>();
      expect(expired, [
        CredentialExpired(
          credentialId: play.id,
          name: play.name,
          kind: CredentialKind.playSa,
          message: 'Deleted. Make a new one.',
        ),
      ]);
      expect(
        verifiers[CredentialKind.playSa]!.targets,
        everyElement(const CredentialTarget()),
        reason: 'a refused credential is not checked for its flavors',
      );
    });

    test('a kind that does not look at flavors takes its status', () async {
      final slack = await service.create(
        create(CredentialKind.slack),
        by: owner,
      );
      await assign(slack.id, CredentialKind.slack);
      verifiers[CredentialKind.slack]!.answers.add(
        const VerificationResult.unreachable('Offline.'),
      );

      final checked = await service.verify(slack.id, by: owner);

      expect(checked.status, CredentialStatus.unreachable);
      expect(checked.usedBy.single.status, CredentialStatus.unreachable);
      expect(verifiers[CredentialKind.slack]!.checked, hasLength(2));
    });

    test('rejects a credential whose secret is gone', () async {
      secrets.values.clear();

      final checked = await service.verify(play.id, by: owner);

      expect(checked.status, CredentialStatus.rejected);
      expect(checked.message, contains('missing from the secret store'));
      expect(checked.fix, 'Replace the secret of the credential.');
      expect(verifiers[CredentialKind.playSa]!.checked, isEmpty);
    });

    test('rejects a credential whose secret is damaged', () async {
      await secrets.write('credential.${play.id}', 'not json');

      final checked = await service.verify(play.id, by: owner);

      expect(checked.status, CredentialStatus.rejected);
      expect(checked.message, contains('cannot be used'));
    });

    test('cannot check a kind without a verifier, and says so', () async {
      verifiers.remove(CredentialKind.playSa);
      service = build();

      final checked = await service.verify(play.id, by: owner);

      expect(checked.status, CredentialStatus.unreachable);
      expect(checked.message, contains('cannot check play_sa'));
      expect(checked.usedBy.first.status, CredentialStatus.unreachable);
    });

    test('refuses an unknown credential and an mcp token', () async {
      await expectLater(
        service.verify('crd_nope', by: owner),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.verify(play.id, by: mcp),
        throwsA(isA<CredentialForbiddenException>()),
      );
    });
  });

  group('remove', () {
    late NamedCredential key;

    setUp(() async {
      key = await service.create(create(CredentialKind.keystore), by: owner);
    });

    test('deletes an unused credential with its secret', () async {
      await service.remove(key.id, by: owner);

      expect(await repository.get(key.id), isNull);
      expect(secrets.values, isEmpty);
      expect(
        (await logged()).last,
        CredentialRemoved(credentialId: key.id, kind: CredentialKind.keystore),
      );
    });

    test('refuses one in use and says where, unless forced', () async {
      await assign(key.id, CredentialKind.keystore, allFlavors: true);

      await expectLater(
        service.remove(key.id, by: owner),
        throwsA(
          isA<CredentialInUseException>()
              .having(
                (e) => e.message,
                'message',
                '"Android keystore" is used by prj_1 dev, prj_1 prod. Delete '
                    'it with force to remove it from them too.',
              )
              .having((e) => e.usedBy.map((usage) => usage.flavor), 'usedBy', [
                'dev',
                'prod',
              ]),
        ),
      );
      expect(await repository.get(key.id), isNotNull);

      await service.remove(key.id, by: owner, force: true);

      expect(await repository.get(key.id), isNull);
      expect(await repository.assignments(), isEmpty);
      expect((await logged()).whereType<CredentialUnassigned>(), hasLength(2));
    });

    test('leaves a secret another credential shares', () async {
      await repository.save(
        CredentialRecord(
          id: 'crd_twin',
          name: 'Twin',
          kind: CredentialKind.keystore,
          secretKey: 'credential.${key.id}',
        ),
      );

      await service.remove(key.id, by: owner);

      expect(secrets.values, isNotEmpty);
    });

    test('refuses an unknown credential and an mcp token', () async {
      await expectLater(
        service.remove('crd_nope', by: owner),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.remove(key.id, by: mcp, force: true),
        throwsA(isA<CredentialForbiddenException>()),
      );
    });
  });

  group('assign', () {
    late NamedCredential personal;
    late NamedCredential studio;

    setUp(() async {
      verifiers[CredentialKind.ascKey]!.checksTarget = true;
      personal = await service.create(
        create(CredentialKind.ascKey, name: 'Personal'),
        by: owner,
      );
      studio = await service.create(
        create(CredentialKind.ascKey, name: 'Studio'),
        by: owner,
      );
      verifiers[CredentialKind.ascKey]!.targets.clear();
    });

    test('gives this flavor the credential and checks it there', () async {
      final result = await assign(personal.id, CredentialKind.ascKey);

      expect(result.kept, isEmpty);
      final assigned = result.assigned.single;
      expect(assigned.flavor, 'prod');
      expect(assigned.name, 'Personal');
      expect(assigned.status, CredentialStatus.verified);
      expect(assigned.assignmentStatus, CredentialStatus.verified);
      expect(
        verifiers[CredentialKind.ascKey]!.targets.single.iosBundleId,
        'com.mataa.app',
      );
      expect(
        await logged(),
        containsAllInOrder([
          CredentialAssigned(
            credentialId: personal.id,
            projectId: 'prj_1',
            app: '.',
            flavor: 'prod',
            kind: CredentialKind.ascKey,
          ),
          CredentialVerified(
            credentialId: personal.id,
            projectId: 'prj_1',
            app: '.',
            flavor: 'prod',
            kind: CredentialKind.ascKey,
            status: CredentialStatus.verified,
          ),
        ]),
      );
    });

    test('keeps an assignment that its check refuses', () async {
      verifiers[CredentialKind.ascKey]!.answers.add(
        const VerificationResult.rejected('No app.'),
      );

      final result = await assign(personal.id, CredentialKind.ascKey);

      expect(result.assigned.single.status, CredentialStatus.rejected);
      expect(result.assigned.single.message, 'No app.');
      expect(
        await repository.assignment('flv_1', CredentialKind.ascKey),
        isNotNull,
      );
      expect((await logged()).whereType<CredentialExpired>(), isEmpty);
    });

    test('replaces what this flavor had, and says so', () async {
      await assign(studio.id, CredentialKind.ascKey);

      await assign(personal.id, CredentialKind.ascKey);

      expect(
        (await repository.assignment('flv_1', CredentialKind.ascKey))!.id,
        personal.id,
      );
      expect(
        (await logged()).whereType<CredentialUnassigned>().single.credentialId,
        studio.id,
      );
    });

    test('every flavor of the app: others keep theirs', () async {
      await assign(studio.id, CredentialKind.ascKey, flavor: 'dev');

      final result = await assign(
        personal.id,
        CredentialKind.ascKey,
        allFlavors: true,
      );

      expect(result.assigned.map((c) => c.flavor), ['prod']);
      expect(result.kept.single.flavor, 'dev');
      expect(result.kept.single.name, 'Studio');
      expect(
        await repository.assignment('flv_3', CredentialKind.ascKey),
        isNull,
        reason: 'another app',
      );
    });

    test('every flavor of the app, replacing theirs', () async {
      await assign(studio.id, CredentialKind.ascKey, flavor: 'dev');

      final result = await assign(
        personal.id,
        CredentialKind.ascKey,
        allFlavors: true,
        replace: true,
      );

      expect(result.assigned.map((c) => c.flavor), ['dev', 'prod']);
      expect(result.kept, isEmpty);
    });

    test('the flavor it is chosen from always gets it', () async {
      await assign(studio.id, CredentialKind.ascKey);

      final result = await assign(
        personal.id,
        CredentialKind.ascKey,
        allFlavors: true,
      );

      expect(result.assigned.map((c) => c.flavor), ['dev', 'prod']);
    });

    test('assigning it again only checks again', () async {
      await assign(personal.id, CredentialKind.ascKey);
      final before = (await logged()).whereType<CredentialAssigned>().length;

      final result = await assign(personal.id, CredentialKind.ascKey);

      expect(result.assigned, hasLength(1));
      expect(
        (await logged()).whereType<CredentialAssigned>(),
        hasLength(before),
      );
    });

    test('an app below the root', () async {
      final result = await assign(
        studio.id,
        CredentialKind.ascKey,
        app: 'apps/captain',
        allFlavors: true,
      );

      expect(result.assigned.single.app, 'apps/captain');
      expect(
        verifiers[CredentialKind.ascKey]!.targets.single,
        const CredentialTarget(),
      );
    });

    test('takes the status of a credential whose secret is gone', () async {
      secrets.values.remove('credential.${personal.id}');

      final result = await assign(personal.id, CredentialKind.ascKey);

      expect(
        result.assigned.single.assignmentStatus,
        CredentialStatus.verified,
      );
      expect(verifiers[CredentialKind.ascKey]!.targets, isEmpty);
    });

    test('a damaged secret is not checked for the flavor either', () async {
      await secrets.write('credential.${personal.id}', 'not json');

      final result = await assign(personal.id, CredentialKind.ascKey);

      expect(result.assigned, hasLength(1));
      expect(verifiers[CredentialKind.ascKey]!.targets, isEmpty);
    });

    test('refuses a credential of another kind and github', () async {
      await expectLater(
        assign(personal.id, CredentialKind.playSa),
        throwsA(
          isA<CredentialRequestException>().having(
            (e) => e.message,
            'message',
            '"Personal" is a asc_key credential, not play_sa.',
          ),
        ),
      );
      await expectLater(
        assign(personal.id, CredentialKind.github),
        throwsA(isA<CredentialRequestException>()),
      );
    });

    test('refuses unknown places and credentials, and mcp tokens', () async {
      await expectLater(
        service.assign(
          'prj_9',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          request: AssignCredentialRequest(credentialId: personal.id),
          by: owner,
        ),
        throwsA(isA<ProjectNotFoundException>()),
      );
      await expectLater(
        assign(personal.id, CredentialKind.ascKey, flavor: 'staging'),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        assign('crd_nope', CredentialKind.ascKey),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        assign(personal.id, CredentialKind.ascKey, by: mcp),
        throwsA(isA<CredentialForbiddenException>()),
      );
    });
  });

  group('unassign', () {
    test('the flavor gives the credential up; it stays', () async {
      final key = await service.create(
        create(CredentialKind.ascKey),
        by: owner,
      );
      await assign(key.id, CredentialKind.ascKey);

      await service.unassign(
        'prj_1',
        app: '.',
        flavor: 'prod',
        kind: CredentialKind.ascKey,
        by: owner,
      );

      expect(await repository.assignments(), isEmpty);
      expect(await repository.get(key.id), isNotNull);
      expect(
        (await logged()).last,
        CredentialUnassigned(
          credentialId: key.id,
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
        ),
      );
    });

    test('refuses a flavor without one, and an mcp token', () async {
      await expectLater(
        service.unassign(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          by: owner,
        ),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.unassign(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          by: mcp,
        ),
        throwsA(isA<CredentialForbiddenException>()),
      );
    });
  });

  group('saveForFlavor, the deprecated route', () {
    test('creates a credential named after the flavor and uses it', () async {
      final saved = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.ascKey),
        by: owner,
      );

      expect(saved.created, isTrue);
      expect(
        saved.credential.name,
        'App Store Connect API key · acme/shop prod',
      );
      expect(saved.credential.flavor, 'prod');
      expect(saved.credential.status, CredentialStatus.verified);
      expect(
        (await logged()).whereType<CredentialSaved>().single.projectId,
        'prj_1',
      );
    });

    test('names a project without a full name by its id', () async {
      projects = InMemoryProjectRepository();
      await projects.add(
        ProjectRecord(
          id: 'prj_1',
          host: 'github.com',
          sourceKey: '1',
          githubRepoId: 1,
          fullName: '',
          remote: 'x',
          githubDefaultBranch: 'main',
          scan: const ProjectProfile(),
          findings: const [],
          scannedAt: DateTime.utc(2026),
        ),
      );
      service = build();

      final saved = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.slack),
        by: owner,
      );

      expect(saved.credential.name, 'Slack webhook · prj_1 prod');
    });

    test('names an app below the root and avoids a taken name', () async {
      await service.create(
        create(
          CredentialKind.slack,
          name: 'Slack webhook · acme/shop apps/captain prod',
        ),
        by: owner,
      );

      final saved = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.slack, app: 'apps/captain'),
        by: owner,
      );

      expect(
        saved.credential.name,
        'Slack webhook · acme/shop apps/captain prod 2',
      );
    });

    test('keeps a generated name within the limit', () async {
      projects = InMemoryProjectRepository();
      await projects.add(
        ProjectRecord(
          id: 'prj_1',
          host: 'github.com',
          sourceKey: '1',
          githubRepoId: 1,
          fullName: 'a-very-long-organisation-name/a-very-long-repository',
          remote: 'x',
          githubDefaultBranch: 'main',
          scan: const ProjectProfile(),
          findings: const [],
          scannedAt: DateTime.utc(2026),
        ),
      );
      service = build();

      // "Firebase service account · <52 characters> prod" is longer than
      // the limit; cut to it, the prod and dev flavors get the same name.
      final first = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.firebaseSa),
        by: owner,
      );
      final second = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.firebaseSa, flavor: 'dev'),
        by: owner,
      );

      expect(
        first.credential.name,
        'Firebase service account · '
        'a-very-long-organisation-name/a-very-long-repository',
      );
      expect(second.created, isTrue);
      expect(second.credential.name, endsWith('-repositor 2'));
      expect(second.credential.name, hasLength(maxCredentialNameLength));
    });

    test('gives the secret to the credential only this flavor uses', () async {
      final first = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.shorebird),
        by: owner,
      );

      final second = await service.saveForFlavor(
        'prj_1',
        legacy(
          CredentialKind.shorebird,
          name: 'Renamed',
          material: const {'token': 'sb_api_two'},
        ),
        by: owner,
      );

      expect(second.created, isFalse);
      expect(second.credential.id, first.credential.id);
      expect(second.credential.name, 'Renamed');
      expect(secrets.text('credential.${first.credential.id}'), 'sb_api_two');
    });

    test('keeps the name when none is given', () async {
      final first = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.shorebird),
        by: owner,
      );

      final second = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.shorebird),
        by: owner,
      );

      expect(second.credential.name, first.credential.name);
    });

    test('creates another credential when others share it', () async {
      final shared = await service.create(
        create(CredentialKind.shorebird, name: 'Shared'),
        by: owner,
      );
      await assign(shared.id, CredentialKind.shorebird, allFlavors: true);

      final saved = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.shorebird),
        by: owner,
      );

      expect(saved.created, isTrue);
      expect(saved.credential.id, isNot(shared.id));
      expect(
        (await repository.assignment('flv_2', CredentialKind.shorebird))!.id,
        shared.id,
        reason: 'the other flavor keeps it',
      );
      expect(
        (await logged()).whereType<CredentialUnassigned>().single.flavor,
        'prod',
      );
    });

    test('refuses a name that is taken by another credential', () async {
      await service.create(
        create(CredentialKind.slack, name: 'Taken'),
        by: owner,
      );
      await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.shorebird),
        by: owner,
      );

      await expectLater(
        service.saveForFlavor(
          'prj_1',
          legacy(CredentialKind.shorebird, name: 'taken'),
          by: owner,
        ),
        throwsA(isA<CredentialConflictException>()),
      );
    });

    test("makes a GitHub token the engine's token", () async {
      verifiers[CredentialKind.github]!.answers.add(
        const VerificationResult.verified(account: 'octocat'),
      );

      final saved = await service.saveForFlavor(
        'prj_1',
        legacy(CredentialKind.github),
        by: owner,
      );

      expect(saved.created, isFalse);
      expect(saved.credential.id, 'github');
      expect(saved.credential.account, 'octocat');
      expect(secrets.text(githubTokenSecretKey), 'ghp_abc123');
      expect(await repository.list(), isEmpty);
    });

    test('refuses an unknown project or flavor and an mcp token', () async {
      await expectLater(
        service.saveForFlavor('prj_9', legacy(CredentialKind.slack), by: owner),
        throwsA(isA<ProjectNotFoundException>()),
      );
      await expectLater(
        service.saveForFlavor(
          'prj_1',
          legacy(CredentialKind.slack, flavor: 'staging'),
          by: owner,
        ),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.saveForFlavor('prj_1', legacy(CredentialKind.slack), by: mcp),
        throwsA(isA<CredentialForbiddenException>()),
      );
    });
  });

  group('the deprecated verify and remove of a project', () {
    late NamedCredential key;

    setUp(() async {
      key = await service.create(create(CredentialKind.ascKey), by: owner);
      await assign(key.id, CredentialKind.ascKey, allFlavors: true);
      await assign(key.id, CredentialKind.ascKey, app: 'apps/captain');
    });

    test('verifies and answers as the first flavor of the project', () async {
      final checked = await service.verifyInProject('prj_1', key.id, by: cli);

      expect(checked.flavor, 'dev');
      expect(checked.id, key.id);
    });

    test('removes it from the project and deletes it when unused', () async {
      await service.removeFromProject('prj_1', key.id, by: owner);

      expect(await repository.get(key.id), isNull);
      expect(
        (await logged()).whereType<CredentialRemoved>().single.projectId,
        'prj_1',
      );
    });

    test('keeps it while another project uses it', () async {
      repository.flavors.add(
        const CredentialFlavor(
          id: 'flv_9',
          projectId: 'prj_2',
          appPath: '.',
          name: 'prod',
        ),
      );
      await projects.add(
        ProjectRecord(
          id: 'prj_2',
          host: 'github.com',
          sourceKey: '2',
          githubRepoId: 2,
          fullName: 'acme/other',
          remote: 'x',
          githubDefaultBranch: 'main',
          scan: const ProjectProfile(),
          findings: const [],
          scannedAt: DateTime.utc(2026),
        ),
      );
      await service.assign(
        'prj_2',
        app: '.',
        flavor: 'prod',
        kind: CredentialKind.ascKey,
        request: AssignCredentialRequest(credentialId: key.id),
        by: owner,
      );

      await service.removeFromProject('prj_1', key.id, by: owner);

      expect(await repository.get(key.id), isNotNull);
      expect(
        (await repository.assignments(credentialId: key.id)).single.flavor.id,
        'flv_9',
      );
    });

    test('refuses a credential the project does not use', () async {
      final other = await service.create(
        create(CredentialKind.slack),
        by: owner,
      );

      await expectLater(
        service.verifyInProject('prj_1', other.id, by: owner),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.removeFromProject('prj_1', other.id, by: owner),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.verifyInProject('prj_1', key.id, by: mcp),
        throwsA(isA<CredentialForbiddenException>()),
      );
      await expectLater(
        service.removeFromProject('prj_1', key.id, by: mcp),
        throwsA(isA<CredentialForbiddenException>()),
      );
    });
  });

  group('checkAll', () {
    test('checks every credential and every assignment', () async {
      final key = await service.create(
        create(CredentialKind.ascKey),
        by: owner,
      );
      await service.create(create(CredentialKind.slack), by: owner);
      await assign(key.id, CredentialKind.ascKey, allFlavors: true);
      clock.advance(const Duration(days: 1));
      verifiers[CredentialKind.slack]!.answers.add(
        const VerificationResult.rejected('Gone.'),
      );

      final results = await service.checkAll();

      expect(results.map((c) => c.status), [
        CredentialStatus.verified,
        CredentialStatus.rejected,
      ]);
      expect(results.first.usedBy.map((u) => u.checkedAt), [
        clock.now(),
        clock.now(),
      ]);
      expect((await logged()).whereType<CredentialExpired>(), hasLength(1));
    });

    test('goes on after a check that throws, then reports it', () async {
      await service.create(create(CredentialKind.ascKey), by: owner);
      await service.create(create(CredentialKind.slack), by: owner);
      verifiers[CredentialKind.ascKey] = _ThrowingVerifier();
      service = build();

      await expectLater(service.checkAll(), throwsStateError);

      expect(verifiers[CredentialKind.slack]!.checked, hasLength(2));
    });

    test('stops at once when the secrets are locked', () async {
      await service.create(create(CredentialKind.ascKey), by: owner);
      secrets.failure = const SecretsLockedException('locked');

      await expectLater(
        service.checkAll(),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test('checks nothing when there is nothing', () async {
      expect(await service.checkAll(), isEmpty);
    });
  });
}

class _SlowVerifier extends FakeCredentialVerifier {
  new(this.gate) : super(CredentialKind.shorebird);

  final Future<void> gate;
  int started = 0;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    started++;
    await gate;
    return await super.verify(material, target);
  }
}

class _ThrowingVerifier extends FakeCredentialVerifier {
  new() : super(CredentialKind.ascKey);

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) => throw StateError('bug');
}

/// A result that says nothing: never checked, no reason.
class _Unverified extends VerificationResult {
  const new() : super.unreachable('');

  @override
  CredentialStatus get status => CredentialStatus.unverified;

  @override
  String? get message => null;
}

class _AnsweringVerifier extends FakeCredentialVerifier {
  new(super.kind, this.answer);

  final VerificationResult answer;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async => answer;
}
