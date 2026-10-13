import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late NoPowerAssertion inner;
  late ReferenceCountedPowerAssertion assertion;

  setUp(() {
    inner = NoPowerAssertion();
    assertion = ReferenceCountedPowerAssertion(inner);
  });

  test('holds the inner assertion from the first hold', () async {
    await assertion.hold();
    await assertion.hold();

    expect(inner.holds, 1);
    expect(assertion.holders, 2);
  });

  test('releases it with the last release', () async {
    await assertion.hold();
    await assertion.hold();

    await assertion.release();
    expect(inner.releases, 0);

    await assertion.release();
    expect(inner.releases, 1);
    expect(assertion.holders, 0);
  });

  test('holds again after it was released', () async {
    await assertion.hold();
    await assertion.release();
    await assertion.hold();

    expect(inner.holds, 2);
  });

  test('ignores a release without a hold', () async {
    await assertion.release();

    expect(inner.releases, 0);
    expect(assertion.holders, 0);
  });
}
