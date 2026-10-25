import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/local_engine/local_engine.dart';
import 'package:xp_desktop/settings/settings.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  const missing = GitHubTokenStatus(stored: false);
  const connected = GitHubTokenStatus(
    stored: true,
    status: CredentialStatus.verified,
    login: 'octo',
  );

  late MockSettingsRepository settings;
  late MockEnginesRepository engines;
  late FakeEngineAgent agent;
  late FakeCliLinker linker;
  late FakeDataWiper data;
  late FakeKeychainWiper keychain;
  late FakeRunningApp app;

  setUp(() {
    settings = quietSettings(token: missing);
    engines = noEngines();
    agent = FakeEngineAgent(current: AgentStatus.enabled);
    linker = FakeCliLinker();
    data = FakeDataWiper(folders: const ['/data/XPath']);
    keychain = FakeKeychainWiper(count: 4);
    app = FakeRunningApp();
    when(engines.revokeLocalRunners).thenAnswer((_) async => 1);
    when(engines.waitForLocalEngineToStop).thenAnswer((_) async => true);
  });

  Future<void> pump(
    WidgetTester tester, {
    bool github = false,
    EngineStatus status = EngineStatus.connected,
    LocalEngineBloc? localEngine,
    List<EngineProfile>? engineList,
    RunnersRepository? runners,
  }) async {
    await tester.pumpApp(
      SettingsPage(github: github),
      settingsRepository: settings,
      runnersRepository: runners,
      connection: connectionIn(
        connectedTo(status: status, engines: engineList),
      ),
      localEngine: localEngine,
      services: testServices(
        engines: engines,
        agent: agent,
        linker: linker,
        dataWiper: data,
        keychainWiper: keychain,
        runningApp: app,
      ),
    );
    // Tall enough for the whole page, so every section is built.
    tester.view.physicalSize = const Size(1440, 1400);
    await tester.pumpAndSettle();
  }

  group('CliTokenSection', () {
    TokenInfo info(DeviceTokenKind kind) => TokenInfo(
      id: 'tok_1',
      name: kind == DeviceTokenKind.cli ? 'xp on MacBook' : 'Agent on MacBook',
      kind: kind,
      createdAt: DateTime.utc(2026, 10, 25),
    );

    setUp(() {
      for (final kind in [DeviceTokenKind.cli, DeviceTokenKind.mcp]) {
        when(() => settings.createToken(name: info(kind).name, kind: kind))
            .thenAnswer(
              (_) async =>
                  CreatedToken(info: info(kind), token: 'xpt_${kind.name}'),
            );
      }
    });

    testWidgets('makes an xp token and shows the connect command once', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('New xp token'));
      await tester.pumpAndSettle();
      expect(
        find.text('xp connect http://127.0.0.1:7480 --token xpt_cli'),
        findsOne,
      );
      expect(find.text('Copy command'), findsOne);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.textContaining('xpt_cli'), findsNothing);
    });

    testWidgets('makes an agent token with its MCP config', (tester) async {
      await pump(tester);

      await tester.tap(find.text('New agent token'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"XP_MCP_TOKEN": "xpt_mcp"'), findsOne);
      expect(find.text('Copy config'), findsOne);
    });

    testWidgets('says why no token was made', (tester) async {
      when(
        () => settings.createToken(
          name: 'xp on MacBook',
          kind: DeviceTokenKind.cli,
        ),
      ).thenThrow(const ConnectionException('The engine is away.'));
      await pump(tester);

      await tester.tap(find.text('New xp token'));
      await tester.pumpAndSettle();
      expect(find.text('The engine is away.'), findsOne);
    });
  });

  test('connectCommand and mcpConfig put the URL and token in place', () {
    final url = Uri.parse('https://mac.example');

    expect(
      connectCommand(url, 'xpt_x'),
      'xp connect https://mac.example --token xpt_x',
    );
    expect(
      mcpConfig(url, 'xpt_y'),
      contains('"XP_ENGINE_URL": "https://mac.example"'),
    );
  });

  group('RunnerUrlSection', () {
    testWidgets('shows the URL with its warning, saves and clears it', (
      tester,
    ) async {
      final runners = quietRunners();
      const plain = RunnerUrl(
        url: 'http://a.example',
        warning: 'Plain http carries signing material.',
      );
      when(runners.runnerUrl).thenAnswer((_) async => plain);
      when(() => runners.setRunnerUrl('https://mac.tailnet.ts.net')).thenAnswer(
        (_) async => const RunnerUrl(url: 'https://mac.tailnet.ts.net'),
      );
      when(() => runners.setRunnerUrl(null))
          .thenAnswer((_) async => const RunnerUrl());
      await pump(tester, runners: runners);

      expect(
        find.text('Runners reach the engine at http://a.example.'),
        findsOne,
      );
      expect(find.text('Plain http carries signing material.'), findsOne);

      await tester.enterText(
        find.byKey(const Key('settings.runnerUrl')),
        'https://mac.tailnet.ts.net',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings.runnerUrlSave')));
      await tester.pumpAndSettle();
      expect(
        find.text('Runners reach the engine at https://mac.tailnet.ts.net.'),
        findsOne,
      );
      expect(find.text('Plain http carries signing material.'), findsNothing);

      await tester.tap(find.byKey(const Key('settings.runnerUrlClear')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No runner URL is set'), findsOne);
    });

    testWidgets('says what the engine refused', (tester) async {
      final runners = quietRunners();
      when(() => runners.setRunnerUrl('ftp://a')).thenThrow(
        const ApiException('"ftp://a" is not a runner URL.', statusCode: 400),
      );
      await pump(tester, runners: runners);

      await tester.enterText(
        find.byKey(const Key('settings.runnerUrl')),
        'ftp://a',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings.runnerUrlSave')));
      await tester.pumpAndSettle();

      expect(find.text('"ftp://a" is not a runner URL.'), findsOne);
    });
  });

  group('SettingsPage', () {
    testWidgets('shows the versions, the engine and its login item', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('0.0.1 (1)'), findsOneWidget);
      expect(find.text('0.0.1 (API v1)'), findsOneWidget);
      expect(find.text('This Mac'), findsOneWidget);
      expect(find.text('http://127.0.0.1:7480'), findsOneWidget);
      expect(find.text('Runs at login'), findsOneWidget);
    });

    testWidgets('says why the engine version is unknown', (tester) async {
      when(settings.engineVersion)
          .thenThrow(const ConnectionException('Cannot reach the engine.'));
      agent.current = AgentStatus.requiresApproval;

      await pump(tester);

      expect(find.text('Cannot reach the engine.'), findsOneWidget);
      expect(find.text('Waiting for you in Login Items'), findsOneWidget);
    });

    group('Engine on this Mac', () {
      LocalEngineState failed(LocalEngineFailure failure) => LocalEngineState(
        running: false,
        progress: LocalEngineProgress.failed,
        failure: failure,
      );

      testWidgets('asks whether it runs, and says it does', (tester) async {
        final local = localEngineIn(const LocalEngineState(running: true));
        await pump(tester, localEngine: local);

        verify(() => local.add(const LocalEngineChecked())).called(1);
        expect(find.text('Running'), findsOneWidget);
        expect(find.byKey(const Key('settings.startEngine')), findsNothing);
      });

      testWidgets('starts it when it does not run', (tester) async {
        final local = localEngineIn(const LocalEngineState(running: false));
        await pump(tester, localEngine: local);

        expect(find.text('Not running'), findsOneWidget);
        await tester.tap(find.byKey(const Key('settings.startEngine')));
        verify(
          () => local.add(
            const LocalEngineStartRequested(tokenName: 'XPath app on MacBook'),
          ),
        ).called(1);
      });

      testWidgets('shows the start in progress', (tester) async {
        await pump(
          tester,
          localEngine: localEngineIn(
            const LocalEngineState(
              running: false,
              progress: LocalEngineProgress.starting,
            ),
          ),
        );

        expect(find.text('Starting…'), findsOneWidget);
        final button = tester.widget<XpButton>(
          find.byKey(const Key('settings.startEngine')),
        );
        expect(button.busy, isTrue);
        expect(button.onPressed, isNull);
      });

      testWidgets('says why it did not start and opens Login Items', (
        tester,
      ) async {
        final local = localEngineIn(failed(LocalEngineFailure.needsApproval));
        await pump(tester, localEngine: local);

        expect(find.textContaining('Login Items, then start'), findsOneWidget);
        await tester.tap(find.text('Open Login Items…'));
        verify(() => local.add(const LocalEngineLoginItemsRequested()))
            .called(1);
      });

      testWidgets('offers no start without an engine set up on this Mac', (
        tester,
      ) async {
        agent.current = AgentStatus.notRegistered;
        await pump(
          tester,
          engineList: [macMini],
          localEngine: localEngineIn(const LocalEngineState(running: false)),
        );

        expect(find.text('Not running'), findsOneWidget);
        expect(find.byKey(const Key('settings.startEngine')), findsNothing);
      });
    });

    test('names every login item status', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        [
          for (final status in AgentStatus.values)
            agentStatusLabel(l10n, status),
        ],
        [
          'Not running',
          'Runs at login',
          'Waiting for you in Login Items',
          'Not in this build',
          'Needs macOS 13',
        ],
      );
      expect(agentStatusLabel(l10n, null), 'Unknown');
    });
  });

  group('CommandLineToolSection', () {
    final status = find.byKey(const Key('settings.cliStatus'));
    final button = find.byKey(const Key('settings.cliLink'));

    testWidgets('links xp when it is not linked', (tester) async {
      await pump(tester);

      expect(
        find.descendant(
          of: status,
          matching: find.text(
            'xp is not linked, so a terminal cannot find it.',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: button, matching: find.text('Link xp')),
      );
      await tester.pumpAndSettle();

      expect(linker.links, 1);
      expect(find.text('Linked at /usr/local/bin/xp.'), findsOneWidget);
      expect(button, findsNothing);
    });

    testWidgets('links xp again over a link into another copy', (tester) async {
      linker.current = const CliLink(
        CliLinkState.elsewhere,
        path: '/usr/local/bin/xp',
        pointsTo: '/Volumes/Old/XPath.app/Contents/Helpers/xp/bin/xp',
      );
      await pump(tester);

      expect(
        find.text(
          '/usr/local/bin/xp links to another copy of XPath '
          '(/Volumes/Old/XPath.app/Contents/Helpers/xp/bin/xp). Link xp '
          'again to use this one.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Link xp again'));
      await tester.pumpAndSettle();

      expect(linker.links, 1);
      expect(find.text('Linked at /usr/local/bin/xp.'), findsOneWidget);
    });

    testWidgets('says when another xp is in the way', (tester) async {
      linker
        ..current = const CliLink(
          CliLinkState.conflict,
          path: '/usr/local/bin/xp',
        )
        ..result = const CliLink(
          CliLinkState.conflict,
          path: '/usr/local/bin/xp',
        );
      await pump(tester);

      expect(
        find.text('/usr/local/bin/xp is another xp. XPath left it alone.'),
        findsOneWidget,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(linker.links, 1);
      expect(button, findsOneWidget);
    });

    testWidgets('offers no link when this build has no xp', (tester) async {
      linker.current = const CliLink(CliLinkState.missingBinary);
      await pump(tester);

      expect(find.text('This build has no xp inside it.'), findsOneWidget);
      expect(button, findsNothing);
    });

    testWidgets('looks for xp while the status loads', (tester) async {
      await tester.pumpApp(
        const SettingsPage(),
        settingsRepository: settings,
        services: testServices(linker: _SlowLinker()),
      );

      expect(find.text('Looking for xp…'), findsOneWidget);
      expect(button, findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });
  });

  group('GitHubTokenSection', () {
    final field = find.byKey(const Key('settings.githubToken'));
    final save = find.byKey(const Key('settings.githubSave'));

    testWidgets('saves a pasted token and clears the field', (tester) async {
      when(() => settings.setGitHubToken('ghp_new'))
          .thenAnswer((_) async => connected);
      await pump(tester, github: true);

      expect(
        find.text('The engine has no GitHub token, so it cannot add projects.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings.githubRemove')), findsNothing);
      await tester.enterText(field, ' ghp_new ');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      verify(() => settings.setGitHubToken('ghp_new')).called(1);
      expect(find.text('Connected to GitHub as octo.'), findsOneWidget);
      expect(find.text('ghp_new'), findsNothing);
    });

    testWidgets('imports the token of the GitHub CLI', (tester) async {
      when(settings.importGitHubToken).thenAnswer((_) async => connected);
      await pump(tester);

      await tester.tap(find.byKey(const Key('settings.githubImport')));
      await tester.pumpAndSettle();

      expect(find.text('Connected to GitHub as octo.'), findsOneWidget);
    });

    testWidgets('says why a token was not saved', (tester) async {
      when(() => settings.setGitHubToken('ghp_bad')).thenThrow(
        const ApiException(
          'GitHub refused the token.',
          statusCode: 422,
          code: ApiErrorCode.credentialRejected,
        ),
      );
      await pump(tester);

      await tester.enterText(field, 'ghp_bad');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text('Not saved: GitHub refused the token.'), findsOneWidget);
    });

    testWidgets('removes the stored token', (tester) async {
      settings = quietSettings();
      when(settings.clearGitHubToken).thenAnswer((_) async {});
      await pump(tester);

      expect(find.text('Connected to GitHub as octo.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings.githubRemove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove the GitHub token?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      verifyNever(settings.clearGitHubToken);

      await tester.tap(find.byKey(const Key('settings.githubRemove')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(confirmDialogKey),
          matching: find.text('Remove token'),
        ),
      );
      await tester.pumpAndSettle();

      verify(settings.clearGitHubToken).called(1);
      expect(
        find.text('The engine has no GitHub token, so it cannot add projects.'),
        findsOneWidget,
      );
    });

    testWidgets('shows what GitHub said of the stored token', (tester) async {
      for (final (status, text) in [
        (
          const GitHubTokenStatus(
            stored: true,
            status: CredentialStatus.rejected,
            message: 'GitHub refused the token.',
            fix: 'Save a new token.',
          ),
          "GitHub refused the engine's token: GitHub refused the token. "
              'Save a new token.',
        ),
        (
          const GitHubTokenStatus(
            stored: true,
            status: CredentialStatus.unreachable,
            message: 'GitHub is not reachable.',
          ),
          "GitHub could not check the engine's token: GitHub is not "
              'reachable.',
        ),
        (
          const GitHubTokenStatus(
            stored: true,
            status: CredentialStatus.verified,
          ),
          'Connected to GitHub.',
        ),
      ]) {
        settings = quietSettings(token: status);
        await tester.pumpWidget(const SizedBox());
        await pump(tester);
        expect(find.text(text), findsOneWidget);
      }
    });

    testWidgets('asks GitHub while the status loads', (tester) async {
      when(settings.gitHubToken).thenAnswer(
        (_) => Future.delayed(const Duration(seconds: 1), () => missing),
      );
      await tester.pumpApp(const SettingsPage(), settingsRepository: settings);
      await tester.pump();

      expect(find.text('Asking GitHub…'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    });

    testWidgets('changes nothing while the engine is offline', (tester) async {
      await pump(tester, status: EngineStatus.unreachable);
      await tester.enterText(field, 'ghp_new');
      await tester.pump();
      await tester.tap(save);
      await tester.tap(find.byKey(const Key('settings.githubImport')));
      await tester.pumpAndSettle();

      verifyNever(() => settings.setGitHubToken(any()));
      verifyNever(settings.importGitHubToken);
    });
  });

  group('RemoveXPathSheet', () {
    Future<void> openSheet(WidgetTester tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('settings.remove')));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps XPath with Keep or Escape', (tester) async {
      await openSheet(tester);
      expect(find.text('Remove XPath from this Mac?'), findsOneWidget);
      expect(
        find.text('The database, builds, logs and copies in /data/XPath.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep XPath'));
      await tester.pumpAndSettle();
      expect(find.text('Remove XPath from this Mac?'), findsNothing);

      await tester.tap(find.byKey(const Key('settings.remove')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(agent.unregistrations, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Remove XPath from this Mac?'), findsNothing);
      expect(agent.unregistrations, 0);
    });

    testWidgets('removes XPath with both options, then trashes and quits', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.tap(find.text('Also delete engine data'));
      await tester.tap(find.text('Also delete Keychain items'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remove.confirm')));
      await tester.pumpAndSettle();

      expect(find.text('XPath is removed from this Mac'), findsOneWidget);
      expect(find.text('1 runner revoked'), findsOneWidget);
      expect(find.text('4 items deleted'), findsOneWidget);
      expect((data.wipes, keychain.wipes), (1, 1));
      // The sheet cannot be dismissed once it started.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('XPath is removed from this Mac'), findsOneWidget);

      await tester.tap(find.byKey(const Key('remove.trash')));
      await tester.pumpAndSettle();
      expect((app.movedToTrash, app.quitted), (true, true));
    });

    testWidgets('says what failed and quits when the Trash refuses', (
      tester,
    ) async {
      when(engines.revokeLocalRunners)
          .thenThrow(const ConnectionException('Cannot reach the engine.'));
      when(engines.waitForLocalEngineToStop).thenAnswer((_) async => false);
      app.trashes = false;
      await openSheet(tester);

      await tester.tap(find.text('Also delete engine data'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('remove.confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Cannot reach the engine.'), findsOneWidget);
      expect(find.text('The engine did not stop in time.'), findsOneWidget);
      expect(find.text('Kept: the engine did not stop.'), findsOneWidget);
      expect(data.wipes, 0);

      await tester.tap(find.byKey(const Key('remove.trash')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('could not move itself to the Trash'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('remove.trash')), findsNothing);

      await tester.tap(find.byKey(const Key('remove.quit')));
      await tester.pumpAndSettle();
      expect(app.quitted, isTrue);
    });
  });
}

class _SlowLinker extends FakeCliLinker {
  @override
  Future<CliLink> status() =>
      Future.delayed(const Duration(seconds: 1), super.status);
}
