import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/memory_secret_store.dart';

void main() {
  late Directory directory;
  late RunnerPaths paths;
  late MemorySecretStore secrets;
  late RunnerEnrollments enrollments;

  final enrollment = RunnerEnrollment(
    identity: RunnerIdentity(
      engine: Uri.parse('https://xpath.example.com'),
      runnerId: 'rnr_1',
      name: 'mac-mini',
    ),
    credential: 'xpr_credential',
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_identity_');
    addTearDown(() => directory.deleteSync(recursive: true));
    paths = RunnerPaths('${directory.path}/runner');
    secrets = MemorySecretStore();
    enrollments = RunnerEnrollments(paths, secrets);
  });

  test('is not paired before it was written', () async {
    expect(await enrollments.read(), isNull);
  });

  test(
    'keeps the identity in a file and the credential in the secret store',
    () async {
      await enrollments.write(enrollment);

      final file = File(paths.identityFile).readAsStringSync();
      expect(jsonDecode(file), {
        'engine': 'https://xpath.example.com',
        'runnerId': 'rnr_1',
        'name': 'mac-mini',
      });
      expect(file, isNot(contains('xpr_credential')));
      expect(secrets.values.keys, ['runner.rnr_1.credential']);
      expect(File('${paths.identityFile}.tmp').existsSync(), isFalse);
    },
  );

  test('reads back what it wrote', () async {
    await enrollments.write(enrollment);

    final read = (await enrollments.read())!;

    expect(read.identity.engine, Uri.parse('https://xpath.example.com'));
    expect(read.identity.runnerId, 'rnr_1');
    expect(read.identity.name, 'mac-mini');
    expect(read.credential, 'xpr_credential');
  });

  test('is not paired when the credential is missing', () async {
    await enrollments.write(enrollment);
    secrets.values.clear();

    expect(await enrollments.read(), isNull);
  });

  test('pairs again over an earlier pairing', () async {
    await enrollments.write(enrollment);
    await enrollments.write(
      RunnerEnrollment(
        identity: RunnerIdentity(
          engine: Uri.parse('http://other:7480'),
          runnerId: 'rnr_2',
          name: 'linux',
        ),
        credential: 'xpr_two',
      ),
    );

    expect((await enrollments.read())!.credential, 'xpr_two');
  });

  test('refuses an identity file that is not what it should be', () async {
    Directory(paths.root).createSync(recursive: true);
    for (final content in ['[]', '{"engine": "x"}', '{"engine": 1}']) {
      File(paths.identityFile).writeAsStringSync(content);

      await expectLater(
        enrollments.read(),
        throwsA(isA<FormatException>()),
        reason: content,
      );
    }
    File(paths.identityFile).writeAsStringSync('not json');
    await expectLater(enrollments.read(), throwsA(isA<FormatException>()));
  });

  test('passes on a secret store that cannot be read', () async {
    await enrollments.write(enrollment);
    secrets.failure = const SecretStoreException('locked');

    await expectLater(enrollments.read(), throwsA(isA<SecretStoreException>()));
  });
}
