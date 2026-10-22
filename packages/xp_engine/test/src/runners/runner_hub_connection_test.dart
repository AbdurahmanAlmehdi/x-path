import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_harness.dart';

void main() {
  late RunnerHarness h;

  setUp(() async => h = await RunnerHarness.create());
  tearDown(() => expect(h.errors, isEmpty));

  List<String> schedulerRunners() => [
    for (final runner in h.scheduler.runners) runner.id,
  ];

  group('connect', () {
    test('welcomes the runner with the rules of the protocol', () async {
      final runner = await h.pair('mac');

      expect(
        runner.link.sent.single,
        WelcomeFrame(
          runnerId: runner.id,
          engineVersion: '9.9.9',
          apiVersion: apiVersion,
        ),
      );
      expect(h.hub.isConnected(runner.id), isTrue);
      expect(h.hub.statusOf(runner.id), RunnerStatus.offline);
    });

    test('a second connection of the runner replaces the first', () async {
      final first = await h.online();

      final second = await h.reconnect(first);
      await first.connection.closed();

      expect(first.link.closeCode, runnerReplacedCloseCode);
      expect(h.hub.isConnected(first.id), isTrue);
      expect(second.link.closeCode, isNull);
      // The first connection took its runner out of the scheduler; the new
      // one is probed before it gets jobs. Nobody was told it left.
      expect(schedulerRunners(), ['local']);
      expect(await h.eventsOf<RunnerDisconnected>(), isEmpty);
    });

    test('a runner that is gone is announced once', () async {
      final runner = await h.online(name: 'mac');

      await runner.connection.closed();
      await runner.connection.closed();

      expect(h.hub.isConnected(runner.id), isFalse);
      expect(schedulerRunners(), ['local']);
      expect(await h.eventsOf<RunnerDisconnected>(), [
        RunnerDisconnected(runnerId: runner.id, name: 'mac'),
      ]);
    });

    test('a runner that never got probed leaves without a word', () async {
      final runner = await h.pair();

      await runner.connection.closed();

      expect(h.hub.isConnected(runner.id), isFalse);
      expect(await h.eventsOf<RunnerDisconnected>(), isEmpty);
    });

    test('a broken connection does not stop the engine', () async {
      final runner = await h.pair();
      runner.link.failToSend = true;

      await runner.hello();

      expect(runner.link.sent, hasLength(1));
    });
  });

  group('frames', () {
    test('the first frame must be hello', () async {
      final runner = await h.pair();

      await runner.heartbeat(const []);

      expect(runner.faults.single.code, 'unexpected_frame');
      expect(runner.link.closeCode, runnerProtocolCloseCode);
      // Nothing more is read from a closed connection.
      await runner.hello();
      expect(runner.link.sentOf<ProbeFrame>(), isEmpty);
    });

    test('text that is not a JSON object closes the connection', () async {
      final text = await h.pair();
      final array = await h.pair();

      await text.connection.receiveText('not json');
      await array.connection.receiveText('[1]');

      for (final runner in [text, array]) {
        expect(runner.faults.single.code, 'invalid_frame');
        expect(runner.link.closeCode, runnerProtocolCloseCode);
        expect(h.hub.isConnected(runner.id), isFalse);
      }
    });

    test('a frame that is not well formed is a fault, not the end', () async {
      final runner = await h.pair();

      await runner.connection.receiveText('{"type":"lease_accept"}');

      expect(runner.faults.single.code, 'invalid_frame');
      expect(runner.link.closeCode, isNull);
    });

    test('a frame of a type the engine does not know is a fault', () async {
      final runner = await h.online();

      await runner.connection.receiveText('{"type":"warp"}');

      expect(runner.faults.single.code, 'unknown_frame');
      expect(runner.faults.single.message, contains('"warp"'));
    });

    test('a second hello is a fault', () async {
      final runner = await h.pair();
      await runner.hello();

      await runner.hello();

      expect(runner.faults.single.code, 'unexpected_frame');
      expect(runner.link.sentOf<ProbeFrame>(), hasLength(1));
    });

    test('a frame is read from text', () async {
      final runner = await h.pair();

      await runner.connection.receiveText(
        '{"type":"hello","version":"1.0.0","os":"linux","arch":"x64",'
        '"cores":4,"draining":false,"leases":[]}',
      );

      expect(runner.link.sentOf<ProbeFrame>(), hasLength(1));
      expect(runner.connection.runnerId, runner.id);
    });
  });

  group('hello', () {
    test('records the machine and asks for the probe', () async {
      final runner = await h.pair();

      await runner.hello(cores: 16);

      final probe = runner.link.sentOf<ProbeFrame>().single;
      expect(probe.commands, const RunnerProbe().commands);
      final record = (await h.runners.get(runner.id))!;
      expect(record.os, 'macos');
      expect(record.arch, 'arm64');
      expect(record.version, '1.0.0');
      expect(record.cores, 16);
      expect(record.lastHeartbeat, h.clock.now());
      // Probed runners only: it gets no job before the answer.
      expect(h.hub.statusOf(runner.id), RunnerStatus.offline);
      expect(schedulerRunners(), ['local']);
    });

    test(
      'the slots are a quarter of the cores unless the owner says',
      () async {
        final big = await h.online(cores: 16);
        final small = await h.online(cores: 2);
        final chosen = await h.online(cores: 16, maxJobs: 1);
        final zero = await h.online(maxJobs: 0);

        expect(h.hub.slotsOf(big.id), 4);
        expect(h.hub.slotsOf(small.id), 1);
        expect(h.hub.slotsOf(chosen.id), 1);
        expect(h.hub.slotsOf(zero.id), 1);
      },
    );

    test('a runner that says it drains gets no jobs', () async {
      final runner = await h.pair();

      await runner.hello(draining: true);
      await runner.answerProbe(macProbe());

      expect(h.hub.statusOf(runner.id), RunnerStatus.draining);
      expect(h.hub.slotsOf(runner.id), 0);
    });
  });

  group('probe', () {
    test('the capabilities are what the commands found', () async {
      final mac = await h.online(results: macProbe(android: true));
      final linux = await h.online(results: linuxProbe(swift: true));
      final bare = await h.online(results: macProbe(xcode: false, git: false));

      Set<Capability> found(FakeRunner runner) =>
          h.scheduler.runners.firstWhere((r) => r.id == runner.id).capabilities;
      expect(found(mac), {
        Capability.flutter,
        Capability.android,
        Capability.iosSign,
      });
      expect(found(linux), {
        Capability.flutter,
        Capability.android,
        Capability.swiftLinux,
      });
      expect(found(bare), isEmpty);
      expect((await h.runners.get(mac.id))!.capabilities, found(mac));
    });

    test('the runner hears what it offers and why not, after the '
        'probe', () async {
      final runner = await h.pair();
      await runner.hello();
      expect(runner.link.sentOf<ProbedFrame>(), isEmpty);

      await runner.answerProbe(macProbe());

      final probed = runner.link.sentOf<ProbedFrame>().single;
      expect(probed.capabilities, ['flutter', 'ios-sign']);
      expect(probed.missing.map((m) => m.capability), ['android']);
      expect(h.hub.missingOf(runner.id), probed.missing);
    });

    test('nothing is missing for a runner that is not connected', () async {
      final runner = await h.pair();
      await runner.hello();

      expect(h.hub.missingOf(runner.id), isNull);
      expect(h.hub.missingOf('rnr_nobody'), isNull);
    });

    test('an answer to another probe is ignored', () async {
      final runner = await h.pair();
      await runner.hello();

      await runner.send(
        ProbeResultFrame(probeId: 'prb_other', results: macProbe()),
      );

      expect(h.hub.statusOf(runner.id), RunnerStatus.offline);
      await runner.answerProbe(macProbe());
      expect(h.hub.statusOf(runner.id), RunnerStatus.online);
      // The answer is taken once.
      await runner.answerProbe(linuxProbe());
      expect(
        (await h.runners.get(runner.id))!.capabilities,
        contains(Capability.iosSign),
      );
    });

    test('announces the runner and records changes of capabilities', () async {
      final runner = await h.online(name: 'mac');
      await runner.connection.closed();
      final same = await h.reconnect(runner);
      await same.online();
      final again = await h.reconnect(runner);
      await again.hello();
      await again.answerProbe(macProbe(android: true));

      expect(await h.eventsOf<RunnerConnected>(), [
        RunnerConnected(
          runnerId: runner.id,
          name: 'mac',
          capabilities: const ['flutter', 'ios-sign'],
          slots: 2,
        ),
        RunnerConnected(
          runnerId: runner.id,
          name: 'mac',
          capabilities: const ['flutter', 'ios-sign'],
          slots: 2,
        ),
        RunnerConnected(
          runnerId: runner.id,
          name: 'mac',
          capabilities: const ['android', 'flutter', 'ios-sign'],
          slots: 2,
        ),
      ]);
      expect(await h.eventsOf<RunnerCapabilitiesChanged>(), [
        RunnerCapabilitiesChanged(
          runnerId: runner.id,
          name: 'mac',
          from: const [],
          to: const ['flutter', 'ios-sign'],
        ),
        RunnerCapabilitiesChanged(
          runnerId: runner.id,
          name: 'mac',
          from: const ['flutter', 'ios-sign'],
          to: const ['android', 'flutter', 'ios-sign'],
        ),
      ]);
    });

    test('a runner with nothing to offer changes nothing', () async {
      await h.online(results: macProbe(xcode: false, git: false));

      expect(await h.eventsOf<RunnerCapabilitiesChanged>(), isEmpty);
    });
  });

  group('sweep', () {
    test('drops a runner that does not answer the probe', () async {
      final runner = await h.pair();
      await runner.hello();

      h.clock.advance(const Duration(seconds: 59));
      await h.hub.sweep();
      expect(runner.link.closeCode, isNull);

      h.clock.advance(const Duration(seconds: 1));
      await h.hub.sweep();
      expect(runner.link.closeCode, runnerTimeoutCloseCode);
      expect(h.hub.isConnected(runner.id), isFalse);
    });

    test('drops a runner that was quiet for a whole lease', () async {
      final runner = await h.online();

      h.clock.advance(const Duration(seconds: 89));
      await h.hub.sweep();
      expect(runner.link.closeCode, isNull);

      h.clock.advance(const Duration(seconds: 1));
      await h.hub.sweep();
      expect(runner.link.closeCode, runnerTimeoutCloseCode);
      expect(schedulerRunners(), ['local']);
      expect(await h.eventsOf<RunnerDisconnected>(), hasLength(1));
    });

    test('a heartbeat keeps a runner that has nothing to do', () async {
      final runner = await h.online();

      for (var i = 0; i < 6; i++) {
        h.clock.advance(const Duration(seconds: 30));
        await runner.heartbeat(const []);
        await h.hub.sweep();
      }

      expect(runner.link.closeCode, isNull);
      expect(runner.link.sentOf<HeartbeatAckFrame>(), hasLength(6));
      expect((await h.runners.get(runner.id))!.lastHeartbeat, h.clock.now());
    });
  });

  group('drain', () {
    test('stops the jobs, and starting again brings them back', () async {
      final runner = await h.online();
      expect(h.hub.statusOf(runner.id), RunnerStatus.online);

      await runner.send(const DrainFrame());
      expect(h.hub.statusOf(runner.id), RunnerStatus.draining);
      expect(h.hub.slotsOf(runner.id), 0);

      await runner.send(const DrainFrame(draining: false));
      expect(h.hub.statusOf(runner.id), RunnerStatus.online);
      expect(h.hub.slotsOf(runner.id), 2);
      // A runner that was not draining and says so changes nothing.
      await runner.send(const DrainFrame(draining: false));
      expect(h.hub.slotsOf(runner.id), 2);
    });
  });
}
