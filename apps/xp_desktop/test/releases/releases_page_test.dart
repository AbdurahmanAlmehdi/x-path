import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/credentials/view/flavor_credentials_sheet.dart';
import 'package:xp_desktop/dispatch/dispatch.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/releases/releases.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../dispatch/dispatch_harness.dart';
import '../helpers/approval_fixtures.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';
import 'releases_harness.dart';

Release _noKey({StoreState apple = StoreState.uploaded}) => reviewRelease(
  stores: [
    lane(
      ReleaseStore.apple,
      apple,
      source: StatusSource.lookup,
      detail: 'On sale: 5.3.7',
      changedAt: oct12(18, 52),
    ),
    lane(ReleaseStore.play, StoreState.inReview, changedAt: oct12(19, 40)),
  ],
);

/// The confirming button [label] of the open confirmation.
Finder confirm(String label) => find.descendant(
  of: find.byType(XpConfirmDialog),
  matching: find.text(label),
);

void main() {
  late List<String?> clipboard;

  setUpAll(() {
    registerFallbackValue(ReleaseStore.apple);
    registerFallbackValue(StoreState.live);
  });

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  group('ReleasesPage', () {
    testWidgets('shows the release in flight and switches release', (
      tester,
    ) async {
      final harness = ReleasesHarness();
      when(() => harness.releasesRepository.notes('rel_1'))
          .thenThrow(const ApiException('No commit yet.', statusCode: 409));
      await harness.pump(tester);
      expect(find.text('Release 5.4.1 (3283)'), findsOneWidget);
      expect(find.text('Waiting for review'), findsOneWidget);
      expect(find.text('Waits for both stores to go live'), findsOneWidget);
      expect(find.text('Live now 5.3.7'), findsNWidgets(2));

      await tester.tap(find.text('5.4.1 (3283) · prod · In review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5.3.7 (3200) · prod · Live').last);
      await tester.pumpAndSettle();
      expect(find.text('Release 5.3.7 (3200)'), findsOneWidget);
      expect(find.text('No commit yet.'), findsOneWidget);
      expect(find.text('Live on both stores'), findsOneWidget);
    });

    testWidgets('refreshes, opens the job and copies the notes', (
      tester,
    ) async {
      final shell = ShellCubit();
      final harness = ReleasesHarness();
      when(() => harness.releasesRepository.refresh('rel_2'))
          .thenAnswer((_) async => reviewRelease());
      await harness.pump(tester, shell: shell, releaseId: 'rel_2');

      await tester.tap(find.text('Refresh'));
      await tester.pump();
      verify(() => harness.releasesRepository.refresh('rel_2')).called(1);

      await tester.tap(find.text('Copy for Slack'));
      await tester.pump();
      expect(clipboard, ['*5.4.1 (3283)*']);
      expect(find.text('Copied'), findsOneWidget);
      await tester.tap(find.text('Copy for WhatsApp'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Copied'), findsNothing);
      await tester.tap(find.text('Copy link'));
      await tester.pump(const Duration(seconds: 2));
      expect(clipboard.last, 'https://github.com/acme/mataa_new_app/pull/42');

      await tester.tap(find.text('Open job'));
      expect(shell.state, const JobDestination('run_1', projectId: 'prj_1'));
    });

    testWidgets('marks a store it cannot read by hand', (tester) async {
      final shell = ShellCubit();
      final harness = ReleasesHarness(
        credentials: const [playAccount],
        releases: [_noKey(), liveRelease],
      );
      final repository = harness.releasesRepository;
      when(() => repository.setStoreStatus('rel_2', any(), any()))
          .thenAnswer((_) async => reviewRelease());
      await harness.pump(tester, shell: shell);
      expect(find.text('Unknown'), findsNWidgets(2));
      expect(find.textContaining('On sale: 5.3.7'), findsOneWidget);
      expect(
        find.text('Mark App Store live and Google Play must go live'),
        findsOneWidget,
      );

      await tester.tap(find.text('Mark approved'));
      await tester.pumpAndSettle();
      expect(find.byType(XpConfirmDialog), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      verifyNever(() => repository.setStoreStatus(any(), any(), any()));

      await tester.tap(find.text('Mark approved'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('Mark approved'));
      await tester.pumpAndSettle();
      verify(
        () => repository.setStoreStatus(
          'rel_2',
          ReleaseStore.apple,
          StoreState.approved,
        ),
      ).called(1);
      await tester.tap(find.text('Mark live'));
      await tester.pumpAndSettle();
      await tester.tap(confirm('Mark live'));
      await tester.pumpAndSettle();
      verify(
        () => repository.setStoreStatus(
          'rel_2',
          ReleaseStore.apple,
          StoreState.live,
        ),
      ).called(1);
      await tester.tap(find.text('Add API key…'));
      await tester.pumpAndSettle();
      expect(find.byType(FlavorCredentialsSheet), findsOneWidget);
      expect(shell.state, const HomeDestination());
    });

    testWidgets('marks an approved App Store and Google Play live', (
      tester,
    ) async {
      final harness = ReleasesHarness(
        credentials: const [],
        releases: [_noKey(apple: StoreState.approved)],
      );
      final repository = harness.releasesRepository;
      when(() => repository.setStoreStatus('rel_2', any(), any()))
          .thenAnswer((_) async => reviewRelease());
      await harness.pump(tester);
      expect(find.text('Mark approved'), findsNothing);
      expect(find.text('Approved'), findsWidgets);
      expect(find.text('Add service account…'), findsOneWidget);
      expect(
        find.text('Mark App Store live and Mark Google Play live'),
        findsOneWidget,
      );
      await tester.tap(find.text('Mark live').last);
      await tester.pumpAndSettle();
      await tester.tap(confirm('Mark live'));
      await tester.pumpAndSettle();
      verify(
        () => repository.setStoreStatus(
          'rel_2',
          ReleaseStore.play,
          StoreState.live,
        ),
      ).called(1);
    });

    testWidgets('merges once both stores are live, and says what failed', (
      tester,
    ) async {
      final harness = ReleasesHarness(
        releases: [
          reviewRelease(
            state: ReleaseState.live,
            mergeEnabled: true,
            stores: [
              lane(
                ReleaseStore.apple,
                StoreState.live,
                changedAt: oct12(20, 0),
              ),
              lane(ReleaseStore.play, StoreState.live, changedAt: oct12(20, 0)),
            ],
          ),
        ],
      );
      when(() => harness.releasesRepository.merge('rel_2'))
          .thenThrow(const ApiException('GitHub said no.', statusCode: 502));
      await harness.pump(tester);
      expect(find.text('release/5.4.1 → main · both stores live'), findsOne);
      expect(find.textContaining('every store has it live'), findsOneWidget);
      await tester.tap(find.text('Merge into main'));
      await tester.pump();
      expect(find.text('GitHub said no.'), findsOneWidget);
    });

    testWidgets('builds a rejected version again after asking', (tester) async {
      final shell = ShellCubit();
      final harness = ReleasesHarness(
        releases: [
          reviewRelease(
            state: ReleaseState.rejected,
            stores: [
              lane(ReleaseStore.apple, StoreState.rejected),
              lane(ReleaseStore.play, StoreState.inReview),
            ],
          ),
        ],
      );
      when(() => harness.releasesRepository.startBuild('rel_2'))
          .thenAnswer((_) async => runningRun().run);
      await harness.pump(tester, shell: shell);
      expect(find.text('Rejected by App Store'), findsOneWidget);
      expect(find.text('App Store rejected this build'), findsOneWidget);
      expect(
        find.textContaining('A new build replaces 3283 here too'),
        findsOneWidget,
      );

      await tester.tap(find.text('New build, same version…'));
      await tester.pumpAndSettle();
      expect(find.text('Build 5.4.1 again?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => harness.releasesRepository.startBuild(any()));

      await tester.tap(find.text('New build, same version…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start new build'));
      await tester.pumpAndSettle();
      verify(() => harness.releasesRepository.startBuild('rel_2')).called(1);
      expect(shell.state, const JobDestination('run_1', projectId: 'prj_1'));
    });

    testWidgets('a merged release opens its merge job', (tester) async {
      final shell = ShellCubit();
      await ReleasesHarness(
        releases: [
          reviewRelease(
            state: ReleaseState.merged,
            mergeRunId: 'run_9',
            mergeCommit: 'abcdef0123456',
            stores: [
              lane(
                ReleaseStore.apple,
                StoreState.live,
                changedAt: oct12(20, 0),
              ),
            ],
          ),
        ],
      ).pump(tester, shell: shell);
      expect(find.text('Merged · abcdef0'), findsOneWidget);
      expect(find.text('Merged into main'), findsOneWidget);
      expect(find.text('Merge into main'), findsNothing);
      expect(
        find.text('This release does not go to Google Play.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Open merge job'));
      expect(shell.state, const JobDestination('run_9', projectId: 'prj_1'));
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      await ReleasesHarness(releases: [_noKey()]).pump(
        tester,
        connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
      );
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(find.text('Read-only while the engine is away'), findsNothing);
    });

    testWidgets('says when there is no release, or no project', (tester) async {
      await ReleasesHarness(releases: const [])
          .pump(tester, workflows: DispatchHarness().workflows);
      expect(
        find.text(
          'A production release dispatched from the overview shows '
          'up here.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Dispatch Prod release…'));
      await tester.pumpAndSettle();
      expect(find.byType(DispatchSheet), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpApp(
        const ReleasesPage(projectId: 'prj_9'),
        projects: projectsIn(const ProjectsState(loaded: true)),
      );
      expect(find.text('Releases'), findsOneWidget);
    });
  });

  testWidgets('the panels say what the release does not have yet', (
    tester,
  ) async {
    final building = Release(
      id: 'rel_3',
      projectId: 'prj_1',
      app: '.',
      flavor: 'prod',
      version: '5.5.0',
      build: 3290,
      state: ReleaseState.building,
      stores: [
        lane(ReleaseStore.apple, StoreState.live, changedAt: oct12(20, 0)),
        lane(
          ReleaseStore.play,
          StoreState.uploaded,
          note: 'Google Play: the service account has no access.',
        ),
      ],
      builds: const [],
      mergeEnabled: false,
      prNumber: 7,
      createdAt: oct12(20, 0),
      updatedAt: oct12(20, 0),
    );
    await ReleasesHarness(releases: [building]).pump(
      tester,
      connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
    );
    expect(
      find.text('The notes are ready once the release is tagged.'),
      findsOneWidget,
    );
    expect(
      find.text('The release is tagged when its build is recorded.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Raise min_version_android once Google Play is live'),
      findsOneWidget,
    );
    expect(
      find.text('Google Play: the service account has no access.'),
      findsOneWidget,
    );
  });

  testWidgets('notes without a release before, or without commits', (
    tester,
  ) async {
    final harness = ReleasesHarness(releases: [reviewRelease()]);
    when(() => harness.releasesRepository.notes('rel_2')).thenAnswer(
      (_) async => const ReleaseNotes(
        releaseId: 'rel_2',
        version: '5.4.1',
        build: 3283,
        to: sha,
        commits: 0,
        groups: [],
        slack: '',
        whatsapp: '',
      ),
    );
    await harness.pump(tester);
    expect(find.text('0 commits'), findsOneWidget);
    expect(
      find.text('Nothing changed since the release before.'),
      findsOneWidget,
    );
  });

  testWidgets('the notes wait for the engine', (tester) async {
    final harness = ReleasesHarness(releases: [reviewRelease()]);
    when(() => harness.releasesRepository.notes('rel_2'))
        .thenAnswer((_) => Completer<ReleaseNotes>().future);
    await harness.pump(tester);
    expect(find.text('RELEASE NOTES'), findsOneWidget);
    expect(find.text('Copy for Slack'), findsNothing);
  });

  group('the board', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('mergeCaption says why Merge sleeps', () {
      final board = ReleaseBoardState(
        credentials: const [verifiedKey, playAccount],
        approvals: [
          Approval(
            id: 'apr_m',
            projectId: 'prj_1',
            action: 'merge',
            sha: sha,
            runId: 'run_m',
            state: ApprovalState.pending,
            createdAt: oct12(20, 0),
            expiresAt: oct12(23, 0),
          ),
        ],
      );
      String caption(Release release) => mergeCaption(release, board, l10n);
      final live = [
        lane(ReleaseStore.apple, StoreState.live),
        lane(ReleaseStore.play, StoreState.live),
      ];
      expect(
        caption(reviewRelease(state: ReleaseState.abandoned)),
        'The release was abandoned',
      );
      expect(
        caption(reviewRelease(state: ReleaseState.live, mergeRunId: 'run_m')),
        'Merge requested · waits for your approval',
      );
      expect(
        caption(reviewRelease(state: ReleaseState.live, mergeRunId: 'run_x')),
        'Merge requested',
      );
      expect(
        caption(reviewRelease(state: ReleaseState.live, stores: live)),
        'Both stores live',
      );
      expect(
        caption(
          reviewRelease(state: ReleaseState.live, stores: live, prNumber: null),
        ),
        'The release has no pull request yet',
      );
      expect(
        caption(
          reviewRelease(
            stores: [
              lane(ReleaseStore.apple, StoreState.live),
              lane(ReleaseStore.play, StoreState.inReview),
            ],
          ),
        ),
        'Waits for Google Play to go live',
      );
      expect(
        caption(
          reviewRelease(
            stores: [
              lane(ReleaseStore.apple, StoreState.rejected),
              lane(ReleaseStore.play, StoreState.rejected),
            ],
          ),
        ),
        'App Store and Google Play rejected this build',
      );
      expect(
        l10n.releaseHero(
          reviewRelease(
            state: ReleaseState.rejected,
            stores: [
              lane(ReleaseStore.apple, StoreState.rejected),
              lane(ReleaseStore.play, StoreState.rejected),
            ],
          ),
        ),
        'Rejected by both stores',
      );
      expect(
        l10n.releaseHero(
          reviewRelease(
            state: ReleaseState.live,
            stores: [lane(ReleaseStore.play, StoreState.live)],
          ),
        ),
        'Live on Google Play',
      );
      final noBranch = Release(
        id: 'rel_x',
        projectId: 'prj_1',
        app: '.',
        flavor: 'prod',
        version: '1.0.0',
        build: 1,
        state: ReleaseState.live,
        stores: const [],
        builds: const [],
        mergeEnabled: true,
        createdAt: oct12(1, 0),
        updatedAt: oct12(1, 0),
      );
      expect(caption(noBranch), 'Both stores live');
    });

    test('laneSteps follows the review, or what it cannot know', () {
      String phases(StoreStatus status, {bool manual = false}) => [
        for (final step in laneSteps(status, manual: manual, l10n: l10n))
          '${step.label}:${step.phase.name}:${step.time ?? ''}',
      ].join(' | ');
      expect(
        phases(lane(ReleaseStore.play, StoreState.pending)),
        'Uploaded:todo: | In review:todo: | Approved:todo: | Published:todo:',
      );
      expect(
        phases(lane(ReleaseStore.apple, StoreState.uploaded), manual: true),
        'Uploaded:done: | Unknown:now:no API key | Ready for sale:todo:',
      );
      expect(
        phases(
          lane(ReleaseStore.play, StoreState.live, changedAt: oct12(9, 5)),
          manual: true,
        ),
        'Uploaded:done: | Unknown:done: | Published:now:Oct 12 09:05',
      );
      expect(
        phases(lane(ReleaseStore.play, StoreState.pending), manual: true),
        'Uploaded:todo: | Unknown:todo: | Published:todo:',
      );
      expect(
        phases(lane(ReleaseStore.play, StoreState.uploaded), manual: true),
        'Uploaded:done: | Unknown:now:no service account | Published:todo:',
      );
      expect(
        phases(
          lane(ReleaseStore.apple, StoreState.approved, changedAt: oct12(9, 5)),
        ),
        'Uploaded:done: | In review:done: | Approved:now:since 09:05 | '
        'Ready for sale:todo:',
      );
    });

    test('releaseTimeline tells decisions, merges and abandonment', () {
      final release = reviewRelease(
        state: ReleaseState.abandoned,
        message: 'Wrong flavor',
      );
      final entries = releaseTimeline(release, [
        decided(pendingApproval, reason: 'ok'),
        decided(pendingApproval, state: ApprovalState.expired),
        mergeApproval,
      ], l10n);
      expect(
        entries.map((entry) => entry.title),
        containsAll([
          'Abandoned',
          'Submit 5.4.1 (3283) to the stores: approved',
          'Submit 5.4.1 (3283) to the stores: expired',
        ]),
      );
      expect(entries.first.props, hasLength(4));
      expect(
        l10n.statusSource(ReleaseStore.apple, StatusSource.manual),
        'Marked by hand',
      );
      expect(
        l10n.statusSource(ReleaseStore.apple, StatusSource.upload),
        'Upload step',
      );
    });
  });
}
