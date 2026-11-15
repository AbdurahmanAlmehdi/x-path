import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/app/app_services.dart';

void main() {
  group('openWithSystem', () {
    final url = Uri.parse('http://127.0.0.1:7480/sign-in#code=ABCD');

    test('opens the link with open', () async {
      final calls = <List<String>>[];

      await openWithSystem(
        url,
        run: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(1, 0, '', '');
        },
      );

      expect(calls, [
        ['/usr/bin/open', '$url'],
      ]);
    });

    test('throws when open fails, without the link', () async {
      await expectLater(
        openWithSystem(
          url,
          run: (_, _) async => ProcessResult(1, 1, '', 'no browser'),
        ),
        throwsA(
          isA<ProcessException>()
              .having((e) => e.errorCode, 'errorCode', 1)
              .having((e) => '$e', 'toString', isNot(contains('ABCD'))),
        ),
      );
    });
  });
}
