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
import '../helpers/release_fixtures.dart';

void main() {
  late MockApprovalsRepository approvals;
  late MockJobsRepository jobs;
  late MockReleasesRepository releases;
  late StreamController<Snapshot<Approval>> approval;

  setUp(() {
    approvals = MockApprovalsRepository();
    jobs = MockJobsRepository();
    releases = MockReleasesRepository();
    approval = StreamController<Snapshot<Approval>>();
    when(() => approvals.watchApproval('apr_1'))
        .thenAnswer((_) => approval.stream);
    when(() => jobs.watchJob('job_upload'))
        .thenAnswer((_) => Stream.value(Snapshot(uploadJob)));
    when(() => releases.watchRelease('rel_2'))
        .thenAnswer((_) => Stream.value(Snapshot(reviewRelease())));
  });

  tearDown(() => unawaited(approval.close()));

  ApprovalReviewBloc build({Duration armingDelay = Duration.zero}) =>
      ApprovalReviewBloc(
        approvals: approvals,
        jobs: jobs,
        releases: releases,
        armingDelay: armingDelay,
      );

  final subject = ApprovalSubject(job: uploadJob, release: reviewRelease());

  /// A bloc whose approval arrived pending and armed.
  Future<void> armed(ApprovalReviewBloc bloc) async {
    bloc.add(const ApprovalReviewStarted('apr_1'));
    approval.add(Snapshot(pendingApproval));
    await pumpEventQueue();
  }

  test('events and state compare by value', () {
    expect(const ApprovalReviewStarted('a').props, ['a']);
    expect(const ApprovalReviewDenyRequested(reason: 'r').props, ['r']);
    expect(const ApprovalReviewApproveRequested().props, isEmpty);
    expect(const ApprovalReviewState().canApprove, isFalse);
    expect(
      const ApprovalReviewState(status: ApprovalReviewStatus.ready).canDeny,
      isTrue,
    );
  });

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'arms after the delay, reads the job and release, and approves',
    setUp: () =>
        when(() => approvals.approve('apr_1'))
            .thenAnswer((_) async => decided(pendingApproval)),
    build: build,
    act: (bloc) async {
      await armed(bloc);
      bloc.add(const ApprovalReviewApproveRequested());
      await pumpEventQueue();
      // The engine's event of this decision changes nothing more.
      approval.add(Snapshot(decided(pendingApproval)));
    },
    expect: () => [
      ApprovalReviewState(
        status: ApprovalReviewStatus.ready,
        approval: pendingApproval,
      ),
      ApprovalReviewState(
        status: ApprovalReviewStatus.ready,
        approval: pendingApproval,
        subject: subject,
      ),
      ApprovalReviewState(
        status: ApprovalReviewStatus.ready,
        approval: pendingApproval,
        subject: subject,
        armed: true,
      ),
      ApprovalReviewState(
        status: ApprovalReviewStatus.approving,
        approval: pendingApproval,
        subject: subject,
        armed: true,
      ),
      ApprovalReviewState(
        status: ApprovalReviewStatus.approved,
        approval: decided(pendingApproval),
        subject: subject,
        armed: true,
      ),
    ],
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'never approves before the arming delay is over',
    build: () => build(armingDelay: const Duration(hours: 1)),
    act: (bloc) async {
      bloc.add(const ApprovalReviewStarted('apr_1'));
      approval.add(Snapshot(pendingApproval));
      await pumpEventQueue();
      bloc.add(const ApprovalReviewApproveRequested());
    },
    verify: (bloc) {
      verifyNever(() => approvals.approve(any()));
      expect(bloc.state.armed, isFalse);
      expect(bloc.state.status, ApprovalReviewStatus.ready);
    },
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'ends as already decided when another device decided first (409)',
    setUp: () => when(() => approvals.approve('apr_1')).thenThrow(
      ApprovalAlreadyDecided(
        'The approval apr_1 was denied already.',
        approval: decided(pendingApproval, state: ApprovalState.denied),
      ),
    ),
    build: build,
    act: (bloc) async {
      await armed(bloc);
      bloc.add(const ApprovalReviewApproveRequested());
    },
    skip: 3,
    expect: () => [
      ApprovalReviewState(
        status: ApprovalReviewStatus.approving,
        approval: pendingApproval,
        subject: subject,
        armed: true,
      ),
      ApprovalReviewState(
        status: ApprovalReviewStatus.alreadyDecided,
        approval: decided(pendingApproval, state: ApprovalState.denied),
        subject: subject,
        armed: true,
      ),
    ],
    verify: (bloc) => expect(bloc.state.canApprove, isFalse),
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'keeps the approval it holds when the 409 carries none',
    setUp: () =>
        when(() => approvals.deny('apr_1'))
            .thenThrow(const ApprovalAlreadyDecided('Expired.')),
    build: build,
    act: (bloc) async {
      await armed(bloc);
      bloc.add(const ApprovalReviewDenyRequested());
    },
    verify: (bloc) {
      expect(bloc.state.status, ApprovalReviewStatus.alreadyDecided);
      expect(bloc.state.approval, pendingApproval);
    },
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'turns already decided when the decision of another device arrives',
    build: () => build(armingDelay: const Duration(hours: 1)),
    act: (bloc) async {
      bloc.add(const ApprovalReviewStarted('apr_1'));
      approval.add(Snapshot(pendingApproval));
      await pumpEventQueue();
      approval.add(Snapshot(decided(pendingApproval)));
      await pumpEventQueue();
      bloc
        ..add(const ApprovalReviewApproveRequested())
        ..add(const ApprovalReviewDenyRequested());
    },
    verify: (bloc) {
      expect(bloc.state.status, ApprovalReviewStatus.alreadyDecided);
      expect(bloc.state.approval, decided(pendingApproval));
      verifyNever(() => approvals.approve(any()));
      verifyNever(() => approvals.deny(any(), reason: any(named: 'reason')));
    },
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'denies with the reason, trimmed, or none',
    setUp: () {
      when(() => approvals.deny('apr_1', reason: 'Wrong build'))
          .thenAnswer((_) async => decided(pendingApproval));
      when(() => approvals.deny('apr_1'))
          .thenAnswer((_) async => decided(pendingApproval));
    },
    build: build,
    act: (bloc) async {
      await armed(bloc);
      bloc.add(const ApprovalReviewDenyRequested(reason: '  Wrong build '));
      await pumpEventQueue();
    },
    verify: (bloc) {
      expect(bloc.state.status, ApprovalReviewStatus.denied);
      verify(() => approvals.deny('apr_1', reason: 'Wrong build')).called(1);
    },
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'sends no reason for a blank one',
    setUp: () =>
        when(() => approvals.deny('apr_1'))
            .thenAnswer((_) async => decided(pendingApproval)),
    build: build,
    act: (bloc) async {
      await armed(bloc);
      bloc.add(const ApprovalReviewDenyRequested(reason: '  '));
    },
    verify: (_) => verify(() => approvals.deny('apr_1')).called(1),
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'says what the engine refused and lets the owner try again',
    setUp: () =>
        when(() => approvals.approve('apr_1'))
            .thenThrow(const ConnectionException('Connection refused.')),
    build: build,
    act: (bloc) async {
      await armed(bloc);
      bloc.add(const ApprovalReviewApproveRequested());
    },
    verify: (bloc) {
      expect(bloc.state.status, ApprovalReviewStatus.ready);
      expect(bloc.state.error, 'Connection refused.');
      expect(bloc.state.canApprove, isTrue);
    },
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'fails when the approval cannot be read, and keeps one it read',
    build: build,
    act: (bloc) async {
      bloc.add(const ApprovalReviewStarted('apr_1'));
      approval.addError(
        const ApiException('No such approval.', statusCode: 404),
      );
      await pumpEventQueue();
      approval.add(Snapshot(pendingApproval));
      await pumpEventQueue();
      approval.addError(const ConnectionException('down'));
    },
    verify: (bloc) {
      expect(bloc.state.status, ApprovalReviewStatus.ready);
      expect(bloc.state.error, 'No such approval.');
    },
  );

  blocTest<ApprovalReviewBloc, ApprovalReviewState>(
    'reports a failed read',
    build: build,
    act: (bloc) async {
      bloc.add(const ApprovalReviewStarted('apr_1'));
      approval.addError(
        const ApiException('No such approval.', statusCode: 404),
      );
    },
    expect: () => [
      const ApprovalReviewState(
        status: ApprovalReviewStatus.failed,
        error: 'No such approval.',
      ),
    ],
  );

  test('closing cancels the arming', () async {
    final bloc = build(armingDelay: const Duration(milliseconds: 100));
    await armed(bloc);
    await bloc.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(bloc.state.armed, isFalse);
  });

  group('loadApprovalSubject', () {
    test('reads the job and its release', () async {
      expect(
        await loadApprovalSubject(
          pendingApproval,
          jobs: jobs,
          releases: releases,
        ),
        subject,
      );
    });

    test(
      'has nothing without a job, and what it read when a read fails',
      () async {
        expect(
          await loadApprovalSubject(
            mergeApproval,
            jobs: jobs,
            releases: releases,
          ),
          const ApprovalSubject(),
        );
        when(() => releases.watchRelease('rel_2'))
            .thenAnswer((_) => const Stream.empty());
        expect(
          await loadApprovalSubject(
            pendingApproval,
            jobs: jobs,
            releases: releases,
          ),
          ApprovalSubject(job: uploadJob),
        );
        when(() => jobs.watchJob('job_upload')).thenAnswer(
          (_) => Stream.value(
            Snapshot(
              Job(
                id: 'job_upload',
                projectId: 'prj_1',
                workflowVersionId: 'wfv_1',
                state: JobState.running,
                createdAt: uploadJob.createdAt,
                steps: const [],
              ),
            ),
          ),
        );
        expect(
          (await loadApprovalSubject(
            pendingApproval,
            jobs: jobs,
            releases: releases,
          )).release,
          isNull,
        );
        when(() => jobs.watchJob('job_upload'))
            .thenAnswer((_) => Stream.error(const ConnectionException('down')));
        expect(
          await loadApprovalSubject(
            pendingApproval,
            jobs: jobs,
            releases: releases,
          ),
          const ApprovalSubject(),
        );
      },
    );
  });
}
