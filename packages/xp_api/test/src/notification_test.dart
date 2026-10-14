import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('NotificationKind', () {
    test('uses snake_case on the wire and reads it back', () {
      for (final kind in NotificationKind.values) {
        expect(kind.wire, matches(RegExp(r'^[a-z]+(_[a-z]+)*$')));
        expect(NotificationKind.fromWire(kind.wire), kind);
      }
      expect(NotificationKind.minVersionReminder.wire, 'min_version_reminder');
    });

    test('does not know a name from a newer engine', () {
      expect(NotificationKind.fromWire('from_the_future'), isNull);
    });
  });

  group('NotificationLevel', () {
    test('reads its wire names back', () {
      expect(NotificationLevel.values.map((level) => level.wire), [
        'info',
        'success',
        'warning',
        'error',
      ]);
      for (final level in NotificationLevel.values) {
        expect(NotificationLevel.fromWire(level.wire), level);
      }
      expect(NotificationLevel.fromWire('loud'), isNull);
    });
  });
}
