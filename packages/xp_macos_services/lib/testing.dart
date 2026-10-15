/// Fakes of the macOS services, for the tests of the app. None of them
/// touches macOS.
library;

import 'dart:async';

import 'package:xp_macos_services/xp_macos_services.dart';

/// An [EngineAgent] that answers [registerResult] and records what it was
/// asked.
class FakeEngineAgent implements EngineAgent {
  /// Creates the fake.
  new({
    this.current = AgentStatus.notRegistered,
    this.registerResult = AgentStatus.enabled,
    this.registerError,
  });

  /// What [status] answers; [register] sets it.
  AgentStatus current;

  /// What [register] answers.
  AgentStatus registerResult;

  /// What [register] throws, if anything.
  Exception? registerError;

  /// How often [register] was called.
  int registrations = 0;

  /// How often the settings were opened.
  int settingsOpened = 0;

  @override
  Future<AgentStatus> status() async => current;

  @override
  Future<AgentStatus> register() async {
    registrations++;
    final error = registerError;
    if (error != null) throw error;
    return current = registerResult;
  }

  @override
  Future<void> openLoginItemsSettings() async => settingsOpened++;
}

/// A [Keychain] in memory.
class FakeKeychain implements Keychain {
  /// Creates the fake with [items].
  new([Map<String, String>? items]) : items = {...?items};

  /// The items.
  final Map<String, String> items;

  /// What every call throws, if anything (a locked Keychain).
  Exception? error;

  @override
  Future<String?> read(String account) async {
    if (error case final error?) throw error;
    return items[account];
  }

  @override
  Future<void> write(String account, String value) async {
    if (error case final error?) throw error;
    items[account] = value;
  }

  @override
  Future<void> delete(String account) async {
    if (error case final error?) throw error;
    items.remove(account);
  }
}

/// A [CliLinker] that answers [result].
class FakeCliLinker implements CliLinker {
  /// Creates the fake.
  new({
    this.current = const CliLink(CliLinkState.notLinked),
    this.result = const CliLink(CliLinkState.linked, path: '/usr/local/bin/xp'),
  });

  /// What [status] answers; [link] sets it.
  CliLink current;

  /// What [link] answers.
  CliLink result;

  /// How often [link] was called.
  int links = 0;

  @override
  Future<CliLink> status() async => current;

  @override
  Future<CliLink> link() async {
    links++;
    return current = result;
  }
}

/// A [ToolChecker] that answers [results].
class FakeToolChecker implements ToolChecker {
  /// Creates the fake.
  new([List<ToolCheck>? results])
    : results =
          results ??
          [
            for (final tool in Tool.values)
              ToolCheck(tool, path: '/bin/${tool.name}'),
          ];

  /// What [check] answers.
  List<ToolCheck> results;

  @override
  Future<List<ToolCheck>> check() async => results;
}

/// A [LocalEngine] that hands out [token].
class FakeLocalEngine implements LocalEngine {
  /// Creates the fake.
  new({this.isBundled = true, this.token = 'xpt_local', this.error});

  @override
  bool isBundled;

  /// What [createAppToken] answers.
  String token;

  /// What [createAppToken] throws, if anything.
  Exception? error;

  /// The names tokens were made for.
  final names = <String>[];

  @override
  Future<String> createAppToken({required String name}) async {
    names.add(name);
    if (error case final error?) throw error;
    return token;
  }
}

/// [NeedsYouAlerts] that records what it was asked and lets the test play
/// the owner's clicks with [act].
class FakeNeedsYouAlerts implements NeedsYouAlerts {
  /// The notices shown, oldest first.
  final notices = <ApprovalNotice>[];

  /// The approvals whose notification was withdrawn, oldest first.
  final withdrawn = <String>[];

  /// Every content of the menu bar extra, oldest first.
  final menus = <MenuBarContent>[];

  final _actions = StreamController<NeedsYouAction>.broadcast();

  /// Plays [action] as if the owner clicked it.
  void act(NeedsYouAction action) => _actions.add(action);

  @override
  Future<void> notify(ApprovalNotice notice) async => notices.add(notice);

  @override
  Future<void> withdraw(String approvalId) async => withdrawn.add(approvalId);

  @override
  Future<void> updateMenuBar(MenuBarContent content) async =>
      menus.add(content);

  @override
  Stream<NeedsYouAction> get actions => _actions.stream;
}
