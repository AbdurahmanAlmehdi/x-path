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
  projectId: 'prj_1',
  app: '.',
  flavor: 'prod',
  kind: CredentialKind.ascKey,
  status: CredentialStatus.verified,
);
