import 'package:path/path.dart' as p;

/// Where things are inside `XPath.app`.
///
/// The engine and the CLI are the bundles `dart build cli` makes (`bin/` and
/// `lib/`, the SQLite library beside the executable), copied into
/// `Contents/Helpers` by the release build (Phase 18b): helpers are code, and
/// Apple keeps code out of `Contents/Resources`.
class AppBundle {
  /// The bundle at [path], for example `/Applications/XPath.app`.
  const new(this.path);

  /// The bundle of the running app, from its executable
  /// (`XPath.app/Contents/MacOS/XPath`).
  factory fromExecutable(String executable) =>
      AppBundle(p.dirname(p.dirname(p.dirname(executable))));

  /// The path of the `.app` folder.
  final String path;

  /// The engine, `Contents/Helpers/xpd/bin/xpd`. The LaunchAgent plist names
  /// the same path as its `BundleProgram`.
  String get xpdExecutable => p.join(path, xpdBundleProgram);

  /// The CLI, `Contents/Helpers/xp/bin/xp`.
  String get xpExecutable =>
      p.join(path, 'Contents', 'Helpers', 'xp', 'bin', 'xp');

  /// The engine's path relative to the bundle, as the LaunchAgent plist has
  /// it.
  static const xpdBundleProgram = 'Contents/Helpers/xpd/bin/xpd';
}
