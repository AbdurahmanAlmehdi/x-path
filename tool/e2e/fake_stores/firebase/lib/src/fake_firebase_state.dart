import 'dart:convert';

/// The OAuth2 scope the fake server asks service accounts for.
const fakeFirebaseScope = 'https://www.googleapis.com/auth/cloud-platform';

/// The bytes of a binary the fake server accepts: it reads the version from
/// the first line, where Firebase reads the manifest or the plist.
///
/// [type] is `apk`, `aab` or `ipa`.
List<int> fakeBinary(
  String type, {
  required String versionName,
  required int versionCode,
  int padding = 0,
}) => utf8.encode(
  'fake-$type versionName=$versionName versionCode=$versionCode\n'
  '${'x' * padding}',
);

/// A release in an app of the fake server.
class FakeFirebaseRelease {
  /// Creates a release.
  new({
    required this.name,
    required this.displayVersion,
    required this.buildVersion,
    required this.binaryType,
    required this.createTime,
    required this.binary,
  });

  /// `projects/{number}/apps/{appId}/releases/{id}`.
  final String name;

  /// The version name of the binary.
  final String displayVersion;

  /// The build number of the binary.
  final String buildVersion;

  /// `APK`, `AAB` or `IPA`.
  final String binaryType;

  /// When the release was made.
  final DateTime createTime;

  /// The bytes of the binary.
  List<int> binary;

  /// The release notes, if set.
  String? notes;

  /// The distributions made, as `testers=a,b groups=c`.
  final distributions = <String>[];

  /// The release as the API writes it.
  Map<String, Object?> toJson() => {
    'name': name,
    'displayVersion': displayVersion,
    'buildVersion': buildVersion,
    'binaryType': binaryType,
    'createTime': createTime.toUtc().toIso8601String(),
    'firebaseConsoleUri': 'https://console.firebase.google.com/fake/$name',
    'testingUri': 'https://appdistribution.firebase.google.com/fake/$name',
    if (notes != null) 'releaseNotes': {'text': notes},
  };
}

/// An upload being processed.
class FakeFirebaseOperation {
  /// Creates an operation.
  new({
    required this.name,
    required this.release,
    required this.result,
    required this.pollsLeft,
  });

  /// `projects/{number}/apps/{appId}/releases/-/operations/{id}`.
  final String name;

  /// The release the upload made or found.
  final FakeFirebaseRelease release;

  /// `RELEASE_CREATED`, `RELEASE_UPDATED` or `RELEASE_UNMODIFIED`.
  final String result;

  /// How many polls still answer "not done".
  int pollsLeft;
}

/// An app of the fake server.
class FakeFirebaseApp {
  /// Creates an app.
  new(
    this.projectNumber,
    this.appId, {
    this.allowedAccounts,
    Set<String>? groups,
  }) : groups = groups ?? {};

  /// The project number.
  final String projectNumber;

  /// The Firebase app id.
  final String appId;

  /// The service accounts (by email) that may use the app, or `null` for
  /// every account the server knows.
  Set<String>? allowedAccounts;

  /// The aliases of the tester groups that exist.
  final Set<String> groups;

  /// The releases, oldest first.
  final releases = <FakeFirebaseRelease>[];

  /// The resource name, `projects/{number}/apps/{appId}`.
  String get name => 'projects/$projectNumber/apps/$appId';
}

/// A request the fake server received.
class FakeFirebaseRequest {
  /// Creates a record.
  const new({
    required this.method,
    required this.uri,
    required this.headers,
    required this.bodyLength,
    this.body,
    this.tokenProblem,
  });

  /// `GET`, `POST`, `PATCH`.
  final String method;

  /// The request URI.
  final Uri uri;

  /// The request headers, lower case names.
  final Map<String, String> headers;

  /// The size of the body in bytes.
  final int bodyLength;

  /// The decoded JSON body, if it had one.
  final Object? body;

  /// Why the access token was refused, if it was.
  final String? tokenProblem;
}
