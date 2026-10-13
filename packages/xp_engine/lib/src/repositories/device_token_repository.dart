import 'package:xp_engine/src/tokens/device_token.dart';

/// Where device tokens are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class DeviceTokenRepository {
  /// Every token, revoked ones included.
  Future<List<DeviceToken>> list();

  /// Stores [token].
  Future<void> add(DeviceToken token);
}

/// A [DeviceTokenRepository] that forgets everything on exit.
class InMemoryDeviceTokenRepository implements DeviceTokenRepository {
  final _tokens = <DeviceToken>[];

  @override
  Future<List<DeviceToken>> list() async => List.unmodifiable(_tokens);

  @override
  Future<void> add(DeviceToken token) async => _tokens.add(token);
}
