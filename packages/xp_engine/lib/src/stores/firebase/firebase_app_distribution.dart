import 'package:xp_engine/src/stores/firebase/firebase_exceptions.dart';
import 'package:xp_engine/src/stores/firebase/firebase_models.dart';
import 'package:xp_engine/src/stores/play/play_service_account.dart';

/// The Firebase App Distribution REST API (v1), for one service account.
///
/// An app is named `projects/{projectNumber}/apps/{appId}`. Every call can
/// throw a [FirebaseException] (or one of its subtypes). `xp_adapters` has the
/// HTTP implementation. No Node and no `firebase` CLI (D-16).
abstract interface class FirebaseAppDistribution {
  /// Uploads a binary of [length] bytes to the app [appName]
  /// (`releases:upload`, raw body) and returns the operation that processes
  /// it. [content] opens the bytes; it is called again if the upload has to be
  /// repeated.
  Future<FirebaseOperation> uploadRelease(
    String appName, {
    required Stream<List<int>> Function() content,
    required int length,
    required String fileName,
  });

  /// The operation [name], to poll an upload until it is done.
  Future<FirebaseOperation> operation(String name);

  /// The releases of the app [appName], newest first, reading at most [pages]
  /// pages of 100.
  Future<List<FirebaseRelease>> releases(String appName, {int pages = 1});

  /// Sets the release notes of the release [releaseName].
  Future<FirebaseRelease> updateReleaseNotes(String releaseName, String text);

  /// Sends the release [releaseName] to testers and groups. Testers who do
  /// not exist are created and invited; a group that does not exist is an
  /// error.
  Future<void> distribute(
    String releaseName, {
    List<String> testerEmails = const [],
    List<String> groupAliases = const [],
  });

  /// Proves that Google accepts the service account: it exchanges the signed
  /// assertion for an access token.
  Future<void> verifyAccess();
}

/// Makes the client for a service account.
typedef FirebaseAppDistributionFactory = FirebaseAppDistribution Function(
  PlayServiceAccount account,
);

/// A [FirebaseAppDistribution] over data the test gives it.
class FakeFirebaseAppDistribution implements FirebaseAppDistribution {
  /// Creates a fake with nothing in it.
  new();

  /// The operations the next uploads answer, in order. An upload with none
  /// left answers an operation that is done with a release of the uploaded
  /// version.
  final uploadOperations = <FirebaseOperation>[];

  /// The operations [operation] answers for each poll of a name, in order.
  /// When a name has none left the last answer repeats.
  final operationsOf = <String, List<FirebaseOperation>>{};

  /// The releases [releases] reports for each app.
  final releasesOf = <String, List<FirebaseRelease>>{};

  /// What the call called `name` throws next, once.
  final failures = <String, FirebaseException>{};

  /// The bytes of each upload, oldest first.
  final uploads = <List<int>>[];

  /// The `length` argument of each upload, oldest first.
  final uploadLengths = <int>[];

  /// The `fileName` argument of each upload, oldest first.
  final uploadNames = <String>[];

  /// Every call as `name argument ...`, oldest first.
  final calls = <String>[];

  /// The notes set, as `release text`, oldest first.
  final notes = <String>[];

  /// The distributions, as `release testers=a,b groups=c`, oldest first.
  final distributions = <String>[];

  void _call(String name, String call) {
    calls.add(call);
    final error = failures.remove(name);
    if (error != null) throw error;
  }

  @override
  Future<FirebaseOperation> uploadRelease(
    String appName, {
    required Stream<List<int>> Function() content,
    required int length,
    required String fileName,
  }) async {
    _call('uploadRelease', 'uploadRelease $appName $length $fileName');
    final bytes = <int>[];
    await content().forEach(bytes.addAll);
    uploads.add(bytes);
    uploadLengths.add(length);
    uploadNames.add(fileName);
    if (uploadOperations.isNotEmpty) return uploadOperations.removeAt(0);
    return FirebaseOperation(
      name: '$appName/releases/-/operations/op-${uploads.length}',
      done: true,
      result: FirebaseUploadResult.created,
      release: FirebaseRelease(
        name: '$appName/releases/rel-${uploads.length}',
        displayVersion: '1.0.0',
        buildVersion: '${uploads.length}',
      ),
    );
  }

  @override
  Future<FirebaseOperation> operation(String name) async {
    _call('operation', 'operation $name');
    final answers = operationsOf[name];
    if (answers == null || answers.isEmpty) {
      return FirebaseOperation(name: name);
    }
    return answers.length == 1 ? answers.single : answers.removeAt(0);
  }

  @override
  Future<List<FirebaseRelease>> releases(
    String appName, {
    int pages = 1,
  }) async {
    _call('releases', 'releases $appName $pages');
    return releasesOf[appName] ?? const [];
  }

  @override
  Future<FirebaseRelease> updateReleaseNotes(
    String releaseName,
    String text,
  ) async {
    _call('updateReleaseNotes', 'updateReleaseNotes $releaseName');
    notes.add('$releaseName $text');
    return FirebaseRelease(name: releaseName, releaseNotes: text);
  }

  @override
  Future<void> distribute(
    String releaseName, {
    List<String> testerEmails = const [],
    List<String> groupAliases = const [],
  }) async {
    _call('distribute', 'distribute $releaseName');
    distributions.add(
      '$releaseName testers=${testerEmails.join(',')} '
      'groups=${groupAliases.join(',')}',
    );
  }

  @override
  Future<void> verifyAccess() async => _call('verifyAccess', 'verifyAccess');
}
