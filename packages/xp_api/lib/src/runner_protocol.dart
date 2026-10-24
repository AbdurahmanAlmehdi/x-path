import 'package:equatable/equatable.dart';
import 'package:xp_api/src/job.dart';
import 'package:xp_api/src/job_logs.dart';

/// How long a lease lasts after the last heartbeat that renewed it (D-08).
const runnerLeaseSeconds = 90;

/// How often the engine asks a runner to send a heartbeat: three times per
/// lease.
const runnerHeartbeatSeconds = 30;

/// WebSocket close code of a runner connection that another connection of
/// the same runner replaced.
const runnerReplacedCloseCode = 4001;

/// WebSocket close code of a runner connection whose runner was revoked.
const runnerRevokedCloseCode = 4003;

/// WebSocket close code of a runner connection that went quiet: no frame for
/// a whole lease, or no answer to the probe.
const runnerTimeoutCloseCode = 4008;

/// WebSocket close code of a runner connection that broke the protocol: it
/// sent something that is not a frame, or the first frame was not `hello`.
const runnerProtocolCloseCode = 4400;

/// The reading of a frame failed: a field is missing or of the wrong type.
FormatException _bad(String message) => FormatException(message);

T _required<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw _bad('"$key" is missing or not a $T.');
}

T? _optional<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is T) return value;
  throw _bad('"$key" is not a $T.');
}

List<T> _list<T>(Map<String, dynamic> json, String key) {
  final value = _required<List<dynamic>>(json, key);
  if (value.every((item) => item is T)) return value.cast<T>();
  throw _bad('"$key" has an item that is not a $T.');
}

List<T> _objects<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic> json) read,
) => [
  for (final item in _list<Object?>(json, key))
    if (item is Map<String, dynamic>)
      read(item)
    else
      throw _bad('"$key" has an item that is not an object.'),
];

E _enum<E extends Enum>(
  Map<String, dynamic> json,
  String key,
  List<E> values, [
  String Function(E value)? wire,
]) {
  final name = _required<String>(json, key);
  for (final value in values) {
    if ((wire?.call(value) ?? value.name) == name) return value;
  }
  throw _bad('"$key" is not one of the known values: "$name".');
}

DateTime _time(Map<String, dynamic> json, String key) =>
    DateTime.parse(_required<String>(json, key));

DateTime? _optionalTime(Map<String, dynamic> json, String key) {
  final text = _optional<String>(json, key);
  return text == null ? null : DateTime.parse(text);
}

String _iso(DateTime time) => time.toUtc().toIso8601String();

/// A lease, as both sides name it: the job and the id of this lease of it.
///
/// A job that is leased again after a lease was lost gets a new id, so a
/// runner that comes back after a lapse cannot touch the new lease.
final class LeaseRef extends Equatable {
  /// Creates the reference.
  const new({required this.jobId, required this.leaseId});

  /// Reads the reference from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LeaseRef(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
  );

  /// The job.
  final String jobId;

  /// The lease, for example `lse_1a2b3c4d5e6f7a8b`.
  final String leaseId;

  /// The JSON form.
  Map<String, dynamic> toJson() => {'jobId': jobId, 'leaseId': leaseId};

  @override
  List<Object?> get props => [jobId, leaseId];
}

/// A lease the engine renewed: it holds until [until].
final class LeaseGrant extends Equatable {
  /// Creates the grant.
  const new({required this.jobId, required this.leaseId, required this.until});

  /// Reads the grant from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LeaseGrant(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    until: _time(json, 'until'),
  );

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// When the lease runs out unless the runner sends another heartbeat, in
  /// UTC.
  final DateTime until;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'jobId': jobId,
    'leaseId': leaseId,
    'until': _iso(until),
  };

  @override
  List<Object?> get props => [jobId, leaseId, until];
}

/// The repository a leased job builds, as the runner reaches it with its own
/// access to GitHub (ADR 0009).
///
/// The offer names the repository and the commit and nothing else: it never
/// carries a credential. The runner keeps a bare cache per repository, keyed
/// by [githubRepoId], fetches the commit over SSH and checks it out in a
/// worktree of its own.
final class LeaseRepository extends Equatable {
  /// Creates the repository.
  const new({required this.githubRepoId, required this.sshUrl});

  /// Reads the repository from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LeaseRepository(
    githubRepoId: _required<int>(json, 'githubRepoId'),
    sshUrl: _required<String>(json, 'sshUrl'),
  );

  /// The id GitHub gave the repository. It survives renames, so it keys the
  /// runner's cache.
  final int githubRepoId;

  /// The SSH URL to fetch from, for example `git@github.com:owner/app.git`.
  final String sshUrl;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'githubRepoId': githubRepoId,
    'sshUrl': sshUrl,
  };

  @override
  List<Object?> get props => [githubRepoId, sshUrl];
}

