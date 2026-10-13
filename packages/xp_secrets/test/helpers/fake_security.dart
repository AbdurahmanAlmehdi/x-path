import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

/// A fake `security -i`: an in-memory Keychain behind a [FakeProcessRunner].
///
/// It understands the three commands [KeychainSecretStore] sends and answers
/// like `security` for a missing item and for a locked Keychain. It fails the
/// test, as the real one would garble the line, if a command line is longer
/// than 4094 bytes.
class FakeSecurity {
  /// The items, by `service/account`, with the (base64) value as sent.
  final items = <String, String>{};

  /// Whether the Keychain is locked.
  bool locked = false;

  /// Every command line received.
  final lines = <String>[];

  /// The handler of a [FakeProcessRunner].
  ProcessOutput handle(FakeProcessCall call) {
    final line = call.stdin.trimRight();
    lines.add(line);
    if (line.length > 4094) {
      throw StateError('security -i would garble a line of ${line.length}.');
    }
    final tokens = [
      for (final match in RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(line))
        match.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!),
    ];
    final command = tokens.first;
    String? option(String flag) {
      final index = tokens.indexOf(flag);
      return index < 0 ? null : tokens[index + 1];
    }

    final id = '${option('-s')}/${option('-a')}';
    if (locked) {
      return ProcessOutput(
        exitCode: 36,
        stderr:
            'security: SecKeychainItemCreateFromContent: '
            'User interaction is not allowed.\n'
            '$command: returned -25308\n',
      );
    }
    switch (command) {
      case 'add-generic-password':
        items[id] = option('-w')!;
        return const ProcessOutput(exitCode: 0);
      case 'find-generic-password':
        final value = items[id];
        return value == null
            ? _notFound(command)
            : ProcessOutput(exitCode: 0, stdout: '$value\n');
      case 'delete-generic-password':
        return items.remove(id) == null
            ? _notFound(command)
            : const ProcessOutput(exitCode: 0);
    }
    throw StateError('Unexpected security command $command.');
  }

  ProcessOutput _notFound(String command) => ProcessOutput(
    exitCode: 44,
    stderr:
        'security: SecKeychainSearchCopyNext: The specified item could not be '
        'found in the keychain.\n'
        '$command: returned -25300\n',
  );
}
