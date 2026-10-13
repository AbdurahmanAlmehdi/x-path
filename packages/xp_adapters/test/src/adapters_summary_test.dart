import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

void main() {
  test('adaptersSummary names the engine', () {
    expect(adaptersSummary(), 'xp_adapters for xp_engine serving API v1');
  });
}
