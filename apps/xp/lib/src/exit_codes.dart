import 'package:xp_client/xp_client.dart';

/// The exit codes of `xp`, after `sysexits.h` as `mason_logger` spells them.
///
/// | code | meaning |
/// |---|---|
/// | 0 | success |
/// | 1 | the command ran, and what it watched ended badly (a failed job) |
/// | 64 | usage error: unknown command, missing or invalid arguments |
/// | 65 | the engine refused the content: an invalid workflow |
/// | 66 | no such project, job, run, release, artifact, credential or file |
/// | 69 | the engine cannot be reached or cannot serve (secrets locked) |
/// | 70 | the engine failed |
/// | 73 | a conflict: the approval was decided already, the project exists |
/// | 75 | a runner switched to another version; its service manager starts it |
/// | 77 | the token is rejected, or its kind may not do this |
/// | 78 | not connected: run `xp connect` |
abstract final class XpExit {
  /// The command ran, and the thing it watched failed.
  static const failed = 1;

  /// Success.
  static const ok = 0;

  /// Usage error.
  static const usage = 64;

  /// Invalid content.
  static const invalid = 65;

  /// Not found.
  static const notFound = 66;

  /// The engine is unavailable.
  static const unavailable = 69;

  /// The engine failed.
  static const software = 70;

  /// Conflict.
  static const conflict = 73;

  /// A runner switched to another version (an update, or a rollback) and has
  /// to be started again. A service manager does that, because the code is
  /// not 0 (`sysexits.h` `EX_TEMPFAIL`).
  static const restart = 75;

  /// Permission denied.
  static const permission = 77;

  /// Not connected.
  static const config = 78;

  /// The exit code for an error the engine answered with.
  static int forApi(ApiException error) => switch (error.statusCode) {
    400 => usage,
    401 || 403 => permission,
    404 => notFound,
    409 => conflict,
    422 => invalid,
    502 || 503 => unavailable,
    _ => software,
  };
}
