import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryCredentialRepository credentials;
  late RunnerSecretGrants grants;

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
    grants = RunnerSecretGrants(credentials);
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

  test('grants the Shorebird key that a step names as its token', () async {
    final granted = await grants.forSteps('prj_1', [
      step({'tokenSecret': 'shorebird'}),
    ]);

    expect(granted, {'shorebird'});
  });

  test('grants the Shorebird key a step names in its environment', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretEnvironment': {'SHOREBIRD_TOKEN': 'shorebird'},
      }),
    ]);

    expect(granted, {'shorebird'});
  });

  test(
    'grants the Shorebird key and the keystore of one job together',
    () async {
      final granted = await grants.forSteps('prj_1', [
        step({
          'secretFiles': {'XPATH_KEYSTORE_FILE': 'ks-a'},
          'tokenSecret': 'shorebird',
        }),
      ]);

      expect(granted, {'ks-a', 'shorebird'});
    },
  );

  test('never grants the Shorebird key unless a step names it', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretFiles': {'XPATH_KEYSTORE_FILE': 'ks-a'},
      }),
    ]);

    expect(granted, {'ks-a'});
  });

  test('never grants the Shorebird key of another project', () async {
    await credentials.save(
      record('e', CredentialKind.shorebird, 'shorebird-2', project: 'prj_2'),
    );

    final granted = await grants.forSteps('prj_1', [
      step({'tokenSecret': 'shorebird-2'}),
    ]);

    expect(granted, isEmpty);
  });

  test('never grants a secret that may not travel to a runner', () async {
    final granted = await grants.forSteps('prj_1', [
      step({
        'secretFiles': {'F': 'asc'},
        'secretEnvironment': {'G': 'github', 'U': 'unknown'},
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
        'tokenSecret': 3,
      }),
      step({}),
    ]);

    expect(granted, isEmpty);
  });

  test('asks no one when the steps name nothing', () async {
    expect(await grants.forSteps('prj_1', const []), isEmpty);
  });
}
