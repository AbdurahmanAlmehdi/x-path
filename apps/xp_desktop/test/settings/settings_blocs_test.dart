import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/app/bloc/engine_notices_bloc.dart';
import 'package:xp_desktop/settings/settings.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

import '../helpers/fakes.dart';

void main() {
  const version = VersionResponse(version: '0.0.1', apiVersion: '1');
  const missing = GitHubTokenStatus(stored: false);
  const connected = GitHubTokenStatus(
    stored: true,
    status: CredentialStatus.verified,
    login: 'octo',
  );

  group('SettingsBloc', () {
    late MockSettingsRepository settings;

    setUp(() => settings = quietSettings());

    test('events compare by value', () {
      expect(const SettingsStarted().props, isEmpty);
    });

    blocTest<SettingsBloc, SettingsState>(
      'reads the versions and the login item',
      build: () => SettingsBloc(
        app: FakeRunningApp(),
        agent: FakeEngineAgent(current: AgentStatus.enabled),
        settings: settings,
      ),
      act: (bloc) => bloc.add(const SettingsStarted()),
      expect: () => const [
        SettingsState(
          loaded: true,
          appVersion: '0.0.1 (1)',
          agentStatus: AgentStatus.enabled,
          engineVersion: version,
        ),
      ],
    );

    blocTest<SettingsBloc, SettingsState>(
      'says why the engine version could not be read',
      setUp: () =>
          when(settings.engineVersion)
              .thenThrow(const ConnectionException('Cannot reach the engine.')),
      build: () => SettingsBloc(
        app: FakeRunningApp(),
        agent: FakeEngineAgent(),
        settings: settings,
      ),
      act: (bloc) => bloc.add(const SettingsStarted()),
      expect: () => const [
        SettingsState(
          loaded: true,
          appVersion: '0.0.1 (1)',
          agentStatus: AgentStatus.notRegistered,
          engineError: 'Cannot reach the engine.',
        ),
      ],
    );
  });

  group('RunnerUrlBloc', () {
    late MockRunnersRepository runners;
    const url = RunnerUrl(url: 'https://mac.tailnet.ts.net');

    setUp(() => runners = quietRunners());

    test('events compare by value', () {
      expect(const RunnerUrlRequested().props, isEmpty);
      expect(const RunnerUrlCleared().props, isEmpty);
      expect(const RunnerUrlSaved('https://a').props, ['https://a']);
      expect(const RunnerUrlState().busy, isFalse);
      expect(
        const RunnerUrlState(command: RunnerUrlCommand.saving).busy,
        isTrue,
      );
    });

    blocTest<RunnerUrlBloc, RunnerUrlState>(
      'reads the runner URL',
      setUp: () => when(runners.runnerUrl).thenAnswer((_) async => url),
      build: () => RunnerUrlBloc(runners: runners),
      act: (bloc) => bloc.add(const RunnerUrlRequested()),
      expect: () => const [
        RunnerUrlState(command: RunnerUrlCommand.loading),
        RunnerUrlState(url: url),
      ],
    );

    blocTest<RunnerUrlBloc, RunnerUrlState>(
      'saves a trimmed URL and counts it',
      setUp: () =>
          when(() => runners.setRunnerUrl('https://mac.tailnet.ts.net'))
              .thenAnswer((_) async => url),
      build: () => RunnerUrlBloc(runners: runners),
      act: (bloc) =>
          bloc.add(const RunnerUrlSaved(' https://mac.tailnet.ts.net ')),
      expect: () => const [
        RunnerUrlState(command: RunnerUrlCommand.saving),
        RunnerUrlState(url: url, saved: 1),
      ],
    );

    blocTest<RunnerUrlBloc, RunnerUrlState>(
      'clears it',
      setUp: () =>
          when(() => runners.setRunnerUrl(null))
              .thenAnswer((_) async => const RunnerUrl()),
      build: () => RunnerUrlBloc(runners: runners),
      seed: () => const RunnerUrlState(url: url),
      act: (bloc) => bloc.add(const RunnerUrlCleared()),
      expect: () => const [
        RunnerUrlState(command: RunnerUrlCommand.clearing, url: url),
        RunnerUrlState(url: RunnerUrl(), saved: 1),
      ],
    );

    blocTest<RunnerUrlBloc, RunnerUrlState>(
      'keeps what it had and says why the engine refused',
      setUp: () => when(() => runners.setRunnerUrl('ftp://a')).thenThrow(
        const ApiException('"ftp://a" is not a runner URL.', statusCode: 400),
      ),
      build: () => RunnerUrlBloc(runners: runners),
      seed: () => const RunnerUrlState(url: url),
      act: (bloc) => bloc.add(const RunnerUrlSaved('ftp://a')),
      expect: () => const [
        RunnerUrlState(command: RunnerUrlCommand.saving, url: url),
        RunnerUrlState(url: url, error: '"ftp://a" is not a runner URL.'),
      ],
    );
  });

  group('GitHubTokenBloc', () {
    late MockSettingsRepository settings;

    setUp(() => settings = quietSettings(token: missing));

    test('events compare by value and never print the token', () {
      expect(const GitHubTokenRequested().props, isEmpty);
      expect(const GitHubTokenImported().props, isEmpty);
      expect(const GitHubTokenCleared().props, isEmpty);
      expect(const GitHubTokenSaved('ghp_x').props, ['ghp_x']);
      expect('${const GitHubTokenSaved('ghp_x')}', isNot(contains('ghp_x')));
    });

    test('needs a token when there is none or GitHub refuses it', () {
      expect(const GitHubTokenState().needsToken, isFalse);
      expect(const GitHubTokenState(status: missing).needsToken, isTrue);
      expect(const GitHubTokenState(status: connected).needsToken, isFalse);
      expect(
        const GitHubTokenState(
          status: GitHubTokenStatus(
            stored: true,
            status: CredentialStatus.rejected,
          ),
        ).needsToken,
        isTrue,
      );
    });

    blocTest<GitHubTokenBloc, GitHubTokenState>(
      'reads the status',
      build: () => GitHubTokenBloc(settings: settings),
      act: (bloc) => bloc.add(const GitHubTokenRequested()),
      expect: () => const [
        GitHubTokenState(command: GitHubTokenCommand.loading),
        GitHubTokenState(status: missing),
      ],
    );

    blocTest<GitHubTokenBloc, GitHubTokenState>(
      'saves a token and counts it',
      setUp: () =>
          when(() => settings.setGitHubToken('ghp_x'))
              .thenAnswer((_) async => connected),
      build: () => GitHubTokenBloc(settings: settings),
      seed: () => const GitHubTokenState(status: missing),
      act: (bloc) => bloc.add(const GitHubTokenSaved('ghp_x')),
      expect: () => const [
        GitHubTokenState(command: GitHubTokenCommand.saving, status: missing),
        GitHubTokenState(status: connected, saved: 1),
      ],
    );

    blocTest<GitHubTokenBloc, GitHubTokenState>(
      'says why a token was not saved, and keeps the status',
      setUp: () => when(() => settings.setGitHubToken('ghp_bad')).thenThrow(
        const ApiException(
          'GitHub refused the token.',
          statusCode: 422,
          code: ApiErrorCode.credentialRejected,
        ),
      ),
      build: () => GitHubTokenBloc(settings: settings),
      seed: () => const GitHubTokenState(status: missing),
      act: (bloc) => bloc.add(const GitHubTokenSaved('ghp_bad')),
      expect: () => const [
        GitHubTokenState(command: GitHubTokenCommand.saving, status: missing),
        GitHubTokenState(status: missing, error: 'GitHub refused the token.'),
      ],
    );

    blocTest<GitHubTokenBloc, GitHubTokenState>(
      "imports the GitHub CLI's token",
      setUp: () =>
          when(settings.importGitHubToken).thenAnswer((_) async => connected),
      build: () => GitHubTokenBloc(settings: settings),
      act: (bloc) => bloc.add(const GitHubTokenImported()),
      expect: () => const [
        GitHubTokenState(command: GitHubTokenCommand.importing),
        GitHubTokenState(status: connected, saved: 1),
      ],
    );

    blocTest<GitHubTokenBloc, GitHubTokenState>(
      'removes the token',
      setUp: () => when(settings.clearGitHubToken).thenAnswer((_) async {}),
      build: () => GitHubTokenBloc(settings: settings),
      seed: () => const GitHubTokenState(status: connected, saved: 1),
      act: (bloc) => bloc.add(const GitHubTokenCleared()),
      expect: () => const [
        GitHubTokenState(
          command: GitHubTokenCommand.clearing,
          status: connected,
          saved: 1,
        ),
        GitHubTokenState(status: missing, saved: 1),
      ],
      verify: (_) => verify(settings.clearGitHubToken).called(1),
    );
  });

  group('CliTokenBloc', () {
    final created = CreatedToken(
      info: TokenInfo(
        id: 'tok_1',
        name: 'xp on MacBook',
        kind: DeviceTokenKind.cli,
        createdAt: DateTime.utc(2026, 10, 25),
      ),
      token: 'xpt_x',
    );
    late MockSettingsRepository settings;

    setUp(() => settings = quietSettings());

    test('events compare by value', () {
      expect(
        const CliTokenRequested(name: 'xp', kind: DeviceTokenKind.cli).props,
        ['xp', DeviceTokenKind.cli],
      );
      expect(const CliTokenDismissed().props, isEmpty);
    });

    blocTest<CliTokenBloc, CliTokenState>(
      'makes a token, then forgets it',
      setUp: () => when(
        () => settings.createToken(
          name: 'xp on MacBook',
          kind: DeviceTokenKind.cli,
        ),
      ).thenAnswer((_) async => created),
      build: () => CliTokenBloc(settings: settings),
      act: (bloc) async {
        bloc.add(
          const CliTokenRequested(
            name: 'xp on MacBook',
            kind: DeviceTokenKind.cli,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(const CliTokenDismissed());
      },
      expect: () => [
        const CliTokenState(creating: DeviceTokenKind.cli),
        CliTokenState(created: created),
        const CliTokenState(),
      ],
    );

    blocTest<CliTokenBloc, CliTokenState>(
      'says why the engine made none',
      setUp: () => when(
        () => settings.createToken(name: 'agent', kind: DeviceTokenKind.mcp),
      ).thenThrow(const ConnectionException('The engine is away.')),
      build: () => CliTokenBloc(settings: settings),
      act: (bloc) => bloc.add(
        const CliTokenRequested(name: 'agent', kind: DeviceTokenKind.mcp),
      ),
      expect: () => const [
        CliTokenState(creating: DeviceTokenKind.mcp),
        CliTokenState(error: 'The engine is away.'),
      ],
    );
  });

  group('NoticeSettingsCubit', () {
    test('reads, keeps and passes on the choices', () async {
      final preferences = AppPreferences({
        'mutedNotices': ['jobSucceeded'],
      });
      final app = FakeRunningApp();
      final cubit = NoticeSettingsCubit(preferences: preferences, app: app);

      expect(cubit.state.keepRunning, isTrue);
      expect(cubit.state.shows(NoticeKind.jobSucceeded), isFalse);
      expect(cubit.state.shows(NoticeKind.jobFailed), isTrue);

      await cubit.setKeepRunning(keep: false);
      await cubit.show(NoticeKind.jobSucceeded, shown: true);
      await cubit.show(NoticeKind.releaseLive, shown: false);

      expect(cubit.state.keepRunning, isFalse);
      expect(cubit.state.muted, {NoticeKind.releaseLive});
      expect(app.keepRunning, isFalse);
      expect(preferences.keepRunning, isFalse);
      expect(preferences.mutedNotices, {'releaseLive'});
      await cubit.close();
    });
  });

  group('CommandLineToolBloc', () {
    const linked = CliLink(CliLinkState.linked, path: '/usr/local/bin/xp');
    const elsewhere = CliLink(
      CliLinkState.elsewhere,
      path: '/usr/local/bin/xp',
      pointsTo: '/Volumes/Old/XPath.app/Contents/Helpers/xp/bin/xp',
    );
    late FakeCliLinker linker;

    setUp(() => linker = FakeCliLinker(current: elsewhere));

    test('events compare by value', () {
      expect(const CommandLineToolRequested().props, isEmpty);
      expect(const CommandLineToolLinkRequested().props, isEmpty);
    });

    blocTest<CommandLineToolBloc, CommandLineToolState>(
      'reads where xp stands',
      build: () => CommandLineToolBloc(linker: linker),
      act: (bloc) => bloc.add(const CommandLineToolRequested()),
      expect: () => const [CommandLineToolState(link: elsewhere)],
      verify: (_) => expect(linker.links, 0),
    );

    blocTest<CommandLineToolBloc, CommandLineToolState>(
      'links xp',
      build: () => CommandLineToolBloc(linker: linker),
      seed: () => const CommandLineToolState(link: elsewhere),
      act: (bloc) => bloc.add(const CommandLineToolLinkRequested()),
      expect: () => const [
        CommandLineToolState(link: elsewhere, linking: true),
        CommandLineToolState(link: linked),
      ],
      verify: (_) => expect(linker.links, 1),
    );
  });

  group('RemoveXPathBloc', () {
    late MockEnginesRepository engines;
    late FakeEngineAgent agent;
    late FakeCliLinker linker;
    late FakeDataWiper data;
    late FakeKeychainWiper keychain;
    late FakeRunningApp app;

    setUp(() {
      engines = MockEnginesRepository();
      agent = FakeEngineAgent(current: AgentStatus.enabled);
      linker = FakeCliLinker();
      data = FakeDataWiper();
      keychain = FakeKeychainWiper();
      app = FakeRunningApp();
      when(engines.revokeLocalRunners).thenAnswer((_) async => 2);
      when(engines.waitForLocalEngineToStop).thenAnswer((_) async => true);
    });

    RemoveXPathBloc build() => RemoveXPathBloc(
      engines: engines,
      agent: agent,
      linker: linker,
      data: data,
      keychain: keychain,
      app: app,
    );

    RemovalStepResult result(
      RemovalStep step,
      RemovalStepState state, {
      String? detail,
      int? count,
    }) => RemovalStepResult(step, state, detail: detail, count: count);

    test('events and results compare by value', () {
      expect(
        const RemoveXPathConfirmed(
          deleteData: true,
          deleteKeychain: false,
        ).props,
        [true, false],
      );
      expect(const RemoveXPathTrashRequested().props, isEmpty);
      expect(const RemoveXPathQuitRequested().props, isEmpty);
      expect(
        result(RemovalStep.cli, RemovalStepState.failed, detail: 'x').props,
        [RemovalStep.cli, RemovalStepState.failed, 'x', null],
      );
    });

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'revokes the runners, stops the engine and unlinks xp, and only that',
      build: build,
      act: (bloc) => bloc.add(
        const RemoveXPathConfirmed(deleteData: false, deleteKeychain: false),
      ),
      skip: 7,
      expect: () => [
        RemoveXPathState(
          phase: RemovalPhase.removed,
          steps: [
            result(RemovalStep.runners, RemovalStepState.done, count: 2),
            result(RemovalStep.engine, RemovalStepState.done),
            result(RemovalStep.cli, RemovalStepState.done),
          ],
        ),
      ],
      verify: (_) {
        expect(agent.unregistrations, 1);
        expect(linker.unlinks, 1);
        expect(data.wipes, 0);
        expect(keychain.wipes, 0);
        expect(app.quitted, isFalse);
      },
    );

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'shows each step as it runs, the data and Keychain last',
      build: build,
      act: (bloc) => bloc.add(
        const RemoveXPathConfirmed(deleteData: true, deleteKeychain: true),
      ),
      expect: () {
        final pending = [
          for (final step in RemovalStep.values)
            result(step, RemovalStepState.pending),
        ];
        final done = [
          result(RemovalStep.runners, RemovalStepState.done, count: 2),
          result(RemovalStep.engine, RemovalStepState.done),
          result(RemovalStep.cli, RemovalStepState.done),
          result(RemovalStep.data, RemovalStepState.done),
          result(RemovalStep.keychain, RemovalStepState.done, count: 3),
        ];
        List<RemovalStepResult> upTo(int index, RemovalStepState state) => [
          ...done.take(index),
          result(RemovalStep.values[index], state),
          ...pending.skip(index + 1),
        ];
        return [
          RemoveXPathState(phase: RemovalPhase.removing, steps: pending),
          for (var index = 0; index < done.length; index++) ...[
            RemoveXPathState(
              phase: RemovalPhase.removing,
              steps: upTo(index, RemovalStepState.working),
            ),
            RemoveXPathState(
              phase: RemovalPhase.removing,
              steps: [...done.take(index + 1), ...pending.skip(index + 1)],
            ),
          ],
          RemoveXPathState(phase: RemovalPhase.removed, steps: done),
        ];
      },
      verify: (_) => expect((data.wipes, keychain.wipes), (1, 1)),
    );

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'goes on when steps fail, but keeps the data of an engine that runs',
      setUp: () {
        when(engines.revokeLocalRunners)
            .thenThrow(const ConnectionException('Cannot reach the engine.'));
        when(engines.waitForLocalEngineToStop).thenAnswer((_) async => false);
        linker.result = const CliLink(CliLinkState.notLinked);
        keychain.error = const MacosServiceException('locked', 'Locked.');
      },
      build: () => RemoveXPathBloc(
        engines: engines,
        agent: agent,
        linker: _FailingLinker(),
        data: data,
        keychain: keychain,
        app: app,
      ),
      act: (bloc) => bloc.add(
        const RemoveXPathConfirmed(deleteData: true, deleteKeychain: true),
      ),
      skip: 10,
      expect: () => [
        RemoveXPathState(
          phase: RemovalPhase.removed,
          steps: [
            result(
              RemovalStep.runners,
              RemovalStepState.failed,
              detail: 'Cannot reach the engine.',
            ),
            result(RemovalStep.engine, RemovalStepState.failed),
            result(
              RemovalStep.cli,
              RemovalStepState.failed,
              detail: 'Permission denied',
            ),
            result(RemovalStep.data, RemovalStepState.skipped),
            result(
              RemovalStep.keychain,
              RemovalStepState.failed,
              detail: 'Locked.',
            ),
          ],
        ),
      ],
      verify: (_) => expect(data.wipes, 0),
    );

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'says what macOS refused when the login item stays',
      setUp: () => agent.unregisterError = const MacosServiceException(
        'unregister_failed',
        'Operation not permitted',
      ),
      build: build,
      act: (bloc) => bloc.add(
        const RemoveXPathConfirmed(deleteData: false, deleteKeychain: false),
      ),
      skip: 7,
      expect: () => [
        RemoveXPathState(
          phase: RemovalPhase.removed,
          steps: [
            result(RemovalStep.runners, RemovalStepState.done, count: 2),
            result(
              RemovalStep.engine,
              RemovalStepState.failed,
              detail: 'Operation not permitted',
            ),
            result(RemovalStep.cli, RemovalStepState.done),
          ],
        ),
      ],
    );

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'says what the file system refused when the data stays',
      setUp: () => data.error = const FileSystemException('Busy'),
      build: build,
      act: (bloc) => bloc.add(
        const RemoveXPathConfirmed(deleteData: true, deleteKeychain: false),
      ),
      skip: 8,
      expect: () => [
        isA<RemoveXPathState>().having(
          (state) => state.steps.last,
          'data',
          result(RemovalStep.data, RemovalStepState.failed, detail: 'Busy'),
        ),
        isA<RemoveXPathState>().having(
          (state) => state.phase,
          'phase',
          RemovalPhase.removed,
        ),
      ],
    );

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'moves the app to the Trash, then quits',
      build: build,
      seed: () => const RemoveXPathState(phase: RemovalPhase.removed),
      act: (bloc) => bloc.add(const RemoveXPathTrashRequested()),
      expect: () => const [RemoveXPathState(phase: RemovalPhase.leaving)],
      verify: (_) => expect((app.movedToTrash, app.quitted), (true, true)),
    );

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'stays when the Trash refuses',
      setUp: () => app.trashes = false,
      build: build,
      seed: () => const RemoveXPathState(phase: RemovalPhase.removed),
      act: (bloc) => bloc.add(const RemoveXPathTrashRequested()),
      expect: () => const [
        RemoveXPathState(phase: RemovalPhase.leaving),
        RemoveXPathState(phase: RemovalPhase.trashFailed),
      ],
      verify: (_) => expect(app.quitted, isFalse),
    );

    blocTest<RemoveXPathBloc, RemoveXPathState>(
      'quits without the Trash',
      build: build,
      act: (bloc) => bloc.add(const RemoveXPathQuitRequested()),
      expect: () => const <RemoveXPathState>[],
      verify: (_) => expect((app.movedToTrash, app.quitted), (false, true)),
    );
  });
}

class _FailingLinker extends FakeCliLinker {
  @override
  Future<CliLink> unlink() async =>
      const CliLink(CliLinkState.failed, detail: 'Permission denied');
}
