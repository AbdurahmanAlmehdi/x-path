/// How the app's connection to an engine stands (PRODUCT.md §5, "Engine").
enum EngineStatus {
  /// The first check has not answered yet.
  connecting,

  /// The engine answers; commands are allowed.
  connected,

  /// The engine stopped answering a moment ago; the app keeps trying.
  reconnecting,

  /// The engine has not answered for a while: the app shows what it cached,
  /// read-only.
  unreachable,

  /// The engine answers, but its Keychain is locked (D-10): jobs queue until
  /// it is unlocked.
  secretsLocked,

  /// The engine answers, but refuses the token of this app (revoked).
  rejected;

  /// Whether commands are allowed. A locked engine still answers (a command
  /// that needs a secret says so); anything else is read-only.
  bool get canCommand =>
      this == EngineStatus.connected || this == EngineStatus.secretsLocked;
}
