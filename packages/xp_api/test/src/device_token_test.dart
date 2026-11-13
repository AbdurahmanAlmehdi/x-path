import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final info = TokenInfo(
    id: 'tok_1',
    name: 'xp on MacBook',
    kind: DeviceTokenKind.cli,
    createdAt: DateTime.utc(2026, 10, 25),
  );

  test('CreateTokenRequest round-trips through JSON', () {
    const request = CreateTokenRequest(
      name: 'agent',
      kind: DeviceTokenKind.mcp,
    );

    expect(request.toJson(), {'name': 'agent', 'kind': 'mcp'});
    expect(CreateTokenRequest.fromJson(request.toJson()), request);
  });

  test('TokenInfo round-trips through JSON', () {
    expect(info.toJson(), {
      'id': 'tok_1',
      'name': 'xp on MacBook',
      'kind': 'cli',
      'createdAt': '2026-10-25T00:00:00.000Z',
    });
    expect(TokenInfo.fromJson(info.toJson()), info);
  });

  test('TokenInfo carries the person it belongs to', () {
    final owned = TokenInfo(
      id: 'tok_2',
      name: 'Chrome',
      kind: DeviceTokenKind.web,
      createdAt: DateTime.utc(2026, 11, 13),
      personId: 'per_1',
    );

    expect(owned.toJson(), containsPair('personId', 'per_1'));
    expect(owned.toJson()['kind'], 'web');
    expect(TokenInfo.fromJson(owned.toJson()), owned);
  });

  group('CreatedToken', () {
    final created = CreatedToken(info: info, token: 'xpt_secret');

    test('round-trips through JSON', () {
      expect(created.toJson(), {'info': info.toJson(), 'token': 'xpt_secret'});
      expect(CreatedToken.fromJson(created.toJson()), created);
    });

    test('never prints the token', () {
      expect('$created', isNot(contains('xpt_secret')));
    });
  });

  test('StatusResponse round-trips through JSON', () {
    final status = StatusResponse(token: info, secretsLocked: true);

    expect(status.toJson(), {'token': info.toJson(), 'secretsLocked': true});
    expect(StatusResponse.fromJson(status.toJson()), status);
  });
}
