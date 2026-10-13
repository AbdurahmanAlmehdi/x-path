import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// What the engine stores about a file a job produced.
class ArtifactRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.jobId,
    required this.kind,
    required this.path,
    required this.size,
    required this.sha256,
    required this.createdAt,
    this.pinned = false,
  });

  /// The engine's id.
  final String id;

  /// The job that produced the file.
  final String jobId;

  /// What the file is.
  final ArtifactKind kind;

  /// Where the file is in the artifact store: `<jobId>/<name>`.
  final String path;

  /// Its size in bytes.
  final int size;

  /// The SHA-256 of its content, in lowercase hexadecimal.
  final String sha256;

  /// When it was stored.
  final DateTime createdAt;

  /// Whether the engine keeps it when it frees up space.
  final bool pinned;

  /// The file name, the last part of [path].
  String get name => path.split('/').last;

  /// This record with [pinned] set.
  ArtifactRecord withPinned({required bool pinned}) => ArtifactRecord(
    id: id,
    jobId: jobId,
    kind: kind,
    path: path,
    size: size,
    sha256: sha256,
    createdAt: createdAt,
    pinned: pinned,
  );

  /// The record as clients see it: without the place in the store.
  Artifact toArtifact() => Artifact(
    id: id,
    jobId: jobId,
    kind: kind,
    name: name,
    size: size,
    sha256: sha256,
    pinned: pinned,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    jobId,
    kind,
    path,
    size,
    sha256,
    createdAt,
    pinned,
  ];
}
