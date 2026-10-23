import 'package:equatable/equatable.dart';

/// An app in App Store Connect.
class AscApp extends Equatable {
  /// Creates an app.
  const new({required this.id, required this.bundleId, this.name});

  /// The numeric Apple id of the app. altool takes it as `--apple-id`.
  final String id;

  /// The bundle id.
  final String bundleId;

  /// The name in App Store Connect.
  final String? name;

  @override
  List<Object?> get props => [id, bundleId, name];
}

/// Where App Store Connect is with a build it received.
enum AscProcessingState {
  /// Apple is processing the build.
  processing('PROCESSING'),

  /// Processing failed.
  failed('FAILED'),

  /// Apple found the build invalid.
  invalid('INVALID'),

  /// The build is processed and can go to TestFlight and review.
  valid('VALID'),

  /// A state this version of XPath does not know.
  unknown('');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// The state called [wire]; [unknown] for any other.
  static AscProcessingState fromWire(String? wire) => values.firstWhere(
    (state) => state.wire == wire && state != unknown,
    orElse: () => unknown,
  );
}

/// A build App Store Connect has received.
class AscBuild extends Equatable {
  /// Creates a build.
  const new({
    required this.id,
    required this.buildNumber,
    required this.processingState,
    this.version,
    this.uploadedDate,
    this.expired = false,
  });

  /// The id of the build resource.
  final String id;

  /// The build number (`CFBundleVersion`), as App Store Connect keeps it: a
  /// string.
  final String buildNumber;

  /// The marketing version (`CFBundleShortVersionString`) of the train the
  /// build is in, if the answer included it.
  final String? version;

  /// Where processing is.
  final AscProcessingState processingState;

  /// When the build was uploaded.
  final DateTime? uploadedDate;

  /// Whether the build expired (builds expire 90 days after upload). It still
  /// counts as a used build number.
  final bool expired;

  @override
  List<Object?> get props => [
    id,
    buildNumber,
    version,
    processingState,
    uploadedDate,
    expired,
  ];
}

/// Where App Store Connect is with a build upload (`buildUploads`).
enum AscBuildUploadState {
  /// The file was not sent yet.
  awaitingUpload('AWAITING_UPLOAD'),

  /// The file arrived; App Store Connect is checking it.
  processing('PROCESSING'),

  /// App Store Connect accepted the file and made a build of it.
  complete('COMPLETE'),

  /// App Store Connect refused the file; the errors say why.
  failed('FAILED'),

  /// A state this version of XPath does not know.
  unknown('');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// Whether App Store Connect is done with the upload, either way.
  bool get isFinal => this == complete || this == failed;

  /// The state called [wire]; [unknown] for any other.
  static AscBuildUploadState fromWire(String? wire) => values.firstWhere(
    (state) => state.wire == wire && state != unknown,
    orElse: () => unknown,
  );
}

/// An error or warning App Store Connect reports about a build upload.
class AscUploadIssue extends Equatable {
  /// Creates an issue.
  const new({required this.code, required this.description});

  /// The code, such as `90189` or `STATE_ERROR.VALIDATION_ERROR`.
  final String code;

  /// What App Store Connect says about it.
  final String description;

  @override
  String toString() => '$code: $description';

  @override
  List<Object?> get props => [code, description];
}

/// A build upload: an IPA sent through the API instead of altool.
class AscBuildUpload extends Equatable {
  /// Creates an upload.
  const new({
    required this.id,
    required this.state,
    this.errors = const [],
    this.warnings = const [],
    this.buildId,
  });

  /// The id of the build upload resource.
  final String id;

  /// Where App Store Connect is with it.
  final AscBuildUploadState state;

  /// Why App Store Connect refused it, when it did.
  final List<AscUploadIssue> errors;

  /// What App Store Connect warns about; the upload goes through.
  final List<AscUploadIssue> warnings;

  /// The build it became, once App Store Connect made one.
  final String? buildId;

  @override
  List<Object?> get props => [id, state, errors, warnings, buildId];
}

/// The state of an App Store version (`appVersionState`).
///
/// `appStoreState` is deprecated since version 3.7 of the API; XPath reads
/// this one only.
enum AppVersionState {
  /// The version is being prepared; nothing was submitted.
  prepareForSubmission('PREPARE_FOR_SUBMISSION'),

  /// Complete and ready to be submitted for review.
  readyForReview('READY_FOR_REVIEW'),

  /// Export compliance answers are missing.
  waitingForExportCompliance('WAITING_FOR_EXPORT_COMPLIANCE'),

  /// Submitted; Apple has not started the review.
  waitingForReview('WAITING_FOR_REVIEW'),

  /// Apple is reviewing it.
  inReview('IN_REVIEW'),

  /// Apple approved it.
  accepted('ACCEPTED'),

  /// Approved, waiting for the developer to release it.
  pendingDeveloperRelease('PENDING_DEVELOPER_RELEASE'),

  /// Approved, waiting for Apple's scheduled release.
  pendingAppleRelease('PENDING_APPLE_RELEASE'),

  /// Approved, a contract is missing.
  pendingContract('PENDING_CONTRACT'),

  /// Being released: processing for the store.
  processingForAppStore('PROCESSING_FOR_APP_STORE'),

  /// Live on the App Store.
  readyForDistribution('READY_FOR_DISTRIBUTION'),

  /// A pre-order that is live.
  preorderReadyForSale('PREORDER_READY_FOR_SALE'),

  /// Apple rejected it.
  rejected('REJECTED'),

