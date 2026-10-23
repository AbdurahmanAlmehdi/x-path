import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/src/credentials_repository.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// The folder's origin is an HTTPS URL on a host other than GitHub, which
/// the engine has no credentials for. It offers the SSH URL of the same
/// repository, [sshUrl], for the owner to confirm (ADR 0015).
class SshUrlRequired implements Exception {
  /// Creates the exception with the engine's [message].
  const new(this.message, {required this.sshUrl});

  /// What the engine said.
  final String message;

  /// The SSH URL the engine offers.
  final String sshUrl;

  @override
  String toString() => 'SshUrlRequired: $message';
}

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
  ///
  /// [sshUrl] is the SSH URL the owner confirmed for a folder whose origin
  /// is an HTTPS URL on a host other than GitHub. Without it such a folder
  /// throws a [SshUrlRequired] that offers the URL (ADR 0015).
  Future<Project> addProject(String path, {String? sshUrl}) async {
    try {
      return await _session.call(
        (client) =>
            client.addProject(AddProjectRequest(path: path, sshUrl: sshUrl)),
      );
    } on ApiException catch (error) {
      final offered = error.sshUrl;
      if (offered == null) rethrow;
      throw SshUrlRequired(error.message, sshUrl: offered);
    }
  }

  /// Scans [id] again.
  Future<Project> scanProject(String id) =>
      _session.call((client) => client.scanProject(id));

  /// Removes [id] from the engine. Nothing in the repository changes.
  Future<void> removeProject(String id) =>
      _session.call((client) => client.removeProject(id));

  /// The credential each flavor of [projectId] uses, one per flavor and
  /// kind that has one, kept up to date by every credential event (a
  /// credential is engine-wide: renaming, checking or deleting it changes
  /// what every project that uses it sees). No secret is ever part of them.
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
        refreshOn: isCredentialEvent,
      );

  /// The flavor [flavor] of the app at [app] of [projectId] uses the named
  /// credential [credentialId] for [kind]. With [allFlavors] every flavor of
  /// the app does too, but those that have another credential of [kind]
  /// keep it (they are in [AssignCredentialResponse.kept]) unless [replace].
  Future<AssignCredentialResponse> assignCredential(
    String projectId, {
    required String app,
    required String flavor,
    required CredentialKind kind,
    required String credentialId,
    bool allFlavors = false,
    bool replace = false,
  }) => _session.call(
    (client) => client.assignCredential(
      projectId,
      app: app,
      flavor: flavor,
      kind: kind,
      request: AssignCredentialRequest(
        credentialId: credentialId,
        allFlavors: allFlavors,
        replace: replace,
      ),
    ),
  );

  /// The flavor [flavor] of the app at [app] of [projectId] stops using its
  /// credential of [kind]. The credential stays.
  Future<void> unassignCredential(
    String projectId, {
    required String app,
    required String flavor,
    required CredentialKind kind,
  }) => _session.call(
    (client) => client.unassignCredential(
      projectId,
      app: app,
      flavor: flavor,
      kind: kind,
    ),
  );
}
