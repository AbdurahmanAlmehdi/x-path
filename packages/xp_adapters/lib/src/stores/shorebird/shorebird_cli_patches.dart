import 'package:xp_adapters/src/stores/shorebird/shorebird_cli.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Moves Shorebird patches with `shorebird --json patches promote` and
/// `shorebird --json patches rollback` (U7b).
///
/// Promoting is `set-track` to `stable`. Both answer success for a patch that
/// is where it is asked to go already. The API key is read from the secret
/// store and handed to the CLI in `SHOREBIRD_TOKEN`, never as an argument,
/// and taken out of anything the CLI printed before it is shown.
class ShorebirdCliPatches implements ShorebirdPatches {
  /// Creates the adapter. The CLI is [executable]; it has [timeout] to answer.
  new({
    required ProcessRunner runner,
    required this._secrets,
    String executable = 'shorebird',
    Duration timeout = const Duration(minutes: 2),
  }) : _cli = ShorebirdCli(
         runner: runner,
         executable: executable,
         timeout: timeout,
       );

  final ShorebirdCli _cli;
  final SecretStore _secrets;

  @override
  Future<void> change({
    required String appId,
    required String releaseVersion,
    required int patchNumber,
    required PatchAction action,
    String? tokenSecret,
  }) async {
    String? token;
    if (tokenSecret != null) {
      try {
        token = await _secrets.read(tokenSecret);
      } on SecretStoreException catch (error) {
        throw ShorebirdPatchesException(
          'The Shorebird API key cannot be read: ${error.message}',
        );
      }
      if (token == null) {
        throw const ShorebirdPatchesException(
          'The Shorebird API key of the flavor is gone. Add it again in '
          'Credentials.',
        );
      }
    }
    final result = await _cli.run([
      '--json',
      'patches',
      action.wire,
      '--app-id',
      appId,
      '--release-version',
      releaseVersion,
      '--patch-number',
      '$patchNumber',
    ], token: token);
    if (result case ShorebirdCliFailure(:final problem, :final output)) {
      throw ShorebirdPatchesException(switch (problem) {
        ShorebirdCliProblem.missing =>
          'The Shorebird CLI is not installed on the engine.',
        ShorebirdCliProblem.timedOut => 'The Shorebird CLI did not answer.',
        ShorebirdCliProblem.failed =>
          token == null ? output : output.replaceAll(token, '***'),
      });
    }
  }
}
