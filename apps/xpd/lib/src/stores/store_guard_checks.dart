import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/stores/apple_stores.dart';
import 'package:xpd/src/stores/play_stores.dart';

/// The guard checks that ask the stores (D-22): `appStoreTrain`,
/// `playTargetSdk`, and `buildNumberReuse` over the build numbers of both
/// stores.
List<GuardCheck> storeGuardChecks({
  required AppleStores apple,
  required PlayStores play,
}) => [
  ...apple.guardChecks,
  ...play.guardChecks,
  BuildNumberReuseCheck(
    CombinedStoreBuildNumbers(
      apple: apple.buildNumbers,
      play: play.buildNumbers,
    ),
  ),
];