/// A step of a job the engine leases to a runner.
final class LeaseStep extends Equatable {
  /// Creates the step.
  const new({
    required this.ordinal,
    required this.kind,
    required this.sideEffect,
    required this.state,
    required this.attempts,
    required this.input,
  });

  /// Reads the step from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LeaseStep(
    ordinal: _required<int>(json, 'ordinal'),
    kind: _required<String>(json, 'kind'),
    sideEffect: _required<bool>(json, 'sideEffect'),
    state: _enum(json, 'state', StepState.values),
    attempts: _required<int>(json, 'attempts'),
    input: _required<Map<String, dynamic>>(json, 'input'),
  );

  /// Its position in the job, from 0.
  final int ordinal;

  /// The step type.
  final String kind;

  /// Whether it has side effects (D-18). The engine decides; a runner cannot
  /// change it.
  final bool sideEffect;

  /// Where the step is. A step that is `succeeded` or `skipped` is done: the
  /// runner continues at the first step that is not.
  final StepState state;

  /// How many times the step was started before.
  final int attempts;

  /// The input the step stored.
  final Map<String, dynamic> input;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'ordinal': ordinal,
    'kind': kind,
    'sideEffect': sideEffect,
    'state': state.name,
    'attempts': attempts,
    'input': input,
  };

  @override
  List<Object?> get props => [
    ordinal,
    kind,
    sideEffect,
    state,
    attempts,
    input,
  ];
}

/// A command the engine has a runner run to find out what it can do (D-19).
///
/// Probe commands only ask for versions or look for folders. A runner runs
/// exactly these, in order, with the environment it runs jobs with.
final class ProbeCommand extends Equatable {
  /// Creates the command.
  const new({
    required this.id,
    required this.executable,
    this.arguments = const [],
    this.timeoutSeconds = 30,
    this.requires,
    this.onlyOn,
  });

  /// Reads the command from its JSON form.
  factory fromJson(Map<String, dynamic> json) => ProbeCommand(
    id: _required<String>(json, 'id'),
    executable: _required<String>(json, 'executable'),
    arguments: _list<String>(json, 'arguments'),
    timeoutSeconds: _required<int>(json, 'timeoutSeconds'),
    requires: _optional<String>(json, 'requires'),
    onlyOn: _optional<String>(json, 'onlyOn'),
  );

  /// Names the command in the result.
  final String id;

  /// The program.
  final String executable;

  /// Its arguments.
  final List<String> arguments;

  /// How long it has to finish.
  final int timeoutSeconds;

  /// The id of a command that must have exited with 0 first. When it did
  /// not, this one is skipped. (`xcodebuild` is only run once `xcode-select`
  /// found an Xcode: on a Mac without developer tools it opens a dialog.)
  final String? requires;

  /// `macos` or `linux`: skip the command on any other operating system.
  final String? onlyOn;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'id': id,
    'executable': executable,
    'arguments': arguments,
    'timeoutSeconds': timeoutSeconds,
    'requires': ?requires,
    'onlyOn': ?onlyOn,
  };

  @override
  List<Object?> get props => [
    id,
    executable,
    arguments,
    timeoutSeconds,
    requires,
    onlyOn,
  ];
}

/// What happened to a [ProbeCommand] on the runner.
enum ProbeStatus {
  /// It ran and exited; see `exitCode`.
  exited('exited'),

  /// It was not run: `requires` did not hold or `onlyOn` did not match.
  skipped('skipped'),

  /// The program could not be started (it is not installed).
  notStarted('not_started'),

  /// It did not finish in time and was stopped.
  timedOut('timed_out');

  new(this.wire);

  /// The name on the wire.
  final String wire;
}

/// The outcome of one [ProbeCommand].
final class ProbeResult extends Equatable {
  /// Creates the result.
  const new({
    required this.id,
    required this.status,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  /// Reads the result from its JSON form.
  factory fromJson(Map<String, dynamic> json) => ProbeResult(
    id: _required<String>(json, 'id'),
    status: _enum(json, 'status', ProbeStatus.values, (s) => s.wire),
    exitCode: _optional<int>(json, 'exitCode'),
    stdout: _optional<String>(json, 'stdout') ?? '',
    stderr: _optional<String>(json, 'stderr') ?? '',
  );

  /// The id of the command.
  final String id;

  /// What happened.
  final ProbeStatus status;

  /// The exit code, when the command [ProbeStatus.exited].
  final int? exitCode;

  /// What it printed on standard output, cut at 64 KiB.
  final String stdout;

  /// What it printed on standard error, cut at 64 KiB.
  final String stderr;

  /// Whether the command ran and exited with 0.
  bool get succeeded => status == ProbeStatus.exited && exitCode == 0;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.wire,
    'exitCode': ?exitCode,
    'stdout': stdout,
    'stderr': stderr,
  };

  @override
  List<Object?> get props => [id, status, exitCode, stdout, stderr];
}

/// A capability a machine does not offer, why, and what gives it.
///
/// The engine derives it from the probe results, like the capabilities, so
/// the engine, the runner and `xp runner doctor` say the same thing.
final class MissingCapability extends Equatable {
  /// Creates the finding.
  const new({
    required this.capability,
    required this.reason,
    required this.fix,
  });

