import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late FakeProcessRunner runner;

  ShorebirdCli cli({Duration timeout = const Duration(minutes: 2)}) =>
      ShorebirdCli(runner: runner, timeout: timeout);

  setUp(() {
    runner = FakeProcessRunner(
      (call) => const ProcessOutput(
        exitCode: 0,
        stdout: '{"status": "success", "data": {"a": 1}}',
      ),
    );
  });

  test('runs the CLI without prompts, the token in the environment', () async {
    await cli().run(['--json', 'x'], token: 'sb_api_secret');

    final call = runner.calls.single;
    expect(call.executable, 'shorebird');
    expect(call.arguments, ['--json', 'x']);
    expect(call.environment, {
      'CI': 'true',
      'SHOREBIRD_TOKEN': 'sb_api_secret',
    });
  });

  test('uses the login of the machine without a token', () async {
    await cli().run(['--json', 'x']);

    expect(runner.calls.single.environment, {'CI': 'true'});
  });

  test('reads the data of the envelope', () async {
    final result = await cli().run(['--json', 'x']);

    expect((result as ShorebirdCliSuccess).data, {'a': 1});
  });

  test('has empty data when the envelope has none', () async {
    runner.handler = (call) =>
        const ProcessOutput(exitCode: 0, stdout: '{"status": "success"}');

    final result = await cli().run(['--json', 'x']);

    expect((result as ShorebirdCliSuccess).data, isEmpty);
  });

  test('fails with everything the CLI printed on a non-zero exit', () async {
    runner.handler = (call) =>
        const ProcessOutput(exitCode: 1, stdout: 'out', stderr: 'err');

    final result = await cli().run(['--json', 'x']) as ShorebirdCliFailure;

    expect(result.problem, ShorebirdCliProblem.failed);
    expect(result.output, 'out\nerr');
  });

  test('fails for output that is not the envelope', () async {
    for (final stdout in ['', 'hello', '[]', '{"status": "error"}']) {
      runner.handler = (call) => ProcessOutput(exitCode: 0, stdout: stdout);

      final result = await cli().run(['--json', 'x']);

      expect(
        (result as ShorebirdCliFailure).problem,
        ShorebirdCliProblem.failed,
        reason: stdout,
      );
    }
  });

  test('fails when the program is missing or too slow', () async {
    runner.startError = const ProcessStartException('shorebird', 'not found');

    expect(
      (await cli().run(['x']) as ShorebirdCliFailure).problem,
      ShorebirdCliProblem.missing,
    );

    runner
      ..startError = null
      ..handler = (call) => Completer<ProcessOutput>().future;

    expect(
      (await cli(
        timeout: const Duration(milliseconds: 10),
      ).run(['x']) as ShorebirdCliFailure).problem,
      ShorebirdCliProblem.timedOut,
    );
  });
}
