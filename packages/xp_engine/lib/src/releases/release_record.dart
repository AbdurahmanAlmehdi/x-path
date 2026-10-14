import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

const _unset = Object();

/// What the engine stores about a release in one store: the status the API
/// shows, and what is needed to ask the store about it again.
class StoreEntry extends Equatable {
  /// Creates an entry.
  const new({
    required this.store,
    required this.state,
    required this.source,
    this.identity = const {},
    this.detail,
    this.checkedAt,
    this.changedAt,
    this.note,
    this.ignored,
  });

  /// Reads an entry from its stored form.
  factory fromJson(ReleaseStore store, Map<String, dynamic> json) {
    DateTime? time(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return StoreEntry(
      store: store,
      state: StoreState.values.firstWhere((s) => s.wire == json['state']),
      source: StatusSource.values.firstWhere((s) => s.wire == json['source']),
      identity: Map<String, String>.from(json['identity'] as Map),
      detail: json['detail'] as String?,
      checkedAt: time('checkedAt'),
      changedAt: time('changedAt'),
      note: json['note'] as String?,
      ignored: json['ignored'] as String?,
    );
  }

  /// Which store.
  final ReleaseStore store;

  /// Where the release is in it.
  final StoreState state;

  /// Where [state] came from.
  final StatusSource source;

  /// What identifies the app in the store, to ask it again. For Apple:
  /// `bundleId`, `appleAppId` and `country`; for Google Play: `packageName`
  /// and `track`.
  final Map<String, String> identity;

  /// What the store said, as it said it.
  final String? detail;

  /// When the store was asked last.
  final DateTime? checkedAt;

  /// When [state] last changed.
  final DateTime? changedAt;

  /// Why the store could not be read the last time, or what the owner should
  /// know.
  final String? note;

  /// A [detail] the store still reports from an earlier build (App Store
  /// Connect says `REJECTED` about the version until the new build is
  /// submitted): a reading with it is not news.
  final String? ignored;

  /// This entry with the given fields replaced. Pass `null` to [detail],
  /// [checkedAt], [changedAt], [note] or [ignored] to clear them.
  StoreEntry copyWith({
    StoreState? state,
    StatusSource? source,
    Object? detail = _unset,
    Object? checkedAt = _unset,
    Object? changedAt = _unset,
    Object? note = _unset,
    Object? ignored = _unset,
  }) => StoreEntry(
    store: store,
    state: state ?? this.state,
    source: source ?? this.source,
    identity: identity,
    detail: identical(detail, _unset) ? this.detail : detail as String?,
    checkedAt: identical(checkedAt, _unset)
        ? this.checkedAt
        : checkedAt as DateTime?,
    changedAt: identical(changedAt, _unset)
        ? this.changedAt
        : changedAt as DateTime?,
    note: identical(note, _unset) ? this.note : note as String?,
    ignored: identical(ignored, _unset) ? this.ignored : ignored as String?,
  );

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'state': state.wire,
    'source': source.wire,
    'identity': identity,
    'detail': ?detail,
    'checkedAt': ?checkedAt?.toUtc().toIso8601String(),
    'changedAt': ?changedAt?.toUtc().toIso8601String(),
    'note': ?note,
    'ignored': ?ignored,
  };

  /// The API form.
  StoreStatus toApi() => StoreStatus(
    store: store,
    state: state,
    source: source,
    detail: detail,
    checkedAt: checkedAt,
    changedAt: changedAt,
    note: note,
  );

  @override
  List<Object?> get props => [
    store,
    state,
    source,
    identity,
    detail,
    checkedAt,
    changedAt,
    note,
    ignored,
  ];
}

