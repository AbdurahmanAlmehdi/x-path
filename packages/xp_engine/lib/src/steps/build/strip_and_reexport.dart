import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/artifacts/artifact_summary.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/build/build_directories.dart';
import 'package:xp_engine/src/steps/build/build_files.dart';
import 'package:xp_engine/src/steps/build/build_outputs.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';

/// The archive `flutter build ipa` leaves, relative to the app.
const iosArchivePath = 'build/ios/archive/Runner.xcarchive';

/// The folder the IPA is exported to, relative to the app.
const iosIpaDirectory = 'build/ios/ipa';

/// Which frameworks to strip from an iOS archive, and how to export it again.
class StripAndReexportInput extends Equatable {
  /// Creates the input.
  const new({
    required this.settings,
    required this.exportOptionsPlist,
    required this.frameworks,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or a framework name is not a plain name.
  factory fromJson(Map<String, dynamic> json) {
    final frameworks = stringList(json, 'frameworks');
    if (frameworks.isEmpty) {
      throw const FormatException('"frameworks" must name at least one.');
    }
    for (final name in frameworks) {
      if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(name) ||
          name.startsWith('.')) {
        throw FormatException('"$name" is not a framework name.');
      }
    }
    return StripAndReexportInput(
      settings: BuildSettings.fromJson(json),
      exportOptionsPlist: requiredRelative(json, 'exportOptionsPlist'),
      frameworks: frameworks,
    );
  }

  /// The build that made the archive; its IPA is the artifact that is
  /// replaced.
  final BuildSettings settings;

  /// The export options (`-exportOptionsPlist`), relative to the app.
  final String exportOptionsPlist;

  /// The names of the frameworks to remove, without `.framework`
  /// (`AgoraAudioBeautyExtension`).
  final List<String> frameworks;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    ...settings.toJson(),
    'exportOptionsPlist': exportOptionsPlist,
    'frameworks': frameworks,
  };

  @override
  List<Object?> get props => [settings, exportOptionsPlist, frameworks];
}

/// What `ios.stripAndReexport` did.
class StripAndReexportResult extends Equatable {
  /// Creates the result.
  const new({
    required this.removed,
    required this.freedBytes,
    required this.artifact,
  });

  /// The frameworks that were removed.
  final List<String> removed;

  /// How many bytes they held.
  final int freedBytes;

  /// The new IPA in the artifact store.
  final ArtifactSummary artifact;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'removed': removed,
    'freedBytes': freedBytes,
    'artifact': artifact.toJson(),
  };

  @override
  List<Object?> get props => [removed, freedBytes, artifact];
}

/// Removes frameworks that an app does not use from its iOS archive and
/// exports the IPA again (`ios.stripAndReexport`, L:585-629).
///
/// An app can vendor dozens of weak-linked extension frameworks (Agora) and
/// use a handful. They cannot be removed inside the Xcode build, because Xcode
/// signs the bundle after every script phase. So the archive is stripped and
/// `xcodebuild -exportArchive` signs the smaller bundle, which keeps signing
/// with Xcode. The new IPA replaces the one `build.ios` stored.
class StripAndReexportStep
    extends Step<StripAndReexportInput, StripAndReexportResult> {
  /// Creates the step. [isMacOS] tells whether this machine runs macOS.
  const new({
    required this.directories,
    required this.files,
    required this.recorder,
    required this.isMacOS,
  });

  /// Looks at and removes the frameworks.
  final BuildDirectories directories;

  /// The export folder on disk.
  final BuildFiles files;

  /// Stores the new IPA.
  final ArtifactRecorder recorder;

  /// Whether this machine runs macOS.
  final bool isMacOS;

  @override
  String get kind => 'ios.stripAndReexport';

  @override
  bool sideEffectOf(StripAndReexportInput input) => false;

  @override
  StripAndReexportInput decodeInput(Map<String, dynamic> json) =>
      StripAndReexportInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(StripAndReexportInput input) =>
      input.toJson();

  @override
  Map<String, dynamic> encodeResult(StripAndReexportResult result) =>
      result.toJson();

  @override
  Future<StepOutcome<StripAndReexportResult>> run(
    StripAndReexportInput input,
    StepContext context,
  ) async {
    if (!isMacOS) {
      return const StepFailed(
        'ios.stripAndReexport needs macOS: this machine cannot run Xcode. '
        'Run the job on a Mac.',
      );
    }
    final app = input.settings.appDirectory;
    final archive = '$app/$iosArchivePath';
    final bundle = '$archive/Products/Applications/Runner.app';
    if (!await directories.exists(bundle)) {
      return StepSkipped('No .app inside $archive; nothing to strip.');
    }

    final removed = <String>[];
    var freed = 0;
    for (final name in input.frameworks) {
      final path = '$bundle/Frameworks/$name.framework';
      if (!await directories.exists(path)) continue;
      freed += await directories.remove(path);
      removed.add(name);
    }
    if (removed.isEmpty) {
      return const StepSkipped('None of the frameworks is in the archive.');
    }

    // The signature of the archive no longer covers what is on disk, so the
    // export signs again. Clearing the old IPA keeps the new one unambiguous.
    final ipaDirectory = '$app/$iosIpaDirectory';
    await files.deleteAll(ipaDirectory, extension: '.ipa');
    final since = await files.markBuildStart();
    final exit = await context.run(
      ProcessCommand(
        'xcodebuild',
        arguments: [
          '-exportArchive',
          '-archivePath',
          archive,
          '-exportOptionsPlist',
          '$app/${input.exportOptionsPlist}',
          '-exportPath',
          ipaDirectory,
          '-allowProvisioningUpdates',
          '-quiet',
        ],
        workingDirectory: app,
        environment: const {'CI': 'true'},
        passThroughEnvironment: const ['DEVELOPER_DIR'],
      ),
    );
    if (exit.cancelled) {
      return const StepFailed('The export was cancelled.');
    }
    if (!exit.succeeded) {
      return StepFailed(
        'Re-export after the strip failed (xcodebuild exited with code '
        '${exit.exitCode}). The unstripped archive is still at $archive if '
        'you need to export it by hand.',
      );
    }

    final BuildFile file;
    switch (await BuildOutputs(files).ios(app, since: since)) {
      case Fresh(file: final fresh):
        file = fresh;
      case Stale(file: final leftover):
        return StepFailed(
          '${leftover.path} is older than this export, so it is not taken.',
        );
      case Missing():
        return const StepFailed('xcodebuild succeeded but exported no .ipa.');
    }
    final record = await recorder.record(
      jobId: context.jobId,
      kind: ArtifactKind.ipa,
      name: '${input.settings.label}.ipa',
      content: files.open(file.path),
    );
    return StepSucceeded(
      StripAndReexportResult(
        removed: removed,
        freedBytes: freed,
        artifact: ArtifactSummary.of(record),
      ),
    );
  }
}
