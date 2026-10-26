import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class HomeEvent extends Equatable {
  const new();
}

/// Starts following the releases and the runs of every project.
final class HomeSubscriptionRequested extends HomeEvent {
  const new();

  @override
  List<Object?> get props => [];
}

/// What a release in review is in: on its way to the stores or waiting for
/// their verdict.
const Set<ReleaseState> inReviewStates = {
  ReleaseState.uploaded,
  ReleaseState.inReview,
  ReleaseState.rejected,
  ReleaseState.approved,
};

class HomeState extends Equatable {
  const new({
    this.loaded = false,
    this.releases = const [],
    this.running = const [],
    this.error,
  });

  /// Whether the releases arrived.
  final bool loaded;

  /// The releases of every project, newest first.
  final List<Release> releases;

  /// The runs of every project that have not finished.
  final List<Run> running;

  /// What the engine said when it could not be read.
  final String? error;

  /// The newest release of [projectId] that is live (or merged since).
  Release? liveOf(String projectId) => _newest(
    projectId,
    (release) =>
        release.state == ReleaseState.live ||
        release.state == ReleaseState.merged,
  );

  /// The newest release of [projectId] in review.
  Release? inReviewOf(String projectId) =>
      _newest(projectId, (release) => inReviewStates.contains(release.state));

  /// How many runs of [projectId] work now.
  int runningOf(String projectId) =>
      running.where((run) => run.projectId == projectId).length;

  Release? _newest(String projectId, bool Function(Release) test) => releases
      .where((release) => release.projectId == projectId && test(release))
      .firstOrNull;

  HomeState copyWith({
    bool? loaded,
    List<Release>? releases,
    List<Run>? running,
    String? Function()? error,
  }) => HomeState(
    loaded: loaded ?? this.loaded,
    releases: releases ?? this.releases,
    running: running ?? this.running,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [loaded, releases, running, error];
}

/// Home (U6d): what is live, in review and running in every project, so an
/// owner sees them all without clicking.
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  new({required this._releases, required this._jobs})
    : super(const HomeState()) {
    on<HomeSubscriptionRequested>(_onSubscribe, transformer: restartable());
  }

  final ReleasesRepository _releases;
  final JobsRepository _jobs;

  Future<void> _onSubscribe(
    HomeSubscriptionRequested event,
    Emitter<HomeState> emit,
  ) => Future.wait([
    emit.forEach<Snapshot<List<Release>>>(
      _releases.watchReleases(),
      onData: (snapshot) => state.copyWith(
        loaded: true,
        releases: snapshot.value,
        error: () => null,
      ),
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    ),
    emit.forEach<Snapshot<List<Run>>>(
      _jobs.watchActiveRuns(),
      onData: (snapshot) => state.copyWith(running: snapshot.value),
      onError: (_, _) => state,
    ),
  ]);
}
