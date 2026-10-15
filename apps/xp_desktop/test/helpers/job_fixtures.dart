import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

import 'fakes.dart';

/// [hour]:[minute]:[second] on the sample day on this Mac, in UTC as the
/// engine sends it, so the UI shows the same wall clock in every time zone.
DateTime local(int hour, int minute, [int second = 0]) =>
    DateTime(2026, 10, 13, hour, minute, second).toUtc();

const sha = '9a3bc0d4e5f60718293a4b5c6d7e8f9012345678';

const workflowYaml = '''
name: Prod release
lock: project
stages:
  - name: preflight
    jobs:
      preflight:
        steps:
          - kind: guard
  - name: build
    jobs:
      build:
        steps:
          - kind: build.ios
  - name: upload
    jobs:
      upload:
        steps:
          - kind: upload.appStore
  - name: record
    jobs:
      tag:
        steps:
          - kind: git.tag
''';

final prodWorkflow = Workflow(
  id: 'wf_prod',
  projectId: 'prj_1',
  name: 'Prod release',
  builtin: true,
  version: WorkflowVersionInfo(id: 'wfv_1', version: 1, createdAt: at),
  versions: [WorkflowVersionInfo(id: 'wfv_1', version: 1, createdAt: at)],
  yaml: workflowYaml,
);

const linuxBuilder = 'rnr_1';

final linuxRunner = Runner(
  id: linuxBuilder,
  name: 'linux-builder-01',
  status: RunnerStatus.online,
  capabilities: const ['android', 'flutter'],
  slots: 4,
  jobIds: const ['job_android'],
  createdAt: at,
);

JobStep step(
  int ordinal,
  String kind,
  StepState state, {
  DateTime? start,
  DateTime? end,
  bool sideEffect = false,
}) => JobStep(
  ordinal: ordinal,
  kind: kind,
  state: state,
  sideEffect: sideEffect,
  attempts: start == null ? 0 : 1,
  startedAt: start,
  finishedAt: end,
);

Job job(
  String id,
  String name,
  int stage,
  JobState state, {
  List<JobStep> steps = const [],
  DateTime? start,
  DateTime? end,
  String? runnerId,
  String? message,
}) => Job(
  id: id,
  projectId: 'prj_1',
  workflowVersionId: 'wfv_1',
  runId: 'run_1',
  sha: sha,
  name: name,
  stage: stage,
  state: state,
  runnerId: runnerId,
  createdAt: local(14, 2),
  startedAt: start,
  finishedAt: end,
  message: message,
  steps: steps,
);

/// The run of `Job-A-Graph`: preflight done, iOS building on the engine,
/// Android built on a runner, upload and tag still queued.
RunJobs runningRun({
  JobState iosState = JobState.running,
  StepState buildState = StepState.running,
  RunState runState = RunState.running,
  DateTime? iosEnd,
}) {
  final jobs = [
    job(
      'job_preflight',
      'Preflight prod',
      0,
      JobState.succeeded,
      start: local(14, 2),
      end: local(14, 2, 41),
      steps: [
        step(
          0,
          'guard',
          StepState.succeeded,
          start: local(14, 2),
          end: local(14, 2, 41),
        ),
      ],
    ),
    job(
      'job_ios',
      'Build prod for ios',
      1,
      iosState,
      start: local(14, 2, 43),
      end: iosEnd,
      steps: [
        step(
          0,
          'git.checkout',
          StepState.succeeded,
          start: local(14, 2, 43),
          end: local(14, 2, 47),
        ),
        step(
          1,
          'version.bump',
          StepState.succeeded,
          start: local(14, 2, 47),
          end: local(14, 3, 8),
        ),
        step(2, 'build.ios', buildState, start: local(14, 3, 8), end: iosEnd),
        step(3, 'symbols.archive', StepState.pending),
        step(4, 'record.manifest', StepState.pending),
      ],
    ),
    job(
      'job_android',
      'Build prod for android',
      1,
      JobState.succeeded,
      runnerId: linuxBuilder,
      start: local(14, 2, 43),
      end: local(14, 7, 38),
      steps: [
        step(
          0,
          'git.checkout',
          StepState.succeeded,
          start: local(14, 2, 43),
          end: local(14, 2, 50),
        ),
        step(
          1,
          'build.android',
          StepState.succeeded,
          start: local(14, 2, 50),
          end: local(14, 7, 38),
        ),
      ],
    ),
    job(
      'job_upload',
      'Upload prod for ios',
      2,
      JobState.queued,
      steps: [step(0, 'upload.appStore', StepState.pending, sideEffect: true)],
    ),
    job(
      'job_tag',
      'Tag prod',
      3,
      JobState.queued,
      steps: [step(0, 'git.tag', StepState.pending, sideEffect: true)],
    ),
  ];
  return RunJobs(
    run: Run(
      id: 'run_1',
      projectId: 'prj_1',
      workflowId: 'wf_prod',
      workflowVersionId: 'wfv_1',
      sha: sha,
      ref: 'release/5.4.1',
      state: runState,
      locksProject: true,
      version: '5.4.1',
      build: 3283,
      createdAt: local(14, 2),
      jobs: [
        for (final job in jobs)
          RunJob(
            id: job.id,
            name: job.name!,
            stage: job.stage!,
            state: job.state,
          ),
      ],
    ),
    jobs: jobs,
  );
}

