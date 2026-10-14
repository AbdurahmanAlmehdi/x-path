import 'package:crypto/crypto.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/runners/runner_exceptions.dart';

final _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,199}$');
final _digest = RegExp(r'^[0-9a-f]{64}$');

/// Takes the files a leased job produced on a runner into the artifact store
/// (D-08).
///
/// The runner declares the SHA-256 and the size of the file. The bytes are
/// hashed as they stream into the store, and the store only commits the file
/// when both match: a mismatch ends the stream with an error before the file
/// replaces anything, so a half or wrong upload leaves no trace.
class RunnerArtifacts {
  /// Creates the service.
  ///
  /// `holdsLease` tells whether the runner holds the lease (the hub's
  /// `holdsLease`).
  const new({required this._recorder, required this._holdsLease});

  final ArtifactRecorder _recorder;
  final bool Function(String runnerId, String jobId, String leaseId)
  _holdsLease;

  /// Stores [content] as the file [name] of [jobId] and records it as an
  /// artifact of [kind].
  ///
  /// Throws a [RunnerLeaseException] if the runner [runnerId] does not hold
  /// the lease [leaseId] of the job, a [RunnerInvalidException] for a name or
  /// digest that is not valid, and an [ArtifactChecksumException] if the
  /// bytes are not [size] bytes with the SHA-256 [sha256].
  Future<ArtifactRecord> upload({
    required String runnerId,
    required String jobId,
    required String leaseId,
    required ArtifactKind kind,
    required String name,
    required Stream<List<int>> content,
    required String sha256,
    required int size,
  }) async {
    if (!_holdsLease(runnerId, jobId, leaseId)) {
      throw RunnerLeaseException(
        'Runner $runnerId does not hold lease $leaseId of job $jobId.',
      );
    }
    if (!_fileName.hasMatch(name)) {
      throw const RunnerInvalidException(
        'An artifact name is a plain file name of letters, digits, dots, '
        'plus signs, underscores and dashes.',
      );
    }
    final expected = sha256.toLowerCase();
    if (!_digest.hasMatch(expected) || size < 0) {
      throw const RunnerInvalidException(
        'Declare the SHA-256 in lowercase hexadecimal and a size of 0 or '
        'more.',
      );
    }
    return await _recorder.record(
      jobId: jobId,
      kind: kind,
      name: name,
      content: _verified(content, expected, size),
    );
  }

  Stream<List<int>> _verified(
    Stream<List<int>> source,
    String expected,
    int size,
  ) async* {
    final sink = _DigestSink();
    final hasher = sha256.startChunkedConversion(sink);
    var received = 0;
    try {
      await for (final chunk in source) {
        received += chunk.length;
        if (received > size) {
          throw ArtifactChecksumException(
            'The upload is longer than the $size bytes declared.',
          );
        }
        hasher.add(chunk);
        yield chunk;
      }
    } finally {
      hasher.close();
    }
    if (received < size) {
      throw ArtifactChecksumException(
        'The upload has $received bytes, not the $size declared.',
      );
    }
    if ('${sink.value}' != expected) {
      throw ArtifactChecksumException(
        'The upload has SHA-256 ${sink.value}, not the $expected declared.',
      );
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
