import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';

/// The name of the engine the app shows, as the nodes of the jobs it runs
/// itself say.
extension EngineName on BuildContext {
  /// The name, rebuilding when it changes. Only while building.
  String get engineName =>
      watch<EngineConnectionBloc>().state.active?.name ?? l10n.jobEngine;

  /// The name now, for event handlers.
  String get currentEngineName =>
      read<EngineConnectionBloc>().state.active?.name ?? l10n.jobEngine;
}

/// The step a resume of [job] starts from: [selected] when every step before
/// it is done, else the first unfinished step. `null` when every step is
/// done.
int? resumeFrom(Job job, int? selected) {
  final first = job.steps.indexWhere((step) => !step.state.isDone);
  if (first < 0) return selected;
  if (selected != null && selected <= first) return selected;
  return first;
}

/// The status a job in [state] shows.
XpStatus jobStatus(JobState state) => switch (state) {
  JobState.queued => XpStatus.jobQueued,
  JobState.running => XpStatus.jobRunning,
  JobState.succeeded => XpStatus.jobSucceeded,
  JobState.failed => XpStatus.jobFailed,
  JobState.cancelled => XpStatus.jobCancelled,
  JobState.interrupted || JobState.waitingForResume => XpStatus.jobInterrupted,
  JobState.waitingForApproval => XpStatus.jobWaitingApproval,
};

/// The status a run in [state] shows.
XpStatus runStatus(RunState state) => switch (state) {
  RunState.queued => XpStatus.jobQueued,
  RunState.running => XpStatus.jobRunning,
  RunState.waitingForApproval => XpStatus.jobWaitingApproval,
  RunState.succeeded => XpStatus.jobSucceeded,
  RunState.failed => XpStatus.jobFailed,
  RunState.cancelled => XpStatus.jobCancelled,
};

/// The status a step in [state] shows.
XpStatus stepStatus(StepState state) => switch (state) {
  StepState.pending => XpStatus.jobQueued,
  StepState.running => XpStatus.jobRunning,
  StepState.succeeded => XpStatus.jobSucceeded,
  StepState.failed => XpStatus.jobFailed,
  StepState.skipped => XpStatus.jobSkipped,
  StepState.cancelled => XpStatus.jobCancelled,
  StepState.interrupted => XpStatus.jobInterrupted,
  StepState.waitingForApproval => XpStatus.jobWaitingApproval,
};

/// Whether a job in [state] stopped short and can be resumed.
bool isResumable(JobState state) =>
    state == JobState.failed ||
    state == JobState.cancelled ||
    state == JobState.interrupted ||
    state == JobState.waitingForResume;

extension JobLabels on AppLocalizations {
  /// What a job in [state] is called.
  String jobState(JobState state) => switch (state) {
    JobState.queued => statusQueued,
    JobState.running => statusRunning,
    JobState.succeeded => statusSucceeded,
    JobState.failed => statusFailed,
    JobState.cancelled => statusCancelled,
    JobState.interrupted => statusInterrupted,
    JobState.waitingForResume => statusWaitingForResume,
    JobState.waitingForApproval => statusWaitingForApproval,
  };

  /// What a run in [state] is called.
  String runState(RunState state) => switch (state) {
    RunState.queued => statusQueued,
    RunState.running => statusRunning,
    RunState.waitingForApproval => statusWaitingForApproval,
    RunState.succeeded => statusSucceeded,
    RunState.failed => statusFailed,
    RunState.cancelled => statusCancelled,
  };

  /// What a step in [state] is called.
  String stepState(StepState state) => switch (state) {
    StepState.pending => statusQueued,
    StepState.running => statusRunning,
    StepState.succeeded => statusSucceeded,
    StepState.failed => statusFailed,
    StepState.skipped => statusSkipped,
    StepState.cancelled => statusCancelled,
    StepState.interrupted => statusInterrupted,
    StepState.waitingForApproval => statusWaitingForApproval,
  };

  /// What the UI calls a step of [kind]; the kind itself for a step it does
  /// not know.
  String stepKind(String kind) => switch (kind) {
    'git.checkout' => stepGitCheckout,
    'guard' => stepGuard,
    'version.bump' => stepVersionBump,
    'build.android' => stepBuildAndroid,
    'build.ios' => stepBuildIos,
    'build.verifyCompiledConfig' => stepVerifyConfig,
    'ios.stripAndReexport' => stepStripIpa,
    'shorebird.release' => stepShorebirdRelease,
    'shorebird.patch' => stepShorebirdPatch,
    'symbols.archive' => stepSymbols,
    'test' => stepTest,
    'analyze' => stepAnalyze,
    'upload.appStore' => stepUploadAppStore,
    'upload.play' => stepUploadPlay,
    'upload.firebase' => stepUploadFirebase,
    'git.tag' => stepGitTag,
    'git.push' => stepGitPush,
    'git.releaseBranch' => stepReleaseBranch,
    'github.createPr' => stepCreatePr,
    'github.mergePr' => stepMergePr,
    'record.manifest' => stepManifest,
    'gate' => stepGate,
    'command' => stepCommand,
    _ => kind,
  };

  /// What the UI calls the gated [action] (`store_submission` → "store
  /// submission").
  String gateAction(String action) => switch (action) {
    'prod_release' => gateProdRelease,
    'prod_patch' => gateProdPatch,
    'store_submission' => gateStoreSubmission,
    'push' => gatePush,
    'merge' => gateMerge,
    'delete' => gateDelete,
    _ => action,
  };
}
