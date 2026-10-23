import 'dart:convert';
import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/repositories/engine_setting_repository.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/runners/runner_exceptions.dart';
import 'package:xp_engine/src/runners/runner_hub.dart';
import 'package:xp_engine/src/runners/runner_record.dart';
import 'package:xp_engine/src/runners/runner_repository.dart';
import 'package:xp_engine/src/tokens/device_token.dart';
import 'package:xp_engine/src/tokens/token_service.dart';

final _namePattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$');

/// Pairs, lists and revokes runners (D-08).
///
/// A runner is paired with a pairing token: single use, valid for 15
/// minutes, made by the owner (`app` and `cli` tokens only: a paired runner
/// receives signing material, so an agent must not be able to pair one).
/// Exchanging it creates the runner and its credential, a device token of
/// kind `runner`; the engine keeps only the hashes of both secrets.
///
/// The owner sets the runner URL, the address runners reach the engine at,
/// and every pairing token carries it, so the pairing command works on the
/// runner machine.
class RunnerService {
  /// Creates the service. [random] is for tests; it must be cryptographically
  /// secure otherwise.
  new({
    required this._runners,
    required this._pairing,
    required this._tokens,
    required this._presence,
    required this._settings,
    required this._events,
    required this._clock,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// The key of the runner URL in the engine settings.
  static const runnerUrlKey = 'runner_url';

  /// How long a pairing token works.
  static const pairingLifetime = Duration(minutes: 15);

  /// Marks a string as an XPath pairing token.
  static const pairingPrefix = 'xpp_';

  final RunnerRepository _runners;
  final PairingTokenRepository _pairing;
  final TokenService _tokens;
  final RunnerPresence _presence;
  final EngineSettingRepository _settings;
  final EventLog _events;
  final Clock _clock;
  final Random _random;

  /// Makes a pairing token for a runner called [name], for the token [by].
  ///
  /// Throws a [RunnerForbiddenException] unless [by] is an `app` or `cli`
  /// token, a [RunnerInvalidException] for a name that is blank or has
  /// characters other than letters, digits, spaces, `.`, `_` and `-` (at most
  /// 64), and a [RunnerNameTakenException] if a runner has the name.
  Future<PairingToken> createPairingToken({
    required String name,
    required DeviceToken by,
  }) async {
    _requireOwner(by, 'pair a runner');
    final trimmed = name.trim();
    if (!_namePattern.hasMatch(trimmed)) {
      throw const RunnerInvalidException(
        'A runner name has 1 to 64 letters, digits, spaces, dots, '
        'underscores or dashes, and starts with a letter or digit.',
      );
    }
    if (await _runners.findByName(trimmed) != null) {
      throw RunnerNameTakenException(trimmed);
    }
    final now = _clock.now();
    await _pairing.prune(before: now.subtract(const Duration(days: 1)));
    final secret = pairingPrefix + _base64Url(_bytes(32));
    final expiresAt = now.add(pairingLifetime);
    await _pairing.add(
      PairingTokenRecord(
        id: 'pair_${_hex(_bytes(8))}',
        hash: hashToken(secret),
        name: trimmed,
        createdBy: by.id,
        createdAt: now,
        expiresAt: expiresAt,
      ),
    );
    return PairingToken(
      token: secret,
      name: trimmed,
      expiresAt: expiresAt,
      engineUrl: await _settings.read(runnerUrlKey),
    );
  }

  /// The runner URL, with the warning its address deserves.
  Future<RunnerUrl> runnerUrl() async {
    final url = await _settings.read(runnerUrlKey);
    return RunnerUrl(url: url, warning: url == null ? null : _warning(url));
  }

  /// Sets the runner URL to [url], or clears it for `null`, for the token
  /// [by].
  ///
  /// The URL must be an absolute `http` or `https` URL with a host and no
  /// user info, query or fragment; a trailing `/` is dropped. A plain `http`
  /// URL that is not on this machine or a tailnet is accepted with a warning:
  /// the socket carries signing material.
  ///
  /// Throws a [RunnerForbiddenException] unless [by] is an `app` or `cli`
  /// token, and a [RunnerInvalidException] for a URL that is not one.
  Future<RunnerUrl> setRunnerUrl(String? url, {required DeviceToken by}) async {
    _requireOwner(by, 'change the runner URL');
    if (url == null || url.trim().isEmpty) {
      await _settings.write(runnerUrlKey, null);
      return const RunnerUrl();
    }
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null ||
        !parsed.hasScheme ||
        !const {'http', 'https'}.contains(parsed.scheme) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw RunnerInvalidException(
        '"$url" is not a runner URL. Give the absolute http or https address '
        'runners reach the engine at, for example '
        'https://mac.tailnet.ts.net, without a user name or password.',
      );
    }
    final text = parsed.toString().replaceFirst(RegExp(r'/+$'), '');
    await _settings.write(runnerUrlKey, text);
    return RunnerUrl(url: text, warning: _warning(text));
  }

  /// Why [url] may be a bad idea, or `null`.
  static String? _warning(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'http' || _private(uri.host)) return null;
    return 'This plain http address is not on this machine or a tailnet, '
        'and the runner connection carries signing material. Put TLS in '
        'front of the engine, or use Tailscale or an SSH tunnel.';
  }

