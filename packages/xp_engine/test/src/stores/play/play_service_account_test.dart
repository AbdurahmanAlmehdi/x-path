import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

const _pem = '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n';

String _json([Map<String, Object?> overrides = const {}]) => jsonEncode(
  {
    'type': 'service_account',
    'project_id': 'ignored',
    'client_email': 'xpath@project.iam.gserviceaccount.com',
    'private_key': _pem,
    'private_key_id': 'key1',
    'token_uri': 'https://oauth2.example.com/token',
    'client_id': 'ignored',
    ...overrides,
  }..removeWhere((_, value) => value == null),
);

void main() {
  group('PlayServiceAccount', () {
    test('reads the key file Google gives out and ignores the rest', () {
      final account = PlayServiceAccount.fromSecret(_json());

      expect(account.clientEmail, 'xpath@project.iam.gserviceaccount.com');
      expect(account.privateKey, _pem);
      expect(account.privateKeyId, 'key1');
      expect(account.tokenUri, 'https://oauth2.example.com/token');
    });

    test('defaults the token endpoint and needs no key id or type', () {
      final account = PlayServiceAccount.fromSecret(
        _json({'token_uri': null, 'private_key_id': null, 'type': null}),
      );

      expect(account.tokenUri, googleTokenUri);
      expect(account.privateKeyId, isNull);
    });

    test('round trips through the secret form', () {
      final account = PlayServiceAccount.fromSecret(_json());

      expect(PlayServiceAccount.fromSecret(account.toSecret()), account);
      expect(
        PlayServiceAccount.fromSecret(
          const PlayServiceAccount(
            clientEmail: 'a@b.c',
            privateKey: _pem,
          ).toSecret(),
        ).privateKeyId,
        isNull,
      );
    });

    test('rejects what is not a service account key', () {
      const failures = {
        'nope': 'not JSON',
        '[]': 'must be a JSON object',
        '{"type": "authorized_user"}': 'not a service account key',
        '{"client_email": " "}': '"client_email"',
        '{"client_email": "a@b.c"}': '"private_key"',
        '{"client_email": "a@b.c", "private_key": "k", "token_uri": "x"}':
            '"token_uri"',
      };
      for (final MapEntry(key: text, value: reason) in failures.entries) {
        expect(
          () => PlayServiceAccount.fromSecret(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(reason),
            ),
          ),
          reason: text,
        );
      }
    });

    test('never prints the private key', () {
      final account = PlayServiceAccount.fromSecret(_json());

      expect(
        account.toString(),
        'PlayServiceAccount(xpath@project.iam.gserviceaccount.com)',
      );
    });
  });
}
