import 'dart:io';

import 'package:xp_tool/xp_tool.dart';

/// Fails when a workspace package is missing from the per-package coverage
/// jobs of the `gate` or `macos` workflow, or runs with the wrong threshold.
///
/// Run from anywhere: `dart run tool/check_ci_matrix.dart`.
void main() {
  final root = File.fromUri(Platform.script).parent.parent;
  exitCode = runCheckCiMatrix(root: root, out: stdout, err: stderr);
}
