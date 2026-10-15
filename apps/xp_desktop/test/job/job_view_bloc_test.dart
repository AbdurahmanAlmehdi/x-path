import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/job/bloc/job_view_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';

void main() {
  late MockJobsRepository jobs;
  late MockWorkflowsRepository workflows;
  late MockRunnersRepository runners;
  late StreamController<Snapshot<RunJobs>> run;

  setUpAll(() => registerFallbackValue(runningRun().run));

  setUp(() {
    jobs = MockJobsRepository();
    workflows = MockWorkflowsRepository();
    runners = MockRunnersRepository();
    run = StreamController<Snapshot<RunJobs>>();
    when(() => jobs.watchRunJobs('run_1')).thenAnswer((_) => run.stream);
    when(() => jobs.listArtifacts(any())).thenAnswer((_) async => iosArtifacts);
    when(runners.watchRunners)
        .thenAnswer((_) => Stream.value(Snapshot([linuxRunner])));
    when(() => workflows.workflowOf(any()))
        .thenAnswer((_) async => prodWorkflow);
  });

  // Never awaited: a controller nobody listened to never finishes closing.
  tearDown(() => unawaited(run.close()));

  JobViewBloc build() =>
      JobViewBloc(jobs: jobs, workflows: workflows, runners: runners);

  group('defaultJobOf', () {
    test('picks what matters most', () {
      final jobs = runningRun().jobs;
      expect(defaultJobOf(jobs), 'job_ios');
      expect(defaultJobOf(failedRun().jobs), 'job_ios');
      expect(defaultJobOf(interruptedRun().jobs), 'job_ios');
      expect(
        defaultJobOf([jobs[0], job('w', 'w', 2, JobState.waitingForApproval)]),
        'w',
      );
      expect(
        defaultJobOf([jobs[0], job('c', 'c', 2, JobState.cancelled)]),
        'c',
      );
      expect(defaultJobOf([jobs[0]]), 'job_preflight');
      expect(defaultJobOf(const []), isNull);
    });
  });

  test('events compare by value', () {
    expect(const JobViewSubscriptionRequested('run_1', jobId: 'j').props, [
      'run_1',
      'j',
    ]);
    expect(const JobViewJobSelected('j').props, ['j']);
    expect(const JobViewStepSelected(2).props, [2]);
    expect(const JobViewCancelRequested().props, isEmpty);
    expect(const JobViewResumeRequested(fromStep: 1).props, [1]);
    expect(const JobViewArtifactsRequested().props, isEmpty);
  });

  group('JobViewBloc', () {
    blocTest<JobViewBloc, JobViewState>(
      'follows the run, its runners, its workflow and the artifacts',
      build: build,
      act: (bloc) async {
        bloc.add(const JobViewSubscriptionRequested('run_1'));
        await Future<void>.delayed(Duration.zero);
        run.add(Snapshot(runningRun(), cached: true));
        await Future<void>.delayed(Duration.zero);
        run.add(Snapshot(runningRun()));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.loaded, isTrue);
        expect(state.cached, isFalse);
        expect(state.run, runningRun().run);
        expect(state.selectedJobId, 'job_ios');
        expect(state.selectedJob?.name, 'Build prod for ios');
        expect(state.runners, {linuxBuilder: 'linux-builder-01'});
        expect(state.workflowName, 'Prod release');
        expect(state.stageName(0), 'preflight');
        expect(state.stageName(9), isNull);
        expect(state.artifacts, iosArtifacts);
        verify(() => workflows.workflowOf(any())).called(1);
      },
    );

    blocTest<JobViewBloc, JobViewState>(
      'shows the job it was asked for and keeps a stage without a name',
      setUp: () => when(() => workflows.workflowOf(any())).thenAnswer(
        (_) async => Workflow(
          id: 'wf',
          projectId: 'prj_1',
          name: 'Custom',
          builtin: false,
          version: prodWorkflow.version,
          versions: prodWorkflow.versions,
          yaml: 'stages:\n  - jobs: {}\n',
        ),
      ),
      build: build,
      act: (bloc) async {
        bloc.add(
          const JobViewSubscriptionRequested('run_1', jobId: 'job_android'),
        );
        await Future<void>.delayed(Duration.zero);
        run.add(Snapshot(runningRun()));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.selectedJobId, 'job_android');
        expect(bloc.state.workflowName, 'Custom');
        expect(bloc.state.stageName(0), isNull);
      },
    );

    blocTest<JobViewBloc, JobViewState>(
      'keeps the names of the workflow out when it cannot be read',
      setUp: () {
        when(runners.watchRunners)
            .thenAnswer((_) => Stream.error(const ConnectionException('down')));
        when(() => workflows.workflowOf(any())).thenAnswer(
          (_) async => Workflow(
            id: 'wf',
            projectId: 'prj_1',
            name: 'Broken',
            builtin: false,
            version: prodWorkflow.version,
            versions: prodWorkflow.versions,
            yaml: '- not a map',
          ),
        );
      },
      build: build,
      act: (bloc) async {
        bloc.add(const JobViewSubscriptionRequested('run_1'));
        await Future<void>.delayed(Duration.zero);
        run.add(Snapshot(runningRun()));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.workflowName, 'Broken');
        expect(bloc.state.outline, isNull);
        expect(bloc.state.runners, isEmpty);
      },
    );

    blocTest<JobViewBloc, JobViewState>(
      'gets on without the workflow when the engine does not answer',
      setUp: () =>
          when(() => workflows.workflowOf(any()))
              .thenThrow(const ConnectionException('down')),
      build: build,
      act: (bloc) async {
        bloc.add(const JobViewSubscriptionRequested('run_1'));
        await Future<void>.delayed(Duration.zero);
        run.add(Snapshot(runningRun()));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.workflowName, isNull);
        expect(bloc.state.loaded, isTrue);
      },
    );

    blocTest<JobViewBloc, JobViewState>(
      'says what the engine answered when the run cannot be read',
      build: build,
      act: (bloc) async {
        bloc.add(const JobViewSubscriptionRequested('run_1'));
        await Future<void>.delayed(Duration.zero);
        run.addError(const ApiException('No such run.', statusCode: 404));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.loaded, isTrue);
        expect(bloc.state.error, 'No such run.');
        expect(bloc.state.run, isNull);
      },
    );

    blocTest<JobViewBloc, JobViewState>(
      'selects a job and a step, and reads the artifacts again',
      build: build,
      seed: () => JobViewState(
        loaded: true,
        runJobs: runningRun(),
        selectedJobId: 'job_ios',
        selectedStep: 2,
      ),
      act: (bloc) => bloc
        ..add(const JobViewJobSelected('job_ios'))
        ..add(const JobViewJobSelected('job_android'))
        ..add(const JobViewStepSelected(1)),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.selectedJobId, 'job_android');
        expect(bloc.state.selectedStep, 1);
        expect(bloc.state.artifacts, iosArtifacts);
        verify(() => jobs.listArtifacts('job_android')).called(1);
      },
    );

    blocTest<JobViewBloc, JobViewState>(
      'keeps the artifacts it has when they cannot be read',
      setUp: () =>
          when(() => jobs.listArtifacts(any()))
              .thenThrow(const ConnectionException('down')),
      build: build,
      seed: () => JobViewState(runJobs: runningRun(), selectedJobId: 'job_ios'),
      act: (bloc) => bloc.add(const JobViewArtifactsRequested()),
      expect: () => const <JobViewState>[],
    );

    blocTest<JobViewBloc, JobViewState>(
      'reads no artifacts without a job',
      build: build,
      act: (bloc) => bloc.add(const JobViewArtifactsRequested()),
      expect: () => const <JobViewState>[],
      verify: (_) => verifyNever(() => jobs.listArtifacts(any())),
    );

    blocTest<JobViewBloc, JobViewState>(
      'cancels the run',
      setUp: () =>
          when(() => jobs.cancelRun('run_1'))
              .thenAnswer((_) async => runningRun().run),
      build: build,
      seed: () => JobViewState(runJobs: runningRun()),
      act: (bloc) => bloc.add(const JobViewCancelRequested()),
      expect: () => [
        JobViewState(runJobs: runningRun(), command: JobViewCommand.cancelling),
        JobViewState(runJobs: runningRun()),
      ],
    );

    blocTest<JobViewBloc, JobViewState>(
      'says why the run could not be cancelled',
      setUp: () =>
          when(() => jobs.cancelRun('run_1'))
              .thenThrow(const ApiException('Ended.', statusCode: 409)),
      build: build,
      seed: () => JobViewState(runJobs: runningRun()),
      act: (bloc) => bloc.add(const JobViewCancelRequested()),
      skip: 1,
      expect: () => [JobViewState(runJobs: runningRun(), error: 'Ended.')],
    );

    blocTest<JobViewBloc, JobViewState>(
      'cancels nothing before the run arrives',
      build: build,
      act: (bloc) => bloc.add(const JobViewCancelRequested()),
      expect: () => const <JobViewState>[],
    );

    blocTest<JobViewBloc, JobViewState>(
      'resumes the job from a step',
      setUp: () =>
          when(() => jobs.resumeJob('job_ios', fromStep: 2))
              .thenAnswer((_) async => interruptedRun().jobs[1]),
      build: build,
      seed: () => JobViewState(
        runJobs: interruptedRun(),
        selectedJobId: 'job_ios',
        selectedStep: 2,
      ),
      act: (bloc) => bloc.add(const JobViewResumeRequested(fromStep: 2)),
      expect: () => [
        JobViewState(
          runJobs: interruptedRun(),
          selectedJobId: 'job_ios',
          selectedStep: 2,
          command: JobViewCommand.resuming,
        ),
        JobViewState(runJobs: interruptedRun(), selectedJobId: 'job_ios'),
      ],
    );

    blocTest<JobViewBloc, JobViewState>(
      'says why the job could not be resumed',
      setUp: () =>
          when(() => jobs.resumeJob('job_ios'))
              .thenThrow(const ApiException('Not resumable.', statusCode: 409)),
      build: build,
      seed: () => JobViewState(runJobs: failedRun(), selectedJobId: 'job_ios'),
      act: (bloc) => bloc.add(const JobViewResumeRequested()),
      skip: 1,
      expect: () => [
        JobViewState(
          runJobs: failedRun(),
          selectedJobId: 'job_ios',
          error: 'Not resumable.',
        ),
      ],
    );

    blocTest<JobViewBloc, JobViewState>(
      'resumes nothing without a job',
      build: build,
      act: (bloc) => bloc.add(const JobViewResumeRequested()),
      expect: () => const <JobViewState>[],
    );
  });
}
