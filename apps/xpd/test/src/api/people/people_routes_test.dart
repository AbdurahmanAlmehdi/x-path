import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;

  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  Future<RawResponse> send(
    String method,
    String path, {
    Object? body,
    String? token,
  }) => engine.request(
    path,
    method: method,
    token: token,
    body: body == null ? null : jsonEncode(body),
  );

  ErrorResponse errorOf(RawResponse response) =>
      ErrorResponse.fromJson(response.json);

  Future<Person> create(String name, PersonRole role) async {
    final response = await send(
      'POST',
      '/people',
      body: {'name': name, 'role': role.name},
    );
    return Person.fromJson(response.json);
  }

  group('POST /people', () {
    test('adds a person and says where they are', () async {
      final response = await send(
        'POST',
        '/people',
        body: {'name': ' Sam ', 'role': 'developer'},
      );

      expect(response.statusCode, 201, reason: response.body);
      final sam = Person.fromJson(response.json);
      expect(sam.name, 'Sam');
      expect(sam.role, PersonRole.developer);
      expect(response.headers['location'], '/people/${sam.id}');
      expect(await engine.people.get(sam.id), sam);
    });

    test('answers 400 for a bad body, and 409 for a name taken', () async {
      final unknownRole = await send(
        'POST',
        '/people',
        body: {'name': 'Sam', 'role': 'owner'},
      );
      expect(unknownRole.statusCode, 400);
      final blank = await send(
        'POST',
        '/people',
        body: {'name': ' ', 'role': 'viewer'},
      );
      expect(blank.statusCode, 400);
      expect(errorOf(blank).error.message, contains('1 to 80 characters'));
      final taken = await send(
        'POST',
        '/people',
        body: {'name': 'OWNER', 'role': 'viewer'},
      );
      expect(taken.statusCode, 409);
    });

    test('is for admins only', () async {
      final response = await send(
        'POST',
        '/people',
        token: await engine.tokenFor(PersonRole.releaser),
        body: {'name': 'Sam', 'role': 'viewer'},
      );

      expect(response.statusCode, 403);
      expect(
        errorOf(response).error.message,
        'A releaser cannot add a person: it takes the admin role or higher.',
      );
    });
  });

  group('GET /people and /people/{id}', () {
    test('anyone lists and reads people, removed ones included', () async {
      final sam = await create('Sam', PersonRole.viewer);
      await send('DELETE', '/people/${sam.id}');
      final viewer = await engine.tokenFor(PersonRole.viewer);

      final list = await send('GET', '/people', token: viewer);

      expect(list.statusCode, 200);
      final people = PeopleResponse.fromJson(list.json).people;
      expect(people.map((p) => p.name), ['Owner', 'Sam', 'viewer']);
      expect(people[1].isRemoved, isTrue);
      final one = await send('GET', '/people/${sam.id}', token: viewer);
      expect(Person.fromJson(one.json).id, sam.id);
    });

    test('answers 404 for no such person', () async {
      final response = await send('GET', '/people/per_nope');

      expect(response.statusCode, 404);
      expect(errorOf(response).error.code, ApiErrorCode.notFound);
    });
  });

  group('PATCH /people/{id}', () {
    test('renames a person and changes their role', () async {
      final sam = await create('Sam', PersonRole.viewer);

      final response = await send(
        'PATCH',
        '/people/${sam.id}',
        body: {'name': 'Samira', 'role': 'releaser'},
      );

      expect(response.statusCode, 200, reason: response.body);
      final changed = Person.fromJson(response.json);
      expect(changed.name, 'Samira');
      expect(changed.role, PersonRole.releaser);
    });

    test('applies a new role to the next request', () async {
      final developer = await engine.tokenFor(PersonRole.developer);
      Future<int> addPerson() async => (await send(
        'POST',
        '/people',
        token: developer,
        body: {'name': 'Kim', 'role': 'viewer'},
      )).statusCode;
      expect(await addPerson(), 403);

      await send('PATCH', '/people/per_developer', body: {'role': 'admin'});

      expect(await addPerson(), 201);
    });

    test('answers 409 when it would demote the last admin', () async {
      final response = await send(
        'PATCH',
        '/people/${testOwner.id}',
        body: {'role': 'releaser'},
      );

      expect(response.statusCode, 409);
      expect(errorOf(response).error.message, contains('last admin'));
    });

    test('answers 400 for nothing to change, and 404 for no one', () async {
      final empty = await send('PATCH', '/people/${testOwner.id}', body: {});
      expect(empty.statusCode, 400);
      expect(errorOf(empty).error.message, contains('"name", a "role"'));
      final missing = await send(
        'PATCH',
        '/people/per_nope',
        body: {'name': 'x'},
      );
      expect(missing.statusCode, 404);
    });
  });

  group('DELETE /people/{id}', () {
    test('removes a person and revokes their tokens', () async {
      final token = await engine.tokenFor(PersonRole.developer);

      final response = await send('DELETE', '/people/per_developer');

      expect(response.statusCode, 204);
      expect((await engine.people.get('per_developer'))!.isRemoved, isTrue);
      expect((await send('GET', '/me', token: token)).statusCode, 401);
    });

    test('answers 409 for the last admin, and 404 for no one', () async {
      expect((await send('DELETE', '/people/${testOwner.id}')).statusCode, 409);
      expect((await send('DELETE', '/people/per_nope')).statusCode, 404);
    });
  });
}
