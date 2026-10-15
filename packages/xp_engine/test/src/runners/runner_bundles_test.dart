import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('RunnerBundleTarget', () {
    test('reads the os and the architecture of a runner', () {
      final target = RunnerBundleTarget.parse('linux', 'arm64');

      expect(target.os, 'linux');
      expect(target.arch, 'arm64');
      expect(target.folderName, 'linux-arm64');
      expect('$target', 'linux-arm64');
      expect(target, RunnerBundleTarget.parse('linux', 'arm64'));
    });

    test('asks for both', () {
      for (final (os, arch) in [
        (null, 'arm64'),
        ('linux', null),
        (null, null),
      ]) {
        expect(
          () => RunnerBundleTarget.parse(os, arch),
          throwsA(
            isA<RunnerInvalidException>().having(
              (error) => error.message,
              'message',
              contains('os and the arch'),
            ),
          ),
        );
      }
    });

    test('is a plain word, never a path', () {
      for (final bad in ['', '../etc', 'a/b', 'Linux', 'mac os', 'x' * 33]) {
        expect(
          () => RunnerBundleTarget.parse(bad, 'arm64'),
          throwsA(isA<RunnerInvalidException>()),
          reason: bad,
        );
        expect(
          () => RunnerBundleTarget.parse('linux', bad),
          throwsA(isA<RunnerInvalidException>()),
          reason: bad,
        );
      }
    });
  });

  group('InMemoryRunnerBundles', () {
    test('serves the bytes with their digest and size', () async {
      final bundles = InMemoryRunnerBundles()..files['macos-arm64'] = [1, 2, 3];

      final bundle = await bundles.find(
        RunnerBundleTarget.parse('macos', 'arm64'),
      );

      expect(bundle.size, 3);
      expect(bundle.sha256, sha256.convert([1, 2, 3]).toString());
      expect(await bundle.open().expand((chunk) => chunk).toList(), [1, 2, 3]);
    });

    test('has none for a target nobody put there', () {
      expect(
        InMemoryRunnerBundles().find(
          RunnerBundleTarget.parse('linux', 'x86_64'),
        ),
        throwsA(
          isA<RunnerBundleMissingException>().having(
            (error) => '$error',
            'text',
            contains('linux-x86_64'),
          ),
        ),
      );
    });
  });
}
