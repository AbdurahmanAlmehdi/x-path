import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final url = Uri.parse('https://hooks.slack.com/services/T/B/X');

  group('FakeSlackWebhook', () {
    test('remembers what got through and counts every attempt', () async {
      final webhook = FakeSlackWebhook()
        ..failures.add(const SlackDeliveryException('down', retryable: true));

      await expectLater(
        webhook.post(url, 'one'),
        throwsA(isA<SlackDeliveryException>()),
      );
      await webhook.post(url, 'two');

      expect(webhook.attempts, 2);
      expect(webhook.posts, [(url, 'two')]);
    });
  });

  test('SlackDeliveryException says what happened and nothing more', () {
    const error = SlackDeliveryException('Slack answered 404.');

    expect(error.toString(), 'SlackDeliveryException: Slack answered 404.');
    expect(error.retryable, isFalse);
    expect(error.retryAfter, isNull);
  });

  group('SlackSender', () {
    late FakeSlackWebhook webhook;
    late List<Duration> sleeps;

    SlackSender sender({
      List<Duration>? backoff,
      Duration maxWait = const Duration(minutes: 1),
    }) => SlackSender(
      webhook: webhook,
      backoff: backoff ?? const [Duration(seconds: 1), Duration(seconds: 5)],
      maxWait: maxWait,
      sleep: (wait) async => sleeps.add(wait),
    );

    setUp(() {
      webhook = FakeSlackWebhook();
      sleeps = [];
    });

    test('posts once when Slack takes it', () async {
      await sender().send(url, 'hello');

      expect(webhook.posts, [(url, 'hello')]);
      expect(sleeps, isEmpty);
    });

    test('tries again after a retryable failure, with growing waits', () async {
      webhook.failures.addAll(const [
        SlackDeliveryException('503', retryable: true),
        SlackDeliveryException('503', retryable: true),
      ]);

      await sender().send(url, 'hello');

      expect(webhook.attempts, 3);
      expect(webhook.posts, [(url, 'hello')]);
      expect(sleeps, [const Duration(seconds: 1), const Duration(seconds: 5)]);
    });

    test('waits as long as Slack asked, but not past maxWait', () async {
      webhook.failures.addAll(const [
        SlackDeliveryException(
          '429',
          retryable: true,
          retryAfter: Duration(seconds: 3),
        ),
        SlackDeliveryException(
          '429',
          retryable: true,
          retryAfter: Duration(hours: 1),
        ),
      ]);

      await sender().send(url, 'hello');

      expect(sleeps, [const Duration(seconds: 3), const Duration(minutes: 1)]);
    });

    test('gives up after the last attempt with the last failure', () async {
      webhook.failures.addAll(const [
        SlackDeliveryException('first', retryable: true),
        SlackDeliveryException('second', retryable: true),
        SlackDeliveryException('third', retryable: true),
      ]);

      await expectLater(
        sender().send(url, 'hello'),
        throwsA(
          isA<SlackDeliveryException>().having((e) => e.message, 'm', 'third'),
        ),
      );
      expect(webhook.attempts, 3);
    });

    test('does not try again after a failure that cannot get better', () async {
      webhook.failures.add(const SlackDeliveryException('404'));

      await expectLater(
        sender().send(url, 'hello'),
        throwsA(isA<SlackDeliveryException>()),
      );
      expect(webhook.attempts, 1);
      expect(sleeps, isEmpty);
    });

    test('stops trying once it is cancelled', () async {
      webhook.failures.add(
        const SlackDeliveryException('503', retryable: true),
      );

      await expectLater(
        sender().send(url, 'hello', cancelled: () => true),
        throwsA(isA<SlackDeliveryException>()),
      );
      expect(webhook.attempts, 1);
      expect(sleeps, isEmpty);
    });

    test('waits for real unless told how', () async {
      final real = SlackSender(
        webhook: webhook,
        backoff: const [Duration(milliseconds: 1)],
      );
      webhook.failures.add(
        const SlackDeliveryException('503', retryable: true),
      );

      await real.send(url, 'hello');

      expect(webhook.posts, hasLength(1));
    });
  });
}
