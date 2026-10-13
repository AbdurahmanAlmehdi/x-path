import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late Directory repo;
  late Directory outside;
  late DirectoryScanSource source;

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('xp_scan_source_');
    addTearDown(() => temp.deleteSync(recursive: true));
    repo = Directory('${temp.path}/repo')..createSync();
    outside = Directory('${temp.path}/outside')..createSync();
    File('${outside.path}/secret.txt').writeAsStringSync('top secret');
    File('${repo.path}/pubspec.yaml').writeAsStringSync('name: a\n');
    Directory('${repo.path}/lib/src').createSync(recursive: true);
    File('${repo.path}/lib/main.dart').writeAsStringSync('void main() {}');
    File('${repo.path}/.fvmrc').writeAsStringSync('{}');
    source = DirectoryScanSource(repo.path);
  });

  group('exists', () {
    test('is true for files, directories and the root', () async {
      expect(await source.exists('pubspec.yaml'), isTrue);
      expect(await source.exists('lib/src'), isTrue);
      expect(await source.exists(''), isTrue);
      expect(await source.exists('.fvmrc'), isTrue);
    });

    test('is false for what is not there', () async {
      expect(await source.exists('ios'), isFalse);
      expect(
        await DirectoryScanSource('${repo.path}/nope').exists(''),
        isFalse,
      );
    });
  });

  group('read', () {
    test('returns the text of a file', () async {
      expect(await source.read('lib/main.dart'), 'void main() {}');
    });

    test('is null for a missing file and for a directory', () async {
      expect(await source.read('missing.txt'), isNull);
      expect(await source.read('lib'), isNull);
    });

    test('reads bytes that are not UTF-8 without failing', () async {
      File('${repo.path}/odd.txt').writeAsBytesSync([0x61, 0xff, 0x62]);

      expect(await source.read('odd.txt'), 'a�b');
    });

    test('is null for a file above the size limit', () async {
      final small = DirectoryScanSource(repo.path, maxFileBytes: 4);

      expect(await small.read('pubspec.yaml'), isNull);
      expect(await small.read('.fvmrc'), '{}');
    });

    test(
      'is null for a file that cannot be read',
      skip: Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
          ? 'root can read anything'
          : false,
      () async {
        final locked = File('${repo.path}/locked.txt')..writeAsStringSync('x');
        Process.runSync('chmod', ['000', locked.path]);
        addTearDown(() => Process.runSync('chmod', ['644', locked.path]));

        expect(await source.read('locked.txt'), isNull);
      },
    );
  });

  group('list', () {
    test('lists entries sorted, files and directories', () async {
      expect(await source.list(''), const [
        ScanEntry('.fvmrc', isDirectory: false),
        ScanEntry('lib', isDirectory: true),
        ScanEntry('pubspec.yaml', isDirectory: false),
      ]);
      expect(await source.list('lib'), const [
        ScanEntry('main.dart', isDirectory: false),
        ScanEntry('src', isDirectory: true),
      ]);
    });

    test('is empty for a missing directory and for a file', () async {
      expect(await source.list('nope'), isEmpty);
      expect(await source.list('pubspec.yaml'), isEmpty);
    });
  });

  group('paths that leave the directory', () {
    test('are refused when absolute or climbing', () async {
      final secret = '${outside.path}/secret.txt';

      expect(await source.exists(secret), isFalse);
      expect(await source.read(secret), isNull);
      expect(await source.read('../outside/secret.txt'), isNull);
      expect(await source.read('lib/../../outside/secret.txt'), isNull);
      expect(await source.list('..'), isEmpty);
    });

    test('are refused through a symbolic link', () async {
      Link('${repo.path}/linked.txt').createSync('${outside.path}/secret.txt');
      Link('${repo.path}/ios').createSync(outside.path);

      expect(await source.exists('linked.txt'), isFalse);
      expect(await source.read('linked.txt'), isNull);
      expect(await source.read('ios/secret.txt'), isNull);
      expect(await source.list('ios'), isEmpty);
    });

    test('are allowed through a link that stays inside', () async {
      Link('${repo.path}/alias.dart').createSync('${repo.path}/lib/main.dart');

      expect(await source.read('alias.dart'), 'void main() {}');
    });

    test('are missing when the link is broken', () async {
      Link('${repo.path}/broken').createSync('${repo.path}/nowhere');

      expect(await source.exists('broken'), isFalse);
    });
  });

  test('works when the root itself is reached through a link', () async {
    final alias = Link('${repo.parent.path}/alias')..createSync(repo.path);

    expect(await DirectoryScanSource(alias.path).read('.fvmrc'), '{}');
  });

  test('never writes: a scan leaves the directory as it was', () async {
    String describe(FileSystemEntity entity) {
      final stat = entity.statSync();
      return '${entity.path} ${stat.modified} ${stat.size}';
    }

    String snapshot() => repo.listSync(recursive: true).map(describe).join();
    final before = snapshot();

    await const ProjectScanner().scan(source);

    expect(snapshot(), before);
  });
}
