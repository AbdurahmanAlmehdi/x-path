import 'dart:async';

/// A Slack incoming webhook (D-22).
///
/// `xp_adapters` has the HTTP implementation. The URL is a secret: it is in no
/// log, no message and no exception.
abstract interface class SlackWebhook {
  /// Posts [text] (Slack `mrkdwn`) to the webhook at [url].
  ///
  /// Throws a [SlackDeliveryException] if Slack did not take it.
  Future<void> post(Uri url, String text);
}

/// Slack did not take a message.
///
/// The message never contains the webhook URL.
class SlackDeliveryException implements Exception {
  /// Creates an exception with [message].
  ///
  /// A [retryable] failure (a timeout, a `5xx`, rate limiting) may work if
  /// sent again, after [retryAfter] when Slack said how long to wait.
  const new(this.message, {this.retryable = false, this.retryAfter});

  /// What went wrong.
  final String message;

  /// Whether sending again may help.
  final bool retryable;

  /// How long Slack asked us to wait, when it did.
  final Duration? retryAfter;

  @override
  String toString() => 'SlackDeliveryException: $message';
}

/// A [SlackWebhook] for tests: remembers the posts and fails when told to.
class FakeSlackWebhook implements SlackWebhook {
  /// Every post that got through, as `(url, text)`.
  final posts = <(Uri, String)>[];

  /// How many posts were tried, including the ones that failed.
  int attempts = 0;

  /// The failures to throw, one per attempt, before posts start to work.
  final failures = <SlackDeliveryException>[];

  @override
  Future<void> post(Uri url, String text) async {
    attempts++;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    posts.add((url, text));
  }
}

/// Sends a message to a Slack webhook and sends it again, with growing waits,
/// when Slack cannot take it right now.
class SlackSender {
  /// Creates a sender over [_webhook].
  ///
  /// After a retryable failure it waits for the next of [backoff] (or for
  /// what Slack asked, at most [maxWait]) and tries again, so a message is
  /// tried `backoff.length + 1` times. [sleep] is how it waits.
  new({
    required this._webhook,
    this.backoff = const [
      Duration(seconds: 1),
      Duration(seconds: 5),
      Duration(seconds: 30),
    ],
    this.maxWait = const Duration(minutes: 1),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  /// The waits between the attempts.
  final List<Duration> backoff;

  /// The longest wait, whatever Slack asked.
  final Duration maxWait;

  final SlackWebhook _webhook;
  final Future<void> Function(Duration) _sleep;

  /// Posts [text] to [url].
  ///
  /// Throws the last failure after the last attempt or at the first failure
  /// that is not retryable. Stops trying as soon as [cancelled] says so.
  Future<void> send(Uri url, String text, {bool Function()? cancelled}) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _webhook.post(url, text);
        return;
      } on SlackDeliveryException catch (error) {
        final last = attempt >= backoff.length;
        if (!error.retryable || last || (cancelled?.call() ?? false)) {
          rethrow;
        }
        final wait = error.retryAfter ?? backoff[attempt];
        await _sleep(wait > maxWait ? maxWait : wait);
        if (cancelled?.call() ?? false) rethrow;
      }
    }
  }
}
