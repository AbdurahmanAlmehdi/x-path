import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/test_engine.dart';
import '../../helpers/workflow_helpers.dart';

void main() {
  group('routePermissions', () {
    late TestEngine engine;

    setUp(() async => engine = await TestEngine.start());
    tearDown(() => engine.close());

    String key(ApiRoute route) => '${route.method} ${route.path}';

    test('lists every mutating route the router serves', () {
      final unlisted = [
        for (final route in engine.server.routes)
          if (route.method != 'GET' &&
              !routePermissions.containsKey(key(route)))
            key(route),
      ];

      expect(unlisted, isEmpty, reason: 'add them to route_permissions.dart');
    });

    test('lists no route the router does not serve', () {
      final served = {for (final route in engine.server.routes) key(route)};

      expect(
        routePermissions.keys.where((listed) => !served.contains(listed)),
        isEmpty,
      );
    });
  });

  group('the role matrix over the API', () {
    late TestEngine engine;
    late WorkflowClient client;
    late String workflowId;

    setUp(() async {
      engine = await TestEngine.start();
      client = await WorkflowClient.add(engine);
      workflowId = await client.create('echo', echoWorkflow);
    });
    tearDown(() => engine.close());

    Future<RawResponse> dispatch(String token) => engine.request(
      '${client.base}/$workflowId/dispatch',
      method: 'POST',
      token: token,
    );

    test('a viewer gets 403 on dispatch, and a developer may', () async {
      final viewer = await dispatch(await engine.tokenFor(PersonRole.viewer));

      expect(viewer.statusCode, 403);
      expect(
        ErrorResponse.fromJson(viewer.json).error.message,
        'A viewer cannot dispatch a workflow: it takes the developer role or '
        'higher.',
      );
      final developer = await dispatch(
        await engine.tokenFor(PersonRole.developer),
      );
      expect(developer.statusCode, 202, reason: developer.body);
    });

    test('a developer gets 403 on approve', () async {
      final response = await engine.request(
        '/approvals/apr_1/approve',
        method: 'POST',
        token: await engine.tokenFor(PersonRole.developer),
      );

      expect(response.statusCode, 403);
      expect(
        ErrorResponse.fromJson(response.json).error.message,
        contains('takes the releaser role'),
      );
    });

    test("an admin's mcp token may develop and nothing else", () async {
      final agent = await engine.tokenFor(
        PersonRole.admin,
        kind: DeviceTokenKind.mcp,
      );

      expect((await dispatch(agent)).statusCode, 202);
      final response = await engine.request(
        '/people',
        method: 'POST',
        token: agent,
        body: '{"name": "Sam", "role": "viewer"}',
      );
      expect(response.statusCode, 403);
      expect(
        ErrorResponse.fromJson(response.json).error.message,
        'A mcp token cannot add a person: only the app or `xp` do.',
      );
    });

    test('an agent of a developer adds and changes a project, and only an '
        'admin removes one', () async {
      final fresh = await TestEngine.start();
      addTearDown(fresh.close);
      fresh.folders['/work/app'] = projectFiles;
      final agent = await fresh.tokenFor(
        PersonRole.developer,
        kind: DeviceTokenKind.mcp,
      );

      final added = await fresh.request(
        '/projects',
        method: 'POST',
        token: agent,
        body: '{"path": "/work/app"}',
      );
      expect(added.statusCode, 201, reason: added.body);
      final path = '/projects/${added.json['id']}';
      final changed = await fresh.request(
        path,
        method: 'PATCH',
        token: agent,
        body: '{"defaultBaseBranch": "dev"}',
      );
      expect(changed.statusCode, 200, reason: changed.body);
      final removed = await fresh.request(
        path,
        method: 'DELETE',
        token: await fresh.tokenFor(PersonRole.releaser),
      );
      expect(removed.statusCode, 403);
      expect(
        ErrorResponse.fromJson(removed.json).error.message,
        contains('cannot remove a project: it takes the admin role'),
      );
    });

    test(
      'a viewer still reads, and checks a workflow it cannot save',
      () async {
        final viewer = await engine.tokenFor(PersonRole.viewer);

        expect(
          (await engine.request('/projects', token: viewer)).statusCode,
          200,
        );
        final validate = await engine.request(
          '/workflows/validate',
          method: 'POST',
          token: viewer,
          body: '{"yaml": "schema: 1"}',
        );
        expect(validate.statusCode, 200, reason: validate.body);
      },
    );

    test('a path no route has is still 404', () async {
      final response = await engine.request(
        '/nothing/here',
        method: 'POST',
        token: await engine.tokenFor(PersonRole.viewer),
      );

      expect(response.statusCode, 404);
    });
  });

  group('permissionMiddleware', () {
    DeviceToken tokenOf(PersonRole role) =>
        DeviceToken(
          id: 'tok_1',
          name: 'n',
          kind: DeviceTokenKind.cli,
          hash: 'h',
          createdAt: DateTime.utc(2026),
          personId: 'per_1',
        ).withPerson(
          Person(
            id: 'per_1',
            name: 'n',
            role: role,
            createdAt: DateTime.utc(2026),
          ),
        );

    Future<Response> send(PersonRole role, String method, String path) {
      final router = ApiRouter()
        ..post(
          '/things/<id>/poke',
          (Request request, String id) => Response.ok(id),
        )
        ..put('/listed', (Request request) => Response.ok('listed'));
      final handler = const Pipeline()
          .addMiddleware(
            (inner) =>
                (request) => inner(
                  request.change(context: {'xpd.deviceToken': tokenOf(role)}),
                ),
          )
          .addMiddleware(
            permissionMiddleware(
              router.routes,
              table: const {
                'PUT /listed': .needs(Permission.develop, 'touch it'),
              },
            ),
          )
          .addHandler(router.call);
      return Future.value(
        handler(Request(method, Uri.parse('http://localhost$path'))),
      );
    }

    test('closes a mutating route the table does not list to all but '
        'admins', () async {
      final refused = await send(PersonRole.releaser, 'POST', '/things/1/poke');

      expect(refused.statusCode, 403);
      expect(
        await refused.readAsString(),
        contains('cannot use a route the engine does not list'),
      );
      final admin = await send(PersonRole.admin, 'POST', '/things/1/poke');
      expect(await admin.readAsString(), '1');
    });

    test('lets a listed route through with its permission', () async {
      expect((await send(PersonRole.viewer, 'PUT', '/listed')).statusCode, 403);
      expect(
        (await send(PersonRole.developer, 'PUT', '/listed')).statusCode,
        200,
      );
    });
  });
}
