import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';

/// The status a release in [state] shows.
XpStatus releaseStatus(ReleaseState state) => switch (state) {
  ReleaseState.draft => XpStatus.releaseDraft,
  ReleaseState.building => XpStatus.releaseBuilding,
  ReleaseState.uploaded => XpStatus.releaseUploaded,
  ReleaseState.inReview => XpStatus.releaseInReview,
  ReleaseState.rejected => XpStatus.releaseRejected,
  ReleaseState.approved => XpStatus.releaseApproved,
  ReleaseState.live => XpStatus.releaseLive,
  ReleaseState.merged => XpStatus.releaseMerged,
  ReleaseState.abandoned => XpStatus.releaseAbandoned,
};

/// The status a release in [state] in [store] shows (the App Store and
/// Google Play lanes).
XpStatus storeStatus(ReleaseStore store, StoreState state) => switch ((
  store,
  state,
)) {
  (_, StoreState.pending) => XpStatus.appstoreProcessing,
  (_, StoreState.uploaded) => XpStatus.releaseUploaded,
  (ReleaseStore.apple, StoreState.inReview) => XpStatus.appstoreInReview,
  (ReleaseStore.play, StoreState.inReview) => XpStatus.playInReview,
  (ReleaseStore.apple, StoreState.rejected) => XpStatus.appstoreRejected,
  (ReleaseStore.play, StoreState.rejected) => XpStatus.playNotApproved,
  (ReleaseStore.apple, StoreState.approved) => XpStatus.appstorePendingRelease,
  (ReleaseStore.play, StoreState.approved) => XpStatus.playApprovedUnpublished,
  (ReleaseStore.apple, StoreState.live) => XpStatus.appstoreLive,
  (ReleaseStore.play, StoreState.live) => XpStatus.playLive,
};

extension ReleaseLabels on AppLocalizations {
  /// What a release in [state] is called.
  String releaseState(ReleaseState state) => switch (state) {
    ReleaseState.draft => releaseDraft,
    ReleaseState.building => releaseBuilding,
    ReleaseState.uploaded => releaseUploaded,
    ReleaseState.inReview => releaseInReview,
    ReleaseState.rejected => releaseRejected,
    ReleaseState.approved => releaseApproved,
    ReleaseState.live => releaseLive,
    ReleaseState.merged => releaseMerged,
    ReleaseState.abandoned => releaseAbandoned,
  };

  /// What [store] calls a release in [state].
  String storeState(ReleaseStore store, StoreState state) =>
      switch ((store, state)) {
        (_, StoreState.pending) => storeNotUploaded,
        (_, StoreState.uploaded) => storeUploaded,
        (_, StoreState.inReview) => storeInReview,
        (ReleaseStore.apple, StoreState.rejected) => storeRejected,
        (ReleaseStore.play, StoreState.rejected) => storeNotApproved,
        (ReleaseStore.apple, StoreState.approved) => storePendingRelease,
        (ReleaseStore.play, StoreState.approved) => storeApprovedUnpublished,
        (ReleaseStore.apple, StoreState.live) => storeReadyForSale,
        (ReleaseStore.play, StoreState.live) => storePublished,
      };

  /// What the UI calls [store].
  String storeName(ReleaseStore store) => switch (store) {
    ReleaseStore.apple => storeAppStore,
    ReleaseStore.play => storeGooglePlay,
  };
}

/// The status of [release] in [store], if it targets it.
StoreStatus? storeOf(Release release, ReleaseStore store) {
  for (final status in release.stores) {
    if (status.store == store) return status;
  }
  return null;
}