/// The run of `Job-A-Failed`: the iOS build failed at the archive step.
RunJobs failedRun() => runningRun(
  iosState: JobState.failed,
  buildState: StepState.failed,
  runState: RunState.failed,
  iosEnd: local(14, 8, 30),
);

/// The run of `Job-A-Interrupted`: the engine restarted during the build.
RunJobs interruptedRun() => runningRun(
  iosState: JobState.interrupted,
  buildState: StepState.interrupted,
  iosEnd: local(14, 8, 30),
);

LogLineFrame line(
  int seq,
  int step,
  String text, {
  DateTime? at,
  LogStream stream = LogStream.stdout,
}) => LogLineFrame(
  seq: seq,
  step: step,
  at: at ?? local(14, 3, 6),
  stream: stream,
  text: text,
);

/// The log of the iOS build as `Job-A-Graph` shows it.
final List<LogLineFrame> iosLog = [
  line(1, 0, 'Checking out 9a3bc0d'),
  line(2, 0, 'HEAD is now at 9a3bc0d'),
  line(3, 1, 'Version 5.4.1+3283'),
  line(
    210,
    2,
    '\x1B[2m[xp] step 3/5 Build iOS · This Mac · Flutter 3.47.6\x1B[0m',
  ),
  line(
    212,
    2,
    '\x1B[1m\$ flutter build ipa --release --flavor prod '
    '--build-name 5.4.1 --build-number 3283\x1B[0m',
  ),
  line(213, 2, 'Running pod install...', at: local(14, 3, 9)),
  line(
    215,
    2,
    '\x1B[32mPod installation complete!\x1B[0m',
    at: local(14, 3, 16),
  ),
  line(
    217,
    2,
    "\x1B[33mwarning: Run script build phase '[CP] Embed Pods Frameworks' "
    'will be run during every build\x1B[0m',
    at: local(14, 3, 21),
    stream: LogStream.stderr,
  ),
  line(
    219,
    2,
    '\x1B[32m✓\x1B[0m Xcode archive done. \x1B[1m312.4s\x1B[0m',
    at: local(14, 8, 30),
  ),
  line(220, 2, 'Building App Store IPA...', at: local(14, 8, 31)),
];

/// The log of the failed build.
final List<LogLineFrame> failedLog = [
  ...iosLog.take(5),
  line(
    221,
    2,
    '\x1B[31;1m*** Error: Error exporting the archive.\x1B[0m',
    at: local(14, 8, 30),
    stream: LogStream.stderr,
  ),
];

final iosArtifacts = [
  Artifact(
    id: 'art_1',
    jobId: 'job_ios',
    kind: ArtifactKind.values.first,
    name: 'mataa.ipa',
    size: 48200000,
    sha256: 'abc',
    pinned: false,
    createdAt: at,
  ),
];
