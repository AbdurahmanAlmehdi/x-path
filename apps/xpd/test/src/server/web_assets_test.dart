import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/test_engine.dart';

const _index = '<!doctype html><div id="app"></div>';
const _script = 'console.log("xp")';
const _html = {'accept': 'text/html,application/xhtml+xml,*/*;q=0.8'};

/// A built dashboard in a temporary folder, and a file beside it that must
/// never be served.
Directory _builtDashboard() {
  final root = Directory.systemTemp.createTempSync('xp_web_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'secret.txt')).writeAsStringSync('do not serve');
  final web = Directory(p.join(root.path, 'web'))..createSync();
  File(p.join(web.path, 'index.html')).writeAsStringSync(_index);
  Directory(p.join(web.path, 'assets')).createSync();
  File(p.join(web.path, 'assets', 'index-AbC123.js'))
      .writeAsStringSync(_script);
  File(p.join(web.path, 'assets', 'index-AbC123.css')).writeAsStringSync('a{}');
  File(p.join(web.path, 'assets', 'font.bin')).writeAsBytesSync([1, 2, 3]);
  return web;
}

PublicUrlService _publicUrl() =>
    PublicUrlService(settings: InMemoryEngineSettingRepository());

Future<Response> _get(
  WebAssets assets,
  String path, {
  String method = 'GET',
  Map<String, String> headers = _html,
}) => assets(
  Request(method, Uri.parse('http://127.0.0.1:7480$path'), headers: headers),
);

void main() {
  group('WebAssets', () {
    late Directory web;
    late PublicUrlService publicUrl;
    late WebAssets assets;

    setUp(() {
      web = _builtDashboard();
      publicUrl = _publicUrl();
      assets = WebAssets(directory: web.path, publicUrl: publicUrl);
    });

    test('serves index.html, never cached, for a page', () async {
      for (final path in [
        '/',
        '/sign-in',
        '/runs/abc',
        '/runs?status=failed',
      ]) {
        final response = await _get(assets, path);

        expect(response.statusCode, 200, reason: path);
        expect(await response.readAsString(), _index, reason: path);
        expect(response.headers['content-type'], 'text/html; charset=utf-8');
        expect(response.headers['cache-control'], 'no-cache');
      }
    });

    test('sends the security headers with a page', () async {
      final response = await _get(assets, '/');

      expect(
        response.headers['content-security-policy'],
        "default-src 'self'; script-src 'self'; style-src 'self'; "
        "img-src 'self' data:; font-src 'self'; connect-src 'self'; "
        "object-src 'none'; base-uri 'none'; form-action 'self'; "
        "frame-ancestors 'none'",
      );
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.headers['referrer-policy'], 'no-referrer');
    });

    test('lets the page open sockets to the public URL', () async {
      await publicUrl.set('https://xpath.example.com');

      final response = await _get(assets, '/');

      expect(
        response.headers['content-security-policy'],
        contains("connect-src 'self' wss://xpath.example.com;"),
      );
    });

    test('serves a hashed asset as immutable, with its type', () async {
      final response = await _get(assets, '/assets/index-AbC123.js');

      expect(response.statusCode, 200);
      expect(await response.readAsString(), _script);
      expect(
        response.headers['content-type'],
        'text/javascript; charset=utf-8',
      );
      expect(response.headers['content-length'], '${_script.length}');
      expect(
        response.headers['cache-control'],
        'public, max-age=31536000, immutable',
      );
      expect(response.headers['x-content-type-options'], 'nosniff');
    });

    test('serves an asset whatever the request accepts', () async {
      final css = await _get(
        assets,
        '/assets/index-AbC123.css',
        headers: {'accept': 'text/css'},
      );
      final other = await _get(assets, '/assets/font.bin', headers: {});

      expect(css.headers['content-type'], 'text/css; charset=utf-8');
      expect(other.headers['content-type'], 'application/octet-stream');
      expect(await other.read().expand((bytes) => bytes).toList(), [1, 2, 3]);
    });

    test('answers HEAD like GET', () async {
      final response = await _get(assets, '/runs', method: 'HEAD');

      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], 'no-cache');
    });

    Future<void> expectNotServed(Response response, {String? reason}) async {
      expect(response.statusCode, 404, reason: reason);
      expect(
        response.headers['content-type'],
        startsWith('application/json'),
        reason: reason,
      );
      final body = await response.readAsString();
      expect(jsonDecode(body), contains('error'), reason: reason);
      expect(body, isNot(contains('do not serve')), reason: reason);
    }

    test('answers a missing asset with the JSON 404', () async {
      for (final path in [
        '/assets/missing.js',
        '/assets/',
        '/assets',
        '/assets/sub',
      ]) {
        await expectNotServed(await _get(assets, path), reason: path);
      }
    });

    test('never serves a file outside the assets', () async {
      for (final path in [
        '/assets/..%2Fsecret.txt',
        '/assets/..%2F..%2Fsecret.txt',
        '/assets/..%5C..%5Csecret.txt',
        '/assets/.%2Findex-AbC123.js',
      ]) {
        await expectNotServed(await _get(assets, path), reason: path);
      }
    });

    test('takes a path that leaves the assets for a page', () async {
      // The URL parser resolves the dots: `/secret.txt`, `/index.html`.
      for (final path in [
        '/assets/%2E%2E/%2E%2E/secret.txt',
        '/assets/../index.html',
      ]) {
        final response = await _get(assets, path);

        expect(await response.readAsString(), _index, reason: path);
      }
    });

    test('never serves the dashboard under /api', () async {
      for (final path in ['/api', '/api/', '/api/v2/projects', '/api/v1']) {
        await expectNotServed(await _get(assets, path), reason: path);
      }
    });

    test('answers a request that does not ask for a page with the 404', () {
      return Future.wait([
        for (final accept in ['application/json', '*/*', ''])
          _get(
            assets,
            '/runs',
            headers: {'accept': accept},
          ).then((response) => expectNotServed(response, reason: accept)),
      ]);
    });

    test('answers a method other than GET and HEAD with the 404', () async {
      for (final method in ['POST', 'PUT', 'DELETE', 'OPTIONS']) {
        await expectNotServed(
          await _get(assets, '/', method: method),
          reason: method,
        );
      }
    });

    test('serves nothing without a dashboard', () async {
      final missing = Directory(p.join(web.path, 'missing'));
      for (final directory in [null, missing.path]) {
        final none = WebAssets(directory: directory, publicUrl: publicUrl);

        await expectNotServed(await _get(none, '/'), reason: directory);
        await expectNotServed(
          await _get(none, '/assets/index-AbC123.js'),
          reason: directory,
        );
      }
    });
  });

  group('xpd with the dashboard', () {
    late TestEngine engine;

    setUp(() async {
      engine = await TestEngine.start(webDirectory: _builtDashboard().path);
    });
    tearDown(() => engine.close());

    Future<RawResponse> page(String path, {String token = ''}) =>
        engine.request(path, token: token, headers: _html, root: true);

    test('serves the dashboard at / and at a deep link', () async {
      for (final path in ['/', '/runs/abc']) {
        final response = await page(path);

        expect(response.statusCode, 200, reason: path);
        expect(response.body, _index, reason: path);
        expect(response.headers['content-security-policy'], isNotNull);
        expect(response.headers['vary'], 'Authorization');
      }
    });

    test('serves an asset as immutable', () async {
      final response = await engine.request(
        '/assets/index-AbC123.js',
        token: '',
        root: true,
      );

      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], contains('immutable'));
    });

    test('keeps a root path with Authorization the API', () async {
      final response = await page('/runs/abc', token: engine.secret);

      expect(response.statusCode, 404);
      expect(response.contentType, startsWith('application/json'));
      expect(response.headers['deprecation'], 'true');
    });

    test('keeps an unknown path under /api/v1 the JSON 404', () async {
      final response = await engine.request('/nope', headers: _html);

      expect(response.statusCode, 404);
      expect(response.contentType, startsWith('application/json'));
    });
  });

  test('xpd without the dashboard answers / with the JSON 404', () async {
    final engine = await TestEngine.start();
    addTearDown(engine.close);

    final response = await engine.request(
      '/',
      token: '',
      headers: _html,
      root: true,
    );

    expect(response.statusCode, 404);
    expect(response.contentType, startsWith('application/json'));
    expect(response.headers['vary'], 'Authorization');
  });
}
