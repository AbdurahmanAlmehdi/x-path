import 'package:xp_engine/src/tokens/device_token.dart';

/// Where device tokens are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class DeviceTokenRepository {
  /// Every token, revoked ones included.
  Future<List<DeviceToken>> list();

  /// Stores [token].
  Future<void> add(DeviceToken token);

  /// Revokes the token [id] at [at]. Returns whether it was valid until now:
  /// `false` for a token that is unknown or revoked already.
  Future<bool> revoke(String id, {required DateTime at});

  /// Revokes, at [at], every valid token of the person [personId]. Returns
  /// how many there were.
  Future<int> revokeOwnedBy(String personId, {required DateTime at});
}

/// A [DeviceTokenRepository] that forgets everything on exit.
class InMemoryDeviceTokenRepository implements DeviceTokenRepository {
  final _tokens = <DeviceToken>[];

  @override
  Future<List<DeviceToken>> list() async => List.unmodifiable(_tokens);

  @override
  Future<void> add(DeviceToken token) async => _tokens.add(token);

  @override
  Future<bool> revoke(String id, {required DateTime at}) async {
    final index = _tokens.indexWhere((token) => token.id == id);
    if (index < 0 || _tokens[index].isRevoked) return false;
    _tokens[index] = _tokens[index].revoked(at);
    return true;
  }

  @override
  Future<int> revokeOwnedBy(String personId, {required DateTime at}) async {
    var count = 0;
    for (var i = 0; i < _tokens.length; i++) {
      final token = _tokens[i];
      if (token.personId != personId || token.isRevoked) continue;
      _tokens[i] = token.revoked(at);
      count++;
    }
    return count;
  }
}
