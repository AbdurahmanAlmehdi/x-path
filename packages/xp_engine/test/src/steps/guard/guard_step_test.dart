import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/guard_harness.dart';
import '../../../helpers/step_context.dart';
import '../../../helpers/stub_git.dart';

class _Check extends GuardCheck {
  const new(this.name, this.status, [this.fix]);

  @override
  final GuardCheckName name;
  final GuardStatus status;
  final String? fix;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async =>
      GuardCheckResult(name, status, '${name.name} says $status', fix: fix);
}

void main() {
  final context = NoProcessContext();
  late StubGit git;
  late List<String> opened;
  late InMemoryWorkspace workspace;

  GuardStep step(Iterable<GuardCheck> checks) => GuardStep(
    checks: checks,
    git: git,
    workspaces: (path) {
      opened.add(path);
      return workspace;
    },
  );

  GuardInput input(List<GuardCheckName> checks) => guardRequest(
    checks: checks,
    releaseVersion: '5.4.1+3283',
    shorebirdAppId: 'sb-1',
  ).request.input;

  setUp(() {
    git = StubGit();
    opened = [];
    workspace = InMemoryWorkspace(customerApp('5.4.1+3283'));
  });

  test('is the guard step, without side effects', () {
    final guard = step([]);

    expect(guard.kind, 'guard');
    expect(guard.sideEffectOf(input([])), isFalse);
  });

  test('stores its input and result as JSON', () {
    final guard = step([]);
    final full = input([GuardCheckName.source, GuardCheckName.patchTarget]);

    expect(guard.decodeInput(guard.encodeInput(full)), full);
    expect(guard.encodeInput(full)['checks'], ['source', 'patchTarget']);
    expect(
      guard.encodeResult(
        const GuardReport([
          GuardCheckResult(GuardCheckName.source, GuardStatus.passed, 'ok'),
          GuardCheckResult(
            GuardCheckName.versionSync,
            GuardStatus.failed,
            'bad',
            fix: 'fix it',
          ),
        ]),
      ),
      {
        'results': [
          {'name': 'source', 'status': 'passed', 'message': 'ok'},
          {
            'name': 'versionSync',
            'status': 'failed',
            'message': 'bad',
            'fix': 'fix it',
          },
        ],
      },
    );
  });

  test('refuses a check that does not exist', () {
    final guard = step([]);
    final json = guard.encodeInput(input([]))..['checks'] = ['everything'];

    expect(
      () => guard.decodeInput(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '"everything" is not a guard check.',
        ),
      ),
    );
  });

  test('runs the requested checks in order on the job worktree', () async {
    final guard = step(const [
      _Check(GuardCheckName.versionSync, GuardStatus.passed),
      _Check(GuardCheckName.source, GuardStatus.warned),
      _Check(GuardCheckName.appStoreTrain, GuardStatus.skipped),
    ]);

    final outcome = await guard.run(
      input([
        GuardCheckName.source,
        GuardCheckName.appStoreTrain,
        GuardCheckName.versionSync,
      ]),
      context,
    );

    final report = (outcome as StepSucceeded<GuardReport>).result;
    expect(report.results.map((r) => r.name), [
      GuardCheckName.source,
      GuardCheckName.appStoreTrain,
      GuardCheckName.versionSync,
    ]);
    expect(report.results.map((r) => r.status), [
      GuardStatus.warned,
      GuardStatus.skipped,
      GuardStatus.passed,
    ]);
    expect(opened, ['/work/job_1']);
  });

  test('fails with every failed check and its fix', () async {
    final guard = step(const [
      _Check(GuardCheckName.source, GuardStatus.failed, 'Commit it.'),
      _Check(GuardCheckName.versionSync, GuardStatus.passed),
      _Check(GuardCheckName.patchTarget, GuardStatus.failed),
    ]);

    final outcome = await guard.run(
      input([
        GuardCheckName.source,
        GuardCheckName.versionSync,
        GuardCheckName.patchTarget,
      ]),
      context,
    );

    expect(
      (outcome as StepFailed).message,
      'source: source says GuardStatus.failed\nFix: Commit it.\n\n'
      'patchTarget: patchTarget says GuardStatus.failed',
    );
  });

  test('fails for a check the engine cannot run', () async {
    final outcome = await step([])
        .run(input([GuardCheckName.appStoreTrain]), context);

    expect(
      (outcome as StepFailed).message,
      'appStoreTrain: This engine cannot run the appStoreTrain check yet.',
    );
  });

  test('succeeds with an empty report when no check is asked for', () async {
    final outcome = await step([]).run(input([]), context);

    expect((outcome as StepSucceeded<GuardReport>).result.results, isEmpty);
  });

  test('refuses two checks of the same name', () {
    expect(
      () => step(const [
        _Check(GuardCheckName.source, GuardStatus.passed),
        _Check(GuardCheckName.source, GuardStatus.failed),
      ]),
      throwsArgumentError,
    );
  });

  test('runs the real checks end to end', () async {
    final guard = step(const [
      SourceCheck(),
      VersionSyncCheck(),
      NewReleaseNumberCheck(),
    ]);
    git.tags.add(tag('v5.4.1+3283', otherSha));

    final outcome = await guard.run(
      input([
        GuardCheckName.source,
        GuardCheckName.versionSync,
        GuardCheckName.newReleaseNumber,
      ]),
      context,
    );

    expect(
      (outcome as StepFailed).message,
      startsWith('newReleaseNumber: v5.4.1+3283 already exists'),
    );
  });
}
