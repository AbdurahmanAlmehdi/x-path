import 'package:xp_engine/src/projects/project_record.dart';

/// Where projects are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class ProjectRepository {
  /// Every project, oldest first.
  Future<List<ProjectRecord>> list();

  /// The project with [id], or `null`.
  Future<ProjectRecord?> get(String id);

  /// The project whose source key is [sourceKey], or `null`.
  Future<ProjectRecord?> findBySourceKey(String sourceKey);

  /// Stores a new project.
  Future<void> add(ProjectRecord record);

  /// Replaces the stored project that has the id of [record].
  Future<void> update(ProjectRecord record);

  /// Deletes the project [id] with everything that belongs to it. Returns
  /// whether there was such a project.
  ///
  /// Throws a `ProjectInUseException` if releases or jobs refer to it.
  Future<bool> remove(String id);
}

/// A [ProjectRepository] that forgets everything on exit.
class InMemoryProjectRepository implements ProjectRepository {
  final _records = <String, ProjectRecord>{};

  @override
  Future<List<ProjectRecord>> list() async => _records.values.toList();

  @override
  Future<ProjectRecord?> get(String id) async => _records[id];

  @override
  Future<ProjectRecord?> findBySourceKey(String sourceKey) async => _records
      .values
      .where((record) => record.sourceKey == sourceKey)
      .firstOrNull;

  @override
  Future<void> add(ProjectRecord record) async {
    if (await findBySourceKey(record.sourceKey) != null) {
      throw StateError('Repository ${record.sourceKey} is a project.');
    }
    _records[record.id] = record;
  }

  @override
  Future<void> update(ProjectRecord record) async {
    if (!_records.containsKey(record.id)) {
      throw StateError('There is no project ${record.id}.');
    }
    _records[record.id] = record;
  }

  @override
  Future<bool> remove(String id) async => _records.remove(id) != null;
}
