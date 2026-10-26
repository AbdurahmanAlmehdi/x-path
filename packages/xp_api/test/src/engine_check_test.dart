import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  const missing = EngineCheck(
    name: 'android',
    state: CheckState.missing,
    detail: 'no JDK: java not found',
    fix: 'install JDK 17 or set JAVA_HOME',
  );

  test('EngineCheck round-trips through JSON and leaves out what is null', () {
    expect(missing.toJson(), {
      'name': 'android',
      'state': 'missing',
      'detail': 'no JDK: java not found',
      'fix': 'install JDK 17 or set JAVA_HOME',
    });
    expect(EngineCheck.fromJson(missing.toJson()), missing);
    expect(const EngineCheck(name: 'flutter', state: CheckState.ok).toJson(), {
      'name': 'flutter',
      'state': 'ok',
    });
  });

  group('DoctorResponse', () {
    test('round-trips through JSON', () {
      const response = DoctorResponse([missing]);

      expect(response.toJson(), {
        'checks': [missing.toJson()],
      });
      expect(DoctorResponse.fromJson(response.toJson()), response);
    });

    test('is healthy when nothing is missing', () {
      expect(const DoctorResponse([missing]).healthy, isFalse);
      expect(
        const DoctorResponse([
          EngineCheck(name: 'flutter', state: CheckState.ok),
          EngineCheck(name: 'ssh', state: CheckState.skipped),
        ]).healthy,
        isTrue,
      );
    });
  });
}
