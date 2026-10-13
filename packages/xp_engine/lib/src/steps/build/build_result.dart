import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/artifacts/artifact_summary.dart';

/// What `build.android` and `build.ios` produced.
class BuildResult extends Equatable {
  /// Creates the result.
  const new({
    required this.artifact,
    this.flutter,
    this.dart,
    this.debugInfoDirectory,
  });

  /// The file the build produced, in the artifact store.
  final ArtifactSummary artifact;

  /// The Flutter version it was built with.
  final String? flutter;

  /// The Dart version of that Flutter.
  final String? dart;

  /// Where an obfuscated build left its debug info, relative to the app; the
  /// symbols step archives it. `null` if the build was not obfuscated.
  final String? debugInfoDirectory;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'artifact': artifact.toJson(),
    'flutter': ?flutter,
    'dart': ?dart,
    'debugInfoDirectory': ?debugInfoDirectory,
  };

  @override
  List<Object?> get props => [artifact, flutter, dart, debugInfoDirectory];
}
