import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('settings public-url', () {
    test('shows the URL, or says none is set and how to set one', () async {
      when(() => env.client.publicUrl()).thenAnswer(
        (_) async => const PublicUrl(url: 'https://xpath.example.com'),
      );
      await env.runOk(['settings', 'public-url']);
      expect(
        env.logger.out,
        'Browsers reach the engine at https://xpath.example.com.',
      );

      env.logger.infos.clear();
      when(() => env.client.publicUrl())
          .thenAnswer((_) async => const PublicUrl());
      await env.runOk(['settings', 'public-url']);
      expect(env.logger.out, contains('No public URL is set'));
    });

    test('sets it', () async {
      when(() => env.client.setPublicUrl('https://a.example'))
          .thenAnswer((_) async => const PublicUrl(url: 'https://a.example'));

      await env.runOk(['settings', 'public-url', 'https://a.example']);

      expect(env.logger.out, contains('at https://a.example.'));
    });

    test('--clear forgets it; --json prints it', () async {
      when(() => env.client.setPublicUrl(null))
          .thenAnswer((_) async => const PublicUrl());

      await env.runOk(['--json', 'settings', 'public-url', '--clear']);

      expect(jsonDecode(env.logger.out), <String, dynamic>{});
    });

    test('takes a URL or --clear, not both or two URLs', () async {
      expect(await env.run(['settings', 'public-url', 'a', 'b']), 64);
      expect(await env.run(['settings', 'public-url', 'a', '--clear']), 64);
      verifyNever(() => env.client.setPublicUrl(any()));
    });
  });
}
