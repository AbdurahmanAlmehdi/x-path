import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';
import 'package:xp_engine/src/stores/apple/asc_key.dart';
import 'package:xp_engine/src/stores/apple/asc_models.dart';

/// The App Store Connect REST API, for one API key.
///
/// Every call can throw an [AppStoreConnectException] (or one of its
/// subtypes). `xp_adapters` has the HTTP implementation. API keys only: an
/// Apple ID with an app-specific password cannot use the REST API (D-14).
abstract interface class AppStoreConnect {
  /// How much quota the key had left after the last call, or `null` before a
  /// call or if Apple did not say.
  AscRateLimit? get rateLimit;

  /// The app with bundle id [bundleId], or `null` if the team has none.
  Future<AscApp?> findApp(String bundleId);

  /// The builds of the app [appId], newest first, optionally only those of
  /// the marketing version [version] and the build number [buildNumber].
  Future<List<AscBuild>> builds(
    String appId, {
    String? version,
    String? buildNumber,
  });

  /// The App Store versions of the app [appId] for iOS, newest first, with
  /// their `appVersionState`.
  Future<List<AscAppStoreVersion>> versions(String appId);

  /// The review submissions of the app [appId] for iOS, in the order App Store
  /// Connect returns them.
  Future<List<AscReviewSubmission>> reviewSubmissions(String appId);

  /// The review submission [id].
  Future<AscReviewSubmission> reviewSubmission(String id);

  /// Creates a review submission of the app [appId] that holds the version
  /// [versionId]. It is not sent to Apple until [submitReviewSubmission].
  Future<AscReviewSubmission> createReviewSubmission(
    String appId,
    String versionId,
  );

  /// Sends the review submission [id] to Apple.
  Future<AscReviewSubmission> submitReviewSubmission(String id);

  /// The phased release of the version [versionId], or `null` if it has none.
  Future<AscPhasedRelease?> phasedRelease(String versionId);

  /// Moves the phased release [id] to [state] (pause, resume, complete).
  Future<AscPhasedRelease> updatePhasedRelease(
    String id,
    PhasedReleaseState state,
  );

  /// Uploads the IPA [content] ([length] bytes, named [fileName]) as the
  /// build [buildNumber] of the version [version] of the app [appId], through
  /// the build-upload API: it creates the build upload and its file, sends the
  /// parts App Store Connect asks for and marks the file uploaded. The token
  /// is never sent with the parts, which go to the addresses Apple names.
  ///
  /// App Store Connect goes on processing the upload after it returns; ask
  /// [buildUpload] until its state is final.
  Future<AscBuildUpload> uploadBuild(
    String appId, {
    required String version,
    required String buildNumber,
    required String fileName,
    required int length,
    required Stream<List<int>> Function() content,
  });

  /// The build upload [id], with its state, errors and warnings.
  Future<AscBuildUpload> buildUpload(String id);

  /// Proves that Apple accepts the key: it reads one app (`GET /v1/apps` with
  /// a limit of 1). Credential checks use it; a `401` is an expired or revoked
  /// key.
  Future<void> verifyAccess();
}

/// Makes the client for an API key.
typedef AppStoreConnectFactory = AppStoreConnect Function(AscKey key);

/// An [AppStoreConnect] over data the test gives it.
class FakeAppStoreConnect implements AppStoreConnect {
  /// Creates a fake with nothing in it.
  new();

  /// The apps, by bundle id.
  final apps = <String, AscApp>{};

  /// The builds of each app id.
  final buildsOf = <String, List<AscBuild>>{};

  /// The versions of each app id.
  final versionsOf = <String, List<AscAppStoreVersion>>{};

  /// The submissions of each app id.
  final submissionsOf = <String, List<AscReviewSubmission>>{};

  /// The phased release of each version id.
  final phasedReleases = <String, AscPhasedRelease>{};

  /// What [buildUpload] answers, oldest first; the last one is answered
  /// again. With none, every upload is complete.
  final uploadAnswers = <AscBuildUpload>[];

  /// The bytes of each upload, by its id.
  final uploads = <String, List<int>>{};

  /// What the next call throws, once; `null` for nothing.
  AppStoreConnectException? failure;

  @override
  AscRateLimit? rateLimit;

