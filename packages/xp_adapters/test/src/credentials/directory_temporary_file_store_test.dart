import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('xpath-tmp-');
    root = p.join(temp.path, 'tmp', 'credentials');
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  test('writes the bytes to a private file in a private folder', () async {
    final store = DirectoryTemporaryFileStore(root);

    final file = await store.create([0, 1, 250, 255]);

    expect(File(file.path).readAsBytesSync(), [0, 1, 250, 255]);
    expect(p.dirname(file.path), root);
    if (!Platform.isWindows) {
      expect(File(file.path).statSync().mode & 0x1ff, 384); // 0600
      expect(Directory(root).statSync().mode & 0x1ff, 448); // 0700
    }
  });

  test('makes a new file every time', () async {
    final store = DirectoryTemporaryFileStore(root);

    final first = await store.create([1]);
    final second = await store.create([2]);

    expect(first.path, isNot(second.path));
    expect(Directory(root).listSync(), hasLength(2));
  });

  test('deletes a file, and does nothing when it is gone', () async {
    final file = await DirectoryTemporaryFileStore(root).create([1]);

    await file.delete();
    await file.delete();

    expect(File(file.path).existsSync(), isFalse);
  });

  test('deletes everything left behind', () async {
    final store = DirectoryTemporaryFileStore(root);
    await store.create([1]);

    await store.deleteAll();
    await store.deleteAll();

    expect(Directory(root).existsSync(), isFalse);
  });

  test('names files from the random source it is given', () async {
    final store = DirectoryTemporaryFileStore(root, random: Random(1));

    final file = await store.create([1]);

    expect(p.basename(file.path), hasLength(24));
  });

  test('fails when it cannot make the file private', () async {
    final store = DirectoryTemporaryFileStore(
      root,
      runProcess: (executable, arguments) async =>
          ProcessResult(0, 1, '', 'nope'),
    );

    await expectLater(store.create([1]), throwsA(isA<FileSystemException>()));
  });
}
