import 'dart:io';

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

  test('FakeEngineAgent unregisters', () async {
    final agent = FakeEngineAgent(current: AgentStatus.enabled);
    expect(await agent.unregister(), AgentStatus.notRegistered);
    expect(agent.unregistrations, 1);
    agent.unregisterError = const MacosServiceException('x', 'y');
    await expectLater(
      agent.unregister(),
      throwsA(isA<MacosServiceException>()),
    );
  });

  test('FakeEngineAgent restarts', () async {
    final agent = FakeEngineAgent(current: AgentStatus.enabled)
      ..restartResult = AgentStatus.requiresApproval;
    expect(await agent.restart(), AgentStatus.requiresApproval);
    expect(await agent.status(), AgentStatus.requiresApproval);
    expect(agent.restarts, 1);
    agent.restartError = const MacosServiceException('x', 'y');
    await expectLater(agent.restart(), throwsA(isA<MacosServiceException>()));
    expect(agent.restarts, 2);
  });

  test('FakeCliLinker unlinks', () async {
    final linker = FakeCliLinker();
    await linker.link();
    expect((await linker.unlink()).state, CliLinkState.notLinked);
    expect(linker.unlinks, 1);
  });

  test('FakeKeychainWiper and FakeDataWiper answer or fail', () async {
    final keychain = FakeKeychainWiper();
    expect(await keychain.wipe(), 3);
    keychain.error = const MacosServiceException('locked', 'Locked.');
    await expectLater(keychain.wipe(), throwsA(isA<MacosServiceException>()));
    expect(keychain.wipes, 2);

    final data = FakeDataWiper();
    expect(await data.wipe(), ['/engine', '/app']);
    data.error = const FileSystemException('busy');
    await expectLater(data.wipe(), throwsA(isA<FileSystemException>()));
    expect(data.wipes, 2);
  });

  test('FakeRunningApp and FakeAppMenu record', () async {
    final app = FakeRunningApp();
    expect(await app.version(), '0.0.1 (1)');
    expect(await app.moveToTrash(), isTrue);
    await app.quit();
    await app.setKeepRunning(keep: true);
    expect(
      (app.movedToTrash, app.quitted, app.keepRunning),
      (true, true, true),
    );

    final menu = FakeAppMenu();
    final chosen = menu.settingsRequests.first;
    menu.chooseSettings();
    await chosen;
  });
}
