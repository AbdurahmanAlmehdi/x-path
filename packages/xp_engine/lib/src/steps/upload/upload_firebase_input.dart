import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/stores/firebase/firebase_models.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

// `1:684690133351:android:b434734f585770367c1fc2`: the second number is the
// project number the REST API names the app by.
final _appId = RegExp(r'^\d+:(\d+):(?:android|ios|web):[0-9A-Za-z]+$');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _group = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');

/// What to upload to Firebase App Distribution.
class UploadFirebaseInput extends Equatable {
  /// Creates the input. [version] must have a build number (`fromJson` checks
  /// it and the rest).
  const new({
    required this.artifactName,
    required this.appId,
    required this.version,
    required this.serviceAccountSecret,
    this.testerEmails = const [],
    this.groupAliases = const [],
    this.releaseNotes,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// the artifact is not an APK, AAB or IPA, the app id is not a Firebase app
  /// id, the version has no build number, or a tester or group is malformed.
  factory fromJson(Map<String, dynamic> json) {
    final version = AppVersion.parse(requiredString(json, 'version'));
    if (version.build == null) {
      throw const FormatException('"version" needs a build number: x.y.z+n.');
    }
    final artifactName = requiredString(json, 'artifactName');
    if (artifactName.contains('/') || artifactName.contains(r'\')) {
      throw const FormatException('"artifactName" must be a plain file name.');
    }
    if (kindOf(artifactName) == null) {
      throw const FormatException(
        '"artifactName" must be an .apk, .aab or .ipa file.',
      );
    }
    final appId = requiredString(json, 'appId');
    if (!_appId.hasMatch(appId)) {
      throw const FormatException(
        '"appId" must be a Firebase app id like '
        '1:123456789012:android:0123abcd.',
      );
    }
    final emails = stringList(json, 'testerEmails');
    if (emails.any((email) => !_email.hasMatch(email))) {
      throw const FormatException(
        '"testerEmails" must be a list of email addresses.',
      );
    }
    final groups = stringList(json, 'groupAliases');
    if (groups.any((group) => !_group.hasMatch(group))) {
      throw const FormatException(
        '"groupAliases" must be a list of group aliases like testers.',
      );
    }
    if (emails.length + groups.length > 999) {
      throw const FormatException(
        'Firebase takes at most 999 testers and groups in one distribution.',
      );
    }
    return UploadFirebaseInput(
      artifactName: artifactName,
      appId: appId,
      version: version,
      serviceAccountSecret: requiredString(json, 'serviceAccountSecret'),
      testerEmails: emails,
      groupAliases: groups,
      releaseNotes: optionalString(json, 'releaseNotes'),
    );
  }

  /// The kind of artifact a file called [name] is, by its extension, or
  /// `null` if Firebase App Distribution takes no such file.
  static ArtifactKind? kindOf(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.apk')) return ArtifactKind.apk;
    if (lower.endsWith('.aab')) return ArtifactKind.aab;
    if (lower.endsWith('.ipa')) return ArtifactKind.ipa;
    return null;
  }

  /// The file name of the binary in the artifact store, such as
  /// `dev-1.2.3+45.apk`. It is looked up among the artifacts of the job.
  final String artifactName;

  /// The Firebase app id, such as `1:684690133351:android:b434734f`.
  final String appId;

  /// The version and build number the binary carries.
  final AppVersion version;

  /// The key in the secret store of the service account key (the JSON file).
  final String serviceAccountSecret;

  /// Email addresses to send the release to.
  final List<String> testerEmails;

  /// Aliases of the tester groups to send the release to.
  final List<String> groupAliases;

  /// The release notes; none are set if absent.
  final String? releaseNotes;

  /// The kind of the binary.
  ArtifactKind get kind => kindOf(artifactName)!;

  /// The project number in [appId].
  String get projectNumber => _appId.firstMatch(appId)![1]!;

  /// The app as the REST API names it: `projects/{number}/apps/{appId}`.
  String get appName => 'projects/$projectNumber/apps/$appId';

  /// Whether the release goes to testers or groups.
  bool get distributes => testerEmails.isNotEmpty || groupAliases.isNotEmpty;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'artifactName': artifactName,
    'appId': appId,
    'version': '$version',
    'serviceAccountSecret': serviceAccountSecret,
    if (testerEmails.isNotEmpty) 'testerEmails': testerEmails,
    if (groupAliases.isNotEmpty) 'groupAliases': groupAliases,
    'releaseNotes': ?releaseNotes,
  };

  @override
  List<Object?> get props => [
    artifactName,
    appId,
    version,
    serviceAccountSecret,
    testerEmails,
    groupAliases,
    releaseNotes,
  ];
}

/// What `upload.firebase` did.
class UploadFirebaseResult extends Equatable {
  /// Creates the result.
  const new({
    required this.releaseName,
    this.displayVersion,
    this.buildVersion,
    this.result = FirebaseUploadResult.unknown,
    this.alreadyUploaded = false,
    this.distributed = false,
    this.consoleUri,
    this.testingUri,
  });

  /// The release, `projects/{number}/apps/{appId}/releases/{id}`.
  final String releaseName;

  /// The version name of the binary Firebase read.
  final String? displayVersion;

  /// The build number of the binary Firebase read.
  final String? buildVersion;

  /// What the upload did to the releases.
  final FirebaseUploadResult result;

  /// Whether Firebase had the release before this run, so nothing was
  /// uploaded.
  final bool alreadyUploaded;

  /// Whether the release was sent to testers or groups by this run.
  final bool distributed;

  /// The release in the Firebase console.
  final String? consoleUri;

  /// Where testers install the release.
  final String? testingUri;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'releaseName': releaseName,
    'displayVersion': ?displayVersion,
    'buildVersion': ?buildVersion,
    if (result != FirebaseUploadResult.unknown) 'result': result.wire,
    'alreadyUploaded': alreadyUploaded,
    'distributed': distributed,
    'consoleUri': ?consoleUri,
    'testingUri': ?testingUri,
  };

  @override
  List<Object?> get props => [
    releaseName,
    displayVersion,
    buildVersion,
    result,
    alreadyUploaded,
    distributed,
    consoleUri,
    testingUri,
  ];
}
