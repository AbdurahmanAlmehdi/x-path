@Tags(['contract'])
library;

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/test_engine.dart';

/// Every response the engine gives is checked against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  void expectContract(
    RawResponse response, {
    required String path,
    String method = 'GET',
  }) => contract.expectResponse(
    method: method,
    path: path,
    statusCode: response.statusCode,
    contentType: response.contentType,
    body: response.body,
  );

  test('GET /health', () async {
    final response = await engine.request('/health', token: '');

    expect(response.statusCode, 200);
    expectContract(response, path: '/health');
  });

  test('GET /version', () async {
    final response = await engine.request('/version', token: '');

    expect(response.statusCode, 200);
    expectContract(response, path: '/version');
  });

  group('GET /events', () {
    test('401 without a token', () async {
      final response = await engine.handshake('/events', token: '');

      expect(response.statusCode, 401);
      expectContract(response, path: '/events');
    });

    test('401 with an unknown token', () async {
      final response = await engine.handshake('/events', token: 'xpt_nope');

      expect(response.statusCode, 401);
      expectContract(response, path: '/events');
    });

    test('400 for a bad cursor', () async {
      final response = await engine.handshake('/events?after=-3');

      expect(response.statusCode, 400);
      expectContract(response, path: '/events');
    });

    test('409 for a cursor outside the window', () async {
      final response = await engine.handshake('/events?after=50');

      expect(response.statusCode, 409);
      expectContract(response, path: '/events');
    });

    test('426 for a plain request', () async {
      final response = await engine.request('/events');

      expect(response.statusCode, 426);
      expectContract(response, path: '/events');
    });

    test('101 and frames that match SequencedEvent', () async {
      final stream = await engine.connect(after: 0);
      addTearDown(stream.close);

      // Connecting succeeded, so the engine answered 101.
      contract.expectResponse(
        method: 'GET',
        path: '/events',
        statusCode: 101,
        body: '',
      );
      for (final frame in await stream.take(2)) {
        expect(
          contract.validateSchema('SequencedEvent', frame.toJson()),
          isEmpty,
        );
      }
    });
  });

  test('500 matches the error envelope', () async {
    final broken = await TestEngine.start(
      repository: ThrowingDeviceTokenRepository(),
    );
    addTearDown(broken.close);

    final failing = await broken.request('/events');

    expect(failing.statusCode, 500);
    expectContract(failing, path: '/events');
  });

  test('an unknown route answers in the error envelope', () async {
    final response = await engine.request('/nope');

    expect(response.statusCode, 404);
    expect(contract.validateSchema('ErrorResponse', response.json), isEmpty);
    expect(
      ErrorResponse.fromJson(response.json).error.code,
      ApiErrorCode.notFound,
    );
  });
}
