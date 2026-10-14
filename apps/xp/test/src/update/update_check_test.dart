import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:xp/src/update/update_check.dart';

void main() {
  late Directory directory;
  late File cache;
  late DateTime now;
  late List<http.Request> requests;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_update');
    cache = File('${directory.path}/xpath/update-check.json');
    now = DateTime.utc(2026, 10, 14, 12);
    requests = [];
  });
  tearDown(() => directory.deleteSync(recursive: true));

  GitHubUpdateCheck check(
    Future<http.Response> Function(http.Request request) handler, {
    String current = '1.0.0',
  }) => GitHubUpdateCheck(
    cacheFile: cache,
    client: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    now: () => now,
    currentVersion: current,
    timeout: const Duration(milliseconds: 200),
  );

  Future<http.Response> release(String tag) async =>
      http.Response(jsonEncode({'tag_name': tag}), 200);

  group('GitHubUpdateCheck', () {
    test('finds a newer release', () async {
      expect(await check((_) => release('v1.2.0')).newerVersion(), '1.2.0');
    });

    test('finds nothing when this is the newest', () async {
      expect(await check((_) => release('v1.0.0')).newerVersion(), isNull);
      expect(await check((_) => release('v0.9.0')).newerVersion(), isNull);
    });

    test(
      'sends one plain request with nothing that identifies the user',
      () async {
        await check((_) => release('v1.0.0')).newerVersion();

        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.method, 'GET');
        expect(request.url, GitHubUpdateCheck.latestRelease);
        expect(request.headers.keys.map((k) => k.toLowerCase()).toSet(), {
          'accept',
          'user-agent',
        });
        expect(request.headers['User-Agent'], 'xp-update-check');
        expect(request.bodyBytes, isEmpty);
      },
    );

    test('a private repository is no news', () async {
      expect(
        await check((_) async => http.Response('', 404)).newerVersion(),
        isNull,
      );
    });

    test('an answer without a tag is no news', () async {
      expect(
        await check((_) async => http.Response('{}', 200)).newerVersion(),
        isNull,
      );
    });

    test('a failure is no news', () async {
      expect(
        await check((_) async => throw const SocketException('offline'))
            .newerVersion(),
        isNull,
      );
    });

    test('a slow GitHub is no news', () async {
      expect(
        await check(
          (_) => Future<http.Response>.delayed(
            const Duration(seconds: 2),
            () => http.Response(jsonEncode({'tag_name': 'v9.0.0'}), 200),
          ),
        ).newerVersion(),
        isNull,
      );
    });

    test('asks once a day and remembers the answer', () async {
      final first = check((_) => release('v1.2.0'));
      expect(await first.newerVersion(), '1.2.0');

      now = now.add(const Duration(hours: 23));
      expect(await check((_) => release('v3.0.0')).newerVersion(), '1.2.0');
      expect(requests, hasLength(1));

      now = now.add(const Duration(hours: 2));
      expect(await check((_) => release('v3.0.0')).newerVersion(), '3.0.0');
      expect(requests, hasLength(2));
    });

    test(
      'remembers a failure too, so it does not ask on every command',
      () async {
        await check((_) async => http.Response('', 404)).newerVersion();
        await check((_) async => http.Response('', 404)).newerVersion();

        expect(requests, hasLength(1));
      },
    );

    test('a broken cache file is ignored', () async {
      cache.parent.createSync(recursive: true);
      cache.writeAsStringSync('nonsense');

      expect(await check((_) => release('v2.0.0')).newerVersion(), '2.0.0');
    });

    test('a cache it cannot write is only a missed cache', () async {
      File('${directory.path}/blocker').writeAsStringSync('x');
      final blocked = GitHubUpdateCheck(
        cacheFile: File('${directory.path}/blocker/sub/cache.json'),
        client: MockClient((_) => release('v2.0.0')),
        currentVersion: '1.0.0',
      );

      expect(await blocked.newerVersion(), '2.0.0');
    });

    test('uses the ambient HTTP client when it is not given one', () async {
      final ambient = GitHubUpdateCheck(
        cacheFile: cache,
        currentVersion: '1.0.0',
      );

      final newer = await http.runWithClient(
        ambient.newerVersion,
        () => MockClient((request) {
          requests.add(request);
          return release('v1.5.0');
        }),
      );

      expect(newer, '1.5.0');
      expect(requests, hasLength(1));
    });
  });

  group('UpdateCheck.system', () {
    test('is a GitHub check by default', () {
      expect(UpdateCheck.system(directory.path, {}), isA<GitHubUpdateCheck>());
    });

    test('is off when XP_NO_UPDATE_CHECK is set', () async {
      final off = UpdateCheck.system(directory.path, {
        noUpdateCheckVariable: '1',
      });

      expect(off, isA<NoUpdateCheck>());
      expect(await off.newerVersion(), isNull);
    });

    test('is on when XP_NO_UPDATE_CHECK is empty', () {
      expect(
        UpdateCheck.system(directory.path, {noUpdateCheckVariable: ''}),
        isA<GitHubUpdateCheck>(),
      );
    });
  });

  group('isNewerVersion', () {
    test('compares major, minor and patch as numbers', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('0.9.0', '1.0.0'), isFalse);
    });

    test('ignores a pre-release and anything that is not a version', () {
      expect(isNewerVersion('2.0.0-rc.1', '1.0.0'), isFalse);
      expect(isNewerVersion('nightly', '1.0.0'), isFalse);
      expect(isNewerVersion('2.0.0', 'dev'), isFalse);
    });

    test('accepts a leading v', () {
      expect(isNewerVersion('v1.0.1', '1.0.0'), isTrue);
    });
  });
}
