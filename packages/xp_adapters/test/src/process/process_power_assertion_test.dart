import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late FakeProcessRunner runner;
  late List<String> warnings;

  setUp(() {
    // The helper runs until it is killed.
    runner = FakeProcessRunner((call) => Completer<ProcessOutput>().future);
    warnings = [];
  });

  ProcessPowerAssertion assertion() => ProcessPowerAssertion(
    runner: runner,
    executable: 'helper',
    arguments: ['--on'],
    onWarning: warnings.add,
  );

  group('ProcessPowerAssertion', () {
    test('runs the helper while it is held', () async {
      final power = assertion();

      await power.hold();

      expect(power.isHeld, isTrue);
      expect(runner.calls.single.executable, 'helper');
      expect(runner.calls.single.arguments, ['--on']);
      expect(runner.calls.single.killed, isFalse);
    });

    test('stops the helper on release', () async {
      final power = assertion();
      await power.hold();

      await power.release();

      expect(power.isHeld, isFalse);
      expect(runner.calls.single.killed, isTrue);
    });

    test('does not start a second helper', () async {
      final power = assertion();

      await power.hold();
      await power.hold();

      expect(runner.calls, hasLength(1));
    });

    test('has nothing to release before it was held', () async {
      await assertion().release();

      expect(runner.calls, isEmpty);
    });

    test('can be held again after a release', () async {
      final power = assertion();
      await power.hold();
      await power.release();

      await power.hold();

      expect(runner.calls, hasLength(2));
    });

    test('warns when the helper is not there', () async {
      runner.startError = const ProcessStartException('helper', 'not found');
      final power = assertion();

      await power.hold();

      expect(power.isHeld, isFalse);
      expect(warnings.single, allOf(contains('not found'), contains('helper')));
    });

    test('warns when the helper ends by itself, and holds nothing', () async {
      final exits = Completer<ProcessOutput>();
      final power = ProcessPowerAssertion(
        runner: _SelfEndingRunner(exits.future),
        executable: 'helper',
        arguments: const [],
        onWarning: warnings.add,
      );
      await power.hold();

      exits.complete(const ProcessOutput(exitCode: 3));
      await Future<void>.delayed(Duration.zero);

      expect(power.isHeld, isFalse);
      expect(warnings.single, contains('exit code 3'));
    });

    test('does not need a warning sink', () async {
      final exits = Completer<ProcessOutput>();
      final power = ProcessPowerAssertion(
        runner: _SelfEndingRunner(exits.future),
        executable: 'helper',
        arguments: const [],
      );
      await power.hold();

      exits.complete(const ProcessOutput(exitCode: 0));
      await Future<void>.delayed(Duration.zero);

      expect(power.isHeld, isFalse);
    });
  });

  group('createPowerAssertion', () {
    test(
      'keeps a Mac awake with caffeinate for as long as xpd lives',
      () async {
        final power = createPowerAssertion(
          runner: runner,
          operatingSystem: 'macos',
          pid: 4711,
          onWarning: warnings.add,
        );

        await power.hold();

        expect(runner.calls.single.executable, 'caffeinate');
        expect(runner.calls.single.arguments, ['-i', '-w', '4711']);
      },
    );

    test('keeps Linux awake with a systemd inhibitor lock', () async {
      final power = createPowerAssertion(
        runner: runner,
        operatingSystem: 'linux',
        pid: 1,
      );

      await power.hold();

      expect(runner.calls.single.executable, 'systemd-inhibit');
      expect(
        runner.calls.single.arguments,
        containsAll(['--what=sleep:idle', 'sleep', 'infinity']),
      );
    });

    test('warns on a system it cannot keep awake', () async {
      final power = createPowerAssertion(
        runner: runner,
        operatingSystem: 'windows',
        pid: 1,
        onWarning: warnings.add,
      );

      await power.hold();
      await power.release();

      expect(runner.calls, isEmpty);
      expect(warnings.single, contains('windows'));
    });

    test('does not need a warning sink', () async {
      final power = createPowerAssertion(
        runner: runner,
        operatingSystem: 'windows',
        pid: 1,
      );

      await power.hold();
    });
  });
}

/// A runner whose process ends when the test says.
class _SelfEndingRunner implements ProcessRunner {
  new(this._result);

  final Future<ProcessOutput> _result;

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async => _Helper(_result);
}

class _Helper implements RunningProcess {
  new(this.result);

  @override
  final Future<ProcessOutput> result;

  @override
  Future<void> closeStdin() async {}

  @override
  void kill() {}

  @override
  Future<void> writeStdin(String text) async {}
}
