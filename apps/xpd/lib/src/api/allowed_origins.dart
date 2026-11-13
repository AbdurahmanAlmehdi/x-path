import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:xp_engine/xp_engine.dart';

/// Where a browser request comes from, when the engine serves that origin.
enum OriginKind {
  /// The HTTPS public URL, through a proxy that terminates TLS.
  public,

  /// This machine, on the port the engine is bound to.
  loopback,
}

/// The origins a browser request may come from (ADR 0018, D15), matched as
/// exact strings:
///
/// - the origin of the public URL;
/// - `http://127.0.0.1:<p>`, `http://localhost:<p>` and `http://[::1]:<p>`,
///   where `<p>` is the port the request reached, but only when its `Host`
///   is one of `127.0.0.1:<p>`, `localhost:<p>` and `[::1]:<p>` too, which
///   blocks DNS rebinding.
///
/// No `X-Forwarded-*` header is ever read.
class AllowedOrigins {
  /// Creates the set over the public URL.
  const new(this._publicUrl);

  final PublicUrlService _publicUrl;

  /// What the `Origin` of [request] is, or `null` when it has none or the
  /// engine does not serve it.
  Future<OriginKind?> of(Request request) async {
    final origin = request.headers['origin'];
    if (origin == null) return null;
    if (origin == await _publicUrl.origin()) return OriginKind.public;
    final port = _connection(request)?.localPort;
    if (port == null) return null;
    final hosts = ['127.0.0.1:$port', 'localhost:$port', '[::1]:$port'];
    return hosts.contains(request.headers['host']) &&
            hosts.map((host) => 'http://$host').contains(origin)
        ? OriginKind.loopback
        : null;
  }

  /// Whether [request] came over a connection from this machine.
  static bool fromLoopback(Request request) =>
      _connection(request)?.remoteAddress.isLoopback ?? false;

  static HttpConnectionInfo? _connection(Request request) =>
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
}
