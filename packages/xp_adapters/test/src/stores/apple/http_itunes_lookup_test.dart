import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Map<String, Object?> _result({
  String bundleId = 'ly.example.app',
  Object? trackId = 1234567890,
  Object? version = '5.4.1',
  Object? released = '2026-10-01T09:30:00Z',
}) => {
  'bundleId': bundleId,
  'trackId': trackId,
  'version': version,
  'currentVersionReleaseDate': released,
};

void main() {
  late ManualClock clock;
  late List<Uri> urls;

  HttpItunesLookup lookupAnswering(
    FutureOr<http.Response> Function() answer, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    urls = [];
    return HttpItunesLookup(
      client: MockClient((request) async {
        urls.add(request.url);
        return await answer();
      }),
      clock: clock,
      timeout: timeout,
    );
  }

  setUp(() => clock = ManualClock(DateTime.utc(2026, 10, 13, 12)));

  group('lookup', () {
    test(
      'asks the storefront of the app and returns the live version',
      () async {
        final lookup = lookupAnswering(
          () => _json({
            'resultCount': 1,
            'results': [_result()],
          }),
        );

        final app = await lookup.lookup(
          bundleId: 'ly.example.app',
          country: 'SA',
        );

        expect(
          app,
          ItunesApp(
            bundleId: 'ly.example.app',
            trackId: '1234567890',
            version: '5.4.1',
            currentVersionReleaseDate: DateTime.utc(2026, 10, 1, 9, 30),
          ),
        );
        final url = urls.single;
        expect(url.origin, 'https://itunes.apple.com');
        expect(url.path, '/lookup');
        expect(url.queryParameters['bundleId'], 'ly.example.app');
        expect(url.queryParameters['country'], 'sa');
      },
    );

    test(
      'adds a parameter that changes with time, to get past the CDN',
      () async {
        final lookup = lookupAnswering(
          () => _json({'resultCount': 0, 'results': <Object?>[]}),
        );

        await lookup.lookup(bundleId: 'a.b', country: 'us');
        clock.advance(const Duration(seconds: 1));
        await lookup.lookup(bundleId: 'a.b', country: 'us');

        expect(urls.map((u) => u.queryParameters['_']), [
          '${DateTime.utc(2026, 10, 13, 12).millisecondsSinceEpoch}',
          '${DateTime.utc(2026, 10, 13, 12, 0, 1).millisecondsSinceEpoch}',
        ]);
      },
    );

    test('is null when the storefront does not have the app', () async {
      final lookup = lookupAnswering(
        () => _json({'resultCount': 0, 'results': <Object?>[]}),
      );

      expect(await lookup.lookup(bundleId: 'a.b', country: 'us'), isNull);
    });

    test('ignores results for another bundle id', () async {
      final lookup = lookupAnswering(
        () => _json({
          'results': [_result(bundleId: 'ly.example.other'), 'junk'],
        }),
      );

      expect(
        await lookup.lookup(bundleId: 'ly.example.app', country: 'us'),
        isNull,
      );
    });

    test('keeps an app whose release date is missing or unreadable', () async {
      final lookup = lookupAnswering(
        () => _json({
          'results': [_result(released: 5)],
        }),
      );

      final app = await lookup.lookup(
        bundleId: 'ly.example.app',
        country: 'us',
      );

      expect(app!.currentVersionReleaseDate, isNull);
    });

    for (final (name, response, message) in <(String, http.Response, String)>[
      ('an HTTP error', http.Response('', 503), 'HTTP 503'),
      ('text', http.Response('<html>', 200), 'not answer with JSON'),
      ('a JSON array', http.Response('[]', 200), 'without results'),
      (
        'no results list',
        http.Response('{"results": 1}', 200),
        'without results',
      ),
      (
        'a result without a version',
        _json({
          'results': [_result(version: null)],
        }),
        'without a version',
      ),
      (
        'a result with a text id',
        _json({
          'results': [_result(trackId: '12')],
        }),
        'without a version or an id',
      ),
    ]) {
      test('fails on $name', () async {
        final lookup = lookupAnswering(() => response);

        await expectLater(
          lookup.lookup(bundleId: 'ly.example.app', country: 'us'),
          throwsA(
            isA<ItunesLookupException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }

    test('fails when it is not answered in time', () async {
      final never = Completer<http.Response>();
      final lookup = lookupAnswering(
        () => never.future,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        lookup.lookup(bundleId: 'a.b', country: 'us'),
        throwsA(
          isA<ItunesLookupException>().having(
            (e) => e.message,
            'message',
            contains('did not answer'),
          ),
        ),
      );
    });

    test('fails when the connection fails', () async {
      final lookup = HttpItunesLookup(
        client: MockClient((_) async => throw http.ClientException('refused')),
      );

      await expectLater(
        lookup.lookup(bundleId: 'a.b', country: 'us'),
        throwsA(
          isA<ItunesLookupException>().having(
            (e) => e.message,
            'message',
            contains('not reachable'),
          ),
        ),
      );
    });
  });

  group('against the fake server', () {
    test('answers per storefront, without a token', () async {
      final server = await FakeAscServer.start();
      addTearDown(server.close);
      server.addItunes('ly.example.app', version: '5.4.1', trackId: '99');
      final lookup = HttpItunesLookup(baseUrl: server.baseUrl);
      addTearDown(lookup.close);

      final us = await lookup.lookup(bundleId: 'ly.example.app', country: 'us');
      final sa = await lookup.lookup(bundleId: 'ly.example.app', country: 'sa');

      expect(us!.version, '5.4.1');
      expect(us.trackId, '99');
      expect(sa, isNull);
    });
  });
}