  /// Reads the finding from its JSON form.
  factory fromJson(Map<String, dynamic> json) => MissingCapability(
    capability: _required<String>(json, 'capability'),
    reason: _required<String>(json, 'reason'),
    fix: _required<String>(json, 'fix'),
  );

  /// The wire name of the capability, for example `android`.
  final String capability;

  /// Why it is missing, one sentence without its full stop, for example `no
  /// JDK: java not found`.
  final String reason;

  /// What gives it, one sentence without its full stop, for example `install
  /// JDK 17 or set JAVA_HOME`.
  final String fix;

  /// The reason and the fix as two sentences: `no JDK: java not found.
  /// Install JDK 17 or set JAVA_HOME.`
  String get explanation => fix.isEmpty
      ? '$reason.'
      : '$reason. ${fix[0].toUpperCase()}${fix.substring(1)}.';

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'capability': capability,
    'reason': reason,
    'fix': fix,
  };

  @override
  List<Object?> get props => [capability, reason, fix];
}

/// One line of output in a [LogChunkFrame].
final class ChunkLine extends Equatable {
  /// Creates the line.
  const new({
    required this.step,
    required this.at,
    required this.stream,
    required this.text,
  });

  /// Reads the line from its JSON form.
  factory fromJson(Map<String, dynamic> json) => ChunkLine(
    step: _required<int>(json, 'step'),
    at: _time(json, 'at'),
    stream: _enum(json, 'stream', LogStream.values),
    text: _required<String>(json, 'text'),
  );

  /// The ordinal of the step that wrote it.
  final int step;

  /// When the runner read it, in UTC.
  final DateTime at;

  /// Where it came from.
  final LogStream stream;

  /// The line without its line ending. The engine masks it again before it
  /// stores it.
  final String text;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'step': step,
    'at': _iso(at),
    'stream': stream.name,
    'text': text,
  };

  @override
  List<Object?> get props => [step, at, stream, text];
}

/// What the engine did with a [LogChunkFrame].
enum ChunkStatus {
  /// It was the next chunk and its lines are in the log.
  stored('stored'),

  /// The engine had it already; nothing was stored.
  duplicate('duplicate'),

  /// An earlier chunk is missing. Nothing was stored; the runner sends the
  /// chunks from `next` on again.
  gap('gap');

  new(this.wire);

  /// The name on the wire.
  final String wire;
}

/// A frame the runner sends to the engine over `GET /runners/connect`.
///
/// Every frame is a JSON object with a `type`. The engine answers a frame it
/// cannot read with a [FaultFrame]; a type this engine does not know becomes
/// an [UnknownRunnerFrame].
sealed class RunnerFrame extends Equatable {
  const new();

  /// Reads a frame from its JSON form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final type = _required<String>(json, 'type');
    return switch (type) {
      HelloFrame.frameType => HelloFrame.fromJson(json),
      ProbeResultFrame.frameType => ProbeResultFrame.fromJson(json),
      LeaseAcceptFrame.frameType => LeaseAcceptFrame.fromJson(json),
      LeaseRejectFrame.frameType => LeaseRejectFrame.fromJson(json),
      HeartbeatFrame.frameType => HeartbeatFrame.fromJson(json),
      LogChunkFrame.frameType => LogChunkFrame.fromJson(json),
      StepStateFrame.frameType => StepStateFrame.fromJson(json),
      JobDoneFrame.frameType => JobDoneFrame.fromJson(json),
      SecretRequestFrame.frameType => SecretRequestFrame.fromJson(json),
      DrainFrame.frameType => DrainFrame.fromJson(json),
      _ => UnknownRunnerFrame(type: type, payload: json),
    };
  }

  /// The wire name of the frame.
  String get type;

  /// The JSON form.
  Map<String, dynamic> toJson();
}

