import 'dart:convert';
import 'dart:io';

import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp_engine/xp_engine.dart';

/// Who a paired runner is: the engine it belongs to and its name there. The
/// credential is not part of it; that is a secret and lives in the secret
/// store ([RunnerEnrollment]).
class RunnerIdentity {
  /// Creates the identity.
  const new({required this.engine, required this.runnerId, required this.name});

  /// Reads the identity from its JSON form.
  ///
  /// Throws a [FormatException] if a field is missing.
  factory fromJson(Map<String, dynamic> json) {
    final engine = json['engine'];
    final runnerId = json['runnerId'];
    final name = json['name'];
    if (engine is! String || runnerId is! String || name is! String) {
      throw const FormatException(
        'runner.json needs "engine", "runnerId" and "name".',
      );
    }
    return RunnerIdentity(
      engine: Uri.parse(engine),
      runnerId: runnerId,
      name: name,
    );
  }

  /// The engine, for example `https://xpath.example.com`.
  final Uri engine;

  /// The runner's id on the engine.
  final String runnerId;

  /// The runner's name on the engine (the one `xp runners pair` was given).
  final String name;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'engine': engine.toString(),
    'runnerId': runnerId,
    'name': name,
  };
}

/// A runner that is paired: its identity and its credential.
class RunnerEnrollment {
  /// Creates the enrollment.
  const new({required this.identity, required this.credential});

  /// Who the runner is.
  final RunnerIdentity identity;

  /// The bearer token the runner dials in with. Never printed or logged.
  final String credential;
}

/// Keeps the enrollment of a runner: the identity in `runner.json` in the data
/// directory, the credential in the secret store (the Keychain on macOS, an
/// encrypted file on Linux; never a plain file).
class RunnerEnrollments {
  /// Creates the store over [_paths] and [_secrets].
  const new(this._paths, this._secrets);

  final RunnerPaths _paths;
  final SecretStore _secrets;

  static String _key(String runnerId) => 'runner.$runnerId.credential';

  /// The enrollment, or `null` if this data directory is not paired.
  ///
  /// Throws a [FormatException] if `runner.json` is not valid, and a
  /// [SecretStoreException] if the credential cannot be read.
  Future<RunnerEnrollment?> read() async {
    final file = File(_paths.identityFile);
    if (!file.existsSync()) return null;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map<String, dynamic>) {
      throw const FormatException('runner.json is not a JSON object.');
    }
    final identity = RunnerIdentity.fromJson(json);
    final credential = await _secrets.read(_key(identity.runnerId));
    if (credential == null) return null;
    return RunnerEnrollment(identity: identity, credential: credential);
  }

  /// Saves the credential, then the identity: a runner counts as paired only
  /// when both are there.
  Future<void> write(RunnerEnrollment enrollment) async {
    final identity = enrollment.identity;
    await _secrets.write(_key(identity.runnerId), enrollment.credential);
    await Directory(_paths.root).create(recursive: true);
    final temporary = File('${_paths.identityFile}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(identity.toJson())}\n',
    );
    await temporary.rename(_paths.identityFile);
  }
}
