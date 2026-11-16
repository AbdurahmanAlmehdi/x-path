import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// Where device tokens are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class DeviceTokenRepository {
  /// Every token, revoked ones included.
  Future<List<DeviceToken>> list();

  /// The token whose hash is [hash], revoked or not, or `null`.
  Future<DeviceToken?> findByHash(String hash);

  /// Stores [token].
  Future<void> add(DeviceToken token);

  /// Revokes the token [id] at [at]. Returns whether it was valid until now:
  /// `false` for a token that is unknown or revoked already.
  Future<bool> revoke(String id, {required DateTime at});

  /// Revokes, at [at], every valid token of the person [personId]. Returns
  /// how many there were.
  Future<int> revokeOwnedBy(String personId, {required DateTime at});

  /// Moves the expiry of the token [id] to [expiresAt], unless it was
  /// revoked.
  Future<void> renew(String id, {required DateTime expiresAt});

  /// Deletes every token of [kinds] that expired or was revoked before
  /// [before]. Returns how many went.
  Future<int> deleteEnded({
    required Set<DeviceTokenKind> kinds,
    required DateTime before,
  });
}

/// A [DeviceTokenRepository] that forgets everything on exit.
class InMemoryDeviceTokenRepository implements DeviceTokenRepository {
  final _tokens = <DeviceToken>[];

  @override
  Future<List<DeviceToken>> list() async => List.unmodifiable(_tokens);

  @override
  Future<DeviceToken?> findByHash(String hash) async =>
      _tokens.where((token) => token.hash == hash).firstOrNull;

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

  @override
  Future<void> renew(String id, {required DateTime expiresAt}) async {
    final index = _tokens.indexWhere((token) => token.id == id);
    if (index < 0 || _tokens[index].isRevoked) return;
    _tokens[index] = _tokens[index].renewed(expiresAt);
  }

  @override
  Future<int> deleteEnded({
    required Set<DeviceTokenKind> kinds,
    required DateTime before,
  }) async {
    final count = _tokens.length;
    _tokens.removeWhere(
      (token) =>
          kinds.contains(token.kind) &&
          ((token.expiresAt?.isBefore(before) ?? false) ||
              (token.revokedAt?.isBefore(before) ?? false)),
    );
    return count - _tokens.length;
  }
}
