import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('ToolchainException names the tool and the problem', () {
    const error = ToolchainException('perl', 'not found');

    expect(error.toString(), 'ToolchainException: perl: not found');
  });

  group('ProcessSpec', () {
    test('compares by value', () {
      const spec = ProcessSpec('git', ['status'], environment: {'A': 'b'});

      expect(
        spec,
        const ProcessSpec('git', ['status'], environment: {'A': 'b'}),
      );
      expect(
        spec,
        isNot(
          const ProcessSpec(
            'git',
            ['status'],
            environment: {'A': 'b'},
            workingDirectory: '/x',
          ),
        ),
      );
    });
  });

  group('ProcessExit', () {
    test('succeeded means exit code 0 and not cancelled', () {
      expect(const ProcessExit(exitCode: 0).succeeded, isTrue);
      expect(const ProcessExit(exitCode: 1).succeeded, isFalse);
      expect(
        const ProcessExit(exitCode: 0, cancelled: true).succeeded,
        isFalse,
      );
    });

    test('compares by value', () {
      expect(
        const ProcessExit(exitCode: -15, cancelled: true),
        const ProcessExit(exitCode: -15, cancelled: true),
      );
    });
  });

  group('ProcessGroupKiller', () {
    late FakeProcessGroupControl control;
    late List<Duration> delays;

    ProcessGroupKiller killer({Duration grace = const Duration(seconds: 1)}) =>
        ProcessGroupKiller(
          control: control,
          grace: grace,
          pollInterval: const Duration(milliseconds: 100),
          delay: (duration) async => delays.add(duration),
        );

    setUp(() {
      control = FakeProcessGroupControl(alive: [100]);
      delays = [];
    });

    test('terminates a group that ends within the grace period', () async {
      final needed = await killer().stop(100);

      expect(needed, isFalse);
      expect(control.signals, ['TERM 100']);
      expect(delays, isEmpty);
    });

    test('kills a group that outlives the grace period', () async {
      control.dieOnTerminate = false;

      final needed = await killer().stop(100);

      expect(needed, isTrue);
      expect(control.signals, ['TERM 100', 'KILL 100']);
      expect(delays, hasLength(10));
    });

    test('stops waiting as soon as the group is gone', () async {
      control.dieOnTerminate = false;
      var polls = 0;
      final stopper = ProcessGroupKiller(
        control: control,
        grace: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 100),
        delay: (_) async {
          if (++polls == 3) control.alive.remove(100);
        },
      );

      final needed = await stopper.stop(100);

      expect(needed, isFalse);
      expect(polls, 3);
      expect(control.signals, ['TERM 100']);
    });

    test('does not signal a group that is not alive', () async {
      expect(await killer().stop(200), isFalse);
      expect(control.signals, isEmpty);
    });

    test('never signals a group id that cannot be a job', () async {
      control.alive.addAll([0, 1]);

      expect(await killer().stop(0), isFalse);
      expect(await killer().stop(1), isFalse);
      expect(control.signals, isEmpty);
    });

    test('needs a positive poll interval', () {
      expect(
        () => ProcessGroupKiller(control: control, pollInterval: Duration.zero),
        throwsA(isA<AssertionError>()),
      );
    });

    test('waits ten seconds by default', () {
      final defaults = ProcessGroupKiller(control: control);

      expect(defaults.grace, const Duration(seconds: 10));
      expect(defaults.pollInterval, const Duration(milliseconds: 50));
    });

    test('waits with Future.delayed by default', () async {
      control.dieOnTerminate = false;
      final fast = ProcessGroupKiller(
        control: control,
        grace: const Duration(milliseconds: 20),
        pollInterval: const Duration(milliseconds: 5),
      );

      expect(await fast.stop(100), isTrue);
    });
  });
}
