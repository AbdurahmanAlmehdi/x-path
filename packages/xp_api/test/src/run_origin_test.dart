import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  test('RunOrigin round-trips through JSON', () {
    const origin = RunOrigin(
      kind: RunOriginKind.person,
      tokenId: 'tok_1',
      personId: 'per_1',
      personName: 'Sam',
    );

    expect(origin.toJson(), {
      'kind': 'person',
      'tokenId': 'tok_1',
      'personId': 'per_1',
      'personName': 'Sam',
    });
    expect(RunOrigin.fromJson(origin.toJson()), origin);
  });

  test('RunOrigin leaves out what it does not have', () {
    const origin = RunOrigin(kind: RunOriginKind.agent);

    expect(origin.toJson(), {'kind': 'agent'});
    expect(RunOrigin.fromJson(origin.toJson()), origin);
  });
}
