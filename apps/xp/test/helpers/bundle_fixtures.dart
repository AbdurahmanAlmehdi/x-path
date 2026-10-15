import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xp/src/runner/update/runner_updater.dart';
import 'package:xp_client/xp_client.dart';

/// Writes a bundle folder the way `dart build cli` lays one out: `bin/xp` and
/// `lib/`. The `xp` is a shell script that prints [version] for `--version`,
/// so that a test needs no compiler; [versionOutput] and [exitCode] make it say
/// something else, or fail.
Directory writeBundle(
  Directory parent, {
  required String version,
  String? versionOutput,
  int exitCode = 0,
  bool executable = true,
  bool withExecutable = true,
}) {
  final bundle = parent.createTempSync('bundle-$version-');
  Directory(p.join(bundle.path, 'lib')).createSync();
  File(p.join(bundle.path, 'lib', 'libsqlite3.so')).writeAsStringSync('lib');
  if (withExecutable) {
    Directory(p.join(bundle.path, 'bin')).createSync();
    final script = File(p.join(bundle.path, 'bin', 'xp'))
      ..writeAsStringSync(
        '#!/bin/sh\necho ${versionOutput ?? version}\nexit $exitCode\n',
      );
    if (executable) {
      Process.runSync('chmod', ['+x', script.path]);
    }
  }
  return bundle;
}

/// The bundle folder as the `.tar.gz` the engine serves: its top level is
/// `bin` and `lib`.
List<int> tarBundle(Directory bundle) {
  final archive = File('${bundle.path}.tar.gz');
  final result = Process.runSync('tar', [
    '-czf',
    archive.path,
    '-C',
    bundle.path,
    '.',
  ]);
  if (result.exitCode != 0) throw StateError('tar: ${result.stderr}');
  return archive.readAsBytesSync();
}

/// The SHA-256 of [bytes] in lowercase hexadecimal.
String digestOf(List<int> bytes) => sha256.convert(bytes).toString();

/// A fetcher that serves [bytes] with the digest and size the engine would
/// announce, unless told to announce others (or none).
BundleFetcher fetcherOf(
  List<int> bytes, {
  String? sha256,
  int? length,
  bool announce = true,
  List<({String os, String arch})>? asked,
}) => ({required os, required arch}) async {
  asked?.add((os: os, arch: arch));
  return ArtifactDownload(
    content: Stream.value(bytes),
    sha256: announce ? sha256 ?? digestOf(bytes) : null,
    length: announce ? length ?? bytes.length : null,
  );
};
