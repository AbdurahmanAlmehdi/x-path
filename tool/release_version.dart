import 'dart:io';

import 'package:xp_tool/xp_tool.dart';

/// Decides and applies the version of an XPath release (release.yml).
///
///     dart run tool/release_version.dart next [--tag v<version>]
///     dart run tool/release_version.dart apply <version> <build>
///
/// `next` prints `version=`, `tag=`, `build=` and `prerelease=` lines for
/// `$GITHUB_OUTPUT`; `apply` writes the version into the pubspecs and
/// `packageVersion` constants of the checkout, which is never committed.
void main(List<String> arguments) {
  final root = File.fromUri(Platform.script).parent.parent;
  exitCode = runReleaseVersion(arguments, root: root, out: stdout, err: stderr);
}
