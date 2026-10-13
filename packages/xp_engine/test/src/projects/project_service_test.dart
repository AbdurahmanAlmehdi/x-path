import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/fakes.dart';
import '../../helpers/repo_builder.dart';

const _repo = GitHubRepo(
  id: 42,
  fullName: 'octo/app',
  defaultBranch: 'main',
  cloneUrl: 'https://github.com/octo/app.git',
);

Matcher _invalid(String message) => throwsA(
  isA<ProjectInvalidException>().having(
    (e) => e.message,
    'message',
    contains(message),
  ),
);

/// A scanner that fails.
class _FailingScanner implements ProjectScanner {
  const new();

  @override
  Future<ScanResult> scan(ScanSource source) async =>
      throw StateError('scan failed');
}

void main() {
  late InMemoryProjectRepository repository;
  late FakeGitHubClient github;
  late FakeGitService git;
  late FakeProcessRunner runner;
  late InMemoryEventLog events;
  late ManualClock clock;
  late Map<String, Map<String, String>> folders;
  late ProjectService service;

  /// The `origin` that `git remote get-url` prints, or `null` for none.
  String? origin;

  /// Sources: the folders by path, and a plain app in every worktree.
  ScanSource source(String directory) => InMemoryScanSource(
    directory.startsWith('/worktrees/') ? app() : folders[directory] ?? {},
  );

  ProjectService serviceWith({
    ProjectScanner scanner = const ProjectScanner(),
    Duration gitTimeout = const Duration(seconds: 30),
  }) => ProjectService(
    repository: repository,
    github: github,
    git: git,
    scanner: scanner,
    sources: source,
    runner: runner,
    events: events,
    clock: clock,
    random: Random(1),
    gitTimeout: gitTimeout,
  );

  setUp(() {
    origin = 'git@github.com:octo/app.git';
    repository = InMemoryProjectRepository();
    github = FakeGitHubClient({42: _repo});
    git = FakeGitService();
    runner = FakeProcessRunner(
      (call) => origin == null
          ? const ProcessOutput(exitCode: 2, stderr: 'no such remote')
          : ProcessOutput(exitCode: 0, stdout: '$origin\n'),
    );
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    events = InMemoryEventLog(clock: clock);
    folders = {'/work/app': app()};
    service = serviceWith();
  });

  Future<List<EngineEvent>> eventsSoFar() async => [
    for (final logged
        in await events.subscribe(after: 0).take(events.head).toList())
      logged.event,
  ];

  const byPath = AddProjectRequest(path: '/work/app');
  const worktreeCalls = ['ensureMirror 42', 'fetch 42', 'resolveRef main'];

  group('add by path', () {
    test(
      'identifies the repository from origin and scans the folder',
      () async {
        final project = await service.add(byPath);

        expect(project.id, matches(RegExp(r'^prj_[0-9a-f]{16}$')));
        expect(project.githubRepoId, 42);
        expect(project.fullName, 'octo/app');
        expect(project.remote, 'https://github.com/octo/app.git');
        expect(project.localPath, '/work/app');
        expect(project.defaultBaseBranch, 'main');
        expect(project.profile.apps.single.name, 'demo');
        expect(project.profile.branches.defaultBranch, 'main');
        expect(project.scannedAt, clock.now());
        expect(github.lookups, ['octo/app']);
        expect(runner.calls.single.executable, 'git');
        expect(runner.calls.single.arguments, [
          '-C',
          '/work/app',
          'remote',
          'get-url',
          'origin',
        ]);
        expect(
          runner.calls.single.environment,
          containsPair('GIT_OPTIONAL_LOCKS', '0'),
        );
        expect(await service.get(project.id), project);
        expect(await service.list(), [project]);
      },
    );

    test('sets up the mirror but does not fetch for a folder scan', () async {
      await service.add(byPath);

      expect(git.calls, ['ensureMirror 42']);
      expect(git.remotes[42], 'https://github.com/octo/app.git');
    });

    test('announces the project and the scan', () async {
      folders['/work/app'] = app(overrides: {'.fvmrc': null});

      final project = await service.add(byPath);

      expect(await eventsSoFar(), [
        ProjectAdded(projectId: project.id, fullName: 'octo/app'),
        ProjectScanned(projectId: project.id, errors: 0, warnings: 1),
      ]);
    });

    test('follows a repository that GitHub knows under another name', () async {
      origin = 'https://github.com/old/name.git';
      github.aliases['old/name'] = 42;

      final project = await service.add(byPath);

      expect(project.fullName, 'octo/app');
      expect(project.remote, 'https://github.com/octo/app.git');
      expect(git.remotes[42], 'https://github.com/octo/app.git');
    });

    test('refuses a relative path and a missing folder', () async {
      await expectLater(
        service.add(const AddProjectRequest(path: 'work/app')),
        _invalid('not an absolute path'),
      );
      await expectLater(
        service.add(const AddProjectRequest(path: '/nowhere')),
        _invalid('not a folder'),
      );
    });

    test('refuses a folder without an origin', () async {
      for (final none in [null, '']) {
        origin = none;

        await expectLater(
          service.add(byPath),
          _invalid('no git remote called origin'),
        );
      }
    });

    test('refuses an origin that is not on GitHub', () async {
      origin = 'https://gitlab.com/octo/app.git';

      await expectLater(service.add(byPath), _invalid('not on GitHub'));
      expect(github.lookups, isEmpty);
    });

    test('refuses when git cannot run', () async {
      runner.startError = const ProcessStartException('git', 'not found');

      await expectLater(service.add(byPath), _invalid('Cannot run git'));
    });

    test('refuses when git does not answer in time', () async {
      runner.handler = (call) => Completer<ProcessOutput>().future;
      service = serviceWith(gitTimeout: const Duration(milliseconds: 10));

      await expectLater(service.add(byPath), _invalid('did not answer'));
      expect(runner.calls.single.killed, isTrue);
    });

    test('refuses a repository that is a project already', () async {
      final first = await service.add(byPath);

      await expectLater(
        service.add(const AddProjectRequest(remote: 'octo/app')),
        throwsA(
          isA<ProjectExistsException>().having(
            (e) => e.existingId,
            'existingId',
            first.id,
          ),
        ),
      );
      expect(await service.list(), hasLength(1));
    });

    test('lets a GitHub failure through and adds nothing', () async {
      github.failure = const GitHubAuthException('Bad credentials');

      await expectLater(
        service.add(byPath),
        throwsA(isA<GitHubAuthException>()),
      );
      expect(await service.list(), isEmpty);
      expect(git.calls, isEmpty);
    });
  });

  group('add by remote', () {
    test('scans a worktree of the mirror and removes it', () async {
      final project = await service.add(
        const AddProjectRequest(remote: 'https://github.com/octo/app.git'),
      );

      expect(project.localPath, isNull);
      expect(project.profile.apps.single.name, 'demo');
      expect(project.profile.branches.defaultBranch, 'main');
      expect(git.calls, [
        ...worktreeCalls,
        'createWorktree scan-${project.id}',
        'removeWorktree /worktrees/scan-${project.id}',
      ]);
      expect(runner.calls, isEmpty);
    });

    test('adds nothing when the mirror cannot be fetched', () async {
      git.fetchFailure = const GitException('network down');

      await expectLater(
        service.add(const AddProjectRequest(remote: 'octo/app')),
        throwsA(isA<GitException>()),
      );
      expect(await service.list(), isEmpty);
      expect(
        git.calls.any((call) => call.startsWith('createWorktree')),
        isFalse,
      );
    });

    test('removes the worktree when the scan fails', () async {
      service = serviceWith(scanner: const _FailingScanner());

      await expectLater(
        service.add(const AddProjectRequest(remote: 'octo/app')),
        throwsA(isA<StateError>()),
      );
      expect(git.calls.last, startsWith('removeWorktree'));
      expect(await service.list(), isEmpty);
    });

    test('refuses a remote that is not a GitHub repository', () async {
      await expectLater(
        service.add(const AddProjectRequest(remote: 'https://example.com/x')),
        _invalid('not a GitHub repository'),
      );
    });

    test('reports a repository GitHub does not know', () async {
      await expectLater(
        service.add(const AddProjectRequest(remote: 'octo/missing')),
        throwsA(isA<GitHubNotFoundException>()),
      );
    });
  });

  test('add needs exactly one of path and remote', () async {
    for (final request in const [
      AddProjectRequest(),
      AddProjectRequest(path: '/work/app', remote: 'octo/app'),
    ]) {
      await expectLater(service.add(request), _invalid('exactly one'));
    }
  });

  test('get says when there is no such project', () async {
    expect(await service.list(), isEmpty);
    await expectLater(
      service.get('prj_nope'),
      throwsA(isA<ProjectNotFoundException>()),
    );
  });

  group('scan', () {
    late Project project;

    setUp(() async {
      project = await service.add(byPath);
      git.calls.clear();
      clock.advance(const Duration(hours: 1));
    });

    test('scans the folder again and keeps the edits', () async {
      await service.update(
        project.id,
        const ProfileEdits(
          defaultBaseBranch: 'dev',
          apps: [AppEdit(path: '.', storeCountry: 'ly')],
        ),
      );
      folders['/work/app'] = app(overrides: {'.fvmrc': null});

      final scanned = await service.scan(project.id);

      expect(scanned.findings.map((f) => f.code), contains('fvmrc_missing'));
      expect(scanned.scannedAt, clock.now());
      expect(scanned.defaultBaseBranch, 'dev');
      expect(scanned.profile.apps.single.storeCountry, 'ly');
      expect(git.calls, ['ensureMirror 42']);
      expect(
        (await eventsSoFar()).last,
        ProjectScanned(projectId: project.id, errors: 0, warnings: 1),
      );
    });

    test('follows a rename and a new default branch of GitHub', () async {
      github.repos[42] = const GitHubRepo(
        id: 42,
        fullName: 'octo/renamed',
        defaultBranch: 'develop',
        cloneUrl: 'https://github.com/octo/renamed.git',
      );

      final scanned = await service.scan(project.id);

      expect(scanned.fullName, 'octo/renamed');
      expect(scanned.remote, 'https://github.com/octo/renamed.git');
      expect(scanned.defaultBaseBranch, 'develop');
      expect(scanned.profile.branches.defaultBranch, 'develop');
      expect(git.remotes[42], 'https://github.com/octo/renamed.git');
    });

    test(
      'keeps what is stored when GitHub or the secrets are unreachable',
      () async {
        for (final failure in <Exception>[
          const GitHubForbiddenException('rate limited', rateLimited: true),
          const SecretsLockedException('locked'),
        ]) {
          github.failure = failure;

          final scanned = await service.scan(project.id);

          expect(scanned.fullName, 'octo/app', reason: '$failure');
          expect(scanned.defaultBaseBranch, 'main');
        }
      },
    );

    test('scans the mirror when the folder is gone', () async {
      folders.remove('/work/app');

      final scanned = await service.scan(project.id);

      expect(scanned.profile.apps.single.name, 'demo');
      expect(git.calls, [
        ...worktreeCalls,
        'createWorktree scan-${project.id}',
        'removeWorktree /worktrees/scan-${project.id}',
      ]);
    });

    test('says when there is no such project', () async {
      await expectLater(
        service.scan('prj_nope'),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });

    test('leaves the stored project alone when the scan fails', () async {
      folders.remove('/work/app');
      git.fetchFailure = const GitException('network down');
      final before = await service.get(project.id);

      await expectLater(service.scan(project.id), throwsA(isA<GitException>()));

      expect(await service.get(project.id), before);
    });
  });

  group('update', () {
    late Project project;

    setUp(() async {
      folders['/work/app'] = app(
        overrides: {
          'android/app/build.gradle': gradle(
            flavors: 'productFlavors { dev { applicationId "com.dev" } }',
          ),
        },
      );
      project = await service.add(byPath);
    });

    test('edits the profile and returns the project', () async {
      final updated = await service.update(
        project.id,
        const ProfileEdits(
          apps: [
            AppEdit(
              path: '.',
              storeCountry: 'LY',
              flavors: [FlavorEdit(name: 'dev', prod: true)],
            ),
          ],
        ),
      );

      expect(updated.profile.apps.single.storeCountry, 'ly');
      expect(updated.profile.apps.single.flavors.single.prod, isTrue);
      expect(await service.get(project.id), updated);
    });

    test('merges successive edits', () async {
      await service.update(
        project.id,
        const ProfileEdits(
          apps: [AppEdit(path: '.', storeCountry: 'ly')],
        ),
      );
      final updated = await service.update(
        project.id,
        const ProfileEdits(
          defaultBaseBranch: 'dev',
          apps: [
            AppEdit(
              path: '.',
              flavors: [FlavorEdit(name: 'dev', shorebird: true)],
            ),
          ],
        ),
      );

      expect(updated.defaultBaseBranch, 'dev');
      expect(updated.profile.apps.single.storeCountry, 'ly');
      expect(updated.profile.apps.single.flavors.single.shorebird, isTrue);
    });

    test('refuses an edit of something that is not there', () async {
      await expectLater(
        service.update(
          project.id,
          const ProfileEdits(apps: [AppEdit(path: 'apps/nope')]),
        ),
        throwsA(isA<ProjectInvalidException>()),
      );
      expect(await service.get(project.id), project);
    });

    test('says when there is no such project', () async {
      await expectLater(
        service.update('prj_nope', const ProfileEdits()),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });
  });

  group('remove', () {
    test('deletes the project and announces it', () async {
      final project = await service.add(byPath);

      await service.remove(project.id);

      expect(await service.list(), isEmpty);
      expect((await eventsSoFar()).last, ProjectRemoved(projectId: project.id));
      expect(git.calls, ['ensureMirror 42']);
    });

    test('says when there is no such project', () async {
      await expectLater(
        service.remove('prj_nope'),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });
  });

  test('operations that change projects run one at a time', () async {
    final gate = Completer<void>();
    git.gate = gate.future;

    final first = service.add(byPath);
    final second = service.add(const AddProjectRequest(remote: 'octo/app'));
    await Future<void>.delayed(Duration.zero);
    gate.complete();

    await first;
    await expectLater(second, throwsA(isA<ProjectExistsException>()));
    expect(await service.list(), hasLength(1));
  });

  test('a failed operation does not block the next one', () async {
    await expectLater(
      service.add(const AddProjectRequest()),
      throwsA(isA<ProjectInvalidException>()),
    );

    expect(await service.add(byPath), isA<Project>());
  });

  test('project ids are random unless a test says otherwise', () async {
    final unseeded = ProjectService(
      repository: repository,
      github: github,
      git: git,
      scanner: const ProjectScanner(),
      sources: source,
      runner: runner,
      events: events,
      clock: clock,
    );

    final project = await unseeded.add(byPath);

    expect(project.id, matches(RegExp(r'^prj_[0-9a-f]{16}$')));
  });

  test('exceptions have readable messages', () {
    expect(const ProjectException('x').toString(), contains('x'));
    expect(const ProjectNotFoundException('p').toString(), contains('p'));
    expect(const ProjectNotFoundException('p').id, 'p');
    expect(
      const ProjectExistsException('p', 'o/r').toString(),
      contains('o/r is project p'),
    );
    expect(const ProjectInvalidException('y').toString(), contains('y'));
    expect(const ProjectInUseException('p').toString(), contains('p'));
    expect(const ProjectInUseException('p').id, 'p');
  });
}
