import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';
import '../../../helpers/fake_snapshot_reader.dart';

const _define = 'apps/mobile/env/prod.json';

void main() {
  late BuildHarness harness;
  late InMemoryWorkspace workspace;
  late FakeSnapshotReader snapshots;
  late VerifyCompiledConfigStep step;
  late BuildContext context;

  VerifyCompiledConfigInput input({
    String artifactName = 'prod-1.2.3+45.aab',
    List<String> keys = const ['API_BASE_URL'],
    List<String> needles = const [],
    String? dartDefineFile = 'env/prod.json',
  }) => VerifyCompiledConfigInput(
    worktree: buildWorktree,
    artifactName: artifactName,
    dartDefineFile: dartDefineFile,
    keys: keys,
    needles: needles,
  );

  Future<void> store(
    String name,
    ArtifactKind kind, [
    List<int> bytes = const [1, 2, 3],
  ]) => harness.recorder.record(
    jobId: 'job_1',
    kind: kind,
    name: name,
    content: Stream.value(bytes),
  );

  List<int> bytes(String text) => latin1.encode(text);

  setUp(() async {
    harness = BuildHarness();
    workspace = InMemoryWorkspace({
      _define: jsonEncode({'API_BASE_URL': 'https://api.example.com/v2/'}),
    });
    snapshots = FakeSnapshotReader([
      bytes('\x00\x01 junk https://api.exa'),
      bytes('mple.com/v2 more junk'),
    ]);
    step = VerifyCompiledConfigStep(
      workspaces: (_) => workspace,
      repository: harness.artifacts,
      store: harness.store,
      snapshots: snapshots,
    );
    context = BuildContext();
    await store('prod-1.2.3+45.aab', ArtifactKind.aab);
  });

  group('the step', () {
    test('is build.verifyCompiledConfig and has no side effect', () {
      expect(step.kind, 'build.verifyCompiledConfig');
      expect(step.sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      expect(step.decodeInput(step.encodeInput(input())), input());
      expect(
        step.decodeInput(
          step.encodeInput(
            input(keys: const [], needles: ['a.b'], dartDefineFile: null),
          ),
        ),
        input(keys: const [], needles: ['a.b'], dartDefineFile: null),
      );
    });

    test('refuses input that is not valid', () {
      final json = step.encodeInput(input());
      for (final bad in <Map<String, dynamic>>[
        {...json, 'keys': <String>[]},
        {
          ...json,
          'needles': [''],
        },
        {...json}..remove('dartDefineFile'),
        {...json}..remove('artifactName'),
        {...json, 'keys': 'API_BASE_URL'},
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });

    test('has something to look for', () {
      expect(
        () => VerifyCompiledConfigInput(
          worktree: buildWorktree,
          artifactName: 'x.aab',
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => VerifyCompiledConfigInput(
          worktree: buildWorktree,
          artifactName: 'x.aab',
          keys: const ['A'],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('encodes its result', () {
      final found = ['a'];
      final result = VerifyCompiledConfigResult(
        artifactName: 'x.aab',
        found: found,
      );

      expect(step.encodeResult(result), {
        'artifactName': 'x.aab',
        'found': ['a'],
      });
      expect(
        result,
        const VerifyCompiledConfigResult(artifactName: 'x.aab', found: ['a']),
      );
    });
  });

  group('with a dart_defines credential', () {
    VerifyCompiledConfigInput secretInput({
      List<String> keys = const ['API_BASE_URL'],
    }) => VerifyCompiledConfigInput(
      worktree: buildWorktree,
      artifactName: 'prod-1.2.3+45.aab',
      dartDefineSecret: 'defines',
      keys: keys,
    );

    setUp(() {
      context.defines['defines'] = jsonEncode({
        'API_BASE_URL': 'https://api.secret.example/v2',
      });
    });

    test('stores its input', () {
      expect(step.decodeInput(step.encodeInput(secretInput())), secretInput());
    });

    test('finds the value and names only its key', () async {
      snapshots.snapshot = [bytes('x api.secret.example y')];

      final outcome = await step.run(secretInput(), context);

      expect(
        (outcome as StepSucceeded<VerifyCompiledConfigResult>).result.found,
        ['API_BASE_URL'],
      );
    });

    test('names only the key of a value that is missing', () async {
      snapshots.snapshot = [bytes('nothing here')];

      final outcome = await step.run(secretInput(), context);

      final message = (outcome as StepFailed).message;
      expect(message, contains('API_BASE_URL is NOT compiled'));
      expect(message, isNot(contains('secret.example')));
    });

    test('says which key the credential lacks', () async {
      final outcome = await step.run(
        secretInput(keys: const ['NOPE']),
        context,
      );

      expect(
        (outcome as StepFailed).message,
        'The dart_defines credential has no value for NOPE.',
      );
    });
  });

  group('run', () {
    test('passes when the host is in the compiled code', () async {
      final outcome = await step.run(input(), context);

      final result =
          (outcome as StepSucceeded<VerifyCompiledConfigResult>).result;
      expect(result.found, ['api.example.com']);
      expect(snapshots.asked.single.$1, ArtifactKind.aab);
      expect(snapshots.asked.single.$2, [1, 2, 3]);
      expect(context.commands, isEmpty);
    });

    test('fails with a clear message on a compiled-config miss', () async {
      snapshots.snapshot = [bytes('https://staging.example.com/ only')];

      final outcome = await step.run(input(), context);

      final message = (outcome as StepFailed).message;
      expect(message, startsWith('api.example.com is NOT compiled into '));
      expect(message, contains('prod-1.2.3+45.aab'));
      expect(message, contains('dropped its --dart-define values'));
      expect(message, contains('Fix: run flutter clean'));
    });

    test('names every missing value', () async {
      final outcome = await step.run(
        input(needles: const ['com.example.app', 'flavor-prod']),
        context,
      );

      expect(
        (outcome as StepFailed).message,
        startsWith('com.example.app, flavor-prod are NOT compiled into'),
      );
    });

    test('looks for literal needles and keys together', () async {
      snapshots.snapshot = [bytes('api.example.com and flavor-prod')];

      final outcome = await step.run(
        input(needles: const ['flavor-prod']),
        context,
      );

      expect(
        (outcome as StepSucceeded<VerifyCompiledConfigResult>).result.found,
        ['flavor-prod', 'api.example.com'],
      );
    });

    test('reads a .env define file', () async {
      workspace.files[_define] =
          '# env\nAPI_BASE_URL="https://api.example.com"\n';

      final outcome = await step.run(input(), context);

      expect(outcome, isA<StepSucceeded<VerifyCompiledConfigResult>>());
    });

    test('skips a package without a snapshot', () async {
      snapshots.snapshot = null;

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepSkipped).reason,
        'No AOT snapshot in prod-1.2.3+45.aab, so the config check is skipped.',
      );
    });

    test('checks an IPA the same way', () async {
      await store('prod-1.2.3+45.ipa', ArtifactKind.ipa);

      await step.run(input(artifactName: 'prod-1.2.3+45.ipa'), context);

      expect(snapshots.asked.single.$1, ArtifactKind.ipa);
    });

    test('fails for a package this job never stored', () async {
      final outcome = await step.run(input(artifactName: 'other.aab'), context);

      expect(
        (outcome as StepFailed).message,
        startsWith('This job has no stored other.aab'),
      );
    });

    test('fails when the stored file left the store', () async {
      harness.store.files.clear();

      final outcome = await step.run(input(), context);

      expect(outcome, isA<StepFailed>());
    });

    test('fails for a file that is not a package', () async {
      await store('manifest.json', ArtifactKind.manifest);

      final outcome = await step.run(
        input(artifactName: 'manifest.json'),
        context,
      );

      expect(
        (outcome as StepFailed).message,
        'manifest.json is not an APK, AAB or IPA.',
      );
    });

    test('fails when the define file is missing or has no value', () async {
      workspace.files.remove(_define);
      final missing = await step.run(input(), context);
      workspace.files[_define] = '{"OTHER": "x"}';
      final empty = await step.run(input(), context);
      workspace.files[_define] = '{"API_BASE_URL": [1]}';
      final malformed = await step.run(input(), context);

      expect(
        (missing as StepFailed).message,
        'apps/mobile/env/prod.json does not exist.',
      );
      expect(
        (empty as StepFailed).message,
        'apps/mobile/env/prod.json has no value for API_BASE_URL.',
      );
      expect(
        (malformed as StepFailed).message,
        'The define file must hold a flat object.',
      );
    });
  });
}
