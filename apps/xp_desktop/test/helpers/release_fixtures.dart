import 'package:xp_api/xp_api.dart';

import 'job_fixtures.dart';

StoreStatus store(ReleaseStore store, StoreState state) =>
    StoreStatus(store: store, state: state, source: StatusSource.api);

Release release(
  String id,
  String version,
  int build,
  ReleaseState state, {
  List<StoreStatus> stores = const [],
  String flavor = 'prod',
  String? runId,
}) => Release(
  id: id,
  projectId: 'prj_1',
  app: '.',
  flavor: flavor,
  version: version,
  build: build,
  state: state,
  stores: stores,
  builds: [
    if (runId != null)
      ReleaseBuild(build: build, runId: runId, createdAt: local(14, 2)),
  ],
  mergeEnabled: false,
  headSha: state == ReleaseState.building ? null : sha,
  createdAt: local(14, 2),
  updatedAt: local(14, 2),
);

/// 5.4.1 (3283) building, the hero of `Main.dc.html`.
final Release buildingRelease = release(
  'rel_2',
  '5.4.1',
  3283,
  ReleaseState.building,
  runId: 'run_1',
  stores: [
    store(ReleaseStore.apple, StoreState.pending),
    store(ReleaseStore.play, StoreState.inReview),
  ],
);

/// 5.3.7 live in both stores.
final Release liveRelease = release(
  'rel_1',
  '5.3.7',
  3200,
  ReleaseState.live,
  runId: 'run_0',
  stores: [
    store(ReleaseStore.apple, StoreState.live),
    store(ReleaseStore.play, StoreState.live),
  ],
);

const verifiedKey = Credential(
  id: 'crd_1',
  name: 'Team App Store key',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
);

/// Oct 12 at [hour]:[minute] on this Mac, in UTC.
DateTime oct12(int hour, int minute) =>
    DateTime(2026, 10, 12, hour, minute).toUtc();

/// The store status of `Release-A-Lanes.dc.html`.
StoreStatus lane(
  ReleaseStore store,
  StoreState state, {
  StatusSource source = StatusSource.api,
  DateTime? changedAt,
  String? detail,
  String? note,
}) => StoreStatus(
  store: store,
  state: state,
  source: source,
  detail: detail,
  note: note,
  changedAt: changedAt,
  checkedAt: changedAt,
);

/// 5.4.1 (3283) of `Release-A-Lanes.dc.html`: the App Store waits for its
/// review, Google Play reviews it.
Release reviewRelease({
  ReleaseState state = ReleaseState.inReview,
  List<StoreStatus>? stores,
  bool mergeEnabled = false,
  String? mergeRunId,
  String? mergeCommit,
  int? prNumber = 42,
  String? message,
  List<ReleaseBuild>? builds,
}) => Release(
  id: 'rel_2',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  version: '5.4.1',
  build: 3283,
  state: state,
  stores:
      stores ??
      [
        lane(
          ReleaseStore.apple,
          StoreState.inReview,
          detail: 'WAITING_FOR_REVIEW',
          changedAt: oct12(19, 5),
        ),
        lane(ReleaseStore.play, StoreState.inReview, changedAt: oct12(19, 40)),
      ],
  builds:
      builds ??
      [ReleaseBuild(build: 3283, runId: 'run_1', createdAt: oct12(18, 30))],
  mergeEnabled: mergeEnabled,
  branch: 'release/5.4.1',
  baseBranch: 'main',
  tag: 'v5.4.1+3283',
  headSha: sha,
  prNumber: prNumber,
  prUrl: prNumber == null
      ? null
      : 'https://github.com/acme/mataa_new_app/pull/$prNumber',
  mergeRunId: mergeRunId,
  mergeCommit: mergeCommit,
  message: message,
  createdAt: oct12(18, 30),
  updatedAt: oct12(19, 40),
);

/// The notes of [reviewRelease].
const reviewNotes = ReleaseNotes(
  releaseId: 'rel_2',
  version: '5.4.1',
  build: 3283,
  from: 'v5.3.7+3200',
  to: sha,
  commits: 3,
  groups: [
    ReleaseNoteGroup(
      type: 'feat',
      title: 'Features',
      items: [
        ReleaseNoteItem(
          sha: sha,
          description: 'Faster checkout on slow connections',
          scope: 'checkout',
        ),
      ],
    ),
    ReleaseNoteGroup(
      type: 'fix',
      title: 'Fixes',
      items: [
        ReleaseNoteItem(
          sha: sha,
          description: 'Fixes a crash when reopening a past order',
        ),
      ],
    ),
  ],
  slack: '*5.4.1 (3283)*',
  whatsapp: '*5.4.1 (3283)* whatsapp',
);

const playAccount = Credential(
  id: 'crd_9',
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.playSa,
  status: CredentialStatus.verified,
);
