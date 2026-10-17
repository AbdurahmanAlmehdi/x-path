import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/tolerant_golden_comparator.dart';

/// Runs before every test file: compares goldens with a small tolerance for
/// font rasterisation (see [goldenTolerance]).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final comparator = goldenFileComparator;
  if (comparator is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      comparator.basedir.resolve('flutter_test_config.dart'),
    );
  }
  await testMain();
}
