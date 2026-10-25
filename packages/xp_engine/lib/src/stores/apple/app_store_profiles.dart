import 'package:collection/collection.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/stores/apple/app_store_connect.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';
import 'package:xp_engine/src/stores/apple/distribution_certificate.dart';

/// Why the engine could not give a Linux runner the App Store profile of a
/// job. The message names what to fix and never contains a secret.
class AppStoreProfileException implements Exception {
  /// Creates the exception.
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'AppStoreProfileException: $message';
}

/// The App Store profiles the engine makes for Linux iOS builds, with its
/// own App Store Connect client (ADR 0014, decision (b)): a runner gets the
/// Apple Distribution identity and the profile, never the API key, and never
/// creates a certificate.
///
/// A profile is asked for like a secret, by a key that names the identity
/// and the bundle id ([keyFor]). The engine makes it with the API key of the
/// flavor that uses the identity for that bundle id, or reuses the active
/// one it made before that does not expire within a day.
class AppStoreProfiles {
  /// Creates the profiles over the credentials of the projects.
  const new({
    required this._credentials,
    required this._secrets,
    required this._connect,
    required this._clock,
  });

  static const _marker = '.profile:';

  final CredentialRepository _credentials;
  final SecretStore _secrets;
  final AppStoreConnectFactory _connect;
  final Clock _clock;

  /// The key of the App Store profile for [bundleId] signed by the identity
  /// whose secret key is [identityKey].
  static String keyFor(String identityKey, String bundleId) =>
      '$identityKey$_marker$bundleId';

  /// Whether [key] names a profile rather than a stored secret.
  static bool isProfileKey(String key) => key.contains(_marker);

  /// The `.mobileprovision` that [key] names, for a job of [projectId].
  ///
  /// Throws an [AppStoreProfileException] if the project has no flavor that
  /// uses the identity for the bundle id with an API key, if App Store
  /// Connect does not list the certificate or the bundle id, or if it
  /// refuses.
  Future<List<int>> profile(String projectId, String key) async {
    final at = key.lastIndexOf(_marker);
    final identityKey = key.substring(0, at);
    final bundleId = key.substring(at + _marker.length);
    final assignments = await _credentials.assignments(projectId: projectId);
    final identity = assignments.firstWhereOrNull(
      (each) =>
          each.kind == CredentialKind.appleDistribution &&
          each.credential.secretKey == identityKey &&
          each.flavor.iosBundleId == bundleId,
    );
    if (identity == null) {
      throw AppStoreProfileException(
        'No flavor of the project signs $bundleId with this identity.',
      );
    }
    final asc = assignments.firstWhereOrNull(
      (each) =>
          each.kind == CredentialKind.ascKey &&
          each.flavor.id == identity.flavor.id,
    );
    final material = asc == null
        ? null
        : await CredentialMaterial.load(
            CredentialKind.ascKey,
            asc.credential.secretKey,
            asc.credential.account,
            _secrets,
          );
    final der = await _secrets.readBytes(
      AppleDistributionMaterial.certificateKey(identityKey),
    );
    if (material is! AscKeyMaterial || der == null) {
      throw AppStoreProfileException(
        'The flavor ${identity.flavor.name} needs an App Store Connect API '
        'key and a saved identity for the engine to make its profile.',
      );
    }
    final certificate = DistributionCertificate.fromDer(der);
    final connect = _connect(material.key);
    try {
      final listed = (await connect.distributionCertificates())
          .firstWhereOrNull((each) => certificate.hasSerial(each.serialNumber));
      if (listed == null) {
        throw AppStoreProfileException(
          'App Store Connect lists no distribution certificate with the '
          'serial number ${certificate.serialNumber}: it was revoked.',
        );
      }
      final name = 'XPath $bundleId ${certificate.serialNumber}';
      final soon = _clock.now().add(const Duration(days: 1));
      final reusable = (await connect.appStoreProfiles(name)).firstWhereOrNull(
        (each) => each.expirationDate?.isAfter(soon) ?? false,
      );
      if (reusable != null) return reusable.content;
      final resource = await connect.bundleIdOf(bundleId);
      if (resource == null) {
        throw AppStoreProfileException(
          'App Store Connect has no bundle id $bundleId registered.',
        );
      }
      final created = await connect.createAppStoreProfile(
        name: name,
        bundleId: resource,
        certificateId: listed.id,
      );
      return created.content;
    } on AppStoreConnectException catch (error) {
      throw AppStoreProfileException(
        'App Store Connect could not make the profile of $bundleId: '
        '${error.message}',
      );
    }
  }
}