/// The first frame of a connection, after the engine's [WelcomeFrame].
final class HelloFrame extends RunnerFrame {
  /// Creates the frame.
  const new({
    required this.version,
    required this.os,
    required this.arch,
    required this.cores,
    this.maxJobs,
    this.draining = false,
    this.leases = const [],
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => HelloFrame(
    version: _required<String>(json, 'version'),
    os: _required<String>(json, 'os'),
    arch: _required<String>(json, 'arch'),
    cores: _required<int>(json, 'cores'),
    maxJobs: _optional<int>(json, 'maxJobs'),
    draining: _optional<bool>(json, 'draining') ?? false,
    leases: _objects(json, 'leases', LeaseRef.fromJson),
  );

  /// The wire name of this frame.
  static const frameType = 'hello';

  /// The `xp` version of the runner.
  final String version;

  /// The operating system, for example `macos`. Shown to the owner; the
  /// engine learns what the machine can do from the probe.
  final String os;

  /// The processor architecture, for example `arm64`.
  final String arch;

  /// The processor cores. The slots default to a quarter of them (D-19).
  final int cores;

  /// The most jobs the owner lets the runner run at once; replaces the
  /// default slots.
  final int? maxJobs;

  /// Whether the runner is draining already.
  final bool draining;

  /// The leases the runner still holds (it reconnected with jobs under way).
  final List<LeaseRef> leases;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'version': version,
    'os': os,
    'arch': arch,
    'cores': cores,
    'maxJobs': ?maxJobs,
    'draining': draining,
    'leases': [for (final lease in leases) lease.toJson()],
  };

  @override
  List<Object?> get props => [
    version,
    os,
    arch,
    cores,
    maxJobs,
    draining,
    leases,
  ];
}

/// The answer to a [ProbeFrame].
final class ProbeResultFrame extends RunnerFrame {
  /// Creates the frame.
  const new({required this.probeId, required this.results, this.iosLinuxDir});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => ProbeResultFrame(
    probeId: _required<String>(json, 'probeId'),
    results: _objects(json, 'results', ProbeResult.fromJson),
    iosLinuxDir: _optional<String>(json, 'iosLinuxDir'),
  );

  /// The wire name of this frame.
  static const frameType = 'probe_result';

  /// The id of the probe.
  final String probeId;

  /// One result per command, in the order of the commands, then one per
  /// command of the omarchy-apple-dev checkout when [iosLinuxDir] is set.
  final List<ProbeResult> results;

  /// The omarchy-apple-dev checkout of a runner configured to build iOS apps
  /// on Linux (`XP_IOS_LINUX_DIR`), whose probe commands the runner ran
  /// after the engine's; `null` for a runner that is not.
  final String? iosLinuxDir;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'probeId': probeId,
    'results': [for (final result in results) result.toJson()],
    'iosLinuxDir': ?iosLinuxDir,
  };

  @override
  List<Object?> get props => [probeId, results, iosLinuxDir];
}

/// The runner takes the job offered.
final class LeaseAcceptFrame extends RunnerFrame {
  /// Creates the frame.
  const new({required this.jobId, required this.leaseId});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LeaseAcceptFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
  );

  /// The wire name of this frame.
  static const frameType = 'lease_accept';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
  };

  @override
  List<Object?> get props => [jobId, leaseId];
}

/// The runner cannot take the job offered. The engine puts the job back in
/// the queue.
final class LeaseRejectFrame extends RunnerFrame {
  /// Creates the frame.
  const new({required this.jobId, required this.leaseId, required this.reason});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LeaseRejectFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    reason: _required<String>(json, 'reason'),
  );

  /// The wire name of this frame.
  static const frameType = 'lease_reject';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// Why, for the owner: for example `busy` or `draining`.
  final String reason;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'reason': reason,
  };

  @override
  List<Object?> get props => [jobId, leaseId, reason];
}

/// Renews the leases the runner holds. Idle runners send it too, so that the
/// engine knows they are there.
final class HeartbeatFrame extends RunnerFrame {
  /// Creates the frame.
  const new({this.leases = const []});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) =>
      HeartbeatFrame(leases: _objects(json, 'leases', LeaseRef.fromJson));

  /// The wire name of this frame.
  static const frameType = 'heartbeat';

  /// The leases the runner holds. The engine renews those it knows and
  /// cancels the others.
  final List<LeaseRef> leases;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'leases': [for (final lease in leases) lease.toJson()],
  };

  @override
  List<Object?> get props => [leases];
}

