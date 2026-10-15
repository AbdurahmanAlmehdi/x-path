/// Where the app keeps the device token (D-06) of each engine it knows.
///
/// The app backs it with the macOS Keychain; it never goes in a file.
abstract interface class TokenVault {
  /// The token of the engine [engineId], or `null` if none is saved.
  Future<String?> read(String engineId);

  /// Saves the token of the engine [engineId], replacing any earlier one.
  Future<void> write(String engineId, String token);

  /// Forgets the token of the engine [engineId].
  Future<void> delete(String engineId);
}

/// A [TokenVault] that keeps nothing beyond the life of the process. For
/// tests and previews.
class MemoryTokenVault implements TokenVault {
  /// Creates a vault holding [tokens].
  new([Map<String, String>? tokens]) : _tokens = {...?tokens};

  final Map<String, String> _tokens;

  @override
  Future<String?> read(String engineId) async => _tokens[engineId];

  @override
  Future<void> write(String engineId, String token) async =>
      _tokens[engineId] = token;

  @override
  Future<void> delete(String engineId) async => _tokens.remove(engineId);
}
