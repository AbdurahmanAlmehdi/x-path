import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xp_api/xp_api.dart';

/// The source key of a repository on a host other than GitHub (ADR 0015).
extension GitRemoteSourceKey on GitRemote {
  /// `h` and the first 16 hex digits of the SHA-256 of [GitRemote.normalised].
  String get sourceKey =>
      'h${sha256.convert(utf8.encode(normalised)).toString().substring(0, 16)}';
}
