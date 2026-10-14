import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/samples.dart' as sample;
import '../helpers/test_env.dart';

void main() {
  late MockXpClient client;

  setUp(() => client = MockXpClient());

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
    githubRepoId: 9,
    fullName: fullName,
    remote: remote,
    defaultBaseBranch: defaultBaseBranch,
  );
}
