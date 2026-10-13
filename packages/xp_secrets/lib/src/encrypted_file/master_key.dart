import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// The size of the master key: 256 bits.
const masterKeyLength = 32;

/// The name of the systemd credential that holds the master key
/// (`LoadCredentialEncrypted=xpath-master-key:...`).
const masterKeyCredentialName = 'xpath-master-key';

/// The file in the data directory that holds the master key when there is no
/// systemd credential.
const masterKeyFileName = 'master.key';

/// Finds the key that encrypts the secrets file.
///
/// The key is 32 raw bytes, from one of two places:
///
/// 1. `$CREDENTIALS_DIRECTORY/xpath-master-key`, when systemd runs the engine
///    with `LoadCredentialEncrypted=`. The key is never on disk in clear.
/// 2. `master.key` in the data directory, readable by its owner only. It is
///    created on first use.
///
/// A key that is missing, unreadable, of the wrong size, or in a file other
/// users can read, is never used: it throws a [SecretsLockedException].
class MasterKeySource {
  /// Creates a source over `dataDir`.
  ///
  /// `credentialsDirectory` is `$CREDENTIALS_DIRECTORY`, or `null` outside
  /// systemd. `runner` sets the permissions of a new key file.
  new({
    required this._dataDir,
    required this._runner,
    this._credentialsDirectory,
    Random? random,
  }) : _random = random ?? Random.secure();

  final String _dataDir;
  final ProcessRunner _runner;
  final String? _credentialsDirectory;
  final Random _random;
  List<int>? _cached;

  /// The path of the key file in the data directory.
  String get keyFilePath => p.join(_dataDir, masterKeyFileName);

  /// Loads the key.
  ///
  /// A new key file is only created when [createIfMissing] is set; a missing
  /// key next to existing secrets is an error, never a reason for a new key.
  Future<List<int>> load({required bool createIfMissing}) async {
    final cached = _cached;
    if (cached != null) return cached;
    final directory = _credentialsDirectory;
    final key = directory != null && directory.isNotEmpty
        ? await _fromCredential(p.join(directory, masterKeyCredentialName))
        : await _fromKeyFile(createIfMissing: createIfMissing);
    return _cached = key;
  }

  Future<List<int>> _fromCredential(String path) async {
    if (!File(path).existsSync()) {
      throw const SecretsLockedException(
        'The systemd credential $masterKeyCredentialName is missing from '
        r'$CREDENTIALS_DIRECTORY.',
      );
    }
    return await _readKey(path);
  }

  Future<List<int>> _fromKeyFile({required bool createIfMissing}) async {
    final path = keyFilePath;
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (!createIfMissing) {
        throw SecretsLockedException(
          'The master key file $path is missing, but secrets exist.',
        );
      }
      return await _createKeyFile(path);
    }
    if (type != FileSystemEntityType.file) {
      throw SecretsLockedException(
        'The master key path $path is not a regular file.',
      );
    }
    final mode = File(path).statSync().mode;
    if (mode & 0x3f != 0) {
      throw SecretsLockedException(
        'The master key file $path is readable by other users '
        '(mode ${(mode & 0xfff).toRadixString(8)}). Run: chmod 600 $path',
      );
    }
    return await _readKey(path);
  }

  Future<List<int>> _readKey(String path) async {
    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (error) {
      throw SecretsLockedException(
        'Cannot read the master key $path: '
        '${error.osError?.message ?? error.message}.',
      );
    }
    if (bytes.length != masterKeyLength) {
      throw SecretsLockedException(
        'The master key $path must be exactly $masterKeyLength bytes, '
        'not ${bytes.length}.',
      );
    }
    return bytes;
  }

  Future<List<int>> _createKeyFile(String path) async {
    final key = List.generate(masterKeyLength, (_) => _random.nextInt(256));
    await writePrivateFile(_runner, path, key);
    return key;
  }
}

/// Atomically writes [bytes] to [path], readable by its owner only.
///
/// The bytes go to a temporary file in the same folder, whose mode is set to
/// 0600 before anything is written to it, and the file is then renamed over
/// [path]. A reader sees the old file or the new one, never half of one.
Future<void> writePrivateFile(
  ProcessRunner runner,
  String path,
  List<int> bytes,
) async {
  final directory = Directory(p.dirname(path));
  final temporary = File('$path.tmp-${DateTime.now().microsecondsSinceEpoch}');
  try {
    await directory.create(recursive: true);
    await temporary.create();
    final chmod = await runner.run('chmod', ['600', temporary.path]);
    if (chmod.exitCode != 0) {
      throw const SecretStoreException(
        'Cannot make the secrets file private: chmod failed.',
      );
    }
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  } on ProcessStartException catch (error) {
    throw SecretStoreException('Cannot run chmod: ${error.message}');
  } on FileSystemException catch (error) {
    throw SecretStoreException(
      'Cannot write $path: ${error.osError?.message ?? error.message}.',
    );
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }
}
