import 'dart:convert';
import 'dart:typed_data';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] in memory that keeps bytes as bytes, so that a binary
/// keystore survives. Text is UTF-8.
class BytesSecretStore implements SecretStore {
  /// What is stored, by key.
  final values = <String, Uint8List>{};

  /// Set to make every call fail with it.
  SecretStoreException? failure;

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  /// The text under [key], without going through the store.
  String? text(String key) {
    final value = values[key];
    return value == null ? null : utf8.decode(value);
  }

  @override
  Future<String?> read(String key) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return text(key);
  }

  @override
  Future<void> write(String key, String value) =>
      writeBytes(key, utf8.encode(value));

  @override
  Future<Uint8List?> readBytes(String key) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return values[key];
  }

  @override
  Future<void> writeBytes(String key, List<int> value) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    values[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// A [TemporaryFileStore] in memory.
class MemoryTemporaryFiles implements TemporaryFileStore {
  /// The contents of every file that was made, in order.
  final created = <List<int>>[];

  /// The paths of the files that were deleted.
  final deleted = <String>[];

  @override
  Future<TemporaryFile> create(List<int> bytes) async {
    created.add(bytes);
    return _File('/tmp/keystore-${created.length}', deleted);
  }
}

class _File implements TemporaryFile {
  new(this.path, this._deleted);

  @override
  final String path;

  final List<String> _deleted;

  @override
  Future<void> delete() async => _deleted.add(path);
}

/// A [PlayServiceAccount] that is not a real key.
const testServiceAccount = PlayServiceAccount(
  clientEmail: 'xpath@project.iam.gserviceaccount.com',
  privateKey: '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n',
  privateKeyId: 'key1',
);

/// The fields of a request for a credential of [kind], for tests.
Map<String, dynamic> credentialFields(CredentialKind kind) => switch (kind) {
  CredentialKind.ascKey => {
    'keyId': 'ABC123DEF4',
    'issuerId': '57246542-96fe-1a63-e053-0824d011072a',
    'privateKey':
        '-----BEGIN PRIVATE KEY-----\nMIGT\n-----END PRIVATE KEY-----',
  },
  CredentialKind.appleId => {
    'appleId': 'dev@example.com',
    'password': 'abcd-efgh-ijkl-mnop',
  },
  CredentialKind.playSa || CredentialKind.firebaseSa => {
    'serviceAccount': testServiceAccount.toSecret(),
  },
  CredentialKind.keystore => {
    'keystore': base64.encode([1, 2, 3, 4, 250]),
    'storePassword': 'store-pass',
    'keyAlias': 'upload',
  },
  CredentialKind.shorebird => {'token': 'sb_api_abc123'},
  CredentialKind.github => {'token': 'ghp_abc123'},
  CredentialKind.slack => {
    'webhookUrl': 'https://hooks.slack.com/services/T000/B000/XXXX',
  },
};

/// The flavor every credential test uses.
const testFlavor = CredentialFlavor(
  id: 'flv_1',
  projectId: 'prj_1',
  appPath: '.',
  name: 'prod',
  iosBundleId: 'com.mataa.app',
  androidAppId: 'com.mataa.app',
);
