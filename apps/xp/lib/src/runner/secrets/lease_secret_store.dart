import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp_engine/xp_engine.dart';

/// Asks the engine for the secret [key] of a lease: its bytes, or `null` if
/// the engine refuses (`secret_denied`).
typedef SecretRequester = Future<List<int>?> Function(String key);

/// The secrets of the job a runner leases, as the steps of the job read them.
///
/// A step reads a secret like on the engine, from a [SecretStore]. Here the
/// values come from the engine, over the authenticated socket, one request per
/// key and lease (D-09, ADR 0012): only the keys of the offer can be asked
/// for. A delivered secret is kept in the job's secret folder ([SecretArea]),
/// which is wiped when the job ends and when the runner starts, and the
/// readable ones are taught to the masker so that no log line shows them.
///
/// The store is read only; nothing a step does can change a secret.
class LeaseSecretStore implements SecretStore {
  /// Creates the store for the job `jobId`, which may ask for `granted`.
  new({
    required this._jobId,
    required Iterable<String> granted,
    required this._area,
    required this._request,
    required this._masker,
  }) : _granted = granted.toSet();

  final String _jobId;
  final Set<String> _granted;
  final SecretArea _area;
  final SecretRequester _request;
  final OutputMasker _masker;
  final _asking = <String, Future<List<int>?>>{};

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<Uint8List?> readBytes(String key) async {
    if (!_granted.contains(key)) return null;
    final kept = await _area.recall(_jobId, key);
    if (kept != null) return Uint8List.fromList(kept);
    final bytes = await (_asking[key] ??= _deliver(key));
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  Future<List<int>?> _deliver(String key) async {
    final bytes = await _request(key);
    if (bytes == null) return null;
    await _area.keep(_jobId, key, bytes);
    try {
      final text = utf8.decode(bytes);
      if (text.isNotEmpty) _masker.add(text);
    } on FormatException {
      // Binary, a keystore: nothing readable to hide.
    }
    return bytes;
  }

  @override
  Future<String?> read(String key) async {
    final bytes = await readBytes(key);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw SecretStoreException('The secret "$key" is not text.');
    }
  }

  @override
  Future<void> write(String key, String value) async =>
      throw const SecretStoreException('A leased job cannot change secrets.');

  @override
  Future<void> writeBytes(String key, List<int> value) async =>
      throw const SecretStoreException('A leased job cannot change secrets.');

  @override
  Future<void> delete(String key) async =>
      throw const SecretStoreException('A leased job cannot change secrets.');
}
