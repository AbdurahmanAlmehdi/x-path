import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

import '../../helpers/schema_dump.dart';

void main() {
  const directories = DirectoryBuildDirectories();
  late Directory root;

  void put(String path, String content) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  Future<List<int>> bytesOf(Stream<List<int>> stream) async => [
    for (final chunk in await stream.toList()) ...chunk,
  ];

  int scratchFolders() => Directory.systemTemp
      .listSync()
      .where((entity) => entity.path.contains('xpath-zip-'))
      .length;

  setUp(() => root = tempDirectory());

  test('exists only for a folder', () async {
    put('dSYMs/Runner.dSYM/Info.plist', 'x');

    expect(await directories.exists('${root.path}/dSYMs'), isTrue);
    expect(
      await directories.exists('${root.path}/dSYMs/Runner.dSYM/Info.plist'),
      isFalse,
    );
    expect(await directories.exists('${root.path}/missing'), isFalse);
  });

  test('removes a folder and counts the bytes in it', () async {
    put('Frameworks/A.framework/A', '12345');
    put('Frameworks/A.framework/Headers/a.h', '678');

    final bytes = await directories.remove(
      '${root.path}/Frameworks/A.framework',
    );

    expect(bytes, 8);
    expect(
      Directory('${root.path}/Frameworks/A.framework').existsSync(),
      isFalse,
    );
    expect(Directory('${root.path}/Frameworks').existsSync(), isTrue);
  });

  test('zips a folder under its own name', () async {
    put('dSYMs/Runner.app.dSYM/Contents/Info.plist', 'plist');
    put('dSYMs/Flutter.framework.dSYM/Contents/Info.plist', 'other');
    final before = scratchFolders();

    final zip = await bytesOf(directories.zip('${root.path}/dSYMs'));

    final archive = ZipDecoder().decodeBytes(zip);
    final files = {
      for (final entry in archive.files)
        if (entry.isFile) entry.name: String.fromCharCodes(entry.content),
    };
    expect(files, {
      'dSYMs/Runner.app.dSYM/Contents/Info.plist': 'plist',
      'dSYMs/Flutter.framework.dSYM/Contents/Info.plist': 'other',
    });
    expect(scratchFolders(), before);
  });

  test(
    'fails to zip a folder that is not there, leaving nothing behind',
    () async {
      final before = scratchFolders();

      await expectLater(
        directories.zip('${root.path}/missing'),
        emitsError(isA<FileSystemException>()),
      );

      expect(scratchFolders(), before);
    },
  );
}
