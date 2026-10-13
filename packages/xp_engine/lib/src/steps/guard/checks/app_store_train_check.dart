import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/steps/guard/guard_ports.dart';

/// App Store Connect rejects every build for a version whose train is closed
/// (ITMS-90186), but only after a full build and upload. This asks first
/// (`check_app_store_train`, R:168-188; D-22).
class AppStoreTrainCheck extends GuardCheck {
  /// Creates the check over [_trains].
  const new(this._trains);

  final AppStoreTrains _trains;

  @override
  GuardCheckName get name => GuardCheckName.appStoreTrain;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final bundleId = request.input.iosBundleId;
    if (bundleId == null) {
      return skipped('The flavor has no iOS bundle id.');
    }
    final version = (await request.versions()).pubspec.name;
    final status = await _trains.status(
      bundleId: bundleId,
      country: request.input.storeCountry,
    );
    if (status == null) {
      return warned(
        'Could not read the App Store state of $bundleId; the closed-train '
        'check is skipped.',
      );
    }
    final live = status.liveVersion;
    if (live != null && !(version > live)) {
      return failed(
        'The App Store already has $live live. Version $version is not '
        'higher, so App Store Connect would reject the upload (closed train, '
        'error 90186).',
        fix: 'Bump to a version higher than $live.',
      );
    }
    if (status.closedVersions.contains(version)) {
      return failed(
        'App Store Connect has already approved version $version, so its '
        'train is closed to new builds (error 90186).',
        fix: 'Bump to a version that has not been approved.',
      );
    }
    return passed(
      live == null
          ? 'The App Store has no live version; $version can be submitted.'
          : 'The App Store has $live live; $version is higher.',
    );
  }
}
