import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryEngineSettingRepository settings;
  late PublicUrlService service;

  setUp(() {
    settings = InMemoryEngineSettingRepository();
    service = PublicUrlService(settings: settings);
  });

  test('is unset at first', () async {
    expect(await service.read(), const PublicUrl());
    expect(await service.origin(), isNull);
  });

  test('reads what is stored', () async {
    await settings.write(PublicUrlService.key, 'https://a.example');

    expect(await service.origin(), 'https://a.example');
  });

  test('keeps the https origin, without a trailing slash', () async {
    for (final (url, origin) in [
      ('https://XPath.Example.com/', 'https://xpath.example.com'),
      (' https://xpath.example.com:8443 ', 'https://xpath.example.com:8443'),
      ('https://xpath.example.com:443', 'https://xpath.example.com'),
    ]) {
      expect(await service.set(url), PublicUrl(url: origin), reason: url);
      expect(await service.read(), PublicUrl(url: origin));
      expect(await settings.read(PublicUrlService.key), origin);
    }
  });

  test('clears it for null or a blank URL', () async {
    await service.set('https://a.example');

    expect(await service.set(null), const PublicUrl());
    expect(await service.origin(), isNull);
    await service.set('https://a.example');
    expect(await service.set('  '), const PublicUrl());
    expect(await settings.read(PublicUrlService.key), isNull);
  });

  test('refuses anything but an https origin', () async {
    for (final url in [
      'http://xpath.example.com',
      'xpath.example.com',
      'https://',
      'https://user:pass@xpath.example.com',
      'https://xpath.example.com/xpath',
      'https://xpath.example.com?a=1',
      'https://xpath.example.com#a',
      'https://[::1',
    ]) {
      await expectLater(
        service.set(url),
        throwsA(
          isA<PublicUrlInvalidException>().having(
            (e) => e.message,
            'message',
            contains('is not a public URL'),
          ),
        ),
        reason: url,
      );
    }
    expect(await service.origin(), isNull);
  });
}
