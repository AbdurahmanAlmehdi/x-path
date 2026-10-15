import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Loads the fonts the app bundles (IBM Plex Sans and Mono, and Phosphor's
/// Regular and Fill), so goldens show the real glyphs instead of the test
/// font's boxes.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  const fonts = 'assets/fonts';
  await load('IBM Plex Sans', [
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      '$fonts/IBMPlexSans-$weight.ttf',
  ]);
  await load('IBM Plex Mono', [
    for (final weight in ['Regular', 'Medium', 'SemiBold'])
      '$fonts/IBMPlexMono-$weight.ttf',
  ]);
  final phosphor = p.join(_packageRoot('phosphor_flutter'), 'lib', 'fonts');
  await load('packages/phosphor_flutter/PhosphorRegular', [
    p.join(phosphor, 'Phosphor.ttf'),
  ]);
  await load('packages/phosphor_flutter/PhosphorFill', [
    p.join(phosphor, 'Phosphor-Fill.ttf'),
  ]);
}

/// The folder of [package], from the workspace's package config (`flutter
/// test` cannot resolve `package:` URIs through `Isolate`).
String _packageRoot(String package) {
  var directory = Directory.current;
  while (!File(p.join(directory.path, '.dart_tool', 'package_config.json'))
      .existsSync()) {
    directory = directory.parent;
  }
  final config = File(
    p.join(directory.path, '.dart_tool', 'package_config.json'),
  );
  final json = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final entry = (json['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere((entry) => entry['name'] == package);
  return config.parent.uri.resolve(entry['rootUri'] as String).toFilePath();
}
