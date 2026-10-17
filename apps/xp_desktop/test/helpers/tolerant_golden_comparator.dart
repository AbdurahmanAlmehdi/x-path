import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The share of pixels a golden may differ by and still pass: 0.1%, about
/// 1,300 pixels of a 1440 x 900 golden.
///
/// The goldens are drawn on the owner's Mac. GitHub's macOS runner draws the
/// same text with slightly different anti-aliasing: up to 0.03% (408 pixels)
/// on the first runs. A changed label, colour or layout moves far more pixels
/// than this, so the goldens still catch real regressions.
const goldenTolerance = 0.001;

/// A [LocalFileComparator] that passes when at most [tolerance] of the pixels
/// differ, so font rasterisation differences between Macs do not fail a
/// golden. Above it, it fails with the usual output in `failures/`.
class TolerantGoldenComparator extends LocalFileComparator {
  /// Compares the goldens next to [testFile], allowing [tolerance] (a share
  /// of the pixels, from 0 to 1).
  new(super.testFile, {this.tolerance = goldenTolerance});

  /// The share of pixels that may differ, from 0 to 1.
  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
