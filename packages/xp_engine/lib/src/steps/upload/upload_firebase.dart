import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/releases/release_texts_source.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/steps/build/stored_artifacts.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/steps/upload/upload_firebase_input.dart';
import 'package:xp_engine/src/stores/firebase/firebase_app_distribution.dart';
import 'package:xp_engine/src/stores/firebase/firebase_exceptions.dart';
import 'package:xp_engine/src/stores/firebase/firebase_models.dart';
import 'package:xp_engine/src/stores/play/play_service_account.dart';

/// How many pages of 100 releases `alreadyDone` reads. A build that was
/// uploaded before is among the newest.
const _searchedPages = 3;

/// Uploads the APK, AAB or IPA of the job to Firebase App Distribution and
/// sends it to testers (`upload.firebase`, C:737-748; D-16, D-09).
///
/// Uses the REST API with a service account: `releases:upload` with the raw
/// bytes streamed from the artifact store, a poll of the long-running
/// operation until it is done, then the release notes (`releases.patch`) and
/// `releases:distribute` to the testers and groups of the input.
///
/// The step has a side effect. `alreadyDone` lists the newest releases
/// (`releases.list`) and is done when one has the build number and version
/// name of the input and, if the input has release notes, the same notes. A
/// release that exists but has other notes was not finished (the notes and the
/// distribution come after the upload), so the step runs again: the upload
/// finds the same release and the rest is repeated.
class UploadFirebaseStep
    extends Step<UploadFirebaseInput, UploadFirebaseResult> {
  /// Creates the step. [connect] makes the client for a service account.
  ///
  /// An upload is polled every [pollInterval] up to [maxPolls] times, waiting
  /// with [sleep] (`Future.delayed` by default; tests replace it).
  const new({
    required this.repository,
    required this.store,
    required this.secrets,
    required this.connect,
    this.texts,
    this.pollInterval = const Duration(seconds: 3),
    this.maxPolls = 200,
    this.sleep = Future.delayed,
  });

  /// The records of the stored artifacts.
  final ArtifactRepository repository;

  /// The artifact store, whose binary is streamed to Firebase.
  final ArtifactStore store;

  /// Where the service account key is read from.
  final SecretStore secrets;

  /// Makes the Firebase client of a service account.
  final FirebaseAppDistributionFactory connect;

  /// The texts of the release the job uploads: its "What to test" (else its
  /// "What's new") goes to the testers when the step gives no release notes
  /// (U7b).
  final ReleaseTextsSource? texts;

  /// How long to wait between two polls of the upload.
  final Duration pollInterval;

  /// How many times the upload is polled before the step gives up.
  final int maxPolls;

  /// Waits for a [Duration].
  final Future<void> Function(Duration) sleep;

  /// The release notes of [input], else the texts of the release of the job.
  Future<String?> _notes(UploadFirebaseInput input, StepContext context) async {
    if (input.releaseNotes case final notes?) return notes;
    final release = await texts?.ofJob(context.jobId);
    return release?.whatToTest ?? release?.whatsNew;
  }

  @override
  String get kind => 'upload.firebase';

  @override
  bool sideEffectOf(UploadFirebaseInput input) => true;

  @override
  UploadFirebaseInput decodeInput(Map<String, dynamic> json) =>
      UploadFirebaseInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(UploadFirebaseInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(UploadFirebaseResult result) =>
      result.toJson();

  /// Done when a release has the build number and version name of the input
  /// (and its release notes). If Firebase cannot be asked, the step runs, and
  /// Firebase finds the release it has.
  @override
  Future<UploadFirebaseResult?> alreadyDone(
    UploadFirebaseInput input,
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
          .releases(input.appName, pages: _searchedPages);
      final release = releases.where((r) => _isBuildOf(r, input)).firstOrNull;
      final notes = await _notes(input, context);
      if (release == null || (notes != null && release.releaseNotes != notes)) {
        return null;
      }
      return _result(release, alreadyUploaded: true);
    } on FirebaseException {
      return null;
    }
  }

  @override
  Future<StepOutcome<UploadFirebaseResult>> run(
    UploadFirebaseInput input,
    StepContext context,
  ) async {
    final binary = await intactArtifact(
      repository: repository,
      store: store,
      jobId: input.artifactJob ?? context.jobId,
      name: input.artifactName,
      kind: input.kind,
    );
    if (binary == null) {
      return StepFailed(
        '${input.sourceOfArtifact} has no intact '
        '${input.kind.wire.toUpperCase()} named '
        '${input.artifactName}. Build the app first; a changed or missing '
        'file is not uploaded.',
      );
    }
    final (:account, :problem) = await _usableAccount(
      input.serviceAccountSecret,
    );
    if (account == null) return StepFailed(problem!);

    final firebase = connect(account);
    FirebaseRelease? release;
    try {
      var operation = await firebase.uploadRelease(
        input.appName,
        content: () => store.read(binary.path),
        length: binary.size,
        fileName: input.artifactName,
      );
      for (var polls = 0; !operation.done; polls++) {
        if (context.isStopping) {
          return const StepFailed(
            'The upload to Firebase App Distribution was cancelled.',
          );
        }
        if (polls == maxPolls) {
          return StepFailed(
            'Firebase App Distribution is still processing the upload '
            '(${operation.name}) after ${maxPolls * pollInterval.inSeconds} '
            'seconds. Run the step again later: it will find the release if '
            'Firebase finished it.',
          );
        }
        await sleep(pollInterval);
        operation = await firebase.operation(operation.name);
      }
      final error = operation.error;
      if (error != null) throw FirebaseOperationFailedException(error);
      release = operation.release;
      if (release == null) {
        return const StepFailed(
          'Firebase App Distribution finished the upload but named no '
          'release.',
        );
      }
      final mismatch = _versionMismatch(release, input);
      if (mismatch != null) return StepFailed(mismatch);

      final notes = await _notes(input, context);
      if (notes != null && notes.isNotEmpty) {
        release = await firebase.updateReleaseNotes(release.name, notes);
      }
      if (input.distributes) {
        await firebase.distribute(
          release.name,
          testerEmails: input.testerEmails,
          groupAliases: input.groupAliases,
        );
      }
      return StepSucceeded(
        _result(
          operation.release!,
          result: operation.result,
          distributed: input.distributes,
        ),
      );
    } on FirebaseException catch (error) {
      final uploaded = release == null
          ? ''
          : ' The binary is in Firebase already (${release.name}); run the '
                'step again to finish the release notes and the '
                'distribution.';
      return StepFailed('${_describe(error)}$uploaded');
    }
  }

  bool _isBuildOf(FirebaseRelease release, UploadFirebaseInput input) =>
      release.buildVersion == '${input.version.build}' &&
      release.displayVersion == '${input.version.name}';

  /// Firebase reads the version from the binary. A binary that carries
  /// another one than the job built is not the build of this job.
  String? _versionMismatch(FirebaseRelease release, UploadFirebaseInput input) {
    final build = release.buildVersion;
    final name = release.displayVersion;
    if ((build == null || build == '${input.version.build}') &&
        (name == null || name == '${input.version.name}')) {
      return null;
    }
    return 'Firebase read version ${name ?? '?'} (${build ?? '?'}) from '
        '${input.artifactName}, not ${input.version}. The release '
        '${release.name} was made; build the app again so that the binary '
        'carries the version of the job.';
  }

  UploadFirebaseResult _result(
    FirebaseRelease release, {
    FirebaseUploadResult result = FirebaseUploadResult.unknown,
    bool alreadyUploaded = false,
    bool distributed = false,
  }) => UploadFirebaseResult(
    releaseName: release.name,
    displayVersion: release.displayVersion,
    buildVersion: release.buildVersion,
    result: result,
    alreadyUploaded: alreadyUploaded,
    distributed: distributed,
    consoleUri: release.firebaseConsoleUri,
    testingUri: release.testingUri,
  );

  String _describe(FirebaseException error) {
    final fix = error.fix;
    return 'Firebase App Distribution refused: ${error.message}'
        '${fix == null ? '' : ' $fix'}';
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
                  'store. Save a firebase_sa credential for the flavor, or '
                  'send the build to testers by hand.'
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
