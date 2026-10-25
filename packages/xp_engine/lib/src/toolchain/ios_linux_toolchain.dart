/// What a Linux runner builds iOS apps with (ADR 0014): its omarchy-apple-dev
/// checkout, and the Flutter installs that `flutter/setup.sh` prepared. Those
/// are kept apart from the SDKs other builds use, one per Flutter version,
/// because setup.sh replaces the iOS `gen_snapshot` of the install it runs on.
///
/// `xp_adapters` has the `dart:io` implementation; a `BuildToolchain` over
/// [installs] resolves the installs.
abstract interface class IosLinuxToolchain {
  /// The omarchy-apple-dev checkout (`XP_IOS_LINUX_DIR`).
  String get directory;

  /// The folder of the dedicated Flutter installs,
  /// `<data dir>/toolchains/flutter-ios-linux`.
  String get installs;

  /// The commit the checkout is at, or `null` if git cannot tell.
  Future<String?> commit();

  /// Whether the Flutter install at [flutterRoot] has the Linux-hosted iOS
  /// `gen_snapshot` (an ELF file), which is what setup.sh leaves.
  Future<bool> isPrepared(String flutterRoot);

  /// Notes that a job builds with the install of [version] now, and frees the
  /// installs no job used for a while. Returns the versions it freed.
  Future<List<String>> markUsed(String version);
}
