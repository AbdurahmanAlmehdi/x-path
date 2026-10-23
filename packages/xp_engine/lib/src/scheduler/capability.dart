/// What a runner can do, and what a job needs (D-19).
///
/// The engine probes the capabilities of a machine; it does not trust what a
/// runner advertises.
enum Capability {
  /// Signs iOS builds: macOS with Xcode, certificates and profiles. One job
  /// at a time per machine.
  iosSign('ios-sign'),

  /// Builds Android apps: the Android SDK and a JDK.
  android('android'),

  /// Builds and tests Flutter apps: git, to fetch the pinned SDK.
  flutter('flutter'),

  /// Builds Swift for Linux.
  swiftLinux('swift-linux'),

  /// Builds and signs iOS apps on Linux with omarchy-apple-dev (ADR 0014):
  /// opt-in and experimental, offered only by a runner configured for it. No
  /// step accepts it yet.
  iosLinux('ios-linux');

  new(this.wire);

  /// The name in workflows, on the wire and in the database.
  final String wire;

  /// The capability called [wire], or `null`.
  static Capability? fromWire(String wire) {
    for (final capability in values) {
      if (capability.wire == wire) return capability;
    }
    return null;
  }
}
