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
  late MockCredentialsRepository repository;
  late StreamController<Snapshot<List<NamedCredential>>> credentials;

  const create = CreateCredentialRequest(
    name: 'Shorebird',
    kind: CredentialKind.shorebird,
    material: {'token': 'sb_api_fake'},
  );
  const replace = ReplaceCredentialRequest({'token': 'sb_api_fake2'});
  const rejected = ApiException(
    'The key was revoked.',
    statusCode: 422,
    code: ApiErrorCode.credentialRejected,
  );

  setUp(() {
    repository = MockCredentialsRepository();
    credentials = StreamController();
    when(repository.watchCredentials).thenAnswer((_) => credentials.stream);
  });

  // Not awaited: a controller nobody listened to never finishes closing.
  tearDown(() => unawaited(credentials.close()));

  final listed = CredentialsState(loaded: true, credentials: [teamKey]);

  group('CredentialsBloc', () {
    blocTest<CredentialsBloc, CredentialsState>(
      'follows the named credentials of the engine',
      build: () => CredentialsBloc(credentials: repository),
      act: (bloc) async {
        bloc.add(const CredentialsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        credentials
          ..add(Snapshot([teamKey], cached: true))
          ..add(Snapshot([teamKey]))
          ..addError(const ConnectionException('gone'));
      },
      expect: () => [
        CredentialsState(loaded: true, credentials: [teamKey], cached: true),
        listed,
        listed.copyWith(error: 'gone'),
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'keeps how the form and a deletion stand while the list changes',
      build: () => CredentialsBloc(credentials: repository),
      seed: () => listed.copyWith(
        save: CredentialSaveStatus.failed,
        saveError: 'No.',
        busy: 'crd_1',
        inUse: const CredentialConflict('crd_1', []),
      ),
      act: (bloc) async {
        bloc.add(const CredentialsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        credentials.add(const Snapshot([playAccountKey]));
      },
      expect: () => [
        const CredentialsState(
          loaded: true,
          credentials: [playAccountKey],
          save: CredentialSaveStatus.failed,
          saveError: 'No.',
          busy: 'crd_1',
          inUse: CredentialConflict('crd_1', []),
        ),
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'adds a credential the engine accepts',
      build: () => CredentialsBloc(credentials: repository),
      seed: () => listed,
      setUp: () =>
          when(() => repository.createCredential(create))
              .thenAnswer((_) async => teamKey),
      act: (bloc) => bloc
        ..add(const CredentialCreateRequested(create))
        ..add(const CredentialFormReset()),
      expect: () => [
        listed.copyWith(save: CredentialSaveStatus.saving),
        listed.copyWith(save: CredentialSaveStatus.saved),
        listed,
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'replaces the secret of a credential',
      build: () => CredentialsBloc(credentials: repository),
      seed: () => listed,
      setUp: () =>
          when(() => repository.replaceSecret('crd_1', replace))
              .thenAnswer((_) async => teamKey),
      act: (bloc) =>
          bloc.add(const CredentialReplaceRequested('crd_1', replace)),
      expect: () => [
        listed.copyWith(save: CredentialSaveStatus.saving),
        listed.copyWith(save: CredentialSaveStatus.saved),
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'says why the engine refused a credential',
      build: () => CredentialsBloc(credentials: repository),
      seed: () => listed,
      setUp: () =>
          when(() => repository.createCredential(create)).thenThrow(rejected),
      act: (bloc) => bloc.add(const CredentialCreateRequested(create)),
      skip: 1,
      expect: () => [
        listed.copyWith(
          save: CredentialSaveStatus.failed,
          saveError: 'The key was revoked.',
        ),
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'renames, checks and deletes credentials',
      build: () => CredentialsBloc(credentials: repository),
      seed: () => listed,
      setUp: () {
        when(() => repository.renameCredential('crd_1', 'Old key'))
            .thenAnswer((_) async => teamKey);
        when(() => repository.verifyCredential('crd_1'))
            .thenAnswer((_) async => teamKey);
        when(() => repository.deleteCredential('crd_1', force: true))
            .thenAnswer((_) async {});
      },
      act: (bloc) async {
        bloc.add(const CredentialRenameRequested('crd_1', 'Old key'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const CredentialVerifyRequested('crd_1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const CredentialDeleteRequested('crd_1', force: true));
      },
      expect: () => [
        listed.copyWith(busy: 'crd_1'),
        listed,
        listed.copyWith(busy: 'crd_1'),
        listed.copyWith(checked: teamKey),
        listed.copyWith(busy: 'crd_1'),
        listed,
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'says which flavors keep a credential from being deleted',
      build: () => CredentialsBloc(credentials: repository),
      seed: () => listed,
      setUp: () =>
          when(() => repository.deleteCredential('crd_1'))
              .thenThrow(CredentialInUse('In use.', usedBy: teamKey.usedBy)),
      act: (bloc) => bloc.add(const CredentialDeleteRequested('crd_1')),
      skip: 1,
      expect: () => [
        listed.copyWith(inUse: CredentialConflict('crd_1', teamKey.usedBy)),
      ],
    );

    blocTest<CredentialsBloc, CredentialsState>(
      'says why a command failed',
      build: () => CredentialsBloc(credentials: repository),
      seed: () => listed,
      setUp: () =>
          when(() => repository.verifyCredential('crd_1'))
              .thenThrow(const ConnectionException('Connection refused.')),
      act: (bloc) => bloc.add(const CredentialVerifyRequested('crd_1')),
      skip: 1,
      expect: () => [listed.copyWith(error: 'Connection refused.')],
    );

    test('events compare by value', () {
      expect(const CredentialsSubscriptionRequested().props, isEmpty);
      expect(const CredentialCreateRequested(create).props, [create]);
      expect(const CredentialReplaceRequested('a', replace).props, [
        'a',
        replace,
      ]);
      expect(const CredentialRenameRequested('a', 'b').props, ['a', 'b']);
      expect(const CredentialVerifyRequested('a').props, ['a']);
      expect(const CredentialDeleteRequested('a').props, ['a', false]);
      expect(const CredentialFormReset().props, isEmpty);
      expect(const CredentialConflict('a', []).props, ['a', <Object>[]]);
    });
  });
}
