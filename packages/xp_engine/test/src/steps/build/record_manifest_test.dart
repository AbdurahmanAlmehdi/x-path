import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';
import '../../../helpers/step_context.dart';
import '../../../helpers/stub_git.dart';

final String _head = 'e' * 40;

void main() {
  late BuildHarness harness;
  late StubGit git;
  late InMemoryWorkspace workspace;
  late RecordManifestStep step;

  RecordManifestInput input({String? dartDefineFile = '.env.dev'}) =>
      RecordManifestInput(
        worktree: buildWorktree,
        version: AppVersion.parse('1.2.3+45'),
        flavors: const ['dev'],
        dartDefineFile: dartDefineFile,
      );

  Future<Map<String, dynamic>> run([RecordManifestInput? given]) async {
    final outcome = await step.run(given ?? input(), NoProcessContext());
    expect(outcome, isA<StepSucceeded<RecordManifestResult>>());
    final text = utf8.decode(harness.store.files['job_1/manifest.json']!);
    return jsonDecode(text) as Map<String, dynamic>;
  }

  setUp(() async {
    harness = BuildHarness();
    await harness.createJob();
    await harness.jobs.saveTools(
      'job_1',
      const JobTools(flutter: '3.47.6', dart: '3.13.5', gh: '2.96.0'),
    );
    git = StubGit()..statusResult = GitWorktreeStatus(headSha: _head);
    workspace = InMemoryWorkspace({
      'apps/mobile/pubspec.lock': 'lock\n',
      'apps/mobile/.env.dev': 'API=https://dev.example\n',
    });
    step = RecordManifestStep(
      git: git,
      workspaces: (_) => workspace,
      artifacts: harness.artifacts,
      recorder: harness.recorder,
      jobs: harness.jobs,
      clock: harness.clock,
    );
    await harness.recorder.record(
      jobId: 'job_1',
      kind: ArtifactKind.apk,
      name: 'dev-1.2.3+45.apk',
      content: Stream.value(utf8.encode('apk')),
    );
  });

  group('the step', () {
    test('is record.manifest and has no side effect', () {
      expect(step.kind, 'record.manifest');
      expect(step.sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      expect(step.decodeInput(step.encodeInput(input())), input());
      expect(
        step
            .encodeInput(input(dartDefineFile: null))
            .containsKey('dartDefineFile'),
        isFalse,
      );
    });

    test('refuses input that is not valid', () {
      final json = step.encodeInput(input());
      for (final bad in <Map<String, dynamic>>[
        {...json, 'version': '1.2.3'},
        {...json}..remove('version'),
        {...json}..remove('worktree'),
        {...json, 'flavors': 'dev'},
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });
  });

  group('the manifest of a build with a dart_defines credential', () {
    test('records the hash of the file and nothing of it', () async {
      const text = 'API_KEY=secret-value\n';
      final inputOf = RecordManifestInput(
        worktree: buildWorktree,
        version: AppVersion.parse('1.2.3+45'),
        dartDefineSecret: 'defines',
      );
      expect(step.decodeInput(step.encodeInput(inputOf)), inputOf);

      await step.run(inputOf, BuildContext()..defines['defines'] = text);

      final bytes = harness.store.files['job_1/manifest.json']!;
      final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(manifest['inputs'], {
        'dartDefineFileSha256': sha256OfBytes(utf8.encode(text)),
      });
      expect(utf8.decode(bytes), isNot(contains('secret-value')));
    });
  });

  group('the manifest', () {
    test('says what was built', () async {
      final manifest = await run();

      expect(manifest, {
        'schema': 1,
        'jobId': 'job_1',
        'app': 'apps/mobile',
        'version': '1.2.3',
        'build': 45,
        'tag': 'v1.2.3+45',
        'flavors': ['dev'],
        'git': {'sha': _head, 'dispatchedSha': buildSha, 'dirty': false},
        'deps': {'pubspecLockSha256': sha256OfBytes(utf8.encode('lock\n'))},
        'toolchain': {'flutter': '3.47.6', 'dart': '3.13.5', 'gh': '2.96.0'},
        'inputs': {
          'dartDefineFile': '.env.dev',
          'dartDefineFileSha256': sha256OfBytes(
            utf8.encode('API=https://dev.example\n'),
          ),
        },
        'artifacts': [
          {
            'kind': 'apk',
            'file': 'dev-1.2.3+45.apk',
            'bytes': 3,
            'sha256': sha256OfBytes(utf8.encode('apk')),
          },
        ],
        'startedAt': '2026-10-13T09:30:00.000Z',
        'finishedAt': '2026-10-13T10:00:00.000Z',
      });
    });

    test('is stored as an artifact of kind manifest', () async {
      final outcome = await step.run(input(), NoProcessContext());

      final summary =
          (outcome as StepSucceeded<RecordManifestResult>).result.artifact;
      expect(summary.kind, ArtifactKind.manifest);
      expect(summary.name, 'manifest.json');
      expect((await harness.artifacts.get(summary.id))!.sha256, summary.sha256);
      expect(step.encodeResult(RecordManifestResult(summary)), {
        'artifact': summary.toJson(),
      });
    });

    test('compares by value', () async {
      final outcome = await step.run(input(), NoProcessContext());
      final result = (outcome as StepSucceeded<RecordManifestResult>).result;

      expect(RecordManifestResult(result.artifact), result);
    });

    test('does not list itself and is replaced when it runs again', () async {
      await run();
      harness.clock.advance(const Duration(minutes: 5));
      final manifest = await run();

      expect(manifest['artifacts'], hasLength(1));
      expect(manifest['finishedAt'], '2026-10-13T10:05:00.000Z');
      final stored = await harness.artifacts.forJob('job_1');
      expect(
        stored.where((a) => a.kind == ArtifactKind.manifest),
        hasLength(1),
      );
    });

    test('says when the worktree is dirty', () async {
      git.statusResult = GitWorktreeStatus(
        headSha: _head,
        changed: const ['pubspec.yaml'],
      );

      expect((await run())['git'], containsPair('dirty', true));
    });

    test('names the tag the release model prescribes', () async {
      final scoped = RecordManifestInput(
        worktree: const ReleaseWorktree(
          path: '/work/job_1',
          mirror: GitMirror(key: '42', path: '/mirrors/42.git'),
          sha: buildSha,
          appPath: 'apps/mobile',
          releaseModel: ReleaseModel(
            tagPattern: '{app}/{flavor}/v{version}+{build}',
          ),
          scope: TagScope(app: 'mobile', flavor: 'dev'),
        ),
        version: AppVersion.parse('1.2.3+45'),
      );

      expect((await run(scoped))['tag'], 'mobile/dev/v1.2.3+45');
    });

    test('leaves out what the job does not have', () async {
      workspace.files.clear();
      await harness.jobs.updateJob(
        JobRecord(
          id: 'job_1',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.running,
          createdAt: harness.clock.now(),
        ),
      );
      final manifest = await run(input(dartDefineFile: null));

      expect(manifest['deps'], {'pubspecLockSha256': null});
      expect(manifest['inputs'], isEmpty);
      expect(manifest['startedAt'], isNull);
    });

    test('has no tool versions before any build recorded them', () async {
      final fresh = BuildHarness();
      await fresh.jobs.create(
        JobRecord(
          id: 'job_1',
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.running,
          createdAt: fresh.clock.now(),
        ),
        const [],
      );
      harness = fresh;
      step = RecordManifestStep(
        git: git,
        workspaces: (_) => workspace,
        artifacts: fresh.artifacts,
        recorder: fresh.recorder,
        jobs: fresh.jobs,
        clock: fresh.clock,
      );

      final manifest = await run();

      expect(manifest['toolchain'], isEmpty);
      expect(manifest['artifacts'], isEmpty);
    });

    test('works even when the job is not stored', () async {
      final empty = BuildHarness();
      harness = empty;
      step = RecordManifestStep(
        git: git,
        workspaces: (_) => workspace,
        artifacts: empty.artifacts,
        recorder: empty.recorder,
        jobs: empty.jobs,
        clock: empty.clock,
      );

      expect((await run())['startedAt'], isNull);
    });
  });
}
