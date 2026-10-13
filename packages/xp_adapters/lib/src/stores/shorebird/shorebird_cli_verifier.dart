import 'package:xp_adapters/src/stores/shorebird/shorebird_cli.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The prefix of a Shorebird API key (D-20). The `login:ci` tokens that came
/// before them stopped working on 2026-10-01.
const shorebirdApiKeyPrefix = 'sb_api_';

final _network = RegExp(
  'socketexception|failed host lookup|connection (refused|reset|closed)|'
  'timed out|network|handshake|service unavailable|bad gateway',
  caseSensitive: false,
);

final _refused = RegExp(
  'not logged in|log in|unauthorized|unauthenticated|invalid|expired|revoked|'
  r'forbidden|\b40[13]\b|api key|credentials',
  caseSensitive: false,
);

/// Checks a Shorebird API key with an authenticated read of the CLI:
/// `shorebird account whoami --json`, run with the key in `SHOREBIRD_TOKEN`.
///
/// A key that does not start with `sb_api_` is refused without asking
/// Shorebird. The CLI says "no" in words, not in an exit code of its own, so
/// only output that says the login is wrong counts as a refusal; any other
/// failure (no network, a CLI that crashes) says nothing about the key.
class ShorebirdCliVerifier implements CredentialVerifier {
  /// Creates the verifier over the CLI.
  const new(this._cli);

  final ShorebirdCli _cli;

  @override
  CredentialKind get kind => CredentialKind.shorebird;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final token = (material as TokenMaterial).token;
    if (!token.startsWith(shorebirdApiKeyPrefix)) {
      return const VerificationResult.rejected(
        'This is not a Shorebird API key: it does not start with '
        '$shorebirdApiKeyPrefix.',
        fix:
            'Create an API key in the Shorebird console (Account, API Keys). '
            'The tokens of `shorebird login:ci` stopped working on '
            '2026-10-01.',
      );
    }
    final result = await _cli.run([
      'account',
      'whoami',
      '--json',
    ], token: token);
    switch (result) {
      case ShorebirdCliSuccess(:final data):
        final email = data['email'];
        return VerificationResult.verified(
          account: email is String && email.isNotEmpty ? email : null,
        );
      case ShorebirdCliFailure(problem: ShorebirdCliProblem.missing):
        return const VerificationResult.unreachable(
          'The Shorebird CLI could not be started.',
          fix:
              'Install Shorebird on the engine machine '
              '(https://docs.shorebird.dev) and put it on the PATH.',
        );
      case ShorebirdCliFailure(problem: ShorebirdCliProblem.timedOut):
        return const VerificationResult.unreachable(
          'The Shorebird CLI did not answer in time.',
          fix: 'Try again later.',
        );
      case ShorebirdCliFailure(:final output):
        final shown = _shown(output, token);
        if (!_network.hasMatch(output) && _refused.hasMatch(output)) {
          return VerificationResult.rejected(
            'Shorebird refused the API key: $shown',
            fix:
                'The key was revoked or has expired (keys last a year by '
                'default). Create a new API key in the Shorebird console and '
                'save it again.',
          );
        }
        return VerificationResult.unreachable(
          'The Shorebird CLI could not check the key: $shown',
          fix: 'Run `shorebird account whoami` by hand to see why.',
        );
    }
  }

  /// The first line that says something, without the token, at most 200
  /// characters.
  String _shown(String output, String token) {
    final line = output
        .split('\n')
        .map((line) => line.replaceAll(token, '***').trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => 'no output');
    return line.length <= 200 ? line : '${line.substring(0, 200)}...';
  }
}
