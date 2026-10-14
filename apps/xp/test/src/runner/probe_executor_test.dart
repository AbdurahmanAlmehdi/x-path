import 'dart:async';

import 'package:test/test.dart';
import 'package:xp/src/runner/probe_executor.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late FakeProcessRunner runner;

  ProbeExecutor executor(String os) =>
      ProbeExecutor(runner: runner, operatingSystem: os);

  setUp(() {
    runner = FakeProcessRunner(
      (call) => ProcessOutput(
        exitCode: 0,
        stdout: '${call.executable} ${call.arguments.join(' ')}\n',
        stderr: 'warning\n',
      ),
    );
  });

  test('runs the commands in order and reports what they printed', () async {
    final results = await executor('macos').run(const [
      ProbeCommand(id: 'os', executable: 'uname', arguments: ['-s']),
      ProbeCommand(id: 'git', executable: 'git', arguments: ['--version']),
    ]);

    expect(
      [for (final call in runner.calls) call.executable],
      ['uname', 'git'],
    );
    expect(results, [
      const ProbeResult(
        id: 'os',
        status: ProbeStatus.exited,
        exitCode: 0,
        stdout: 'uname -s\n',
        stderr: 'warning\n',
      ),
      const ProbeResult(
        id: 'git',
        status: ProbeStatus.exited,
        exitCode: 0,
        stdout: 'git --version\n',
        stderr: 'warning\n',
      ),
    ]);
  });

  test('reports a failing command with its exit code', () async {
    runner.handler = (call) => const ProcessOutput(exitCode: 1);

    final results = await executor('linux').run(const [
      ProbeCommand(id: 'sdk', executable: 'sh', arguments: ['-c', 'exit 1']),
    ]);

    expect(results.single.exitCode, 1);
    expect(results.single.succeeded, isFalse);
  });

  test('skips a command meant for another operating system', () async {
    final results = await executor('linux').run(const [
      ProbeCommand(
        id: 'xcode_select',
        executable: 'xcode-select',
        onlyOn: 'macos',
      ),
      ProbeCommand(id: 'swift', executable: 'swift', onlyOn: 'linux'),
    ]);

    expect(
      [for (final r in results) (r.id, r.status)],
      [('xcode_select', ProbeStatus.skipped), ('swift', ProbeStatus.exited)],
    );
    expect(runner.calls.map((c) => c.executable), ['swift']);
  });

  test('skips a command whose condition did not succeed', () async {
    runner.handler = (call) =>
        ProcessOutput(exitCode: call.executable == 'xcode-select' ? 2 : 0);

    final results = await executor('macos').run(const [
      ProbeCommand(id: 'xcode_select', executable: 'xcode-select'),
      ProbeCommand(
        id: 'xcodebuild',
        executable: 'xcodebuild',
        requires: 'xcode_select',
      ),
      ProbeCommand(id: 'late', executable: 'late', requires: 'nothing'),
    ]);

    expect(
      [for (final r in results) r.status],
      [ProbeStatus.exited, ProbeStatus.skipped, ProbeStatus.skipped],
    );
    expect(runner.calls.map((c) => c.executable), ['xcode-select']);
  });

  test('runs a command whose condition succeeded', () async {
    final results = await executor('macos').run(const [
      ProbeCommand(id: 'xcode_select', executable: 'xcode-select'),
      ProbeCommand(
        id: 'xcodebuild',
        executable: 'xcodebuild',
        requires: 'xcode_select',
      ),
    ]);

    expect(results.last.status, ProbeStatus.exited);
  });

  test('says a program is not installed', () async {
    runner.startError = const ProcessStartException('swift', 'not found');

    final results = await executor('linux')
        .run(const [ProbeCommand(id: 'swift', executable: 'swift')]);

    expect(results.single.status, ProbeStatus.notStarted);
    expect(results.single.exitCode, isNull);
  });

  test('stops a command that takes too long', () async {
    runner.handler = (call) => Completer<ProcessOutput>().future;

    final results = await executor('linux').run(const [
      ProbeCommand(id: 'slow', executable: 'slow', timeoutSeconds: 0),
    ]);

    expect(results.single.status, ProbeStatus.timedOut);
    expect(runner.calls.single.killed, isTrue);
  });

  test('keeps at most 64 KiB of the output of a command', () async {
    runner.handler = (call) =>
        ProcessOutput(exitCode: 0, stdout: 'x' * (70 * 1024), stderr: 'y' * 10);

    final results = await executor('linux')
        .run(const [ProbeCommand(id: 'noisy', executable: 'noisy')]);

    expect(results.single.stdout.length, 64 * 1024);
    expect(results.single.stderr.length, 10);
  });
}
