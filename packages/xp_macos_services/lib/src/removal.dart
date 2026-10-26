import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:xp_macos_services/src/channel.dart';
import 'package:xp_macos_services/src/keychain.dart';
import 'package:xp_macos_services/src/tool_checker.dart';

/// The prefix of every Keychain service XPath uses (ADR 0005): the app's
/// `ly.abdurahman.xpath.app`, the engine's `ly.abdurahman.xpath.credentials`
/// and `ly.abdurahman.xpath.master`, and those of `xp`.
const keychainServicePrefix = 'ly.abdurahman.xpath';

/// The data folder of the engine on this Mac when nothing overrides it
/// (`xpd`'s `resolveDataDirectory`), for the home folder [home].
String engineDataDirectory(String home) =>
    p.join(home, 'Library', 'Application Support', 'XPath');

/// Deletes the Keychain items of XPath: every generic password whose
/// service is [keychainServicePrefix] or starts with it and a dot.
abstract interface class KeychainWiper {
  /// Deletes them and returns how many there were.
  ///
  /// Throws a [MacosServiceException] when one cannot be deleted (a locked
  /// Keychain); the ones before it are gone.
  Future<int> wipe();
}

/// The [KeychainWiper] of this Mac. The macOS runner lists the items (their
/// names only, never a value). The app's own items go through the runner,
/// which made them; the engine's through `security`, which made those, so
/// that macOS asks nobody for permission.
class SystemKeychainWiper implements KeychainWiper {
  /// Creates the wiper.
  const new({
    this.channel = macosServicesChannel,
    this._run = Process.run,
    this.security = '/usr/bin/security',
  });

  /// The channel of the macOS runner.
  final MethodChannel channel;

  /// The `security` tool.
  final String security;

  final RunProcess _run;

  @override
  Future<int> wipe() async {
    final List<Map<Object?, Object?>> items;
    try {
      items =
          await channel.invokeListMethod<Map<Object?, Object?>>(
            'keychainItems',
            {'prefix': keychainServicePrefix},
          ) ??
          const [];
    } on PlatformException catch (error) {
      throw MacosServiceException.fromPlatform(error);
    }
    for (final item in items) {
      final service = item['service']! as String;
      final account = item['account']! as String;
      if (service == appKeychainService) {
        await MethodChannelKeychain(channel: channel).delete(account);
        continue;
      }
      final result = await _run(security, [
        'delete-generic-password',
        '-s',
        service,
        '-a',
        account,
      ]);
      if (result.exitCode != 0) {
        throw MacosServiceException(
          'keychain',
          'security could not delete $service ($account): '
              '${(result.stderr as String).trim()}',
        );
      }
    }
    return items.length;
  }
}

/// Deletes folders of XPath's data.
abstract interface class DataWiper {
  /// The folders it deletes.
  List<String> get folders;

  /// Deletes the [folders] that exist and returns them.
  Future<List<String>> wipe();
}

/// The [DataWiper] of the file system.
class FileSystemDataWiper implements DataWiper {
  /// Creates the wiper of [folders].
  const new(this.folders);

  @override
  final List<String> folders;

  @override
  Future<List<String>> wipe() async {
    final deleted = <String>[];
    for (final folder in folders) {
      final directory = Directory(folder);
      if (!directory.existsSync()) continue;
      await directory.delete(recursive: true);
      deleted.add(folder);
    }
    return deleted;
  }
}

/// The running app itself: its version, and leaving.
abstract interface class RunningApp {
  /// The version, as `<CFBundleShortVersionString> (<CFBundleVersion>)`.
  Future<String> version();

  /// Moves `XPath.app` to the Trash (`NSWorkspace.recycle`). Whether it
  /// went; the app keeps running until [quit].
  Future<bool> moveToTrash();

  /// Quits the app.
  Future<void> quit();

  /// Whether closing the main window keeps the app running in the menu bar
  /// (UX-07); otherwise it quits. macOS keeps the choice.
  Future<void> setKeepRunning({required bool keep});
}

/// The [RunningApp] over the platform channel of the macOS runner.
class MethodChannelRunningApp implements RunningApp {
  /// Creates it over [channel].
  const new({this.channel = macosServicesChannel});

  /// The channel.
  final MethodChannel channel;

  @override
  Future<String> version() async =>
      await channel.invokeMethod<String>('appVersion') ?? '';

  @override
  Future<bool> moveToTrash() async =>
      await channel.invokeMethod<bool>('appMoveToTrash') ?? false;

  @override
  Future<void> quit() => channel.invokeMethod<void>('appQuit');

  @override
  Future<void> setKeepRunning({required bool keep}) =>
      channel.invokeMethod<void>('appKeepRunning', {'keep': keep});
}

/// The name of the channel of the app menu (`MacosServicesChannel.swift`).
const appMenuChannelName = 'ly.abdurahman.xpath/app_menu';

/// The items of the app menu that the Dart side answers.
abstract interface class AppMenu {
  /// Fires when the owner chose XPath ▸ Settings… (⌘,).
  Stream<void> get settingsRequests;
}

/// The [AppMenu] over the platform channel of the macOS runner.
class MethodChannelAppMenu implements AppMenu {
  /// Creates it over [channel] and starts listening.
  new({this.channel = const MethodChannel(appMenuChannelName)}) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'settings') _settings.add(null);
    });
  }

  /// The channel.
  final MethodChannel channel;

  final _settings = StreamController<void>.broadcast();

  @override
  Stream<void> get settingsRequests => _settings.stream;
}
