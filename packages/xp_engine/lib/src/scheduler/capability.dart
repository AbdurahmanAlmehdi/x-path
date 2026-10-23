import 'package:equatable/equatable.dart';

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

/// One thing a job needs of a runner: any of [anyOf], the first preferred
/// (D-19, ADR 0014).
///
/// In a job's `capabilities` it is its capabilities joined by `|`, such as
/// `ios-sign|ios-linux`; a single capability is a need of its own, so a job
/// that needs `flutter` and `ios-sign` reads as before.
class CapabilityNeed extends Equatable {
  /// Creates a need met by any of [anyOf].
  const new(this.anyOf);

  /// Reads [wire]; capabilities this engine does not know are left out.
  factory parse(String wire) => CapabilityNeed([
    for (final name in wire.split('|')) ?Capability.fromWire(name),
  ]);

  /// The needs of a job's [capabilities], without empty ones.
  static List<CapabilityNeed> parseAll(Iterable<String> capabilities) => [
    for (final wire in capabilities)
      if (CapabilityNeed.parse(wire) case final need when need.anyOf.isNotEmpty)
        need,
  ];

  /// The capabilities that meet it, the preferred first.
  final List<Capability> anyOf;

  /// The form in a job's `capabilities`.
  String get wire => anyOf.map((capability) => capability.wire).join('|');

  /// The form in a message: `ios-sign or ios-linux`.
  String get described =>
      anyOf.map((capability) => capability.wire).join(' or ');

  /// How well a runner that offers [offered] meets it: 0 for the preferred
  /// capability, 1 for the next, and so on; `null` when it does not.
  int? rankFor(Set<Capability> offered) {
    final index = anyOf.indexWhere(offered.contains);
    return index < 0 ? null : index;
  }

  /// Whether a job with it takes the one iOS place of a machine: Xcode and
  /// its keychain, or omarchy-apple-dev's toolchain, cannot be shared.
  bool get isIos =>
      anyOf.contains(Capability.iosSign) || anyOf.contains(Capability.iosLinux);

  @override
  List<Object?> get props => [anyOf];
}
