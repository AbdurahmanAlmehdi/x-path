import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const verifier = SlackWebhookVerifier();

  Future<VerificationResult> verify(String url) =>
      verifier.verify(SlackMaterial(url), const CredentialTarget());

  test('is the verifier of Slack webhooks', () {
    expect(verifier.kind, CredentialKind.slack);
  });

  test('accepts the shape of an incoming webhook', () async {
    expect(
      await verify('https://hooks.slack.com/services/T000/B000/XXXX'),
      const VerificationResult.verified(),
    );
  });

  test('rejects anything else, without sending a message', () async {
    for (final url in [
      'http://hooks.slack.com/services/T000/B000/XXXX',
      'https://example.com/services/T000/B000/XXXX',
      'https://hooks.slack.com/services/T000/B000',
      'https://hooks.slack.com/other/T000/B000/XXXX',
      'https://hooks.slack.com/services//B000/XXXX',
      'not a url',
    ]) {
      final result = await verify(url);

      expect(result.status, CredentialStatus.rejected, reason: url);
      expect(result.fix, contains('hooks.slack.com'));
    }
  });
}
