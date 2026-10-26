import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// What a notice is about; each can be turned off in Settings (U6b).
enum NoticeKind {
  jobFailed,
  jobSucceeded,
  releaseRejected,
  releaseApproved,
  releaseLive,
  credentialExpired,
  secretsLocked,

  /// A runner lost a job it held (its lease ran out).
  runnerLost,

  /// A runner can no longer do something it could, for example after a
  /// self-update.
  capabilityLost,

  /// A job has waited [EngineNoticesBloc.waitLimit] for a runner.
  jobWaiting;

  /// The kind of an engine notification, if the app shows it as a notice.
  /// Approvals have notifications of their own.
  static NoticeKind? of(NotificationKind kind) => switch (kind) {
    NotificationKind.jobFailed => jobFailed,
    NotificationKind.jobSucceeded => jobSucceeded,
    NotificationKind.releaseRejected => releaseRejected,
    NotificationKind.releaseApproved => releaseApproved,
    NotificationKind.releaseLive => releaseLive,
    NotificationKind.credentialExpired => credentialExpired,
    NotificationKind.secretsLocked => secretsLocked,
    _ => null,
  };
}

/// Something to tell the owner, with what clicking it opens ([target]):
/// `job:<jobId>`, `run:<runId>:<projectId>[:<jobId>]`,
/// `release:<projectId>:<releaseId>`, `credentials:<projectId>`, `runners`
/// or `settings`.
sealed class Notice extends Equatable {
  const new();

  NoticeKind get kind;
  String get target;
}

/// A notification the engine raised (D-22): its own title and body.
final class EngineRaisedNotice extends Notice {
  const new(this.kind, this.event);

  @override
  final NoticeKind kind;
  final NotificationRaised event;

  @override
  String get target => switch (event) {
    NotificationRaised(:final jobId?) => 'job:$jobId',
    NotificationRaised(:final projectId?, :final releaseId?) =>
      'release:$projectId:$releaseId',
    NotificationRaised(:final projectId?)
        when kind == NoticeKind.credentialExpired =>
      'credentials:$projectId',
    _ => 'settings',
  };

  @override
  List<Object?> get props => [kind, event];
}

/// A runner lost the lease of a job.
final class RunnerLostNotice extends Notice {
  const new(this.event);

  final RunnerLeaseLost event;

  @override
  NoticeKind get kind => NoticeKind.runnerLost;

  @override
  String get target => 'job:${event.jobId}';

  @override
  List<Object?> get props => [event];
}

/// A runner can no longer do [lost].
final class CapabilityLostNotice extends Notice {
  const new({required this.runner, required this.lost});

  final String runner;
  final List<String> lost;

  @override
  NoticeKind get kind => NoticeKind.capabilityLost;

  @override
  String get target => 'runners';

  @override
  List<Object?> get props => [runner, lost];
}

/// The job [jobName] of [run] has waited for a runner since long, for
/// [reason].
final class JobWaitingNotice extends Notice {
  const new({
    required this.run,
    required this.jobId,
    required this.jobName,
    required this.reason,
  });

  final Run run;
  final String jobId;
  final String jobName;
  final String reason;

  @override
  NoticeKind get kind => NoticeKind.jobWaiting;

  @override
  String get target => 'run:${run.id}:${run.projectId}:$jobId';

  @override
  List<Object?> get props => [run, jobId, jobName, reason];
}

sealed class EngineNoticesEvent {
  const new();
}

/// Starts following the engine's notices and its active runs.
final class EngineNoticesStarted extends EngineNoticesEvent {
  const new();
}

final class _Noticed extends EngineNoticesEvent {
  const new(this.event);

  final EngineEvent event;
}

final class _RunsChanged extends EngineNoticesEvent {
  const new(this.runs);

  final List<Run> runs;
}

final class _Ticked extends EngineNoticesEvent {
  const new();
}

class EngineNoticesState extends Equatable {
  const new({this.running = const [], this.notice, this.count = 0});

  /// The runs of every project that have not finished, newest first.
  final List<Run> running;

  /// The newest notice, if any.
  final Notice? notice;

  /// How many notices there were: it grows with each, so the same notice
  /// twice is told twice.
  final int count;

