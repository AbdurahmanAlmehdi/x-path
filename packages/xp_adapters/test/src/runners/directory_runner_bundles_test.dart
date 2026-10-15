import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/schema_dump.dart';

void main() {
  late Directory first;
  late Directory second;
  late DirectoryRunnerBundles bundles;
  final linux = RunnerBundleTarget.parse('linux', 'arm64');

  File put(Directory root, String folder, List<int> bytes) =>
      File(p.join(root.path, folder, runnerBundleFileName))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  setUp(() {
    first = tempDirectory();
    second = tempDirectory();
    bundles = DirectoryRunnerBundles([first.path, second.path]);
  });

  Future<List<int>> read(RunnerBundle bundle) =>
      bundle.open().expand((chunk) => chunk).toList();

  test('finds the bundle of the target with its size and digest', () async {
    put(first, 'linux-arm64', [1, 2, 3, 4]);

    final bundle = await bundles.find(linux);

    expect(bundle.size, 4);
    expect(bundle.sha256, sha256.convert([1, 2, 3, 4]).toString());
    expect(await read(bundle), [1, 2, 3, 4]);
  });

  test('tries the roots in order and takes the first that has one', () async {
    put(second, 'linux-arm64', [9]);
    expect(await read(await bundles.find(linux)), [9]);

    put(first, 'linux-arm64', [1]);
    expect(await read(await bundles.find(linux)), [1]);
  });

  test('does not mix up targets', () async {
    put(first, 'macos-arm64', [7]);

    expect(bundles.find(linux), throwsA(isA<RunnerBundleMissingException>()));
  });

  test('says where the bundle goes when there is none', () {
    expect(
      bundles.find(linux),
      throwsA(
        isA<RunnerBundleMissingException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('linux-arm64'),
            contains(p.join(first.path, 'linux-arm64', 'xp.tar.gz')),
            contains(p.join(second.path, 'linux-arm64', 'xp.tar.gz')),
          ),
        ),
      ),
    );
  });

  test('keeps the digest until the file changes', () async {
    final file = put(first, 'linux-arm64', [1, 2, 3]);
    final before = await bundles.find(linux);
    final again = await bundles.find(linux);
    expect(again.sha256, before.sha256);

    file
      ..writeAsBytesSync([4, 5, 6, 7])
      ..setLastModifiedSync(DateTime.utc(2030));
    final after = await bundles.find(linux);

    expect(after.size, 4);
    expect(after.sha256, sha256.convert([4, 5, 6, 7]).toString());
  });
}
