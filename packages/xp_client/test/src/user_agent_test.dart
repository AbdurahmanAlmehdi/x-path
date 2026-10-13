import 'package:test/test.dart';
import 'package:xp_client/xp_client.dart';

void main() {
  test('clientUserAgent names the API version', () {
    expect(clientUserAgent(), 'xp_client (API v1)');
  });
}
