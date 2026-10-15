import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/job/bloc/job_log_bloc.dart';
import 'package:xp_desktop/job/bloc/job_view_bloc.dart';
import 'package:xp_desktop/job/widgets/cancel_run_dialog.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/job/widgets/log_view.dart';
import 'package:xp_desktop/job/widgets/pipeline_graph.dart';
import 'package:xp_desktop/job/widgets/step_list.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The live job view (2A, `Job-A-Graph`): the run's pipeline graph over the
/// steps and the log of one of its jobs.
class JobPage extends StatelessWidget {
  const new({required this.runId, this.jobId, super.key});

  final String runId;

  /// The job to show first; the one that matters most when `null`.
  final String? jobId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey((runId, jobId)),
    create: (context) => JobViewBloc(
      jobs: context.read<JobsRepository>(),
      workflows: context.read<WorkflowsRepository>(),
      runners: context.read<RunnersRepository>(),
    )..add(JobViewSubscriptionRequested(runId, jobId: jobId)),
    child: const JobView(),
  );
}

class JobView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<JobViewBloc>().state;
    final runJobs = state.runJobs;
    if (runJobs == null) {
      return ShellPage(
        title: l10n.jobTitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: state.error == null
              ? const SizedBox()
              : XpMessage(XpStatus.scanError, state.error!),
        ),
      );
    }
    final run = runJobs.run;
    final project = context.watch<ProjectsBloc>().state.byId(run.projectId);
    final title = state.workflowName ?? l10n.jobTitle;
    final job = state.selectedJob;
    return _JobShortcuts(
      child: ShellPage(
        title: title,
        subtitle: [
          ?project?.fullName.split('/').last,
          ?run.ref,
          shortSha(run.sha),
        ].join(' · '),
        actions: _actions(context, state, title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (job != null &&
                (job.state == JobState.interrupted ||
                    job.state == JobState.waitingForResume))
              _InterruptedBanner(job),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.error case final error?) ...[
                    XpMessage(XpStatus.scanError, error),
                    const SizedBox(height: 10),
                  ],
                  _Hero(state),
                  const SizedBox(height: 16),
                  PipelineGraph(
                    stages: pipelineStages(
                      runJobs: runJobs,
                      l10n: l10n,
                      now: XpClock.now(context),
                      engineName: context.engineName,
                      stageName: state.stageName,
                      runnerName: (id) => state.runners[id],
                      selectedJobId: state.selectedJobId,
                    ),
                    onNodeTap: (id) =>
                        context.read<JobViewBloc>().add(JobViewJobSelected(id)),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const XpHairline(),
            Expanded(
              child: job == null
                  ? const SizedBox()
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 280, child: StepAside(job: job)),
                        const XpHairline(vertical: true),
                        Expanded(
                          child: JobLogPane(
                            job: job,
                            runnerName: state.runners[job.runnerId],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    JobViewState state,
    String title,
  ) {
    final l10n = context.l10n;
    final bloc = context.read<JobViewBloc>();
    final canCommand = context.canCommand;
    final jobs = state.runJobs!.jobs;
    final running = jobs.where((job) => job.state == JobState.running).length;
    final job = state.selectedJob;
    final open = jobs.any((job) => !job.state.isFinished);
    final resumable = job != null && isResumable(job.state);
    final from = job == null ? null : resumeFrom(job, state.selectedStep);
    return [
      if (running > 0)
        XpStatusLabel(XpStatus.jobRunning, l10n.jobRunningCount(running)),
      if (resumable) ...[
        XpButton(
          label: l10n.jobRerunAll,
          icon: PhosphorIconsRegular.arrowClockwise,
          hint: '⌘R',
          busy: state.command == JobViewCommand.resuming,
          onPressed: canCommand
              ? () => bloc.add(const JobViewResumeRequested(fromStep: 0))
              : null,
        ),
        if (from != null)
          XpButton(
            label: l10n.jobResumeFrom(l10n.stepKind(job.steps[from].kind)),
            icon: PhosphorIconsRegular.play,
            hint: '⌥⌘R',
            kind: XpButtonKind.primary,
            onPressed: canCommand
                ? () => bloc.add(JobViewResumeRequested(fromStep: from))
                : null,
          ),
      ],
      if (job != null && hasTestResults(job))
        XpButton(
          label: l10n.jobTestResults,
          icon: PhosphorIconsRegular.testTube,
          onPressed: () => context.read<ShellCubit>().show(
            TestsDestination(job.projectId, jobId: job.id),
          ),
        ),
      if (open)
        XpButton(
          label: l10n.jobCancel,
          icon: PhosphorIconsRegular.stopCircle,
          hint: '⌘.',
          busy: state.command == JobViewCommand.cancelling,
          onPressed: canCommand ? () => cancelRun(context, title) : null,
        ),
    ];
  }
}

/// Whether [job] ran its tests to the end: its `test` step succeeded or
/// failed, so the engine has the run (D-21).
bool hasTestResults(Job job) => job.steps.any(
  (step) =>
      step.kind == 'test' &&
      (step.state == StepState.succeeded || step.state == StepState.failed),
);

/// Asks, then cancels the run of the job view.
Future<void> cancelRun(BuildContext context, String title) async {
  final bloc = context.read<JobViewBloc>();
  final state = bloc.state;
  final run = state.run!;
  final confirmed = await confirmCancelRun(
    context,
    runJobs: state.runJobs!,
    title: [title, ?_version(run)].join(' '),
    engineName: context.currentEngineName,
    runners: state.runners,
  );
  if (confirmed) bloc.add(const JobViewCancelRequested());
}

String? _version(Run run) =>
    run.version == null ? null : versionLabel(run.version!, run.build);

class _JobShortcuts extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<JobViewBloc>();
    void ifCommand(VoidCallback action) {
      if (context.read<EngineConnectionBloc>().state.status.canCommand) {
        action();
      }
    }

    final state = bloc.state;
    final job = state.selectedJob;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.period, meta: true): () =>
            ifCommand(() {
              if (state.runJobs!.jobs.any((job) => !job.state.isFinished)) {
                unawaited(
                  cancelRun(
                    context,
                    state.workflowName ?? context.l10n.jobTitle,
                  ),
                );
              }
            }),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () =>
            ifCommand(() {
              if (job != null && isResumable(job.state)) {
                bloc.add(const JobViewResumeRequested(fromStep: 0));
              }
            }),
        const SingleActivator(
          LogicalKeyboardKey.keyR,
          meta: true,
          alt: true,
        ): () => ifCommand(() {
          final from = job == null || !isResumable(job.state)
              ? null
              : resumeFrom(job, state.selectedStep);
          if (from != null) bloc.add(JobViewResumeRequested(fromStep: from));
        }),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

class _Hero extends StatelessWidget {
  const new(this.state);

  final JobViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final runJobs = state.runJobs!;
    final run = runJobs.run;
    final jobs = runJobs.jobs;
    final (status, label) = heroOf(runJobs, l10n);
    final starts = [
      for (final job in jobs)
        if (job.startedAt != null) job.startedAt!,
    ]..sort();
    final ends = [
      for (final job in jobs)
        if (job.finishedAt != null) job.finishedAt!,
    ]..sort();
    final live = jobs.any((job) => job.state == JobState.running);
    final ran = starts.isEmpty
        ? null
        : elapsed(
            starts.first,
            live || ends.isEmpty ? null : ends.last,
            XpClock.now(context),
          );
    final artifacts = state.artifacts.length;
    return Row(
      children: [
        XpStatusIcon(status, size: context.xpSizes.iconLg),
        const SizedBox(width: 10),
        Text(
          label,
          style: type.hero.copyWith(color: colors.onContainer(status.pair)),
        ),
        if (_version(run) case final version?) ...[
          const SizedBox(width: 12),
          Text(
            version,
            style: type.heroCode.copyWith(color: colors.textPrimary),
          ),
        ],
        const SizedBox(width: 12),
        if (ran != null)
          Text(
            live
                ? l10n.jobElapsed(formatDuration(ran), formatTime(starts.first))
                : l10n.jobRan(formatDuration(ran), formatTime(starts.first)),
            style: type.caption.copyWith(color: colors.textSecondary),
          ),
        const Spacer(),
        if (artifacts > 0)
          Row(
            children: [
              Icon(
                PhosphorIconsRegular.package,
                size: context.xpSizes.iconSm,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.jobArtifacts(artifacts),
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

/// The hero of a run: its status and what to call it. A run with an
/// interrupted job is interrupted; a failed run says where it failed.
(XpStatus, String) heroOf(RunJobs runJobs, AppLocalizations l10n) {
  final jobs = runJobs.jobs;
  if (jobs.any(
    (job) =>
        job.state == JobState.interrupted ||
        job.state == JobState.waitingForResume,
  )) {
    return (XpStatus.jobInterrupted, l10n.statusInterrupted);
  }
  return switch (runJobs.run.state) {
    RunState.queued => (XpStatus.jobQueued, l10n.statusQueued),
    RunState.running => (XpStatus.jobRunning, l10n.statusRunning),
    RunState.waitingForApproval => (
      XpStatus.jobWaitingApproval,
      l10n.statusWaitingForApproval,
    ),
    RunState.succeeded => (XpStatus.jobSucceeded, l10n.statusSucceeded),
    RunState.cancelled => (XpStatus.jobCancelled, l10n.statusCancelled),
    RunState.failed => (XpStatus.jobFailed, _failedAt(jobs, l10n)),
  };
}

String _failedAt(List<Job> jobs, AppLocalizations l10n) {
  for (final job in jobs) {
    if (job.state != JobState.failed) continue;
    for (final step in job.steps) {
      if (step.state == StepState.failed) {
        return l10n.jobFailedAt(l10n.stepKind(step.kind));
      }
    }
  }
  return l10n.statusFailed;
}

class _InterruptedBanner extends StatelessWidget {
  const new(this.job);

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final step = job.steps
        .where(
          (step) =>
              step.state == StepState.interrupted ||
              step.state == StepState.running,
        )
        .firstOrNull;
    final name = step == null ? null : l10n.stepKind(step.kind);
    final sideEffects = job.steps.any(
      (step) => step.sideEffect && step.state == StepState.succeeded,
    );
    final text = [
      if (job.state == JobState.waitingForResume && name != null)
        l10n.jobWaitingForResumeBody(name)
      else
        l10n.jobInterruptedBody,
      if (!sideEffects) l10n.jobNothingChanged,
      ?job.message,
    ].join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: colors.statusCautionContainer,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const XpStatusIcon(XpStatus.jobInterrupted),
          const SizedBox(width: 6),
          Text(
            l10n.statusInterrupted,
            style: context.xpType.bodyStrong.copyWith(
              color: colors.statusCautionOnContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: context.xpType.body.copyWith(
                color: colors.statusCautionOnContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The log of [job], followed again whenever the job runs after its log
/// ended (a resume), from the last line it holds.
class JobLogPane extends StatelessWidget {
  const new({required this.job, this.runnerName, super.key});

  final Job job;

  /// The name of the runner the job runs on, when it is not the engine.
  final String? runnerName;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(job.id),
    create: (context) =>
        JobLogBloc(jobs: context.read<JobsRepository>(), jobId: job.id)
          ..add(const JobLogFollowRequested()),
    child: _JobLog(job: job, runnerName: runnerName),
  );
}

class _JobLog extends StatefulWidget {
  const new({required this.job, required this.runnerName});

  final Job job;
  final String? runnerName;

  @override
  State<_JobLog> createState() => _JobLogState();
}

class _JobLogState extends State<_JobLog> {
  @override
  void didUpdateWidget(_JobLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = widget.job.state;
    final bloc = context.read<JobLogBloc>();
    if (oldWidget.job.state != state &&
        bloc.state.ended != null &&
        (state == JobState.running || state == JobState.queued)) {
      bloc.add(const JobLogFollowRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final log = context.watch<JobLogBloc>().state;
    final runner = widget.runnerName;
    final ran = elapsed(job.startedAt, job.finishedAt, XpClock.now(context));
    return LogView(
      steps: job.steps,
      lines: log.lines,
      live: job.state == JobState.running,
      status: jobStatus(job.state),
      title: [
        job.name ?? job.id,
        if (job.startedAt != null) runner ?? context.engineName,
        if (ran != null) formatDuration(ran),
      ].join(' · '),
    );
  }
}
