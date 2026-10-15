import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(macosServicesChannel, (call) async {
          calls.add(call);
          return answer(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(macosServicesChannel, null);
  });

  group('MethodChannelEngineAgent', () {
    const agent = MethodChannelEngineAgent();

    test('reads the status of the agent', () async {
      answer = (_) => 'requiresApproval';
      expect(await agent.status(), AgentStatus.requiresApproval);
      answer = (_) => 'something new';
      expect(await agent.status(), AgentStatus.notFound);
      expect(calls.map((call) => call.method), ['agentStatus', 'agentStatus']);
    });

    test('registers the agent', () async {
      answer = (_) => 'enabled';
      expect(await agent.register(), AgentStatus.enabled);
      expect(calls.single.method, 'agentRegister');
    });

    test('reports what macOS refused', () async {
      answer = (_) => throw PlatformException(
        code: 'register_failed',
        message: 'Operation not permitted',
      );
      await expectLater(
        agent.register(),
        throwsA(
          isA<MacosServiceException>().having(
            (error) => error.code,
            'code',
            'register_failed',
          ),
        ),
      );
    });

    test('opens Login Items', () async {
      await agent.openLoginItemsSettings();
      expect(calls.single.method, 'openLoginItems');
    });

    test('names the label of the engine', () {
      expect(engineAgentLabel, 'ly.abdurahman.xpath.xpd');
    });
  });

  group('MethodChannelKeychain', () {
    const keychain = MethodChannelKeychain();

    test('reads, writes and deletes items of the app', () async {
      answer = (call) => call.method == 'keychainRead' ? 'xpt_1' : null;
      expect(await keychain.read('engine.local'), 'xpt_1');
      await keychain.write('engine.local', 'xpt_2');
      await keychain.delete('engine.local');
      expect(calls.map((call) => call.method), [
        'keychainRead',
        'keychainWrite',
        'keychainDelete',
      ]);
      expect(calls.map((call) => call.arguments), [
        {'account': 'engine.local'},
        {'account': 'engine.local', 'value': 'xpt_2'},
        {'account': 'engine.local'},
      ]);
      expect(appKeychainService, 'ly.abdurahman.xpath.app');
    });

    test('reports a locked Keychain', () async {
      answer = (_) => throw PlatformException(code: 'locked');
      await expectLater(
        keychain.read('engine.local'),
        throwsA(
          isA<MacosServiceException>().having(
            (error) => error.code,
            'code',
            'locked',
          ),
        ),
      );
    });
  });
}
