import 'package:test/test.dart';
import 'package:xp_engine/src/scan/ios_files.dart';

void main() {
  group('plistString', () {
    const plist = r'''
<dict>
	<key>CFBundleShortVersionString</key>
	<string>5.5.0</string>
	<key>CFBundleVersion</key>
	<string>  $(FLUTTER_BUILD_NUMBER) </string>
	<key>UIRequiresFullScreen</key>
	<true/>
</dict>
''';

    test('reads a string value as written, trimmed', () {
      expect(plistString(plist, 'CFBundleShortVersionString'), '5.5.0');
      expect(plistString(plist, 'CFBundleVersion'), r'$(FLUTTER_BUILD_NUMBER)');
    });

    test('is null for a missing key or a value that is not a string', () {
      expect(plistString(plist, 'CFBundleName'), isNull);
      expect(plistString(plist, 'UIRequiresFullScreen'), isNull);
    });
  });

  group('isBuildVariable', () {
    test('accepts parenthesis and brace forms', () {
      expect(isBuildVariable(r'$(FLUTTER_BUILD_NAME)'), isTrue);
      expect(isBuildVariable(r'${MARKETING_VERSION}'), isTrue);
    });

    test('rejects literals and mixtures', () {
      expect(isBuildVariable('5.5.0'), isFalse);
      expect(isBuildVariable(r'5.$(BUILD)'), isFalse);
      expect(isBuildVariable(''), isFalse);
    });
  });

  group('schemeArchiveConfiguration', () {
    test('reads the archive configuration across lines', () {
      const scheme = '''
<Scheme>
   <LaunchAction
      buildConfiguration = "Debug-dev">
   </LaunchAction>
   <ArchiveAction
      buildConfiguration = "Release-dev"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''';

      expect(schemeArchiveConfiguration(scheme), 'Release-dev');
    });

    test('is null when the scheme has no archive action', () {
      expect(schemeArchiveConfiguration('<Scheme></Scheme>'), isNull);
    });
  });

  group('editDistance', () {
    test('counts insertions, deletions and substitutions', () {
      expect(editDistance('com.mataa.captain', 'com.mataaa.captain'), 1);
      expect(editDistance('abc', 'abd'), 1);
      expect(editDistance('abc', 'ab'), 1);
      expect(editDistance('kitten', 'sitting'), 3);
    });

    test('is zero for equal strings and the length for empty ones', () {
      expect(editDistance('same', 'same'), 0);
      expect(editDistance('', 'abc'), 3);
      expect(editDistance('abc', ''), 3);
    });
  });
}
