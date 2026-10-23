import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/credentials/credentials.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

const shorebirdKey = NamedCredential(
  id: 'crd_9',
  name: 'Shorebird CI',
  kind: CredentialKind.shorebird,
  status: CredentialStatus.verified,
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
    registerFallbackValue(CredentialKind.slack);
    registerFallbackValue(const ProfileEdits());
  });

  late MockCredentialsRepository credentials;
  late MockProjectsRepository projects;
  late StreamController<Snapshot<List<NamedCredential>>> named;
  late StreamController<Snapshot<List<Credential>>> assignments;
  late AssignCredentialResponse response;

  setUp(() {
    credentials = MockCredentialsRepository();
    projects = MockProjectsRepository();
    named = StreamController.broadcast();
    assignments = StreamController.broadcast();
    response = AssignCredentialResponse(assigned: [ascKey]);
    when(credentials.watchCredentials).thenAnswer((_) => named.stream);
    when(() => projects.watchCredentials(any()))
        .thenAnswer((_) => assignments.stream);
    when(
      () => projects.assignCredential(
        any(),
        app: any(named: 'app'),
        flavor: any(named: 'flavor'),
        kind: any(named: 'kind'),
        credentialId: any(named: 'credentialId'),
        allFlavors: any(named: 'allFlavors'),
        replace: any(named: 'replace'),
      ),
    ).thenAnswer((_) async => response);
    when(
      () => projects.unassignCredential(
        any(),
        app: any(named: 'app'),
        flavor: any(named: 'flavor'),
        kind: any(named: 'kind'),
      ),
    ).thenAnswer((_) async {});
    when(() => credentials.createCredential(any()))
        .thenAnswer((_) async => shorebirdKey);
  });

  Future<void> open(
    WidgetTester tester, {
    String flavor = 'prod',
    Project project = mataa,
    EngineStatus status = EngineStatus.connected,
    List<NamedCredential> list = const [],
    bool focusStoreIds = false,
  }) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => XpButton(
          label: 'Open',
          onPressed: () => showFlavorCredentialsSheet(
            context,
            project: project,
            target: (
              app: project.profile.apps.first.path,
              appName: project.profile.apps.first.name,
              flavor: flavor,
            ),
            focusStoreIds: focusStoreIds,
          ),
        ),
      ),
      credentialsRepository: credentials,
      projectsRepository: projects,
      connection: connectionIn(connectedTo(status: status)),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    named.add(Snapshot([teamKey, slackWebhook, ...list]));
    assignments.add(Snapshot([ascKey, devAscKey]));
    await tester.pumpAndSettle();
  }

  /// Scrolls [finder] into the sheet's view, then taps it.
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder row(CredentialKind kind) =>
      find.byKey(Key('flavorCredentials.${kind.wire}'));

  Future<void> tapIn(
    WidgetTester tester,
    CredentialKind kind,
    String label,
  ) async {
    await tap(
      tester,
      find.descendant(of: row(kind), matching: find.text(label)),
    );
  }

  group('FlavorCredentialsSheet', () {
    testWidgets('shows the credential of each kind with its checks', (
      tester,
    ) async {
      await open(tester, flavor: 'dev');
      expect(find.text('Credentials of dev'), findsOneWidget);
      expect(
        find.text('acme/mataa_new_app · Mataa customer app'),
        findsOneWidget,
      );
      for (final kind in namedKinds) {
        expect(row(kind), findsOneWidget);
      }
      expect(find.text('GitHub token'), findsNothing);
      expect(find.text('Team App Store key · ABC123DEF4'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(
        find.text(
          'The key cannot see com.mataaa.dev. Give the key access to the app.',
        ),
        findsOneWidget,
      );
      expect(find.text('Not assigned'), findsNWidgets(6));
      await tap(tester, find.text('Close'));
      expect(find.text('Credentials of dev'), findsNothing);
    });

    testWidgets('assigns an existing credential to this flavor', (
      tester,
    ) async {
      await open(tester);
      await tapIn(tester, CredentialKind.slack, 'Assign…');
      expect(find.text('Releases channel'), findsOneWidget);
      await tap(tester, find.text('Assign'));
      verify(
        () => projects.assignCredential(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.slack,
          credentialId: 'crd_3',
        ),
      ).called(1);
      expect(find.text('Assign'), findsNothing, reason: 'the picker closed');
    });

    testWidgets('assigns to every flavor and says which kept theirs', (
      tester,
    ) async {
      response = AssignCredentialResponse(
        assigned: [ascKey],
        kept: const [devAscKey],
      );
      await open(tester);
      await tapIn(tester, CredentialKind.ascKey, 'Change…');
      expect(find.text('Team App Store key · ABC123DEF4'), findsNWidgets(2));
      await tap(tester, find.text('Every flavor of Mataa customer app'));
      expect(
        find.text(
          'Flavors that have their own App Store Connect API key keep '
          'it.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Assign'));
      verify(
        () => projects.assignCredential(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          credentialId: 'crd_1',
          allFlavors: true,
        ),
      ).called(1);
      expect(
        find.text(
          'dev kept its own credential. Tick “Replace existing” to change it '
          'too.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('replaces the credential of every flavor when ticked', (
      tester,
    ) async {
      await open(tester);
      await tapIn(tester, CredentialKind.ascKey, 'Change…');
      await tap(tester, find.text('Replace existing'));
      await tap(tester, find.text('Every flavor of Mataa customer app'));
      await tap(tester, find.text('Replace existing'));
      expect(
        find.text(
          'Every flavor of the app uses this App Store Connect API key, even '
          'those that have their own.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('Assign'));
      verify(
        () => projects.assignCredential(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
          credentialId: 'crd_1',
          allFlavors: true,
          replace: true,
        ),
      ).called(1);
    });

    testWidgets('adds a new credential of the kind and assigns it', (
      tester,
    ) async {
      await open(tester);
      await tapIn(tester, CredentialKind.shorebird, 'Assign…');
      expect(find.text('Add new…'), findsOneWidget);
      expect(find.byKey(const Key('credentialForm.kind')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('credentialForm.name')),
        'Shorebird CI',
      );
      await tester.enterText(
        find.byKey(const Key('credentialForm.token')),
        'sb_api_fake',
      );
      await tester.pump();
      await tap(tester, find.text('Check, save and assign'));
      verify(
        () => credentials.createCredential(
          const CreateCredentialRequest(
            name: 'Shorebird CI',
            kind: CredentialKind.shorebird,
            material: {'token': 'sb_api_fake'},
          ),
        ),
      ).called(1);
      verify(
        () => projects.assignCredential(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.shorebird,
          credentialId: 'crd_9',
        ),
      ).called(1);
    });

    testWidgets('picks "Add new…" over existing credentials, and says why '
        'the engine refused', (tester) async {
      when(() => credentials.createCredential(any())).thenThrow(
        const ApiException(
          'The token was revoked.',
          statusCode: 422,
          code: ApiErrorCode.credentialRejected,
        ),
      );
      await open(tester, list: [shorebirdKey]);
      await tapIn(tester, CredentialKind.shorebird, 'Assign…');
      await tap(tester, find.byKey(const Key('flavorCredentials.choice')));
      await tap(tester, find.text('Add new…').last);
      await tester.enterText(
        find.byKey(const Key('credentialForm.name')),
        'Other',
      );
      await tester.enterText(
        find.byKey(const Key('credentialForm.token')),
        'sb_api_fake',
      );
      await tester.pump();
      await tap(tester, find.text('Check, save and assign'));
      expect(find.text('Not saved: The token was revoked.'), findsOneWidget);
      await tap(tester, find.text('Cancel'));
      expect(find.text('Check, save and assign'), findsNothing);
    });

    testWidgets('says why an assignment failed', (tester) async {
      when(
        () => projects.assignCredential(
          any(),
          app: any(named: 'app'),
          flavor: any(named: 'flavor'),
          kind: any(named: 'kind'),
          credentialId: any(named: 'credentialId'),
          allFlavors: any(named: 'allFlavors'),
          replace: any(named: 'replace'),
        ),
      ).thenThrow(const ConnectionException('Connection refused.'));
      await open(tester);
      await tapIn(tester, CredentialKind.slack, 'Assign…');
      await tap(tester, find.text('Assign'));
      expect(find.text('Connection refused.'), findsOneWidget);
    });

    testWidgets('removes a credential from the flavor', (tester) async {
      final unassigned = Completer<void>();
      when(
        () => projects.unassignCredential(
          any(),
          app: any(named: 'app'),
          flavor: any(named: 'flavor'),
          kind: any(named: 'kind'),
        ),
      ).thenAnswer((_) => unassigned.future);
      await open(tester);
      await tapIn(tester, CredentialKind.ascKey, 'Remove from this flavor');
      final remove = find.byWidgetPredicate(
        (widget) =>
            widget is XpButton && widget.label == 'Remove from this flavor',
      );
      expect(tester.widget<XpButton>(remove).onPressed, isNull);
      unassigned.completeError(
        const ConnectionException('Connection refused.'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<XpButton>(remove).onPressed, isNotNull);
      verify(
        () => projects.unassignCredential(
          'prj_1',
          app: '.',
          flavor: 'prod',
          kind: CredentialKind.ascKey,
        ),
      ).called(1);
      expect(find.text('Connection refused.'), findsOneWidget);
    });

    testWidgets('has no scope to choose for an app with one flavor', (
      tester,
    ) async {
      await open(tester, project: captain, flavor: 'default');
      await tapIn(tester, CredentialKind.slack, 'Assign…');
      expect(find.text('Use for'), findsNothing);
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      await open(tester, status: EngineStatus.unreachable);
      await tapIn(tester, CredentialKind.slack, 'Assign…');
      await tapIn(tester, CredentialKind.ascKey, 'Remove from this flavor');
      expect(find.text('Assign'), findsNothing);
      verifyNever(
        () => projects.unassignCredential(
          any(),
          app: any(named: 'app'),
          flavor: any(named: 'flavor'),
          kind: any(named: 'kind'),
        ),
      );
    });
  });

  group('store ids', () {
    Finder field(String key) => find.descendant(
      of: find.byKey(Key('storeIds.$key')),
      matching: find.byType(EditableText),
    );

    testWidgets('saves the store ids of the flavor', (tester) async {
      when(() => projects.editProject(any(), any()))
          .thenAnswer((_) async => mataa);
      await open(tester, flavor: 'dev', focusStoreIds: true);
      await tester.pumpAndSettle();

      expect(find.text('STORE IDS'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(field('firebaseAndroid'))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(field('firebaseAndroid'), '1:1:android:a');
      await tester.enterText(field('apple'), '123');
      await tap(tester, find.text('Save ids'));

      final edits =
          verify(() => projects.editProject('prj_1', captureAny()))
                  .captured
                  .single
              as ProfileEdits;
      final edit = edits.apps.single.flavors.single;
      expect(edit.name, 'dev');
      expect(edit.firebaseAppId, {'android': '1:1:android:a', 'ios': ''});
      expect(edit.appleAppId, '123');
      expect(
        find.text('Saved. The next dispatch uploads to these apps.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the ids the flavor has, and why a save failed', (
      tester,
    ) async {
      when(() => projects.editProject(any(), any())).thenThrow(
        const ApiException('Not a Firebase app id.', statusCode: 400),
      );
      final app = mataa.profile.apps.first;
      final project = Project(
        id: mataa.id,
        githubRepoId: mataa.githubRepoId,
        fullName: mataa.fullName,
        remote: mataa.remote,
        defaultBaseBranch: mataa.defaultBaseBranch,
        profile: ProjectProfile(
          apps: [
            app.copyWith(
              flavors: [
                for (final flavor in app.flavors)
                  flavor.copyWith(
                    firebaseAppId: () => {'ios': '1:1:ios:b'},
                    appleAppId: () => '9',
                  ),
              ],
            ),
          ],
        ),
      );
      await open(tester, project: project);

      expect(
        tester.widget<EditableText>(field('firebaseIos')).controller.text,
        '1:1:ios:b',
      );
      expect(tester.widget<EditableText>(field('apple')).controller.text, '9');
      await tap(tester, find.text('Save ids'));
      expect(find.text('Not a Firebase app id.'), findsOneWidget);
    });

    testWidgets('waits for the engine to save', (tester) async {
      await open(tester, status: EngineStatus.unreachable);

      await tap(tester, find.text('Save ids'));

      verifyNever(() => projects.editProject(any(), any()));
    });
  });

  test('flavorOf finds the flavor a target names, if it is there', () {
    expect(flavorOf(mataa, (app: '.', appName: 'x', flavor: 'nope')), isNull);
  });
}
