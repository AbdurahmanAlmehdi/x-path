import 'dart:io';

/// The captured output of a tool, from `test/src/toolchain/fixtures`.
///
/// They were taken from real runs on macOS (fvm 3.2.1 and 4.0.5, gh 2.96.0,
/// Xcode 27.1, Flutter 3.47.6), with the home folder replaced by `/Users/dev`.
/// `shorebird_version.txt` follows `versionBanner` of the Shorebird CLI source
/// (1.6.128), since Shorebird is not installed on the machine that captured
/// the others.
String fixture(String name) =>
    File('test/src/toolchain/fixtures/$name').readAsStringSync();
