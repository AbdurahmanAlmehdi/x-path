import 'dart:async';
import 'dart:convert';

import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/src/tracking_secret_store.dart';

/// Keeps secrets in the macOS Keychain (ADR 0004).
///
/// Every operation runs one `security -i` process and writes a single command
/// line to its standard input, so a secret is never in the arguments or the
/// environment of a process, where `ps` could show it. Each argument is
/// double-quoted, with `\` written as `\\` and `"` as `\"`. Secrets are kept
/// under the service `ly.abdurahman.xpath.<scope>`, with the key as the
/// account.
///
/// Values are stored as base64 of their UTF-8 bytes. `security -i` reads one
/// line, so a raw newline would end the command, and `find-generic-password
/// -w` prints a value that is not plain ASCII as hex.
///
/// The engine never prompts. A locked Keychain, or no Keychain at all, throws
/// a [SecretsLockedException]. When a Keychain is locked inside a graphical
/// session macOS may wait for a password prompt instead of failing, so each
/// operation has a `timeout` after which `security` is killed and the store
/// counts as locked. Reading an item that does not exist succeeds even when
/// the Keychain is locked, so only operations on existing items can tell.
class KeychainSecretStore extends TrackingSecretStore {
  /// Creates a store that runs `security` through `runner`.
  ///
  /// `scope` becomes the service name `ly.abdurahman.xpath.<scope>`. Without a
  /// `keychainPath` the default Keychain is used; tests pass a temporary one.
  new({
    required this._runner,
    this.scope = defaultScope,
    this._keychainPath,
    this._timeout = const Duration(seconds: 10),
    this._securityExecutable = '/usr/bin/security',
  });

  /// The scope used when none is given.
  static const defaultScope = 'credentials';

  /// The longest command line `security -i` reads: its input buffer holds
  /// 4096 bytes, and longer lines are silently garbled.
  static const maxCommandLength = 4094;

  /// The error codes that mean the Keychain cannot be used without a user:
  /// interaction not allowed, authentication failed, user cancelled and no
  /// default Keychain.
  static const _lockedCodes = {-25308, -25293, -128, -25307};
  static const _notFoundCode = -25300;

  /// The scope of the service name.
  final String scope;

  final ProcessRunner _runner;
  final String? _keychainPath;
  final Duration _timeout;
  final String _securityExecutable;

  String get _service => 'ly.abdurahman.xpath.$scope';

  @override
  Future<String?> read(String key) => track(() async {
    checkKey(key);
    final output = await _run('find-generic-password', [
      '-a',
      key,
      '-s',
      _service,
      '-w',
    ]);
    if (output == null) return null;
    try {
      return utf8.decode(base64.decode(output.stdout.trim()));
    } on FormatException {
      throw const SecretStoreException(
        'The Keychain item was not written by XPath: its value is not base64.',
      );
    }
  });

  @override
  Future<void> write(String key, String value) => track(() async {
    checkKey(key);
    await _run('add-generic-password', [
      '-U',
      '-a',
      key,
      '-s',
      _service,
      '-w',
      base64.encode(utf8.encode(value)),
    ]);
  });

  @override
  Future<void> delete(String key) => track(() async {
    checkKey(key);
    await _run('delete-generic-password', ['-a', key, '-s', _service]);
  });

  /// Runs a `security` command. Returns `null` if the item does not exist.
  Future<ProcessOutput?> _run(String command, List<String> arguments) async {
    final line = [command, ...arguments, ?_keychainPath].map(_quote).join(' ');
    if (utf8.encode(line).length > maxCommandLength) {
      throw const SecretStoreException(
        'The secret is too large for the Keychain store: security -i reads '
        'at most $maxCommandLength bytes per command.',
      );
    }
    final ProcessOutput output;
    try {
      output = await _runner.run(
        _securityExecutable,
        ['-i'],
        stdin: '$line\n',
        timeout: _timeout,
      );
    } on TimeoutException {
      throw const SecretsLockedException(
        'The Keychain did not answer in time. It is probably locked and '
        'waiting for a password.',
      );
    } on ProcessStartException catch (error) {
      throw SecretStoreException('Cannot run security: ${error.message}');
    }
    if (output.exitCode == 0) return output;
    return _fail(command, output);
  }

  /// Turns a failed `security` run into the right exception, or `null` for a
  /// missing item.
  ///
  /// The message never repeats `security`'s own output: it echoes the
  /// arguments it could not parse, and those include the secret.
  ProcessOutput? _fail(String command, ProcessOutput output) {
    final code = _errorCode(output.stderr);
    if (code == _notFoundCode ||
        output.stderr.contains('could not be found in the keychain')) {
      return null;
    }
    if (_lockedCodes.contains(code) ||
        output.stderr.contains('User interaction is not allowed')) {
      throw SecretsLockedException(
        'The Keychain is locked (security error ${code ?? 'unknown'}).',
      );
    }
    throw SecretStoreException(
      'security $command failed with exit code ${output.exitCode}'
      '${code == null ? '' : ' (security error $code)'}.',
    );
  }

  /// The status `security -i` printed after `returned`, if any.
  int? _errorCode(String stderr) {
    final match = RegExp(r'returned (-?\d+)').firstMatch(stderr);
    return match == null ? null : int.parse(match.group(1)!);
  }

  /// Quotes [argument] for `security -i`.
  String _quote(String argument) {
    if (argument.runes.any((r) => r == 0x0a || r == 0x0d || r == 0)) {
      throw ArgumentError.value(
        argument,
        'argument',
        'contains a line break or NUL',
      );
    }
    final escaped = argument.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
