import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('sourceKey', () {
    String key(String text) => GitRemote.parse(text)!.sourceKey;

    test('is the same for every spelling of one repository', () {
      final keys = {
        key('git@bitbucket.org:ws/app.git'),
        key('ssh://git@Bitbucket.org:22/ws/app/'),
      };

      expect(keys, hasLength(1));
      expect(keys.single, matches(GitMirror.keyPattern));
    });

    test('differs for another repository, host or port', () {
      final app = key('git@bitbucket.org:ws/app.git');
      expect(key('git@bitbucket.org:ws/other.git'), isNot(app));
      expect(key('git@gitlab.com:ws/app.git'), isNot(app));
      expect(key('ssh://git@bitbucket.org:2222/ws/app.git'), isNot(app));
      expect(key('file:///ws/app.git'), isNot(app));
    });

    test('is h and 16 hex digits of the SHA-256 of the normalised remote', () {
      // printf 'ssh://bitbucket.org/ws/app' | shasum -a 256
      expect(key('git@bitbucket.org:ws/app.git'), 'h212353d06bc50c7b');
    });
  });
}
