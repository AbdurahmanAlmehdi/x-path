import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';

/// An artifact as a step reports it in its result.
class ArtifactSummary extends Equatable {
  /// Creates a summary.
  const new({
    required this.id,
    required this.kind,
    required this.name,
    required this.size,
    required this.sha256,
  });

  /// Summarizes [record].
  factory of(ArtifactRecord record) => ArtifactSummary(
    id: record.id,
    kind: record.kind,
    name: record.name,
    size: record.size,
    sha256: record.sha256,
  );

  /// The artifact's id.
  final String id;

  /// What the file is.
  final ArtifactKind kind;

  /// The file name.
  final String name;

  /// Its size in bytes.
  final int size;

  /// Its SHA-256.
  final String sha256;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.wire,
    'name': name,
    'size': size,
    'sha256': sha256,
  };

  @override
  List<Object?> get props => [id, kind, name, size, sha256];
}
