import 'dart:async';
import 'dart:io';

import 'package:xpd/xpd.dart';

Future<void> main(List<String> args) async {
  final shutdown = StreamController<void>.broadcast();
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) => shutdown.add(null));
  }
  final code = await runXpd(
    args,
    out: stdout,
    err: stderr,
    shutdown: shutdown.stream,
    environment: Platform.environment,
    operatingSystem: Platform.operatingSystem,
  );
  await Future.wait([stdout.flush(), stderr.flush()]);
  // The signal watchers would keep the process alive.
  exit(code);
}
