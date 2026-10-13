import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';

/// Checks that a Slack webhook URL has the shape of one
/// (`https://hooks.slack.com/services/T.../B.../...`). Nothing is sent: a
/// message in a channel is not a check.
class SlackWebhookVerifier implements CredentialVerifier {
  /// Creates the verifier.
  const new();

  @override
  CredentialKind get kind => CredentialKind.slack;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final url = Uri.tryParse((material as SlackMaterial).webhookUrl);
    final shaped =
        url != null &&
        url.scheme == 'https' &&
        url.host == 'hooks.slack.com' &&
        url.pathSegments.length == 4 &&
        url.pathSegments.first == 'services' &&
        url.pathSegments.every((segment) => segment.isNotEmpty);
    if (shaped) return const VerificationResult.verified();
    return const VerificationResult.rejected(
      'This is not a Slack incoming webhook URL.',
      fix:
          'Copy the webhook URL of the Slack app (Incoming Webhooks): '
          'https://hooks.slack.com/services/T.../B.../...',
    );
  }
}
