import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/theme/theme.dart';

/// The `min_version_*` variable of [store] in Firebase Remote Config, as the
/// engine's reminder names it (Phase 12c).
String minVersionVariable(ReleaseStore store) => switch (store) {
  ReleaseStore.apple => 'min_version_ios',
  ReleaseStore.play => 'min_version_android',
};

/// The stores of [release] in [state].
List<ReleaseStore> storesIn(Release release, StoreState state) => [
  for (final status in release.stores)
    if (status.state == state) status.store,
];

/// The status the hero of [release] shows.
XpStatus heroStatus(Release release) => releaseStatus(release.state);

extension ReleaseBoardLabels on AppLocalizations {
  /// The hero of [release]: its state, and which store rejected it or has
  /// it live.
  String releaseHero(Release release) {
    final rejected = storesIn(release, StoreState.rejected);
    final live = storesIn(release, StoreState.live);
    return switch (release.state) {
      ReleaseState.rejected when rejected.length == 1 => releaseRejectedBy(
        storeName(rejected.single),
      ),
      ReleaseState.rejected when rejected.length > 1 => releaseRejectedByBoth,
      ReleaseState.live when live.length > 1 => overviewLiveBoth,
      ReleaseState.live when live.length == 1 => overviewLiveIn(
        storeName(live.single),
      ),
      _ => releaseState(release.state),
    };
  }

  /// Where a store status came from, for the timeline.
  String statusSource(ReleaseStore store, StatusSource source) =>
      switch ((store, source)) {
        (_, StatusSource.upload) => sourceUpload,
        (ReleaseStore.apple, StatusSource.api) => sourceAppStoreConnect,
        (ReleaseStore.play, StatusSource.api) => sourcePlayApi,
        (_, StatusSource.lookup) => sourceLookup,
        (_, StatusSource.manual) => sourceManual,
      };

  /// [stores] in one phrase: `App Store`, `App Store and Google Play`.
  String storeList(List<ReleaseStore> stores) =>
      stores.length == 1 ? storeName(stores.single) : storesBoth;

  /// The variables of [stores] in one phrase.
  String variableList(List<ReleaseStore> stores) =>
      stores.map(minVersionVariable).join(listAnd);
}
