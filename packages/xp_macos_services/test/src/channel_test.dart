import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  test('macosServicesChannelName is namespaced under ly.abdurahman.xpath', () {
    expect(macosServicesChannelName, 'ly.abdurahman.xpath/macos_services');
    expect(macosServicesChannel.name, macosServicesChannelName);
  });

  test('MacosServiceException reads a platform error', () {
    final error = MacosServiceException.fromPlatform(
      PlatformException(code: 'locked', message: 'The Keychain is locked.'),
    );
    expect(error.code, 'locked');
    expect(error.message, 'The Keychain is locked.');
    expect(error.toString(), contains('locked'));
    expect(
      MacosServiceException.fromPlatform(PlatformException(code: 'x')).message,
      'x',
    );
  });

  test('AppBundle finds the helpers from the executable', () {
    final bundle = AppBundle.fromExecutable(
      '/Applications/XPath.app/Contents/MacOS/XPath',
    );
    expect(bundle.path, '/Applications/XPath.app');
    expect(
      bundle.xpdExecutable,
      '/Applications/XPath.app/Contents/Helpers/xpd/bin/xpd',
    );
    expect(
      bundle.xpExecutable,
      '/Applications/XPath.app/Contents/Helpers/xp/bin/xp',
    );
  });
}
