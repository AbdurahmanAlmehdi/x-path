import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_summary.dart';
import 'package:xp_engine/src/artifacts/digest.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';
import 'package:xp_engine/src/versioning/workspace.dart';

/// The file name of the manifest in the artifact store.
const manifestFileName = 'manifest.json';

/// What the manifest describes.
class RecordManifestInput extends Equatable {
  /// Creates the input.
  const new({
    required this.worktree,
    required this.version,
    this.flavors = const [],
    this.dartDefineFile,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or `version` is not `x.y.z+build`.
  factory fromJson(Map<String, dynamic> json) {
    final version = AppVersion.parse(requiredString(json, 'version'));
    if (version.build == null) {
      throw const FormatException('"version" needs a build number.');
    }
    final dartDefineFile = optionalString(json, 'dartDefineFile');
    return RecordManifestInput(
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      version: version,
      flavors: stringList(json, 'flavors'),
      dartDefineFile: dartDefineFile,
    );
  }

  /// The worktree the job built in. Its head is the commit that was built.
  final ReleaseWorktree worktree;

  /// The version that was built.
  final AppVersion version;

  /// The flavors that were built.
  final List<String> flavors;

  /// The `--dart-define-from-file` file of the builds, relative to the app;
  /// the manifest records its SHA-256.
  final String? dartDefineFile;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'version': '$version',
    'flavors': flavors,
    'dartDefineFile': ?dartDefineFile,
  };

  @override
  List<Object?> get props => [worktree, version, flavors, dartDefineFile];
}

/// What `record.manifest` stored.
class RecordManifestResult extends Equatable {
  /// Creates the result.
  const new(this.artifact);

  /// The manifest in the artifact store.
  final ArtifactSummary artifact;

  @override
  List<Object?> get props => [artifact];
}

/// Writes `manifest.json`, which says exactly what a job built, and stores it
/// as an artifact of kind `manifest` (`record.manifest`, R:234-305).
///
/// It names the version, the build and the tag, the commit that was built and
/// whether the worktree was dirty, the tool versions the job ran with, the
/// SHA-256 of `pubspec.lock` and of the `--dart-define-from-file` file, and
/// every artifact of the job with its SHA-256. Running it again replaces the
/// manifest.
class RecordManifestStep
    extends Step<RecordManifestInput, RecordManifestResult> {
  /// Creates the step.
  const new({
    required this._git,
    required this._workspaces,
    required this._artifacts,
    required this._recorder,
    required this._jobs,
    required this._clock,
  });

  final GitService _git;
  final WorkspaceOpener _workspaces;
  final ArtifactRepository _artifacts;
  final ArtifactRecorder _recorder;
  final JobRepository _jobs;
  final Clock _clock;

  @override
  String get kind => 'record.manifest';

  @override
  bool sideEffectOf(RecordManifestInput input) => false;

  @override
  RecordManifestInput decodeInput(Map<String, dynamic> json) =>
      RecordManifestInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(RecordManifestInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(RecordManifestResult result) => {
    'artifact': result.artifact.toJson(),
  };

  @override
  Future<StepOutcome<RecordManifestResult>> run(
    RecordManifestInput input,
    StepContext context,
  ) async {
    final worktree = input.worktree;
    final status = await _git.status(worktree.gitWorktree);
    final workspace = _workspaces(worktree.path);
    final job = await _jobs.get(context.jobId);
    final tools = await _jobs.tools(context.jobId);
    final lock = await workspace.read(worktree.inApp('pubspec.lock'));
    final defines = input.dartDefineFile;
    final defineText = defines == null
        ? null
        : await workspace.read(worktree.inApp(defines));
    final built = [
      for (final artifact in await _artifacts.forJob(context.jobId))
        if (artifact.kind != ArtifactKind.manifest) artifact,
    ];

    final manifest = <String, Object?>{
      'schema': 1,
      'jobId': context.jobId,
      'app': worktree.appPath,
      'version': '${input.version.name}',
      'build': input.version.build,
      'tag': worktree.releaseModel.tagName(
        input.version.name,
        input.version.build!,
        scope: worktree.scope,
      ),
      'flavors': input.flavors,
      'git': {
        'sha': status.headSha,
        'dispatchedSha': worktree.sha,
        'dirty': status.changed.isNotEmpty,
      },
      'deps': {'pubspecLockSha256': lock == null ? null : _sha(lock)},
      'toolchain': tools?.toJson() ?? const <String, dynamic>{},
      'inputs': {
        'dartDefineFile': ?defines,
        if (defineText != null) 'dartDefineFileSha256': _sha(defineText),
      },
      'artifacts': [
        for (final artifact in built)
          {
            'kind': artifact.kind.wire,
            'file': artifact.name,
            'bytes': artifact.size,
            'sha256': artifact.sha256,
          },
      ],
      'startedAt': job?.startedAt?.toIso8601String(),
      'finishedAt': _clock.now().toIso8601String(),
    };

    final record = await _recorder.record(
      jobId: context.jobId,
      kind: ArtifactKind.manifest,
      name: manifestFileName,
      content: Stream.value(
        utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        ),
      ),
    );
    return StepSucceeded(RecordManifestResult(ArtifactSummary.of(record)));
  }

  static String _sha(String text) => sha256OfBytes(utf8.encode(text));
}
