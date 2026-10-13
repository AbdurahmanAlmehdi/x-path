import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

import '../../helpers/schema_dump.dart';

void main() {
  const files = DirectoryBuildFiles();
  late Directory root;

  File put(String path, [String content = 'x']) {
    final file = File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return file;
  }

  setUp(() => root = tempDirectory());

  group('the freshness marker', () {
    test(
      'is older than a file written after it and newer than one before',
      () async {
        final before = put('before.txt')
          ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 1)),
          );

        final marker = await files.markBuildStart();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final after = put('after.txt');

        expect(marker.isUtc, isTrue);
        expect(after.statSync().modified.toUtc().isAfter(marker), isTrue);
        expect(before.statSync().modified.toUtc().isAfter(marker), isFalse);
      },
    );

    test('leaves nothing behind', () async {
      final before = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains('xpath-build-'))
          .length;

      await files.markBuildStart();

      final after = Directory.systemTemp
          .listSync()
          .where((e) => e.path.contains('xpath-build-'))
          .length;
      expect(after, before);
    });
  });

  test('stat describes a file and nothing else', () async {
    final file = put('a/app.apk');

    final stat = await files.stat(file.path);

    expect(stat?.path, file.path);
    expect(stat?.modified, file.statSync().modified.toUtc());
    expect(await files.stat('${root.path}/a'), isNull);
    expect(await files.stat('${root.path}/nope'), isNull);
  });

  test('find returns the files with that name anywhere below', () async {
    put('outputs/flutter-apk/app-dev-release.apk');
    put('outputs/apk/dev/release/app-dev-release.apk');
    put('outputs/apk/prod/release/app-prod-release.apk');
    put('outputs/app-dev-release.apk.sha1');

    final found = await files.find(
      '${root.path}/outputs',
      name: 'app-dev-release.apk',
    );

    expect(
      found.map((f) => f.path.substring(root.path.length)).toList()..sort(),
      [
        '/outputs/apk/dev/release/app-dev-release.apk',
        '/outputs/flutter-apk/app-dev-release.apk',
      ],
    );
    expect(await files.find('${root.path}/nope', name: 'x'), isEmpty);
  });

  group('files by extension', () {
    test('are listed from one directory only', () async {
      put('ipa/Mataa.ipa');
      put('ipa/notes.txt');
      put('ipa/nested/Other.ipa');

      final listed = await files.list('${root.path}/ipa', extension: '.ipa');

      expect(listed.map((f) => f.path), ['${root.path}/ipa/Mataa.ipa']);
      expect(await files.list('${root.path}/nope', extension: '.ipa'), isEmpty);
    });

    test('are deleted from one directory only', () async {
      put('ipa/Mataa.ipa');
      put('ipa/notes.txt');
      put('ipa/nested/Other.ipa');

      await files.deleteAll('${root.path}/ipa', extension: '.ipa');
      await files.deleteAll('${root.path}/nope', extension: '.ipa');

      expect(File('${root.path}/ipa/Mataa.ipa').existsSync(), isFalse);
      expect(File('${root.path}/ipa/notes.txt').existsSync(), isTrue);
      expect(File('${root.path}/ipa/nested/Other.ipa').existsSync(), isTrue);
    });
  });

  test('open streams the bytes', () async {
    final file = put('a.apk', 'abc');

    expect(
      utf8.decode(await files.open(file.path).expand((c) => c).toList()),
      'abc',
    );
  });
}
