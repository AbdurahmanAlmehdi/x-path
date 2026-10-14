@Tags(['macos'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/secrets/temporary_keychain.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

/// Uses a keychain of its own in a temporary folder, created unlocked, so
/// that no dialog can appear. The login keychain and the search list of the
/// user are never touched.
void main() {
  test('creates, unlocks and deletes a real keychain', () async {
    final directory = Directory.systemTemp.createTempSync('xp_real_keychain_');
    addTearDown(() => directory.deleteSync(recursive: true));
    const runner = IoProcessRunner();

    final keychain = await TemporaryKeychain.create(
      runner: runner,
      directory: directory.path,
      name: 'job_1',
    );

    expect(File(keychain.path).existsSync(), isTrue);
    // Unlocked and never locking again: `security show-keychain-info` prints
    // the settings, and a keychain without timeout has none.
    final info = await runner.run('/usr/bin/security', [
      'show-keychain-info',
      keychain.path,
    ]);
    expect('${info.stdout}${info.stderr}', isNot(contains('timeout=')));
    final listed = await runner.run('/usr/bin/security', [
      'list-keychains',
      '-d',
      'user',
    ]);
    expect(listed.stdout, isNot(contains(directory.path)));

    await keychain.delete();
    expect(File(keychain.path).existsSync(), isFalse);
  });

  test('removes the keychains a dead runner left', () async {
    final directory = Directory.systemTemp.createTempSync('xp_real_keychain_');
    addTearDown(() => directory.deleteSync(recursive: true));
    const runner = IoProcessRunner();
    final folder = p.join(directory.path, 'keychains');
    await TemporaryKeychain.create(
      runner: runner,
      directory: folder,
      name: 'job_1',
    );
    await TemporaryKeychain.create(
      runner: runner,
      directory: folder,
      name: 'job_2',
    );

    final removed = await TemporaryKeychain.removeLeftovers(
      runner: runner,
      directory: folder,
    );

    expect(removed, 2);
    expect(Directory(folder).listSync(), isEmpty);
  });
}
