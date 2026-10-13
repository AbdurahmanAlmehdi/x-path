import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';

Stream<List<int>> _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  return Stream.value(ZipEncoder().encode(archive));
}

Future<String?> _snapshot(ArtifactKind kind, Stream<List<int>> package) async {
  final stream = await const ZipSnapshotReader().snapshotOf(kind, package);
  if (stream == null) return null;
  return utf8.decode([for (final chunk in await stream.toList()) ...chunk]);
}

int _scratchFolders() => Directory.systemTemp
    .listSync()
    .where((entity) => entity.path.contains('xpath-package-'))
    .length;

void main() {
  test('takes libapp.so out of an APK', () async {
    final package = _zip({
      'classes.dex': 'dex',
      'lib/arm64-v8a/libflutter.so': 'engine',
      'lib/arm64-v8a/libapp.so': 'api.example.com',
    });

    expect(await _snapshot(ArtifactKind.apk, package), 'api.example.com');
  });

  test('takes libapp.so out of the base module of an AAB', () async {
    final package = _zip({
      'BundleConfig.pb': 'config',
      'feature/lib/arm64-v8a/libapp.so': 'wrong',
      'base/lib/arm64-v8a/libapp.so': 'api.example.com',
    });

    expect(await _snapshot(ArtifactKind.aab, package), 'api.example.com');
  });

  test('takes App.framework/App out of an IPA', () async {
    final package = _zip({
      'Payload/Runner.app/Info.plist': 'plist',
      'Payload/Runner.app/Frameworks/App.framework/App': 'api.example.com',
    });

    expect(await _snapshot(ArtifactKind.ipa, package), 'api.example.com');
  });

  test('is null for a package without a snapshot', () async {
    final package = _zip({'classes.dex': 'dex'});
    final before = _scratchFolders();

    expect(await _snapshot(ArtifactKind.apk, package), isNull);
    expect(_scratchFolders(), before);
  });

  test('is null for a kind that is not a package', () async {
    expect(await _snapshot(ArtifactKind.mapping, _zip({'a': 'b'})), isNull);
  });

  test('rejects a file that is not a ZIP archive', () async {
    final before = _scratchFolders();

    await expectLater(
      _snapshot(ArtifactKind.apk, Stream.value(utf8.encode('plain text'))),
      throwsFormatException,
    );

    expect(_scratchFolders(), before);
  });

  test('rejects a ZIP archive that was cut short', () async {
    final whole = [
      for (final chunk in await _zip({
        'lib/arm64-v8a/libapp.so': 'x' * 500,
      }).toList())
        ...chunk,
    ];

    await expectLater(
      _snapshot(ArtifactKind.apk, Stream.value(whole.sublist(0, 100))),
      throwsFormatException,
    );
  });
}
