import 'package:flutter_test/flutter_test.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

void main() {
  test('FakeEngineAgent registers and records', () async {
    final agent = FakeEngineAgent();
    expect(await agent.status(), AgentStatus.notRegistered);
    expect(await agent.register(), AgentStatus.enabled);
    expect(await agent.status(), AgentStatus.enabled);
    await agent.openLoginItemsSettings();
    expect((agent.registrations, agent.settingsOpened), (1, 1));
    agent.registerError = const MacosServiceException('x', 'y');
    await expectLater(agent.register(), throwsA(isA<MacosServiceException>()));
  });

  test('FakeKeychain keeps items and can be locked', () async {
    final keychain = FakeKeychain({'a': '1'});
    expect(await keychain.read('a'), '1');
    await keychain.write('b', '2');
    await keychain.delete('a');
    expect(keychain.items, {'b': '2'});
    keychain.error = const MacosServiceException('locked', 'Locked.');
    await expectLater(
      keychain.read('b'),
      throwsA(isA<MacosServiceException>()),
    );
    await expectLater(
      keychain.write('b', '3'),
      throwsA(isA<MacosServiceException>()),
    );
    await expectLater(
      keychain.delete('b'),
      throwsA(isA<MacosServiceException>()),
    );
  });

  test('FakeCliLinker links', () async {
    final linker = FakeCliLinker();
    expect((await linker.status()).state, CliLinkState.notLinked);
    expect((await linker.link()).state, CliLinkState.linked);
    expect((await linker.status()).state, CliLinkState.linked);
    expect(linker.links, 1);
  });

  test('FakeToolChecker finds every tool by default', () async {
    expect((await FakeToolChecker().check()).every((c) => c.found), isTrue);
    expect(await FakeToolChecker(const []).check(), isEmpty);
  });

  test('FakeLocalEngine hands out its token', () async {
    final engine = FakeLocalEngine();
    expect(engine.isBundled, isTrue);
    expect(await engine.createAppToken(name: 'XPath app'), 'xpt_local');
    expect(engine.names, ['XPath app']);
    engine.error = const LocalEngineException('no');
    await expectLater(
      engine.createAppToken(name: 'x'),
      throwsA(isA<LocalEngineException>()),
    );
  });
}
