import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/releases/releases.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/release_fixtures.dart';

const _pause = RolloutRequest(
  store: ReleaseStore.apple,
  action: RolloutAction.pause,
);

void main() {
  late MockReleasesRepository releases;
  late MockApprovalsRepository approvals;
  late MockProjectsRepository projects;
  late StreamController<Snapshot<List<Release>>> list;

  setUp(() {
    releases = MockReleasesRepository();
    approvals = MockApprovalsRepository();
    projects = MockProjectsRepository();
    list = StreamController<Snapshot<List<Release>>>();
    when(() => releases.watchReleases(projectId: 'prj_1'))
        .thenAnswer((_) => list.stream);
    when(() => approvals.watchApprovals(projectId: 'prj_1'))
        .thenAnswer((_) => Stream.value(Snapshot([pendingApproval])));
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => Stream.value(const Snapshot([verifiedKey])));
    when(() => releases.notes('rel_2')).thenAnswer((_) async => reviewNotes);
    // The notes of the live release never arrive.
    when(() => releases.notes('rel_1'))
        .thenAnswer((_) => Completer<ReleaseNotes>().future);
  });

  tearDown(() => unawaited(list.close()));

  ReleaseBoardBloc build() => ReleaseBoardBloc(
    releases: releases,
    approvals: approvals,
    projects: projects,
  );

  Future<void> loaded(ReleaseBoardBloc bloc, {String? releaseId}) async {
    bloc.add(ReleaseBoardSubscriptionRequested('prj_1', releaseId: releaseId));
    await pumpEventQueue();
    list.add(Snapshot([reviewRelease(), liveRelease]));
    await pumpEventQueue();
  }

  test('events compare by value', () {
    expect(const ReleaseBoardSubscriptionRequested('p', releaseId: 'r').props, [
      'p',
      'r',
    ]);
    expect(const ReleaseBoardReleaseSelected('r').props, ['r']);
    expect(
      const ReleaseBoardStoreMarked(ReleaseStore.play, StoreState.live).props,
      [ReleaseStore.play, StoreState.live],
    );
    expect(const ReleaseBoardMergeRequested().props, isEmpty);
    expect(const ReleaseBoardRolloutRequested(_pause).props, [_pause]);
  });

  group('ReleaseBoardState', () {
    test(
      'shows the release picked, else the one in flight, else the newest',
      () {
        expect(const ReleaseBoardState().release, isNull);
        expect(
          ReleaseBoardState(releases: [liveRelease, reviewRelease()]).release,
          reviewRelease(),
        );
        expect(
          ReleaseBoardState(
            releases: [reviewRelease(), liveRelease],
            selectedId: 'rel_1',
          ).release,
          liveRelease,
        );
        expect(ReleaseBoardState(releases: [liveRelease]).release, liveRelease);
      },
    );

    test('reads a store through its API only with its credential', () {
      const state = ReleaseBoardState(credentials: [verifiedKey, slackHook]);
      expect(state.readsStore(reviewRelease(), ReleaseStore.apple), isTrue);
      expect(state.readsStore(reviewRelease(), ReleaseStore.play), isFalse);
    });
  });

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'follows the releases, approvals and credentials, and reads the notes',
    build: build,
    act: loaded,
    verify: (bloc) {
      final state = bloc.state;
      expect(state.loaded, isTrue);
      expect(state.release, reviewRelease());
      expect(state.approvals, [pendingApproval]);
      expect(state.credentials, const [verifiedKey]);
      expect(state.notes, reviewNotes);
    },
  );

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'reads the notes again only for another release or commit',
    build: build,
    act: (bloc) async {
      await loaded(bloc);
      list.add(
        Snapshot([reviewRelease(state: ReleaseState.approved), liveRelease]),
      );
      await pumpEventQueue();
      bloc.add(const ReleaseBoardReleaseSelected('rel_1'));
      await pumpEventQueue();
    },
    verify: (bloc) {
      verify(() => releases.notes('rel_2')).called(1);
      verify(() => releases.notes('rel_1')).called(1);
      expect(bloc.state.release, liveRelease);
      expect(bloc.state.notes, isNull);
    },
  );

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'says why the notes cannot be read, and drops late notes',
    setUp: () =>
        when(() => releases.notes('rel_2'))
            .thenThrow(const ApiException('Not tagged.', statusCode: 409)),
    build: build,
    act: (bloc) => loaded(bloc, releaseId: 'rel_2'),
    verify: (bloc) => expect(bloc.state.notesError, 'Not tagged.'),
  );

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'drops notes of a release no longer shown',
    setUp: () {
      final notes = Completer<ReleaseNotes>();
      when(() => releases.notes('rel_2')).thenAnswer((_) => notes.future);
      addTearDown(() => notes.complete(reviewNotes));
    },
    build: build,
    act: (bloc) async {
      await loaded(bloc);
      bloc.add(const ReleaseBoardReleaseSelected('rel_1'));
    },
    verify: (bloc) => expect(bloc.state.notes, isNull),
  );

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'drops a failure of the notes of a release no longer shown',
    setUp: () {
      final notes = Completer<ReleaseNotes>();
      when(() => releases.notes('rel_2')).thenAnswer((_) => notes.future);
      addTearDown(() => notes.completeError(const ConnectionException('down')));
    },
    build: build,
    act: (bloc) async {
      await loaded(bloc);
      bloc.add(const ReleaseBoardReleaseSelected('rel_1'));
    },
    verify: (bloc) => expect(bloc.state.notesError, isNull),
  );

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'refreshes, marks, merges, rolls out and builds again',
    setUp: () {
      when(() => releases.refresh('rel_2'))
          .thenAnswer((_) async => reviewRelease());
      when(
        () => releases.setStoreStatus(
          'rel_2',
          ReleaseStore.apple,
          StoreState.live,
        ),
      ).thenAnswer((_) async => reviewRelease());
      when(() => releases.merge('rel_2'))
          .thenAnswer((_) async => runningRun().run);
      when(() => releases.rollout('rel_2', _pause))
          .thenAnswer((_) async => runningRun().run);
      when(() => releases.startBuild('rel_2'))
          .thenAnswer((_) async => runningRun().run);
    },
    build: build,
    act: (bloc) async {
      await loaded(bloc);
      bloc.add(const ReleaseBoardRefreshRequested());
      await pumpEventQueue();
      bloc.add(
        const ReleaseBoardStoreMarked(ReleaseStore.apple, StoreState.live),
      );
      await pumpEventQueue();
      bloc.add(const ReleaseBoardMergeRequested());
      await pumpEventQueue();
      bloc.add(const ReleaseBoardRolloutRequested(_pause));
      await pumpEventQueue();
      expect(bloc.state.builtRun, isNull);
      bloc.add(const ReleaseBoardNewBuildRequested());
      await pumpEventQueue();
    },
    verify: (bloc) {
      expect(bloc.state.command, ReleaseCommand.none);
      expect(bloc.state.builtRun, runningRun().run);
      verify(() => releases.refresh('rel_2')).called(1);
      verify(() => releases.merge('rel_2')).called(1);
      verify(() => releases.rollout('rel_2', _pause)).called(1);
    },
  );

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'says what the engine refused',
    setUp: () =>
        when(() => releases.merge('rel_2'))
            .thenThrow(const ApiException('Not live.', statusCode: 409)),
    build: build,
    act: (bloc) async {
      await loaded(bloc);
      bloc.add(const ReleaseBoardMergeRequested());
    },
    verify: (bloc) {
      expect(bloc.state.error, 'Not live.');
      expect(bloc.state.command, ReleaseCommand.none);
    },
  );

  blocTest<ReleaseBoardBloc, ReleaseBoardState>(
    'does nothing without a release, and keeps going when lists fail',
    setUp: () {
      when(() => approvals.watchApprovals(projectId: 'prj_1'))
          .thenAnswer((_) => Stream.error(const ConnectionException('x')));
      when(() => projects.watchCredentials('prj_1'))
          .thenAnswer((_) => Stream.error(const ConnectionException('x')));
    },
    build: build,
    act: (bloc) async {
      bloc
        ..add(const ReleaseBoardSubscriptionRequested('prj_1'))
        ..add(const ReleaseBoardRefreshRequested());
      await pumpEventQueue();
      list.addError(const ApiException('Nope.', statusCode: 500));
    },
    verify: (bloc) {
      expect(bloc.state.error, 'Nope.');
      verifyNever(() => releases.refresh(any()));
    },
  );
}
