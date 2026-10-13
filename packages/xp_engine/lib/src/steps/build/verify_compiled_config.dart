import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/build/bytes_finder.dart';
import 'package:xp_engine/src/steps/build/dart_defines.dart';
import 'package:xp_engine/src/steps/build/snapshot_reader.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';
import 'package:xp_engine/src/versioning/workspace.dart';

/// What the compiled app must contain.
class VerifyCompiledConfigInput extends Equatable {
  /// Creates the input. At least one of [keys] and [needles] is needed, and
  /// [keys] need the [dartDefineFile] they are read from.
  const new({
    required this.worktree,
    required this.artifactName,
    this.dartDefineFile,
    this.keys = const [],
    this.needles = const [],
  }) : assert(
         keys.length + needles.length > 0,
         'There must be something to look for.',
       ),
       assert(
         keys.length == 0 || dartDefineFile != null,
         'Keys are read from a define file.',
       );

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// there is nothing to look for, or keys come without a define file.
  factory fromJson(Map<String, dynamic> json) {
    final keys = stringList(json, 'keys');
    final needles = stringList(json, 'needles');
    final dartDefineFile = optionalString(json, 'dartDefineFile');
    if (keys.isEmpty && needles.isEmpty) {
      throw const FormatException('"keys" or "needles" must name something.');
    }
    if (needles.any((needle) => needle.isEmpty)) {
      throw const FormatException('"needles" must not hold an empty string.');
    }
    if (keys.isNotEmpty && dartDefineFile == null) {
      throw const FormatException('"keys" need a "dartDefineFile".');
    }
    return VerifyCompiledConfigInput(
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      artifactName: requiredString(json, 'artifactName'),
      dartDefineFile: dartDefineFile,
      keys: keys,
      needles: needles,
    );
  }

  /// The worktree the app was built in; the define file is read from it.
  final ReleaseWorktree worktree;

  /// The file name of the built package in the artifact store, such as
  /// `prod-1.2.3+45.aab`.
  final String artifactName;

  /// The `--dart-define-from-file` file of the build, relative to the app.
  final String? dartDefineFile;

  /// Keys of the define file whose values must be in the compiled app, such
  /// as `API_BASE_URL`. For a URL the host is looked for.
  final List<String> keys;

  /// Strings that must be in the compiled app as they are.
  final List<String> needles;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'artifactName': artifactName,
    'dartDefineFile': ?dartDefineFile,
    'keys': keys,
    'needles': needles,
  };

  @override
  List<Object?> get props => [
    worktree,
    artifactName,
    dartDefineFile,
    keys,
    needles,
  ];
}

/// What `build.verifyCompiledConfig` proved.
class VerifyCompiledConfigResult extends Equatable {
  /// Creates the result.
  const new({required this.artifactName, required this.found});

  /// The package that was checked.
  final String artifactName;

  /// The strings that were found in it.
  final List<String> found;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'artifactName': artifactName,
    'found': found,
  };

  @override
  List<Object?> get props => [artifactName, found];
}

/// Proves that the configuration of a build is compiled into the package
/// (`build.verifyCompiledConfig`, K:430-462).
///
/// Passing `--dart-define-from-file` is not evidence that the values arrived:
/// a vendor build reached TestFlight with an empty base URL because Xcode
/// reused a stale Dart kernel. A string constant appears verbatim in the AOT
/// snapshot, so the step looks for the expected values in `libapp.so` (APK,
/// AAB) or `App.framework/App` (IPA) and fails if one is missing. A package
/// without a snapshot is skipped, as K does.
class VerifyCompiledConfigStep
    extends Step<VerifyCompiledConfigInput, VerifyCompiledConfigResult> {
  /// Creates the step.
  const new({
    required this._workspaces,
    required this._repository,
    required this._store,
    required this._snapshots,
  });

  final WorkspaceOpener _workspaces;
  final ArtifactRepository _repository;
  final ArtifactStore _store;
  final SnapshotReader _snapshots;

  @override
  String get kind => 'build.verifyCompiledConfig';

  @override
  bool sideEffectOf(VerifyCompiledConfigInput input) => false;

  @override
  VerifyCompiledConfigInput decodeInput(Map<String, dynamic> json) =>
      VerifyCompiledConfigInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(VerifyCompiledConfigInput input) =>
      input.toJson();

  @override
  Map<String, dynamic> encodeResult(VerifyCompiledConfigResult result) =>
      result.toJson();

  @override
  Future<StepOutcome<VerifyCompiledConfigResult>> run(
    VerifyCompiledConfigInput input,
    StepContext context,
  ) async {
    final name = input.artifactName;
    final record = await _repository.findByPath(
      context.jobId,
      ArtifactRecorder.pathOf(context.jobId, name),
    );
    if (record == null || !await _store.exists(record.path)) {
      return StepFailed(
        'This job has no stored $name to check. Run the build that makes it '
        'first.',
      );
    }
    const packages = {ArtifactKind.apk, ArtifactKind.aab, ArtifactKind.ipa};
    if (!packages.contains(record.kind)) {
      return StepFailed('$name is not an APK, AAB or IPA.');
    }

    final String expectations;
    final List<String> needles;
    try {
      needles = await _needles(input);
    } on FormatException catch (error) {
      return StepFailed(error.message);
    }
    expectations = needles.join(', ');

    final snapshot = await _snapshots.snapshotOf(
      record.kind,
      _store.read(record.path),
    );
    if (snapshot == null) {
      return StepSkipped(
        'No AOT snapshot in $name, so the config check is skipped.',
      );
    }
    final finder = BytesFinder([
      for (final needle in needles) utf8.encode(needle),
    ]);
    await snapshot.forEach(finder.add);
    final missing = [for (final bytes in finder.missing) utf8.decode(bytes)];
    if (missing.isNotEmpty) {
      return StepFailed(
        '${missing.join(', ')} ${missing.length == 1 ? 'is' : 'are'} NOT '
        'compiled into $name (looked for $expectations). The build dropped '
        'its --dart-define values and every request would fail, so the '
        'package is not shipped. Fix: run flutter clean in the app and build '
        'again; for a Shorebird release bump the build number first, because '
        'Shorebird has registered this version.',
      );
    }
    return StepSucceeded(
      VerifyCompiledConfigResult(artifactName: name, found: needles),
    );
  }

  /// The strings to look for: the literal ones and the values of `keys`.
  ///
  /// Throws a [FormatException] with the reason the define file cannot give
  /// them.
  Future<List<String>> _needles(VerifyCompiledConfigInput input) async {
    final needles = [...input.needles];
    final file = input.dartDefineFile;
    if (file != null && input.keys.isNotEmpty) {
      final path = input.worktree.inApp(file);
      final text = await _workspaces(input.worktree.path).read(path);
      if (text == null) throw FormatException('$path does not exist.');
      final defines = parseDartDefines(text);
      for (final key in input.keys) {
        final value = defines[key] ?? '';
        final needle = compiledNeedle(value);
        if (needle.isEmpty) {
          throw FormatException('$path has no value for $key.');
        }
        needles.add(needle);
      }
    }
    return needles;
  }
}
