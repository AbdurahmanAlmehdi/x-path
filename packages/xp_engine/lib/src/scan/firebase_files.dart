import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scan/ios_files.dart';
import 'package:xp_engine/src/scan/scan_source.dart';

/// What the Firebase files of an app name: the Firebase app id of each
/// Android application id and iOS bundle id, and what the `firebase_options`
/// files of `flutterfire configure` say.
class FirebaseFiles {
  /// Creates the reading.
  const new({
    this.android = const {},
    this.ios = const {},
    this.options = const {},
  });

  /// Firebase app ids by Android application id (`google-services.json`).
  final Map<String, String> android;

  /// Firebase app ids by iOS bundle id (`GoogleService-Info.plist`, and the
  /// `iosBundleId` of a `firebase_options` file).
  final Map<String, String> ios;

  /// The ids of each `firebase_options` file by platform, keyed by the
  /// flavor its name gives: `firebase_options_dev.dart` is `dev`,
  /// `firebase_options.dart` is `''`.
  final Map<String, Map<String, String>> options;

  /// Whether a file names an app of [platform] (`android`, `ios`).
  bool covers(String platform) =>
      (platform == 'android' ? android : ios).isNotEmpty ||
      options.values.any((ids) => ids.containsKey(platform));

  /// The Firebase app ids of [flavor] by platform. A `firebase_options.dart`
  /// without a flavor in its name counts for an app with [one] flavor only.
  Map<String, String> idsOf(FlavorProfile flavor, {required bool one}) => {
    ...?options[flavor.name] ?? (one ? options[''] : null),
    'android': ?android[flavor.androidAppId],
    'ios': ?ios[flavor.iosBundleId],
  };
}

/// Reads the Firebase files of the app in [dir]: `google-services.json` of
/// the Android app and its flavor source sets, every `GoogleService-Info.plist`
/// of the iOS project, and `lib/firebase_options*.dart`.
Future<FirebaseFiles> readFirebaseFiles(ScanSource source, String dir) async {
  String at(String path) => joinScanPath(dir, path);
  final android = <String, String>{};
  final ios = <String, String>{};
  final options = <String, Map<String, String>>{};

  final googleServices = [
    at('android/app/google-services.json'),
    for (final entry in await source.list(at('android/app/src')))
      if (entry.isDirectory)
        at('android/app/src/${entry.name}/google-services.json'),
  ];
  for (final path in googleServices) {
    if (await source.read(path) case final text?) {
      android.addAll(googleServicesIds(text));
    }
  }

  for (final path in await _plists(source, at('ios'), depth: 3)) {
    final plist = await source.read(path);
    if (plist == null) continue;
    final bundle = plistString(plist, 'BUNDLE_ID');
    final id = plistString(plist, 'GOOGLE_APP_ID');
    if (bundle != null && id != null) ios[bundle] = id;
  }

  final name = RegExp(r'^firebase_options(?:_(.+))?\.dart$');
  for (final entry in await source.list(at('lib'))) {
    final match = entry.isDirectory ? null : name.firstMatch(entry.name);
    if (match == null) continue;
    final text = await source.read(at('lib/${entry.name}'));
    if (text == null) continue;
    final reading = firebaseOptionsIds(text);
    options[match.group(1) ?? ''] = reading.ids;
    ios.addAll(reading.iosBundles);
  }
  return FirebaseFiles(android: android, ios: ios, options: options);
}

/// The `GoogleService-Info.plist` files below [path], at most [depth]
/// folders down, leaving out what CocoaPods, Flutter and Xcode generate.
Future<List<String>> _plists(
  ScanSource source,
  String path, {
  required int depth,
}) async {
  const skipped = {'Pods', 'Flutter', '.symlinks', 'build', 'DerivedData'};
  final found = <String>[];
  for (final entry in await source.list(path)) {
    final child = joinScanPath(path, entry.name);
    if (!entry.isDirectory) {
      if (entry.name == 'GoogleService-Info.plist') found.add(child);
    } else if (depth > 0 &&
        !skipped.contains(entry.name) &&
        !entry.name.endsWith('.xcodeproj') &&
        !entry.name.endsWith('.xcworkspace')) {
      found.addAll(await _plists(source, child, depth: depth - 1));
    }
  }
  return found;
}

/// The Firebase app id of each Android application id a
/// `google-services.json` lists; empty when it is not that file.
Map<String, String> googleServicesIds(String json) {
  final Object? data;
  try {
    data = jsonDecode(json);
  } on FormatException {
    return const {};
  }
  return {
    if (data case {'client': final List<Object?> clients})
      for (final client in clients)
        if (client case {
          'client_info': {
            'mobilesdk_app_id': final String id,
            'android_client_info': {'package_name': final String package},
          },
        })
          package: id,
  };
}

/// What a `firebase_options.dart` says: the app id of each of its Android
/// and iOS options, and the Firebase app id of each `iosBundleId` it names.
({Map<String, String> ids, Map<String, String> iosBundles}) firebaseOptionsIds(
  String dart,
) {
  final ids = <String, String>{};
  final iosBundles = <String, String>{};
  final block = RegExp(
    r'static const FirebaseOptions (\w+) = FirebaseOptions\(([^;]*)\);',
  );
  String? field(String body, String name) =>
      RegExp("$name:\\s*['\"]([^'\"]+)['\"]").firstMatch(body)?.group(1);
  for (final match in block.allMatches(dart)) {
    final platform = match.group(1)!;
    final body = match.group(2)!;
    final id = field(body, 'appId');
    if (id == null || (platform != 'android' && platform != 'ios')) continue;
    ids[platform] = id;
    if (platform == 'ios') {
      if (field(body, 'iosBundleId') case final bundle?) {
        iosBundles[bundle] = id;
      }
    }
  }
  return (ids: ids, iosBundles: iosBundles);
}