/// Output lines of a leased job.
///
/// Chunks are numbered from 1 per lease. The engine stores the next chunk,
/// ignores one it has (a duplicate) and ignores one that skips ahead (a
/// gap); each is answered with a [ChunkAckFrame]. The runner keeps the
/// chunks until they are acknowledged and sends again from `next` on after a
/// gap or a reconnect.
final class LogChunkFrame extends RunnerFrame {
  /// Creates the frame.
  const new({
    required this.jobId,
    required this.leaseId,
    required this.seq,
    required this.lines,
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LogChunkFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    seq: _required<int>(json, 'seq'),
    lines: _objects(json, 'lines', ChunkLine.fromJson),
  );

  /// The wire name of this frame.
  static const frameType = 'log_chunk';

  /// The most lines a chunk may have.
  static const maxLines = 5000;

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The number of the chunk in this lease, from 1.
  final int seq;

  /// The lines, in order.
  final List<ChunkLine> lines;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'seq': seq,
    'lines': [for (final line in lines) line.toJson()],
  };

  @override
  List<Object?> get props => [jobId, leaseId, seq, lines];
}

/// Where a step of a leased job is. Sending it again changes nothing.
final class StepStateFrame extends RunnerFrame {
  /// Creates the frame.
  const new({
    required this.jobId,
    required this.leaseId,
    required this.ordinal,
    required this.state,
    required this.attempts,
    this.result,
    this.message,
    this.startedAt,
    this.finishedAt,
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => StepStateFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    ordinal: _required<int>(json, 'ordinal'),
    state: _enum(json, 'state', StepState.values),
    attempts: _required<int>(json, 'attempts'),
    result: _optional<Map<String, dynamic>>(json, 'result'),
    message: _optional<String>(json, 'message'),
    startedAt: _optionalTime(json, 'startedAt'),
    finishedAt: _optionalTime(json, 'finishedAt'),
  );

  /// The wire name of this frame.
  static const frameType = 'step_state';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The step.
  final int ordinal;

  /// Where it is.
  final StepState state;

  /// How many times the step was started, this time included. A report with
  /// fewer attempts than the engine has is out of date and ignored.
  final int attempts;

  /// What it produced, once it succeeded.
  final Map<String, dynamic>? result;

  /// Why it failed or was skipped.
  final String? message;

  /// When this attempt started, in UTC.
  final DateTime? startedAt;

  /// When this attempt ended, in UTC.
  final DateTime? finishedAt;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'ordinal': ordinal,
    'state': state.name,
    'attempts': attempts,
    'result': ?result,
    'message': ?message,
    'startedAt': ?(startedAt == null ? null : _iso(startedAt!)),
    'finishedAt': ?(finishedAt == null ? null : _iso(finishedAt!)),
  };

  @override
  List<Object?> get props => [
    jobId,
    leaseId,
    ordinal,
    state,
    attempts,
    result,
    message,
    startedAt,
    finishedAt,
  ];
}

/// The runner ended the job. The engine answers with a [DoneAckFrame] once
/// the job is recorded; until then the runner keeps what it has to resend.
final class JobDoneFrame extends RunnerFrame {
  /// Creates the frame.
  const new({
    required this.jobId,
    required this.leaseId,
    required this.state,
    required this.lastChunk,
    this.message,
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) {
    final state = _enum(json, 'state', JobState.values, (s) => s.wire);
    if (state != JobState.succeeded &&
        state != JobState.failed &&
        state != JobState.cancelled) {
      throw _bad(
        '"state" of a finished job is succeeded, failed or cancelled.',
      );
    }
    return JobDoneFrame(
      jobId: _required<String>(json, 'jobId'),
      leaseId: _required<String>(json, 'leaseId'),
      state: state,
      lastChunk: _required<int>(json, 'lastChunk'),
      message: _optional<String>(json, 'message'),
    );
  }

  /// The wire name of this frame.
  static const frameType = 'job_done';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// How it ended: `succeeded`, `failed` or `cancelled`.
  final JobState state;

  /// The number of the last [LogChunkFrame] the runner sent, 0 if none. The
  /// engine ends the job only when it has the log up to there.
  final int lastChunk;

  /// Why it failed.
  final String? message;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'state': state.wire,
    'lastChunk': lastChunk,
    'message': ?message,
  };

  @override
  List<Object?> get props => [jobId, leaseId, state, lastChunk, message];
}

/// The runner asks for a secret of the leased job (D-09, ADR 0012). The engine
/// gives signing material and the Shorebird key that the job's steps name,
/// once per lease.
final class SecretRequestFrame extends RunnerFrame {
  /// Creates the frame.
  const new({required this.jobId, required this.leaseId, required this.key});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => SecretRequestFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    key: _required<String>(json, 'key'),
  );

  /// The wire name of this frame.
  static const frameType = 'secret_request';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The key, one of the `secrets` of the [LeaseOfferFrame].
  final String key;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'key': key,
  };

  @override
  List<Object?> get props => [jobId, leaseId, key];
}

