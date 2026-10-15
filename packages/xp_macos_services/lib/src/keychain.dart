import 'package:flutter/services.dart';
import 'package:xp_macos_services/src/channel.dart';

/// The Keychain service of the app's own items: the device tokens of the
/// engines it knows (ADR 0005).
const appKeychainService = 'ly.abdurahman.xpath.app';

/// Generic passwords of the app in the login Keychain, under
/// [appKeychainService].
abstract interface class Keychain {
  /// The value of [account], or `null` if there is none.
  ///
  /// Throws a [MacosServiceException] with the code `locked` when the
  /// Keychain is locked; the app never asks for its password.
  Future<String?> read(String account);

  /// Saves [value] as [account], replacing what was there.
  Future<void> write(String account, String value);

  /// Deletes [account]. Deleting what is not there is harmless.
  Future<void> delete(String account);
}

/// A [Keychain] over the platform channel of the macOS runner, which uses
/// the Security framework (`SecItem*`), so no value ever reaches a process
/// list.
class MethodChannelKeychain implements Keychain {
  /// Creates the Keychain over [channel].
  const new({this.channel = macosServicesChannel});

  /// The channel.
  final MethodChannel channel;

  Future<T?> _invoke<T>(String method, Map<String, String> arguments) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw MacosServiceException.fromPlatform(error);
    }
  }

  @override
  Future<String?> read(String account) =>
      _invoke<String>('keychainRead', {'account': account});

  @override
  Future<void> write(String account, String value) =>
      _invoke<void>('keychainWrite', {'account': account, 'value': value});

  @override
  Future<void> delete(String account) =>
      _invoke<void>('keychainDelete', {'account': account});
}
