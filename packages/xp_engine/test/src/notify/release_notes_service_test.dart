import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/notify_harness.dart';
import '../../helpers/stub_git.dart';
import '../../helpers/workflow_fixtures.dart';

void main() {
  late StubGit git;
  late InMemoryProjectRepository projects;
  late InMemoryReleaseRepository releases;
  late ReleaseNotesService service;

  const head = 'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1';

  ReleaseNotesService build({
    ReleaseModelRepository? models,
    int firstReleaseLimit = 100,
  }) => ReleaseNotesService(
    releases: releases,
    projects: projects,
    models: models ?? InMemoryReleaseModelRepository(['prj_1']),
    git: git,
    firstReleaseLimit: firstReleaseLimit,
  );

  setUp(() async {
    git = StubGit();
    projects = InMemoryProjectRepository();
    releases = InMemoryReleaseRepository();
    await projects.add(demoProject());
    await releases.create(releaseRecord(headSha: head));
    service = build();
  });

  GitTagInfo tag(String name) => GitTagInfo(name: name, commit: 'c' * 40);

  test('lists the commits since the release before, newest tag wins', () async {
    git
      ..tags.addAll([
        tag('v1.0.0+10'),
        tag('v1.1.0+38'),
        tag('v1.1.0+40'),
        tag('v1.1.0+40-p1'),
        tag('v1.2.0+4'),
        tag('v2.0.0+1'),
        tag('not-a-release'),
      ])
      ..commits = const [
        GitCommit(sha: 'd1', subject: 'feat(ui): add dark mode'),
        GitCommit(sha: 'd2', subject: 'fix: spinner'),
      ];

    final notes = await service.forRelease('rel_1');

    expect(git.calls, contains('commitsBetween v1.1.0+40 $head 500'));
    expect(notes.from, 'v1.1.0+40');
    expect(notes.to, head);
    expect(notes.commits, 2);
    expect(notes.groups.map((g) => g.type), ['feat', 'fix']);
    expect(
      notes.compareUrl,
      'https://github.com/octo/demo/compare/v1.1.0%2B40...$head',
    );
    expect(notes.releaseId, 'rel_1');
    expect(notes.version, '1.2.0');
    expect(notes.build, 5);
    expect(notes.slack, startsWith('*octo/demo prod 1.2.0 (5)*\n'));
  });

  test('a first release lists its latest commits with no link', () async {
    git.commits = const [GitCommit(sha: 'd1', subject: 'feat: first')];
    service = build(firstReleaseLimit: 7);

    final notes = await service.forRelease('rel_1');

    expect(git.calls, contains('commitsBetween null $head 7'));
    expect(notes.from, isNull);
    expect(notes.compareUrl, isNull);
  });

  test('ignores tags of other flavors when the pattern has one', () async {
    git
      ..tags.addAll([tag('v1.0.0+10-dev'), tag('v1.1.0+30-prod')])
      ..commits = const [];
    service = build(
      models: _Models(
        const ReleaseModel(tagPattern: 'v{version}+{build}-{flavor}'),
      ),
    );

    final notes = await service.forRelease('rel_1');

    expect(notes.from, 'v1.1.0+30-prod');
  });

  test('reads the tag of an app by name when the pattern has one', () async {
    git
      ..tags.addAll([tag('other-1.0.0+10'), tag('demo-1.1.0+30')])
      ..commits = const [];
    service = build(
      models: _Models(
        const ReleaseModel(tagPattern: '{app}-{version}+{build}'),
      ),
    );

    final notes = await service.forRelease('rel_1');

    expect(notes.from, 'demo-1.1.0+30');
  });

  test('an app without flavors has the tags of no flavor', () async {
    final bare = releaseRecord(id: 'rel_2', flavor: '', headSha: head);
    await releases.create(bare);
    git
      ..tags.add(tag('v1.1.0+30'))
      ..commits = const [];

    final notes = await service.forRelease('rel_2');

    expect(notes.from, 'v1.1.0+30');
    expect(notes.slack, startsWith('*octo/demo 1.2.0 (5)*'));
  });

  test('a release known only by its tag ends at the tag', () async {
    await releases.create(releaseRecord(id: 'rel_3', tag: 'v1.2.0+5'));
    git.commits = const [];

    final notes = await service.forRelease('rel_3');

    expect(notes.to, 'a' * 40);
  });

  test('an app the profile does not list is read without its name', () async {
    projects = InMemoryProjectRepository();
    await projects.add(
      demoProject(
        apps: const [AppProfile(name: 'other', path: 'apps/other')],
      ),
    );
    git
      ..tags.add(tag('v1.1.0+30'))
      ..commits = const [];
    service = build();

    expect((await service.forRelease('rel_1')).from, 'v1.1.0+30');
  });

  test('a release with no commit yet has no notes', () async {
    await releases.create(releaseRecord(id: 'rel_4'));

    await expectLater(
      service.forRelease('rel_4'),
      throwsA(isA<ReleaseStateException>()),
    );
  });

  test('an unknown release or project is not found', () async {
    await expectLater(
      service.forRelease('rel_gone'),
      throwsA(isA<ReleaseNotFoundException>()),
    );
    await releases.create(
      releaseRecord(id: 'rel_5', projectId: 'prj_gone', headSha: head),
    );
    await expectLater(
      service.forRelease('rel_5'),
      throwsA(isA<ProjectNotFoundException>()),
    );
  });
}

class _Models implements ReleaseModelRepository {
  new(this.model);

  final ReleaseModel model;

  @override
  Future<ReleaseModel> get(String projectId) async => model;

  @override
  Future<void> save(String projectId, ReleaseModel model) async {}
}
