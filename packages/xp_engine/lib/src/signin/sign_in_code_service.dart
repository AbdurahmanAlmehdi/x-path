import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/access/access_policy.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/people/person_exceptions.dart';
import 'package:xp_engine/src/people/person_repository.dart';
import 'package:xp_engine/src/signin/sign_in_code_repository.dart';
import 'package:xp_engine/src/signin/sign_in_exceptions.dart';
import 'package:xp_engine/src/tokens/device_token.dart';
import 'package:xp_engine/src/tokens/token_service.dart';

/// Issues the one-time codes a browser signs in to the web dashboard with,
/// and exchanges a code for a browser session's token (ADR 0018, D10).
///
/// A code is 16 Crockford base32 characters (80 random bits), shown as
/// `XXXX-XXXX-XXXX-XXXX`. It works once, for [lifetime]; issuing one deletes
/// the person's unused codes; only its SHA-256 is stored. After
/// [failureLimit] wrong codes within [failureWindow], in total, no code is
/// taken until the oldest of them leaves the window.
class SignInCodeService {
  /// Creates the service.
  ///
  /// `random` is for tests; it must be cryptographically secure otherwise.
  new({
    required this._codes,
    required this._people,
    required this._tokens,
    required this._clock,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// How long a code works.
  static const lifetime = Duration(minutes: 10);

  /// How many wrong codes [failureWindow] takes before it takes none.
  static const failureLimit = 20;

  /// The window [failureLimit] counts wrong codes in.
  static const failureWindow = Duration(minutes: 10);

  /// Crockford's base32 alphabet: no I, L, O or U.
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static const _length = 16;

  final SignInCodeRepository _codes;
  final PersonRepository _people;
  final TokenService _tokens;
  final Clock _clock;
  final Random _random;
  final _failures = <DateTime>[];

  /// Issues a code for the person [personId], for the token [asker] (D9):
  /// an admin's for anyone, a person's own `app` or `cli` token for them.
  ///
  /// Throws a [SignInForbiddenException] if [asker] may not, and a
  /// [PersonNotFoundException] if there is no such active person.
  Future<SignInCode> issueFor(DeviceToken asker, String personId) {
    if (!AccessPolicy.mayIssueSignInCode(asker, personId)) {
      throw const SignInForbiddenException();
    }
    return issue(personId);
  }

  /// Issues a code for the person [personId], deleting their unused ones:
  /// what `xpd person code` does on the engine machine.
  ///
  /// Throws a [PersonNotFoundException] if there is no such active person.
  Future<SignInCode> issue(String personId) async {
    final person = await _people.get(personId);
    if (person == null || person.isRemoved) {
      throw PersonNotFoundException(personId);
    }
    final now = _clock.now();
    final plain = String.fromCharCodes([
      for (var i = 0; i < _length; i++)
        _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
    ]);
    final expiresAt = now.add(lifetime);
    await _codes.deleteUnused(person.id, expiredBefore: now);
    await _codes.add(
      SignInCodeRecord(
        hash: hashToken(plain),
        personId: person.id,
        createdAt: now,
        expiresAt: expiresAt,
      ),
    );
    return SignInCode(
      code: [for (var i = 0; i < _length; i += 4) plain.substring(i, i + 4)]
          .join('-'),
      personId: person.id,
      expiresAt: expiresAt,
    );
  }

  /// Uses [code] up and issues the `web` token of its person: a browser
  /// session (D11).
  ///
  /// The code may have its dashes or not, in any case; `O` reads as `0`,
  /// and `I` and `L` as `1`.
  ///
  /// Throws a [SignInRejectedException] for a code that is unknown, used or
  /// expired, or whose person was removed, and a
  /// [SignInRateLimitedException] while too many wrong codes were given.
  Future<IssuedToken> signIn(String code) async {
    final now = _clock.now();
    final since = now.subtract(failureWindow);
    _failures.removeWhere((at) => !at.isAfter(since));
    if (_failures.length >= failureLimit) {
      throw SignInRateLimitedException(
        _failures.first.add(failureWindow).difference(now),
      );
    }
    final plain = _plain(code);
    final personId = plain == null
        ? null
        : await _codes.use(hashToken(plain), at: now);
    final person = personId == null ? null : await _people.get(personId);
    if (person == null || person.isRemoved) {
      _failures.add(now);
      throw const SignInRejectedException();
    }
    return await _tokens.issueWeb(personId: person.id);
  }

  /// [code] without dashes or spaces, in upper case, with the letters
  /// Crockford reads as digits read so; `null` if it cannot be a code.
  static String? _plain(String code) {
    if (code.length > 64) return null;
    final plain = code
        .toUpperCase()
        .replaceAll(_separators, '')
        .replaceAll('O', '0')
        .replaceAll(_one, '1');
    if (plain.length != _length) return null;
    return plain.split('').every(_alphabet.contains) ? plain : null;
  }

  static final _separators = RegExp(r'[\s-]');
  static final _one = RegExp('[IL]');
}
