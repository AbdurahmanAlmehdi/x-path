import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class JobLogEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Follows the log from the line after the last one held: from the start the
/// first time, from where it stopped after the job was resumed or the
/// connection failed.
final class JobLogFollowRequested extends JobLogEvent {
  const new();
}

class JobLogState extends Equatable {
  const new({
    this.lines = const [],
    this.following = false,
    this.ended,
    this.error,
  });

  /// Every line held, in order. Lines are only ever appended, so the bloc
  /// grows one list and states compare by its length ([count]).
  final List<LogLineFrame> lines;

  /// How many lines are held.
  int get count => lines.length;

  /// Whether lines are arriving now.
  final bool following;

  /// The state the job was in when the log ended, if it did. A job resumed
  /// after that writes on: follow again.
  final JobState? ended;

  /// What the engine said when the log could not be read.
  final String? error;

  /// The `seq` of the last line held: following again resumes after it.
  int get lastSeq => lines.isEmpty ? 0 : lines.last.seq;

  /// The lines each step wrote, by step ordinal.
  Map<int, List<LogLineFrame>> get byStep {
    final steps = <int, List<LogLineFrame>>{};
    for (final line in lines) {
      (steps[line.step] ??= []).add(line);
    }
    return steps;
  }

  @override
  List<Object?> get props => [count, following, ended, error];
}

/// The log of one job (`GET /jobs/{id}/logs`), resumed from the last line it
/// holds so a line is never shown twice.
class JobLogBloc extends Bloc<JobLogEvent, JobLogState> {
  new({required this._jobs, required this.jobId}) : super(const JobLogState()) {
    on<JobLogFollowRequested>(_onFollow, transformer: droppable());
  }

  final JobsRepository _jobs;
  final _lines = <LogLineFrame>[];

  /// The job whose log this is.
  final String jobId;

  Future<void> _onFollow(
    JobLogFollowRequested event,
    Emitter<JobLogState> emit,
  ) async {
    final lines = _lines;
    emit(JobLogState(lines: lines, following: true));
    await emit.forEach<LogFrame>(
      _jobs.followLogs(jobId, after: state.lastSeq),
      onData: (frame) => switch (frame) {
        LogLineFrame() => JobLogState(
          lines: lines..add(frame),
          following: true,
        ),
        LogEndFrame(:final state) => JobLogState(lines: lines, ended: state),
        // The client reconnects over a gap by itself.
        LogGapFrame() => state,
      },
      onError: (error, _) =>
          JobLogState(lines: lines, error: errorMessage(error)),
    );
    if (state.following) emit(JobLogState(lines: lines));
  }
}
