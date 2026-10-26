import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/samples.dart' as sample;
import '../helpers/test_env.dart';

void main() {
  late MockXpClient client;

  setUp(() => client = MockXpClient());

  group('projectOfRemote', () {
    const bitbucket = Project(
      id: 'prj_3',
      host: 'bitbucket.org',
      sourceKey: 'h1',
      fullName: 'ws/mobile/shop',
      remote: 'git@bitbucket.org:ws/mobile/shop.git',
      defaultBaseBranch: 'main',
    );

    setUp(
      () => when(() => client.listProjects()).thenAnswer(
        (_) async => [sample.project, sample.bareProject, bitbucket],
      ),
    );

    test('matches every spelling of the same repository', () async {
      for (final remote in [
        'https://github.com/acme/app.git',
        'git@github.com:ACME/app',
        'ssh://git@github.com/acme/app.git',
      ]) {
        expect(
          (await projectOfRemote(client, remote))?.id,
          'prj_1',
          reason: remote,
        );
      }
      expect(
        (await projectOfRemote(
          client,
          'git@bitbucket.org:ws/mobile/shop.git',
        ))?.id,
        'prj_3',
      );
    });

    test('is null outside a clone, for another repository or URL', () async {
      expect(await projectOfRemote(client, null), isNull);
      expect(
        await projectOfRemote(client, 'git@gitlab.com:acme/app.git'),
        isNull,
      );
      expect(await projectOfRemote(client, 'not a url'), isNull);
      verify(() => client.listProjects()).called(1);
    });
  });

  group('resolveProject', () {
    test('passes an id through without asking', () async {
      expect(await resolveProject(client, 'prj_9'), 'prj_9');
      verifyNever(() => client.listProjects());
    });

    test('finds owner/name and name, in any case', () async {
      when(() => client.listProjects())
          .thenAnswer((_) async => [sample.project, sample.bareProject]);

      expect(await resolveProject(client, 'ACME/app'), 'prj_1');
      expect(await resolveProject(client, 'other'), 'prj_2');
    });

    test('says when nothing matches', () async {
      when(() => client.listProjects()).thenAnswer((_) async => []);

      await expectLater(
        resolveProject(client, 'nope'),
        throwsA(
          isA<ReferenceException>()
              .having((e) => e.notFound, 'notFound', isTrue)
              .having((e) => '$e', 'message', contains('"nope"')),
        ),
      );
    });

    test('says when several match', () async {
      when(() => client.listProjects()).thenAnswer(
        (_) async => [
          sample.project,
          sample.bareProject.copyWithName('beta/app'),
        ],
      );

      await expectLater(
        resolveProject(client, 'app'),
        throwsA(
          isA<ReferenceException>()
              .having((e) => e.notFound, 'notFound', isFalse)
              .having((e) => e.message, 'message', contains('acme/app')),
        ),
      );
    });
  });

  group('resolveRunner', () {
    test('passes an id through without asking', () async {
      expect(await resolveRunner(client, 'rnr_9'), 'rnr_9');
      verifyNever(() => client.listRunners());
    });

    test('finds a runner by name', () async {
      when(() => client.listRunners()).thenAnswer((_) async => [sample.runner]);

      expect(await resolveRunner(client, 'mac-mini'), 'rnr_1');
    });

    test('says when nothing matches', () async {
      when(() => client.listRunners()).thenAnswer((_) async => []);

      await expectLater(
        resolveRunner(client, 'nope'),
        throwsA(
          isA<ReferenceException>()
              .having((e) => e.notFound, 'notFound', isTrue)
              .having((e) => '$e', 'message', contains('"nope"')),
        ),
      );
    });
  });

  group('resolveCredential', () {
    const named = NamedCredential(
      id: 'crd_9',
      name: 'crd_1',
      kind: CredentialKind.slack,
      status: CredentialStatus.verified,
    );

    setUp(
      () =>
          when(() => client.listNamedCredentials())
              .thenAnswer((_) async => [sample.ascCredential, named]),
    );

    test('finds an id', () async {
      expect((await resolveCredential(client, 'crd_9')).name, 'crd_1');
    });

    test('takes an id before a name that looks like one', () async {
      expect((await resolveCredential(client, 'crd_1')).name, 'Acme ASC');
    });

    test('finds a name regardless of case', () async {
      expect((await resolveCredential(client, 'ACME asc')).id, 'crd_1');
    });

    test('finds a name that starts like an id but is none', () async {
      when(() => client.listNamedCredentials())
          .thenAnswer((_) async => [named]);

      expect((await resolveCredential(client, 'CRD_1')).id, 'crd_9');
      expect((await resolveCredential(client, 'crd_1')).id, 'crd_9');
    });

    test('says when nothing matches', () async {
      await expectLater(
        resolveCredential(client, 'nope'),
        throwsA(
          isA<ReferenceException>()
              .having((e) => e.notFound, 'notFound', isTrue)
              .having((e) => '$e', 'message', contains('xp credentials list')),
        ),
      );
    });
  });

  group('resolveWorkflow', () {
    test('passes an id through', () async {
      expect(await resolveWorkflow(client, 'prj_1', 'wf_3'), 'wf_3');
      verifyNever(() => client.listWorkflows(any()));
    });

    test('finds a name', () async {
      when(() => client.listWorkflows('prj_1'))
          .thenAnswer((_) async => [sample.workflowSummary]);

      expect(await resolveWorkflow(client, 'prj_1', 'dev-build'), 'wf_1');
    });

    test('says when there is none', () async {
      when(() => client.listWorkflows('prj_1')).thenAnswer((_) async => []);

      await expectLater(
        resolveWorkflow(client, 'prj_1', 'x'),
        throwsA(isA<ReferenceException>()),
      );
    });
  });
}

extension on Project {
  Project copyWithName(String fullName) => Project(
    id: 'prj_3',
    host: 'github.com',
    sourceKey: '9',
    githubRepoId: 9,
    fullName: fullName,
    remote: remote,
    defaultBaseBranch: defaultBaseBranch,
  );
}