/// The runner starts or stops draining: with `true` it asks for no more
/// jobs and finishes the ones it holds.
final class DrainFrame extends RunnerFrame {
  /// Creates the frame.
  const new({this.draining = true});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) =>
      DrainFrame(draining: _required<bool>(json, 'draining'));

  /// The wire name of this frame.
  static const frameType = 'drain';

  /// Whether the runner drains.
  final bool draining;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {'type': frameType, 'draining': draining};

  @override
  List<Object?> get props => [draining];
}

/// A frame of a type this engine does not know.
final class UnknownRunnerFrame extends RunnerFrame {
  /// Creates the frame.
  const new({required this.type, required this.payload});

  @override
  final String type;

  /// The whole object.
  final Map<String, dynamic> payload;

  @override
  Map<String, dynamic> toJson() => payload;

  @override
  List<Object?> get props => [type, payload];
}

/// A frame the engine sends to the runner over `GET /runners/connect`. A
/// runner ignores a type it does not know ([UnknownEngineFrame]).
sealed class EngineFrame extends Equatable {
  const new();

  /// Reads a frame from its JSON form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final type = _required<String>(json, 'type');
    return switch (type) {
      WelcomeFrame.frameType => WelcomeFrame.fromJson(json),
      ProbeFrame.frameType => ProbeFrame.fromJson(json),
      ProbedFrame.frameType => ProbedFrame.fromJson(json),
      LeaseOfferFrame.frameType => LeaseOfferFrame.fromJson(json),
      HeartbeatAckFrame.frameType => HeartbeatAckFrame.fromJson(json),
      ChunkAckFrame.frameType => ChunkAckFrame.fromJson(json),
      DoneAckFrame.frameType => DoneAckFrame.fromJson(json),
      CancelFrame.frameType => CancelFrame.fromJson(json),
      SecretValueFrame.frameType => SecretValueFrame.fromJson(json),
      SecretDeniedFrame.frameType => SecretDeniedFrame.fromJson(json),
      FaultFrame.frameType => FaultFrame.fromJson(json),
      _ => UnknownEngineFrame(type: type, payload: json),
    };
  }

  /// The wire name of the frame.
  String get type;

  /// The JSON form.
  Map<String, dynamic> toJson();
}

/// The first frame of a connection: the engine accepted the credential.
final class WelcomeFrame extends EngineFrame {
  /// Creates the frame.
  const new({
    required this.runnerId,
    required this.engineVersion,
    required this.apiVersion,
    this.heartbeatSeconds = runnerHeartbeatSeconds,
    this.leaseSeconds = runnerLeaseSeconds,
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => WelcomeFrame(
    runnerId: _required<String>(json, 'runnerId'),
    engineVersion: _required<String>(json, 'engineVersion'),
    apiVersion: _required<String>(json, 'apiVersion'),
    heartbeatSeconds: _required<int>(json, 'heartbeatSeconds'),
    leaseSeconds: _required<int>(json, 'leaseSeconds'),
  );

  /// The wire name of this frame.
  static const frameType = 'welcome';

  /// The runner's id.
  final String runnerId;

  /// The engine's version.
  final String engineVersion;

  /// The major version of the API the engine serves.
  final String apiVersion;

  /// How often the runner sends a heartbeat.
  final int heartbeatSeconds;

  /// How long a lease lasts after a heartbeat.
  final int leaseSeconds;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'runnerId': runnerId,
    'engineVersion': engineVersion,
    'apiVersion': apiVersion,
    'heartbeatSeconds': heartbeatSeconds,
    'leaseSeconds': leaseSeconds,
  };

  @override
  List<Object?> get props => [
    runnerId,
    engineVersion,
    apiVersion,
    heartbeatSeconds,
    leaseSeconds,
  ];
}

/// Asks the runner to run [commands] and answer with a [ProbeResultFrame]
/// (D-19). Sent after every `hello`.
final class ProbeFrame extends EngineFrame {
  /// Creates the frame.
  const new({required this.probeId, required this.commands});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => ProbeFrame(
    probeId: _required<String>(json, 'probeId'),
    commands: _objects(json, 'commands', ProbeCommand.fromJson),
  );

  /// The wire name of this frame.
  static const frameType = 'probe';

  /// Names the probe in the answer.
  final String probeId;

  /// The commands, in order.
  final List<ProbeCommand> commands;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'probeId': probeId,
    'commands': [for (final command in commands) command.toJson()],
  };

  @override
  List<Object?> get props => [probeId, commands];
}

