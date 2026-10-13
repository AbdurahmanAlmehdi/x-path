import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('Finding', () {
    const finding = Finding(
      severity: FindingSeverity.warning,
      code: 'plist_literal_version',
      message: 'Info.plist hard-codes the build number.',
      fix: r'Use $(FLUTTER_BUILD_NUMBER).',
      path: 'ios/Runner/Info.plist',
      app: '.',
      flavor: 'prod',
    );

    test('serializes every field', () {
      expect(finding.toJson(), {
        'severity': 'warning',
        'code': 'plist_literal_version',
        'message': 'Info.plist hard-codes the build number.',
        'fix': r'Use $(FLUTTER_BUILD_NUMBER).',
        'path': 'ios/Runner/Info.plist',
        'app': '.',
        'flavor': 'prod',
      });
    });

    test('leaves out what it is not about', () {
      const bare = Finding(
        severity: FindingSeverity.info,
        code: 'c',
        message: 'm',
        fix: 'f',
      );

      expect(bare.toJson().keys, ['severity', 'code', 'message', 'fix']);
    });

    test('round-trips through JSON', () {
      expect(Finding.fromJson(finding.toJson()), finding);
    });

    test('names the three severities', () {
      expect(FindingSeverity.values.map((s) => s.name), [
        'error',
        'warning',
        'info',
      ]);
    });
  });
}
