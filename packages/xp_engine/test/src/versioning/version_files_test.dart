import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/version_fixtures.dart';

void main() {
  const files = [
    'pubspec.yaml',
    'ios/Runner/Info.plist',
    'ios/Runner/Info-Dev.plist',
  ];

  InMemoryWorkspace workspace({
    String version = '5.4.0+3282',
    Map<String, String> more = const {},
  }) => InMemoryWorkspace({
    'pubspec.yaml': pubspec(version),
    'ios/Runner/Info.plist': plist('5.4.0', '3282'),
    'ios/Runner/Info-Dev.plist': plist('5.4.0', '3282'),
    ...more,
  });

  Future<VersionFilesState> read(
    InMemoryWorkspace workspace, [
    List<String> paths = files,
  ]) => VersionFiles(workspace).read(paths);

  group('read', () {
    test('reads the pubspec and every plist', () async {
      final state = await read(workspace());

      expect(state.pubspecPath, 'pubspec.yaml');
      expect(state.pubspec, AppVersion.parse('5.4.0+3282'));
      expect(state.plists.map((plist) => plist.path), [
        'ios/Runner/Info.plist',
        'ios/Runner/Info-Dev.plist',
      ]);
      expect(state.plists.first.shortVersion, '5.4.0');
      expect(state.plists.first.buildNumber, '3282');
      expect(state.plists.first.literal, isTrue);
    });

    test('takes only the top-level version line of the pubspec', () async {
      // The dependency `version: ignored` is indented and does not count.
      final state = await read(workspace(), ['pubspec.yaml']);

      expect(state.pubspec.build, 3282);
    });

    test('accepts a comment after the version and Windows line ends', () async {
      final text = pubspec('1.2.3+4 # first').replaceAll('\n', '\r\n');
      final state = await read(InMemoryWorkspace({'pubspec.yaml': text}), [
        'pubspec.yaml',
      ]);

      expect(state.pubspec, AppVersion.parse('1.2.3+4'));
    });

    test('knows a plist that follows the build is not literal', () async {
      final state = await read(
        workspace(more: {'ios/Runner/Info.plist': flutterPlist}),
        ['pubspec.yaml', 'ios/Runner/Info.plist'],
      );

      expect(state.plists.single.literal, isFalse);
    });

    test('works in an app below the root', () async {
      final state = await read(
        InMemoryWorkspace({'apps/m/pubspec.yaml': pubspec('2.0.0+9')}),
        ['apps/m/pubspec.yaml'],
      );

      expect(state.pubspecPath, 'apps/m/pubspec.yaml');
      expect(state.pubspec.build, 9);
    });

    test('fails for a file that is missing', () {
      expect(
        read(workspace(), [...files, 'ios/Other/Info.plist']),
        _versionFileError('ios/Other/Info.plist', 'does not exist'),
      );
    });

    test('fails for a file that is neither pubspec nor plist', () {
      expect(
        read(workspace(), [...files, 'README.md']),
        _versionFileError('README.md', 'neither a pubspec.yaml nor a plist'),
      );
    });

    test('needs exactly one pubspec', () {
      expect(
        read(workspace(), ['ios/Runner/Info.plist']),
        _versionFileError('pubspec.yaml', 'exactly one pubspec.yaml, found 0'),
      );
      expect(
        read(workspace(more: {'b/pubspec.yaml': pubspec('1.0.0+1')}), [
          'pubspec.yaml',
          'b/pubspec.yaml',
        ]),
        _versionFileError('pubspec.yaml, b/pubspec.yaml', 'found 2'),
      );
    });

    test('fails for a pubspec without a version line', () {
      expect(
        read(InMemoryWorkspace({'pubspec.yaml': 'name: x\n'}), [
          'pubspec.yaml',
        ]),
        _versionFileError('pubspec.yaml', '0 matches'),
      );
    });

    test('fails for a pubspec with two version lines', () {
      expect(
        read(
          InMemoryWorkspace({
            'pubspec.yaml': 'version: 1.0.0+1\nversion: 1.0.1+2\n',
          }),
          ['pubspec.yaml'],
        ),
        _versionFileError('pubspec.yaml', '2 matches'),
      );
    });

    test('fails for a version that is not x.y.z+build', () {
      expect(
        read(InMemoryWorkspace({'pubspec.yaml': 'version: latest\n'}), [
          'pubspec.yaml',
        ]),
        _versionFileError('pubspec.yaml', 'not a version'),
      );
    });

    test('fails for a plist with no key or with two', () {
      const missing =
          '<plist><dict><key>CFBundleVersion</key>'
          '<string>1</string></dict></plist>';
      final twice = plist('5.4.0', '1').replaceFirst(
        '</dict>',
        '<key>CFBundleVersion</key><string>2</string></dict>',
      );

      expect(
        read(workspace(more: {'ios/Runner/Info.plist': missing})),
        _versionFileError(
          'ios/Runner/Info.plist',
          'CFBundleShortVersionString',
        ),
      );
      expect(
        read(workspace(more: {'ios/Runner/Info.plist': twice})),
        _versionFileError(
          'ios/Runner/Info.plist',
          '2 matches for CFBundleVersion',
        ),
      );
    });
  });

  group('write', () {
    test('writes the version into the pubspec and every plist', () async {
      final space = workspace();

      final changed = await VersionFiles(space)
          .write(files, AppVersion.parse('5.4.1+3283'));

      expect(changed, files);
      expect(space.files['pubspec.yaml'], pubspec('5.4.1+3283'));
      expect(space.files['ios/Runner/Info.plist'], plist('5.4.1', '3283'));
      expect(space.files['ios/Runner/Info-Dev.plist'], plist('5.4.1', '3283'));
    });

    test('keeps everything else in the file as it was', () async {
      final space = workspace(
        more: {'pubspec.yaml': pubspec('5.4.0+3282').replaceAll('\n', '\r\n')},
      );

      await VersionFiles(space).write(files, AppVersion.parse('5.4.1+3283'));

      expect(
        space.files['pubspec.yaml'],
        pubspec('5.4.1+3283').replaceAll('\n', '\r\n'),
      );
      expect(space.files['ios/Runner/Info.plist'], contains('bumped by XPath'));
    });

    test('keeps a comment after the version', () async {
      final space = InMemoryWorkspace({
        'pubspec.yaml': 'version: 1.0.0+1   # keep\n',
      });

      await VersionFiles(space)
          .write(['pubspec.yaml'], AppVersion.parse('1.1.0+2'));

      expect(space.files['pubspec.yaml'], 'version: 1.1.0+2   # keep\n');
    });

    test('leaves a key that follows the build alone', () async {
      final space = workspace(
        more: {
          'ios/Runner/Info.plist': flutterPlist,
          'ios/Runner/Info-Dev.plist': plist(r'$(FLUTTER_BUILD_NAME)', '3282'),
        },
      );

      final changed = await VersionFiles(space)
          .write(files, AppVersion.parse('5.4.1+3283'));

      expect(changed, ['pubspec.yaml', 'ios/Runner/Info-Dev.plist']);
      expect(space.files['ios/Runner/Info.plist'], flutterPlist);
      expect(
        space.files['ios/Runner/Info-Dev.plist'],
        plist(r'$(FLUTTER_BUILD_NAME)', '3283'),
      );
    });

    test('writes nothing when the files already say the version', () async {
      final space = workspace();

      final changed = await VersionFiles(space)
          .write(files, AppVersion.parse('5.4.0+3282'));

      expect(changed, isEmpty);
      expect(space.writes, isEmpty);
    });

    test('writes nothing at all when one file cannot take the version', () {
      final space = workspace(
        more: {'ios/Runner/Info-Dev.plist': '<plist></plist>'},
      );

      expect(
        VersionFiles(space).write(files, AppVersion.parse('5.4.1+3283')),
        _versionFileError('ios/Runner/Info-Dev.plist', 'has 0 matches'),
      );
      expect(space.writes, isEmpty);
    });

    test('needs a build number', () {
      expect(
        VersionFiles(workspace()).write(files, AppVersion.parse('5.4.1')),
        throwsArgumentError,
      );
    });
  });

  group('VersionFilesState', () {
    test('matches only when every version file says the version', () async {
      final state = await read(workspace());

      expect(state.matches(AppVersion.parse('5.4.0+3282')), isTrue);
      expect(state.matches(AppVersion.parse('5.4.1+3282')), isFalse);
      expect(state.matches(AppVersion.parse('5.4.0+3283')), isFalse);
    });

    test('names the plists that disagree with the version', () async {
      final state = await read(
        workspace(more: {'ios/Runner/Info-Dev.plist': plist('5.3.0', '3282')}),
      );

      expect(
        state
            .plistsOutOfSync(AppVersion.parse('5.4.0+3282'))
            .map((plist) => plist.path),
        ['ios/Runner/Info-Dev.plist'],
      );
    });

    test('compares a plist build with a pubspec that has none', () async {
      final state = await read(workspace(version: '5.4.0'));

      expect(state.plistsOutOfSync(state.pubspec), hasLength(2));
    });

    test('does not compare keys that follow the build', () async {
      final state = await read(
        workspace(
          more: {
            'ios/Runner/Info.plist': flutterPlist,
            'ios/Runner/Info-Dev.plist': flutterPlist,
          },
        ),
      );

      expect(state.matches(AppVersion.parse('5.4.0+3282')), isTrue);
    });
  });
}

Matcher _versionFileError(String path, String message) => throwsA(
  isA<VersionFileException>()
      .having((e) => e.path, 'path', path)
      .having((e) => e.message, 'message', contains(message)),
);
