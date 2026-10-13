import 'package:xp_engine/src/projects/project_exceptions.dart';
import 'package:xp_engine/src/versioning/release_model.dart';

/// Where the release model of each project is kept (`project.release_model`).
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class ReleaseModelRepository {
  /// The release model of [projectId]; the default model if the owner set
  /// none.
  ///
  /// Throws a `ProjectNotFoundException` if there is no such project.
  Future<ReleaseModel> get(String projectId);

  /// Stores [model] as the release model of [projectId].
  ///
  /// Throws a `ProjectNotFoundException` if there is no such project.
  Future<void> save(String projectId, ReleaseModel model);
}

/// A [ReleaseModelRepository] that forgets everything on exit.
class InMemoryReleaseModelRepository implements ReleaseModelRepository {
  /// Creates a repository for the projects [projectIds].
  new(Iterable<String> projectIds)
    : _models = {for (final id in projectIds) id: const ReleaseModel()};

  final Map<String, ReleaseModel> _models;

  @override
  Future<ReleaseModel> get(String projectId) async =>
      _models[projectId] ?? (throw ProjectNotFoundException(projectId));

  @override
  Future<void> save(String projectId, ReleaseModel model) async {
    if (!_models.containsKey(projectId)) {
      throw ProjectNotFoundException(projectId);
    }
    _models[projectId] = model;
  }
}
