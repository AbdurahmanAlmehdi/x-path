import 'package:flutter_test/flutter_test.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  test('macosServicesChannelName is namespaced under ly.abdurahman.xpath', () {
    expect(macosServicesChannelName, 'ly.abdurahman.xpath/macos_services');
  });
}