  /// Apple rejected the metadata only.
  metadataRejected('METADATA_REJECTED'),

  /// Apple rejected the binary as invalid.
  invalidBinary('INVALID_BINARY'),

  /// The developer withdrew the submission.
  developerRejected('DEVELOPER_REJECTED'),

  /// The developer took the version off sale.
  developerRemovedFromSale('DEVELOPER_REMOVED_FROM_SALE'),

  /// Apple took the version off sale.
  removedFromSale('REMOVED_FROM_SALE'),

  /// A newer version replaced it.
  replacedWithNewVersion('REPLACED_WITH_NEW_VERSION'),

  /// A state this version of XPath does not know.
  unknown('');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// The state called [wire]; [unknown] for any other.
  static AppVersionState fromWire(String? wire) => values.firstWhere(
    (state) => state.wire == wire && state != unknown,
    orElse: () => unknown,
  );

  /// Whether the version is on sale now.
  bool get isLive =>
      this == readyForDistribution || this == preorderReadyForSale;

  /// Whether Apple approved the version and it is not on sale yet. Its train
  /// is closed: App Store Connect rejects any new build for it (ITMS-90186).
  bool get isApprovedNotLive => const {
    accepted,
    pendingDeveloperRelease,
    pendingAppleRelease,
    pendingContract,
    processingForAppStore,
  }.contains(this);

  /// Whether the version is submitted and waits for, or is in, review.
  bool get isInReview => this == waitingForReview || this == inReview;

  /// Whether the review ended without approval.
  bool get isRejected => const {
    rejected,
    metadataRejected,
    invalidBinary,
    developerRejected,
  }.contains(this);
}

/// An App Store version of an app.
class AscAppStoreVersion extends Equatable {
  /// Creates a version.
  const new({
    required this.id,
    required this.versionString,
    required this.platform,
    required this.state,
    this.createdDate,
  });

  /// The id of the version resource.
  final String id;

  /// The marketing version, such as `5.4.1`.
  final String versionString;

  /// `IOS`, `MAC_OS`, `TV_OS` or `VISION_OS`.
  final String platform;

  /// Where the version is: the review, the release.
  final AppVersionState state;

  /// When the version was created in App Store Connect.
  final DateTime? createdDate;

  @override
  List<Object?> get props => [id, versionString, platform, state, createdDate];
}

/// Where a review submission is.
enum ReviewSubmissionState {
  /// Created, not submitted.
  readyForReview('READY_FOR_REVIEW'),

  /// Submitted, waiting for Apple.
  waitingForReview('WAITING_FOR_REVIEW'),

  /// Apple is reviewing it.
  inReview('IN_REVIEW'),

  /// Apple found issues the developer has to resolve.
  unresolvedIssues('UNRESOLVED_ISSUES'),

  /// Being cancelled.
  canceling('CANCELING'),

  /// Being completed.
  completing('COMPLETING'),

  /// Reviewed and done.
  complete('COMPLETE'),

  /// A state this version of XPath does not know.
  unknown('');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// The state called [wire]; [unknown] for any other.
  static ReviewSubmissionState fromWire(String? wire) => values.firstWhere(
    (state) => state.wire == wire && state != unknown,
    orElse: () => unknown,
  );
}

/// A submission of an app to review.
class AscReviewSubmission extends Equatable {
  /// Creates a submission.
  const new({
    required this.id,
    required this.state,
    required this.platform,
    this.submittedDate,
  });

  /// The id of the submission.
  final String id;

  /// Where it is.
  final ReviewSubmissionState state;

  /// `IOS`, ...
  final String platform;

  /// When it was submitted.
  final DateTime? submittedDate;

  @override
  List<Object?> get props => [id, state, platform, submittedDate];
}

/// Where the phased release of a version is.
enum PhasedReleaseState {
  /// Not started.
  inactive('INACTIVE'),

  /// Rolling out.
  active('ACTIVE'),

  /// Paused by the developer.
  paused('PAUSED'),

  /// Everyone has it.
  complete('COMPLETE');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// The state called [wire], or `null`.
  static PhasedReleaseState? fromWire(String? wire) =>
      values.where((state) => state.wire == wire).firstOrNull;
}

/// The phased release (7-day rollout) of a version.
class AscPhasedRelease extends Equatable {
  /// Creates a phased release.
  const new({required this.id, required this.state, this.currentDayNumber});

  /// The id of the phased release resource.
  final String id;

  /// Where the rollout is.
  final PhasedReleaseState state;

  /// The day of the rollout, from 1; `null` before it starts.
  final int? currentDayNumber;

  @override
  List<Object?> get props => [id, state, currentDayNumber];
}

/// How much of its hourly quota a key has left, from the `X-Rate-Limit`
/// header of the last response.
class AscRateLimit extends Equatable {
  /// Creates a rate limit reading.
  const new({required this.limit, required this.remaining});

  /// Reads `user-hour-lim:3500;user-hour-rem:500;`, or returns `null` if the
  /// header is absent or not in that form.
  static AscRateLimit? parse(String? header) {
    if (header == null) return null;
    int? number(String name) {
      final match = RegExp('$name:(\\d+)').firstMatch(header);
      return match == null ? null : int.parse(match[1]!);
    }

    final limit = number('user-hour-lim');
    final remaining = number('user-hour-rem');
    if (limit == null || remaining == null) return null;
    return AscRateLimit(limit: limit, remaining: remaining);
  }

  /// Requests per hour for the key.
  final int limit;

  /// Requests left in the current hour.
  final int remaining;

  @override
  List<Object?> get props => [limit, remaining];
}
