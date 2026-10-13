import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  test('engineSummary names the API version', () {
    expect(engineSummary(), 'xp_engine serving API v1');
  });
}
