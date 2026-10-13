import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/guard_harness.dart';
import '../../helpers/step_context.dart';
import '../../helpers/stub_git.dart';
import '../../helpers/version_fixtures.dart';

const headSha = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

void main() {
  final context = NoProcessContext();
  const files = [
    'pubspec.yaml',
    'ios/Runner/Info.plist',
    'ios/Runner/Info-Dev.plist',
  ];
  final newVersion = AppVersion.parse('5.4.1+3283');
  late StubGit git;
  late InMemoryWorkspace workspace;
  late VersionBumpStep step;
  late VersionBumpInput input;

  setUp(() {
    git = StubGit();
    workspace = InMemoryWorkspace(customerApp('5.4.0+3282'));
    step = VersionBumpStep(git: git, workspaces: (_) => workspace);
    input = VersionBumpInput(
      worktree: const ReleaseWorktree(
        path: '/work/job_1',
        mirror: mirror,
        sha: dispatchedSha,
        versionFiles: files,
      ),
      version: newVersion,
    );
  });

  group('the step', () {
    test('is version.bump and has a side effect: the commit', () {
      expect(step.kind, 'version.bump');
      expect(step.sideEffectOf(input), isTrue);
    });

    test('stores its input and result as JSON', () {
      expect(step.decodeInput(step.encodeInput(input)), input);
      expect(step.encodeInput(input)['version'], '5.4.1+3283');
      expect(
        step.encodeResult(
          VersionBumpResult(
            commit: 'c' * 40,
            created: true,
            previous: AppVersion.parse('5.4.0+3282'),
          ),
        ),
        {'commit': 'c' * 40, 'created': true, 'previous': '5.4.0+3282'},
      );
      expect(
        step.encodeResult(VersionBumpResult(commit: 'c' * 40, created: false)),
        {'commit': 'c' * 40, 'created': false},
      );
    });

    test('rejects input that is not valid', () {
      final json = step.encodeInput(input);
      for (final bad in <Map<String, dynamic>>[
        {...json, 'version': '5.4.1'},
        {...json, 'version': 'latest'},
        {...json}..remove('version'),
        {...json}..remove('worktree'),
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });
  });

  group('run', () {
    test('writes the version and commits the version files', () async {
      final outcome = await step.run(input, context);

      final result = (outcome as StepSucceeded<VersionBumpResult>).result;
      expect(result.commit, 'c' * 40);
      expect(result.created, isTrue);
      expect(result.previous, AppVersion.parse('5.4.0+3282'));
      expect(workspace.files['pubspec.yaml'], pubspec('5.4.1+3283'));
      expect(workspace.files['ios/Runner/Info.plist'], plist('5.4.1', '3283'));
      expect(git.calls, [
        'listTags',
        'commit chore(release): 5.4.1+3283 ${files.join(',')}',
      ]);
    });

    test(
      'has nothing to commit when the head already has the version',
      () async {
        workspace = InMemoryWorkspace(customerApp('5.4.1+3283'));
        git.commitResult = GitCommitResult(
          sha: 'd' * 40,
          tree: 't' * 40,
          created: false,
        );

        final outcome = await step.run(input, context);

        final result = (outcome as StepSucceeded<VersionBumpResult>).result;
        expect(result.commit, 'd' * 40);
        expect(result.created, isFalse);
        expect(result.previous, isNull);
        expect(workspace.writes, isEmpty);
      },
    );

    test('refuses a version that is tagged already', () async {
      git.tags.add(tag('v5.4.1+3283', otherSha));

      final outcome = await step.run(input, context);

      expect((outcome as StepFailed).message, 'v5.4.1+3283 is already tagged.');
      expect(workspace.writes, isEmpty);
      expect(git.calls, ['listTags']);
    });

    test('looks for the tag the release model names', () async {
      git.tags.add(tag('v5.4.1+3283'));
      final custom = VersionBumpInput(
        worktree: const ReleaseWorktree(
          path: '/work/job_1',
          mirror: mirror,
          sha: dispatchedSha,
          versionFiles: files,
          releaseModel: ReleaseModel(tagPattern: '{app}/v{version}+{build}'),
          scope: TagScope(app: 'mobile'),
        ),
        version: newVersion,
      );

      expect(await step.run(custom, context), isA<StepSucceeded<Object?>>());
    });

    test(
      'fails, writing nothing, when a version file cannot take it',
      () async {
        workspace = InMemoryWorkspace({
          ...customerApp('5.4.0+3282'),
          'ios/Runner/Info-Dev.plist': '<plist></plist>',
        });

        final outcome = await step.run(input, context);

        expect(
          (outcome as StepFailed).message,
          startsWith('ios/Runner/Info-Dev.plist: has 0 matches'),
        );
        expect(workspace.writes, isEmpty);
        expect(git.calls, ['listTags']);
      },
    );
  });

  group('alreadyDone', () {
    setUp(() => workspace = InMemoryWorkspace(customerApp('5.4.1+3283')));

    test('is the head commit when it already holds the version', () async {
      git.statusResult = const GitWorktreeStatus(headSha: headSha);

      final done = await step.alreadyDone(input, context);

      expect(done?.commit, headSha);
      expect(done?.created, isFalse);
    });

    test('is not done while the files have another version', () async {
      workspace = InMemoryWorkspace(customerApp('5.4.0+3282'));

      expect(await step.alreadyDone(input, context), isNull);
      expect(git.calls, isEmpty);
    });

    test('is not done while one plist lags behind', () async {
      workspace.files['ios/Runner/Info-Dev.plist'] = plist('5.4.0', '3282');

      expect(await step.alreadyDone(input, context), isNull);
    });

    test('is not done while the edit is not committed yet', () async {
      git.statusResult = const GitWorktreeStatus(
        headSha: headSha,
        changed: ['pubspec.yaml'],
      );

      expect(await step.alreadyDone(input, context), isNull);
    });

    test('is done despite changes to other files', () async {
      git.statusResult = const GitWorktreeStatus(
        headSha: headSha,
        changed: ['lib/main.dart'],
        untracked: ['notes.txt'],
      );

      expect(await step.alreadyDone(input, context), isNotNull);
    });

    test('is not done when the version files cannot be read', () async {
      workspace = InMemoryWorkspace({});

      expect(await step.alreadyDone(input, context), isNull);
    });
  });
}
