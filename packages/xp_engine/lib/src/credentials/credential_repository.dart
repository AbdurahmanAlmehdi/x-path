import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_record.dart';

/// Where named credentials (the `credential` table) and their assignments to
/// flavors (`credential_assignment`) are kept.
///
/// A name is unique regardless of case. A flavor has at most one credential
/// of each kind, and only of the credential's kind. `xp_adapters` has the
/// SQLite implementation.
abstract interface class CredentialRepository {
  /// The flavor [flavorName] of the app at [appPath] in the project, or
  /// `null`.
  Future<CredentialFlavor?> findFlavor(
    String projectId,
    String appPath,
    String flavorName,
  );

  /// The flavors of the app at [appPath] in the project, by name.
  Future<List<CredentialFlavor>> flavorsOf(String projectId, String appPath);

  /// The named credentials, by name.
  Future<List<CredentialRecord>> list();

  /// The credential [id], or `null`.
  Future<CredentialRecord?> get(String id);

  /// The credential called [name] regardless of case, or `null`.
  Future<CredentialRecord?> findByName(String name);

  /// Stores [record]: a new one, or the one with its id.
  Future<void> save(CredentialRecord record);

  /// Deletes the credential [id] and its assignments. Returns whether there
  /// was one.
  Future<bool> delete(String id);

  /// How many credentials keep their secret under [secretKey].
  Future<int> countUsing(String secretKey);

  /// The assignments, by project, app, flavor and kind: those of the flavor
  /// [flavorId], else those of the credential [credentialId], else those of
  /// the project [projectId], else all of them. Filters combine.
  Future<List<AssignedCredential>> assignments({
    String? projectId,
    String? flavorId,
    String? credentialId,
  });

  /// The credential the flavor [flavorId] uses for [kind], or `null`.
  Future<AssignedCredential?> assignment(String flavorId, CredentialKind kind);

  /// Stores [assignment]: the flavor uses its credential for the
  /// credential's kind from now on, with its check.
  Future<void> assign(AssignedCredential assignment);

  /// The flavor [flavorId] stops using a credential of [kind]. Returns
  /// whether it used one.
  Future<bool> unassign(String flavorId, CredentialKind kind);
}

/// A [CredentialRepository] that forgets everything on exit.
class InMemoryCredentialRepository implements CredentialRepository {
  /// Creates a repository that knows the flavors [flavors].
  new([Iterable<CredentialFlavor> flavors = const []]) : flavors = [...flavors];

  /// The flavors that exist.
  final List<CredentialFlavor> flavors;

  final _records = <String, CredentialRecord>{};
  final _assignments = <(String, CredentialKind), AssignedCredential>{};

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
  Future<List<CredentialFlavor>> flavorsOf(
    String projectId,
    String appPath,
  ) async => [
    for (final flavor in flavors)
      if (flavor.projectId == projectId && flavor.appPath == appPath) flavor,
  ]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<List<CredentialRecord>> list() async =>
      [..._records.values]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Future<CredentialRecord?> get(String id) async => _records[id];

  @override
  Future<CredentialRecord?> findByName(String name) async => _records.values
      .where((record) => record.name.toLowerCase() == name.toLowerCase())
      .firstOrNull;

  @override
  Future<void> save(CredentialRecord record) async {
    final clash = await findByName(record.name);
    if (clash != null && clash.id != record.id) {
      throw StateError('The name ${record.name} is taken.');
    }
    _records[record.id] = record;
  }

  @override
  Future<bool> delete(String id) async {
    _assignments.removeWhere((_, assignment) => assignment.id == id);
    return _records.remove(id) != null;
  }

  @override
  Future<int> countUsing(String secretKey) async =>
      _records.values.where((record) => record.secretKey == secretKey).length;

  @override
  Future<List<AssignedCredential>> assignments({
    String? projectId,
    String? flavorId,
    String? credentialId,
  }) async => [
    for (final assignment in _assignments.values)
      if ((projectId == null || assignment.flavor.projectId == projectId) &&
          (flavorId == null || assignment.flavor.id == flavorId) &&
          (credentialId == null || assignment.id == credentialId))
        assignment.withCredential(_records[assignment.id]!),
  ]..sort(_byPlace);

  @override
  Future<AssignedCredential?> assignment(
    String flavorId,
    CredentialKind kind,
  ) async => _assignments[(flavorId, kind)]?.withCredential(
    _records[_assignments[(flavorId, kind)]!.id]!,
  );

  @override
  Future<void> assign(AssignedCredential assignment) async {
    if (!_records.containsKey(assignment.id)) {
      throw StateError('There is no credential ${assignment.id}.');
    }
    _assignments[(assignment.flavor.id, assignment.kind)] = assignment;
  }

  @override
  Future<bool> unassign(String flavorId, CredentialKind kind) async =>
      _assignments.remove((flavorId, kind)) != null;

  /// Stores the credential of [assignment] and the assignment, at once. For
  /// tests that need a flavor with a credential.
  Future<void> put(AssignedCredential assignment) async {
    await save(assignment.credential);
    await assign(assignment);
  }

  static int _byPlace(AssignedCredential a, AssignedCredential b) {
    for (final (x, y) in [
      (a.flavor.projectId, b.flavor.projectId),
      (a.flavor.appPath, b.flavor.appPath),
      (a.flavor.name, b.flavor.name),
    ]) {
      final order = x.compareTo(y);
      if (order != 0) return order;
    }
    return a.kind.index.compareTo(b.kind.index);
  }
}
