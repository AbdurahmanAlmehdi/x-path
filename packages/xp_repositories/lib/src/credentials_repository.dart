import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// Whether [event] changes a credential or where one is used. Every one of
/// them may change what any project sees: a credential is engine-wide.
bool isCredentialEvent(EngineEvent event) =>
    event is CredentialSaved ||
    event is CredentialVerified ||
    event is CredentialExpired ||
    event is CredentialRemoved ||
    event is CredentialRenamed ||
    event is CredentialAssigned ||
    event is CredentialUnassigned;

/// A credential was not deleted because flavors use it. Deleting it with
/// `force` unassigns it from [usedBy] first.
class CredentialInUse implements Exception {
  /// Creates the exception with the engine's [message].
  const new(this.message, {this.usedBy = const []});

  /// What the engine said.
  final String message;

  /// The flavors that use the credential.
  final List<CredentialUsage> usedBy;

  @override
  String toString() => 'CredentialInUse: $message';
}

/// The named credentials of the engine of an [EngineSession]: any flavor of
/// any project may use one. No secret is ever part of what it returns.
class CredentialsRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// The named credentials, by name, with the flavors that use each, kept up
  /// to date by every credential event.
  Stream<Snapshot<List<NamedCredential>>> watchCredentials() => _session.watch(
    key: 'named-credentials',
    fetch: (client) => client.listNamedCredentials(),
    encode: (credentials) => [
      for (final credential in credentials) credential.toJson(),
    ],
    decode: (json) => [
      for (final credential in json! as List<dynamic>)
        NamedCredential.fromJson(credential as Map<String, dynamic>),
    ],
    refreshOn: isCredentialEvent,
  );

  /// Verifies [request] and stores it. Throws an `ApiException` with
  /// `credential_rejected` and nothing stored when the place it is for says
  /// no, or with `conflict` when the name is taken.
  Future<NamedCredential> createCredential(CreateCredentialRequest request) =>
      _session.call((client) => client.createCredential(request));

  /// Has the engine create an Apple Distribution certificate with the App
  /// Store Connect key of the flavor [flavor] of the app at [app] of
  /// [projectId], and assign the identity, called [name], to the flavor.
  /// Throws an `ApiException` with `conflict` and the team's certificates in
  /// its `details` when the team is at Apple's limit.
  Future<NamedCredential> createDistributionCertificate(
    String projectId, {
    required String app,
    required String flavor,
    required String name,
  }) => _session.call(
    (client) => client.createDistributionCertificate(
      projectId,
      app: app,
      flavor: flavor,
      name: name,
    ),
  );

  /// Gives [id] a new [name]. Its secret and assignments stay.
  Future<NamedCredential> renameCredential(String id, String name) =>
      _session.call((client) => client.renameCredential(id, name));

  /// Verifies the secret of [request] and gives it to [id]. Its name and
  /// assignments stay.
  Future<NamedCredential> replaceSecret(
    String id,
    ReplaceCredentialRequest request,
  ) => _session.call((client) => client.replaceCredentialSecret(id, request));

  /// Checks [id], and where it is used, again now.
  Future<NamedCredential> verifyCredential(String id) =>
      _session.call((client) => client.verifyNamedCredential(id));

  /// Deletes [id] and its secret. Throws a [CredentialInUse] with the flavors
  /// that use it, unless [force], which unassigns it from them first.
  Future<void> deleteCredential(String id, {bool force = false}) async {
    try {
      await _session.call(
        (client) => client.deleteNamedCredential(id, force: force),
      );
    } on ApiException catch (error) {
      if (!error.isCredentialInUse) rethrow;
      throw CredentialInUse(error.message, usedBy: error.usedBy);
    }
  }
}
