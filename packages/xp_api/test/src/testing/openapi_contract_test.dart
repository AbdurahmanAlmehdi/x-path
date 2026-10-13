import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

const _spec = r'''
openapi: 3.1.0
info: {title: t, version: "1"}
paths:
  /things/{id}:
    get:
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Thing"}
        "4XX":
          $ref: "#/components/responses/Failure"
        default:
          description: anything else, no body
  /empty:
    post:
      responses:
        "204": {description: nothing}
  /text:
    get:
      responses:
        "200":
          description: text
          content:
            text/plain:
              schema: {type: string}
components:
  responses:
    Failure:
      description: failure
      content:
        application/json:
          schema: {$ref: "#/components/schemas/Failure"}
  schemas:
    Thing:
      type: object
      required: [name, tags]
      properties:
        name: {type: string}
        tags:
          type: array
          items: {$ref: "#/components/schemas/Tag"}
    Tag: {type: string, minLength: 1}
    Failure:
      type: object
      required: [reason]
      properties:
        reason: {type: string}
''';

void main() {
  final contract = OpenApiContract.parse(_spec);

  List<String> validate({
    String method = 'GET',
    String path = '/things/7',
    int statusCode = 200,
    String body = '{"name":"a","tags":["x"]}',
    String? contentType = 'application/json; charset=utf-8',
  }) => contract.validateResponse(
    method: method,
    path: path,
    statusCode: statusCode,
    body: body,
    contentType: contentType,
  );

  group('validateResponse', () {
    test('accepts a response that matches, with a path template', () {
      expect(validate(), isEmpty);
    });

    test('reports a body that breaks the schema, through nested refs', () {
      expect(
        validate(body: '{"name":"a","tags":[""]}'),
        everyElement(contains('GET /things/7 200')),
      );
      expect(validate(body: '{"name":"a","tags":[""]}'), isNotEmpty);
      expect(validate(body: '{"tags":[]}'), isNotEmpty);
    });

    test('reports a path that is not in the spec', () {
      expect(validate(path: '/nope'), ['GET /nope is not in openapi.yaml']);
    });

    test('reports a method that is not in the spec', () {
      expect(validate(method: 'delete'), [
        'DELETE /things/7 is not in openapi.yaml',
      ]);
    });

    test('falls back to the 4XX range, resolving a response ref', () {
      expect(validate(statusCode: 404, body: '{"reason":"gone"}'), isEmpty);
      expect(validate(statusCode: 404, body: '{}'), isNotEmpty);
    });

    test('falls back to default, which declares no body', () {
      expect(validate(statusCode: 500, body: ''), isEmpty);
      expect(validate(statusCode: 500, body: '{}'), [
        'GET /things/7 500 declares no body but got one',
      ]);
    });

    test('reports a status the operation does not declare', () {
      expect(validate(path: '/empty', method: 'POST'), [
        'POST /empty does not declare status 200',
      ]);
    });

    test('accepts an empty body for a response without content', () {
      expect(
        validate(path: '/empty', method: 'POST', statusCode: 204, body: ''),
        isEmpty,
      );
    });

    test('does not check bodies that are not JSON', () {
      expect(
        validate(path: '/text', body: 'hi', contentType: 'text/plain'),
        isEmpty,
      );
    });

    test('reports a missing or non-JSON content type', () {
      expect(validate(contentType: null), [
        'GET /things/7 200 expects application/json, got null',
      ]);
      expect(validate(contentType: 'text/html'), [
        'GET /things/7 200 expects application/json, got text/html',
      ]);
    });

    test('reports a body that is not JSON', () {
      expect(validate(body: '{oops'), [contains('body is not JSON')]);
    });
  });

  group('validateSchema', () {
    test('checks a value against a component schema', () {
      expect(contract.validateSchema('Failure', {'reason': 'x'}), isEmpty);
      expect(
        contract.validateSchema('Failure', <String, dynamic>{}),
        isNotEmpty,
      );
    });
  });

  group('expectResponse', () {
    test('passes silently when the response matches', () {
      contract.expectResponse(
        method: 'GET',
        path: '/things/1',
        statusCode: 200,
        body: '{"name":"a","tags":[]}',
        contentType: 'application/json',
      );
    });

    test('fails with every problem', () {
      expect(
        () => contract.expectResponse(
          method: 'GET',
          path: '/things/1',
          statusCode: 200,
          body: '{}',
          contentType: 'application/json',
        ),
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('differs from openapi.yaml'),
              contains('GET /things/1'),
            ),
          ),
        ),
      );
    });
  });

  group('the shipped openapi.yaml', () {
    late OpenApiContract shipped;

    setUpAll(() async => shipped = await OpenApiContract.load());

    test('documents /health, /version and /events', () {
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/health',
          statusCode: 200,
          body: jsonEncode(const HealthResponse().toJson()),
          contentType: 'application/json',
        ),
        isEmpty,
      );
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/version',
          statusCode: 200,
          body: jsonEncode(
            const VersionResponse(version: '1', apiVersion: '1').toJson(),
          ),
          contentType: 'application/json',
        ),
        isEmpty,
      );
      expect(
        shipped.validateResponse(
          method: 'GET',
          path: '/events',
          statusCode: 101,
          body: '',
        ),
        isEmpty,
      );
    }, tags: 'contract');

    test('documents the project endpoints and their error responses', () {
      final unauthorized = jsonEncode(
        ErrorResponse.of(ApiErrorCode.unauthorized, 'm').toJson(),
      );

      for (final (method, path) in [
        ('GET', '/projects'),
        ('POST', '/projects'),
        ('GET', '/projects/prj_1'),
        ('PATCH', '/projects/prj_1'),
        ('DELETE', '/projects/prj_1'),
        ('POST', '/projects/prj_1/scan'),
      ]) {
        expect(
          shipped.validateResponse(
            method: method,
            path: path,
            statusCode: 401,
            body: unauthorized,
            contentType: 'application/json',
          ),
          isEmpty,
          reason: '$method $path',
        );
      }
    }, tags: 'contract');

    test('has an error code for every ApiErrorCode', () {
      for (final code in ApiErrorCode.values) {
        final body = ErrorResponse.of(code, 'm').toJson();

        expect(shipped.validateSchema('ErrorResponse', body), isEmpty);
      }
    }, tags: 'contract');

    test('describes every event the engine can send', () {
      for (final event in <EngineEvent>[
        const EngineStarted(version: '0.0.1', apiVersion: '1'),
        const StreamOpened(),
        const ProjectAdded(projectId: 'prj_1', fullName: 'o/r'),
        const ProjectScanned(projectId: 'prj_1', errors: 0, warnings: 1),
        const ProjectRemoved(projectId: 'prj_1'),
      ]) {
        final json = SequencedEvent(
          seq: 1,
          at: DateTime.utc(2026),
          event: event,
        ).toJson();

        expect(shipped.validateSchema('SequencedEvent', json), isEmpty);
      }
    }, tags: 'contract');
  });
}
