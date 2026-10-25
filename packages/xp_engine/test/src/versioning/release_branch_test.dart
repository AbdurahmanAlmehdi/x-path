import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/stub_git.dart';

void main() {
  const mirror = GitMirror(key: '1', path: '/m.git');
  const sha = 'a';
  const later = 'b';
  final version = VersionName.parse('5.4.1');
  late StubGit git;
  late ReleaseBranchCutter cutter;

  setUp(() {
    git = StubGit();
    cutter = ReleaseBranchCutter(git);
  });

  test('creates release/<x.y.z> at the dispatched commit', () async {
    final cut = await cutter.cut(mirror, version: version, sha: sha);

    expect(cut.name, 'release/5.4.1');
    expect(cut.outcome, BranchOutcome.created);
    expect(git.branches, {'release/5.4.1': sha});
  });

  test('uses the branch name of the release model', () async {
    final cut = await cutter.cut(
      mirror,
      version: version,
      sha: sha,
      model: const ReleaseModel(branchPattern: 'rel/{app}/{version}'),
      scope: const TagScope(app: 'mobile'),
    );

    expect(cut.name, 'rel/mobile/5.4.1');
  });

  test('reuses a branch that already is on the commit', () async {
    await cutter.cut(mirror, version: version, sha: sha);

    final cut = await cutter.cut(mirror, version: version, sha: sha);

    expect(cut.outcome, BranchOutcome.unchanged);
  });

  test('moves a branch forward to a commit that descends from it', () async {
    await cutter.cut(mirror, version: version, sha: sha);
    git.descendants.add(later);

    final cut = await cutter.cut(mirror, version: version, sha: later);

    expect(cut.outcome, BranchOutcome.updated);
    expect(git.branches['release/5.4.1'], later);
  });

  test('refuses to move a branch sideways and leaves it', () async {
    await cutter.cut(mirror, version: version, sha: sha);

    await expectLater(
      cutter.cut(mirror, version: version, sha: later),
      throwsA(isA<GitBranchConflictException>()),
    );
    expect(git.branches['release/5.4.1'], sha);
  });
}
