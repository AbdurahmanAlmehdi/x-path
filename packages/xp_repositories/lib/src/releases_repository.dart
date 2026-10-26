import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// The releases of the engine of an [EngineSession].
class ReleasesRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  bool _isReleaseEvent(EngineEvent event, String? projectId) => switch (event) {
    ReleaseCreated(projectId: final project) ||
    ReleaseStateChanged(projectId: final project) ||
    ReleaseStoreChanged(
      projectId: final project,
    ) => projectId == null || project == projectId,
    _ => false,
  };

  /// The releases, newest first, of [projectId] if given, kept up to date by
  /// the release events.
  Stream<Snapshot<List<Release>>> watchReleases({String? projectId}) =>
      _session.watch(
        key: projectId == null ? 'releases' : 'releases.$projectId',
        fetch: (client) => client.listReleases(projectId: projectId),
        encode: (releases) => [
          for (final release in releases) release.toJson(),
        ],
        decode: (json) => [
          for (final release in json! as List<dynamic>)
            Release.fromJson(release as Map<String, dynamic>),
        ],
        refreshOn: (event) => _isReleaseEvent(event, projectId),
      );

  /// One release, kept up to date by its events.
  Stream<Snapshot<Release>> watchRelease(String id) => _session.watch(
    key: 'release.$id',
    fetch: (client) => client.getRelease(id),
    encode: (release) => release.toJson(),
    decode: (json) => Release.fromJson(json! as Map<String, dynamic>),
    refreshOn: (event) => switch (event) {
      ReleaseStateChanged(:final releaseId) ||
      ReleaseStoreChanged(:final releaseId) => releaseId == id,
      _ => false,
    },
  );

  /// Asks the stores about [id] now.
  Future<Release> refresh(String id) =>
      _session.call((client) => client.refreshRelease(id));

  /// Says by hand that [store] is in [state] for [id].
  Future<Release> setStoreStatus(
    String id,
    ReleaseStore store,
    StoreState state,
  ) =>
      _session.call((client) => client.setReleaseStoreStatus(id, store, state));

  /// Builds the version of [id] again with a new build number.
  Future<Run> startBuild(String id) =>
      _session.call((client) => client.startReleaseBuild(id));

  /// Asks to merge the pull request of [id].
  Future<Run> merge(String id) =>
      _session.call((client) => client.mergeRelease(id));

  /// Asks to change the rollout of [id] in a store.
  Future<Run> rollout(String id, RolloutRequest request) =>
      _session.call((client) => client.requestRollout(id, request));

  /// What happened to [id], oldest first.
  Future<ReleaseHistory> history(String id) =>
      _session.call((client) => client.getReleaseHistory(id));

  /// Sets the texts the uploads of [id] send.
  Future<Release> setTexts(String id, ReleaseTexts texts) =>
      _session.call((client) => client.setReleaseTexts(id, texts));

  /// Asks to [action] the Shorebird patch [number] of [id].
  Future<Run> movePatch(String id, int number, PatchAction action) =>
      _session.call((client) => client.moveReleasePatch(id, number, action));

  /// Abandons [id].
  Future<Release> abandon(String id, {String? reason}) =>
      _session.call((client) => client.abandonRelease(id, reason: reason));

  /// The release notes of [id].
  Future<ReleaseNotes> notes(String id) =>
      _session.call((client) => client.getReleaseNotes(id));
}
