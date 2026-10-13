import 'dart:typed_data';

/// Whether the engine can currently reach its secrets.
enum SecretsStatus {
  /// Secrets can be read and written.
  unlocked,

  /// Secrets cannot be reached: the Keychain is locked, or the master key is
  /// missing or unreadable. The engine never prompts for it. Jobs that need
  /// secrets queue until the status goes back to [unlocked].
  locked,
}

/// A secret store operation failed.
///
/// The message never contains a secret value.
class SecretStoreException implements Exception {
  /// Creates an exception with [message].
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'SecretStoreException: $message';
}

/// The store cannot reach its secrets right now; see [SecretsStatus.locked].
class SecretsLockedException extends SecretStoreException {
  /// Creates an exception with [message].
  const new(super.message);

  @override
  String toString() => 'SecretsLockedException: $message';
}

/// Where credentials are kept on the engine machine.
///
/// `xp_secrets` has the macOS Keychain and the Linux encrypted-file
/// implementations. Keys are opaque names, for example the `secret_key` of a
/// credential reference. Values are any text, including multi-line text, or
/// any bytes (a binary Android keystore, for example).
///
/// Text and bytes share one key space: [write] stores the UTF-8 bytes of the
/// text, and [read] decodes the stored bytes as UTF-8. Reading a binary value
/// that is not UTF-8 with [read] is a [SecretStoreException]; use [readBytes].
abstract interface class SecretStore {
  /// Whether the last operation could reach the secrets.
  ///
  /// Starts as [SecretsStatus.unlocked]: a store only finds out that it is
  /// locked when it tries.
  SecretsStatus get status;

  /// The new [status], each time it changes.
  Stream<SecretsStatus> get statusChanges;

  /// The value stored under [key], or `null` if there is none.
  ///
  /// Throws a [SecretsLockedException] if the secrets cannot be reached and a
  /// [SecretStoreException] on any other failure.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any previous value.
  ///
  /// Throws like [read].
  Future<void> write(String key, String value);

  /// The bytes stored under [key], or `null` if there is none.
  ///
  /// Throws like [read].
  Future<Uint8List?> readBytes(String key);

  /// Stores [value] under [key], replacing any previous value.
  ///
  /// Throws like [read].
  Future<void> writeBytes(String key, List<int> value);

  /// Removes the value stored under [key]. Does nothing if there is none.
  ///
  /// Throws like [read].
  Future<void> delete(String key);
}
