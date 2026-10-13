import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Device tokens in a JSON file, `tokens.json`, in the data directory.
///
/// The file holds hashes only. It is read on every call, so a token created
/// by `xpd token create` works at once in a running engine. Phase 3 replaces
/// this with SQLite.
class FileDeviceTokenRepository implements DeviceTokenRepository {
  /// Creates a repository over the file `tokens.json` in `directory`.
  ///
  /// `runProcess` runs `chmod`, which keeps the files private to the user;
  /// tests replace it.
  new(String directory, {this._runProcess = Process.run})
    : _file = File(p.join(directory, 'tokens.json'));

  final File _file;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;

  @override
  Future<List<DeviceToken>> list() async {
    if (!_file.existsSync()) return const [];
    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    return [
      for (final entry in json['tokens'] as List<dynamic>)
        _fromJson(entry as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> add(DeviceToken token) async {
    final tokens = [...await list(), token];
    final directory = _file.parent;
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      await _chmod('700', directory.path);
    }
    // Write beside the target and rename, so a crash never leaves half a file.
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'tokens': tokens.map(_toJson).toList()}),
      flush: true,
    );
    await _chmod('600', temporary.path);
    await temporary.rename(_file.path);
  }

  static Map<String, dynamic> _toJson(DeviceToken token) => {
    'id': token.id,
    'name': token.name,
    'kind': token.kind.name,
    'hash': token.hash,
    'createdAt': token.createdAt.toUtc().toIso8601String(),
    'revokedAt': token.revokedAt?.toUtc().toIso8601String(),
  };

  static DeviceToken _fromJson(Map<String, dynamic> json) {
    final revokedAt = json['revokedAt'] as String?;
    return DeviceToken(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: DeviceTokenKind.values.byName(json['kind'] as String),
      hash: json['hash'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      revokedAt: revokedAt == null ? null : DateTime.parse(revokedAt),
    );
  }

  Future<void> _chmod(String mode, String path) async {
    final result = await _runProcess('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed: ${result.stderr}', path);
    }
  }
}
