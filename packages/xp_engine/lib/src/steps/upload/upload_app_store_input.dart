import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// How the upload to App Store Connect signs in (D-14).
sealed class AppStoreUploadAuth extends Equatable {
  const new();

  /// Reads the stored form.
  ///
  /// Throws a [FormatException] if [json] is not a valid auth.
  factory fromJson(Map<String, dynamic> json) {
    final type = requiredString(json, 'type');
    return switch (type) {
      'apiKey' => ApiKeyUploadAuth(requiredString(json, 'keySecret')),
      'appleId' => AppleIdUploadAuth(
        appleId: requiredString(json, 'appleId'),
        passwordSecret: requiredString(json, 'passwordSecret'),
      ),
      _ => throw FormatException(
        '"auth.type" must be "apiKey" or "appleId", not $type.',
      ),
    };
  }

  /// The stored form.
  Map<String, dynamic> toJson();
}

/// Upload with an App Store Connect API key. The REST API can then confirm
/// the build and read the review state.
class ApiKeyUploadAuth extends AppStoreUploadAuth {
  /// Creates the auth. [keySecret] is the key in the secret store of the ASC
  /// key (`AscKey.toSecret`).
  const new(this.keySecret);

  /// The key in the secret store of the ASC key.
  final String keySecret;

  @override
  Map<String, dynamic> toJson() => {'type': 'apiKey', 'keySecret': keySecret};

  @override
  List<Object?> get props => [keySecret];
}

/// Upload with an Apple ID and an app-specific password. The password goes to
/// altool as `-p @env:XPATH_ASC_APP_PASSWORD`, never as an argument.
class AppleIdUploadAuth extends AppStoreUploadAuth {
  /// Creates the auth. [passwordSecret] is the key in the secret store of the
  /// app-specific password.
  const new({required this.appleId, required this.passwordSecret});

  /// The Apple ID (an email address).
  final String appleId;

  /// The key in the secret store of the app-specific password.
  final String passwordSecret;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'appleId',
    'appleId': appleId,
    'passwordSecret': passwordSecret,
  };

  @override
  List<Object?> get props => [appleId, passwordSecret];
}

/// What to upload to App Store Connect.
class UploadAppStoreInput extends Equatable {
  /// Creates the input. [version] must have a build number (`fromJson`
  /// checks it).
  const new({
    required this.artifactName,
    required this.bundleId,
    required this.appleAppId,
    required this.version,
    required this.auth,
    this.artifactJob,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or the version has no build number.
  factory fromJson(Map<String, dynamic> json) {
    final version = AppVersion.parse(requiredString(json, 'version'));
    if (version.build == null) {
      throw const FormatException('"version" needs a build number: x.y.z+n.');
    }
    final artifactName = requiredString(json, 'artifactName');
    if (artifactName.contains('/') || artifactName.contains(r'\')) {
      throw const FormatException('"artifactName" must be a plain file name.');
    }
    return UploadAppStoreInput(
      artifactName: artifactName,
      bundleId: requiredString(json, 'bundleId'),
      appleAppId: requiredString(json, 'appleAppId'),
      version: version,
      auth: AppStoreUploadAuth.fromJson(requiredObject(json, 'auth')),
      artifactJob: optionalString(json, 'artifactJob'),
    );
  }

  /// The file name of the IPA in the artifact store, such as
  /// `prod-1.2.3+45.ipa`. It is looked up among the artifacts of the job.
  final String artifactName;

  /// The job whose artifacts hold the file, when it is not this job: a build
  /// job of an earlier stage that the runner uploaded the file from (ADR
  /// 0010). `null` looks among the artifacts of the job the step runs in.
  final String? artifactJob;

  /// The bundle id of the app.
  final String bundleId;

  /// The numeric Apple id of the app in App Store Connect (`--apple-id`), also
  /// the id of the app in the REST API.
  final String appleAppId;

  /// The version and build number the IPA carries.
  final AppVersion version;

  /// How to sign in.
  final AppStoreUploadAuth auth;

  /// Who has the file, for a message: this job, or the build job.
  String get sourceOfArtifact =>
      artifactJob == null ? 'This job' : 'The build job $artifactJob';

  /// The build number as text.
  String get build => '${version.build ?? 0}';

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'artifactName': artifactName,
    'bundleId': bundleId,
    'appleAppId': appleAppId,
    'version': '$version',
    'auth': auth.toJson(),
    'artifactJob': ?artifactJob,
  };

  @override
  List<Object?> get props => [
    artifactName,
    bundleId,
    appleAppId,
    version,
    auth,
    artifactJob,
  ];
}

/// What `upload.appStore` did.
class UploadAppStoreResult extends Equatable {
  /// Creates the result.
  const new({
    this.alreadyUploaded = false,
    this.confirmed = false,
    this.deliveryId,
    this.buildId,
    this.processingState,
  });

  /// Whether App Store Connect had the build before this run, so nothing was
  /// uploaded.
  final bool alreadyUploaded;

  /// Whether App Store Connect accepted the upload, or altool said it went
  /// through (a success line in its output).
  final bool confirmed;

  /// altool's delivery UUID, for `altool --build-status`.
  final String? deliveryId;

  /// The id of the build in the REST API, when an API key found or uploaded
  /// it.
  final String? buildId;

  /// The processing state (`PROCESSING`, `VALID`, ...) when an API key found
  /// the build.
  final String? processingState;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'alreadyUploaded': alreadyUploaded,
    'confirmed': confirmed,
    'deliveryId': ?deliveryId,
    'buildId': ?buildId,
    'processingState': ?processingState,
  };

  @override
  List<Object?> get props => [
    alreadyUploaded,
    confirmed,
    deliveryId,
    buildId,
    processingState,
  ];
}
