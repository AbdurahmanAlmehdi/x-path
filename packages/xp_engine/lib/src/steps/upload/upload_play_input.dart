import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/stores/play/play_models.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// The track `upload.play` uses unless told otherwise.
const defaultPlayTrack = 'internal';

final _packageName = RegExp(r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$');
final _trackName = RegExp(r'^[A-Za-z0-9_:.-]+$');

/// What to upload to Google Play.
class UploadPlayInput extends Equatable {
  /// Creates the input. [version] must have a build number, which is the
  /// version code of the bundle (`fromJson` checks it and the rest).
  const new({
    required this.artifactName,
    required this.packageName,
    required this.version,
    required this.serviceAccountSecret,
    this.track = defaultPlayTrack,
    this.status = PlayReleaseStatus.completed,
    this.userFraction,
    this.releaseName,
    this.releaseNotes = const {},
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// the version has no build number, or the release is not one Play takes.
  factory fromJson(Map<String, dynamic> json) {
    final version = AppVersion.parse(requiredString(json, 'version'));
    if (version.build == null) {
      throw const FormatException('"version" needs a build number: x.y.z+n.');
    }
    final artifactName = requiredString(json, 'artifactName');
    if (artifactName.contains('/') || artifactName.contains(r'\')) {
      throw const FormatException('"artifactName" must be a plain file name.');
    }
    final packageName = requiredString(json, 'packageName');
    if (!_packageName.hasMatch(packageName)) {
      throw const FormatException(
        '"packageName" must be an application id like ly.example.app.',
      );
    }
    final track = optionalString(json, 'track') ?? defaultPlayTrack;
    if (!_trackName.hasMatch(track)) {
      throw const FormatException(
        '"track" must be a track name like internal or production.',
      );
    }
    final status = _status(optionalString(json, 'status'));
    final userFraction = _fraction(json['userFraction']);
    if (status == PlayReleaseStatus.inProgress && userFraction == null) {
      throw const FormatException(
        '"userFraction" is needed when "status" is "inProgress".',
      );
    }
    if (status != PlayReleaseStatus.inProgress && userFraction != null) {
      throw const FormatException(
        '"userFraction" can only be set when "status" is "inProgress".',
      );
    }
    return UploadPlayInput(
      artifactName: artifactName,
      packageName: packageName,
      version: version,
      serviceAccountSecret: requiredString(json, 'serviceAccountSecret'),
      track: track,
      status: status,
      userFraction: userFraction,
      releaseName: optionalString(json, 'releaseName'),
      releaseNotes: stringMap(json, 'releaseNotes'),
    );
  }

  static PlayReleaseStatus _status(String? wire) {
    if (wire == null) return PlayReleaseStatus.completed;
    final status = PlayReleaseStatus.fromWire(wire);
    if (status == PlayReleaseStatus.completed ||
        status == PlayReleaseStatus.draft ||
        status == PlayReleaseStatus.inProgress) {
      return status;
    }
    throw FormatException(
      '"status" must be "completed", "inProgress" or "draft", not $wire.',
    );
  }

  static double? _fraction(Object? value) {
    if (value == null) return null;
    if (value is num && value > 0 && value < 1) return value.toDouble();
    throw const FormatException('"userFraction" must be above 0 and below 1.');
  }

  /// The file name of the AAB in the artifact store, such as
  /// `prod-1.2.3+45.aab`. It is looked up among the artifacts of the job.
  final String artifactName;

  /// The Android application id of the app.
  final String packageName;

  /// The version and build number the bundle carries. The build number is the
  /// version code.
  final AppVersion version;

  /// The key in the secret store of the service account key (the JSON file,
  /// `PlayServiceAccount.toSecret`).
  final String serviceAccountSecret;

  /// The track the release goes to.
  final String track;

  /// The status of the release in the track.
  final PlayReleaseStatus status;

  /// The fraction of users of a staged rollout, for `inProgress`.
  final double? userFraction;

  /// The release name; Play makes one from the version name if absent.
  final String? releaseName;

  /// The release notes, by language tag.
  final Map<String, String> releaseNotes;

  /// The version code.
  int get versionCode => version.build ?? 0;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'artifactName': artifactName,
    'packageName': packageName,
    'version': '$version',
    'serviceAccountSecret': serviceAccountSecret,
    'track': track,
    'status': status.wire,
    'userFraction': ?userFraction,
    'releaseName': ?releaseName,
    if (releaseNotes.isNotEmpty) 'releaseNotes': releaseNotes,
  };

  @override
  List<Object?> get props => [
    artifactName,
    packageName,
    version,
    serviceAccountSecret,
    track,
    status,
    userFraction,
    releaseName,
    releaseNotes,
  ];
}

/// What `upload.play` did.
class UploadPlayResult extends Equatable {
  /// Creates the result.
  const new({
    required this.versionCode,
    required this.track,
    this.alreadyUploaded = false,
    this.lifecycleState,
  });

  /// The version code of the bundle.
  final int versionCode;

  /// The track it is in.
  final String track;

  /// Whether Google Play had the version code in the track before this run,
  /// so nothing was uploaded.
  final bool alreadyUploaded;

  /// Where the release is in review (`releaseLifecycleState`), when Play
  /// could say.
  final PlayLifecycleState? lifecycleState;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'versionCode': versionCode,
    'track': track,
    'alreadyUploaded': alreadyUploaded,
    'lifecycleState': ?lifecycleState?.wire,
  };

  @override
  List<Object?> get props => [
    versionCode,
    track,
    alreadyUploaded,
    lifecycleState,
  ];
}
