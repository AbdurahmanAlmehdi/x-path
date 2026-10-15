import 'package:flutter/services.dart';

/// The name of the platform channel shared with the macOS runner
/// (`apps/xp_desktop/macos/Runner/MacosServicesChannel.swift`), ADR 0005.
const macosServicesChannelName = 'ly.abdurahman.xpath/macos_services';

/// The platform channel shared with the macOS runner.
const macosServicesChannel = MethodChannel(macosServicesChannelName);

/// A macOS service failed. [code] is the runner's error code, for example
/// `locked` for a locked Keychain.
class MacosServiceException implements Exception {
  /// Creates the exception.
  const new(this.code, this.message);

  /// Reads a [PlatformException] of the channel.
  factory fromPlatform(PlatformException error) =>
      MacosServiceException(error.code, error.message ?? error.code);

  /// What failed, as the runner names it.
  final String code;

  /// What macOS said.
  final String message;

  @override
  String toString() => 'MacosServiceException($code): $message';
}