  EngineNoticesState _told(Notice notice) =>
      EngineNoticesState(running: running, notice: notice, count: count + 1);

  @override
  List<Object?> get props => [running, notice, count];
}

/// What the owner should hear about when not looking at the window (U6b):
/// the engine's notifications, runners that lose jobs or capabilities, and
/// jobs that wait [waitLimit] for a runner; and the runs that work now, for
/// the menu bar extra.
class EngineNoticesBloc extends Bloc<EngineNoticesEvent, EngineNoticesState> {
  new({
    required this._notices,
    required this._jobs,
    DateTime Function()? now,
    Stream<void>? ticks,
  }) : _now = now ?? DateTime.now,
       _ticks = ticks ?? Stream<void>.periodic(const Duration(minutes: 1)),
       super(const EngineNoticesState()) {
    on<EngineNoticesStarted>(_onStarted, transformer: restartable());
    on<_Noticed>(_onNoticed);
    on<_RunsChanged>(_onRuns);
    on<_Ticked>((_, emit) => _checkWaits(emit));
  }

  /// How long a job waits for a runner before the owner hears about it.
  static const waitLimit = Duration(minutes: 10);

  final NoticesRepository _notices;
  final JobsRepository _jobs;
  final DateTime Function() _now;
  final Stream<void> _ticks;

  /// When each job that waits for a runner was first seen waiting.
  final _waitingSince = <String, DateTime>{};

  /// The waiting jobs already told about.
  final _toldJobs = <String>{};

  Future<void> _onStarted(
    EngineNoticesStarted event,
    Emitter<EngineNoticesState> emit,
  ) => Future.wait([
    emit.onEach<EngineEvent>(
      _notices.watchNotices(),
      onData: (event) => add(_Noticed(event)),
    ),
    emit.onEach<Snapshot<List<Run>>>(
      _jobs.watchActiveRuns(),
      onData: (snapshot) => add(_RunsChanged(snapshot.value)),
      onError: (_, _) {},
    ),
    emit.onEach<void>(_ticks, onData: (_) => add(const _Ticked())),
  ]);

  void _onNoticed(_Noticed event, Emitter<EngineNoticesState> emit) {
    final notice = switch (event.event) {
      NotificationRaised(:final kind) && final raised => switch (NoticeKind.of(
        kind,
      )) {
        final kind? => EngineRaisedNotice(kind, raised),
        null => null,
      },
      RunnerLeaseLost(reason: 'lapsed') && final lost => RunnerLostNotice(lost),
      RunnerCapabilitiesChanged(:final name, :final from, :final to) =>
        switch ([
          for (final capability in from)
            if (!to.contains(capability)) capability,
        ]) {
          final lost when lost.isNotEmpty => CapabilityLostNotice(
            runner: name,
            lost: lost,
          ),
          _ => null,
        },
      _ => null,
    };
    if (notice != null) emit(state._told(notice));
  }

  void _onRuns(_RunsChanged event, Emitter<EngineNoticesState> emit) {
    final now = _now();
    final waiting = <String>{};
    for (final run in event.runs) {
      for (final job in run.jobs) {
        if (job.state == JobState.queued && job.message != null) {
          waiting.add(job.id);
          _waitingSince.putIfAbsent(job.id, () => now);
        }
      }
    }
    _waitingSince.removeWhere((id, _) => !waiting.contains(id));
    _toldJobs.retainAll(waiting);
    emit(
      EngineNoticesState(
        running: event.runs,
        notice: state.notice,
        count: state.count,
      ),
    );
    _checkWaits(emit);
  }

  void _checkWaits(Emitter<EngineNoticesState> emit) {
    final now = _now();
    for (final run in state.running) {
      for (final job in run.jobs) {
        final since = _waitingSince[job.id];
        if (since == null ||
            _toldJobs.contains(job.id) ||
            now.difference(since) < waitLimit) {
          continue;
        }
        _toldJobs.add(job.id);
        emit(
          state._told(
            JobWaitingNotice(
              run: run,
              jobId: job.id,
              jobName: job.name,
              reason: job.message!,
            ),
          ),
        );
      }
    }
  }
}
