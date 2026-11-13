import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/people.dart';

void main() {
  late InMemorySignInCodeRepository codes;
  late InMemoryPersonRepository people;
  late InMemoryDeviceTokenRepository tokenRepository;
  late ManualClock clock;
  late TokenService tokens;
  late SignInCodeService service;
  late Person sam;

  final start = DateTime.utc(2026, 11, 14, 9);

  setUp(() async {
    codes = InMemorySignInCodeRepository();
    sam = personWith(PersonRole.developer);
    people = InMemoryPersonRepository([owner, sam]);
    tokenRepository = InMemoryDeviceTokenRepository();
    clock = ManualClock(start);
    tokens = TokenService(
      tokens: tokenRepository,
      people: people,
      clock: clock,
    );
    service = SignInCodeService(
      codes: codes,
      people: people,
      tokens: tokens,
      clock: clock,
    );
  });

  Future<DeviceToken> tokenOf(Person person, DeviceTokenKind kind) async {
    final issued = await tokens.issue(
      name: kind.name,
      kind: kind,
      personId: person.id,
    );
    return issued.token;
  }

  group('issue', () {
    test('makes a 16-character Crockford code that lasts 10 minutes', () async {
      final code = await service.issue(sam.id);

      expect(
        code.code,
        matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){3}[0-9A-HJKMNP-TV-Z]{4}$')),
      );
      expect(code.personId, sam.id);
      expect(code.expiresAt, start.add(const Duration(minutes: 10)));
    });

    test('stores only the hash of the code', () async {
      final code = await service.issue(sam.id);

      final stored = codes.codes.single;
      expect(stored.hash, hashToken(code.code.replaceAll('-', '')));
      expect(stored.personId, sam.id);
      expect(stored.createdAt, start);
      expect(stored.expiresAt, code.expiresAt);
      expect(stored.usedAt, isNull);
      expect('$stored', isNot(contains(code.code.substring(0, 4))));
    });

    test('is different every time, and the same for a seeded random', () async {
      final a = await service.issue(sam.id);
      final b = await service.issue(sam.id);
      expect(a.code, isNot(b.code));

      Future<String> codeFrom(int seed) async => (await SignInCodeService(
        codes: InMemorySignInCodeRepository(),
        people: people,
        tokens: tokens,
        clock: clock,
        random: Random(seed),
      ).issue(sam.id)).code;
      expect(await codeFrom(7), await codeFrom(7));
    });

    test("deletes the person's unused codes and every expired one", () async {
      final first = await service.issue(sam.id);
      final ownerCode = await service.issue(owner.id);
      clock.advance(const Duration(minutes: 11));
      final second = await service.issue(sam.id);

      expect(codes.codes.single.personId, sam.id);
      await expectLater(
        service.signIn(first.code),
        throwsA(isA<SignInRejectedException>()),
      );
      await expectLater(
        service.signIn(ownerCode.code),
        throwsA(isA<SignInRejectedException>()),
      );
      expect((await service.signIn(second.code)).token.personId, sam.id);
    });

    test('refuses a removed or unknown person', () async {
      await people.update(sam.copyWith(removedAt: start));

      expect(service.issue(sam.id), throwsA(isA<PersonNotFoundException>()));
      expect(
        service.issue('per_nope'),
        throwsA(isA<PersonNotFoundException>()),
      );
    });
  });

  group('issueFor', () {
    test('lets an admin issue for anyone', () async {
      final admin = await tokenOf(owner, DeviceTokenKind.app);

      final code = await service.issueFor(admin.withPerson(owner), sam.id);

      expect(code.personId, sam.id);
    });

    test("lets a person's app or cli token issue for themself only", () async {
      for (final kind in [DeviceTokenKind.app, DeviceTokenKind.cli]) {
        final token = (await tokenOf(sam, kind)).withPerson(sam);

        expect((await service.issueFor(token, sam.id)).personId, sam.id);
        expect(
          () => service.issueFor(token, owner.id),
          throwsA(isA<SignInForbiddenException>()),
        );
      }
    });

    test('refuses an agent and a browser, even for themself', () async {
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.web]) {
        final token = (await tokenOf(sam, kind)).withPerson(sam);

        expect(
          () => service.issueFor(token, sam.id),
          throwsA(isA<SignInForbiddenException>()),
        );
      }
    });
  });

  group('signIn', () {
    test('exchanges a code for a web token of its person, once', () async {
      final code = await service.issue(sam.id);

      final issued = await service.signIn(code.code);

      expect(issued.token.kind, DeviceTokenKind.web);
      expect(issued.token.personId, sam.id);
      expect(await tokens.authenticate(issued.secret), isNotNull);
      expect(codes.codes.single.usedAt, start);
      await expectLater(
        service.signIn(code.code),
        throwsA(isA<SignInRejectedException>()),
      );
    });

    test(
      'takes the code without dashes, in lower case, with O, I and L',
      () async {
        final code = (await service.issue(sam.id)).code;
        final typed = code
            .replaceAll('-', ' ')
            .toLowerCase()
            .replaceAll('0', 'o')
            .replaceAll('1', 'l');

        expect((await service.signIn(typed)).token.personId, sam.id);
      },
    );

    test('refuses an expired code like an unknown one', () async {
      final code = await service.issue(sam.id);
      clock.advance(SignInCodeService.lifetime);

      await expectLater(
        service.signIn(code.code),
        throwsA(
          isA<SignInRejectedException>().having(
            (e) => e.message,
            'message',
            contains('wrong, used or expired'),
          ),
        ),
      );
    });

    test('refuses the code of a person removed since', () async {
      final code = await service.issue(sam.id);
      await people.update(sam.copyWith(removedAt: start));

      await expectLater(
        service.signIn(code.code),
        throwsA(isA<SignInRejectedException>()),
      );
    });

    test('refuses what cannot be a code', () async {
      for (final code in ['', 'ABCD', 'U' * 16, 'A' * 65, '!' * 16]) {
        await expectLater(
          service.signIn(code),
          throwsA(isA<SignInRejectedException>()),
          reason: code,
        );
      }
    });

    test('takes no code after 20 wrong ones in 10 minutes', () async {
      for (var i = 0; i < SignInCodeService.failureLimit; i++) {
        await expectLater(
          service.signIn('0000-0000-0000-000$i'.substring(0, 19)),
          throwsA(isA<SignInRejectedException>()),
        );
        clock.advance(const Duration(seconds: 10));
      }
      final code = await service.issue(sam.id);

      await expectLater(
        service.signIn(code.code),
        throwsA(
          isA<SignInRateLimitedException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(minutes: 6, seconds: 40),
          ),
        ),
      );

      clock.advance(const Duration(minutes: 6, seconds: 40));
      expect((await service.signIn(code.code)).token.personId, sam.id);
    });
  });

  test('the exceptions say what happened', () {
    expect(
      '${const SignInRateLimitedException(Duration.zero)}',
      contains('Too many wrong sign-in codes'),
    );
    expect('${const SignInForbiddenException()}', contains('Only an admin'));
  });
}
