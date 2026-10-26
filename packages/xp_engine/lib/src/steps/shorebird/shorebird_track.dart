import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// Shorebird could not move a patch; [message] says why, with no secret in
/// it.
class ShorebirdPatchesException implements Exception {
  /// Creates the exception.
  const new(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'ShorebirdPatchesException: $message';
}

/// Moves the patches of a Shorebird release between tracks.
///
/// `xp_adapters` implements it over `shorebird patches promote` and
/// `shorebird patches rollback`.
abstract interface class ShorebirdPatches {
  /// Does [action] to the patch [patchNumber] of the release
  /// [releaseVersion] (`x.y.z+build`) of the Shorebird app [appId].
  /// [tokenSecret] is the key in the secret store of the Shorebird API key.
  ///
  /// Throws a [ShorebirdPatchesException] if Shorebird did not.
  Future<void> change({
    required String appId,
    required String releaseVersion,
    required int patchNumber,
    required PatchAction action,
    String? tokenSecret,
  });
}

/// A [ShorebirdPatches] that remembers what it was asked.
class FakeShorebirdPatches implements ShorebirdPatches {
  /// Every change as `action appId releaseVersion patchNumber`, oldest first.
  final changes = <String>[];

  /// The message to fail with, if set.
  String? failure;

  @override
  Future<void> change({
    required String appId,
    required String releaseVersion,
    required int patchNumber,
    required PatchAction action,
    String? tokenSecret,
  }) async {
    if (failure case final message?) throw ShorebirdPatchesException(message);
    changes.add('${action.wire} $appId $releaseVersion $patchNumber');
  }
}

/// Which patch of which release to move, and where.
class ShorebirdTrackInput extends Equatable {
  /// Creates the input.
  const new({
    required this.shorebirdAppId,
    required this.releaseVersion,
    required this.patchNumber,
    required this.action,
    this.tokenSecret,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final number = json['patchNumber'];
    if (number is! int || number < 1) {
      throw const FormatException('"patchNumber" must be a number from 1.');
    }
    final wire = requiredString(json, 'action');
    return ShorebirdTrackInput(
      shorebirdAppId: requiredString(json, 'shorebirdAppId'),
      releaseVersion: AppVersion.parse(requiredString(json, 'releaseVersion')),
      patchNumber: number,
      action:
          PatchAction.values.where((a) => a.wire == wire).firstOrNull ??
          (throw FormatException('"action" cannot be $wire.')),
      tokenSecret: optionalString(json, 'tokenSecret'),
    );
  }

  /// The Shorebird app of the flavor.
  final String shorebirdAppId;

  /// The release the patch belongs to, build number included.
  final AppVersion releaseVersion;

  /// The patch.
  final int patchNumber;

  /// Promote it to stable, or roll it back.
  final PatchAction action;

  /// The key in the secret store of the Shorebird API key.
  final String? tokenSecret;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'shorebirdAppId': shorebirdAppId,
    'releaseVersion': '$releaseVersion',
    'patchNumber': patchNumber,
    'action': action.wire,
    'tokenSecret': ?tokenSecret,
  };

  @override
  List<Object?> get props => [
    shorebirdAppId,
    releaseVersion,
    patchNumber,
    action,
    tokenSecret,
  ];
}

/// What `shorebird.track` did.
class ShorebirdTrackResult extends Equatable {
  /// Creates the result.
  const new({required this.patchNumber, required this.action});

  /// The patch moved.
  final int patchNumber;

  /// Where it went.
  final PatchAction action;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'patchNumber': patchNumber,
    'action': action.wire,
  };

  @override
  List<Object?> get props => [patchNumber, action];
}

/// Promotes a Shorebird patch to the stable track, or rolls it back
/// (`shorebird.track`, U7b).
///
/// The `shorebird-track` workflow puts `gate: prod_patch` in front of it:
/// every user of the release gets the change. It runs on the engine, which
/// holds the Shorebird API key. Shorebird answers success for a patch that is
/// where it is asked to go already, so the step is safe to run again.
class ShorebirdTrackStep
    extends Step<ShorebirdTrackInput, ShorebirdTrackResult> {
  /// Creates the step.
  const new(this._patches);

  final ShorebirdPatches _patches;

  @override
  String get kind => 'shorebird.track';

  @override
  bool sideEffectOf(ShorebirdTrackInput input) => true;

  @override
  ShorebirdTrackInput decodeInput(Map<String, dynamic> json) =>
      ShorebirdTrackInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(ShorebirdTrackInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(ShorebirdTrackResult result) =>
      result.toJson();

  @override
  Future<StepOutcome<ShorebirdTrackResult>> run(
    ShorebirdTrackInput input,
    StepContext context,
  ) async {
    try {
      await _patches.change(
        appId: input.shorebirdAppId,
        releaseVersion: '${input.releaseVersion}',
        patchNumber: input.patchNumber,
        action: input.action,
        tokenSecret: input.tokenSecret,
      );
    } on ShorebirdPatchesException catch (error) {
      return StepFailed('Shorebird: ${error.message}');
    }
    return StepSucceeded(
      ShorebirdTrackResult(
        patchNumber: input.patchNumber,
        action: input.action,
      ),
    );
  }
}
