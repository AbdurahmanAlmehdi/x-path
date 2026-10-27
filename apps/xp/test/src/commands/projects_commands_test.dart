import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUpAll(registerFallbacks);
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('projects list', () {
    test('prints a table', () async {
      when(() => env.client.listProjects())
          .thenAnswer((_) async => [sample.project, sample.bareProject]);

      await env.runOk(['projects', 'list']);

      expect(env.logger.out, contains('ID'));
      expect(env.logger.out, contains('prj_1  acme/app'));
      expect(env.logger.out, contains('2026-10-14 09:30'));
      expect(env.logger.out, contains('acme/other'));
      expect(env.connections.single.token, 'cli-token');
    });

    test('says how to add a project when there is none', () async {
      when(() => env.client.listProjects()).thenAnswer((_) async => []);

      await env.runOk(['projects', 'list']);

      expect(env.logger.out, contains('xp projects add'));
    });

    test('with --json prints the projects as JSON', () async {
      when(() => env.client.listProjects())
          .thenAnswer((_) async => [sample.project]);

      await env.runOk(['--json', 'projects', 'list']);

      final json = jsonDecode(env.logger.infos.single) as List<dynamic>;
      expect((json.single as Map)['fullName'], 'acme/app');
    });

    test('takes --json after the command too', () async {
      when(() => env.client.listProjects())
          .thenAnswer((_) async => [sample.project]);

      await env.runOk(['projects', 'list', '--json']);

      final json = jsonDecode(env.logger.infos.single) as List<dynamic>;
      expect((json.single as Map)['fullName'], 'acme/app');
    });

    test('closes the client', () async {
      when(() => env.client.listProjects()).thenAnswer((_) async => []);

      await env.runOk(['projects', 'list']);

      expect(env.client.closed, 1);
    });
  });

  group('projects show', () {
    test('resolves a name and prints the apps, flavors and findings', () async {
      when(() => env.client.listProjects())
          .thenAnswer((_) async => [sample.project]);
      when(() => env.client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);

      await env.runOk(['projects', 'show', 'acme/app']);

      expect(env.logger.out, contains('acme/app (prj_1)'));
      expect(env.logger.out, contains('app app (.), flutter 1.2.3+4'));
      expect(
        env.logger.out,
        contains('flavor prod (prod)  android com.acme.app  ios com.acme.app'),
      );
      expect(env.logger.out, contains('flavor dev\n'));
      expect(env.logger.out, contains('warning: Something is off'));
    });

    test('takes an id without a lookup and prints a bare project', () async {
      when(() => env.client.getProject('prj_2'))
          .thenAnswer((_) async => sample.bareProject);

      await env.runOk(['projects', 'show', 'prj_2']);

      expect(env.logger.out, contains('acme/other (prj_2)'));
      expect(env.logger.out, isNot(contains('findings')));
      verifyNever(() => env.client.listProjects());
    });

    test('with --json prints the project', () async {
      when(() => env.client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);

      await env.runOk(['--json', 'projects', 'show', 'prj_1']);

      expect((jsonDecode(env.logger.infos.single) as Map)['id'], 'prj_1');
    });

    test('without a project is a usage error', () async {
      expect(await env.run(['projects', 'show']), 64);
      expect(env.logger.errors.single, contains('<project>'));
    });

    test('with too many arguments is a usage error', () async {
      expect(await env.run(['projects', 'show', 'a', 'b']), 64);
    });

    test('for a project that does not exist is "not found"', () async {
      when(() => env.client.listProjects()).thenAnswer((_) async => []);

      expect(await env.run(['projects', 'show', 'ghost']), 66);
      expect(env.logger.errors.single, contains('ghost'));
    });

    test('for a name that fits two projects is a usage error', () async {
      when(() => env.client.listProjects()).thenAnswer(
        (_) async => [
          sample.project,
          const Project(
            id: 'prj_3',
            host: 'github.com',
            sourceKey: '3',
            githubRepoId: 3,
            fullName: 'beta/app',
            remote: 'r',
            defaultBaseBranch: 'main',
          ),
        ],
      );

      expect(await env.run(['projects', 'show', 'app']), 64);
    });
  });

  group('projects add', () {
    test('adds a clone on this machine by its absolute path', () async {
      when(() => env.client.addProject(any()))
          .thenAnswer((_) async => sample.project);
      final clone = Directory.systemTemp.createTempSync('xp_clone');
      addTearDown(() => clone.deleteSync(recursive: true));

      await env.runOk(['projects', 'add', clone.path]);

      final request =
          verify(() => env.client.addProject(captureAny())).captured.single
              as AddProjectRequest;
      expect(request.path, endsWith(clone.path.split('/').last));
      expect(request.path, startsWith('/'));
      expect(request.remote, isNull);
      expect(env.logger.out, contains('Added acme/app (prj_1).'));
    });

    test('adds a repository by name', () async {
      when(() => env.client.addProject(any()))
          .thenAnswer((_) async => sample.project);

      await env.runOk(['projects', 'add', 'acme/app']);

      final request =
          verify(() => env.client.addProject(captureAny())).captured.single
              as AddProjectRequest;
      expect(request.remote, 'acme/app');
      expect(request.path, isNull);
    });

    test('says a folder that does not exist is not there', () async {
      for (final path in ['./typo', '/no/such/folder', '~/typo', '..']) {
        if (Directory(path).existsSync()) continue;
        env.logger.errors.clear();
        expect(await env.run(['projects', 'add', path]), 64);
        expect(env.logger.errors.first, 'No folder at $path.');
      }
      verifyNever(() => env.client.addProject(any()));
    });

    test('takes the remote forms of any host for a remote', () async {
      when(() => env.client.addProject(any()))
          .thenAnswer((_) async => sample.project);
      const remotes = [
        'git@gitlab.example.com:acme/app.git',
        'ssh://git@host/acme/app.git',
        'file:///srv/git/app.git',
        'https://gitea.example.com/acme/app',
        'http://host/acme/app',
      ];

      for (final remote in remotes) {
        await env.runOk(['projects', 'add', remote]);
      }

      final requests = verify(() => env.client.addProject(captureAny()))
          .captured
          .cast<AddProjectRequest>();
      expect([for (final request in requests) request.remote], remotes);
    });

    test('adds an SSH or file:// URL as a remote, not a folder', () async {
      when(() => env.client.addProject(any()))
          .thenAnswer((_) async => sample.project);

      for (final url in [
        'git@bitbucket.org:ws/app.git',
        'ssh://git@gitlab.com/group/sub/app.git',
        'file:///srv/git/app.git',
      ]) {
        await env.runOk(['projects', 'add', url]);

        final request =
            verify(() => env.client.addProject(captureAny())).captured.single
                as AddProjectRequest;
        expect(request.remote, url);
        expect(request.path, isNull);
      }
    });

    test('sends the SSH URL the owner confirmed with a folder', () async {
      when(() => env.client.addProject(any()))
          .thenAnswer((_) async => sample.project);
      final clone = Directory.systemTemp.createTempSync('xp_clone');
      addTearDown(() => clone.deleteSync(recursive: true));

      await env.runOk([
        'projects',
        'add',
        clone.path,
        '--ssh-url',
        'git@bitbucket.org:ws/app.git',
      ]);

      final request =
          verify(() => env.client.addProject(captureAny())).captured.single
              as AddProjectRequest;
      expect(request.path, startsWith('/'));
      expect(request.sshUrl, 'git@bitbucket.org:ws/app.git');
    });

    test('takes --ssh-url only with a folder', () async {
      expect(
        await env.run([
          'projects',
          'add',
          'git@bitbucket.org:ws/app.git',
          '--ssh-url',
          'git@bitbucket.org:ws/app.git',
        ]),
        64,
      );
      verifyNever(() => env.client.addProject(any()));
    });

    test('says how to add an HTTPS origin on another host by SSH', () async {
      const offered = ApiException(
        'XPath has no credentials for bitbucket.org over HTTPS; use the SSH '
        'URL git@bitbucket.org:ws/app.git.',
        statusCode: 422,
        code: ApiErrorCode.sshUrlRequired,
        sshUrl: 'git@bitbucket.org:ws/app.git',
      );
      when(() => env.client.addProject(any())).thenThrow(offered);
      final clone = Directory.systemTemp.createTempSync('xp_clone');
      addTearDown(() => clone.deleteSync(recursive: true));

      expect(await env.run(['projects', 'add', clone.path]), 65);
      expect(env.logger.errors.single, offered.message);
      expect(
        env.logger.out,
        contains('--ssh-url git@bitbucket.org:ws/app.git'),
      );

      expect(
        await env.run(['projects', 'add', 'https://bitbucket.org/ws/app.git']),
        65,
      );
      expect(
        env.logger.out,
        contains('Run: xp projects add git@bitbucket.org:ws/app.git'),
      );
    });

    test('says when the project exists already', () async {
      when(() => env.client.addProject(any())).thenThrow(
        const ApiException(
          'acme/app is a project already.',
          statusCode: 409,
          code: ApiErrorCode.conflict,
        ),
      );

      expect(await env.run(['projects', 'add', 'acme/app']), 73);
      expect(env.logger.errors.single, contains('already'));
    });
  });

  group('projects scan and remove', () {
    test('scan prints the project again', () async {
      when(() => env.client.scanProject('prj_1'))
          .thenAnswer((_) async => sample.project);

      await env.runOk(['projects', 'scan', 'prj_1']);

      expect(env.logger.out, contains('Scanned acme/app.'));
    });

    test('remove removes it', () async {
      when(() => env.client.removeProject('prj_1')).thenAnswer((_) async {});

      await env.runOk(['projects', 'remove', 'prj_1']);

      expect(env.logger.out, 'Removed prj_1.');
      verify(() => env.client.removeProject('prj_1')).called(1);
    });

    test('remove with --json says what it removed', () async {
      when(() => env.client.removeProject('prj_1')).thenAnswer((_) async {});

      await env.runOk(['--json', 'projects', 'remove', 'prj_1']);

      expect(jsonDecode(env.logger.infos.single), {'removed': 'prj_1'});
    });
  });

  group('failures every command shares', () {
    Future<int> listWith(Object error) {
      when(() => env.client.listProjects()).thenThrow(error);
      return env.run(['projects', 'list']);
    }

    ApiException api(int status, ApiErrorCode code, [String message = 'm']) =>
        ApiException(message, statusCode: status, code: code);

    test('not connected is exit 78 and says what to do', () async {
      env = TestEnv(environment: {engineUrlVariable: '', tokenVariable: ''});

      expect(await env.run(['projects', 'list']), 78);
      expect(env.logger.errors.single, contains('xp connect'));
      expect(env.connections, isEmpty);
    });

    test('a rejected token is exit 77 and says to connect again', () async {
      expect(await listWith(api(401, ApiErrorCode.unauthorized, 'Bad.')), 77);
      expect(
        env.logger.errors.single,
        allOf(contains('Bad.'), contains('xp connect')),
      );
    });

    test('a token of the wrong kind is exit 77 and says so', () async {
      expect(await listWith(api(403, ApiErrorCode.forbidden, 'No.')), 77);
      expect(env.logger.errors.single, 'Not allowed with this token: No.');
    });

    test('a missing resource is exit 66', () async {
      expect(await listWith(api(404, ApiErrorCode.notFound)), 66);
    });

    test('a conflict is exit 73', () async {
      expect(await listWith(api(409, ApiErrorCode.conflict)), 73);
    });

    test('content the engine refuses is exit 65', () async {
      expect(await listWith(api(422, ApiErrorCode.workflowInvalid)), 65);
    });

    test('a bad request is exit 64', () async {
      expect(await listWith(api(400, ApiErrorCode.invalidRequest)), 64);
    });

    test('an engine that cannot serve is exit 69', () async {
      expect(await listWith(api(503, ApiErrorCode.secretsLocked)), 69);
      expect(await listWith(api(502, ApiErrorCode.upstreamError)), 69);
    });

    test('an engine that fails is exit 70', () async {
      expect(await listWith(api(500, ApiErrorCode.internal)), 70);
    });

    test('an engine that cannot be reached is exit 69', () async {
      expect(await listWith(const ConnectionException('Cannot reach.')), 69);
      expect(
        env.logger.errors.single,
        'Cannot reach. See '
        'docs/guide/troubleshooting.md#the-engine-does-not-answer.',
      );
    });

    test('a download that broke is exit 1', () async {
      expect(await listWith(const DownloadException('Broke.')), 1);
    });
  });

  group('projects set', () {
    ProfileEdits sent() =>
        verify(() => env.client.updateProject('prj_1', captureAny()))
                .captured
                .single
            as ProfileEdits;

    setUp(() {
      when(() => env.client.updateProject('prj_1', any())).thenAnswer(
        (_) async => const Project(
          id: 'prj_1',
          githubRepoId: 7,
          host: 'github.com',
          sourceKey: '7',
          fullName: 'acme/app',
          remote: 'r',
          defaultBaseBranch: 'main',
          profile: ProjectProfile(
            apps: [
              AppProfile(
                name: 'app',
                path: '.',
                flavors: [
                  FlavorProfile(
                    name: 'dev',
                    entrypoint: 'lib/main_dev.dart',
                    firebaseAppId: {'android': '1:1:android:a'},
                    appleAppId: '123',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      when(() => env.client.getProject('prj_1'))
          .thenAnswer((_) async => sample.project);
    });

    test('sets the store ids of a flavor of the only app', () async {
      await env.runOk([
        'projects',
        'set',
        'prj_1',
        '--flavor',
        'dev',
        '--firebase-app-id',
        'android=1:1:android:a',
        '--firebase-app-id',
        'ios=',
        '--apple-app-id',
        '123',
      ]);

      final app = sent().apps.single;
      expect(app.path, '.');
      expect(
        app.flavors.single,
        const FlavorEdit(
          name: 'dev',
          firebaseAppId: {'android': '1:1:android:a', 'ios': ''},
          appleAppId: '123',
        ),
      );
      expect(env.logger.out, contains('firebase android: 1:1:android:a'));
      expect(env.logger.out, contains('app store: 123'));
    });

    test('takes the app it is given', () async {
      await env.runOk([
        'projects',
        'set',
        'prj_1',
        '--app',
        'apps/x',
        '--flavor',
        'dev',
        '--apple-app-id',
        '',
      ]);

      final app = sent().apps.single;
      expect(app.path, 'apps/x');
      expect(app.flavors.single.firebaseAppId, isNull);
      verifyNever(() => env.client.getProject(any()));
    });

    test(
      'refuses a value that is not platform=id, or nothing to set',
      () async {
        expect(
          await env.run([
            'projects',
            'set',
            'prj_1',
            '--flavor',
            'dev',
            '--firebase-app-id',
            'nope',
          ]),
          64,
        );
        expect(
          await env.run(['projects', 'set', 'prj_1', '--flavor', 'dev']),
          64,
        );
        expect(
          await env.run(['projects', 'set', 'prj_1', '--apple-app-id', '1']),
          64,
        );
        verifyNever(() => env.client.updateProject(any(), any()));
      },
    );

    test('turns Linux iOS builds of an app off, and on again', () async {
      await env.runOk(['projects', 'set', 'prj_1', '--no-ios-linux']);

      expect(sent().apps.single, const AppEdit(path: '.', iosLinux: false));

      await env.runOk(['projects', 'set', 'prj_1', '--ios-linux']);

      expect(
        verify(() => env.client.updateProject('prj_1', captureAny())).captured
            .cast<ProfileEdits>()
            .single
            .apps
            .single
            .iosLinux,
        isTrue,
      );
    });

    test('says when Linux iOS builds of an app are off', () async {
      when(() => env.client.updateProject('prj_1', any())).thenAnswer(
        (_) async => const Project(
          id: 'prj_1',
          githubRepoId: 7,
          host: 'github.com',
          sourceKey: '7',
          fullName: 'acme/app',
          remote: 'r',
          defaultBaseBranch: 'main',
          profile: ProjectProfile(
            apps: [AppProfile(name: 'app', path: '.', iosLinux: false)],
          ),
        ),
      );

      await env.runOk(['projects', 'set', 'prj_1', '--no-ios-linux']);

      expect(
        env.logger.out,
        contains('app app (.), flutter, Linux iOS builds off'),
      );
    });

    test('asks for --app when the project has more than one', () async {
      when(() => env.client.getProject('prj_1')).thenAnswer(
        (_) async => const Project(
          id: 'prj_1',
          githubRepoId: 7,
          host: 'github.com',
          sourceKey: '7',
          fullName: 'acme/app',
          remote: 'r',
          defaultBaseBranch: 'main',
          profile: ProjectProfile(
            apps: [
              AppProfile(name: 'a', path: 'apps/a'),
              AppProfile(name: 'b', path: 'apps/b'),
            ],
          ),
        ),
      );

      expect(
        await env.run([
          'projects',
          'set',
          'prj_1',
          '--flavor',
          'dev',
          '--apple-app-id',
          '1',
        ]),
        64,
      );
      expect(env.logger.errors.first, contains('apps/a, apps/b'));
    });
  });
}
