import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Where the device tokens of the user are kept.
///
/// One engine has one token per client (D-06): `xp` has a `cli` token, and
/// `xp mcp` its own `mcp` token (D-12).
abstract interface class TokenVault {
  /// The token of [kind], or `null` if none was saved.
  Future<String?> read(DeviceTokenKind kind);

  /// Saves the token of [kind], replacing any earlier one.
  Future<void> write(DeviceTokenKind kind, String token);

  /// Forgets the token of [kind]. Does nothing if none was saved.
  Future<void> delete(DeviceTokenKind kind);
}

/// A [TokenVault] over the OS secret store: the Keychain on macOS, an
/// encrypted file on Linux.
class SecretStoreTokenVault implements TokenVault {
  /// Creates a vault that keeps the tokens in `store`.
  const new(this._store);

  final SecretStore _store;

  static String _key(DeviceTokenKind kind) => 'token.${kind.name}';

  @override
  Future<String?> read(DeviceTokenKind kind) => _store.read(_key(kind));

  @override
  Future<void> write(DeviceTokenKind kind, String token) =>
      _store.write(_key(kind), token);

  @override
  Future<void> delete(DeviceTokenKind kind) => _store.delete(_key(kind));
}
