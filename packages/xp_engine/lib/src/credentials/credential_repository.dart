import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_record.dart';

/// Where credential references are kept (the `credential_ref` table).
///
/// A flavor has at most one credential of each kind. `xp_adapters` has the
/// SQLite implementation.
abstract interface class CredentialRepository {
  /// The flavor [flavorName] of the app at [appPath] in the project, or
  /// `null`.
  Future<CredentialFlavor?> findFlavor(
    String projectId,
    String appPath,
    String flavorName,
  );

  /// The credentials, oldest first: those of the flavor [flavorId], else those
  /// of the project [projectId], else all of them.
  Future<List<CredentialRecord>> list({String? projectId, String? flavorId});

  /// The credential [id], or `null`.
  Future<CredentialRecord?> get(String id);

  /// The credential of [kind] of the flavor [flavorId], or `null`.
  Future<CredentialRecord?> find(String flavorId, CredentialKind kind);

  /// Stores [record]: a new one, or the one with its id.
  Future<void> save(CredentialRecord record);

  /// Deletes the credential [id]. Returns whether there was one.
  Future<bool> delete(String id);

  /// How many credentials keep their secret under [secretKey].
  Future<int> countUsing(String secretKey);
}

/// A [CredentialRepository] that forgets everything on exit.
class InMemoryCredentialRepository implements CredentialRepository {
  /// Creates a repository that knows the flavors [flavors].
  new([Iterable<CredentialFlavor> flavors = const []]) : flavors = [...flavors];

  /// The flavors that exist.
  final List<CredentialFlavor> flavors;

  final _records = <String, CredentialRecord>{};

  @override
  Future<CredentialFlavor?> findFlavor(
    String projectId,
    String appPath,
    String flavorName,
  ) async => flavors
      .where(
        (flavor) =>
            flavor.projectId == projectId &&
            flavor.appPath == appPath &&
            flavor.name == flavorName,
      )
      .firstOrNull;

  @override
  Future<List<CredentialRecord>> list({
    String? projectId,
    String? flavorId,
  }) async => [
    for (final record in _records.values)
      if ((flavorId == null || record.flavor.id == flavorId) &&
          (projectId == null || record.flavor.projectId == projectId))
        record,
  ];

  @override
  Future<CredentialRecord?> get(String id) async => _records[id];

  @override
  Future<CredentialRecord?> find(String flavorId, CredentialKind kind) async =>
      _records.values
          .where(
            (record) => record.flavor.id == flavorId && record.kind == kind,
          )
          .firstOrNull;

  @override
  Future<void> save(CredentialRecord record) async {
    _records[record.id] = record;
  }

  @override
  Future<bool> delete(String id) async => _records.remove(id) != null;

  @override
  Future<int> countUsing(String secretKey) async =>
      _records.values.where((record) => record.secretKey == secretKey).length;
}
