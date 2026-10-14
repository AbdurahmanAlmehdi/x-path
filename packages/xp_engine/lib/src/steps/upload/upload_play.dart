import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/steps/build/stored_artifacts.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/steps/upload/upload_play_input.dart';
import 'package:xp_engine/src/stores/play/google_play.dart';
import 'package:xp_engine/src/stores/play/play_exceptions.dart';
import 'package:xp_engine/src/stores/play/play_models.dart';
import 'package:xp_engine/src/stores/play/play_service_account.dart';

/// Uploads the AAB of the job to Google Play and releases it to a track
/// (`upload.play`; D-15, D-09).
///
/// Opens an edit, uploads the bundle, sets the release of the track
/// (`completed`, `inProgress` with a user fraction, or `draft`) and commits
/// with `changesInReviewBehavior=ERROR_IF_IN_REVIEW`. If changes are in
/// review the step fails and the review is not cancelled; whatever fails, the
/// edit is deleted so that nothing is left half done.
///
/// The step has a side effect. `alreadyDone` lists the releases of the track
/// (`tracks.releases.list`) and is done when one holds the version code.
class UploadPlayStep extends Step<UploadPlayInput, UploadPlayResult> {
  /// Creates the step. [connect] makes the client for a service account.
  const new({
    required this.repository,
    required this.store,
    required this.secrets,
    required this.connect,
  });

  /// The records of the stored artifacts.
  final ArtifactRepository repository;

  /// The artifact store, whose AAB is streamed to Google Play.
  final ArtifactStore store;

  /// Where the service account key is read from.
  final SecretStore secrets;

  /// Makes the Google Play client of a service account.
  final GooglePlayFactory connect;

  @override
  String get kind => 'upload.play';

  @override
  bool sideEffectOf(UploadPlayInput input) => true;

  @override
  UploadPlayInput decodeInput(Map<String, dynamic> json) =>
      UploadPlayInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(UploadPlayInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(UploadPlayResult result) => result.toJson();

  /// Done when a release of the track holds the version code. If Google Play
  /// cannot be asked, the step runs, and Play refuses a version code it has
  /// seen.
  @override
  Future<UploadPlayResult?> alreadyDone(
    UploadPlayInput input,
    StepContext context,
  ) async {
    final PlayServiceAccount? account;
    try {
      account = await _readAccount(input.serviceAccountSecret);
    } on Object {
      return null;
    }
    if (account == null) return null;
    try {
      final releases = await connect(account)
          .releases(input.packageName, input.track);
      final release = releases
          .where((release) => release.versionCodes.contains(input.versionCode))
          .firstOrNull;
      if (release == null) return null;
      return UploadPlayResult(
        versionCode: input.versionCode,
        track: input.track,
        alreadyUploaded: true,
        lifecycleState: release.state,
      );
    } on PlayException {
      return null;
    }
  }

  @override
  Future<StepOutcome<UploadPlayResult>> run(
    UploadPlayInput input,
    StepContext context,
  ) async {
    final aab = await intactArtifact(
      repository: repository,
      store: store,
      jobId: input.artifactJob ?? context.jobId,
      name: input.artifactName,
      kind: ArtifactKind.aab,
    );
    if (aab == null) {
      return StepFailed(
        '${input.sourceOfArtifact} has no intact AAB named '
        '${input.artifactName}. Build the '
        'Android app first; a changed or missing file is not uploaded.',
      );
    }
    final (:account, :problem) = await _usableAccount(
      input.serviceAccountSecret,
    );
    if (account == null) return StepFailed(problem!);

    final play = connect(account);
    final String editId;
    try {
      editId = (await play.insertEdit(input.packageName)).id;
    } on PlayException catch (error) {
      return StepFailed(_describe(error));
    }

    try {
      return await _release(input, context, play, editId, aab.size, aab.path);
    } on PlayReviewInProgressException {
      await _discard(play, input.packageName, editId);
      return const StepFailed(
        'Play has a review in progress; the release was not committed and '
        'the review was not cancelled. Wait for the review to finish (or '
        'cancel it in the Play Console), then run the step again.',
      );
    } on PlayException catch (error) {
      await _discard(play, input.packageName, editId);
      return StepFailed(_describe(error));
    }
  }

  Future<StepOutcome<UploadPlayResult>> _release(
    UploadPlayInput input,
    StepContext context,
    GooglePlay play,
    String editId,
    int length,
    String path,
  ) async {
    final bundle = await play.uploadBundle(
      input.packageName,
      editId,
      content: () => store.read(path),
      length: length,
    );
    if (bundle.versionCode != input.versionCode) {
      await _discard(play, input.packageName, editId);
      return StepFailed(
        'The bundle ${input.artifactName} has version code '
        '${bundle.versionCode}, not the ${input.versionCode} of the build '
        'number ${input.version}. Nothing was released; build the app again.',
      );
    }
    await play.updateTrack(
      input.packageName,
      editId,
      PlayTrack(
        name: input.track,
        releases: [
          PlayRelease(
            versionCodes: [input.versionCode],
            status: input.status,
            userFraction: input.userFraction,
            name: input.releaseName,
            releaseNotes: input.releaseNotes,
          ),
        ],
      ),
    );
    if (context.isStopping) {
      await _discard(play, input.packageName, editId);
      return const StepFailed(
        'The upload to Google Play was cancelled before the commit; nothing '
        'was released.',
      );
    }
    await play.commitEdit(input.packageName, editId);
    return StepSucceeded(
      UploadPlayResult(
        versionCode: input.versionCode,
        track: input.track,
        lifecycleState: await _lifecycleState(play, input),
      ),
    );
  }

  /// The review state of the release that was committed, or `null` if Play
  /// cannot say now. The commit already went through.
  Future<PlayLifecycleState?> _lifecycleState(
    GooglePlay play,
    UploadPlayInput input,
  ) async {
    try {
      final releases = await play.releases(input.packageName, input.track);
      return releases
          .where((release) => release.versionCodes.contains(input.versionCode))
          .firstOrNull
          ?.state;
    } on PlayException {
      return null;
    }
  }

  /// Deletes the edit; a failure to do so changes nothing for the owner (the
  /// edit expires) and must not hide why the step failed.
  Future<void> _discard(
    GooglePlay play,
    String packageName,
    String editId,
  ) async {
    try {
      await play.deleteEdit(packageName, editId);
    } on PlayException {
      // The edit expires by itself.
    }
  }

  String _describe(PlayException error) {
    final fix = error.fix;
    return 'Google Play refused: ${error.message}${fix == null ? '' : ' $fix'}';
  }

  /// The service account under [secret], or `null` if there is none.
  Future<PlayServiceAccount?> _readAccount(String secret) async {
    final json = await secrets.read(secret);
    return json == null ? null : PlayServiceAccount.fromSecret(json);
  }

  /// The service account under [secret], or the reason it cannot be used.
  Future<({PlayServiceAccount? account, String? problem})> _usableAccount(
    String secret,
  ) async {
    try {
      final account = await _readAccount(secret);
      return (
        account: account,
        problem: account == null
            ? 'There is no service account under "$secret" in the secret '
                  'store. Without one XPath cannot upload to Google Play: '
                  'upload the bundle by hand in the Play Console.'
            : null,
      );
    } on FormatException catch (error) {
      return (
        account: null,
        problem:
            'The secret "$secret" is not a usable service account key: '
            '${error.message}',
      );
    }
  }
}
