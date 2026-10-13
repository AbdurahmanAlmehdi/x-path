import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

export 'package:xp_engine/src/versioning/release_worktree.dart';

/// What a `guard` step checks, and about what.
class GuardInput extends Equatable {
  /// Creates the input.
  const new({
    required this.checks,
    required this.worktree,
    this.releaseVersion,
    this.iosBundleId,
    this.androidAppId,
    this.shorebirdAppId,
    this.storeCountry = 'us',
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if `checks` names a check that does not
  /// exist, or a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final names = stringList(json, 'checks');
    return GuardInput(
      checks: [
        for (final name in names)
          GuardCheckName.values.asNameMap()[name] ??
              (throw FormatException('"$name" is not a guard check.')),
      ],
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      releaseVersion: optionalString(json, 'releaseVersion'),
      iosBundleId: optionalString(json, 'iosBundleId'),
      androidAppId: optionalString(json, 'androidAppId'),
      shorebirdAppId: optionalString(json, 'shorebirdAppId'),
      storeCountry: optionalString(json, 'storeCountry') ?? 'us',
    );
  }

  /// The checks to run, in order.
  final List<GuardCheckName> checks;

  /// The worktree of the job and the app in it.
  final ReleaseWorktree worktree;

  /// For a patch, the release it patches as the owner wrote it:
  /// `x.y.z+build`. `patchTarget` rejects `latest` and anything else that is
  /// not exact.
  final String? releaseVersion;

  /// The iOS bundle id of the flavor.
  final String? iosBundleId;

  /// The Android application id of the flavor.
  final String? androidAppId;

  /// The Shorebird app id of the flavor.
  final String? shorebirdAppId;

  /// The App Store storefront.
  final String storeCountry;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'checks': [for (final check in checks) check.name],
    'worktree': worktree.toJson(),
    if (releaseVersion != null) 'releaseVersion': releaseVersion,
    if (iosBundleId != null) 'iosBundleId': iosBundleId,
    if (androidAppId != null) 'androidAppId': androidAppId,
    if (shorebirdAppId != null) 'shorebirdAppId': shorebirdAppId,
    'storeCountry': storeCountry,
  };

  @override
  List<Object?> get props => [
    checks,
    worktree,
    releaseVersion,
    iosBundleId,
    androidAppId,
    shorebirdAppId,
    storeCountry,
  ];
}

/// What a `guard` step found: one result per check, in the order asked.
class GuardReport extends Equatable {
  /// Creates a report.
  const new(this.results);

  /// The results.
  final List<GuardCheckResult> results;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'results': [for (final result in results) result.toJson()],
  };

  @override
  List<Object?> get props => [results];
}
