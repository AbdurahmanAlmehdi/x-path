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
import 'package:xp_desktop/settings/widgets/github_token_section.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// The save button of the credential form, not the one of the GitHub token
/// section below it (U6d).
final Finder _formSave = find.descendant(
  of: find.byType(CredentialForm),
  matching: find.text('Check and save'),
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CreateCredentialRequest(
        name: 'n',
        kind: CredentialKind.slack,
        material: {},
      ),
    );
    registerFallbackValue(const ReplaceCredentialRequest({}));
  });

  late MockCredentialsRepository credentials;
  late MockProjectsRepository projects;
  late StreamController<Snapshot<List<NamedCredential>>> named;
  late StreamController<Snapshot<List<Credential>>> assignments;
  late ShellCubit shell;
  late List<Object> sent;

  setUp(() {
    credentials = MockCredentialsRepository();
    projects = MockProjectsRepository();
    named = StreamController.broadcast();
    assignments = StreamController.broadcast();
    shell = ShellCubit(const CredentialsDestination());
    sent = [];
    when(credentials.watchCredentials).thenAnswer((_) => named.stream);
    when(() => projects.watchCredentials(any()))
        .thenAnswer((_) => assignments.stream);
    when(() => credentials.createCredential(any()))
        .thenAnswer((invocation) async {
          sent.add(invocation.positionalArguments.single as Object);
          return teamKey;
        });
    when(() => credentials.replaceSecret(any(), any()))
        .thenAnswer((invocation) async {
          sent.add(invocation.positionalArguments[1] as Object);
          return teamKey;
        });
    when(() => credentials.renameCredential(any(), any()))
        .thenAnswer((_) async => teamKey);
    when(() => credentials.verifyCredential(any()))
        .thenAnswer((_) async => teamKey);
    when(() => credentials.deleteCredential(any(), force: any(named: 'force')))
        .thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    List<NamedCredential> list = const [],
    List<Credential> assigned = const [],
    List<Project> projectList = const [mataa, captain],
    String? projectId,
    EngineStatus status = EngineStatus.connected,
    FilePicker? pickFile,
    bool github = false,
  }) async {
    await tester.pumpApp(
      CredentialsPage(projectId: projectId, github: github),
      shell: shell,
      credentialsRepository: credentials,
      projectsRepository: projects,
      services: testServices(pickFile: pickFile),
      connection: connectionIn(connectedTo(status: status)),
      projects: projectsIn(ProjectsState(loaded: true, projects: projectList)),
    );
    await tester.pump();
    named.add(Snapshot(list));
    assignments.add(Snapshot(assigned));
    await tester.pumpAndSettle();
  }

  testWidgets('has the GitHub token, focused when it is what was asked', (
    tester,
  ) async {
    await pump(tester, github: true);

    final section = find.byType(GitHubTokenSection);
    expect(section, findsOneWidget);
    final input = tester.widget<EditableText>(
      find.descendant(of: section, matching: find.byType(EditableText)),
    );
    expect(input.focusNode.hasFocus, isTrue);
  });

  Finder field(String name) => find.byKey(Key('credentialForm.$name'));

  Future<void> choose(WidgetTester tester, Finder select, String label) async {
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Taps [label] in the row of [id]: a button, or an item of its menu
  /// (U6c), which a disabled More does not open.
  Future<void> tapIn(WidgetTester tester, String id, String label) async {
    Finder inRow(String text) => find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.text(text),
    );
    if (const {'Rename…', 'Replace secret…', 'Delete…'}.contains(label)) {
      await tester.tap(inRow('More'));
      await tester.pumpAndSettle();
      if (find.text(label).evaluate().isEmpty) return;
      await tester.tap(find.text(label).last);
    } else {
      await tester.tap(inRow(label));
    }
    await tester.pumpAndSettle();
  }

  group('CredentialsPage', () {
    testWidgets('lists the named credentials with their checks and users', (
      tester,
    ) async {
      await pump(tester, list: [teamKey, playAccountKey, slackWebhook]);
      expect(find.text('Team App Store key'), findsOneWidget);
      expect(find.text('App Store Connect API key'), findsOneWidget);
      expect(find.text('ABC123DEF4'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(
        find.text(
          'The service account has no access. Give it the Release manager '
          'role.',
        ),
        findsOneWidget,
      );
      expect(find.text('Not checked'), findsOneWidget);
      expect(find.text('2 flavors'), findsOneWidget);
      expect(find.text('1 flavor'), findsOneWidget);
      expect(find.text('Not used'), findsOneWidget);
      expect(
        find.byTooltip('acme/mataa_new_app · prod\nacme/mataa_new_app · dev'),
        findsOneWidget,
      );
      expect(find.byTooltip('prj_2 · apps/captain · default'), findsOneWidget);
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
      await tester.tap(find.text('Add credential…').first);
      await tester.pumpAndSettle();
      expect(find.text('Add a credential'), findsOneWidget);

      await tester.tap(_formSave);
      expect(sent, isEmpty, reason: 'the fields are empty');

      await tester.enterText(field('name'), '  Team key ');
      await tester.enterText(field('keyId'), 'ABC123DEF4');
      await tester.enterText(field('issuerId'), 'issuer-fake');
      await tester.tap(find.text('Choose file…'));
      await tester.pumpAndSettle();
      await choose(tester, field('keyKind'), 'Individual key');
      await tester.tap(_formSave);
      await tester.pumpAndSettle();

      expect(sent, [
        const CreateCredentialRequest(
          name: 'Team key',
          kind: CredentialKind.ascKey,
          material: {
            'keyId': 'ABC123DEF4',
            'issuerId': 'issuer-fake',
            'privateKey': '-----BEGIN PRIVATE KEY-----',
            'keyKind': 'individual',
          },
        ),
      ]);
      expect(_formSave, findsNothing, reason: 'closed');
      expect(find.text('Credential saved'), findsOneWidget);
    });

    testWidgets('adds a keystore as base64 bytes', (tester) async {
      await pump(
        tester,
        pickFile: () async =>
            const PickedFile(name: 'upload.jks', bytes: [1, 2, 3]),
      );
      await tester.tap(find.text('Add credential…').first);
      await tester.pumpAndSettle();
      await choose(tester, field('kind'), 'Android keystore');
      await tester.tap(find.text('Choose file…'));
      await tester.pumpAndSettle();
      expect(find.text('upload.jks · 3\u00a0B'), findsOneWidget);
      await tester.enterText(field('name'), 'Upload key');
      await tester.enterText(field('storePassword'), 'fake-store-pass');
      await tester.enterText(field('keyAlias'), 'upload');
      await tester.pump();
      await tester.tap(_formSave);
      await tester.pumpAndSettle();
      expect((sent.single as CreateCredentialRequest).material, {
        'keystore': 'AQID',
        'storePassword': 'fake-store-pass',
        'keyAlias': 'upload',
      });
    });

    testWidgets('every named kind has its fields; a cancelled pick changes '
        'nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Add credential…').first);
      await tester.pumpAndSettle();
      await tester.tap(field('kind'));
      await tester.pumpAndSettle();
      expect(find.text('GitHub token'), findsNothing);
      await tester.tap(find.text('App Store Connect API key').last);
      await tester.pumpAndSettle();
      for (final (label, fields) in [
        ('Apple ID', ['appleId', 'password']),
        ('Google Play service account', ['serviceAccount']),
        ('Firebase service account', ['serviceAccount']),
        ('Shorebird API key', ['token']),
        ('Slack webhook', ['webhookUrl']),
      ]) {
        await choose(tester, field('kind'), label);
        for (final name in fields) {
          expect(field(name), findsOneWidget, reason: '$label $name');
        }
      }
      await choose(tester, field('kind'), 'Google Play service account');
      await tester.tap(find.text('Choose file…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_formSave, findsNothing);
    });

    testWidgets('shows why the engine refused, and replaces a secret', (
      tester,
    ) async {
      when(() => credentials.replaceSecret(any(), any())).thenThrow(
        const ApiException(
          'The key was revoked.',
          statusCode: 422,
          code: ApiErrorCode.credentialRejected,
        ),
      );
      await pump(tester, list: [teamKey]);
      await tapIn(tester, 'crd_1', 'Replace secret…');
      expect(
        find.text('Replace the secret of Team App Store key'),
        findsOneWidget,
      );
      expect(field('name'), findsNothing);
      expect(field('kind'), findsNothing);
      await tester.enterText(field('keyId'), 'K');
      await tester.enterText(field('issuerId'), 'I');
      await tester.enterText(field('privateKey'), 'P');
      await tester.pump();
      await tester.tap(_formSave);
      await tester.pumpAndSettle();
      expect(find.text('Not saved: The key was revoked.'), findsOneWidget);

      when(() => credentials.replaceSecret(any(), any()))
          .thenAnswer((invocation) async {
            sent.add(invocation.positionalArguments[1] as Object);
            return teamKey;
          });
      await tester.tap(_formSave);
      await tester.pumpAndSettle();
      expect(sent, [
        const ReplaceCredentialRequest({
          'keyId': 'K',
          'issuerId': 'I',
          'privateKey': 'P',
          'keyKind': 'team',
        }),
      ]);
      expect(_formSave, findsNothing, reason: 'closed');
    });

    testWidgets('renames a credential', (tester) async {
      await pump(tester, list: [teamKey]);
      await tapIn(tester, 'crd_1', 'Rename…');
      expect(find.text('Rename Team App Store key'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => credentials.renameCredential(any(), any()));

      await tapIn(tester, 'crd_1', 'Rename…');
      await tester.enterText(
        find.byKey(const Key('renameCredential.name')),
        ' Old team key ',
      );
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      verify(() => credentials.renameCredential('crd_1', 'Old team key'))
          .called(1);
    });

    testWidgets('checks a credential again', (tester) async {
      await pump(tester, list: [teamKey]);
      await tapIn(tester, 'crd_1', 'Check now');
      verify(() => credentials.verifyCredential('crd_1')).called(1);
      await tester.pump();
      expect(find.textContaining('Checked Team App Store key'), findsOneWidget);
    });

    testWidgets('deletes an unused credential after a simple confirmation', (
      tester,
    ) async {
      await pump(tester, list: [slackWebhook]);
      await tapIn(tester, 'crd_3', 'Delete…');
      expect(find.text('Delete Releases channel?'), findsOneWidget);
      expect(find.text('No flavor uses it.'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      verifyNever(
        () => credentials.deleteCredential(any(), force: any(named: 'force')),
      );

      await tapIn(tester, 'crd_3', 'Delete…');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      verify(() => credentials.deleteCredential('crd_3')).called(1);
    });

    testWidgets('deletes a credential in use only once the owner saw where', (
      tester,
    ) async {
      await pump(tester, list: [teamKey]);
      await tapIn(tester, 'crd_1', 'Delete…');
      expect(
        find.text(
          '2 flavors use it. They will have no App Store Connect API key '
          'until you assign another:',
        ),
        findsOneWidget,
      );
      expect(find.text('acme/mataa_new_app · prod'), findsOneWidget);
      expect(find.text('acme/mataa_new_app · dev'), findsOneWidget);
      await tester.tap(find.text('Unassign and delete'));
      await tester.pumpAndSettle();
      verify(() => credentials.deleteCredential('crd_1', force: true))
          .called(1);
    });

    testWidgets('asks again when a credential came into use meanwhile', (
      tester,
    ) async {
      when(() => credentials.deleteCredential('crd_3')).thenThrow(
        CredentialInUse('In use.', usedBy: teamKey.usedBy.sublist(0, 1)),
      );
      await pump(tester, list: [slackWebhook]);
      await tapIn(tester, 'crd_3', 'Delete…');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '1 flavor uses it. It will have no Slack webhook until you assign '
          'another:',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Unassign and delete'));
      await tester.pumpAndSettle();
      verify(() => credentials.deleteCredential('crd_3', force: true))
          .called(1);
    });

    testWidgets('says when there is none, or no project', (tester) async {
      await pump(tester);
      expect(
        find.text(
          'No credentials yet. Add one, then assign it to the flavors that '
          'need it.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Add credential…').last);
      await tester.pumpAndSettle();
      expect(_formSave, findsOneWidget);
      await pump(tester, projectList: const []);
      expect(
        find.text('Add a project to give its flavors credentials.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the flavors of a project with their credentials', (
      tester,
    ) async {
      await pump(tester, list: [teamKey], assigned: [ascKey, devAscKey]);
      expect(find.text('Flavors'), findsOneWidget);
      expect(find.text('App Store Connect API key: '), findsNWidgets(2));
      expect(find.text('Team App Store key'), findsNWidgets(3));
      expect(find.text('Verified'), findsNWidgets(2));
      expect(find.text('Rejected'), findsOneWidget);
      verify(() => projects.watchCredentials('prj_1')).called(1);

      await tester.tap(find.text('Manage…').first);
      await tester.pumpAndSettle();
      expect(find.text('Credentials of prod'), findsOneWidget);
    });

    testWidgets('names flavors by app when a project has several apps', (
      tester,
    ) async {
      await pump(tester, projectId: 'prj_2');
      expect(find.text('captain · default'), findsOneWidget);
      expect(find.text('None assigned'), findsNWidgets(2));
      expect(find.text('None'), findsNWidgets(2));
    });

    testWidgets('says when the project has no app', (tester) async {
      await pump(
        tester,
        projectList: const [
          Project(
            id: 'prj_3',
            host: 'github.com',
            sourceKey: '3',
            githubRepoId: 3,
            fullName: 'acme/empty',
            remote: 'r',
            defaultBaseBranch: 'main',
          ),
        ],
      );
      expect(find.text('No Flutter app found.'), findsOneWidget);
    });

    testWidgets('switches project', (tester) async {
      await pump(tester);
      await choose(
        tester,
        find.byKey(const Key('credentials.project')),
        'acme/mataa_captain',
      );
      expect(shell.state, const CredentialsDestination('prj_2'));
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      await pump(tester, list: [teamKey], status: EngineStatus.unreachable);
      await tester.tap(find.text('Add credential…').first);
      for (final label in [
        'Check now',
        'Rename…',
        'Replace secret…',
        'Delete…',
      ]) {
        await tapIn(tester, 'crd_1', label);
      }
      expect(_formSave, findsNothing);
      expect(find.text('Rename Team App Store key'), findsNothing);
      verifyNever(() => credentials.verifyCredential(any()));
    });

    testWidgets('shows what failed', (tester) async {
      await pump(tester, list: [teamKey]);
      assignments.addError(const ConnectionException('away'));
      await tester.pumpAndSettle();
      expect(find.text('away'), findsOneWidget);
      named.addError(const ConnectionException('gone'));
      await tester.pumpAndSettle();
      expect(find.text('gone'), findsNWidgets(2));
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
