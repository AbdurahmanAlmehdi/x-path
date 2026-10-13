import 'package:xp_engine/xp_engine.dart';

/// A [FlutterInstaller] over a set of versions, for tests.
class FakeFlutterInstaller implements FlutterInstaller {
  /// Creates an installer whose cache already holds [installed].
  new({Set<String> installed = const {}}) : installed = {...installed};

  /// The versions in the cache.
  final Set<String> installed;

  /// The versions [install] was asked for, in order.
  final installs = <String>[];

  /// If set, [install] throws it.
  FlutterInstallException? failure;

  @override
  String pathFor(String version) => '/data/toolchains/flutter/$version';

  @override
  Future<bool> isInstalled(String version) async => installed.contains(version);

  @override
  Future<void> install(String version) async {
    installs.add(version);
    final error = failure;
    if (error != null) throw error;
    installed.add(version);
  }
}
