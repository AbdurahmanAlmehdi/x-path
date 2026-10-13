import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

void main() {
  late Directory root;
  late Directory first;
  late Directory second;

  File script(Directory directory, String name, {bool executable = true}) {
    final file = File(p.join(directory.path, name))
      ..writeAsStringSync('#!/bin/sh\n');
    final mode = executable ? '755' : '644';
    Process.runSync('chmod', [mode, file.path]);
    return file;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_lookup_');
    first = Directory(p.join(root.path, 'first'))..createSync();
    second = Directory(p.join(root.path, 'second'))..createSync();
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test('finds a program in the first directory that has it', () {
    script(second, 'tool');
    final inFirst = script(first, 'tool');

    expect(
      findExecutable('tool', '${first.path}:${second.path}'),
      inFirst.path,
    );
  });

  test('skips directories without it, and empty entries', () {
    final tool = script(second, 'tool');

    expect(findExecutable('tool', ':${first.path}::${second.path}'), tool.path);
  });

  test('does not find a file that is not executable, or a directory', () {
    script(first, 'plain', executable: false);
    Directory(p.join(first.path, 'folder')).createSync();

    expect(findExecutable('plain', first.path), isNull);
    expect(findExecutable('folder', first.path), isNull);
    expect(findExecutable('missing', first.path), isNull);
  });

  test('takes a name with a slash as a path', () {
    final tool = script(first, 'tool');
    final plain = script(first, 'plain', executable: false);

    expect(findExecutable(tool.path, null), tool.path);
    expect(findExecutable(plain.path, tool.path), isNull);
    expect(findExecutable('./nope/tool', first.path), isNull);
  });

  test('finds nothing without a PATH, or for an empty name', () {
    script(first, 'tool');

    expect(findExecutable('tool', null), isNull);
    expect(findExecutable('tool', ''), isNull);
    expect(findExecutable('', first.path), isNull);
  });
}
