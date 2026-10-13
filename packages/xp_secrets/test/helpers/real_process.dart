import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xp_engine/xp_engine.dart';

/// Runs the process of [call] for real, for use as a [FakeProcessRunner]
/// handler.
///
/// The process gets the standard input of [call]. If [whileAlive] is given it
/// runs after the input was written and before it is closed, that is while the
/// process is waiting for more input and so certainly alive; it gets the pid.
Future<ProcessOutput> runForReal(
  FakeProcessCall call, {
  FutureOr<void> Function(int pid)? whileAlive,
}) async {
  final process = await Process.start(call.executable, call.arguments);
  const decoder = Utf8Decoder(allowMalformed: true);
  final stdout = decoder.bind(process.stdout).join();
  final stderr = decoder.bind(process.stderr).join();
  process.stdin.write(call.stdin);
  await process.stdin.flush();
  await whileAlive?.call(process.pid);
  await process.stdin.close();
  return ProcessOutput(
    exitCode: await process.exitCode,
    stdout: await stdout,
    stderr: await stderr,
  );
}

/// A runner that really runs `chmod` and nothing else.
FakeProcessRunner chmodRunner() => FakeProcessRunner((call) {
  if (call.executable != 'chmod') {
    throw StateError('Unexpected program ${call.executable}.');
  }
  return runForReal(call);
});

/// The permission bits of the file at [path], for example `0x180` for 0600.
int permissionsOf(String path) => File(path).statSync().mode & 0xfff;
