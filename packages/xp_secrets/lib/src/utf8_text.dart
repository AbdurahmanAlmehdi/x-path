import 'dart:convert';

/// Decodes [bytes] as UTF-8, keeping a leading byte order mark.
///
/// `utf8.decode` drops a leading U+FEFF, so bytes that begin with one would
/// not come back unchanged. Throws a [FormatException] if [bytes] are not
/// valid UTF-8.
String decodeUtf8Exactly(List<int> bytes) =>
    utf8.decode([0xEF, 0xBB, 0xBF, ...bytes]);
