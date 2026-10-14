import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/update/runner_versions.dart';
import 'package:xp/src/runner/update/update_journal.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart' hide ArtifactDownload;

/// Fetches the bundle the engine offers a runner of [os] and [arch]:
/// `XpClient.downloadRunnerBundle`.
typedef BundleFetcher = Future<ArtifactDownload> Function({
  required String os,
  required String arch,
});

/// What an update came to.
sealed class UpdateOutcome {
  const new();
}

/// The runner switched to [version]; it has to start again as it.
final class Updated extends UpdateOutcome {
  /// Creates the outcome.
  const new(this.version);

  /// The version now in `current`.
  final String version;
}

/// The update to [version] did not happen; nothing was switched.
final class UpdateFailed extends UpdateOutcome {
  /// Creates the outcome.
  const new(this.version, this.message);

  /// The version the runner tried.
  final String version;

  /// Why, with what to do about it.
  final String message;
}

class _Failure implements Exception {
  const new(this.message);

  final String message;
}

/// Updates the runner to the version of its engine (D-24).
///
/// The agent decides when: it asks [wantsUpdateTo] at every welcome, finishes
/// the jobs it holds (it never updates in the middle of one) and ends; then
/// [update] runs, with no connection and no job open:
///
/// 1. **Download** the bundle of the engine's own version for this machine
///    (`GET /runners/bundle`) and check the size and SHA-256 the engine said.
/// 2. **Unpack** it with `tar` beside the versions that are installed, and
///    check it has `bin/xp`.
/// 3. **Try** it: `bin/xp --version` has to print the version the engine runs.
///    A bundle that cannot start (the wrong architecture, a missing library)
///    is found out here, while the old version still runs.
/// 4. **Install** it as `versions/<version>` and **switch** `current` to it in
///    one step. The version before stays.
///
/// Nothing before the last step changes what runs, so a failure at any of
/// them leaves the runner as it was. The caller starts the new version
/// afterwards (`Restarter`).
///
/// **Rollback.** [checkStart] runs first thing in every start: the new version
/// is counted until the engine welcomed it ([connected]); after
/// [maxUnconfirmedStarts] starts that never got welcomed it switches `current`
/// back, remembers the version as bad (it is not tried again) and asks for a
/// restart.
class RunnerUpdater {
  /// Creates the updater of a runner that runs [version] on [os] and [arch].
  ///
  /// [bundle] is the folder of the bundle that runs now (`.../bin/xp` is in
  /// it), or `null` when the runner is not started from a bundle.
  new({
    required this.paths,
    required this.version,
    required this.os,
    required this.arch,
    required this.runner,
    required this.fetch,
    required this.log,
    this.bundle,
  }) : journal = UpdateJournal(paths.updateState),
       versions = RunnerVersions(paths);

  /// The data directory of the runner.
  final RunnerPaths paths;

  /// The version that runs.
  final String version;

  /// The operating system of this machine, as the hello says it.
  final String os;

  /// The architecture of this machine, as the hello says it.
  final String arch;

  /// Starts `tar` and the new `xp`.
  final ProcessRunner runner;

  /// Downloads the bundle.
  final BundleFetcher fetch;

  /// Says something to the owner.
  final void Function(String message) log;

  /// The bundle that runs now, if it is one.
  final String? bundle;

  /// The record of the update in progress.
  final UpdateJournal journal;

  /// The installed versions.
  final RunnerVersions versions;

  final _declined = <String>{};

  /// Whether the runner should update to the engine's [engineVersion]: it
  /// differs from the runner's, it is a version this runner can install, and
  /// the runner did not fail with it already.
  bool wantsUpdateTo(String engineVersion) {
    if (engineVersion == version || _declined.contains(engineVersion)) {
      return false;
    }
    if (!isVersionName(engineVersion)) {
      _decline(engineVersion, 'it is not a version name');
      return false;
    }
    if (journal.blocked == engineVersion) {
      _decline(
        engineVersion,
        'it did not start on this machine and the runner went back',
      );
      return false;
    }
    return true;
  }

  void _decline(String engineVersion, String reason) {
    if (_declined.add(engineVersion)) {
      log(
        "Not updating to the engine's version $engineVersion: $reason. "
        'This runner stays on $version.',
      );
    }
  }

  /// Stops [wantsUpdateTo] from asking for [target] again: the update to it
  /// failed.
  void giveUp(String target) => _declined.add(target);

