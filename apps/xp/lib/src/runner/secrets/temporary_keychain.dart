import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

const _security = '/usr/bin/security';

/// A keychain made for one job on macOS, for signing material that has to be
/// in a keychain (D-09). It is never the login keychain, and it never makes
/// macOS show a dialog: it is created unlocked, with a random password, and
/// set not to lock again by timeout or by sleep.
///
/// It is added to the search list of the user only if the build needs that
/// ([addToSearchList]), and the list is put back by [delete], which also
/// removes the keychain and its file. A start of the runner removes what a
/// crash left ([removeLeftovers]).
///
/// Every `security` command runs as `security -i` with the command on its
/// standard input, so that the password is in no argument (ADR 0004).
class TemporaryKeychain {
  new _(this._runner, this.path, this.password, this._timeout);

  /// Creates and unlocks the keychain [name] in [directory].
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  static Future<TemporaryKeychain> create({
    required ProcessRunner runner,
    required String directory,
    required String name,
    Duration timeout = const Duration(seconds: 30),
    Random? random,
  }) async {
    final secure = random ?? Random.secure();
    final password = List.generate(
      32,
      (_) => secure.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await Directory(directory).create(recursive: true);
    final keychain = TemporaryKeychain._(
      runner,
      p.join(directory, '$name.keychain-db'),
      password,
      timeout,
    );
    await keychain._run('create-keychain', ['-p', password, keychain.path]);
    // No -t and no -l: the keychain never locks by timeout or by sleep.
    await keychain._run('set-keychain-settings', [keychain.path]);
    await keychain._run('unlock-keychain', ['-p', password, keychain.path]);
    return keychain;
  }

  final ProcessRunner _runner;
  final Duration _timeout;

  /// The keychain file.
  final String path;

  /// The random password it was created with. Never printed or logged.
  final String password;

  List<String>? _savedSearchList;

  /// Puts the keychain first in the search list of the user, remembering the
  /// list as it was.
  Future<void> addToSearchList() async {
    if (_savedSearchList != null) return;
    final saved = await _searchList(_runner, _timeout);
    await _run('list-keychains', ['-d', 'user', '-s', path, ...saved]);
    _savedSearchList = saved;
  }

  /// Puts the search list back as it was, deletes the keychain and its file.
  /// Does nothing wrong if either is gone already.
  Future<void> delete() async {
    final saved = _savedSearchList;
    if (saved != null) {
      _savedSearchList = null;
      await _run('list-keychains', ['-d', 'user', '-s', ...saved]);
    }
    await _runIgnoringFailure('delete-keychain', [path]);
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  /// Deletes every keychain in [directory], and takes them out of the search
  /// list: what a runner that died left. Returns how many it removed.
  static Future<int> removeLeftovers({
    required ProcessRunner runner,
    required String directory,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final folder = Directory(directory);
    if (!folder.existsSync()) return 0;
    final leftovers = [
      for (final entry in folder.listSync())
        if (entry is File && entry.path.endsWith('.keychain-db')) entry.path,
    ];
    if (leftovers.isEmpty) return 0;
    final listed = await _searchList(runner, timeout);
    final kept = [
      for (final path in listed)
        if (!leftovers.contains(path)) path,
    ];
    if (kept.length != listed.length) {
      await _runWith(runner, timeout, 'list-keychains', [
        '-d',
        'user',
        '-s',
        ...kept,
      ]);
    }
    for (final path in leftovers) {
      await _runWith(runner, timeout, 'delete-keychain', [path], mayFail: true);
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }
    return leftovers.length;
  }

  static Future<List<String>> _searchList(
    ProcessRunner runner,
    Duration timeout,
  ) async {
    final output = await _runWith(runner, timeout, 'list-keychains', [
      '-d',
      'user',
    ]);
    return [
      for (final match in RegExp('"([^"]+)"').allMatches(output.stdout))
        match.group(1)!,
    ];
  }

  Future<void> _run(String command, List<String> arguments) async {
    await _runWith(_runner, _timeout, command, arguments);
  }

  Future<void> _runIgnoringFailure(String command, List<String> arguments) =>
      _runWith(_runner, _timeout, command, arguments, mayFail: true);

  static Future<ProcessOutput> _runWith(
    ProcessRunner runner,
    Duration timeout,
    String command,
    List<String> arguments, {
    bool mayFail = false,
  }) async {
    final line = [command, ...arguments].map(_quote).join(' ');
    final ProcessOutput output;
    try {
      output = await runner.run(
        _security,
        ['-i'],
        stdin: '$line\n',
        timeout: timeout,
      );
    } on TimeoutException {
      throw SecretStoreException('security $command did not answer in time.');
    } on ProcessStartException catch (error) {
      throw SecretStoreException('Cannot run security: ${error.message}');
    }
    if (output.exitCode != 0 && !mayFail) {
      // `security` echoes the arguments it fails on, and one is a password.
      throw SecretStoreException(
        'security $command failed with exit code ${output.exitCode}.',
      );
    }
    return output;
  }

  static String _quote(String argument) =>
      '"${argument.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}
