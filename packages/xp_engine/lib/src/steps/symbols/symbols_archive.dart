import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/artifacts/artifact_summary.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/build/build_directories.dart';
import 'package:xp_engine/src/steps/build/build_files.dart';
import 'package:xp_engine/src/steps/build/build_outputs.dart';
import 'package:xp_engine/src/steps/build/build_settings.dart';
import 'package:xp_engine/src/steps/build/stored_artifacts.dart';
import 'package:xp_engine/src/steps/build/strip_and_reexport.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';

/// Which symbols of a build to keep.
class SymbolsArchiveInput extends Equatable {
  /// Creates the input.
  const new({
    required this.settings,
    this.android = false,
    this.ios = false,
    this.debugInfoDirectory,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or `debugInfoDirectory` leaves the app.
  factory fromJson(Map<String, dynamic> json) => SymbolsArchiveInput(
    settings: BuildSettings.fromJson(json),
    android: optionalFlag(json, 'android'),
    ios: optionalFlag(json, 'ios'),
    debugInfoDirectory: json['debugInfoDirectory'] == null
        ? null
        : requiredRelative(json, 'debugInfoDirectory'),
  );

  /// The build the symbols belong to.
  final BuildSettings settings;

  /// Whether to keep the R8 mapping of the Android release build.
  final bool android;

  /// Whether to keep the dSYMs of the iOS archive.
  final bool ios;

  /// Where an obfuscated build left its debug info, relative to the app: the
  /// `debugInfoDirectory` of the build result. `null` if it was not
  /// obfuscated.
  final String? debugInfoDirectory;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    ...settings.toJson(),
    'android': android,
    'ios': ios,
    'debugInfoDirectory': ?debugInfoDirectory,
  };

  @override
  List<Object?> get props => [settings, android, ios, debugInfoDirectory];
}

/// What `symbols.archive` kept.
class SymbolsArchiveResult extends Equatable {
  /// Creates the result.
  const new({required this.artifacts, this.warnings = const []});

  /// The symbols in the artifact store.
  final List<ArtifactSummary> artifacts;

  /// What was asked for and was not there. A missing mapping does not stop a
  /// release (C:467-553); it makes a later patch hard to build.
  final List<String> warnings;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'artifacts': [for (final artifact in artifacts) artifact.toJson()],
    'warnings': warnings,
  };

  @override
  List<Object?> get props => [artifacts, warnings];
}

/// One thing to keep.
class _Symbol {
  const new({
    required this.kind,
    required this.name,
    required this.paths,
    required this.isFolder,
    required this.missing,
  });

  final ArtifactKind kind;
  final String name;

  /// Where it may be, the first that is there taken.
  final List<String> paths;

  /// Whether it is a folder, which is zipped.
  final bool isFolder;

  /// What to warn about when it is not there.
  final String missing;
}

