import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final created = DateTime.utc(2026, 10, 14, 9);
  final runner = RunnerRecord(
    id: 'rnr_1',
    name: 'mac-mini',
    tokenId: 'tok_1',
    createdAt: created,
  );

  group('RunnerRecord', () {
    test('starts with nothing probed', () {
      expect(runner.capabilities, isEmpty);
      expect(runner.slots, 1);
      expect(runner.isRevoked, isFalse);
      expect(runner.os, isNull);
    });

    test('copyWith replaces what it is given and keeps the rest', () {
      final changed = runner.copyWith(
        capabilities: {Capability.flutter, Capability.iosSign},
        slots: 4,
        os: 'macos',
        arch: 'arm64',
        version: '1.0.0',
        cores: 16,
        lastHeartbeat: created,
        revokedAt: created,
      );

      expect(changed.id, 'rnr_1');
      expect(changed.name, 'mac-mini');
      expect(changed.tokenId, 'tok_1');
      expect(changed.createdAt, created);
      expect(changed.capabilities, {Capability.flutter, Capability.iosSign});
      expect(changed.slots, 4);
      expect(changed.os, 'macos');
      expect(changed.arch, 'arm64');
      expect(changed.version, '1.0.0');
      expect(changed.cores, 16);
      expect(changed.lastHeartbeat, created);
      expect(changed.isRevoked, isTrue);
      expect(changed.copyWith(), changed);
      expect(changed.copyWith(os: null, revokedAt: null).os, isNull);
      expect(changed.copyWith(os: null, revokedAt: null).isRevoked, isFalse);
      expect(runner.copyWith(slots: 2) == runner, isFalse);
    });

    test('is described for the API with sorted wire names', () {
      final described = runner
          .copyWith(
            capabilities: {Capability.swiftLinux, Capability.android},
            slots: 2,
            os: 'linux',
            cores: 8,
          )
          .toRunner(status: RunnerStatus.online, jobIds: ['job_1']);

      expect(described.status, RunnerStatus.online);
      expect(described.capabilities, ['android', 'swift-linux']);
      expect(described.jobIds, ['job_1']);
      expect(described.slots, 2);
      expect(described.os, 'linux');
      expect(described.cores, 8);
      expect(described.createdAt, created);
      expect(runner.toRunner(status: RunnerStatus.offline).jobIds, isEmpty);
      expect(RunnerRecord.wireNames({}), isEmpty);
    });
  });

  group('InMemoryRunnerRepository', () {
    late InMemoryRunnerRepository runners;

    setUp(() => runners = InMemoryRunnerRepository());

    test('finds a runner by id, name and credential', () async {
      await runners.add(runner);

      expect(await runners.get('rnr_1'), runner);
      expect(await runners.findByName('mac-mini'), runner);
      expect(await runners.findByToken('tok_1'), runner);
      expect(await runners.get('rnr_2'), isNull);
      expect(await runners.findByName('other'), isNull);
      expect(await runners.findByToken('tok_2'), isNull);
    });

    test('lists in the order they were added', () async {
      final second = RunnerRecord(
        id: 'rnr_2',
        name: 'linux',
        tokenId: 'tok_2',
        createdAt: created,
      );
      await runners.add(runner);
      await runners.add(second);

      expect(await runners.list(), [runner, second]);
    });

    test('refuses an id or a name that exists', () async {
      await runners.add(runner);

      await expectLater(runners.add(runner), throwsStateError);
      await expectLater(
        runners.add(
          RunnerRecord(
            id: 'rnr_2',
            name: 'mac-mini',
            tokenId: 'tok_2',
            createdAt: created,
          ),
        ),
        throwsStateError,
      );
    });

    test('replaces a runner that is there', () async {
      await runners.add(runner);

      await runners.update(runner.copyWith(slots: 3));

      expect((await runners.get('rnr_1'))!.slots, 3);
      await expectLater(
        runners.update(
          RunnerRecord(
            id: 'rnr_9',
            name: 'x',
            tokenId: 't',
            createdAt: created,
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('InMemoryPairingTokenRepository', () {
    late InMemoryPairingTokenRepository tokens;
    PairingTokenRecord token(String id, {DateTime? usedAt}) =>
        PairingTokenRecord(
          id: id,
          hash: 'hash-$id',
          name: id,
          createdBy: 'tok_1',
          createdAt: created,
          expiresAt: created.add(const Duration(minutes: 15)),
          usedAt: usedAt,
        );

    setUp(() => tokens = InMemoryPairingTokenRepository());

    test('finds a token by the hash of its secret', () async {
      await tokens.add(token('a'));

      expect(await tokens.findByHash('hash-a'), token('a'));
      expect(await tokens.findByHash('hash-b'), isNull);
    });

    test('consume works once, before the token expires', () async {
      await tokens.add(token('a'));
      await tokens.add(token('late'));

      expect(await tokens.consume('a', at: created), isTrue);
      expect(await tokens.consume('a', at: created), isFalse);
      expect((await tokens.findByHash('hash-a'))!.usedAt, created);
      expect(await tokens.consume('nope', at: created), isFalse);
      expect(
        await tokens.consume(
          'late',
          at: created.add(const Duration(minutes: 15)),
        ),
        isFalse,
      );
      expect(
        await tokens.consume(
          'late',
          at: created.add(const Duration(minutes: 14, seconds: 59)),
        ),
        isTrue,
      );
    });

    test('prune forgets the expired and the used', () async {
      await tokens.add(token('expired'));
      await tokens.add(token('used', usedAt: created));
      await tokens.add(token('fresh'));

      await tokens.prune(before: created.add(const Duration(minutes: 16)));
      expect(await tokens.findByHash('hash-expired'), isNull);
      expect(await tokens.findByHash('hash-used'), isNull);
      expect(await tokens.findByHash('hash-fresh'), isNull);

      await tokens.add(token('again'));
      await tokens.add(token('used-now', usedAt: created));
      await tokens.prune(before: created.subtract(const Duration(minutes: 1)));
      expect(await tokens.findByHash('hash-again'), isNotNull);
      expect(await tokens.findByHash('hash-used-now'), isNotNull);
    });
  });

  group('exceptions', () {
    test('say what went wrong', () {
      const exceptions = <RunnerException>[
        RunnerException('plain'),
        RunnerNotFoundException('rnr_1'),
        RunnerForbiddenException('no'),
        PairingRejectedException('expired'),
        RunnerNameTakenException('mac'),
        RunnerInvalidException('bad name'),
        RunnerLeaseException('no lease'),
        ArtifactChecksumException('wrong digest'),
      ];

      for (final exception in exceptions) {
        expect(exception.toString(), contains(exception.message));
        expect(exception.toString(), contains('Exception'));
      }
      expect(const RunnerNotFoundException('rnr_1').message, contains('rnr_1'));
      expect(const RunnerNameTakenException('mac').name, 'mac');
      expect(const RunnerNameTakenException('mac').message, contains('"mac"'));
    });
  });

  group('FakeRunnerLink', () {
    test('keeps what it is sent and refuses once closed', () async {
      final link = FakeRunnerLink();
      const frame = FaultFrame(code: 'x', message: 'y');

      link.send(frame);
      expect(link.sent, [frame]);
      expect(link.sentOf<FaultFrame>(), [frame]);
      expect(link.sentOf<CancelFrame>(), isEmpty);
      expect(link.isClosed, isFalse);

      await link.close(4001, 'first');
      await link.close(4002, 'second');
      expect(link.isClosed, isTrue);
      expect(link.closeCode, 4001);
      expect(link.closeReason, 'first');
      expect(() => link.send(frame), throwsStateError);
      expect(
        () => (FakeRunnerLink()..failToSend = true).send(frame),
        throwsStateError,
      );
    });
  });
}
