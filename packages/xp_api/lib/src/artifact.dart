// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'artifact.g.dart';

/// What a stored file is.
@JsonEnum(valueField: 'wire')
enum ArtifactKind {
  /// An iOS app, ready for App Store Connect.
  ipa('ipa'),

  /// An Android App Bundle, ready for Google Play.
  aab('aab'),

  /// An Android package for direct installs and Firebase App Distribution.
  apk('apk'),

  /// The R8 mapping of an Android build.
  mapping('mapping'),

  /// The debug symbols of an iOS build.
  dsym('dsym'),

  /// The record of what a job built (`record.manifest`).
  manifest('manifest'),

  /// The symbols Shorebird needs to read a crash of a release.
  shorebirdSymbols('shorebird_symbols');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;
}

/// A file a job produced, kept in the engine's artifact store.
@JsonSerializable(includeIfNull: false)
class Artifact extends Equatable {
  /// Creates an artifact.
  const new({
    required this.id,
    required this.jobId,
    required this.kind,
    required this.name,
    required this.size,
    required this.sha256,
    required this.pinned,
    required this.createdAt,
  });

  /// Reads an artifact from its JSON form.
  factory Artifact.fromJson(Map<String, dynamic> json) =>
      _$ArtifactFromJson(json);

  /// The engine's id, for example `art_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The job that produced it.
  final String jobId;

  /// What it is.
  final ArtifactKind kind;

  /// The file name, such as `dev-1.0.0+7.apk`.
  final String name;

  /// Its size in bytes.
  final int size;

  /// The SHA-256 of its content, in lowercase hexadecimal.
  final String sha256;

  /// Whether a pinned artifact is kept when the engine frees up space.
  final bool pinned;

  /// When the engine stored it, in UTC.
  final DateTime createdAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ArtifactToJson(this);

  @override
  List<Object?> get props => [
    id,
    jobId,
    kind,
    name,
    size,
    sha256,
    pinned,
    createdAt,
  ];
}

/// The body of `GET /jobs/{id}/artifacts`.
@JsonSerializable(explicitToJson: true)
class ArtifactsResponse extends Equatable {
  /// Creates the list.
  const new(this.artifacts);

  /// Reads the list from its JSON form.
  factory ArtifactsResponse.fromJson(Map<String, dynamic> json) =>
      _$ArtifactsResponseFromJson(json);

  /// The artifacts of the job, oldest first.
  final List<Artifact> artifacts;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ArtifactsResponseToJson(this);

  @override
  List<Object?> get props => [artifacts];
}
