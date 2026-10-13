import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late Directory root;
  late Directory outside;
  late DirectoryWorkspace workspace;

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('xp_workspace_');
    addTearDown(() => temp.deleteSync(recursive: true));
    root = Directory('${temp.path}/worktree')..createSync();
    outside = Directory('${temp.path}/outside')..createSync();
    File('${outside.path}/secret.txt').writeAsStringSync('top secret');
    File('${root.path}/pubspec.yaml').writeAsStringSync('version: 1.0.0+1\n');
    Directory('${root.path}/ios/Runner').createSync(recursive: true);
    File('${root.path}/ios/Runner/Info.plist').writeAsStringSync('<plist/>');
    workspace = DirectoryWorkspace(root.path);
  });

  group('read side', () {
    test('reads, lists and finds files below the root', () async {
      expect(await workspace.exists('ios/Runner'), isTrue);
      expect(await workspace.exists(''), isTrue);
      expect(await workspace.exists('nope'), isFalse);
      expect(await workspace.read('pubspec.yaml'), 'version: 1.0.0+1\n');
      expect(await workspace.read('nope'), isNull);
      expect(await workspace.read('ios'), isNull);
      expect(await workspace.list(''), const [
        ScanEntry('ios', isDirectory: true),
        ScanEntry('pubspec.yaml', isDirectory: false),
      ]);
      expect(await workspace.list('nope'), isEmpty);
      expect(await workspace.list('pubspec.yaml'), isEmpty);
    });

    test('does not see outside the root', () async {
      Link('${root.path}/escape').createSync(outside.path);
      Link('${root.path}/secret').createSync('${outside.path}/secret.txt');

      for (final path in [
        '../outside/secret.txt',
        '/etc/hosts',
        'escape/secret.txt',
        'secret',
      ]) {
        expect(await workspace.exists(path), isFalse, reason: path);
        expect(await workspace.read(path), isNull, reason: path);
      }
      expect(await workspace.list('escape'), isEmpty);
    });

    test('reads a file that is not UTF-8 as missing, not as garbage', () async {
      File('${root.path}/blob.bin').writeAsBytesSync([0x62, 0xff, 0xfe, 0x00]);

      expect(await workspace.read('blob.bin'), isNull);
    });

    test('reads a file larger than the limit as missing', () async {
      File('${root.path}/big.txt').writeAsStringSync('x' * 100);

      expect(
        await DirectoryWorkspace(root.path, maxFileBytes: 10).read('big.txt'),
        isNull,
      );
      expect(await workspace.read('big.txt'), hasLength(100));
    });
  });

  group('write', () {
    test('replaces the text of an existing file', () async {
      await workspace.write('pubspec.yaml', 'version: 1.1.0+2\n');

      expect(
        File('${root.path}/pubspec.yaml').readAsStringSync(),
        'version: 1.1.0+2\n',
      );
      expect(await workspace.read('pubspec.yaml'), 'version: 1.1.0+2\n');
    });

    test('keeps the file mode', () async {
      Process.runSync('chmod', ['750', '${root.path}/pubspec.yaml']);

      await workspace.write('pubspec.yaml', 'x');

      expect(
        FileStat.statSync('${root.path}/pubspec.yaml').mode & 0x1ff,
        0x1e8, // 0750
      );
    });

    test('does not create files or write to directories', () async {
      for (final path in ['new.txt', 'ios', 'ios/new.txt', 'nope/new.txt']) {
        await expectLater(
          workspace.write(path, 'x'),
          throwsA(isA<FileSystemException>()),
          reason: path,
        );
      }
      expect(File('${root.path}/new.txt').existsSync(), isFalse);
    });

    test('cannot write outside the root', () async {
      Link('${root.path}/escape').createSync(outside.path);
      Link('${root.path}/secret').createSync('${outside.path}/secret.txt');

      for (final path in [
        '../outside/secret.txt',
        '/etc/hosts',
        'escape/secret.txt',
        'secret',
      ]) {
        await expectLater(
          workspace.write(path, 'pwned'),
          throwsA(isA<FileSystemException>()),
          reason: path,
        );
      }
      expect(
        File('${outside.path}/secret.txt').readAsStringSync(),
        'top secret',
      );
    });
  });
}
