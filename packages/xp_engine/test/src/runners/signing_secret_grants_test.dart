import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryCredentialRepository credentials;
  late SigningSecretGrants grants;

  CredentialRecord record(
    String id,
    CredentialKind kind,
    String secretKey, {
    String project = 'prj_1',
  }) => CredentialRecord(
    id: id,
    flavor: CredentialFlavor(
      id: 'flv_$id',
      projectId: project,
      appPath: '.',
      name: id,
    ),
    kind: kind,
    secretKey: secretKey,
  );

  StepRecord step(Map<String, dynamic> input) => StepRecord(
    jobId: 'job_1',
    ordinal: 0,
    kind: 'build.android',
    sideEffect: false,
    input: input,
  );

  setUp(() async {
    credentials = InMemoryCredentialRepository();
    grants = SigningSecretGrants(credentials);
    await credentials.save(record('a', CredentialKind.keystore, 'ks-a'));
    await credentials.save(
      record('b', CredentialKind.keystore, 'ks-b', project: 'prj_2'),
    );
    await credentials.save(record('c', CredentialKind.ascKey, 'asc'));
    await credentials.save(record('d', CredentialKind.shorebird, 'shorebird'));
  });

  test('grants the keystore and its passwords that the steps name', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretFiles': {'XPATH_KEYSTORE_FILE': 'ks-a'},
        'secretEnvironment': {
          'STORE': 'ks-a.storePassword',
          'KEY': 'ks-a.keyPassword',
        },
      }),
    ]);

    expect(granted, {'ks-a', 'ks-a.storePassword', 'ks-a.keyPassword'});
  });

  test('grants only what is named', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretEnvironment': {'STORE': 'ks-a.storePassword'},
      }),
    ]);

    expect(granted, {'ks-a.storePassword'});
  });

  test('never grants a secret that is not signing material', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretFiles': {'F': 'asc'},
        'secretEnvironment': {'T': 'shorebird', 'G': 'github', 'U': 'unknown'},
        'tokenSecret': 'shorebird',
      }),
    ]);

    expect(granted, isEmpty);
  });

  test('never grants the keystore of another project', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretFiles': {'F': 'ks-b'},
      }),
    ]);

    expect(granted, isEmpty);
  });

  test('reads what is not a map or not text as naming nothing', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretFiles': 'ks-a',
        'secretEnvironment': {'N': 3},
      }),
      step({}),
    ]);

    expect(granted, isEmpty);
  });

  test('asks no one when the steps name nothing', () async {
    expect(await grants.forSteps('prj_1', const []), isEmpty);
  });
}
