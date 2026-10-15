import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Opens a session with the engine [profile] using [token].
typedef SessionFactory = EngineSession Function(
  EngineProfile profile,
  String token,
);

/// Asks the user for a folder; `null` when they cancel.
typedef FolderPicker = Future<String?> Function();

/// Asks the user for a file; `null` when they cancel.
typedef FilePicker = Future<PickedFile?> Function();

/// A file the user picked.
class PickedFile extends Equatable {
  const new({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;

  @override
  List<Object?> get props => [name, bytes];
}

/// A [TokenVault] in the app's Keychain items (`ly.abdurahman.xpath.app`),
/// one per engine.
class KeychainTokenVault implements TokenVault {
  const new(this._keychain);

  final Keychain _keychain;

  static String _account(String engineId) => 'engine.$engineId';

  @override
  Future<String?> read(String engineId) => _keychain.read(_account(engineId));

  @override
  Future<void> write(String engineId, String token) =>
      _keychain.write(_account(engineId), token);

  @override
  Future<void> delete(String engineId) => _keychain.delete(_account(engineId));
}

/// Everything the app reaches outside Flutter: the engines it knows, the
/// sessions with them and the macOS services. Tests pass fakes.
class AppServices {
  const new({
    required this.engines,
    required this.openSession,
    required this.agent,
    required this.linker,
    required this.tools,
    required this.localEngine,
    required this.pickFolder,
    required this.pickFile,
    required this.deviceName,
    required this.alerts,
  });

  /// The services of this Mac: the engine list and the offline cache in the
  /// app's Application Support folder, tokens in the Keychain, the engine
  /// and `xp` inside the running app's bundle.
  static Future<AppServices> system() async {
    final support = (await getApplicationSupportDirectory()).path;
    final home = Platform.environment['HOME'] ?? '';
    final bundle = AppBundle.fromExecutable(Platform.resolvedExecutable);
    return AppServices(
      engines: EnginesRepository(
        directory: support,
        vault: const KeychainTokenVault(MethodChannelKeychain()),
      ),
      openSession: (profile, token) => EngineSession.connect(
        profile: profile,
        token: token,
        cacheDirectory: p.join(support, 'cache'),
      ),
      agent: const MethodChannelEngineAgent(),
      linker: FileSystemCliLinker(target: bundle.xpExecutable, home: home),
      tools: PathToolChecker(searchPath: serviceSearchPath(home)),
      localEngine: BundledLocalEngine(executable: bundle.xpdExecutable),
      pickFolder: getDirectoryPath,
      pickFile: () async {
        final file = await openFile();
        if (file == null) return null;
        return PickedFile(name: file.name, bytes: await file.readAsBytes());
      },
      deviceName: Platform.localHostname.split('.').first,
      alerts: MethodChannelNeedsYouAlerts(),
    );
  }

  final EnginesRepository engines;
  final SessionFactory openSession;
  final EngineAgent agent;
  final CliLinker linker;
  final ToolChecker tools;
  final LocalEngine localEngine;
  final FolderPicker pickFolder;
  final FilePicker pickFile;

  /// What this Mac is called, for naming its token.
  final String deviceName;

  /// The notifications and the menu bar extra of approvals that wait.
  final NeedsYouAlerts alerts;
}
