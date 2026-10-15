/// XPath macOS platform services: the LaunchAgent of the bundled engine
/// (`SMAppService`), the app's Keychain items, the `xp` link, the tool
/// check, and the notifications and menu bar extra of approvals that
/// wait. Each is an interface with a real implementation; the fakes are in
/// `package:xp_macos_services/testing.dart`.
library;

export 'src/app_bundle.dart';
export 'src/channel.dart';
export 'src/cli_linker.dart';
export 'src/engine_agent.dart';
export 'src/keychain.dart';
export 'src/local_engine.dart';
export 'src/needs_you_alerts.dart';
export 'src/tool_checker.dart';
