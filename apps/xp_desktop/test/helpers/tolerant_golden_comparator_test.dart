import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'tolerant_golden_comparator.dart';

/// A white 100 x 100 PNG with [dots] black pixels in its first rows.
Future<Uint8List> _png({int dots = 0}) async {
  const size = 100;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  final black = ui.Paint()
    ..color = const ui.Color(0xFF000000)
    ..isAntiAlias = false;
  for (var i = 0; i < dots; i++) {
    canvas.drawRect(
      ui.Rect.fromLTWH((i % size).toDouble(), (i ~/ size).toDouble(), 1, 1),
      black,
    );
  }
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late TolerantGoldenComparator comparator;
  final golden = Uri.parse('golden.png');

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('xp_golden_');
    File(p.join(directory.path, 'golden.png')).writeAsBytesSync(await _png());
    comparator = TolerantGoldenComparator(
      Uri.file(p.join(directory.path, 'golden_test.dart')),
    );
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('every test file compares goldens with the tolerance', () {
    expect(goldenFileComparator, isA<TolerantGoldenComparator>());
    expect(
      (goldenFileComparator as TolerantGoldenComparator).tolerance,
      goldenTolerance,
    );
  });

  test('passes an identical image', () async {
    expect(await comparator.compare(await _png(), golden), isTrue);
  });

  test('passes a difference up to the tolerance', () async {
    // 10 of 10,000 pixels is 0.1%.
    expect(await comparator.compare(await _png(dots: 10), golden), isTrue);
  });

  test('fails a difference above the tolerance and writes the diff', () async {
    final image = await _png(dots: 11);
    await expectLater(
      comparator.compare(image, golden),
      throwsA(
        isA<FlutterError>().having(
          (error) => error.message,
          'message',
          contains('0.11%, 11px diff detected'),
        ),
      ),
    );
    expect(Directory(p.join(directory.path, 'failures')).existsSync(), isTrue);
  });
}
