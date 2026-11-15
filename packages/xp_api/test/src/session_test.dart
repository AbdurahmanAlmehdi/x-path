import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final code = SignInCode(
    code: 'ABCD-EFGH-JKMN-PQRS',
    personId: 'per_1',
    expiresAt: DateTime.utc(2026, 11, 14, 9, 10),
  );

  group('SignInCode', () {
    test('round-trips through JSON', () {
      expect(code.toJson(), {
        'code': 'ABCD-EFGH-JKMN-PQRS',
        'personId': 'per_1',
        'expiresAt': '2026-11-14T09:10:00.000Z',
      });
      expect(SignInCode.fromJson(code.toJson()), code);
    });

    test('puts the code in the fragment of the sign-in page', () {
      expect(
        code.signInUrl(Uri.parse('http://127.0.0.1:7480/api/v1?x=1')),
        Uri.parse('http://127.0.0.1:7480/sign-in#code=ABCD-EFGH-JKMN-PQRS'),
      );
      expect(
        code.signInUrl(Uri.parse('https://xpath.example.com')),
        Uri.parse('https://xpath.example.com/sign-in#code=ABCD-EFGH-JKMN-PQRS'),
      );
    });

    test('never prints the code', () {
      expect('$code', isNot(contains('ABCD')));
    });
  });

  group('SignInRequest', () {
    test('round-trips through JSON and needs a code', () {
      const request = SignInRequest(code: 'abcd');

      expect(request.toJson(), {'code': 'abcd'});
      expect(SignInRequest.fromJson(request.toJson()), request);
      expect(() => SignInRequest.fromJson(const {}), throwsA(isA<Exception>()));
      expect('$request', isNot(contains('abcd')));
    });
  });

  group('PublicUrl', () {
    test('round-trips through JSON, without a url when none is set', () {
      const set = PublicUrl(url: 'https://xpath.example.com');

      expect(set.toJson(), {'url': 'https://xpath.example.com'});
      expect(PublicUrl.fromJson(set.toJson()), set);
      expect(const PublicUrl().toJson(), isEmpty);
    });

    test('a request to set it needs the url key, which may be null', () {
      const clear = SetPublicUrlRequest(url: null);

      expect(clear.toJson(), {'url': null});
      expect(SetPublicUrlRequest.fromJson(clear.toJson()), clear);
      expect(
        () => SetPublicUrlRequest.fromJson(const {}),
        throwsA(isA<Exception>()),
      );
    });
  });
}
