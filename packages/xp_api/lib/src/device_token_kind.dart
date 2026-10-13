/// What a device token is used by. One token per device or client (D-06).
enum DeviceTokenKind {
  /// The macOS app.
  app,

  /// The `xp` command-line client.
  cli,

  /// `xp mcp`. Can never approve or loosen gates (D-13).
  mcp,

  /// `xp runner`.
  runner,
}
