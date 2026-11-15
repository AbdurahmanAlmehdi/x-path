import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/api/middleware.dart';
import 'package:xpd/src/api/responses.dart';

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
///
/// **A proxy on the engine machine.** A request through the public URL
/// counts as [OriginKind.loopback] when the proxy rewrites its `Host` to
/// the engine's loopback address and its `Origin` claims one too, as a
/// proxy that sets `Host` to its upstream (nginx's default) lets a client
/// do. Such a browser then gets the loopback cookie, without `Secure`. The
/// proxy must pass the public host on (nginx: `proxy_set_header Host
/// $host;`; Caddy and `tailscale serve` do by default). Refusing loopback
/// sign-in while a public URL is set would close this, but would also
/// refuse a browser on the engine machine itself.
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
    final port = localPortOf(request);
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

  /// The port of this machine the connection of [request] reached: the
  /// port the engine serves on. `null` when it is not known.
  static int? localPortOf(Request request) => _connection(request)?.localPort;

  /// The address the connection of [request] comes from, or `null` when it
  /// is not known. Never a header such as `X-Forwarded-For`: behind a proxy
  /// on this machine, it is the proxy's address.
  static String? remoteAddressOf(Request request) =>
      _connection(request)?.remoteAddress.address;

  static HttpConnectionInfo? _connection(Request request) =>
      request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
}

/// Why a WebSocket upgrade from a browser is refused, as a `403 forbidden`
/// response, or `null` when it may open (D2, D15): a request with an
/// `Origin` must come from one of [origins], and one authenticated by the
/// session cookie must have an `Origin`.
Future<Response?> socketOriginRefusal(
  Request request,
  AllowedOrigins origins,
) async {
  final origin = request.headers['origin'];
  if (origin == null && !authenticatedByCookie(request)) return null;
  if (origin != null && await origins.of(request) != null) return null;
  return errorResponse(
    ApiErrorCode.forbidden,
    'A browser opens this socket only from a page of the engine: its Origin '
    'is missing or not one the engine serves.',
  );
}
