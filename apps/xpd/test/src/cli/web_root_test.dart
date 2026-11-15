import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xpd/xpd.dart';

void main() {
  late String root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_web_root_').path;
    addTearDown(() => Directory(root).deleteSync(recursive: true));
  });

  void dashboardIn(String directory) {
    Directory(directory).createSync(recursive: true);
    File(p.join(directory, 'index.html')).writeAsStringSync('<!doctype html>');
  }

  test('is web next to the bin and lib of the engine bundle', () {
    dashboardIn(p.join(root, 'xpd', 'web'));

    expect(
      webRoot(executable: p.join(root, 'xpd', 'bin', 'xpd')),
      p.join(root, 'xpd', 'web'),
    );
  });

  test('inside XPath.app, is in its resources', () {
    final contents = p.join(root, 'XPath.app', 'Contents');
    dashboardIn(p.join(contents, 'Resources', 'web'));

    expect(
      webRoot(executable: p.join(contents, 'Helpers', 'xpd', 'bin', 'xpd')),
      p.join(contents, 'Resources', 'web'),
    );
  });

  test('is null when no folder holds an index.html', () {
    Directory(p.join(root, 'xpd', 'web')).createSync(recursive: true);

    expect(webRoot(executable: p.join(root, 'xpd', 'bin', 'xpd')), isNull);
  });

  test('is null outside a bundle', () {
    dashboardIn(p.join(root, 'web'));

    for (final executable in ['', p.join(root, 'dart')]) {
      expect(webRoot(executable: executable), isNull, reason: executable);
    }
  });
}
