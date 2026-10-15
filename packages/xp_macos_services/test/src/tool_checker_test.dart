import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  late Directory root;
  late String brew;
  late String usrBin;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_tools_');
    brew = p.join(root.path, 'opt-homebrew-bin');
    usrBin = '/usr/bin';
    for (final name in ['fvm', 'gh']) {
      File(p.join(brew, name)).createSync(recursive: true);
    }
  });

  tearDown(() => root.deleteSync(recursive: true));

  PathToolChecker checker(ProcessResult Function() xcodeSelect) =>
      PathToolChecker(
        searchPath: [brew, usrBin],
        run: (executable, arguments) async {
          expect(executable, '/usr/bin/xcode-select');
          expect(arguments, ['-p']);
          return xcodeSelect();
        },
      );

  Map<Tool, String?> paths(List<ToolCheck> checks) => {
    for (final check in checks) check.tool: check.path,
  };

  test('finds Xcode and the tools on the search path', () async {
    final checks = await checker(
      () => ProcessResult(
        1,
        0,
        '/Applications/Xcode.app/Contents/Developer\n',
        '',
      ),
    ).check();
    expect(checks.map((check) => check.tool), Tool.values);
    expect(paths(checks), {
      Tool.xcode: '/Applications/Xcode.app/Contents/Developer',
      Tool.git: '/usr/bin/git',
      Tool.fvm: p.join(brew, 'fvm'),
      Tool.gh: p.join(brew, 'gh'),
      Tool.shorebird: null,
    });
    expect(checks.first.found, isTrue);
    expect(checks.last.found, isFalse);
    expect(
      ToolCheck(Tool.git, path: p.join('a')),
      ToolCheck(Tool.git, path: p.join('a')),
    );
    expect(Tool.xcode.required, isTrue);
    expect(Tool.shorebird.required, isFalse);
  });

  test('does not count the Command Line Tools as Xcode', () async {
    final checks = await checker(
      () => ProcessResult(1, 0, '/Library/Developer/CommandLineTools', ''),
    ).check();
    expect(paths(checks)[Tool.xcode], isNull);
    expect(paths(checks)[Tool.git], '/usr/bin/git');
  });

  test('skips the git shim without developer tools', () async {
    final checks = await checker(
      () => ProcessResult(
        1,
        2,
        '',
        'error: unable to get active developer directory',
      ),
    ).check();
    expect(paths(checks)[Tool.xcode], isNull);
    expect(paths(checks)[Tool.git], isNull);
  });

  test('copes with xcode-select missing', () async {
    final checks = await PathToolChecker(
      searchPath: [brew],
      run: (executable, arguments) async =>
          throw ProcessException(executable, arguments),
    ).check();
    expect(paths(checks)[Tool.xcode], isNull);
  });

  test('searches the folders of the engine service', () {
    expect(serviceSearchPath('/Users/me'), [
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/local/bin',
      '/Users/me/.shorebird/bin',
      '/Users/me/.pub-cache/bin',
      '/Users/me/fvm/default/bin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
    ]);
  });

  test(
    'runs xcode-select for real by default',
    () async {
      final checks = await const PathToolChecker(searchPath: []).check();
      expect(checks, hasLength(Tool.values.length));
    },
    tags: 'process',
    testOn: 'mac-os',
  );
}
