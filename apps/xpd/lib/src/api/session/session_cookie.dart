import 'package:shelf/shelf.dart';
import 'package:xpd/src/api/allowed_origins.dart';

/// The cookie of a browser session (ADR 0018, D3a): its value is the secret
/// of a `web` token.
///
/// The name and attributes come from the origin the browser signed in from,
/// never from request headers: through the HTTPS public URL a `__Host-`
/// cookie with `Secure`; on this machine one without `Secure`, which Safari
/// refuses on `http://localhost`, and which never leaves the machine.
///
/// A browser sends a cookie to every port of a host, so the loopback cookie
/// is named after the port the engine serves on ([loopbackName]): two
/// engines on one machine keep their sessions apart. Any other server on
/// `localhost` still receives it, whatever its port; only the `Origin`
/// check and the CSRF header keep such a page from using it to change
/// something.
abstract final class SessionCookie {
  /// The cookie set through the public URL.
  static const secureName = '__Host-xp_session';

  /// The cookie set on this machine by the engine that serves on [port],
  /// for example `xp_session_7480`.
  static String loopbackName(int port) => 'xp_session_$port';

  /// The `Set-Cookie` of a session with [secret] that lasts [maxAge], for a
  /// browser that signed in with [request] from an origin of [kind].
  static String set(
    Request request,
    OriginKind kind,
    String secret,
    Duration maxAge,
  ) => switch (kind) {
    OriginKind.public => _cookie(
      secureName,
      secret,
      maxAge.inSeconds,
      secure: true,
    ),
    OriginKind.loopback => _cookie(
      loopbackName(AllowedOrigins.localPortOf(request) ?? 0),
      secret,
      maxAge.inSeconds,
      secure: false,
    ),
  };

  /// The `Set-Cookie` headers that clear every session cookie [request]
  /// carries (`Max-Age=0`).
  static List<String> clear(Request request) => [
    for (final name in _names(request))
      if (_values(request).containsKey(name))
        _cookie(name, '', 0, secure: name == secureName),
  ];

  /// The session secrets [request] carries, the `__Host-` one first.
  static List<String> secretsOf(Request request) {
    final values = _values(request);
    return [
      for (final name in _names(request))
        if (values[name] case final value? when value.isNotEmpty) value,
    ];
  }

  /// The names of the session cookies of the engine [request] reached.
  static List<String> _names(Request request) => [
    secureName,
    if (AllowedOrigins.localPortOf(request) case final port?)
      loopbackName(port),
  ];

  static String _cookie(
    String name,
    String value,
    int maxAge, {
    required bool secure,
  }) => [
    '$name=$value',
    if (secure) 'Secure',
    'HttpOnly',
    'SameSite=Strict',
    'Path=/',
    'Max-Age=$maxAge',
  ].join('; ');

  /// The cookies of [request] by name; the first of two with one name wins.
  static Map<String, String> _values(Request request) {
    final header = request.headers['cookie'];
    if (header == null) return const {};
    final values = <String, String>{};
    for (final pair in header.split(';')) {
      final at = pair.indexOf('=');
      if (at < 0) continue;
      values.putIfAbsent(
        pair.substring(0, at).trim(),
        () => pair.substring(at + 1).trim(),
      );
    }
    return values;
  }
}
