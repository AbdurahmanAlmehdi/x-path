import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/access/access_policy.dart';
import 'package:xp_engine/src/repositories/engine_setting_repository.dart';
import 'package:xp_engine/src/signin/sign_in_exceptions.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// The public URL: the HTTPS origin browsers reach the engine at through a
/// proxy that terminates TLS (ADR 0018, D3). Browser sign-in works on this
/// machine, or through it; it is one of the origins a browser request may
/// come from (D15).
///
/// The engine is the only writer of the setting, so the service keeps it
/// once read.
class PublicUrlService {
  /// Creates the service over the engine settings.
  new({required this._settings});

  /// The key of the public URL in the engine settings.
  static const key = 'public_url';

  final EngineSettingRepository _settings;
  Future<String?>? _origin;

  /// The public URL's origin, for example `https://xpath.example.com`, or
  /// `null` when none is set.
  Future<String?> origin() => _origin ??= _settings.read(key);

  /// The public URL.
  Future<PublicUrl> read() async => PublicUrl(url: await origin());

  /// Sets the public URL to [url], or clears it for `null` or a blank one,
  /// [by] an admin's token.
  ///
  /// The URL must be an `https` origin: a host, maybe a port, and nothing
  /// else (no user info, path, query or fragment); a trailing `/` is
  /// dropped. The dashboard is served at the root of its origin, and its
  /// session cookie is a `__Host-` one.
  ///
  /// Throws a [PublicUrlForbiddenException] if [by] may not
  /// [Permission.administer], and a [PublicUrlInvalidException] for a URL
  /// that is not one.
  Future<PublicUrl> set(String? url, {required DeviceToken by}) async {
    final refusal = AccessPolicy.refusal(
      by,
      Permission.administer,
      'set the public URL',
    );
    if (refusal != null) throw PublicUrlForbiddenException(refusal);
    final text = url?.trim() ?? '';
    final String? origin;
    if (text.isEmpty) {
      origin = null;
    } else {
      final parsed = Uri.tryParse(text);
      if (parsed == null ||
          parsed.scheme != 'https' ||
          parsed.host.isEmpty ||
          parsed.userInfo.isNotEmpty ||
          (parsed.path.isNotEmpty && parsed.path != '/') ||
          parsed.hasQuery ||
          parsed.hasFragment) {
        throw PublicUrlInvalidException(
          '"$url" is not a public URL. Give the https address of the proxy '
          'in front of the engine, with no path, for example '
          'https://xpath.example.com.',
        );
      }
      origin = parsed.origin;
    }
    await _settings.write(key, origin);
    _origin = Future.value(origin);
    return PublicUrl(url: origin);
  }
}
