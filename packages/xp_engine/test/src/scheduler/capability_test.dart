// Equality needs two separate objects, which `const` would make one.
// ignore_for_file: prefer_const_constructors

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('Capability', () {
    test('reads its wire name, and nothing else', () {
      expect(Capability.fromWire('ios-linux'), Capability.iosLinux);
      expect(Capability.fromWire('ios-sign|ios-linux'), isNull);
    });
  });

  group('CapabilityNeed', () {
    const both = CapabilityNeed([Capability.iosSign, Capability.iosLinux]);

    test('reads and writes one capability or several joined by |', () {
      expect(CapabilityNeed.parse('ios-sign|ios-linux'), both);
      expect(both.wire, 'ios-sign|ios-linux');
      expect(both.described, 'ios-sign or ios-linux');
      expect(
        CapabilityNeed.parse('flutter'),
        CapabilityNeed(const [Capability.flutter]),
      );
    });

    test('leaves out what this engine does not know', () {
      expect(
        CapabilityNeed.parse('ios-sign|warp'),
        CapabilityNeed(const [Capability.iosSign]),
      );
      expect(
        CapabilityNeed.parseAll(['flutter', 'warp', 'ios-sign|ios-linux']),
        [
          CapabilityNeed(const [Capability.flutter]),
          both,
        ],
      );
    });

    test('ranks a runner by the capability it meets the need with', () {
      expect(both.rankFor({Capability.iosSign, Capability.iosLinux}), 0);
      expect(both.rankFor({Capability.iosLinux}), 1);
      expect(both.rankFor({Capability.flutter}), isNull);
    });

    test('knows an iOS need', () {
      expect(both.isIos, isTrue);
      expect(CapabilityNeed(const [Capability.iosLinux]).isIos, isTrue);
      expect(CapabilityNeed(const [Capability.flutter]).isIos, isFalse);
    });

    test('compares by value', () {
      expect(
        CapabilityNeed(const [Capability.flutter]),
        CapabilityNeed(const [Capability.flutter]),
      );
    });
  });
}