/// What the engine stores about a release (D-17).
///
/// One release is one flavor of one app at one version. A new build of the
/// same version after a rejection stays in the same release: [build] is the
/// current one and [builds] lists them all.
class ReleaseRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.projectId,
    required this.appPath,
    required this.flavor,
    required this.version,
    required this.build,
    required this.state,
    required this.stores,
    required this.builds,
    required this.baseBranch,
    required this.createdAt,
    required this.updatedAt,
    this.branch,
    this.tag,
    this.headSha,
    this.prNumber,
    this.prUrl,
    this.mergeCommit,
    this.mergeRunId,
    this.message,
  });

  /// The engine's id, for example `rel_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project.
  final String projectId;

  /// The path of the app.
  final String appPath;

  /// The flavor.
  final String flavor;

  /// The marketing version, `x.y.z`.
  final String version;

  /// The build number now.
  final int build;

  /// Where it is.
  final ReleaseState state;

  /// The stores the release targets, with its status in each.
  final Map<ReleaseStore, StoreEntry> stores;

  /// Every build, oldest first.
  final List<ReleaseBuild> builds;

  /// The branch the pull request merges into.
  final String baseBranch;

  /// The release branch, once it is cut.
  final String? branch;

  /// The tag of the current build, once it is made.
  final String? tag;

  /// The commit the current build was tagged on.
  final String? headSha;

  /// The pull request, once it is opened.
  final int? prNumber;

  /// Where to see it.
  final String? prUrl;

  /// The merge commit, once merged.
  final String? mergeCommit;

  /// The run that merges the pull request, while it is under way.
  final String? mergeRunId;

  /// Why the release was abandoned, or what the owner should know.
  final String? message;

  /// When the release was dispatched.
  final DateTime createdAt;

  /// When it last changed.
  final DateTime updatedAt;

  /// The run of the current build.
  String get runId => builds.last.runId;

  /// Whether the merge of the pull request can be requested: every store
  /// targeted is live, the pull request exists and no run merges it.
  bool get mergeEnabled =>
      state == ReleaseState.live && prNumber != null && mergeRunId == null;

  /// This record with the given fields replaced. Pass `null` to [branch],
  /// [tag], [headSha], [prNumber], [prUrl], [mergeCommit], [mergeRunId] or
  /// [message] to clear them.
  ReleaseRecord copyWith({
    int? build,
    ReleaseState? state,
    Map<ReleaseStore, StoreEntry>? stores,
    List<ReleaseBuild>? builds,
    DateTime? updatedAt,
    Object? branch = _unset,
    Object? tag = _unset,
    Object? headSha = _unset,
    Object? prNumber = _unset,
    Object? prUrl = _unset,
    Object? mergeCommit = _unset,
    Object? mergeRunId = _unset,
    Object? message = _unset,
  }) => ReleaseRecord(
    id: id,
    projectId: projectId,
    appPath: appPath,
    flavor: flavor,
    version: version,
    build: build ?? this.build,
    state: state ?? this.state,
    stores: stores ?? this.stores,
    builds: builds ?? this.builds,
    baseBranch: baseBranch,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    branch: identical(branch, _unset) ? this.branch : branch as String?,
    tag: identical(tag, _unset) ? this.tag : tag as String?,
    headSha: identical(headSha, _unset) ? this.headSha : headSha as String?,
    prNumber: identical(prNumber, _unset) ? this.prNumber : prNumber as int?,
    prUrl: identical(prUrl, _unset) ? this.prUrl : prUrl as String?,
    mergeCommit: identical(mergeCommit, _unset)
        ? this.mergeCommit
        : mergeCommit as String?,
    mergeRunId: identical(mergeRunId, _unset)
        ? this.mergeRunId
        : mergeRunId as String?,
    message: identical(message, _unset) ? this.message : message as String?,
  );

  /// The stored form of [stores]: the `store_status` column.
  Map<String, dynamic> storesToJson() => {
    for (final entry in stores.entries) entry.key.wire: entry.value.toJson(),
  };

  /// Reads [storesToJson] back.
  static Map<ReleaseStore, StoreEntry> storesFromJson(
    Map<String, dynamic> json,
  ) => {
    for (final store in ReleaseStore.values)
      if (json[store.wire] != null)
        store: StoreEntry.fromJson(
          store,
          json[store.wire] as Map<String, dynamic>,
        ),
  };

  /// The API form.
  Release toApi() => Release(
    id: id,
    projectId: projectId,
    app: appPath,
    flavor: flavor,
    version: version,
    build: build,
    state: state,
    stores: [for (final entry in stores.values) entry.toApi()],
    builds: builds,
    mergeEnabled: mergeEnabled,
    branch: branch,
    baseBranch: baseBranch,
    tag: tag,
    headSha: headSha,
    prNumber: prNumber,
    prUrl: prUrl,
    mergeCommit: mergeCommit,
    mergeRunId: mergeRunId,
    message: message,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    projectId,
    appPath,
    flavor,
    version,
    build,
    state,
    stores,
    builds,
    baseBranch,
    branch,
    tag,
    headSha,
    prNumber,
    prUrl,
    mergeCommit,
    mergeRunId,
    message,
    createdAt,
    updatedAt,
  ];
}
