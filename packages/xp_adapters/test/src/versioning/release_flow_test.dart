@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/git_fixture.dart';
import '../../helpers/memory_secret_store.dart';

/// The guard and version steps over real git and a real directory: a fixture
/// repository shaped like the Mataa customer app.
class _NoProcessContext implements StepContext {
  @override
  String get jobId => 'job_1';

  @override
  int get ordinal => 0;

  @override
  bool get isStopping => false;

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) => throw StateError('no process expected');
}

String _plist(String version, String build) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>$version</string>
	<key>CFBundleVersion</key>
	<string>$build</string>
</dict>
</plist>
''';

void main() {
  late GitFixture fixture;
  late Directory dataDir;
  late CliGitService git;
  late GitMirror mirror;
  late String sha;
  late GitWorktree worktree;
  late GuardStep guard;
  late VersionBumpStep bump;
  final context = _NoProcessContext();
  const versionFiles = ['pubspec.yaml', 'ios/Runner/Info.plist'];

  ReleaseWorktree target(String atSha) => ReleaseWorktree(
    path: worktree.path,
    mirror: mirror,
    sha: atSha,
    versionFiles: versionFiles,
  );

  Future<StepOutcome<GuardReport>> runGuard(
    List<GuardCheckName> checks, {
    String? releaseVersion,
  }) => guard.run(
    GuardInput(
      checks: checks,
      worktree: target(sha),
      releaseVersion: releaseVersion,
    ),
    context,
  );

  setUp(() async {
    fixture = GitFixture.create();
    dataDir = Directory.systemTemp.createTempSync('xp_flow_data_');
    fixture
      ..commit('pubspec.yaml', 'name: app\nversion: 5.4.0+3282\n')
      ..commit('ios/Runner/Info.plist', _plist('5.4.0', '3282'))
      ..commit('lib/main.dart', 'void main() {}');
    sha = fixture.commit('android/app/build.gradle.kts', 'android {}');
    fixture.push('main');
    git = CliGitService(
      runner: const IoProcessRunner(),
      secrets: MemorySecretStore(),
      dataDir: dataDir.path,
    );
    mirror = await git.ensureMirror(key: '42', remoteUrl: fixture.originUrl);
    await git.fetch(mirror);
    worktree = await git.createWorktree(mirror, name: 'job_1', sha: sha);
    guard = GuardStep(
      checks: const [
        SourceCheck(),
        VersionSyncCheck(),
        NewReleaseNumberCheck(),
        PatchNativeDiffCheck(),
      ],
      git: git,
      workspaces: DirectoryWorkspace.new,
    );
    bump = VersionBumpStep(git: git, workspaces: DirectoryWorkspace.new);
  });

  tearDown(() {
    fixture.dispose();
    dataDir.deleteSync(recursive: true);
  });

  test('a clean checkout passes the source and version guards', () async {
    final outcome = await runGuard([
      GuardCheckName.source,
      GuardCheckName.versionSync,
      GuardCheckName.newReleaseNumber,
    ]);

    expect(outcome, isA<StepSucceeded<GuardReport>>());
  });

  test(
    'the source guard sees an untracked file in lib/ (real incident)',
    () async {
      File(p.join(worktree.path, 'lib/debug_flags.dart'))
          .writeAsStringSync('const forceProd = true;');

      final outcome = await runGuard([GuardCheckName.source]);

      expect(
        (outcome as StepFailed).message,
        contains('Untracked file: lib/debug_flags.dart'),
      );
    },
  );

  test(
    'the source guard sees pubspec_overrides.yaml (real incident)',
    () async {
      File(p.join(worktree.path, 'pubspec_overrides.yaml')).writeAsStringSync(
        'dependency_overrides:\n  mataa_core:\n    path: ../mataa_core\n',
      );

      final outcome = await runGuard([GuardCheckName.source]);

      expect(
        (outcome as StepFailed).message,
        contains('pubspec_overrides.yaml is active'),
      );
    },
  );

  test(
    'version.bump commits the version files, which the guards accept',
    () async {
      final input = VersionBumpInput(
        worktree: target(sha),
        version: AppVersion.parse('5.4.1+3283'),
      );

      final outcome = await bump.run(input, context);

      final result = (outcome as StepSucceeded<VersionBumpResult>).result;
      expect(result.created, isTrue);
      expect(result.previous, AppVersion.parse('5.4.0+3282'));
      expect(
        File(p.join(worktree.path, 'pubspec.yaml')).readAsStringSync(),
        'name: app\nversion: 5.4.1+3283\n',
      );
      expect(
        File(p.join(worktree.path, 'ios/Runner/Info.plist')).readAsStringSync(),
        _plist('5.4.1', '3283'),
      );
      expect(
        fixture.git([
          'log',
          '-1',
          '--format=%s',
          result.commit,
        ], cwd: mirror.path),
        'chore(release): 5.4.1+3283',
      );
      // The worktree head is the version commit now; guards run on it.
      final after = await guard.run(
        GuardInput(
          checks: const [
            GuardCheckName.source,
            GuardCheckName.versionSync,
            GuardCheckName.newReleaseNumber,
          ],
          worktree: target(result.commit),
        ),
        context,
      );
      expect(after, isA<StepSucceeded<GuardReport>>());
    },
  );

  test('version.bump is done once the head has the version', () async {
    final input = VersionBumpInput(
      worktree: target(sha),
      version: AppVersion.parse('5.4.1+3283'),
    );
    expect(await bump.alreadyDone(input, context), isNull);
    final first = await bump.run(input, context);

    final done = await bump.alreadyDone(input, context);

    expect(
      done?.commit,
      (first as StepSucceeded<VersionBumpResult>).result.commit,
    );
    final again = await bump.run(input, context);
    expect((again as StepSucceeded<VersionBumpResult>).result.created, isFalse);
    expect(
      fixture.git(['rev-list', '--count', 'HEAD'], cwd: worktree.path),
      '5',
    );
  });

  test('a release branch is cut at the version commit and reused', () async {
    final input = VersionBumpInput(
      worktree: target(sha),
      version: AppVersion.parse('5.4.1+3283'),
    );
    final bumped = (await bump.run(
      input,
      context,
    ) as StepSucceeded<VersionBumpResult>).result;
    final cutter = ReleaseBranchCutter(git);
    final version = VersionName.parse('5.4.1');

    final first = await cutter.cut(
      mirror,
      version: version,
      sha: bumped.commit,
    );
    final again = await cutter.cut(
      mirror,
      version: version,
      sha: bumped.commit,
    );

    expect(first.name, 'release/5.4.1');
    expect(first.outcome, BranchOutcome.created);
    expect(again.outcome, BranchOutcome.unchanged);
    await git.push(mirror, refspecs: [GitRefspecs.branch(first.name)]);
    expect(fixture.originRef('refs/heads/release/5.4.1'), bumped.commit);
  });

  test('the native diff guard compares with the release tag', () async {
    fixture
      ..git(['tag', '-a', '-m', 'r', 'v5.4.0+3282', sha])
      ..commit('lib/fix.dart', 'fix');
    final dartOnly = fixture.git(['rev-parse', 'HEAD']);
    fixture
      ..push('main')
      ..git(['push', '--quiet', 'origin', 'v5.4.0+3282']);
    final native = fixture.commit(
      'ios/Runner/Info.plist',
      _plist('5.4.0', '1'),
    );
    fixture.push('main');
    await git.fetch(mirror);

    Future<StepOutcome<GuardReport>> patch(String at) => guard.run(
      GuardInput(
        checks: const [GuardCheckName.patchNativeDiff],
        worktree: target(at),
        releaseVersion: '5.4.0+3282',
      ),
      context,
    );

    expect(await patch(dartOnly), isA<StepSucceeded<GuardReport>>());
    expect(
      (await patch(native) as StepFailed).message,
      contains('ios/Runner/Info.plist'),
    );
  });
}
