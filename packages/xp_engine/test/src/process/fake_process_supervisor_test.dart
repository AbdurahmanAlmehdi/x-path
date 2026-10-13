// The watcher ends with the process it listens to.
// ignore_for_file: cancel_subscriptions

import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late ManualClock clock;
  const spec = ProcessSpec('tool', ['a'], environment: {});

  setUp(() => clock = ManualClock(DateTime.utc(2026, 10, 13)));

  group('FakeProcessSupervisor', () {
    test('records what it starts and numbers the process ids', () async {
      final supervisor = FakeProcessSupervisor((_) => 0, clock: clock);

      final first = await supervisor.start(spec);
      final second = await supervisor.start(spec);

      expect(supervisor.specs, [spec, spec]);
      expect(supervisor.processes, hasLength(2));
      expect(first.pid, 4000);
      expect(second.pid, 4001);
    });

    test('throws the start error', () async {
      final supervisor = FakeProcessSupervisor((_) => 0, clock: clock)
        ..startError = const ProcessStartException('tool', 'nope');

      await expectLater(
        supervisor.start(spec),
        throwsA(isA<ProcessStartException>()),
      );
      expect(supervisor.specs, isEmpty);
    });

    test('masks nothing unless given a masker', () {
      expect(
        FakeProcessSupervisor((_) => 0, clock: clock).masker,
        isA<NoMasking>(),
      );
    });
  });

  group('FakeSupervisedProcess', () {
    test('streams the lines the handler emits and returns its code', () async {
      final supervisor = FakeProcessSupervisor((process) async {
        await process.emit('one');
        clock.advance(const Duration(seconds: 1));
        await process.emit('two', stream: LogStream.stderr);
        return 3;
      }, clock: clock);
      final process = await supervisor.start(spec);
      final lines = <OutputLine>[];
      process.output.subscribe().listen(lines.add);

      final exit = await process.run();

      expect(exit, const ProcessExit(exitCode: 3));
      expect(lines.map((l) => (l.seq, l.stream, l.text, l.timestamp)), [
        (1, LogStream.stdout, 'one', DateTime.utc(2026, 10, 13)),
        (2, LogStream.stderr, 'two', DateTime.utc(2026, 10, 13, 0, 0, 1)),
      ]);
    });

    test('numbers its lines for readers that may lose some', () async {
      final supervisor = FakeProcessSupervisor((process) async {
        for (var i = 0; i < 4; i++) {
          await process.emit('line $i');
        }
        return 0;
      }, clock: clock);
      final process = await supervisor.start(spec);
      final seen = <String>[];
      final watcher = process.output.watch(capacity: 1).listen((event) {
        seen.add(switch (event) {
          FanOutItem(:final value) => value.text,
          FanOutGap(:final count) => 'gap $count',
        });
      })..pause();

      await process.run();
      watcher.resume();
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['gap 3', 'line 3']);
    });

    test('runs until cancelled when the handler never returns', () async {
      final supervisor = FakeProcessSupervisor((process) async {
        await process.cancelRequested;
        await Future<void>.delayed(const Duration(days: 1));
        return 0;
      }, clock: clock);
      final process = await supervisor.start(spec) as FakeSupervisedProcess;
      final running = process.run();

      await process.cancel();
      final exit = await running;

      expect(exit, const ProcessExit(exitCode: -15, cancelled: true));
      expect(process.wasCancelled, isTrue);
    });

    test('a cancel before run makes it end cancelled at once', () async {
      final supervisor = FakeProcessSupervisor(
        (process) => Completer<int>().future,
        clock: clock,
      );
      final process = await supervisor.start(spec);

      await process.cancel();
      await process.cancel();

      expect(
        await process.run(),
        const ProcessExit(exitCode: -15, cancelled: true),
      );
    });

    test('fails run when the handler throws', () async {
      final supervisor = FakeProcessSupervisor(
        (process) => throw StateError('boom'),
        clock: clock,
      );
      final process = await supervisor.start(spec);

      await expectLater(process.run(), throwsStateError);
    });
  });

  group('FakeProcessGroupControl', () {
    test('records signals and kills groups the way it is told', () {
      final control = FakeProcessGroupControl(alive: [1, 2, 3])
        ..dieOnTerminate = false
        ..terminate(1);
      expect(control.isAlive(1), isTrue);
      control
        ..kill(1)
        ..dieOnTerminate = true
        ..terminate(2);
      expect(control.isAlive(1), isFalse);

      expect(control.isAlive(2), isFalse);
      expect(control.isAlive(3), isTrue);
      expect(control.signals, ['TERM 1', 'KILL 1', 'TERM 2']);
    });
  });
}