  /// Every call as `name argument ...`, oldest first.
  final calls = <String>[];

  void _call(String call) {
    calls.add(call);
    final error = failure;
    if (error != null) {
      failure = null;
      throw error;
    }
  }

  @override
  Future<AscApp?> findApp(String bundleId) async {
    _call('findApp $bundleId');
    return apps[bundleId];
  }

  @override
  Future<List<AscBuild>> builds(
    String appId, {
    String? version,
    String? buildNumber,
  }) async {
    _call('builds $appId $version $buildNumber');
    return [
      for (final build in buildsOf[appId] ?? const <AscBuild>[])
        if ((version == null || build.version == version) &&
            (buildNumber == null || build.buildNumber == buildNumber))
          build,
    ];
  }

  @override
  Future<List<AscAppStoreVersion>> versions(String appId) async {
    _call('versions $appId');
    return versionsOf[appId] ?? const [];
  }

  @override
  Future<List<AscReviewSubmission>> reviewSubmissions(String appId) async {
    _call('reviewSubmissions $appId');
    return submissionsOf[appId] ?? const [];
  }

  @override
  Future<AscReviewSubmission> reviewSubmission(String id) async {
    _call('reviewSubmission $id');
    return _submission(id);
  }

  @override
  Future<AscReviewSubmission> createReviewSubmission(
    String appId,
    String versionId,
  ) async {
    _call('createReviewSubmission $appId $versionId');
    final submission = AscReviewSubmission(
      id: 'submission-${calls.length}',
      state: ReviewSubmissionState.readyForReview,
      platform: 'IOS',
    );
    submissionsOf.putIfAbsent(appId, () => []).insert(0, submission);
    return submission;
  }

  @override
  Future<AscReviewSubmission> submitReviewSubmission(String id) async {
    _call('submitReviewSubmission $id');
    return _replace(
      id,
      (submission) => AscReviewSubmission(
        id: id,
        state: ReviewSubmissionState.waitingForReview,
        platform: submission.platform,
        submittedDate: DateTime.utc(2026),
      ),
    );
  }

  @override
  Future<AscPhasedRelease?> phasedRelease(String versionId) async {
    _call('phasedRelease $versionId');
    return phasedReleases[versionId];
  }

  @override
  Future<AscPhasedRelease> updatePhasedRelease(
    String id,
    PhasedReleaseState state,
  ) async {
    _call('updatePhasedRelease $id ${state.wire}');
    final entry = phasedReleases.entries.firstWhere(
      (entry) => entry.value.id == id,
    );
    return phasedReleases[entry.key] = AscPhasedRelease(
      id: id,
      state: state,
      currentDayNumber: entry.value.currentDayNumber,
    );
  }

  @override
  Future<AscBuildUpload> uploadBuild(
    String appId, {
    required String version,
    required String buildNumber,
    required String fileName,
    required int length,
    required Stream<List<int>> Function() content,
  }) async {
    _call('uploadBuild $appId $version $buildNumber $fileName $length');
    final id = 'upload-${calls.length}';
    uploads[id] = [await for (final chunk in content()) ...chunk];
    return AscBuildUpload(id: id, state: AscBuildUploadState.processing);
  }

  @override
  Future<AscBuildUpload> buildUpload(String id) async {
    _call('buildUpload $id');
    if (uploadAnswers.isEmpty) {
      return AscBuildUpload(
        id: id,
        state: AscBuildUploadState.complete,
        buildId: 'build-of-$id',
      );
    }
    return uploadAnswers.length == 1
        ? uploadAnswers.single
        : uploadAnswers.removeAt(0);
  }

  @override
  Future<void> verifyAccess() async => _call('verifyAccess');

  AscReviewSubmission _submission(String id) =>
      [for (final list in submissionsOf.values) ...list]
          .firstWhere((submission) => submission.id == id);

  AscReviewSubmission _replace(
    String id,
    AscReviewSubmission Function(AscReviewSubmission) change,
  ) {
    for (final list in submissionsOf.values) {
      final index = list.indexWhere((submission) => submission.id == id);
      if (index >= 0) return list[index] = change(list[index]);
    }
    throw StateError('There is no submission $id.');
  }
}
