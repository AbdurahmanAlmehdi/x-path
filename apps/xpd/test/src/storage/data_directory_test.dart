import 'package:test/test.dart';
import 'package:xpd/xpd.dart';

void main() {
  group('resolveDataDirectory', () {
    test('prefers the option over everything', () {
      expect(
        resolveDataDirectory(
          option: '/opt',
          environment: {dataDirectoryEnvironmentKey: '/env', 'HOME': '/h'},
          operatingSystem: 'macos',
        ),
        '/opt',
      );
    });

    test('then the environment variable', () {
      expect(
        resolveDataDirectory(
          option: '',
          environment: {dataDirectoryEnvironmentKey: '/env', 'HOME': '/h'},
          operatingSystem: 'linux',
        ),
        '/env',
      );
    });

    test('uses Application Support on macOS, ignoring XDG_DATA_HOME', () {
      expect(
        resolveDataDirectory(
          environment: {'HOME': '/Users/me', 'XDG_DATA_HOME': '/x'},
          operatingSystem: 'macos',
        ),
        '/Users/me/Library/Application Support/XPath',
      );
    });

    test('uses XDG_DATA_HOME on Linux', () {
      expect(
        resolveDataDirectory(
          environment: {'HOME': '/home/me', 'XDG_DATA_HOME': '/data'},
          operatingSystem: 'linux',
        ),
        '/data/xpath',
      );
    });

    test('falls back to ~/.local/share/xpath on Linux', () {
      for (final xdg in [null, '']) {
        expect(
          resolveDataDirectory(
            environment: {'HOME': '/home/me', 'XDG_DATA_HOME': ?xdg},
            operatingSystem: 'linux',
          ),
          '/home/me/.local/share/xpath',
        );
      }
    });

    test('says what to do when there is no home', () {
      expect(
        () => resolveDataDirectory(environment: {}, operatingSystem: 'linux'),
        throwsA(
          isA<DataDirectoryException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('--data-dir'), contains('XPATH_DATA_DIR')),
          ),
        ),
      );
    });
  });
}
