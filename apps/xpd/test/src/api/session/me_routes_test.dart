import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;

  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  test('GET /me answers the person, the token and everything an admin may '
      'do', () async {
    final response = await engine.request('/me');

    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    final me = Me.fromJson(response.json);
    expect(me.person, testOwner);
    expect(me.token.kind, DeviceTokenKind.app);
    expect(me.token.personId, testOwner.id);
    expect(me.permissions, Permission.values);
  });

  test("GET /me gives an admin's mcp token develop only", () async {
    final response = await engine.request(
      '/me',
      token: await engine.tokenFor(PersonRole.admin, kind: DeviceTokenKind.mcp),
    );

    expect(Me.fromJson(response.json).permissions, [Permission.develop]);
  });

  test('GET /me gives a viewer nothing to change', () async {
    final response = await engine.request(
      '/me',
      token: await engine.tokenFor(PersonRole.viewer),
    );

    final me = Me.fromJson(response.json);
    expect(me.person.role, PersonRole.viewer);
    expect(me.permissions, isEmpty);
  });
}
