import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/runners/runner_record.dart';

/// Where runners are kept (the `runner` table).
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class RunnerRepository {
  /// Stores a new runner.
  Future<void> add(RunnerRecord runner);

  /// The runner [id], or `null`.
  Future<RunnerRecord?> get(String id);

  /// The runner called [name], revoked ones included, or `null`.
  Future<RunnerRecord?> findByName(String name);

  /// The runner whose credential is the device token [tokenId], or `null`.
  Future<RunnerRecord?> findByToken(String tokenId);

  /// Every runner, oldest first.
  Future<List<RunnerRecord>> list();

  /// Replaces the stored runner that has the id of [runner].
  ///
  /// Throws a `StateError` if there is none.
  Future<void> update(RunnerRecord runner);
}

/// A [RunnerRepository] that forgets everything on exit.
class InMemoryRunnerRepository implements RunnerRepository {
  final _runners = <String, RunnerRecord>{};

  @override
  Future<void> add(RunnerRecord runner) async {
    if (_runners.containsKey(runner.id) ||
        _runners.values.any((other) => other.name == runner.name)) {
      throw StateError('Runner ${runner.id} (${runner.name}) exists.');
    }
    _runners[runner.id] = runner;
  }

  @override
  Future<RunnerRecord?> get(String id) async => _runners[id];

  @override
  Future<RunnerRecord?> findByName(String name) async =>
      _runners.values.where((runner) => runner.name == name).firstOrNull;

  @override
  Future<RunnerRecord?> findByToken(String tokenId) async =>
      _runners.values.where((runner) => runner.tokenId == tokenId).firstOrNull;

  @override
  Future<List<RunnerRecord>> list() async => _runners.values.toList();

  @override
  Future<void> update(RunnerRecord runner) async {
    if (!_runners.containsKey(runner.id)) {
      throw StateError('There is no runner ${runner.id}.');
    }
    _runners[runner.id] = runner;
  }
}

/// A pairing token as the engine stores it: never the secret, only its hash
/// (D-08).
class PairingTokenRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.hash,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    this.usedAt,
  });

  /// Identifies the token without revealing it.
  final String id;

  /// Hex SHA-256 of the secret.
  final String hash;

  /// The name of the runner it pairs.
  final String name;

  /// The id of the device token that asked for it.
  final String createdBy;

  /// When it was made.
  final DateTime createdAt;

  /// When it stops working.
  final DateTime expiresAt;

  /// When it was exchanged, or `null` while it can be.
  final DateTime? usedAt;

  @override
  List<Object?> get props => [
    id,
    hash,
    name,
    createdBy,
    createdAt,
    expiresAt,
    usedAt,
  ];
}

/// Where pairing tokens are kept (the `pairing_token` table).
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class PairingTokenRepository {
  /// Stores a new token.
  Future<void> add(PairingTokenRecord token);

  /// The token whose secret has the SHA-256 [hash], or `null`.
  Future<PairingTokenRecord?> findByHash(String hash);

  /// Marks the token [id] used at [at], in one compare-and-set: it succeeds
  /// for the first caller only, and only while the token is unused and not
  /// expired at [at]. Returns whether this call did it.
  Future<bool> consume(String id, {required DateTime at});

  /// Deletes the tokens that expired before [before], and those used before
  /// it.
  Future<void> prune({required DateTime before});
}

/// A [PairingTokenRepository] that forgets everything on exit.
class InMemoryPairingTokenRepository implements PairingTokenRepository {
  final _tokens = <String, PairingTokenRecord>{};

  @override
  Future<void> add(PairingTokenRecord token) async => _tokens[token.id] = token;

  @override
  Future<PairingTokenRecord?> findByHash(String hash) async =>
      _tokens.values.where((token) => token.hash == hash).firstOrNull;

  @override
  Future<bool> consume(String id, {required DateTime at}) async {
    final token = _tokens[id];
    if (token == null ||
        token.usedAt != null ||
        !at.isBefore(token.expiresAt)) {
      return false;
    }
    _tokens[id] = PairingTokenRecord(
      id: token.id,
      hash: token.hash,
      name: token.name,
      createdBy: token.createdBy,
      createdAt: token.createdAt,
      expiresAt: token.expiresAt,
      usedAt: at,
    );
    return true;
  }

  @override
  Future<void> prune({required DateTime before}) async {
    _tokens.removeWhere(
      (_, token) =>
          token.expiresAt.isBefore(before) ||
          (token.usedAt?.isBefore(before) ?? false),
    );
  }
}
