import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

void main() {
  test('asks for the level Play asks for today unless configured', () async {
    expect(defaultPlayTargetSdk, 36);
    expect(await const ConfiguredPlayRequirements().requiredTargetSdk(), 36);
  });

  test('asks for the level it was given', () async {
    expect(await const ConfiguredPlayRequirements(37).requiredTargetSdk(), 37);
  });
}
