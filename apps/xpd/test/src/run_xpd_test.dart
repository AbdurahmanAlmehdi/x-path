import 'package:test/test.dart';
import 'package:xpd/xpd.dart';

void main() {
  group('runXpd', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    test('--version prints the version and the API version', () {
      final code = runXpd(['--version'], out: out, err: err);

      expect(code, 0);
      expect(out.toString(), 'xpd $packageVersion (API v1)\n');
      expect(err.toString(), isEmpty);
    });

    test('anything else prints usage and fails', () {
      final code = runXpd(['serve'], out: out, err: err);

      expect(code, 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), 'Usage: xpd --version\n');
    });
  });
}
