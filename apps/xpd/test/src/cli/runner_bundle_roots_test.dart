import 'package:test/test.dart';
import 'package:xpd/xpd.dart';

void main() {
  test('looks in the data directory, then next to the engine bundle', () {
    expect(
      runnerBundleRoots(
        dataDirectory: '/data/xpath',
        version: '1.2.3',
        executable: '/opt/xpath/xpd/bin/xpd',
      ),
      ['/data/xpath/bundles/1.2.3', '/opt/xpath/xpd/runners'],
    );
  });

  test('inside XPath.app, also looks in its resources', () {
    expect(
      runnerBundleRoots(
        dataDirectory: '/data/xpath',
        version: '1.2.3',
        executable: '/Applications/XPath.app/Contents/Helpers/xpd/bin/xpd',
      ),
      [
        '/data/xpath/bundles/1.2.3',
        '/Applications/XPath.app/Contents/Helpers/xpd/runners',
        '/Applications/XPath.app/Contents/Resources/runners',
      ],
    );
  });

  test('looks only in the data directory outside a bundle', () {
    for (final executable in ['', '/usr/local/dart/dart']) {
      expect(
        runnerBundleRoots(
          dataDirectory: '/data/xpath',
          version: '1.2.3',
          executable: executable,
        ),
        ['/data/xpath/bundles/1.2.3'],
        reason: executable,
      );
    }
  });
}
