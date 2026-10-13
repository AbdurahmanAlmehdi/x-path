import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/credential_harness.dart';
import '../../helpers/job_harness.dart';

class _FailingRepository extends InMemoryCredentialRepository {
  new(super.flavors);

  bool failing = true;

  @override
  Future<void> save(CredentialRecord record) =>
      failing ? throw StateError('disk on fire') : super.save(record);
}

void main() {
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

  SaveCredentialRequest request(
    CredentialKind kind, {
    String app = '.',
    String flavor = 'prod',
    Map<String, dynamic>? material,
  }) => SaveCredentialRequest(
    app: app,
    flavor: flavor,
    kind: kind,
    material: material ?? credentialFields(kind),
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
    repository = InMemoryCredentialRepository([
      testFlavor,
      const CredentialFlavor(
        id: 'flv_2',
        projectId: 'prj_1',
        appPath: 'apps/captain',
        name: 'dev',
      ),
    ]);
    projects = InMemoryProjectRepository();
    await projects.add(
      ProjectRecord(
        id: 'prj_1',
        githubRepoId: 1,
        fullName: 'o/r',
        remote: 'https://github.com/o/r.git',
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

  group('save', () {
    test('verifies, stores the secret and the reference', () async {
      final saved = await service.save('prj_1', request(CredentialKind.ascKey));

      final credential = saved.credential;
      expect(saved.created, isTrue);
      expect(credential.id, startsWith('crd_'));
      expect(credential.projectId, 'prj_1');
      expect(credential.app, '.');
      expect(credential.flavor, 'prod');
      expect(credential.kind, CredentialKind.ascKey);
      expect(credential.status, CredentialStatus.verified);
      expect(credential.account, 'ABC123DEF4');
      expect(credential.verifiedAt, clock.now());
      expect(credential.checkedAt, clock.now());
      final stored = (await repository.get(credential.id))!;
      expect(stored.secretKey, 'credential.${credential.id}');
      expect(
        AscKey.fromSecret(secrets.text(stored.secretKey)!).keyId,
        'ABC123DEF4',
      );
      expect(
        verifiers[CredentialKind.ascKey]!.targets.single,
        const CredentialTarget(
          iosBundleId: 'com.mataa.app',
          androidAppId: 'com.mataa.app',
        ),
      );
    });

    test('announces the save', () async {
      final saved = await service.save(
        'prj_1',
        request(CredentialKind.appleId),
      );

      expect(await logged(), [
        CredentialSaved(
          credentialId: saved.credential.id,
          projectId: 'prj_1',
          kind: CredentialKind.appleId,
          replaced: false,
        ),
      ]);
    });

    test('lets the masker learn the secrets, and nothing else', () async {
      await service.save('prj_1', request(CredentialKind.appleId));
      await service.save('prj_1', request(CredentialKind.keystore));

      expect(masker.secrets, contains('abcd-efgh-ijkl-mnop'));
      expect(masker.secrets, contains('store-pass'));
    });

    test('lets the masker learn a secret that is refused, too', () async {
      verifiers[CredentialKind.appleId]!.answers.add(
        const VerificationResult.rejected('No.'),
      );

      await expectLater(
        service.save('prj_1', request(CredentialKind.appleId)),
        throwsA(isA<CredentialRejectedException>()),
      );

      expect(masker.secrets, contains('abcd-efgh-ijkl-mnop'));
    });

    test('replaces the credential of the same flavor and kind', () async {
      final first = await service.save(
        'prj_1',
        request(CredentialKind.shorebird),
      );
      clock.advance(const Duration(days: 1));
      final second = await service.save(
        'prj_1',
        request(CredentialKind.shorebird, material: {'token': 'sb_api_second'}),
      );

      expect(second.created, isFalse);
      expect(second.credential.id, first.credential.id);
      expect(second.credential.verifiedAt, clock.now());
      expect(await repository.list(), hasLength(1));
      expect(
        secrets.text('credential.${first.credential.id}'),
        'sb_api_second',
      );
      final replaced = (await logged()).whereType<CredentialSaved>().last;
      expect(replaced.replaced, isTrue);
    });

    test('keeps the account the check found out', () async {
      verifiers[CredentialKind.github]!.answers.add(
        const VerificationResult.verified(account: 'octocat'),
      );

      final saved = await service.save('prj_1', request(CredentialKind.github));

      expect(saved.credential.account, 'octocat');
    });

    test(
      'keeps the one GitHub token of the engine under its own key',
      () async {
        final saved = await service.save(
          'prj_1',
          request(CredentialKind.github),
        );

        expect(
          (await repository.get(saved.credential.id))!.secretKey,
          githubTokenSecretKey,
        );
        expect(secrets.text(githubTokenSecretKey), 'ghp_abc123');
      },
    );

    test('stores nothing when the store refuses the credential', () async {
      verifiers[CredentialKind.ascKey]!.answers.add(
        const VerificationResult.rejected('Revoked.', fix: 'Make a new one.'),
      );

      await expectLater(
        service.save('prj_1', request(CredentialKind.ascKey)),
        throwsA(
          isA<CredentialRejectedException>()
              .having((e) => e.message, 'message', 'Revoked.')
              .having((e) => e.fix, 'fix', 'Make a new one.'),
        ),
      );

      expect(secrets.values, isEmpty);
      expect(await repository.list(), isEmpty);
      expect(await logged(), isEmpty);
    });

    test('keeps the old credential when the new one is refused', () async {
      final first = await service.save(
        'prj_1',
        request(CredentialKind.shorebird),
      );
      verifiers[CredentialKind.shorebird]!.answers.add(
        const VerificationResult.rejected('Revoked.'),
      );

      await expectLater(
        service.save(
          'prj_1',
          request(CredentialKind.shorebird, material: {'token': 'sb_api_bad'}),
        ),
        throwsA(isA<CredentialRejectedException>()),
      );

      expect(
        secrets.text('credential.${first.credential.id}'),
        'sb_api_abc123',
      );
    });

    test('stores nothing when the check could not be made', () async {
      verifiers[CredentialKind.playSa]!.answers.add(
        const VerificationResult.unreachable('Offline.', fix: 'Retry.'),
      );

      await expectLater(
        service.save('prj_1', request(CredentialKind.playSa)),
        throwsA(
          isA<CredentialUnreachableException>().having(
            (e) => e.described,
            'described',
            'Offline. Retry.',
          ),
        ),
      );

      expect(secrets.values, isEmpty);
      expect(await repository.list(), isEmpty);
    });

    test('says so when the check gave no reason', () async {
      verifiers[CredentialKind.playSa]!.answers.add(
        const VerificationResult.unreachable('x'),
      );

      await expectLater(
        service.save('prj_1', request(CredentialKind.playSa)),
        throwsA(isA<CredentialUnreachableException>()),
      );
    });

    test('refuses a kind it has no verifier for', () async {
      verifiers.remove(CredentialKind.slack);
      service = build();

      await expectLater(
        service.save('prj_1', request(CredentialKind.slack)),
        throwsA(
          isA<CredentialRejectedException>().having(
            (e) => e.message,
            'message',
            contains('cannot check slack'),
          ),
        ),
      );
    });

    test(
      'refuses a malformed request and a missing project or flavor',
      () async {
        await expectLater(
          service.save(
            'prj_1',
            request(CredentialKind.ascKey, material: {'keyId': 'x'}),
          ),
          throwsA(isA<CredentialRequestException>()),
        );
        await expectLater(
          service.save('prj_9', request(CredentialKind.ascKey)),
          throwsA(isA<ProjectNotFoundException>()),
        );
        await expectLater(
          service.save('prj_1', request(CredentialKind.ascKey, flavor: 'nope')),
          throwsA(isA<CredentialNotFoundException>()),
        );
      },
    );

    test(
      'takes back a new secret when the reference cannot be saved',
      () async {
        service = build(_FailingRepository([testFlavor]));

        await expectLater(
          service.save('prj_1', request(CredentialKind.keystore)),
          throwsStateError,
        );

        expect(secrets.values, isEmpty);
      },
    );

    test('leaves the secret of an old credential when saving fails', () async {
      final repo = _FailingRepository([testFlavor])..failing = false;
      service = build(repo);
      final first = await service.save(
        'prj_1',
        request(CredentialKind.shorebird),
      );
      repo.failing = true;

      await expectLater(
        service.save(
          'prj_1',
          request(CredentialKind.shorebird, material: {'token': 'sb_api_new'}),
        ),
        throwsStateError,
      );

      expect(secrets.values, isNotEmpty);
      expect(first.created, isTrue);
    });

    test('lets a locked secret store through', () async {
      secrets.failure = const SecretsLockedException('locked');

      await expectLater(
        service.save('prj_1', request(CredentialKind.shorebird)),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(await repository.list(), isEmpty);
    });

    test('runs one save at a time', () async {
      final gate = Completer<void>();
      final slow = _SlowVerifier(gate.future);
      verifiers[CredentialKind.shorebird] = slow;
      service = build();

      final first = service.save('prj_1', request(CredentialKind.shorebird));
      final second = service.save(
        'prj_1',
        request(CredentialKind.shorebird, material: {'token': 'sb_api_two'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(slow.started, 1);
      gate.complete();
      final results = await Future.wait([first, second]);

      expect(results[0].created, isTrue);
      expect(results[1].created, isFalse);
    });
  });

  group('list', () {
    setUp(() async {
      await service.save('prj_1', request(CredentialKind.ascKey));
      await service.save(
        'prj_1',
        request(CredentialKind.slack, app: 'apps/captain', flavor: 'dev'),
      );
    });

    test('lists the credentials of the project, oldest first', () async {
      final all = await service.list('prj_1');

      expect(
        [for (final c in all) c.kind],
        [CredentialKind.ascKey, CredentialKind.slack],
      );
    });

    test('narrows to a flavor, the root app by default', () async {
      expect(
        [for (final c in await service.list('prj_1', flavor: 'prod')) c.kind],
        [CredentialKind.ascKey],
      );
      expect(
        [
          for (final c in await service.list(
            'prj_1',
            app: 'apps/captain',
            flavor: 'dev',
          ))
            c.kind,
        ],
        [CredentialKind.slack],
      );
    });

    test('refuses an unknown project or flavor, and an app alone', () async {
      await expectLater(
        service.list('prj_9'),
        throwsA(isA<ProjectNotFoundException>()),
      );
      await expectLater(
        service.list('prj_1', flavor: 'nope'),
        throwsA(isA<CredentialNotFoundException>()),
      );
      await expectLater(
        service.list('prj_1', app: 'apps/captain'),
        throwsA(isA<CredentialRequestException>()),
      );
    });

    test('shows no secret', () async {
      final json = (await service.list('prj_1'))
          .map((c) => c.toJson())
          .toString();

      expect(json, isNot(contains('PRIVATE KEY')));
      expect(json, isNot(contains('hooks.slack.com')));
    });
  });

  group('verify', () {
    late Credential saved;

    setUp(() async {
      saved = (await service.save(
        'prj_1',
        request(CredentialKind.appleId),
      )).credential;
      clock.advance(const Duration(days: 1));
    });

    test('checks again with the stored secret and keeps the result', () async {
      final result = await service.verify('prj_1', saved.id);

      expect(result.status, CredentialStatus.verified);
      expect(result.checkedAt, clock.now());
      expect(result.verifiedAt, clock.now());
      final material =
          verifiers[CredentialKind.appleId]!.checked.last as AppleIdMaterial;
      expect(material.appleId, 'dev@example.com');
      expect(material.password, 'abcd-efgh-ijkl-mnop');
    });

    test(
      'keeps a refusal with its reason and fix, and announces expiry',
      () async {
        verifiers[CredentialKind.appleId]!.answers.add(
          const VerificationResult.rejected('Revoked.', fix: 'Make a new one.'),
        );

        final result = await service.verify('prj_1', saved.id);

        expect(result.status, CredentialStatus.rejected);
        expect(result.message, 'Revoked.');
        expect(result.fix, 'Make a new one.');
        expect(result.verifiedAt, saved.verifiedAt);
        final entries = await logged();
        expect(
          entries.whereType<CredentialVerified>().last.status,
          CredentialStatus.rejected,
        );
        expect(
          entries.whereType<CredentialExpired>().single.message,
          'Revoked. Make a new one.',
        );
      },
    );

    test('announces an expiry once, not on every check', () async {
      verifiers[CredentialKind.appleId]!.answers.addAll([
        const VerificationResult.rejected('Revoked.'),
        const VerificationResult.rejected('Revoked.'),
      ]);

      await service.verify('prj_1', saved.id);
      final again = await service.verify('prj_1', saved.id);

      expect(again.message, 'Revoked.');
      expect((await logged()).whereType<CredentialExpired>(), hasLength(1));
    });

    test(
      'does not call it expired when the store could not be reached',
      () async {
        verifiers[CredentialKind.appleId]!.answers.add(
          const VerificationResult.unreachable('Offline.'),
        );

        final result = await service.verify('prj_1', saved.id);

        expect(result.status, CredentialStatus.unreachable);
        expect((await logged()).whereType<CredentialExpired>(), isEmpty);
      },
    );

    test('rejects a credential whose secret is gone', () async {
      secrets.values.clear();

      final result = await service.verify('prj_1', saved.id);

      expect(result.status, CredentialStatus.rejected);
      expect(result.message, contains('missing from the secret store'));
      expect(verifiers[CredentialKind.appleId]!.checked, hasLength(1));
    });

    test('rejects a credential whose secret is damaged', () async {
      final sa = (await service.save(
        'prj_1',
        request(CredentialKind.playSa),
      )).credential;
      secrets.values['credential.${sa.id}'] = secrets.values.values.first;
      await secrets.write('credential.${sa.id}', 'not json');

      final result = await service.verify('prj_1', sa.id);

      expect(result.status, CredentialStatus.rejected);
      expect(result.message, contains('cannot be used'));
    });

    test('cannot check a kind without a verifier, and says so', () async {
      verifiers.remove(CredentialKind.appleId);
      service = build();

      final result = await service.verify('prj_1', saved.id);

      expect(result.status, CredentialStatus.unreachable);
      expect(result.message, contains('cannot check apple_id'));
    });

    test(
      'refuses unknown credentials, also those of another project',
      () async {
        await expectLater(
          service.verify('prj_1', 'crd_nope'),
          throwsA(isA<CredentialNotFoundException>()),
        );
        await expectLater(
          service.verify('prj_9', saved.id),
          throwsA(isA<ProjectNotFoundException>()),
        );
        await projects.add(
          ProjectRecord(
            id: 'prj_2',
            githubRepoId: 2,
            fullName: 'o/s',
            remote: 'x',
            githubDefaultBranch: 'main',
            scan: const ProjectProfile(),
            findings: const [],
            scannedAt: DateTime.utc(2026),
          ),
        );
        await expectLater(
          service.verify('prj_2', saved.id),
          throwsA(isA<CredentialNotFoundException>()),
        );
      },
    );
  });

  group('remove', () {
    test('deletes the reference, the secret and announces it', () async {
      final saved = (await service.save(
        'prj_1',
        request(CredentialKind.keystore),
      )).credential;
      expect(secrets.values, hasLength(3));

      await service.remove('prj_1', saved.id);

      expect(await repository.list(), isEmpty);
      expect(secrets.values, isEmpty);
      expect(
        (await logged()).last,
        CredentialRemoved(
          credentialId: saved.id,
          projectId: 'prj_1',
          kind: CredentialKind.keystore,
        ),
      );
    });

    test('leaves a secret another credential shares', () async {
      await service.save('prj_1', request(CredentialKind.github));
      final other = (await service.save(
        'prj_1',
        request(CredentialKind.github, app: 'apps/captain', flavor: 'dev'),
      )).credential;

      await service.remove('prj_1', other.id);

      expect(secrets.text(githubTokenSecretKey), 'ghp_abc123');
      final last = (await repository.list()).single;
      await service.remove('prj_1', last.id);
      expect(secrets.values, isEmpty);
    });

    test('refuses an unknown credential', () async {
      await expectLater(
        service.remove('prj_1', 'crd_nope'),
        throwsA(isA<CredentialNotFoundException>()),
      );
    });
  });

  group('checkAll', () {
    test('checks every credential of every project', () async {
      await service.save('prj_1', request(CredentialKind.ascKey));
      await service.save(
        'prj_1',
        request(CredentialKind.slack, app: 'apps/captain', flavor: 'dev'),
      );
      clock.advance(const Duration(days: 1));
      verifiers[CredentialKind.slack]!.answers.add(
        const VerificationResult.rejected('Gone.'),
      );

      final results = await service.checkAll();

      expect(
        [for (final c in results) c.status],
        [CredentialStatus.verified, CredentialStatus.rejected],
      );
      expect(results.first.checkedAt, clock.now());
      expect((await logged()).whereType<CredentialExpired>(), hasLength(1));
    });

    test('goes on after a check that throws, then reports it', () async {
      await service.save('prj_1', request(CredentialKind.ascKey));
      await service.save('prj_1', request(CredentialKind.slack));
      verifiers[CredentialKind.ascKey] = _ThrowingVerifier();
      service = build();

      await expectLater(service.checkAll(), throwsStateError);

      expect(verifiers[CredentialKind.slack]!.checked, hasLength(2));
    });

    test('stops at once when the secrets are locked', () async {
      await service.save('prj_1', request(CredentialKind.ascKey));
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