/// What the engine concluded from a [ProbeResultFrame]: the capabilities it
/// stored for the runner, and why it has no others. Sent after every probe.
final class ProbedFrame extends EngineFrame {
  /// Creates the frame.
  const new({required this.capabilities, this.missing = const []});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => ProbedFrame(
    capabilities: _list<String>(json, 'capabilities'),
    missing: _objects(json, 'missing', MissingCapability.fromJson),
  );

  /// The wire name of this frame.
  static const frameType = 'probed';

  /// The wire names of what the runner can do, sorted.
  final List<String> capabilities;

  /// What it cannot do on its operating system, and why.
  final List<MissingCapability> missing;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'capabilities': capabilities,
    'missing': [for (final item in missing) item.toJson()],
  };

  @override
  List<Object?> get props => [capabilities, missing];
}

/// Offers the runner a job. The lease holds until [expiresAt] unless the
/// runner accepts and sends heartbeats.
final class LeaseOfferFrame extends EngineFrame {
  /// Creates the frame.
  const new({
    required this.leaseId,
    required this.jobId,
    required this.projectId,
    required this.stage,
    required this.capabilities,
    required this.expiresAt,
    required this.steps,
    this.sha,
    this.name,
    this.repository,
    this.secrets = const [],
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => LeaseOfferFrame(
    leaseId: _required<String>(json, 'leaseId'),
    jobId: _required<String>(json, 'jobId'),
    projectId: _required<String>(json, 'projectId'),
    sha: _optional<String>(json, 'sha'),
    name: _optional<String>(json, 'name'),
    repository: switch (_optional<Map<String, dynamic>>(json, 'repository')) {
      final repository? => LeaseRepository.fromJson(repository),
      null => null,
    },
    stage: _required<int>(json, 'stage'),
    capabilities: _list<String>(json, 'capabilities'),
    expiresAt: _time(json, 'expiresAt'),
    steps: _objects(json, 'steps', LeaseStep.fromJson),
    secrets: _list<String>(json, 'secrets'),
  );

  /// The wire name of this frame.
  static const frameType = 'lease_offer';

  /// The lease.
  final String leaseId;

  /// The job.
  final String jobId;

  /// The project.
  final String projectId;

  /// The exact commit the job builds, in full. It is the dispatched commit,
  /// or, for a job that starts from the version commit of an earlier job of
  /// its run, that commit. The runner checks out this commit and verifies its
  /// head before it runs anything (ADR 0009).
  final String? sha;

  /// What the workflow calls the job.
  final String? name;

  /// Where the runner gets the commit from; see [LeaseRepository].
  final LeaseRepository? repository;

  /// The stage of the job in its run.
  final int stage;

  /// The capabilities the job needs.
  final List<String> capabilities;

  /// When the lease runs out unless it is renewed, in UTC.
  final DateTime expiresAt;

  /// The steps, with where each is. The runner continues at the first one
  /// that is not done.
  final List<LeaseStep> steps;

  /// The keys of the secrets the job may ask for with a [SecretRequestFrame]:
  /// signing material (D-09) and the Shorebird key (ADR 0012). Keys only,
  /// never values.
  final List<String> secrets;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'leaseId': leaseId,
    'jobId': jobId,
    'projectId': projectId,
    'sha': ?sha,
    'name': ?name,
    'repository': ?repository?.toJson(),
    'stage': stage,
    'capabilities': capabilities,
    'expiresAt': _iso(expiresAt),
    'steps': [for (final step in steps) step.toJson()],
    'secrets': secrets,
  };

  @override
  List<Object?> get props => [
    leaseId,
    jobId,
    projectId,
    sha,
    name,
    repository,
    stage,
    capabilities,
    expiresAt,
    steps,
    secrets,
  ];
}

/// The answer to a [HeartbeatFrame]: the leases that were renewed.
final class HeartbeatAckFrame extends EngineFrame {
  /// Creates the frame.
  const new({this.leases = const []});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) =>
      HeartbeatAckFrame(leases: _objects(json, 'leases', LeaseGrant.fromJson));

  /// The wire name of this frame.
  static const frameType = 'heartbeat_ack';

  /// The renewed leases.
  final List<LeaseGrant> leases;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'leases': [for (final lease in leases) lease.toJson()],
  };

  @override
  List<Object?> get props => [leases];
}

/// The answer to a [LogChunkFrame].
final class ChunkAckFrame extends EngineFrame {
  /// Creates the frame.
  const new({
    required this.jobId,
    required this.leaseId,
    required this.seq,
    required this.next,
    required this.status,
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => ChunkAckFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    seq: _required<int>(json, 'seq'),
    next: _required<int>(json, 'next'),
    status: _enum(json, 'status', ChunkStatus.values, (s) => s.wire),
  );

  /// The wire name of this frame.
  static const frameType = 'chunk_ack';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The number of the chunk this answers.
  final int seq;

  /// The number of the chunk the engine wants next. Everything before it is
  /// stored.
  final int next;

  /// What the engine did with the chunk.
  final ChunkStatus status;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'seq': seq,
    'next': next,
    'status': status.wire,
  };

