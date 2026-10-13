import 'dart:io';

import 'package:xp_tool/xp_tool.dart';

/// Fails when a package depends on something its layer may not.
///
/// Run from anywhere: `dart run tool/check_layers.dart`.
void main() {
  final root = File.fromUri(Platform.script).parent.parent;
  exitCode = runCheckLayers(root: root, out: stdout, err: stderr);
}
