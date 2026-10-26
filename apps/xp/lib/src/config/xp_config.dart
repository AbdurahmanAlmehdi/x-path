import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp/src/config/token_vault.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart' show SecretsLockedException;

/// The engine URL, instead of the one `xp connect` saved.
const engineUrlVariable = 'XP_ENGINE_URL';

/// The token of `xp`, instead of the one `xp connect` saved.
const tokenVariable = 'XP_TOKEN';

/// The token of `xp mcp`, instead of the one `xp connect` saved.
const mcpTokenVariable = 'XP_MCP_TOKEN';

/// The folder of `xp.json`, instead of `~/.config/xpath`.
const configDirVariable = 'XP_CONFIG_DIR';

/// What `xp` needs to talk to an engine: where it is and the token to use.
class Connection {
  /// Creates the connection.
  const new({required this.url, required this.token});

  /// The engine, for example `http://127.0.0.1:7480`.
  final Uri url;

  /// The device token. Never printed or logged.
  final String token;
}

/// `xp` has nothing to connect with: no engine URL or no token.
class NotConnectedException implements Exception {
  /// Creates the exception.
  const new(this.message);

  /// What is missing and what to do about it.
  final String message;

  @override
  String toString() => message;
}

/// Where `xp` keeps its settings: the engine URL in `xp.json` in the config
/// folder (`$XP_CONFIG_DIR`, else `$XDG_CONFIG_HOME/xpath`, else
/// `~/.config/xpath`), and the tokens in the OS secret store (a
/// `TokenVault`), never in that file.
///
/// `XP_ENGINE_URL`, `XP_TOKEN` and `XP_MCP_TOKEN` override what was saved, so
/// a script can use `xp` without saving anything (and without the Keychain).
class XpConfig {
  /// Creates the config. `openVault` runs only when a token has to be read or
  /// saved and no environment variable gives it, so a Keychain is not touched
  /// for nothing.
  new({
    required this.directory,
    required this._environment,
    required this._openVault,
  });

  /// The config folder for [environment] on a machine whose home folder is
  /// [home].
  static String directoryFor(Map<String, String> environment, String home) {
    final explicit = environment[configDirVariable];
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final xdg = environment['XDG_CONFIG_HOME'];
    final base = xdg != null && xdg.isNotEmpty ? xdg : p.join(home, '.config');
    return p.join(base, 'xpath');
  }

  /// The config folder.
  final String directory;

  final Map<String, String> _environment;
  final TokenVault Function() _openVault;

  File get _file => File(p.join(directory, 'xp.json'));

  /// The engine URL: `XP_ENGINE_URL`, else the saved one, else `null`.
  Future<Uri?> engineUrl() async {
    final fromEnvironment = _environment[engineUrlVariable];
    if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
      return parseEngineUrl(fromEnvironment);
    }
    final saved = (await _read())['engine'];
    return saved is String ? parseEngineUrl(saved) : null;
  }

  /// Saves the engine URL.
  Future<void> saveEngineUrl(Uri url) async {
    final settings = await _read();
    settings['engine'] = url.toString();
    await _write(settings);
  }

  Future<void> _write(Map<String, dynamic> settings) async {
    await Directory(directory).create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(settings)}\n',
    );
    await temporary.rename(_file.path);
  }

  /// Forgets the saved engine URL and the saved `cli` and `mcp` tokens
  /// (`xp disconnect`). The environment variables still apply. Returns the
  /// URL it forgot, if one was saved.
  Future<Uri?> forget() async {
    final settings = await _read();
    final saved = settings.remove('engine');
    if (saved != null) await _write(settings);
    try {
      final vault = _openVault();
      for (final kind in [DeviceTokenKind.cli, DeviceTokenKind.mcp]) {
        await vault.delete(kind);
      }
    } on SecretsLockedException catch (error) {
      throw NotConnectedException(
        '${error.message} Unlock it to forget the tokens.',
      );
    }
    return saved is String ? parseEngineUrl(saved) : null;
  }

  /// The token of [kind]: from the environment, else the secret store.
  Future<String?> token(DeviceTokenKind kind) async {
    final fromEnvironment = _environment[_tokenVariable(kind)];
    if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
      return fromEnvironment;
    }
    try {
      return await _openVault().read(kind);
    } on SecretsLockedException catch (error) {
      throw NotConnectedException(
        '${error.message} Unlock it, or set ${_tokenVariable(kind)}.',
      );
    }
  }

  /// Saves the token of [kind] in the secret store.
  Future<void> saveToken(DeviceTokenKind kind, String token) async {
    try {
      await _openVault().write(kind, token);
    } on SecretsLockedException catch (error) {
      throw NotConnectedException(
        '${error.message} Unlock it, or set ${_tokenVariable(kind)} instead '
        'of saving the token.',
      );
    }
  }

  /// The engine and the token of [kind].
  ///
  /// Throws a [NotConnectedException] that says what to do if either is
  /// missing.
  Future<Connection> connection(DeviceTokenKind kind) async {
    final url = await engineUrl();
    if (url == null) {
      throw const NotConnectedException(
        'No engine is set. Run: xp connect <url> --token <token>  '
        '(or set $engineUrlVariable).',
      );
    }
    final token = await this.token(kind);
    if (token == null) {
      final option = kind == DeviceTokenKind.mcp ? '--mcp-token' : '--token';
      throw NotConnectedException(
        'No ${kind.name} token is saved. '
        'Run: xp connect $option <token>  (or set ${_tokenVariable(kind)}).',
      );
    }
    return Connection(url: url, token: token);
  }

  static String _tokenVariable(DeviceTokenKind kind) =>
      kind == DeviceTokenKind.mcp ? mcpTokenVariable : tokenVariable;

  Future<Map<String, dynamic>> _read() async {
    if (!_file.existsSync()) return <String, dynamic>{};
    try {
      final settings = jsonDecode(await _file.readAsString());
      if (settings is Map<String, dynamic>) return settings;
    } on FormatException {
      // Falls through to the error below.
    }
    throw NotConnectedException(
      '${_file.path} is not a JSON object. Fix or delete it.',
    );
  }
}

/// Reads an engine URL: `http` or `https`, with a host.
///
/// A bare `host:port` is taken as `http://host:port`. Throws a
/// [FormatException] that says what is wrong.
Uri parseEngineUrl(String text) {
  final trimmed = text.trim();
  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final url = Uri.parse(withScheme);
  if ((url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty) {
    throw FormatException('"$text" is not an http(s) URL of an engine.');
  }
  return url;
}
