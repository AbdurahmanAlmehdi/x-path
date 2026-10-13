import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('HealthResponse', () {
    test('is ok by default', () {
      expect(const HealthResponse().toJson(), {'status': 'ok'});
    });

    test('round-trips through JSON', () {
      expect(
        HealthResponse.fromJson(const HealthResponse().toJson()),
        const HealthResponse(),
      );
    });
  });

  group('VersionResponse', () {
    const response = VersionResponse(version: '1.2.3', apiVersion: '1');

    test('serializes both versions', () {
      expect(response.toJson(), {'version': '1.2.3', 'apiVersion': '1'});
    });

    test('round-trips through JSON', () {
      expect(VersionResponse.fromJson(response.toJson()), response);
    });
  });

  group('DeviceTokenKind', () {
    test('names the four kinds of the data model', () {
      expect(DeviceTokenKind.values.map((k) => k.name), [
        'app',
        'cli',
        'mcp',
        'runner',
      ]);
    });
  });
}