  @override
  List<Object?> get props => [jobId, leaseId, seq, next, status];
}

/// The answer to a [JobDoneFrame] the engine recorded.
final class DoneAckFrame extends EngineFrame {
  /// Creates the frame.
  const new({required this.jobId, required this.leaseId, required this.state});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => DoneAckFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    state: _enum(json, 'state', JobState.values, (s) => s.wire),
  );

  /// The wire name of this frame.
  static const frameType = 'done_ack';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The state the engine recorded. It can differ from the runner's: a
  /// `succeeded` job with steps that are not done is recorded as `failed`.
  final JobState state;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'state': state.wire,
  };

  @override
  List<Object?> get props => [jobId, leaseId, state];
}

/// The runner must stop the job: the lease is gone (it ran out, the job was
/// cancelled, the runner was revoked) or the engine does not know it.
final class CancelFrame extends EngineFrame {
  /// Creates the frame.
  const new({required this.jobId, required this.reason, this.leaseId});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => CancelFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _optional<String>(json, 'leaseId'),
    reason: _required<String>(json, 'reason'),
  );

  /// The wire name of this frame.
  static const frameType = 'cancel';

  /// The job.
  final String jobId;

  /// The lease that is gone, when the runner named one.
  final String? leaseId;

  /// Why.
  final String reason;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': ?leaseId,
    'reason': reason,
  };

  @override
  List<Object?> get props => [jobId, leaseId, reason];
}

/// A secret of the leased job (D-09, ADR 0012). It is sent once per lease; the
/// runner keeps it in a temporary keychain or folder and wipes it when the job
/// ends.
final class SecretValueFrame extends EngineFrame {
  /// Creates the frame.
  const new({
    required this.jobId,
    required this.leaseId,
    required this.key,
    required this.value,
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => SecretValueFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    key: _required<String>(json, 'key'),
    value: _required<String>(json, 'value'),
  );

  /// The wire name of this frame.
  static const frameType = 'secret_value';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The key.
  final String key;

  /// The value, base64 for binary secrets such as a keystore.
  final String value;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'key': key,
    'value': value,
  };

  @override
  List<Object?> get props => [jobId, leaseId, key, value];
}

/// The engine does not give the secret asked for.
final class SecretDeniedFrame extends EngineFrame {
  /// Creates the frame.
  const new({
    required this.jobId,
    required this.leaseId,
    required this.key,
    required this.reason,
  });

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => SecretDeniedFrame(
    jobId: _required<String>(json, 'jobId'),
    leaseId: _required<String>(json, 'leaseId'),
    key: _required<String>(json, 'key'),
    reason: _required<String>(json, 'reason'),
  );

  /// The wire name of this frame.
  static const frameType = 'secret_denied';

  /// The job.
  final String jobId;

  /// The lease.
  final String leaseId;

  /// The key.
  final String key;

  /// Why: the job does not hold the lease, the key is not a secret the job
  /// may have (signing material or the Shorebird key that its steps name), or
  /// it was given already.
  final String reason;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'jobId': jobId,
    'leaseId': leaseId,
    'key': key,
    'reason': reason,
  };

  @override
  List<Object?> get props => [jobId, leaseId, key, reason];
}

/// The engine could not use a frame of the runner.
final class FaultFrame extends EngineFrame {
  /// Creates the frame.
  const new({required this.code, required this.message});

  /// Reads the frame from its JSON form.
  factory fromJson(Map<String, dynamic> json) => FaultFrame(
    code: _required<String>(json, 'code'),
    message: _required<String>(json, 'message'),
  );

  /// The wire name of this frame.
  static const frameType = 'fault';

  /// `invalid_frame`, `unknown_frame`, `unexpected_frame` or
  /// `chunk_too_large`.
  final String code;

  /// What is wrong.
  final String message;

  @override
  String get type => frameType;

  @override
  Map<String, dynamic> toJson() => {
    'type': frameType,
    'code': code,
    'message': message,
  };

  @override
  List<Object?> get props => [code, message];
}

/// A frame of a type this runner does not know.
final class UnknownEngineFrame extends EngineFrame {
  /// Creates the frame.
  const new({required this.type, required this.payload});

  @override
  final String type;

  /// The whole object.
  final Map<String, dynamic> payload;

  @override
  Map<String, dynamic> toJson() => payload;

  @override
  List<Object?> get props => [type, payload];
}
