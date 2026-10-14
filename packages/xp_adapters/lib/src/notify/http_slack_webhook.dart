import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xp_engine/xp_engine.dart';

/// A [SlackWebhook] over `package:http`: posts `{"text": ...}` to the
/// incoming webhook.
///
/// Slack answers `200 ok` when it takes the message. A timeout, a failure to
/// connect, `429` and `5xx` are [SlackDeliveryException]s that may work again
/// later; any other answer (a revoked webhook, an archived channel) is not.
/// The URL is a secret and appears in no message.
class HttpSlackWebhook implements SlackWebhook {
  /// Creates the webhook client. [client] is for tests.
  new({http.Client? client, this.timeout = const Duration(seconds: 10)})
    : _client = client ?? http.Client();

  /// How long Slack has to answer.
  final Duration timeout;

  final http.Client _client;

  /// Releases the HTTP client.
  void close() => _client.close();

  @override
  Future<void> post(Uri url, String text) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            url,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw SlackDeliveryException(
        'Slack did not answer within ${timeout.inSeconds} seconds.',
        retryable: true,
      );
    } on http.ClientException {
      // Its message names the URL, which is a secret.
      throw const SlackDeliveryException(
        'Slack could not be reached.',
        retryable: true,
      );
    }
    final status = response.statusCode;
    if (status == 200) return;
    if (status == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      throw SlackDeliveryException(
        'Slack asked to slow down (429).',
        retryable: true,
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
      );
    }
    // Slack's reasons are single words such as `channel_not_found`.
    final body = response.body.trim();
    final reason = body.length > 100 ? body.substring(0, 100) : body;
    throw SlackDeliveryException(
      'Slack answered $status${reason.isEmpty ? '' : ': $reason'}.',
      retryable: status >= 500,
    );
  }
}
