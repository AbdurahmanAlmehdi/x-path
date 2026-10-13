import 'dart:async';

import 'package:crypto/crypto.dart';

/// The SHA-256 of [content] in lowercase hexadecimal, read in one pass.
Future<String> sha256OfStream(Stream<List<int>> content) async =>
    '${await sha256.bind(content).first}';

/// The SHA-256 of [bytes] in lowercase hexadecimal.
String sha256OfBytes(List<int> bytes) => '${sha256.convert(bytes)}';
