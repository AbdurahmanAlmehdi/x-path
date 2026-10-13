import 'dart:convert';

/// The version of the GitHub CLI in the output of `gh --version`, or `null`.
String? parseGhVersion(String output) => RegExp(
  r'^gh version (\d+\.\d+\.\d+\S*)',
  multiLine: true,
).firstMatch(output)?.group(1);

/// The version of the Shorebird CLI in the output of `shorebird --version`
/// (its first line, `Shorebird 1.6.128 • git@github.com:...`), or `null`.
String? parseShorebirdVersion(String output) => RegExp(
  r'^Shorebird v?(\d+\.\d+\.\d+\S*)',
  multiLine: true,
).firstMatch(output)?.group(1);

/// What `xcodebuild -version` printed.
typedef XcodeVersion = ({String version, String? build});

/// The version and build of Xcode in the output of `xcodebuild -version`, or
/// `null`.
XcodeVersion? parseXcodeVersion(String output) {
  final version = RegExp(
    r'^Xcode (\d+(?:\.\d+)*)',
    multiLine: true,
  ).firstMatch(output)?.group(1);
  if (version == null) return null;
  final build = RegExp(
    r'^Build version (\S+)',
    multiLine: true,
  ).firstMatch(output)?.group(1);
  return (version: version, build: build);
}

/// What `flutter --version --machine` printed.
typedef FlutterSdkVersions = ({String flutter, String? dart});

/// The Flutter and Dart versions in the output of `flutter --version
/// --machine`, or `null` if it holds no JSON object with a Flutter version.
///
/// A fresh SDK prints progress lines before the JSON, so the object is cut
/// out of the text.
FlutterSdkVersions? parseFlutterMachineVersion(String output) {
  final json = _jsonObject(output);
  if (json == null) return null;
  final flutter = json['frameworkVersion'] ?? json['flutterVersion'];
  if (flutter is! String || flutter.isEmpty) return null;
  final dart = json['dartSdkVersion'];
  return (
    flutter: flutter,
    dart: dart is String && dart.isNotEmpty ? dart : null,
  );
}

/// One Flutter SDK in the cache of fvm.
typedef FvmVersion = ({
  String name,
  String directory,
  String? flutterVersion,
  String? dartVersion,
});

/// The SDKs fvm has cached, from the output of `fvm api list`, or `null` if
/// the output is not what fvm 3 and 4 print.
List<FvmVersion>? parseFvmList(String output) {
  final json = _jsonObject(output);
  final versions = json?['versions'];
  if (versions is! List) return null;
  return [
    for (final entry in versions)
      if (entry is Map<String, dynamic> &&
          entry['name'] is String &&
          entry['directory'] is String)
        (
          name: entry['name'] as String,
          directory: entry['directory'] as String,
          flutterVersion: _text(entry['flutterSdkVersion']),
          dartVersion: _text(entry['dartSdkVersion']),
        ),
  ];
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

Map<String, dynamic>? _jsonObject(String output) {
  final start = output.indexOf('{');
  final end = output.lastIndexOf('}');
  if (start < 0 || end < start) return null;
  try {
    final json = jsonDecode(output.substring(start, end + 1));
    return json is Map<String, dynamic> ? json : null;
  } on FormatException {
    return null;
  }
}
