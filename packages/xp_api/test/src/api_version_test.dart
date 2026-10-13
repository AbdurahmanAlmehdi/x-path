import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  test('apiVersion is the first major version', () {
    expect(apiVersion, '1');
  });
}
