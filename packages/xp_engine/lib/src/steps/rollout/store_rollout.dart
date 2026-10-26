import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/releases/release_record.dart';
import 'package:xp_engine/src/releases/release_repository.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/stores/apple/app_store_connect.dart';
import 'package:xp_engine/src/stores/apple/asc_credential_source.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';
import 'package:xp_engine/src/stores/apple/asc_models.dart';
import 'package:xp_engine/src/stores/play/google_play.dart';
import 'package:xp_engine/src/stores/play/play_credential_source.dart';
import 'package:xp_engine/src/stores/play/play_exceptions.dart';
import 'package:xp_engine/src/stores/play/play_models.dart';

/// Which rollout of which release to change.
class StoreRolloutInput extends Equatable {
  /// Creates the input.
  const new({required this.releaseId, required this.request});

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) => StoreRolloutInput(
    releaseId: requiredString(json, 'releaseId'),
    request: RolloutRequest.fromJson(json),
  );

  /// The release whose rollout changes.
  final String releaseId;

  /// The store and the change.
  final RolloutRequest request;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'releaseId': releaseId,
    ...request.toJson(),
  };

  @override
  List<Object?> get props => [releaseId, request];
}

/// Where the rollout stands after `store.rollout`.
class StoreRolloutResult extends Equatable {
  /// Creates the result.
  const new({
    required this.store,
    required this.state,
    this.userFraction,
    this.alreadyDone = false,
  });

  /// The store it changed.
  final ReleaseStore store;

  /// What the store says now: `PAUSED`, `ACTIVE`, `COMPLETE` for Apple;
  /// `inProgress`, `halted`, `completed` for Google Play.
  final String state;

  /// For Google Play, the share of users the release reaches.
  final double? userFraction;

  /// Whether the store was there before the step asked.
  final bool alreadyDone;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'store': store.wire,
    'state': state,
    'userFraction': ?userFraction,
    'alreadyDone': alreadyDone,
  };

  @override
  List<Object?> get props => [store, state, userFraction, alreadyDone];
}

/// Changes how a release reaches users in a store (`store.rollout`, U7a):
/// Apple's phased release (pause, resume, complete) and Google Play's staged
/// rollout of the production track (a new fraction, halt, complete).
///
/// A rollout change is a gated action (D-13): the `release-rollout` workflow
/// puts `gate: rollout` in front of this step, which runs only on the engine.
/// It reaches the stores with the credentials of the release's app, as the
/// status poller does.
///
/// The step has a side effect. `alreadyDone` reads the store: done when the
/// rollout is where the step would put it.
class StoreRolloutStep extends Step<StoreRolloutInput, StoreRolloutResult> {
  /// Creates the step.
  const new({
    required this.releases,
    required this.ascCredentials,
    required this.appStoreConnect,
    required this.playCredentials,
    required this.googlePlay,
  });

  /// Where the releases are.
  final ReleaseRepository releases;

  /// The App Store Connect key of a bundle id.
  final AscCredentialSource ascCredentials;

  /// Makes the App Store Connect client of a key.
  final AppStoreConnectFactory appStoreConnect;

  /// The Google Play service account of a package.
  final PlayCredentialSource playCredentials;

  /// Makes the Google Play client of a service account.
  final GooglePlayFactory googlePlay;

  @override
  String get kind => 'store.rollout';

  @override
  bool sideEffectOf(StoreRolloutInput input) => true;

