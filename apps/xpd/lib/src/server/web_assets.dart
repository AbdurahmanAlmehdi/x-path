import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/legacy_alias.dart';

/// Serves the web dashboard (`apps/xp_web`, built) from a `web` folder: its
/// `index.html` and its hashed `assets/` (ADR 0018).
///
/// - `GET /assets/<file>` is the file, cached for a year as immutable: its
///   name changes with its content.
/// - Any other `GET` whose `Accept` names `text/html` is `index.html`, never
///   cached, so the app's router opens the page (a deep link such as
///   `/runs/abc`).
/// - Everything else is the JSON `404` of [notTheApi]: another method, a
///   request that does not ask for a page, a missing asset, any path under
///   `/api`, and every path when the engine was built without the
///   dashboard.
///
/// Every answer with a file carries the Content-Security-Policy of the
/// dashboard, `X-Content-Type-Options: nosniff` and `Referrer-Policy:
/// no-referrer`.
class WebAssets {
  /// Serves the dashboard in [directory], or nothing when it is `null` or
  /// holds no `index.html`. The public URL adds its WebSocket origin to the
  /// policy's `connect-src`.
  new({required String? directory, required this._publicUrl})
    : _assets = directory == null ? '' : p.join(directory, 'assets'),
      _index = _readIndex(directory);

  final PublicUrlService _publicUrl;
  final String _assets;
  final String? _index;

  /// The answer to [request], a root path that is not the API.
  Future<Response> call(Request request) async {
    final index = _index;
    final segments = request.url.pathSegments;
    if (index == null ||
        !(request.method == 'GET' || request.method == 'HEAD') ||
        (segments.isNotEmpty && segments.first == 'api')) {
      return notTheApi(request);
    }
    if (segments.isNotEmpty && segments.first == 'assets') {
      return await _asset(request, segments.skip(1).toList());
    }
    if (!(request.headers['accept']?.contains('text/html') ?? false)) {
      return notTheApi(request);
    }
    return Response.ok(
      index,
      headers: {
        ...await _securityHeaders(),
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache',
      },
    );
  }

  Future<Response> _asset(Request request, List<String> names) async {
    final safe =
        names.isNotEmpty &&
        names.every(
          (name) =>
              name.isNotEmpty &&
              name != '.' &&
              name != '..' &&
              !name.contains('/') &&
              !name.contains(r'\'),
        );
    final file = File(p.joinAll([_assets, ...names]));
    if (!safe || !p.isWithin(_assets, file.path) || !file.existsSync()) {
      return notTheApi(request);
    }
    return Response.ok(
      file.openRead(),
      headers: {
        ...await _securityHeaders(),
        'content-type': _contentType(file.path),
        'content-length': '${file.lengthSync()}',
        'cache-control': 'public, max-age=31536000, immutable',
      },
    );
  }

  Future<Map<String, String>> _securityHeaders() async {
    final public = await _publicUrl.origin();
    final sockets = public == null
        ? ''
        : ' ${public.replaceFirst('https://', 'wss://')}';
    return {
      'content-security-policy':
          "default-src 'self'; script-src 'self'; style-src 'self'; "
          "img-src 'self' data:; font-src 'self'; "
          "connect-src 'self'$sockets; object-src 'none'; base-uri 'none'; "
          "form-action 'self'; frame-ancestors 'none'",
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
    };
  }

  static String? _readIndex(String? directory) {
    if (directory == null) return null;
    final index = File(p.join(directory, 'index.html'));
    return index.existsSync() ? index.readAsStringSync() : null;
  }

  static String _contentType(String path) =>
      _contentTypes[p.extension(path).toLowerCase()] ??
      'application/octet-stream';

  static const _contentTypes = {
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.html': 'text/html; charset=utf-8',
    '.json': 'application/json',
    '.map': 'application/json',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.webp': 'image/webp',
    '.ico': 'image/x-icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.txt': 'text/plain; charset=utf-8',
  };
}
