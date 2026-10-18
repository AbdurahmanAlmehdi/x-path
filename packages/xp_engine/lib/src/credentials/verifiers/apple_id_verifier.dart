import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/process/process_runner.dart';
import 'package:xp_engine/src/steps/upload/upload_app_store.dart';
import 'package:xp_engine/src/stores/apple/altool_output.dart';

// An app-specific password is four groups of four lowercase letters.
final _appSpecificPassword = RegExp(r'^[a-z]{4}(-[a-z]{4}){3}$');

final _offline = RegExp(
  'internet connection appears to be offline|could not connect|timed out|'
  'network connection was lost|cannot find host|unknown host|no route to host|'
  'service unavailable',
  caseSensitive: false,
);

final _refused = RegExp(
  'authenticat|invalid username|invalid credentials|password|unauthorized|'
  r'-22938|-19209|\(1013\)',
  caseSensitive: false,
);

/// Checks an Apple ID and its app-specific password with
/// `xcrun altool --list-providers`, which authenticates and reads the
/// providers of the account and changes nothing.
///
/// The password reaches altool through the environment (`-p @env:`), never
/// the arguments. A password that is not shaped like an app-specific one is
/// refused without asking Apple: the real Apple ID password does not work for
/// altool, and sending it anywhere is a mistake.
class AppleIdVerifier implements CredentialVerifier {
  /// Creates the verifier. `isMacOS` tells whether this machine has altool.
  const new({
    required this._runner,
    required this._isMacOS,
    this.executable = 'xcrun',
    this.timeout = const Duration(minutes: 2),
  });

  /// The program that runs altool.
  final String executable;

  /// How long altool has to answer.
  final Duration timeout;

  final ProcessRunner _runner;
  final bool _isMacOS;

  @override
  CredentialKind get kind => CredentialKind.appleId;

  @override
  bool get checksTarget => false;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final apple = material as AppleIdMaterial;
    if (!_appSpecificPassword.hasMatch(apple.password)) {
      return const VerificationResult.rejected(
        'The password is not an app-specific password.',
        fix:
            'Create one at appleid.apple.com (Sign-In and Security, '
            'App-Specific Passwords); it looks like abcd-efgh-ijkl-mnop. The '
            'password of the Apple ID itself does not work for uploads.',
      );
    }
    if (!_isMacOS) {
      return const VerificationResult.unreachable(
        'An Apple ID is checked with xcrun altool, which exists on macOS '
        'only.',
        fix: 'Run the engine on the Mac that uploads to App Store Connect.',
      );
    }
    final ProcessOutput output;
    try {
      output = await _runner.run(
        executable,
        [
          'altool',
          '--list-providers',
          '-u',
          apple.appleId,
          '-p',
          '@env:$ascAppPasswordVariable',
        ],
        environment: {ascAppPasswordVariable: apple.password},
        timeout: timeout,
      );
    } on ProcessStartException {
      return const VerificationResult.unreachable(
        'xcrun could not be started.',
        fix: 'Install Xcode and select it with xcode-select.',
      );
    } on TimeoutException {
      return const VerificationResult.unreachable(
        'altool did not answer in time.',
        fix: 'Try again later.',
      );
    }
    final text = '${output.stdout}\n${output.stderr}';
    final parsed = AltoolOutput.parse(text.split('\n'));
    if (output.exitCode == 0 && !parsed.rejected) {
      return VerificationResult.verified(account: apple.appleId);
    }
    final what = parsed.rejected
        ? _without(parsed.describe(), apple.password)
        : 'altool exited with code ${output.exitCode}.';
    if (_offline.hasMatch(text)) {
      return VerificationResult.unreachable(
        'Apple could not be reached: $what',
        fix: 'Check the network connection and try again.',
      );
    }
    if (_refused.hasMatch(text)) {
      return VerificationResult.rejected(
        'Apple refused the Apple ID ${apple.appleId}: $what',
        fix:
            'The app-specific password was revoked or is wrong, or the Apple '
            'ID is. Create a new app-specific password at appleid.apple.com '
            'and save it again.',
      );
    }
    return VerificationResult.unreachable(
      'altool could not check the Apple ID: $what',
      fix: 'Run xcrun altool --list-providers by hand to see why.',
    );
  }

  String _without(String text, String secret) => text.replaceAll(secret, '***');
}
