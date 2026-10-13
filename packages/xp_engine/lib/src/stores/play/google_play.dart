import 'package:xp_engine/src/stores/play/play_exceptions.dart';
import 'package:xp_engine/src/stores/play/play_models.dart';
import 'package:xp_engine/src/stores/play/play_service_account.dart';

/// The Google Play Developer API (androidpublisher v3), for one service
/// account.
///
/// Changes go through an edit: [insertEdit], then uploads and track changes,
/// then [commitEdit]; [deleteEdit] throws the changes away. Every call can
/// throw a [PlayException] (or one of its subtypes). `xp_adapters` has the
/// HTTP implementation.
abstract interface class GooglePlay {
  /// Opens an edit of the app [packageName].
  Future<PlayEdit> insertEdit(String packageName);

  /// Discards the edit [editId] and everything uploaded or changed in it.
  Future<void> deleteEdit(String packageName, String editId);

  /// Uploads an Android App Bundle of [length] bytes to the edit.
  ///
  /// [content] opens the bytes: it is called again if the upload has to be
  /// repeated.
  Future<PlayBundle> uploadBundle(
    String packageName,
    String editId, {
    required Stream<List<int>> Function() content,
    required int length,
  });

  /// The bundles of the app, including those uploaded in the edit.
  Future<List<PlayBundle>> bundles(String packageName, String editId);

  /// The track [track] as the edit sees it.
  Future<PlayTrack> track(String packageName, String editId, String track);

  /// Replaces the releases of the track in the edit with those of [track].
  Future<PlayTrack> updateTrack(
    String packageName,
    String editId,
    PlayTrack track,
  );

  /// Commits the edit.
  ///
  /// This always sends `changesInReviewBehavior=ERROR_IF_IN_REVIEW` (D-15):
  /// Google Play's default is to cancel a review that is in progress, which a
  /// release tool must never do. If changes are in review the call throws a
  /// [PlayReviewInProgressException]; the review is untouched and the edit is
  /// still valid.
  Future<void> commitEdit(String packageName, String editId);

  /// The committed releases of the track [track], with their review state
  /// (`tracks.releases.list`: at most 20, no edit needed).
  Future<List<PlayReleaseSummary>> releases(String packageName, String track);

  /// Proves that Google accepts the service account: it exchanges the signed
  /// assertion for an access token. Credential checks use it.
  Future<void> verifyAccess();
}

/// Makes the client for a service account.
typedef GooglePlayFactory = GooglePlay Function(PlayServiceAccount account);

/// A [GooglePlay] over data the test gives it.
class FakeGooglePlay implements GooglePlay {
  /// Creates a fake with nothing in it.
  new();

  /// The version code the next uploads report, in order. When it is empty
  /// the fake counts up from 1.
  final uploadVersionCodes = <int>[];

  /// The bundles [bundles] reports.
  final bundlesOnPlay = <PlayBundle>[];

  /// The releases of each track [releases] reports.
  final releasesOf = <String, List<PlayReleaseSummary>>{};

  /// What a track holds before the edit changes it.
  final tracksOf = <String, PlayTrack>{};

  /// What the call called `name` throws next, once.
  final failures = <String, PlayException>{};

  /// The bytes of each upload, oldest first.
  final uploads = <List<int>>[];

  /// The `length` argument of each upload, oldest first.
  final uploadLengths = <int>[];

  /// Every call as `name argument ...`, oldest first.
  final calls = <String>[];

  /// The tracks [updateTrack] was called with, oldest first.
  final updatedTracks = <PlayTrack>[];

  /// The edits that were committed, oldest first.
  final committed = <String>[];

  /// The edits that were deleted, oldest first.
  final deleted = <String>[];

  var _edits = 0;

  void _call(String name, String call) {
    calls.add(call);
    final error = failures.remove(name);
    if (error != null) throw error;
  }

  @override
  Future<PlayEdit> insertEdit(String packageName) async {
    _call('insertEdit', 'insertEdit $packageName');
    return PlayEdit(id: 'edit-${++_edits}');
  }

  @override
  Future<void> deleteEdit(String packageName, String editId) async {
    _call('deleteEdit', 'deleteEdit $packageName $editId');
    deleted.add(editId);
  }

  @override
  Future<PlayBundle> uploadBundle(
    String packageName,
    String editId, {
    required Stream<List<int>> Function() content,
    required int length,
  }) async {
    _call('uploadBundle', 'uploadBundle $packageName $editId $length');
    final bytes = <int>[];
    await content().forEach(bytes.addAll);
    uploads.add(bytes);
    uploadLengths.add(length);
    final versionCode = uploadVersionCodes.isEmpty
        ? uploads.length
        : uploadVersionCodes.removeAt(0);
    return PlayBundle(versionCode: versionCode);
  }

  @override
  Future<List<PlayBundle>> bundles(String packageName, String editId) async {
    _call('bundles', 'bundles $packageName $editId');
    return bundlesOnPlay;
  }

  @override
  Future<PlayTrack> track(
    String packageName,
    String editId,
    String track,
  ) async {
    _call('track', 'track $packageName $editId $track');
    return tracksOf[track] ?? PlayTrack(name: track);
  }

  @override
  Future<PlayTrack> updateTrack(
    String packageName,
    String editId,
    PlayTrack track,
  ) async {
    _call('updateTrack', 'updateTrack $packageName $editId ${track.name}');
    updatedTracks.add(track);
    return tracksOf[track.name] = track;
  }

  @override
  Future<void> commitEdit(String packageName, String editId) async {
    _call('commitEdit', 'commitEdit $packageName $editId');
    committed.add(editId);
  }

  @override
  Future<List<PlayReleaseSummary>> releases(
    String packageName,
    String track,
  ) async {
    _call('releases', 'releases $packageName $track');
    return releasesOf[track] ?? const [];
  }

  @override
  Future<void> verifyAccess() async => _call('verifyAccess', 'verifyAccess');
}
