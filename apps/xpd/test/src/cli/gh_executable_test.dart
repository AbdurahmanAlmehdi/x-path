import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xpd/xpd.dart';

void main() {
  late Directory root;

  /// A `gh` in a new folder of [root], executable unless [mode] says not.
  String makeGh(String folder, {String mode = '755'}) {
    final directory = Directory(p.join(root.path, folder))
      ..createSync(recursive: true);
    final file = File(p.join(directory.path, 'gh'))
      ..writeAsStringSync('#!/bin/sh\n');
    Process.runSync('chmod', [mode, file.path]);
    return file.path;
  }

  setUp(() => root = Directory.systemTemp.createTempSync('xpd_gh_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('finds gh on PATH', () {
    final gh = makeGh('bin');

    expect(findGhExecutable(path: p.dirname(gh), fallbacks: []), gh);
  });

  test('takes the first directory of PATH that has gh', () {
    final first = makeGh('first');
    final second = makeGh('second');

    expect(
      findGhExecutable(
        path: '${p.dirname(first)}:${p.dirname(second)}',
        fallbacks: [],
      ),
      first,
    );
  });

  test('skips empty entries and directories without gh', () {
    final gh = makeGh('bin');
    Directory(p.join(root.path, 'empty')).createSync();

    expect(
      findGhExecutable(
        path: ':${p.join(root.path, 'empty')}::${p.dirname(gh)}',
        fallbacks: [],
      ),
      gh,
    );
  });

  test('skips a gh that cannot be run', () {
    final plain = makeGh('plain', mode: '644');
    final good = makeGh('good');

    expect(
      findGhExecutable(
        path: '${p.dirname(plain)}:${p.dirname(good)}',
        fallbacks: [],
      ),
      good,
    );
  });

  test('skips a directory called gh', () {
    final folder = Directory(p.join(root.path, 'bin', 'gh'))
      ..createSync(recursive: true);

    expect(
      findGhExecutable(path: p.dirname(folder.path), fallbacks: []),
      isNull,
    );
  });

  test('uses the fallbacks after PATH, in order', () {
    final onPath = makeGh('path');
    final first = makeGh('first');
    final second = makeGh('second');

    expect(
      findGhExecutable(path: p.dirname(onPath), fallbacks: [second, first]),
      onPath,
    );
    expect(
      findGhExecutable(
        path: p.join(root.path, 'nowhere'),
        fallbacks: [p.join(root.path, 'missing', 'gh'), second, first],
      ),
      second,
    );
  });

  test('works without a PATH', () {
    final fallback = makeGh('fallback');

    expect(findGhExecutable(path: null, fallbacks: [fallback]), fallback);
    expect(findGhExecutable(path: null, fallbacks: []), isNull);
  });
}