/// Keeps the symbols a release needs to read its crashes and to build its
/// patches (`symbols.archive`, C:467-553, C:721-735, D-22).
///
/// - the R8 `mapping.txt` of the release build, as an artifact of kind
///   `mapping`. R8 renames classes differently on every run, so an Android
///   patch can only be built by applying the mapping of its release;
/// - the dSYMs of the iOS archive, zipped, as `dsym`, or those a Linux build
///   left in `build/ios-linux/dSYMs` (ADR 0014);
/// - the debug info of an obfuscated build, zipped, as `shorebird_symbols`
///   (the kind list has no other for it).
///
/// Each file is stored with its SHA-256. A symbol that is not there is a
/// warning, not a failure. Running the step again replaces the artifacts;
/// `alreadyDone` holds when everything that can be found was stored and still
/// has its recorded SHA-256.
class SymbolsArchiveStep
    extends Step<SymbolsArchiveInput, SymbolsArchiveResult> {
  /// Creates the step.
  const new({
    required this.directories,
    required this.files,
    required this.recorder,
    required this.repository,
    required this.store,
  });

  /// Looks at and zips the symbol folders.
  final BuildDirectories directories;

  /// The build output on disk.
  final BuildFiles files;

  /// Stores the symbols.
  final ArtifactRecorder recorder;

  /// The records of the stored artifacts.
  final ArtifactRepository repository;

  /// The artifact store, to check a file that was stored before.
  final ArtifactStore store;

  @override
  String get kind => 'symbols.archive';

  @override
  bool sideEffectOf(SymbolsArchiveInput input) => false;

  @override
  SymbolsArchiveInput decodeInput(Map<String, dynamic> json) =>
      SymbolsArchiveInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(SymbolsArchiveInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(SymbolsArchiveResult result) =>
      result.toJson();

  List<_Symbol> _wanted(SymbolsArchiveInput input) {
    final settings = input.settings;
    final app = settings.appDirectory;
    final label = settings.label;
    final variant = settings.flavor == null
        ? 'release'
        : '${settings.flavor}Release';
    final debugInfo = input.debugInfoDirectory;
    return [
      if (input.android)
        _Symbol(
          kind: ArtifactKind.mapping,
          name: '$label.mapping.txt',
          paths: ['$app/build/app/outputs/mapping/$variant/mapping.txt'],
          isFolder: false,
          missing:
              'No R8 mapping at build/app/outputs/mapping/$variant/mapping.txt; '
              'nothing archived. Future Android patches for '
              '${settings.version} may be unbuildable.',
        ),
      if (input.ios)
        _Symbol(
          kind: ArtifactKind.dsym,
          name: '$label.dSYMs.zip',
          paths: ['$app/$iosArchivePath/dSYMs', '$app/$iosLinuxDsymsPath'],
          isFolder: true,
          missing:
              'No dSYMs in $iosArchivePath/dSYMs or $iosLinuxDsymsPath; '
              'crashes of ${settings.version} cannot be symbolicated.',
        ),
      if (debugInfo != null)
        _Symbol(
          kind: ArtifactKind.shorebirdSymbols,
          name: '$label.debug-info.zip',
          paths: ['$app/$debugInfo'],
          isFolder: true,
          missing:
              'No debug info in $debugInfo; crashes of ${settings.version} '
              'cannot be symbolicated.',
        ),
    ];
  }

  /// Where [symbol] is, or `null` if it is not there.
  Future<String?> _find(_Symbol symbol) async {
    for (final path in symbol.paths) {
      if (symbol.isFolder
          ? await directories.exists(path)
          : await files.stat(path) != null) {
        return path;
      }
    }
    return null;
  }

  @override
  Future<SymbolsArchiveResult?> alreadyDone(
    SymbolsArchiveInput input,
    StepContext context,
  ) async {
    final stored = <ArtifactSummary>[];
    for (final symbol in _wanted(input)) {
      final record = await intactArtifact(
        repository: repository,
        store: store,
        jobId: context.jobId,
        name: symbol.name,
        kind: symbol.kind,
      );
      if (record != null) {
        stored.add(ArtifactSummary.of(record));
      } else if (await _find(symbol) != null) {
        return null;
      }
    }
    return stored.isEmpty ? null : SymbolsArchiveResult(artifacts: stored);
  }

  @override
  Future<StepOutcome<SymbolsArchiveResult>> run(
    SymbolsArchiveInput input,
    StepContext context,
  ) async {
    final wanted = _wanted(input);
    if (wanted.isEmpty) {
      return const StepSkipped('There are no symbols to keep.');
    }
    final stored = <ArtifactSummary>[];
    final warnings = <String>[];
    for (final symbol in wanted) {
      final path = await _find(symbol);
      if (path == null) {
        warnings.add(symbol.missing);
        continue;
      }
      final record = await recorder.record(
        jobId: context.jobId,
        kind: symbol.kind,
        name: symbol.name,
        content: symbol.isFolder ? directories.zip(path) : files.open(path),
      );
      stored.add(ArtifactSummary.of(record));
    }
    return StepSucceeded(
      SymbolsArchiveResult(artifacts: stored, warnings: warnings),
    );
  }
}
