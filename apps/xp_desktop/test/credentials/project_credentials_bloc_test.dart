import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/credentials/bloc/project_credentials_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';

void main() {
  late MockProjectsRepository projects;
  late MockCredentialsRepository credentials;
  late StreamController<Snapshot<List<Credential>>> assignments;
  late StreamController<Snapshot<List<NamedCredential>>> named;

  const create = CreateCredentialRequest(
    name: 'Shorebird',
    kind: CredentialKind.shorebird,
    material: {'token': 'sb_api_fake'},
  );
  const created = NamedCredential(
    id: 'crd_9',
    name: 'Shorebird',
    kind: CredentialKind.shorebird,
    status: CredentialStatus.verified,
  );
  const prod = AssignmentScope(app: '.', flavor: 'prod');
  const everyFlavor = AssignmentScope(
    app: '.',
    flavor: 'prod',
    allFlavors: true,
    replace: true,
  );

  setUp(() {
    projects = MockProjectsRepository();
    credentials = MockCredentialsRepository();
    assignments = StreamController();
    named = StreamController();
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => assignments.stream);
    when(credentials.watchCredentials).thenAnswer((_) => named.stream);
  });

  // Not awaited: a controller nobody listened to never finishes closing.
  tearDown(() {
    unawaited(assignments.close());
    unawaited(named.close());
  });

  ProjectCredentialsBloc build() =>
      ProjectCredentialsBloc(projects: projects, credentials: credentials);

  final listed = ProjectCredentialsState(
    projectId: 'prj_1',
    loaded: true,
    assignments: [ascKey, devAscKey],
    named: [teamKey],
  );

  void assigns({
    required String credentialId,
    CredentialKind kind = CredentialKind.ascKey,
    bool allFlavors = false,
    bool replace = false,
    List<Credential> kept = const [],
  }) =>
      when(
        () => projects.assignCredential(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: kind,
          credentialId: credentialId,
          allFlavors: allFlavors,
          replace: replace,
        ),
      ).thenAnswer(
        (_) async => AssignCredentialResponse(assigned: [ascKey], kept: kept),
      );

  group('ProjectCredentialsBloc', () {
    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'follows the assignments of the project and the named credentials',
      build: build,
      act: (bloc) async {
        bloc.add(const ProjectCredentialsSubscriptionRequested('prj_1'));
        await Future<void>.delayed(Duration.zero);
        assignments.add(Snapshot([ascKey, devAscKey]));
        await Future<void>.delayed(Duration.zero);
        named.add(Snapshot([teamKey]));
        await Future<void>.delayed(Duration.zero);
        assignments.addError(const ConnectionException('gone'));
        await Future<void>.delayed(Duration.zero);
        named.addError(const ConnectionException('away'));
      },
      expect: () => [
        const ProjectCredentialsState(projectId: 'prj_1'),
        ProjectCredentialsState(
          projectId: 'prj_1',
          loaded: true,
          assignments: [ascKey, devAscKey],
        ),
        listed,
        listed.copyWith(error: () => 'gone'),
        listed.copyWith(error: () => 'away'),
      ],
    );

    test('reads the credentials of a flavor and the choices of a kind', () {
      expect(listed.of('.', 'dev'), [devAscKey]);
      expect(listed.of('apps/x', 'dev'), isEmpty);
      expect(listed.choices(CredentialKind.ascKey), [teamKey]);
      expect(listed.choices(CredentialKind.slack), isEmpty);
    });

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'assigns a credential to one flavor',
      build: build,
      seed: () => listed,
      setUp: () => assigns(credentialId: 'crd_1'),
      act: (bloc) => bloc.add(
        const ProjectCredentialAssignRequested(
          scope: AssignmentScope(app: '.', flavor: 'prod', replace: true),
          kind: CredentialKind.ascKey,
          credentialId: 'crd_1',
        ),
      ),
      expect: () => [
        listed.copyWith(
          assign: AssignStatus.working,
          busy: () => CredentialKind.ascKey,
        ),
        listed.copyWith(assign: AssignStatus.done),
      ],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'assigns a credential to every flavor of the app and says who kept '
      'theirs',
      build: build,
      seed: () => listed,
      setUp: () => assigns(
        credentialId: 'crd_1',
        allFlavors: true,
        replace: true,
        kept: [devAscKey],
      ),
      act: (bloc) => bloc
        ..add(
          const ProjectCredentialAssignRequested(
            scope: everyFlavor,
            kind: CredentialKind.ascKey,
            credentialId: 'crd_1',
          ),
        )
        ..add(const ProjectCredentialEditorReset()),
      expect: () => [
        listed.copyWith(
          assign: AssignStatus.working,
          busy: () => CredentialKind.ascKey,
        ),
        listed.copyWith(assign: AssignStatus.done, kept: [devAscKey]),
        listed,
      ],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'adds a credential, then assigns it',
      build: build,
      seed: () => listed,
      setUp: () {
        when(() => credentials.createCredential(create))
            .thenAnswer((_) async => created);
        assigns(credentialId: 'crd_9', kind: CredentialKind.shorebird);
      },
      act: (bloc) => bloc.add(
        const ProjectCredentialCreateRequested(scope: prod, request: create),
      ),
      expect: () => [
        listed.copyWith(
          assign: AssignStatus.working,
          busy: () => CredentialKind.shorebird,
        ),
        listed.copyWith(assign: AssignStatus.done),
      ],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'says why the engine refused a new credential',
      build: build,
      seed: () => listed,
      setUp: () => when(() => credentials.createCredential(create)).thenThrow(
        const ApiException(
          'The token was revoked.',
          statusCode: 422,
          code: ApiErrorCode.credentialRejected,
        ),
      ),
      act: (bloc) => bloc.add(
        const ProjectCredentialCreateRequested(scope: prod, request: create),
      ),
      skip: 1,
      expect: () => [
        listed.copyWith(
          assign: AssignStatus.failed,
          error: () => 'The token was revoked.',
        ),
      ],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'has the engine create a distribution certificate for a flavor',
      build: build,
      seed: () => listed,
      setUp: () => when(
        () => credentials.createDistributionCertificate(
          'prj_1',
          app: '.',
          flavor: 'prod',
          name: 'Linux signing',
        ),
      ).thenAnswer((_) async => slackWebhook),
      act: (bloc) => bloc.add(
        const ProjectCertificateCreateRequested(
          app: '.',
          flavor: 'prod',
          name: 'Linux signing',
        ),
      ),
      expect: () => [
        listed.copyWith(
          assign: AssignStatus.working,
          busy: () => CredentialKind.appleDistribution,
        ),
        listed.copyWith(assign: AssignStatus.done),
      ],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      "says why the engine made no certificate, as at Apple's limit",
      build: build,
      seed: () => listed,
      setUp: () =>
          when(
            () => credentials.createDistributionCertificate(
              'prj_1',
              app: '.',
              flavor: 'prod',
              name: 'Linux signing',
            ),
          ).thenThrow(
            const ApiException(
              'The team has 3 distribution certificates.',
              statusCode: 409,
              code: ApiErrorCode.conflict,
            ),
          ),
      act: (bloc) => bloc.add(
        const ProjectCertificateCreateRequested(
          app: '.',
          flavor: 'prod',
          name: 'Linux signing',
        ),
      ),
      skip: 1,
      expect: () => [
        listed.copyWith(
          assign: AssignStatus.failed,
          error: () => 'The team has 3 distribution certificates.',
        ),
      ],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'unassigns a credential from a flavor',
      build: build,
      seed: () => listed,
      setUp: () => when(
        () => projects.unassignCredential(
          'prj_1',
          app: '.',
          flavor: 'dev',
          kind: CredentialKind.ascKey,
        ),
      ).thenAnswer((_) async {}),
      act: (bloc) => bloc.add(
        const ProjectCredentialUnassignRequested(
          app: '.',
          flavor: 'dev',
          kind: CredentialKind.ascKey,
        ),
      ),
      expect: () => [
        listed.copyWith(busy: () => CredentialKind.ascKey),
        listed,
      ],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'says why an unassignment failed',
      build: build,
      seed: () => listed,
      setUp: () => when(
        () => projects.unassignCredential(
          'prj_1',
          app: '.',
          flavor: 'dev',
          kind: CredentialKind.ascKey,
        ),
      ).thenThrow(const ConnectionException('Connection refused.')),
      act: (bloc) => bloc.add(
        const ProjectCredentialUnassignRequested(
          app: '.',
          flavor: 'dev',
          kind: CredentialKind.ascKey,
        ),
      ),
      skip: 1,
      expect: () => [listed.copyWith(error: () => 'Connection refused.')],
    );

    blocTest<ProjectCredentialsBloc, ProjectCredentialsState>(
      'does nothing before it knows the project',
      build: build,
      act: (bloc) => bloc
        ..add(
          const ProjectCredentialAssignRequested(
            scope: prod,
            kind: CredentialKind.ascKey,
            credentialId: 'crd_1',
          ),
        )
        ..add(
          const ProjectCredentialUnassignRequested(
            app: '.',
            flavor: 'dev',
            kind: CredentialKind.ascKey,
          ),
        ),
      expect: () => <ProjectCredentialsState>[],
    );

    test('events compare by value', () {
      expect(const ProjectCredentialsSubscriptionRequested('a').props, ['a']);
      expect(prod.props, ['.', 'prod', false, false]);
      expect(
        const ProjectCredentialAssignRequested(
          scope: prod,
          kind: CredentialKind.slack,
          credentialId: 'a',
        ).props,
        [prod, CredentialKind.slack, 'a'],
      );
      expect(
        const ProjectCredentialCreateRequested(
          scope: prod,
          request: create,
        ).props,
        [prod, create],
      );
      expect(
        const ProjectCredentialUnassignRequested(
          app: '.',
          flavor: 'dev',
          kind: CredentialKind.slack,
        ).props,
        ['.', 'dev', CredentialKind.slack],
      );
      expect(
        const ProjectCertificateCreateRequested(
          app: '.',
          flavor: 'prod',
          name: 'n',
        ).props,
        ['.', 'prod', 'n'],
      );
      expect(const ProjectCredentialEditorReset().props, isEmpty);
    });
  });
}
