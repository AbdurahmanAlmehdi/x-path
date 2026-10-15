import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// The projects of the engine of an [EngineSession] and their credentials.
class ProjectsRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// The projects, oldest first, kept up to date by the project events.
  Stream<Snapshot<List<Project>>> watchProjects() => _session.watch(
    key: 'projects',
    fetch: (client) => client.listProjects(),
    encode: (projects) => [for (final project in projects) project.toJson()],
    decode: (json) => [
      for (final project in json! as List<dynamic>)
        Project.fromJson(project as Map<String, dynamic>),
    ],
    refreshOn: (event) =>
        event is ProjectAdded ||
        event is ProjectScanned ||
        event is ProjectRemoved,
  );

  /// One project.
  Future<Project> getProject(String id) =>
      _session.call((client) => client.getProject(id));

  /// Adds the repository at [path] on the engine machine and scans it.
  Future<Project> addProject(String path) => _session.call(
    (client) => client.addProject(AddProjectRequest(path: path)),
  );

  /// Scans [id] again.
  Future<Project> scanProject(String id) =>
      _session.call((client) => client.scanProject(id));

  /// Removes [id] from the engine. Nothing in the repository changes.
  Future<void> removeProject(String id) =>
      _session.call((client) => client.removeProject(id));

  /// The credentials of [projectId], kept up to date by the credential
  /// events. No secret is ever part of them.
  Stream<Snapshot<List<Credential>>> watchCredentials(String projectId) =>
      _session.watch(
        key: 'credentials.$projectId',
        fetch: (client) => client.listCredentials(projectId),
        encode: (credentials) => [
          for (final credential in credentials) credential.toJson(),
        ],
        decode: (json) => [
          for (final credential in json! as List<dynamic>)
            Credential.fromJson(credential as Map<String, dynamic>),
        ],
        refreshOn: (event) => switch (event) {
          CredentialSaved(projectId: final id) ||
          CredentialVerified(projectId: final id) ||
          CredentialExpired(projectId: final id) ||
          CredentialRemoved(projectId: final id) => id == projectId,
          _ => false,
        },
      );

  /// Verifies [request] and stores it. Throws an `ApiException` with
  /// `credential_rejected` and nothing stored when the place it is for says
  /// no.
  Future<Credential> saveCredential(
    String projectId,
    SaveCredentialRequest request,
  ) => _session.call((client) => client.saveCredential(projectId, request));

  /// Checks [credentialId] again now.
  Future<Credential> verifyCredential(String projectId, String credentialId) =>
      _session.call(
        (client) => client.verifyCredential(projectId, credentialId),
      );

  /// Deletes [credentialId] and its secret.
  Future<void> deleteCredential(String projectId, String credentialId) =>
      _session.call(
        (client) => client.deleteCredential(projectId, credentialId),
      );
}
