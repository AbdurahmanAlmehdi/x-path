import 'package:flutter/services.dart';
import 'package:xp_macos_services/src/channel.dart';

/// The launchd label of the engine the app bundles, and the name of its
/// plist in `XPath.app/Contents/Library/LaunchAgents` (ADR 0005).
const engineAgentLabel = 'ly.abdurahman.xpath.xpd';

/// Where the LaunchAgent of the bundled engine stands with `SMAppService`.
enum AgentStatus {
  /// Not registered: the engine does not run.
  notRegistered,

  /// Registered and allowed: launchd runs the engine at login and keeps it
  /// running.
  enabled,

  /// Registered, but the user has to allow it in System Settings ▸ General ▸
  /// Login Items before it runs.
  requiresApproval,

  /// This build has no LaunchAgent plist (or no engine) to register: a
  /// development build before the engine is bundled (Phase 18b).
  notFound,

  /// The macOS is older than 13, which has no `SMAppService`.
  unsupported,
}

/// Registers the engine the app bundles as a LaunchAgent of the user
/// (`SMAppService.agent`, D-10). With the app installed, the app owns the
/// label `ly.abdurahman.xpath.xpd`; `xpd install-service` is for Macs
/// without the app.
abstract interface class EngineAgent {
  /// Where the agent stands now.
  Future<AgentStatus> status();

  /// Registers the agent (it starts at once and at every login) and returns
  /// where it stands then. Registering again is harmless.
  ///
  /// Throws a [MacosServiceException] when macOS refuses.
  Future<AgentStatus> register();

  /// Unregisters the agent: launchd stops the engine and does not start it
  /// again. Returns where it stands then. Unregistering an agent that is not
  /// registered is harmless.
  ///
  /// Throws a [MacosServiceException] when macOS refuses.
  Future<AgentStatus> unregister();

  /// Starts the agent again, for an engine that does not answer, and returns
  /// where it stands then. An agent macOS reads as [AgentStatus.enabled]
  /// may still be gone from launchd (a `launchctl bootout`), or name a copy
  /// of the app that moved: it is unregistered (stopping the engine, if it
  /// runs) and registered again from this app. One that
  /// [AgentStatus.requiresApproval] is left alone; anything else is
  /// registered.
  ///
  /// Throws a [MacosServiceException] when macOS refuses.
  Future<AgentStatus> restart();

  /// Opens System Settings at Login Items, where the user allows an agent
  /// that [AgentStatus.requiresApproval].
  Future<void> openLoginItemsSettings();
}

/// An [EngineAgent] over the platform channel of the macOS runner.
class MethodChannelEngineAgent implements EngineAgent {
  /// Creates the agent over [channel].
  const new({this.channel = macosServicesChannel});

  /// The channel.
  final MethodChannel channel;

  static AgentStatus _parse(String? wire) => AgentStatus.values.firstWhere(
    (status) => status.name == wire,
    orElse: () => AgentStatus.notFound,
  );

  @override
  Future<AgentStatus> status() async =>
      _parse(await channel.invokeMethod<String>('agentStatus'));

  @override
  Future<AgentStatus> register() async {
    try {
      return _parse(await channel.invokeMethod<String>('agentRegister'));
    } on PlatformException catch (error) {
      throw MacosServiceException.fromPlatform(error);
    }
  }

  @override
  Future<AgentStatus> unregister() async {
    try {
      return _parse(await channel.invokeMethod<String>('agentUnregister'));
    } on PlatformException catch (error) {
      throw MacosServiceException.fromPlatform(error);
    }
  }

  @override
  Future<AgentStatus> restart() async {
    try {
      return _parse(await channel.invokeMethod<String>('agentRestart'));
    } on PlatformException catch (error) {
      throw MacosServiceException.fromPlatform(error);
    }
  }

  @override
  Future<void> openLoginItemsSettings() =>
      channel.invokeMethod<void>('openLoginItems');
}