  /// Whether [host] is this machine or a tailnet: loopback, `100.64.0.0/10`
  /// or a `*.ts.net` name.
  static bool _private(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name.endsWith('.ts.net')) return true;
    if (name == '::1' || name == '[::1]') return true;
    final octets = name.split('.').map(int.tryParse).toList();
    if (octets.length != 4 || octets.contains(null)) return false;
    final [first!, second!, _, _] = octets;
    return first == 127 || (first == 100 && second >= 64 && second < 128);
  }

  /// Exchanges the pairing token [secret] for a runner and its credential.
  ///
  /// Throws a [PairingRejectedException] if the token is unknown, expired or
  /// used, and a [RunnerNameTakenException] if a runner got the name since.
  Future<PairRunnerResponse> pair(String secret) async {
    final record = secret.startsWith(pairingPrefix)
        ? await _pairing.findByHash(hashToken(secret))
        : null;
    if (record == null) {
      throw const PairingRejectedException('Unknown pairing token.');
    }
    final now = _clock.now();
    if (record.usedAt != null) {
      throw const PairingRejectedException(
        'This pairing token was used already. Create another.',
      );
    }
    if (!now.isBefore(record.expiresAt)) {
      throw const PairingRejectedException(
        'This pairing token expired. Create another; they last 15 minutes.',
      );
    }
    if (await _runners.findByName(record.name) != null) {
      throw RunnerNameTakenException(record.name);
    }
    // The compare-and-set: two exchanges of one token make one runner.
    if (!await _pairing.consume(record.id, at: now)) {
      throw const PairingRejectedException(
        'This pairing token was used already. Create another.',
      );
    }
    final credential = await _tokens.issue(
      name: record.name,
      kind: DeviceTokenKind.runner,
    );
    final runner = RunnerRecord(
      id: 'rnr_${_hex(_bytes(8))}',
      name: record.name,
      tokenId: credential.token.id,
      createdAt: now,
    );
    await _runners.add(runner);
    _events.append(RunnerPaired(runnerId: runner.id, name: runner.name));
    return PairRunnerResponse(
      runner: runner.toRunner(status: RunnerStatus.offline),
      token: credential.secret,
    );
  }

  /// Every runner, oldest first.
  Future<List<Runner>> list() async => [
    for (final record in await _runners.list()) _describe(record),
  ];

  /// The runner [id].
  ///
  /// Throws a [RunnerNotFoundException] if there is none.
  Future<Runner> get(String id) async => _describe(await _require(id));

  /// Revokes the runner [id] for the token [by] (D-08): its credential stops
  /// working, its connection closes and its leases end, each job by the loss
  /// rule. Revoking a revoked runner changes nothing.
  ///
  /// Throws a [RunnerForbiddenException] unless [by] is an `app` or `cli`
  /// token and a [RunnerNotFoundException] if there is no such runner.
  Future<Runner> revoke(String id, {required DeviceToken by}) async {
    _requireOwner(by, 'revoke a runner');
    var runner = await _require(id);
    if (runner.isRevoked) return _describe(runner);
    runner = runner.copyWith(revokedAt: _clock.now());
    await _tokens.revoke(runner.tokenId);
    await _runners.update(runner);
    await _presence.revoked(runner);
    _events.append(RunnerRevoked(runnerId: runner.id, name: runner.name));
    return _describe(runner);
  }

  /// The runner whose credential is [token], for the connection it opens.
  ///
  /// Throws a [RunnerForbiddenException] if the token is not a runner's.
  Future<RunnerRecord> runnerFor(DeviceToken token) async {
    if (token.kind != DeviceTokenKind.runner) {
      throw RunnerForbiddenException(
        'Only a runner token connects as a runner; this is a '
        '${token.kind.name} token.',
      );
    }
    final runner = await _runners.findByToken(token.id);
    if (runner == null || runner.isRevoked) {
      throw const RunnerForbiddenException(
        'This runner token belongs to no runner. Pair the runner with a '
        'pairing token.',
      );
    }
    return runner;
  }

  Future<RunnerRecord> _require(String id) async =>
      await _runners.get(id) ?? (throw RunnerNotFoundException(id));

  Runner _describe(RunnerRecord record) => record.toRunner(
    status: record.isRevoked
        ? RunnerStatus.revoked
        : _presence.statusOf(record.id),
    jobIds: _presence.jobsOf(record.id),
    missing: _presence.missingOf(record.id),
  );

  void _requireOwner(DeviceToken by, String action) {
    if (by.kind != DeviceTokenKind.app && by.kind != DeviceTokenKind.cli) {
      throw RunnerForbiddenException(
        'A ${by.kind.name} token cannot $action. Only app and cli tokens '
        'can: a paired runner receives signing material.',
      );
    }
  }

  List<int> _bytes(int length) =>
      List.generate(length, (_) => _random.nextInt(256));

  String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
