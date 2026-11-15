import 'package:equatable/equatable.dart';

/// A sign-in code as the engine stores it: never the code, only its hash.
class SignInCodeRecord extends Equatable {
  /// Creates the record.
  const new({
    required this.hash,
    required this.personId,
    required this.createdAt,
    required this.expiresAt,
    this.usedAt,
  });

  /// Hex SHA-256 of the code, without its dashes.
  final String hash;

  /// The person the code signs in.
  final String personId;

  /// When it was issued, in UTC.
  final DateTime createdAt;

  /// When it stops working, in UTC.
  final DateTime expiresAt;

  /// When it was used, in UTC, or `null` while it is not.
  final DateTime? usedAt;

  @override
  List<Object?> get props => [hash, personId, createdAt, expiresAt, usedAt];
}

/// Where sign-in codes are kept (ADR 0018).
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class SignInCodeRepository {
  /// Stores [code], which is new.
  Future<void> add(SignInCodeRecord code);

  /// Deletes the codes of the person [personId] that were not used.
  Future<void> deleteUnusedOf(String personId);

  /// Deletes every person's codes that expired before [before], used or
  /// not.
  Future<void> deleteExpired({required DateTime before});

  /// Uses the code with [hash] up at [at], in one step: only a code that is
  /// neither used nor expired is. Returns the person it signs in, or `null`
  /// when there was no such code to use.
  Future<String?> use(String hash, {required DateTime at});
}

/// A [SignInCodeRepository] that forgets everything on exit.
class InMemorySignInCodeRepository implements SignInCodeRepository {
  final _codes = <String, SignInCodeRecord>{};

  /// Every code kept, for tests.
  List<SignInCodeRecord> get codes => List.unmodifiable(_codes.values);

  @override
  Future<void> add(SignInCodeRecord code) async => _codes[code.hash] = code;

  @override
  Future<void> deleteUnusedOf(String personId) async => _codes.removeWhere(
    (_, code) => code.personId == personId && code.usedAt == null,
  );

  @override
  Future<void> deleteExpired({required DateTime before}) async =>
      _codes.removeWhere((_, code) => code.expiresAt.isBefore(before));

  @override
  Future<String?> use(String hash, {required DateTime at}) async {
    final code = _codes[hash];
    if (code == null || code.usedAt != null || !at.isBefore(code.expiresAt)) {
      return null;
    }
    _codes[hash] = SignInCodeRecord(
      hash: code.hash,
      personId: code.personId,
      createdAt: code.createdAt,
      expiresAt: code.expiresAt,
      usedAt: at,
    );
    return code.personId;
  }
}
