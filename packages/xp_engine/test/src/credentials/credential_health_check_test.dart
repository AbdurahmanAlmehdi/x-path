import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/credential_harness.dart';
import '../../helpers/job_harness.dart';

/// A timer that does not tick by itself.
class _ManualTimer implements Timer {
  new(this.callback);

  final void Function(Timer timer) callback;

  @override
  bool isActive = true;

  @override
  int get tick => 0;

  @override
  void cancel() => isActive = false;

  void fire() => callback(this);
}

void main() {
  late InMemoryCredentialRepository repository;
  late BytesSecretStore secrets;
  late ManualClock clock;
  late FakeCredentialVerifier asc;
  late CredentialService service;
  late List<_ManualTimer> timers;
  late List<Duration> periods;
  late List<Object> errors;

  CredentialHealthCheck check({CredentialRepository? repo}) =>
      CredentialHealthCheck(
        service: service,
        repository: repo ?? repository,
        clock: clock,
        onError: (error, _) => errors.add(error),
        timers: (period, callback) {
          periods.add(period);
          final timer = _ManualTimer(callback);
          timers.add(timer);
          return timer;
        },
      );

  Future<NamedCredential> saveKey() => service.create(
    CreateCredentialRequest(
      name: 'Key',
      kind: CredentialKind.ascKey,
      material: credentialFields(CredentialKind.ascKey),
    ),
    by: tokenOf(DeviceTokenKind.app),
  );

  setUp(() async {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    repository = InMemoryCredentialRepository([testFlavor]);
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
        scannedAt: DateTime.utc(2026),
      ),
    );
    secrets = BytesSecretStore();
    asc = FakeCredentialVerifier(CredentialKind.ascKey);
    service = CredentialService(
      repository: repository,
      projects: projects,
      secrets: secrets,
      verifiers: [asc],
      masker: ReplacingMasker(),
      events: InMemoryEventLog(clock: clock),
      clock: clock,
    );
    timers = [];
    periods = [];
    errors = [];
  });

  test('checks every day unless told otherwise', () async {
    final health = check();

    await health.start();

    expect(periods, [const Duration(hours: 24)]);
    expect(health.interval, const Duration(hours: 24));
    expect(health.isRunning, isTrue);
  });

  test('does not check at start when everything was checked lately', () async {
    await saveKey();
    clock.advance(const Duration(hours: 23));
    final health = check();

    await health.start();

    expect(asc.checked, hasLength(1));
  });

  test(
    'catches up at start when a credential was last checked a day ago',
    () async {
      final saved = await saveKey();
      clock.advance(const Duration(hours: 24));
      asc.answers.add(const VerificationResult.rejected('Expired.'));
      final health = check();

      await health.start();

      final record = (await repository.get(saved.id))!;
      expect(record.status, CredentialStatus.rejected);
      expect(record.check.checkedAt, clock.now());
    },
  );

  test('catches up at start for a credential that was never checked', () async {
    await repository.save(
      const CredentialRecord(
        id: 'crd_1',
        name: 'Key',
        kind: CredentialKind.ascKey,
        secretKey: 'credential.crd_1',
      ),
    );
    await secrets.write(
      'credential.crd_1',
      const AscKey(keyId: 'K', issuerId: 'I', privateKey: 'P').toSecret(),
    );

    await check().start();

    expect(asc.checked, hasLength(1));
  });

  test(
    'catches up at start for an assignment that was never checked',
    () async {
      final saved = await saveKey();
      final record = (await repository.get(saved.id))!;
      await repository.assign(
        AssignedCredential(flavor: testFlavor, credential: record),
      );
      clock.advance(const Duration(hours: 1));

      await check().start();

      expect(asc.checked, hasLength(2));
      final assignment = (await repository.assignment(
        testFlavor.id,
        CredentialKind.ascKey,
      ))!;
      expect(assignment.check.checkedAt, clock.now());
    },
  );

  test('checks again when the timer fires', () async {
    await saveKey();
    final health = check();
    await health.start();
    clock.advance(const Duration(hours: 24));

    timers.single.fire();
    await Future<void>.delayed(Duration.zero);

    expect(asc.checked, hasLength(2));
  });

  test('never runs two checks at once', () async {
    await saveKey();
    final gate = Completer<void>();
    final slow = _SlowVerifier(gate.future);
    service = CredentialService(
      repository: repository,
      projects: await _projects(),
      secrets: secrets,
      verifiers: [slow],
      masker: ReplacingMasker(),
      events: InMemoryEventLog(clock: clock),
      clock: clock,
    );
    final health = check();

    final first = health.runNow();
    final second = health.runNow();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    gate.complete();
    await Future.wait([first, second]);

    expect(slow.calls, 1);
  });

  test('reports a failed run and carries on', () async {
    await saveKey();
    secrets.failure = const SecretsLockedException('locked');
    final health = check();

    await health.runNow();
    secrets.failure = null;
    await health.runNow();

    expect(errors.single, isA<SecretsLockedException>());
    expect(asc.checked, hasLength(2));
  });

  test('reports a failure to read the schedule', () async {
    final health = check(repo: _BrokenRepository());

    await health.start();

    expect(errors.single, isA<StateError>());
    expect(health.isRunning, isTrue);
  });

  test('starts once and stops', () async {
    final health = check();

    await health.start();
    await health.start();
    health
      ..stop()
      ..stop();

    expect(timers, hasLength(1));
    expect(timers.single.isActive, isFalse);
    expect(health.isRunning, isFalse);
  });

  test('works with the real timer too', () async {
    final real = CredentialHealthCheck(
      service: service,
      repository: repository,
      clock: clock,
      interval: const Duration(hours: 1),
    );

    await real.start();
    real.stop();

    expect(real.isRunning, isFalse);
  });
}

Future<InMemoryProjectRepository> _projects() async {
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
      scannedAt: DateTime.utc(2026),
    ),
  );
  return projects;
}

class _SlowVerifier extends FakeCredentialVerifier {
  new(this.gate) : super(CredentialKind.ascKey);

  final Future<void> gate;
  int calls = 0;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    calls++;
    await gate;
    return await super.verify(material, target);
  }
}

class _BrokenRepository extends InMemoryCredentialRepository {
  @override
  Future<List<CredentialRecord>> list() => throw StateError('disk on fire');
}
