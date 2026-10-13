import 'package:xp_api/xp_api.dart';
import 'package:xpd/src/version.dart';

/// Exit code for a command line that `xpd` does not understand
/// (`EX_USAGE` in `sysexits.h`).
const _usageExitCode = 64;

/// Runs `xpd` with [args] and returns the process exit code.
int runXpd(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length == 1 && args.single == '--version') {
    out.writeln('xpd $packageVersion (API v$apiVersion)');
    return 0;
  }
  err.writeln('Usage: xpd --version');
  return _usageExitCode;
}
