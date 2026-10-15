import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  late Directory root;
  late String target;
  late String system;
  late String home;
  late FileSystemCliLinker linker;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_link_');
    target = p.join(
      root.path,
      'XPath.app',
      'Contents',
      'Helpers',
      'xp',
      'bin',
      'xp',
    );
    File(target).createSync(recursive: true);
    system = p.join(root.path, 'usr-local-bin');
    Directory(system).createSync();
    home = p.join(root.path, 'home');
    linker = FileSystemCliLinker(
      target: target,
      home: home,
      systemDirectory: system,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('links into the system folder when it can be written', () async {
    expect(await linker.status(), const CliLink(CliLinkState.notLinked));
    final link = await linker.link();
    expect(link, CliLink(CliLinkState.linked, path: p.join(system, 'xp')));
    expect(Link(p.join(system, 'xp')).targetSync(), target);
    expect(await linker.status(), link);
    expect(linker.userDirectory, p.join(home, '.local', 'bin'));
  });

  test(
    'falls back to ~/.local/bin when the system folder is missing',
    () async {
      Directory(system).deleteSync();
      final link = await linker.link();
      final path = p.join(home, '.local', 'bin', 'xp');
      expect(link, CliLink(CliLinkState.linked, path: path, fellBack: true));
      expect(Link(path).targetSync(), target);
      expect(await linker.status(), link);
    },
  );

  test('keeps or replaces a link into an XPath app', () async {
    final path = p.join(system, 'xp');
    Link(path).createSync(target);
    expect((await linker.link()).state, CliLinkState.linked);

    Link(path).updateSync('/Volumes/Old/XPath.app/Contents/Helpers/xp/bin/xp');
    expect((await linker.link()).state, CliLinkState.linked);
    expect(Link(path).targetSync(), target);
  });

  test('leaves another xp alone', () async {
    final path = p.join(system, 'xp');
    Link(path).createSync('/opt/other/xp');
    expect(await linker.link(), CliLink(CliLinkState.conflict, path: path));

    Link(path).deleteSync();
    File(path).writeAsStringSync('#!/bin/sh');
    expect((await linker.link()).state, CliLinkState.conflict);
    expect(Link(path).existsSync(), isFalse);
  });

  test('says when there is no xp to link', () async {
    File(target).deleteSync();
    expect(
      await linker.link(),
      CliLink(CliLinkState.missingBinary, path: target),
    );
  });

  test('fails when no folder can take the link', () async {
    Directory(system).deleteSync();
    File(home).writeAsStringSync('not a folder');
    final link = await linker.link();
    expect(link.state, CliLinkState.failed);
    expect(link.detail, isNotNull);
  });

  group('unlink', () {
    test('removes the links to this app and nothing else', () async {
      await linker.link();
      final other = p.join(linker.userDirectory, 'xp');
      Directory(linker.userDirectory).createSync(recursive: true);
      Link(other).createSync('/somewhere/else/xp');

      expect(await linker.unlink(), const CliLink(CliLinkState.notLinked));
      expect(
        FileSystemEntity.typeSync(p.join(system, 'xp'), followLinks: false),
        FileSystemEntityType.notFound,
      );
      expect(Link(other).targetSync(), '/somewhere/else/xp');
    });

    test('leaves a file called xp alone', () async {
      File(p.join(system, 'xp')).writeAsStringSync('#!/bin/sh');

      expect(await linker.unlink(), const CliLink(CliLinkState.notLinked));
      expect(File(p.join(system, 'xp')).existsSync(), isTrue);
    });

    test('says when the link cannot be removed', () async {
      await linker.link();
      Process.runSync('chmod', ['555', system]);
      addTearDown(() => Process.runSync('chmod', ['755', system]));

      final result = await linker.unlink();

      expect(result.state, CliLinkState.failed);
      expect(result.path, p.join(system, 'xp'));
      expect(result.detail, isNotEmpty);
    });
  });
}
