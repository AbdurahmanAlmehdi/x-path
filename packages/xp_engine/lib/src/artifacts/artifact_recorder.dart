import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/clock/clock.dart';

/// Puts a file into the artifact store and records it with its size and
/// SHA-256.
///
/// A job keeps one file per name: storing the name again replaces the file and
/// updates its record, which keeps its id and whether it is pinned. That is
/// how a step that runs again leaves one artifact, not two.
class ArtifactRecorder {
  /// Creates a recorder. [random] is for tests; it must be cryptographically
  /// secure otherwise.
  new({
    required this._store,
    required this._repository,
    required this._clock,
    Random? random,
  }) : _random = random ?? Random.secure();

  final ArtifactStore _store;
  final ArtifactRepository _repository;
  final Clock _clock;
  final Random _random;

  /// The path in the store of the file [name] of the job [jobId].
  static String pathOf(String jobId, String name) => '$jobId/$name';

  /// Stores [content] as the file [name] of the job [jobId] and records it as
  /// an artifact of [kind].
  ///
  /// The size and the SHA-256 come from the bytes that were written, in one
  /// pass. Throws what the store throws, and an [ArgumentError] for a [name]
  /// that is not a plain file name.
  Future<ArtifactRecord> record({
    required String jobId,
    required ArtifactKind kind,
    required String name,
    required Stream<List<int>> content,
  }) async {
    final path = pathOf(jobId, name);
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var size = 0;
    try {
      await _store.write(
        path,
        content.map((chunk) {
          hasher.add(chunk);
          size += chunk.length;
          return chunk;
        }),
      );
    } finally {
      hasher.close();
    }
    final existing = await _repository.findByPath(jobId, path);
    final record = ArtifactRecord(
      id: existing?.id ?? 'art_${_hex(8)}',
      jobId: jobId,
      kind: kind,
      path: path,
      size: size,
      sha256: '${digest.value}',
      createdAt: _clock.now(),
      pinned: existing?.pinned ?? false,
    );
    await _repository.save(record);
    return record;
  }

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
