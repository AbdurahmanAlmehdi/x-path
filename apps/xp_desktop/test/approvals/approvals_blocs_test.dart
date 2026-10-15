import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/release_fixtures.dart';

void main() {
  late MockApprovalsRepository approvals;
  late MockJobsRepository jobs;
  late MockReleasesRepository releases;
  late StreamController<Snapshot<List<Approval>>> list;

  setUp(() {
    approvals = MockApprovalsRepository();
    jobs = MockJobsRepository();
    releases = MockReleasesRepository();
    list = StreamController<Snapshot<List<Approval>>>();
    when(() => jobs.watchJob('job_upload'))
        .thenAnswer((_) => Stream.value(Snapshot(uploadJob)));
    when(() => releases.watchRelease('rel_2'))
        .thenAnswer((_) => Stream.value(Snapshot(reviewRelease())));
  });

  tearDown(() => unawaited(list.close()));

  final subject = ApprovalSubject(job: uploadJob, release: reviewRelease());
  final expired = Approval(
    id: 'apr_3',
    projectId: 'prj_1',
    action: 'push',
    sha: 'abc',
    state: ApprovalState.expired,
    createdAt: pendingApproval.createdAt,
    expiresAt: pendingApproval.expiresAt,
  );

  group('PendingApprovalsBloc', () {
    setUp(
      () =>
          when(() => approvals.watchApprovals(state: ApprovalState.pending))
              .thenAnswer((_) => list.stream),
    );

    test('events compare by value', () {
      expect(const PendingApprovalsSubscriptionRequested().props, isEmpty);
    });

    blocTest<PendingApprovalsBloc, PendingApprovalsState>(
      'follows what waits, keeping it when the engine is away',
      build: () => PendingApprovalsBloc(approvals: approvals),
      act: (bloc) async {
        bloc.add(const PendingApprovalsSubscriptionRequested());
        await pumpEventQueue();
        list
          ..add(Snapshot([pendingApproval, expired], cached: true))
          ..addError(const ConnectionException('down'))
          ..add(Snapshot([mergeApproval, pendingApproval]));
      },
      expect: () => [
        PendingApprovalsState(
          loaded: true,
          approvals: [pendingApproval],
          cached: true,
        ),
        PendingApprovalsState(
          loaded: true,
          approvals: [mergeApproval, pendingApproval],
        ),
      ],
      verify: (bloc) {
        expect(bloc.state.of('prj_1'), [pendingApproval]);
        expect(bloc.state.of('prj_9'), isEmpty);
      },
    );

    test('of puts the approval that expires first first', () {
      final later = Approval(
        id: 'apr_9',
        projectId: 'prj_1',
        action: 'merge',
        sha: sha,
        state: ApprovalState.pending,
        createdAt: pendingApproval.createdAt,
        expiresAt: pendingApproval.expiresAt.add(const Duration(hours: 1)),
      );
      expect(
        PendingApprovalsState(approvals: [later, pendingApproval]).of('prj_1'),
        [pendingApproval, later],
      );
    });
  });

  group('ApprovalsInboxBloc', () {
    setUp(() => when(approvals.watchApprovals).thenAnswer((_) => list.stream));

    ApprovalsInboxBloc build() => ApprovalsInboxBloc(
      approvals: approvals,
      jobs: jobs,
      releases: releases,
    );

    test('events and filters compare by value', () {
      expect(const ApprovalsInboxSubscriptionRequested().props, [null]);
      expect(const ApprovalsInboxFilterChanged(ApprovalsFilter.decided).props, [
        ApprovalsFilter.decided,
      ]);
      expect(const ApprovalsInboxApprovalSelected('a').props, ['a']);
      expect(ApprovalsFilter.of(ApprovalState.denied), ApprovalsFilter.decided);
      expect(
        ApprovalsFilter.of(ApprovalState.expired),
        ApprovalsFilter.expired,
      );
    });

    blocTest<ApprovalsInboxBloc, ApprovalsInboxState>(
      'lists pending first, shows the first with its job and release',
      build: build,
      act: (bloc) async {
        bloc.add(const ApprovalsInboxSubscriptionRequested());
        await pumpEventQueue();
        list.add(Snapshot([pendingApproval, expired, mergeApproval]));
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state.loaded, isTrue);
        expect(state.visible, [pendingApproval, mergeApproval]);
        expect(state.pendingCount, 2);
        expect(state.selected, pendingApproval);
        expect(state.subject, subject);
      },
    );

    blocTest<ApprovalsInboxBloc, ApprovalsInboxState>(
      'filters and selects',
      build: build,
      act: (bloc) async {
        bloc.add(const ApprovalsInboxSubscriptionRequested());
        await pumpEventQueue();
        list.add(Snapshot([pendingApproval, expired, mergeApproval]));
        await pumpEventQueue();
        bloc.add(const ApprovalsInboxApprovalSelected('apr_2'));
        await pumpEventQueue();
        expect(bloc.state.selected, mergeApproval);
        expect(bloc.state.subject, const ApprovalSubject());
        bloc.add(const ApprovalsInboxFilterChanged(ApprovalsFilter.expired));
        await pumpEventQueue();
        expect(bloc.state.selected, expired);
        bloc.add(const ApprovalsInboxFilterChanged(ApprovalsFilter.decided));
        await pumpEventQueue();
        expect(bloc.state.selected, isNull);
        // The list again changes nothing about the selection.
        list.add(Snapshot([pendingApproval, expired, mergeApproval]));
      },
      verify: (bloc) => expect(bloc.state.filter, ApprovalsFilter.decided),
    );

    blocTest<ApprovalsInboxBloc, ApprovalsInboxState>(
      'opens at the approval asked for, under its filter',
      build: build,
      act: (bloc) async {
        bloc.add(
          const ApprovalsInboxSubscriptionRequested(approvalId: 'apr_3'),
        );
        await pumpEventQueue();
        list.add(Snapshot([pendingApproval, expired]));
      },
      verify: (bloc) {
        expect(bloc.state.filter, ApprovalsFilter.expired);
        expect(bloc.state.selected, expired);
      },
    );

    blocTest<ApprovalsInboxBloc, ApprovalsInboxState>(
      'drops a job and release that arrive after the selection moved',
      setUp: () {
        final job = Completer<Snapshot<Job>>();
        when(() => jobs.watchJob('job_upload'))
            .thenAnswer((_) => Stream.fromFuture(job.future));
        addTearDown(() => job.complete(Snapshot(uploadJob)));
      },
      build: build,
      act: (bloc) async {
        bloc.add(const ApprovalsInboxSubscriptionRequested());
        await pumpEventQueue();
        list.add(Snapshot([pendingApproval, mergeApproval]));
        await pumpEventQueue();
        bloc.add(const ApprovalsInboxApprovalSelected('apr_2'));
      },
      verify: (bloc) => expect(bloc.state.subject, const ApprovalSubject()),
    );

    blocTest<ApprovalsInboxBloc, ApprovalsInboxState>(
      'says what the engine refused',
      build: build,
      act: (bloc) async {
        bloc.add(const ApprovalsInboxSubscriptionRequested());
        await pumpEventQueue();
        list.addError(const ApiException('Nope.', statusCode: 500));
      },
      expect: () => [const ApprovalsInboxState(loaded: true, error: 'Nope.')],
    );
  });
}
