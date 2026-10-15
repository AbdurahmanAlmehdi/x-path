import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/credentials/credentials.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(
      const SaveCredentialRequest(
        flavor: 'f',
        kind: CredentialKind.slack,
        material: {},
      ),
    );
  });

  late MockProjectsRepository repository;
  late StreamController<Snapshot<List<Credential>>> credentials;
  late ShellCubit shell;
  late List<SaveCredentialRequest> saved;

  setUp(() {
    repository = MockProjectsRepository();
    credentials = StreamController.broadcast();
    shell = ShellCubit(const CredentialsDestination());
    saved = [];
    when(() => repository.watchCredentials(any()))
        .thenAnswer((_) => credentials.stream);
    when(() => repository.saveCredential('prj_1', any()))
        .thenAnswer((invocation) async {
          saved.add(invocation.positionalArguments[1] as SaveCredentialRequest);
          return ascKey;
        });
    when(() => repository.verifyCredential('prj_1', any()))
        .thenAnswer((_) async => ascKey);
    when(() => repository.deleteCredential('prj_1', any()))
        .thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Credential> list = const [],
    List<Project> projects = const [mataa, captain],
    String? projectId,
    EngineStatus status = EngineStatus.connected,
    FilePicker? pickFile,
  }) async {
    await tester.pumpApp(
      CredentialsPage(projectId: projectId),
      shell: shell,
      projectsRepository: repository,
      services: testServices(pickFile: pickFile),
      connection: connectionIn(connectedTo(status: status)),
      projects: projectsIn(ProjectsState(loaded: true, projects: projects)),
    );
    await tester.pump();
    credentials.add(Snapshot(list));
    await tester.pumpAndSettle();
  }

  Finder field(String name) => find.byKey(Key('credentialForm.$name'));

  Future<void> chooseKind(WidgetTester tester, String label) async {
    await tester.tap(field('kind'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  group('CredentialsPage', () {
    testWidgets('lists credentials with their checks', (tester) async {
      await pump(tester, list: [ascKey, playKey, slackHook]);
      expect(find.text('App Store Connect API key'), findsOneWidget);
      expect(find.text('FANNAK'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('apps/x · prod'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(
        find.text(
          'The service account has no access. Give it the Release manager '
          'role.',
        ),
        findsOneWidget,
      );
      expect(find.text('Not checked'), findsOneWidget);
    });

    testWidgets('checks and deletes', (tester) async {
      await pump(tester, list: [ascKey]);
      await tester.tap(find.text('Check now'));
      await tester.pumpAndSettle();
      verify(() => repository.verifyCredential('prj_1', 'crd_1')).called(1);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      verify(() => repository.deleteCredential('prj_1', 'crd_1')).called(1);
    });

    testWidgets('says when there is none, or no project', (tester) async {
      await pump(tester);
      expect(find.text('No credentials yet.'), findsOneWidget);
      await pump(tester, projects: const []);
      expect(
        find.text('Add a project first: credentials belong to its flavors.'),
        findsOneWidget,
      );
    });

    testWidgets('adds an App Store Connect key, reading the .p8 file', (
      tester,
    ) async {
      await pump(
        tester,
        pickFile: () async => PickedFile(
          name: 'AuthKey.p8',
          bytes: utf8.encode('-----BEGIN PRIVATE KEY-----'),
        ),
      );
      await tester.tap(find.text('Add credential…'));
      await tester.pumpAndSettle();
      expect(find.text('Check and save'), findsOneWidget);

      await tester.tap(find.text('Check and save'));
      expect(saved, isEmpty, reason: 'the fields are empty');

      await tester.enterText(field('keyId'), 'ABC123');
      await tester.enterText(field('issuerId'), 'issuer');
      await tester.tap(find.text('Choose file…'));
      await tester.pumpAndSettle();
      await tester.tap(field('flavor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('dev').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check and save'));
      await tester.pumpAndSettle();

      expect(saved, [
        const SaveCredentialRequest(
          flavor: 'dev',
          kind: CredentialKind.ascKey,
          material: {
            'keyId': 'ABC123',
            'issuerId': 'issuer',
            'privateKey': '-----BEGIN PRIVATE KEY-----',
          },
        ),
      ]);
      expect(find.text('Check and save'), findsNothing, reason: 'closed');
    });

    testWidgets('adds a keystore as base64 bytes', (tester) async {
      await pump(
        tester,
        pickFile: () async =>
            const PickedFile(name: 'upload.jks', bytes: [1, 2, 3]),
      );
      await tester.tap(find.text('Add credential…'));
      await tester.pumpAndSettle();
      await chooseKind(tester, 'Android keystore');
      await tester.tap(find.text('Choose file…'));
      await tester.pumpAndSettle();
      expect(find.text('upload.jks · 3 bytes'), findsOneWidget);
      await tester.enterText(field('storePassword'), 'secret');
      await tester.enterText(field('keyAlias'), 'upload');
      await tester.pump();
      await tester.tap(find.text('Check and save'));
      await tester.pumpAndSettle();
      expect(saved.single.material, {
        'keystore': 'AQID',
        'storePassword': 'secret',
        'keyAlias': 'upload',
      });
    });

    testWidgets('every kind has its fields; a cancelled pick changes nothing', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Add credential…'));
      await tester.pumpAndSettle();
      for (final (label, fields) in [
        ('Apple ID', ['appleId', 'password']),
        ('Google Play service account', ['serviceAccount']),
        ('Firebase service account', ['serviceAccount']),
        ('Shorebird API key', ['token']),
        ('GitHub token', ['token']),
        ('Slack webhook', ['webhookUrl']),
      ]) {
        await chooseKind(tester, label);
        for (final name in fields) {
          expect(field(name), findsOneWidget, reason: '$label $name');
        }
      }
      await chooseKind(tester, 'Google Play service account');
      await tester.tap(find.text('Choose file…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Check and save'), findsNothing);
    });

    testWidgets('shows why the engine refused, and replaces a credential', (
      tester,
    ) async {
      when(() => repository.saveCredential('prj_1', any())).thenThrow(
        const ApiException(
          'The key was revoked.',
          statusCode: 422,
          code: ApiErrorCode.credentialRejected,
        ),
      );
      await pump(tester, list: [ascKey]);
      await tester.tap(find.text('Replace…'));
      await tester.pumpAndSettle();
      await tester.enterText(field('keyId'), 'K');
      await tester.enterText(field('issuerId'), 'I');
      await tester.enterText(field('privateKey'), 'P');
      await tester.pump();
      await tester.tap(find.text('Check and save'));
      await tester.pumpAndSettle();
      expect(find.text('Not saved: The key was revoked.'), findsOneWidget);
    });

    testWidgets('replaces a credential of a flavor the scan no longer has', (
      tester,
    ) async {
      await pump(tester, list: [playKey]);
      await tester.tap(find.text('Replace…'));
      await tester.pumpAndSettle();
      expect(find.text('Google Play service account'), findsNWidgets(2));
    });

    testWidgets('names flavors by app when a project has several apps', (
      tester,
    ) async {
      await pump(tester, projectId: 'prj_2');
      await tester.tap(find.text('Add credential…'));
      await tester.pumpAndSettle();
      expect(find.text('captain · default'), findsOneWidget);
    });

    testWidgets('switches project', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('credentials.project')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('acme/mataa_captain').last);
      await tester.pumpAndSettle();
      expect(shell.state, const CredentialsDestination('prj_2'));
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      await pump(tester, list: [ascKey], status: EngineStatus.unreachable);
      await tester.tap(find.text('Add credential…'));
      await tester.tap(find.text('Check now'));
      await tester.tap(find.text('Replace…'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Check and save'), findsNothing);
      verifyNever(() => repository.verifyCredential(any(), any()));
    });

    testWidgets('shows what failed', (tester) async {
      await pump(tester, list: [ascKey]);
      credentials.addError(const ConnectionException('gone'));
      await tester.pumpAndSettle();
      expect(find.text('gone'), findsOneWidget);
    });
  });
}
