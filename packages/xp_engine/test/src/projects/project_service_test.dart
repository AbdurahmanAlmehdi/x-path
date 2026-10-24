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
      expect(git.remotes['42'], 'https://github.com/octo/app.git');
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
      expect(git.remotes['42'], 'https://github.com/octo/app.git');
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

    test('refuses a remote XPath cannot reach', () async {
      await expectLater(
        service.add(const AddProjectRequest(remote: 'svn://example.com/x')),
        _invalid('"svn://example.com/x" is not a repository XPath can reach'),
      );
    });

    test('reports a repository GitHub does not know', () async {
      await expectLater(
        service.add(const AddProjectRequest(remote: 'octo/missing')),
        throwsA(isA<GitHubNotFoundException>()),
      );
    });
  });

  group('add from another git host (ADR 0015)', () {
    String keyOf(String url) => GitRemote.parse(url)!.sourceKey;

    Matcher gitFailure(Object message) => throwsA(
      isA<GitException>().having((e) => e.message, 'message', message),
    );

    test('adds a folder with an SSH origin without asking GitHub', () async {
      origin = 'git@bitbucket.org:ws/app.git';
      git.defaultBranch = 'develop';

      final project = await service.add(byPath);

      expect(project.host, 'bitbucket.org');
      expect(project.sourceKey, keyOf('git@bitbucket.org:ws/app.git'));
      expect(project.githubRepoId, isNull);
      expect(project.isOnGitHub, isFalse);
      expect(project.fullName, 'ws/app');
      expect(project.remote, 'git@bitbucket.org:ws/app.git');
      expect(project.localPath, '/work/app');
      expect(project.defaultBaseBranch, 'develop');
      expect(project.profile.branches.defaultBranch, 'develop');
      expect(github.lookups, isEmpty);
      expect(git.calls, [
        'lsRemote git@bitbucket.org:ws/app.git',
        'ensureMirror ${project.sourceKey}',
      ]);
      expect(git.remotes[project.sourceKey], 'git@bitbucket.org:ws/app.git');
      expect(
        await eventsSoFar(),
        contains(ProjectAdded(projectId: project.id, fullName: 'ws/app')),
      );
    });

    test('adds a file:// remote and scans a worktree of its mirror', () async {
      final project = await service.add(
        const AddProjectRequest(remote: ' file:///srv/git/app.git '),
      );
      final key = project.sourceKey;

      expect(project.host, Project.localHost);
      expect(project.fullName, 'srv/git/app');
      expect(project.remote, 'file:///srv/git/app.git');
      expect(project.localPath, isNull);
      expect(project.profile.apps.single.name, 'demo');
      expect(git.calls, [
        'lsRemote file:///srv/git/app.git',
        'ensureMirror $key',
        'fetch $key',
        'resolveRef main',
        'createWorktree scan-${project.id}',
        'removeWorktree /worktrees/scan-${project.id}',
      ]);
    });

    test('reads a folder cloned from a local repository as file://', () async {
      origin = '/srv/git/app.git';

      final project = await service.add(byPath);

      expect(project.remote, 'file:///srv/git/app.git');
      expect(project.host, Project.localHost);
    });

    test('keys every spelling of one repository alike', () async {
      final first = await service.add(
        const AddProjectRequest(remote: 'git@bitbucket.org:ws/app.git'),
      );
      Matcher exists() => throwsA(
        isA<ProjectExistsException>().having(
          (e) => e.existingId,
          'existingId',
          first.id,
        ),
      );

      for (final again in [
        'ssh://git@bitbucket.org/ws/app.git',
        'ssh://git@Bitbucket.org:22/ws/app/',
      ]) {
        await expectLater(
          service.add(AddProjectRequest(remote: again)),
          exists(),
          reason: again,
        );
      }
      origin = 'https://bitbucket.org/ws/app.git';
      await expectLater(
        service.add(
          const AddProjectRequest(
            path: '/work/app',
            sshUrl: 'git@bitbucket.org:ws/app.git',
          ),
        ),
        exists(),
      );
      expect(await service.list(), hasLength(1));
    });

    test('offers the SSH URL of an HTTPS origin on another host', () async {
      origin = 'https://me@bitbucket.org/ws/app.git';

      await expectLater(
        service.add(byPath),
        throwsA(
          isA<ProjectSshUrlRequiredException>()
              .having((e) => e.host, 'host', 'bitbucket.org')
              .having((e) => e.sshUrl, 'sshUrl', 'git@bitbucket.org:ws/app.git')
              .having(
                (e) => e.message,
                'message',
                'XPath has no credentials for bitbucket.org over HTTPS; use '
                    'the SSH URL git@bitbucket.org:ws/app.git.',
              ),
        ),
      );
      await expectLater(
        service.add(
          const AddProjectRequest(remote: 'https://gitlab.com/group/sub/app'),
        ),
        throwsA(
          isA<ProjectSshUrlRequiredException>().having(
            (e) => e.sshUrl,
            'sshUrl',
            'git@gitlab.com:group/sub/app.git',
          ),
        ),
      );
      expect(git.calls, isEmpty);
      expect(await service.list(), isEmpty);
    });

    test('adds the folder at the SSH URL the owner confirmed', () async {
      origin = 'https://bitbucket.org/ws/app.git';

      final project = await service.add(
        const AddProjectRequest(
          path: '/work/app',
          sshUrl: 'ssh://git@bitbucket.org/ws/app.git',
        ),
      );

      expect(project.remote, 'ssh://git@bitbucket.org/ws/app.git');
      expect(project.localPath, '/work/app');
      expect(project.sourceKey, keyOf('git@bitbucket.org:ws/app.git'));
      expect(git.calls.first, 'lsRemote ssh://git@bitbucket.org/ws/app.git');
    });

    test('refuses an SSH URL that is not the one of the origin', () async {
      origin = 'https://bitbucket.org/ws/app.git';

      for (final sshUrl in ['git@bitbucket.org:ws/other.git', 'nope']) {
        await expectLater(
          service.add(AddProjectRequest(path: '/work/app', sshUrl: sshUrl)),
          _invalid(
            '"$sshUrl" is not the SSH URL of https://bitbucket.org/ws/app.git. '
            'Use git@bitbucket.org:ws/app.git.',
          ),
        );
      }
      expect(await service.list(), isEmpty);
    });

    test(
      'takes an SSH URL only with a folder whose origin needs one',
      () async {
        const sshUrl = 'git@bitbucket.org:ws/app.git';
        const refusal =
            '"sshUrl" only goes with a "path" whose origin is an HTTPS URL on '
            'a host other than GitHub; leave it out.';

        await expectLater(
          service.add(
            const AddProjectRequest(path: '/work/app', sshUrl: sshUrl),
          ),
          _invalid(refusal),
          reason: 'the origin is on GitHub',
        );
        origin = sshUrl;
        await expectLater(
          service.add(
            const AddProjectRequest(path: '/work/app', sshUrl: sshUrl),
          ),
          _invalid(refusal),
          reason: 'the origin is an SSH URL',
        );
        await expectLater(
          service.add(
            const AddProjectRequest(
              remote: 'https://bitbucket.org/ws/app.git',
              sshUrl: sshUrl,
            ),
          ),
          _invalid(refusal),
          reason: 'there is no folder',
        );
        expect(git.calls, isEmpty);
      },
    );

    test('refuses a GitHub URL that only reads as another host', () async {
      for (final url in [
        'ssh://git@github.com:22/octo/app',
        'org@github.com:octo/app.git',
        'https://github.com/octo/app/tree/main',
      ]) {
        await expectLater(
          service.add(AddProjectRequest(remote: url)),
          _invalid(
            '"$url" is on GitHub, but not in a form XPath reads. Give the '
            'repository as owner/name.',
          ),
          reason: url,
        );
      }
      expect(git.calls, isEmpty, reason: 'nothing was fetched');
      expect(await service.list(), isEmpty);
    });

    test('names a GitLab subgroup repository by its whole path', () async {
      final project = await service.add(
        const AddProjectRequest(remote: 'git@gitlab.com:group/sub/app.git'),
      );

      expect(project.host, 'gitlab.com');
      expect(project.fullName, 'group/sub/app');
    });

    test('refuses an origin it cannot reach at all', () async {
      origin = 'svn://host/app';

      await expectLater(
        service.add(byPath),
        _invalid('is not a repository XPath can reach'),
      );
    });

    test('says where to add the engine key when it cannot read', () async {
      git.lsRemoteFailure = const GitException(
        'git ls-remote failed (exit 128): git@bitbucket.org: Permission '
        'denied (publickey).\nfatal: Could not read from remote repository.',
      );

      await expectLater(
        service.add(
          const AddProjectRequest(remote: 'git@bitbucket.org:ws/app.git'),
        ),
        gitFailure(
          allOf(
            contains('The engine cannot read ws/app over SSH'),
            contains("the engine's SSH key (~/.ssh/id_ed25519.pub"),
            contains(
              'as an access key of ws/app (Bitbucket: Repository settings, '
              'Access keys)',
            ),
            contains('then add the project again'),
          ),
        ),
      );
      expect(await service.list(), isEmpty);
      expect(git.calls, ['lsRemote git@bitbucket.org:ws/app.git']);
    });

    test('says when a host key changed and passes other failures on', () async {
      git.lsRemoteFailure = const GitException(
        'git ls-remote failed (exit 128): Host key verification failed.',
      );
      await expectLater(
        service.add(
          const AddProjectRequest(remote: 'git@gitlab.com:group/app.git'),
        ),
        gitFailure(contains('ssh-keygen -R gitlab.com')),
      );

      git.lsRemoteFailure = const GitException(
        'git ls-remote failed (exit 128): ssh: Could not resolve hostname x',
      );
      await expectLater(
        service.add(const AddProjectRequest(remote: 'git@x:app.git')),
        gitFailure(
          'XPath cannot read git@x:app.git: git ls-remote failed (exit 128): '
          'ssh: Could not resolve hostname x',
        ),
      );
    });

    test('scans a project on another host without asking GitHub', () async {
      origin = 'git@bitbucket.org:ws/app.git';
      final project = await service.add(byPath);
      github.failure = Exception('GitHub must not be asked');
      folders['/work/app'] = app(overrides: {'.fvmrc': null});

      final scanned = await service.scan(project.id);

      expect(scanned.fullName, 'ws/app');
      expect(scanned.findings.map((f) => f.code), contains('fvmrc_missing'));
      expect(git.calls.last, 'ensureMirror ${project.sourceKey}');
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
      expect(git.remotes['42'], 'https://github.com/octo/renamed.git');
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
    expect(
      const ProjectSshUrlRequiredException(
        host: 'h',
        sshUrl: 'git@h:a.git',
      ).toString(),
      contains('ProjectSshUrlRequiredException: XPath has no credentials'),
    );
    expect(const ProjectInUseException('p').toString(), contains('p'));
    expect(const ProjectInUseException('p').id, 'p');
  });
}