  @override
  StoreRolloutInput decodeInput(Map<String, dynamic> json) =>
      StoreRolloutInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(StoreRolloutInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(StoreRolloutResult result) =>
      result.toJson();

  /// The phased-release state each Apple change leads to.
  static PhasedReleaseState _appleTarget(RolloutAction action) =>
      switch (action) {
        RolloutAction.pause => PhasedReleaseState.paused,
        RolloutAction.resume => PhasedReleaseState.active,
        _ => PhasedReleaseState.complete,
      };

  @override
  Future<StoreRolloutResult?> alreadyDone(
    StoreRolloutInput input,
    StepContext context,
  ) async {
    try {
      final found = await _find(input);
      if (found case _Apple(:final phased)) {
        return phased.state == _appleTarget(input.request.action)
            ? StoreRolloutResult(
                store: ReleaseStore.apple,
                state: phased.state.wire,
                alreadyDone: true,
              )
            : null;
      }
      if (found case _Play(
        :final client,
        :final packageName,
        :final track,
        :final build,
      )) {
        final release = await _playRelease(client, packageName, track, build);
        if (release == null) return null;
        final target = _playTarget(release, input.request);
        return release.status == target.status &&
                release.userFraction == target.userFraction
            ? StoreRolloutResult(
                store: ReleaseStore.play,
                state: release.status.wire,
                userFraction: release.userFraction,
                alreadyDone: true,
              )
            : null;
      }
      return null;
    } on Exception {
      // The store cannot be asked now: the step runs, and says why.
      return null;
    }
  }

  @override
  Future<StepOutcome<StoreRolloutResult>> run(
    StoreRolloutInput input,
    StepContext context,
  ) async {
    try {
      return switch (await _find(input)) {
        _Missing(:final reason) => StepFailed(reason),
        _Apple(:final client, :final phased) => await _apple(
          client,
          phased,
          input.request,
        ),
        final _Play play => await _play(play, input.request),
      };
    } on AppStoreConnectException catch (error) {
      return StepFailed('App Store Connect: ${error.message}');
    } on PlayException catch (error) {
      return StepFailed('Google Play: ${error.message}');
    }
  }

  Future<StepOutcome<StoreRolloutResult>> _apple(
    AppStoreConnect client,
    AscPhasedRelease phased,
    RolloutRequest request,
  ) async {
    final updated = await client.updatePhasedRelease(
      phased.id,
      _appleTarget(request.action),
    );
    return StepSucceeded(
      StoreRolloutResult(store: ReleaseStore.apple, state: updated.state.wire),
    );
  }

  Future<StepOutcome<StoreRolloutResult>> _play(
    _Play play,
    RolloutRequest request,
  ) async {
    final _Play(:client, :packageName, :track, :build) = play;
    final edit = await client.insertEdit(packageName);
    try {
      final current = await client.track(packageName, edit.id, track);
      final release = current.releases
          .where((release) => release.versionCodes.contains(build))
          .firstOrNull;
      if (release == null) {
        await client.deleteEdit(packageName, edit.id);
        return StepFailed(
          'The $track track of Google Play has no release with version code '
          '$build: there is no rollout to change.',
        );
      }
      final target = _playTarget(release, request);
      await client.updateTrack(
        packageName,
        edit.id,
        PlayTrack(
          name: track,
          releases: [
            for (final other in current.releases)
              if (identical(other, release)) target else other,
          ],
        ),
      );
      await client.commitEdit(packageName, edit.id);
      return StepSucceeded(
        StoreRolloutResult(
          store: ReleaseStore.play,
          state: target.status.wire,
          userFraction: target.userFraction,
        ),
      );
    } on PlayException {
      await client.deleteEdit(packageName, edit.id);
      rethrow;
    }
  }

  /// The release of the track as [request] leaves it.
  static PlayRelease _playTarget(PlayRelease release, RolloutRequest request) {
    final (status, fraction) = switch (request.action) {
      RolloutAction.halt => (PlayReleaseStatus.halted, release.userFraction),
      RolloutAction.fraction when request.userFraction! < 1 => (
        PlayReleaseStatus.inProgress,
        request.userFraction,
      ),
      _ => (PlayReleaseStatus.completed, null),
    };
    return PlayRelease(
      versionCodes: release.versionCodes,
      status: status,
      userFraction: fraction,
      name: release.name,
      releaseNotes: release.releaseNotes,
    );
  }

  Future<PlayRelease?> _playRelease(
    GooglePlay client,
    String packageName,
    String track,
    int build,
  ) async {
    final edit = await client.insertEdit(packageName);
    try {
      final current = await client.track(packageName, edit.id, track);
      return current.releases
          .where((release) => release.versionCodes.contains(build))
          .firstOrNull;
    } finally {
      await client.deleteEdit(packageName, edit.id);
    }
  }

  /// The store client and what in it the rollout is, or why there is none.
  Future<_Found> _find(StoreRolloutInput input) async {
    final release = await releases.get(input.releaseId);
    if (release == null) {
      return _Missing('There is no release ${input.releaseId}.');
    }
    final store = input.request.store;
    final entry = release.stores[store];
    if (entry == null) {
      return _Missing(
        'The release ${release.id} did not go to ${store.wire}: it has no '
        'rollout there.',
      );
    }
    return switch (store) {
      ReleaseStore.apple => await _findApple(release, entry),
      ReleaseStore.play => await _findPlay(entry, release.build),
    };
  }

  Future<_Found> _findApple(ReleaseRecord release, StoreEntry entry) async {
    final bundleId = entry.identity['bundleId']!;
    final key = await ascCredentials.forBundleId(bundleId);
    if (key == null) {
      return _Missing(
        'No App Store Connect API key reaches $bundleId: change the phased '
        'release in App Store Connect.',
      );
    }
    final client = appStoreConnect(key);
    final app = await client.findApp(bundleId);
    final version = app == null
        ? null
        : (await client.versions(app.id))
              .where((version) => version.versionString == release.version)
              .firstOrNull;
    if (version == null) {
      return _Missing(
        'App Store Connect has no version ${release.version} of $bundleId.',
      );
    }
    final phased = await client.phasedRelease(version.id);
    if (phased == null) {
      return _Missing(
        'Version ${release.version} has no phased release: it goes to every '
        'user at once.',
      );
    }
    return _Apple(client, phased);
  }

  Future<_Found> _findPlay(StoreEntry entry, int build) async {
    final packageName = entry.identity['packageName']!;
    final account = await playCredentials.forAndroidAppId(packageName);
    if (account == null) {
      return _Missing(
        'No Google Play service account reaches $packageName: change the '
        'rollout in the Play Console.',
      );
    }
    return _Play(
      googlePlay(account),
      packageName,
      entry.identity['track']!,
      build,
    );
  }
}

sealed class _Found {
  const new();
}

final class _Missing extends _Found {
  const new(this.reason);

  final String reason;
}

final class _Apple extends _Found {
  const new(this.client, this.phased);

  final AppStoreConnect client;
  final AscPhasedRelease phased;
}

final class _Play extends _Found {
  const new(this.client, this.packageName, this.track, this.build);

  final GooglePlay client;
  final String packageName;
  final String track;

  /// The version code of the release.
  final int build;
}
