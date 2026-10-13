import 'package:xp_engine/xp_engine.dart';

/// The target API level Google Play asks of new apps and updates since
/// 2026-08-31: Android 16 (API 36), for phones, tablets and foldables
/// (developer.android.com/google/play/requirements/target-sdk, verified
/// 2026-10-13). Play raises it every August.
const defaultPlayTargetSdk = 36;

/// The target API level Play asks for, as configured.
///
/// Google publishes no API for the policy value, so it is a setting: the
/// owner raises it when Play does (`XPD_PLAY_TARGET_SDK` for `xpd serve`),
/// and the default is the level that applies today.
class ConfiguredPlayRequirements implements PlayRequirements {
  /// Creates the requirements with the level [targetSdk].
  const new([this.targetSdk = defaultPlayTargetSdk]);

  /// The lowest `targetSdk` Play accepts.
  final int targetSdk;

  @override
  Future<int?> requiredTargetSdk() async => targetSdk;
}
