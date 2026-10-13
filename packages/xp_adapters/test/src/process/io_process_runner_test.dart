@Tags(['process'])
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const runner = IoProcessRunner();

  test('collects the output and exit code of a process', () async {
    final output = await runner.run('sh', [
      '-c',
      'echo out; echo err >&2; exit 3',
    ]);

    expect(
      output,
      const ProcessOutput(exitCode: 3, stdout: 'out\n', stderr: 'err\n'),
    );
  });

  test('feeds stdin to the process and passes arguments untouched', () async {
    final output = await runner.run('sh', [
      '-c',
      r'cat; echo "$0"',
      r'$HOME "quoted"',
    ], stdin: 'multi\nline é');

    expect(output.stdout, 'multi\nline é\$HOME "quoted"\n');
  });

  test('throws a ProcessStartException for a missing program', () async {
    await expectLater(
      runner.start('/definitely/not/a/program', []),
      throwsA(
        isA<ProcessStartException>().having(
          (e) => e.executable,
          'executable',
          '/definitely/not/a/program',
        ),
      ),
    );
  });

  test('kills a process that outlives the timeout', () async {
    await expectLater(
      runner.run('sleep', ['30'], timeout: const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('ignores input for a process that already exited', () async {
    final process = await runner.start('sh', ['-c', 'exit 0']);
    await process.result;

    await process.writeStdin('x' * 100000);
    await process.closeStdin();

    expect((await process.result).exitCode, 0);
  });
}
