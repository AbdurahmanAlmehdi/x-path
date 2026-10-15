import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/credentials/bloc/credentials_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';

void main() {
  late MockProjectsRepository projects;
  late StreamController<Snapshot<List<Credential>>> credentials;

  const request = SaveCredentialRequest(
    flavor: 'prod',
    kind: CredentialKind.shorebird,
    material: {'token': 'sb_api_1'},
  );
  const rejected = ApiException(
    'The key was revoked.',
    statusCode: 422,
    code: ApiErrorCode.credentialRejected,
  );

  setUp(() {
    projects = MockProjectsRepository();
    credentials = StreamController();
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => credentials.stream);
  });

  // Not awaited: a controller nobody listened to never finishes closing.
  tearDown(() => unawaited(credentials.close()));

  final listed = CredentialsState(
    projectId: 'prj_1',
    loaded: true,
    credentials: [ascKey],
  );

  group('CredentialsBloc', () {
    blocTest<CredentialsBloc, CredentialsState>(
      'follows the credentials of the project',
      build: () => CredentialsBloc(projects: projects),
      act: (bloc) async {
        bloc.add(const CredentialsSubscriptionRequested('prj_1'));
        await Future<void>.delayed(Duration.zero);
        credentials
          ..add(Snapshot([ascKey], cached: true))
          ..add(Snapshot([ascKey]))
          ..addError(const ConnectionException('gone'));
      },
      expect: () => [
        const CredentialsState(projectId: 'prj_1'),
        CredentialsState(
          projectId: 'prj_1',
          loaded: true,
          credentials: [ascKey],
          cached: true,
        ),
        listed,
        listed.copyWith(error: 'gone'),
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'saves a credential the engine accepts',
      build: () => CredentialsBloc(projects: projects),
      seed: () => listed,
      setUp: () =>
          when(() => projects.saveCredential('prj_1', request))
              .thenAnswer((_) async => ascKey),
      act: (bloc) => bloc
        ..add(const CredentialSaveRequested(request))
        ..add(const CredentialFormReset()),
      expect: () => [
        listed.copyWith(save: CredentialSaveStatus.saving),
        listed.copyWith(save: CredentialSaveStatus.saved),
        listed,
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'says why the engine refused a credential',
      build: () => CredentialsBloc(projects: projects),
      seed: () => listed,
      setUp: () =>
          when(() => projects.saveCredential('prj_1', request))
              .thenThrow(rejected),
      act: (bloc) => bloc.add(const CredentialSaveRequested(request)),
      skip: 1,
      expect: () => [
        listed.copyWith(
          save: CredentialSaveStatus.failed,
          saveError: 'The key was revoked.',
        ),
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'checks and deletes credentials',
      build: () => CredentialsBloc(projects: projects),
      seed: () => listed,
      setUp: () {
        when(() => projects.verifyCredential('prj_1', 'crd_1'))
            .thenAnswer((_) async => ascKey);
        when(() => projects.deleteCredential('prj_1', 'crd_1'))
            .thenAnswer((_) async {});
      },
      act: (bloc) => bloc
        ..add(const CredentialVerifyRequested('crd_1'))
        ..add(const CredentialDeleteRequested('crd_1')),
      expect: () => [
        listed.copyWith(busy: 'crd_1'),
        listed,
        listed.copyWith(busy: 'crd_1'),
        listed,
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'says why a check failed',
      build: () => CredentialsBloc(projects: projects),
      seed: () => listed,
      setUp: () =>
          when(() => projects.verifyCredential('prj_1', 'crd_1'))
              .thenThrow(const ConnectionException('Connection refused.')),
      act: (bloc) => bloc.add(const CredentialVerifyRequested('crd_1')),
      skip: 1,
      expect: () => [listed.copyWith(error: 'Connection refused.')],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'does nothing before it knows the project',
      build: () => CredentialsBloc(projects: projects),
      act: (bloc) => bloc
        ..add(const CredentialSaveRequested(request))
        ..add(const CredentialVerifyRequested('crd_1')),
      expect: () => <CredentialsState>[],
    );

    test('events compare by value', () {
      expect(const CredentialsSubscriptionRequested('a').props, ['a']);
      expect(const CredentialSaveRequested(request).props, [request]);
      expect(const CredentialVerifyRequested('a').props, ['a']);
      expect(const CredentialDeleteRequested('a').props, ['a']);
      expect(const CredentialFormReset().props, isEmpty);
    });
  });
}
