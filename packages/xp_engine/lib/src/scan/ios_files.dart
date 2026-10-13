/// The value of the top-level string key [key] of an `Info.plist` in XML
/// form, as written, or `null` if the key is missing or not a string.
///
/// Text matching on purpose: reading a plist as a document and writing it
/// back reorders keys, and XPath only reads here.
String? plistString(String plist, String key) =>
    RegExp('<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>')
        .firstMatch(plist)
        ?.group(1)
        ?.trim();

/// Whether a plist value is a build variable such as `$(FLUTTER_BUILD_NAME)`
/// rather than a literal.
bool isBuildVariable(String value) =>
    RegExp(r'^\$[({][A-Za-z0-9_]+[)}]$').hasMatch(value);

/// The build configuration that archiving uses in the Xcode scheme [xml], for
/// example `Release-dev`, or `null` if the scheme names none.
String? schemeArchiveConfiguration(String xml) =>
    RegExp(r'<ArchiveAction[^>]*?buildConfiguration\s*=\s*"([^"]+)"')
        .firstMatch(xml)
        ?.group(1);

/// The number of single-character edits that turn [a] into [b].
int editDistance(String a, String b) {
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = [i];
    for (var j = 1; j <= b.length; j++) {
      final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final insertion = current[j - 1] + 1;
      final deletion = previous[j] + 1;
      current.add(
        [substitution, insertion, deletion].reduce((x, y) => x < y ? x : y),
      );
    }
    previous = current;
  }
  return previous[b.length];
}
