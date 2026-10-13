import 'package:test/test.dart';
import 'package:xp_secrets/xp_secrets.dart';

void main() {
  test('secretsSummary names the engine', () {
    expect(secretsSummary(), 'xp_secrets for xp_engine serving API v1');
  });
}
