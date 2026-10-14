import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final url = Uri.parse('https://hooks.slack.com/services/T0/B0/SECRETPART');
  late List<http.Request> requests;

  HttpSlackWebhook webhook(
    FutureOr<http.Response> Function(http.Request request) answer, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    requests = [];
    return HttpSlackWebhook(
      timeout: timeout,
      client: MockClient((request) async {
        requests.add(request);
        return await answer(request);
      }),
    );
  }

  Future<SlackDeliveryException> failure(HttpSlackWebhook hook) async {
    try {
      await hook.post(url, 'hello');
    } on SlackDeliveryException catch (error) {
      return error;
    }
    throw StateError('The post did not fail.');
  }

  test('posts the text as JSON to the webhook', () async {
    final hook = webhook((request) => http.Response('ok', 200));

    await hook.post(url, '*Release live*\nocto/demo');

    expect(requests.single.method, 'POST');
    expect(requests.single.url, url);
    expect(
      requests.single.headers['content-type'],
      contains('application/json'),
    );
    expect(jsonDecode(requests.single.body), {
      'text': '*Release live*\nocto/demo',
    });
  });

  test('429 may work later, after as long as Slack asked', () async {
    final error = await failure(
      webhook(
        (request) => http.Response('', 429, headers: {'retry-after': '7'}),
      ),
    );

    expect(error.retryable, isTrue);
    expect(error.retryAfter, const Duration(seconds: 7));
  });

  test('429 without a usable Retry-After has no wait of its own', () async {
    final error = await failure(
      webhook(
        (request) => http.Response('', 429, headers: {'retry-after': 'soon'}),
      ),
    );

    expect(error.retryable, isTrue);
    expect(error.retryAfter, isNull);
  });

  test('a server error may work later', () async {
    final error = await failure(webhook((request) => http.Response('', 503)));

    expect(error.retryable, isTrue);
    expect(error.message, 'Slack answered 503.');
  });

  test('a refusal says why and will not work later', () async {
    final error = await failure(
      webhook((request) => http.Response('channel_not_found\n', 404)),
    );

    expect(error.retryable, isFalse);
    expect(error.message, 'Slack answered 404: channel_not_found.');
  });

  test('a long reason is cut', () async {
    final error = await failure(
      webhook((request) => http.Response('x' * 500, 400)),
    );

    expect(error.message, 'Slack answered 400: ${'x' * 100}.');
  });

  test(
    'a connection failure may work later and does not name the URL',
    () async {
      final error = await failure(
        webhook(
          (request) => throw http.ClientException('refused', request.url),
        ),
      );

      expect(error.retryable, isTrue);
      expect(error.message, 'Slack could not be reached.');
      expect(error.toString(), isNot(contains('SECRETPART')));
    },
  );

  test('a Slack that does not answer in time may work later', () async {
    final error = await failure(
      webhook(
        (request) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 10),
      ),
    );

    expect(error.retryable, isTrue);
    expect(error.message, 'Slack did not answer within 0 seconds.');
  });

  test('close releases the client', () {
    HttpSlackWebhook().close();
  });
}
