import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The open event and log sockets by the token that opened them, so that
/// they close with [sessionEndedCloseCode] when the token stops working
/// (D12): at once when it is revoked (a sign-out, a revocation, a person
/// removed), and within [sweepEvery] of its expiry.
class TokenSockets {
  /// Creates the registry over the [tokens] whose revocations it follows.
  new({
    required TokenService tokens,
    required this._clock,
    this.sweepEvery = const Duration(seconds: 60),
  }) {
    _revocations = tokens.revocations.listen((id) => _end(id, 'token revoked'));
  }

  /// How often the sockets of expired tokens are looked for.
  final Duration sweepEvery;

  final Clock _clock;
  late final StreamSubscription<String> _revocations;
  final _sockets = <String, Set<WebSocketChannel>>{};
  final _expiry = <String, DateTime>{};
  Timer? _sweep;

  /// Follows [channel], opened with [token].
  void track(DeviceToken token, WebSocketChannel channel) {
    final id = token.id;
    (_sockets[id] ??= {}).add(channel);
    if (token.expiresAt case final expiresAt?) {
      _expiry[id] = expiresAt;
      _sweep ??= Timer.periodic(sweepEvery, (_) => sweep());
    }
    unawaited(
      channel.sink.done.whenComplete(() {
        final open = _sockets[id]?..remove(channel);
        if (open == null || open.isNotEmpty) return;
        _sockets.remove(id);
        _expiry.remove(id);
      }),
    );
  }

  /// Closes the sockets of every token that has expired.
  void sweep() {
    final now = _clock.now();
    final expired = [
      for (final MapEntry(:key, :value) in _expiry.entries)
        if (!now.isBefore(value)) key,
    ];
    for (final id in expired) {
      _end(id, 'session expired');
    }
  }

  /// Stops following revocations and expiry.
  Future<void> close() async {
    _sweep?.cancel();
    await _revocations.cancel();
  }

  void _end(String id, String why) {
    final open = _sockets.remove(id);
    _expiry.remove(id);
    for (final channel in open ?? const <WebSocketChannel>{}) {
      unawaited(channel.sink.close(sessionEndedCloseCode, why));
    }
  }
}
