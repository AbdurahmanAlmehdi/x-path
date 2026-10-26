import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every link into the guide that the CLI, the app, the engine's hints and
/// the skills print, and every relative link of the docs, reaches a page that
/// exists and a heading on it (U8).
void main() {
  final root = _repositoryRoot();

  /// The anchors GitHub gives the headings of the Markdown file [path]:
  /// outside code fences, a repeated one with `-1`, `-2` and so on.
  Set<String> anchorsOf(String path) {
    final anchors = <String>{};
    var fenced = false;
    for (final line in File(path).readAsLinesSync()) {
      if (line.trimLeft().startsWith('```')) fenced = !fenced;
      if (fenced || !RegExp('^#{1,6} ').hasMatch(line)) continue;
      final slug = _slug(line.replaceFirst(RegExp('^#+ '), ''));
      var anchor = slug;
      for (var n = 1; anchors.contains(anchor); n++) {
        anchor = '$slug-$n';
      }
      anchors.add(anchor);
    }
    return anchors;
  }

  /// Why the link to [target] from [from] does not resolve, or `null`.
  String? problemOf(String from, String target) {
    final [file, ...anchor] = target.split('#');
    final path = p.normalize(p.join(p.dirname(from), file));
    if (file.isNotEmpty &&
        FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      return 'no file $path';
    }
    if (anchor.isEmpty || !path.endsWith('.md')) return null;
    final page = file.isEmpty ? from : path;
    return anchorsOf(page).contains(anchor.single)
        ? null
        : 'no heading for #${anchor.single} in ${p.relative(page, from: root)}';
  }

  List<File> filesUnder(String folder, Set<String> extensions) => [
    for (final entity in Directory(
      p.join(root, folder),
    ).listSync(recursive: true))
      if (entity is File &&
          extensions.contains(p.extension(entity.path)) &&
          !entity.path.contains('${p.separator}.dart_tool${p.separator}') &&
          !entity.path.contains('${p.separator}build${p.separator}'))
        entity,
  ];

  test('the code, the hints and the skills link to pages and anchors there '
      'are', () {
    final guide = p.join(root, 'docs', 'guide');
    final problems = <String>[];
    final sources = [
      for (final folder in ['apps', 'packages'])
        ...filesUnder(folder, {'.dart', '.arb'}).where(
          (file) => file.path.contains('${p.separator}lib${p.separator}'),
        ),
      ...filesUnder('skills', {'.md'}),
    ];
    var links = 0;
    for (final file in sources) {
      final text = file.readAsStringSync();
      final targets = [
        for (final match in RegExp(
          r'docs/guide/([a-z0-9-]+\.md)(#[a-z0-9-]+)?',
        ).allMatches(text))
          '${match[1]}${match[2] ?? ''}',
        for (final match in RegExp(
          r"guideUri\(\s*'([a-z0-9-]+\.md)'(?:,\s*anchor:\s*'([a-z0-9-]+)')?",
        ).allMatches(text))
          '${match[1]}${match[2] == null ? '' : '#${match[2]}'}',
      ];
      for (final target in targets) {
        links++;
        final problem = problemOf(p.join(guide, 'index'), target);
        if (problem != null) {
          problems.add('${p.relative(file.path, from: root)}: $problem');
        }
      }
    }

    expect(problems, isEmpty);
    expect(links, greaterThan(3), reason: 'the scan finds the links');
  });

  test('the README, the guide and the reference link to files and headings '
      'there are', () {
    final pages = [
      File(p.join(root, 'README.md')),
      ...filesUnder(p.join('docs', 'guide'), {'.md'}),
      ...filesUnder(p.join('docs', 'reference'), {'.md'}),
    ];
    final problems = <String>[];
    for (final page in pages) {
      for (final match in RegExp(
        r'\]\(([^)\s]+)\)',
      ).allMatches(page.readAsStringSync())) {
        final target = match[1]!;
        if (target.startsWith(RegExp('https?:|mailto:'))) continue;
        final problem = problemOf(page.path, target);
        if (problem != null) {
          problems.add('${p.relative(page.path, from: root)}: $problem');
        }
      }
    }

    expect(problems, isEmpty);
  });

  test('the README links every page of the guide', () {
    final readme = File(p.join(root, 'README.md')).readAsStringSync();

    for (final page in filesUnder(p.join('docs', 'guide'), {'.md'})) {
      expect(
        readme,
        contains('docs/guide/${p.basename(page.path)}'),
        reason: p.basename(page.path),
      );
    }
    expect(readme.length, lessThan(20 * 1024));
  });

  test('a heading becomes the anchor GitHub gives it', () {
    expect(_slug('Reaching the engine'), 'reaching-the-engine');
    expect(_slug('The `xp` command line'), 'the-xp-command-line');
    expect(_slug('Tailscale (recommended)'), 'tailscale-recommended');
    expect(_slug('1. Install the app'), '1-install-the-app');
  });
}

/// The anchor GitHub makes of the heading [text]: lower case, without
/// punctuation, spaces made hyphens.
String _slug(String text) => text
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
    .replaceAll(' ', '-');

/// The root of the repository: the folder above this package with
/// `docs/guide`.
String _repositoryRoot() {
  var directory = Directory.current.absolute;
  while (!Directory(p.join(directory.path, 'docs', 'guide')).existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('No docs/guide above ${Directory.current.path}.');
    }
    directory = parent;
  }
  return directory.path;
}
