import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('ProcessOutput', () {
    test('compares by value', () {
      expect(
        const ProcessOutput(exitCode: 1, stdout: 'a', stderr: 'b'),
        const ProcessOutput(exitCode: 1, stdout: 'a', stderr: 'b'),
      );
      expect(
        const ProcessOutput(exitCode: 0),
        isNot(const ProcessOutput(exitCode: 1)),
      );
    });

    test('defaults its streams to empty', () {
      const output = ProcessOutput(exitCode: 0);

      expect(output.stdout, isEmpty);
      expect(output.stderr, isEmpty);
    });
  });

  test('ProcessStartException names the program and the reason', () {
    const error = ProcessStartException('security', 'not found');

    expect(error.toString(), 'ProcessStartException: security: not found');
  });

  group('ProcessRunner.run', () {
    test('feeds stdin, closes it and returns the output', () async {
      final runner = FakeProcessRunner(
        (call) => ProcessOutput(exitCode: 3, stdout: 'got ${call.stdin}'),
      );

      final output = await runner.run('tool', ['a', 'b'], stdin: 'hello');

      expect(output, const ProcessOutput(exitCode: 3, stdout: 'got hello'));
      expect(runner.calls.single.executable, 'tool');
      expect(runner.calls.single.arguments, ['a', 'b']);
    });

    test('passes the working directory and environment on', () async {
      final runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0));

      await runner.run(
        'tool',
        [],
        workingDirectory: '/work',
        environment: {'A': 'b'},
      );
      await runner.run('tool', []);

      expect(runner.calls.first.workingDirectory, '/work');
      expect(runner.calls.first.environment, {'A': 'b'});
      expect(runner.calls.last.workingDirectory, isNull);
      expect(runner.calls.last.environment, isNull);
    });

    test('closes stdin even when there is nothing to write', () async {
      final runner = FakeProcessRunner(
        (call) => ProcessOutput(exitCode: 0, stdout: '[${call.stdin}]'),
      );

      final output = await runner.run('tool', []);

      expect(output.stdout, '[]');
    });

    test('returns the output of a process that beats the timeout', () async {
      final runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0));

      final output = await runner.run(
        'tool',
        [],
        timeout: const Duration(seconds: 5),
      );

      expect(output.exitCode, 0);
      expect(runner.calls.single.killed, isFalse);
    });

    test('kills a process that outlives the timeout', () async {
      final runner = FakeProcessRunner(
        (_) => Completer<ProcessOutput>().future,
      );

      await expectLater(
        runner.run('tool', [], timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
      expect(runner.calls.single.killed, isTrue);
    });

    test('lets a start failure through', () async {
      final runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0))
        ..startError = const ProcessStartException('tool', 'missing');

      await expectLater(
        runner.run('tool', []),
        throwsA(isA<ProcessStartException>()),
      );
      expect(runner.calls, isEmpty);
    });
  });

  group('FakeProcessRunner', () {
    test('closing stdin twice answers once', () async {
      var answered = 0;
      final runner = FakeProcessRunner((_) {
        answered++;
        return const ProcessOutput(exitCode: 0);
      });
      final process = await runner.start('tool', []);

      await process.closeStdin();
      await process.result;
      await process.closeStdin();

      expect(answered, 1);
    });

    test('a killed process exits with a signal code', () async {
      final runner = FakeProcessRunner(
        (_) => Completer<ProcessOutput>().future,
      );
      final process = await runner.start('tool', []);
      await process.closeStdin();

      process.kill();

      expect((await process.result).exitCode, -15);
      expect(runner.calls.single.killed, isTrue);
    });

    test('a kill after the answer changes nothing', () async {
      final runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0));
      final process = await runner.start('tool', []);
      await process.closeStdin();
      await process.result;

      process.kill();

      expect((await process.result).exitCode, 0);
    });

    test('a failing handler fails the result', () async {
      final runner = FakeProcessRunner((_) => throw StateError('boom'));
      final process = await runner.start('tool', []);
      await process.closeStdin();

      await expectLater(process.result, throwsA(isA<StateError>()));
    });

    test('a failing handler after a kill changes nothing', () async {
      final gate = Completer<ProcessOutput>();
      final runner = FakeProcessRunner((_) => gate.future);
      final process = await runner.start('tool', []);
      await process.closeStdin();
      process.kill();

      gate.completeError(StateError('late'));

      expect((await process.result).exitCode, -15);
    });
  });
}
