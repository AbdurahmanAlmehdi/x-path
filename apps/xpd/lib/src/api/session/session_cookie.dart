import 'package:shelf/shelf.dart';
import 'package:xpd/src/api/allowed_origins.dart';

/// The cookie of a browser session (ADR 0018, D3a): its value is the secret
/// of a `web` token.
///
/// The name and attributes come from the origin the browser signed in from,
/// never from request headers: through the HTTPS public URL a `__Host-`
/// cookie with `Secure`; on this machine one without `Secure`, which Safari
/// refuses on `http://localhost`, and which never leaves the machine.
abstract final class SessionCookie {
  /// The cookie set through the public URL.
  static const secureName = '__Host-xp_session';

  /// The cookie set on this machine.
  static const loopbackName = 'xp_session';

  static const List<String> _names = [secureName, loopbackName];

  /// The `Set-Cookie` of a session with [secret] that lasts [maxAge], for a
  /// browser that signed in from an origin of [kind].
  static String set(OriginKind kind, String secret, Duration maxAge) =>
      _cookie(_nameOf(kind), secret, maxAge.inSeconds, secure: _secure(kind));

  /// The `Set-Cookie` headers that clear every session cookie [request]
  /// carries (`Max-Age=0`).
  static List<String> clear(Request request) => [
    for (final name in _names)
      if (_values(request).containsKey(name))
        _cookie(name, '', 0, secure: name == secureName),
  ];

  /// The session secrets [request] carries, the `__Host-` one first.
  static List<String> secretsOf(Request request) {
    final values = _values(request);
    return [
      for (final name in _names)
        if (values[name] case final value? when value.isNotEmpty) value,
    ];
  }

  static String _nameOf(OriginKind kind) => switch (kind) {
    OriginKind.public => secureName,
    OriginKind.loopback => loopbackName,
  };

  static bool _secure(OriginKind kind) => kind == OriginKind.public;

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
