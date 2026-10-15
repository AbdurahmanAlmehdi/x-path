import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/src/engines/engine_profile.dart';
import 'package:xp_repositories/src/engines/token_vault.dart';

/// Makes a client of the engine at `url` for the owner of `token`.
typedef ClientFactory = XpClient Function(Uri url, String token);

XpClient _defaultClient(Uri url, String token) =>
    XpClient(baseUrl: url, token: token);

/// Why an engine was not added.
enum EngineCheckFailure {
  /// The URL is not an `http(s)` URL with a host.
  invalidUrl,

  /// Nothing answered at the URL.
  unreachable,

  /// Something answered, but not an XPath engine.
  notAnEngine,

  /// The engine speaks another major version of the API.
  apiMismatch,

  /// The engine refused the token.
  tokenRejected,
}

/// An engine could not be added; [failure] says why.
class EngineCheckException implements Exception {
  /// Creates the exception.
  const new(this.failure, {this.detail});

  /// Why.
  final EngineCheckFailure failure;

  /// What the engine or the network said, when it said something.
  final String? detail;

  @override
  String toString() => 'EngineCheckException(${failure.name}): $detail';
}

/// The engines the app knows and the one it shows.
class EngineList extends Equatable {
  /// Creates the list.
  const new({this.engines = const [], this.activeId});

  /// The engines, the local one first.
  final List<EngineProfile> engines;

  /// The id of the engine the app shows, if any.
  final String? activeId;

  /// The engine the app shows: the active one, else the first, else `null`.
  EngineProfile? get active {
    for (final engine in engines) {
      if (engine.id == activeId) return engine;
    }
    return engines.isEmpty ? null : engines.first;
  }

  @override
  List<Object?> get props => [engines, activeId];
}

/// The engines the app knows: their names and URLs in `engines.json` in
/// [directory], their tokens in a [TokenVault].
class EnginesRepository {
  /// Creates the repository.
  new({
    required this.directory,
    required this._vault,
    this._clientFactory = _defaultClient,
  });

  /// The folder of `engines.json`.
  final String directory;

  final TokenVault _vault;
  final ClientFactory _clientFactory;

  File get _file => File(p.join(directory, 'engines.json'));

  /// The saved engines. A missing or unreadable file is an empty list.
  Future<EngineList> load() async {
    if (!_file.existsSync()) return const EngineList();
    try {
      final json =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      final engines = [
        for (final engine in json['engines'] as List<dynamic>)
          EngineProfile.fromJson(engine as Map<String, dynamic>),
      ]..sort((a, b) => (b.isLocal ? 1 : 0) - (a.isLocal ? 1 : 0));
      return EngineList(engines: engines, activeId: json['active'] as String?);
    } on Object {
      return const EngineList();
    }
  }

  /// The token of the engine [engineId], or `null`.
  Future<String?> token(String engineId) => _vault.read(engineId);

  /// Makes [engineId] the engine the app shows.
  Future<void> select(String engineId) async {
    final list = await load();
    await _save(EngineList(engines: list.engines, activeId: engineId));
  }

  /// Saves the engine on this Mac with its app [token] and makes it active.
  ///
  /// It is not checked: right after the app registered it, the engine may
  /// still be starting.
  Future<EngineProfile> saveLocal({
    required String name,
    required String token,
  }) async {
    final profile = EngineProfile(
      id: localEngineId,
      name: name,
      url: localEngineUrl,
    );
    await _vault.write(profile.id, token);
    await _upsert(profile);
    return profile;
  }

  /// Checks the engine at [url] with [token] as `xp connect` does, then saves
  /// it as [name] and makes it active.
  ///
  /// Throws an [EngineCheckException] that says what is wrong; nothing is
  /// saved then.
  Future<EngineProfile> addRemote({
    required String name,
    required String url,
    required String token,
  }) async {
    final parsed = parseEngineUrl(url);
    await check(parsed, token);
    final profile = EngineProfile(
      id: parsed.authority,
      name: name.trim().isEmpty ? parsed.host : name.trim(),
      url: parsed,
    );
    await _vault.write(profile.id, token);
    await _upsert(profile);
    return profile;
  }

  /// Checks that [url] is an engine of this API version
  /// (`GET /health`, `GET /version`) and that it accepts [token]
  /// (`GET /projects`).
  Future<void> check(Uri url, String token) async {
    final client = _clientFactory(url, token);
    try {
      await client.health();
      final version = await client.version();
      if (version.apiVersion != apiVersion) {
        throw EngineCheckException(
          EngineCheckFailure.apiMismatch,
          detail: version.apiVersion,
        );
      }
      try {
        await client.listProjects();
      } on ApiException catch (error) {
        throw EngineCheckException(
          error.isUnauthorized || error.isForbidden
              ? EngineCheckFailure.tokenRejected
              : EngineCheckFailure.notAnEngine,
          detail: error.message,
        );
      }
    } on ConnectionException catch (error) {
      throw EngineCheckException(
        EngineCheckFailure.unreachable,
        detail: error.message,
      );
    } on ApiException catch (error) {
      throw EngineCheckException(
        EngineCheckFailure.notAnEngine,
        detail: error.message,
      );
    } finally {
      client.close();
    }
  }

  /// Forgets the engine [engineId] and its token.
  Future<void> remove(String engineId) async {
    final list = await load();
    await _vault.delete(engineId);
    await _save(
      EngineList(
        engines: [
          for (final engine in list.engines)
            if (engine.id != engineId) engine,
        ],
        activeId: list.activeId == engineId ? null : list.activeId,
      ),
    );
  }

  Future<void> _upsert(EngineProfile profile) async {
    final list = await load();
    await _save(
      EngineList(
        engines: [
          for (final engine in list.engines)
            if (engine.id != profile.id) engine,
          profile,
        ],
        activeId: profile.id,
      ),
    );
  }

  Future<void> _save(EngineList list) async {
    await Directory(directory).create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'active': list.activeId,
        'engines': [for (final engine in list.engines) engine.toJson()],
      }),
    );
    await temporary.rename(_file.path);
  }
}

/// Reads an engine URL: `http` or `https`, with a host. A bare `host:port`
/// is taken as `http://host:port`. Throws an [EngineCheckException] with
/// [EngineCheckFailure.invalidUrl] otherwise.
Uri parseEngineUrl(String text) {
  final trimmed = text.trim();
  final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final url = Uri.tryParse(withScheme);
  if (url == null ||
      (url.scheme != 'http' && url.scheme != 'https') ||
      url.host.isEmpty) {
    throw EngineCheckException(EngineCheckFailure.invalidUrl, detail: text);
  }
  return url;
}
