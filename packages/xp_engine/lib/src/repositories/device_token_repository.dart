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
    final token = _tokens[index];
    _tokens[index] = DeviceToken(
      id: token.id,
      name: token.name,
      kind: token.kind,
      hash: token.hash,
      createdAt: token.createdAt,
      revokedAt: at,
    );
    return true;
  }
}
