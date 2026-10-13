import 'dart:io';

import 'package:test/test.dart';
import 'package:xp/src/version.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(packageVersion, declared);
  });
}
