import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// What the engine of an [EngineSession] keeps on its disk, and housekeeping
/// (D-22, D-24).
class StorageRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// What the engine keeps and what "free up space" would give back. No
  /// event says it changed (the engine measures folders to answer), so it is
  /// read again only when the engine answers again after an outage; listen
  /// again to read it now.
  Stream<Snapshot<StorageReport>> watchStorage() => _session.watch(
    key: 'storage',
    fetch: (client) => client.getStorage(),
    encode: (report) => report.toJson(),
    decode: (json) => StorageReport.fromJson(json! as Map<String, dynamic>),
    refreshOn: (_) => false,
  );

  /// Deletes what retention gives back in [categories]: the owner's "free up
  /// space" (only the app and `xp` may).
  Future<FreeSpaceResult> freeSpace(List<StorageCategory> categories) =>
      _session.call(
        (client) => client.freeStorage(
          FreeSpaceRequest(dryRun: false, categories: categories),
        ),
      );

  /// Replaces the retention settings.
  Future<RetentionSettings> setRetention(RetentionSettings settings) =>
      _session.call((client) => client.setRetention(settings));
}