  /// Called first thing when the runner starts. Returns the version it
  /// switched back to, when the version that runs did not reach the engine
  /// after [maxUnconfirmedStarts] starts; the caller starts again.
  String? checkStart() {
    switch (journal.noteStart(version)) {
      case ProceedStart():
        return null;
      case RollBack(version: final previous, :final failed):
        if (!versions.has(previous)) {
          log(
            'Version $failed did not reach the engine in '
            '$maxUnconfirmedStarts starts, but the version before it '
            '($previous) is not installed any more: staying on $failed.',
          );
          journal.abandon();
          return null;
        }
        versions.switchTo(previous);
        journal.rolledBack(failed);
        log(
          'Version $failed did not reach the engine in '
          '$maxUnconfirmedStarts starts: going back to $previous. The runner '
          'does not update to $failed again.',
        );
        return previous;
    }
  }

  /// The engine welcomed the runner: an update that was waiting for this has
  /// proven itself, and only it and the version before it stay installed.
  void connected(String engineVersion) {
    final previous = journal.confirm(version);
    if (previous == null) return;
    versions.prune({version, previous});
    log('Updated from $previous to $version.');
  }

  /// Downloads, unpacks, tries and switches to the bundle of [target].
  Future<UpdateOutcome> update(String target) async {
    final work = Directory(paths.updates);
    try {
      if (!isVersionName(target)) {
        throw _Failure('"$target" is not a version name.');
      }
      await _update(target, work);
      log('Switched to version $target.');
      return Updated(target);
    } on _Failure catch (error) {
      return _failed(target, error.message);
    } on XpClientException catch (error) {
      return _failed(target, error.message);
    } on FileSystemException catch (error) {
      return _failed(target, '${error.message} ${error.path ?? ''}'.trim());
    } on ProcessStartException catch (error) {
      return _failed(target, error.message);
    } on TimeoutException {
      return _failed(target, 'A program did not finish in time.');
    } finally {
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  }

  UpdateOutcome _failed(String target, String reason) {
    giveUp(target);
    final message =
        'Cannot update to version $target: $reason The runner stays on '
        '$version and does not try again until it restarts.';
    log(message);
    return UpdateFailed(target, message);
  }

  Future<void> _update(String target, Directory work) async {
    if (work.existsSync()) work.deleteSync(recursive: true);
    work.createSync(recursive: true);
    log('Updating from $version to $target.');

    final download = await fetch(os: os, arch: arch);
    if (download.sha256 == null || download.length == null) {
      throw const _Failure(
        'The engine did not say the SHA-256 and the size of the bundle.',
      );
    }
    final archive = File(p.join(work.path, 'xp.tar.gz'));
    await download.saveTo(archive);

    final unpacked = p.join(work.path, 'bundle');
    Directory(unpacked).createSync();
    final tar = await runner.run('tar', [
      '-xzf',
      archive.path,
      '-C',
      unpacked,
    ], timeout: const Duration(minutes: 10));
    if (tar.exitCode != 0) {
      throw _Failure('The bundle does not unpack: ${tar.stderr.trim()}');
    }
    final executable = File(p.join(unpacked, 'bin', 'xp'));
    if (!executable.existsSync()) {
      throw const _Failure('The bundle has no bin/xp.');
    }
    if (executable.statSync().mode & 0x49 == 0) {
      throw const _Failure('bin/xp of the bundle is not executable.');
    }
    final tried = await runner.run(executable.path, [
      '--version',
    ], timeout: const Duration(seconds: 30));
    final said = tried.stdout.trim();
    if (tried.exitCode != 0 || said != target) {
      throw _Failure(
        tried.exitCode != 0
            ? 'The new xp does not start (exit ${tried.exitCode}): '
                  '${tried.stderr.trim()}'
            : 'The bundle is xp $said, not $target.',
      );
    }

    // From here on the old version has to stay possible to go back to.
    final from = versions.currentVersion() ?? version;
    final running = bundle;
    if (running != null && !versions.has(from) && from == version) {
      await versions.adopt(bundle: running, version: from, runner: runner);
    }
    versions.install(unpacked, target);
    journal.begin(from: from, to: target);
    try {
      versions.switchTo(target);
    } on FileSystemException {
      journal.abandon();
      rethrow;
    }
  }
}
