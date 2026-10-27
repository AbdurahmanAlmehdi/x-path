import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../helpers/directory_scan_source.dart';

/// Set `UPDATE_GOLDENS=1` to rewrite the golden files from the scanner.
/// Review the diff: it is the contract of what a scan reports.
final _update = Platform.environment['UPDATE_GOLDENS'] == '1';

final _fixtures = Directory('../../tool/e2e/fixtures');
final _goldens = Directory('test/scan/goldens');

const _encoder = JsonEncoder.withIndent('  ');

Future<ScanResult> _scan(Directory directory) =>
    const ProjectScanner().scan(DirectoryScanSource(directory));

String _json(ScanResult result) =>
    '${_encoder.convert({
      'profile': result.profile.toJson(),
      'findings': [for (final finding in result.findings) finding.toJson()],
    })}\n';

/// Every file below [directory] with its content, to see if a scan changed
/// anything.
Map<String, String> _snapshot(Directory directory) => {
  for (final entity in directory.listSync(recursive: true))
    if (entity is File)
      entity.path.substring(directory.path.length): entity.readAsStringSync(),
};

void main() {
  final names =
      _fixtures
          .listSync()
          .whereType<Directory>()
          .map((directory) => directory.uri.pathSegments.reversed.skip(1).first)
          .toList()
        ..sort();

  test('the fixtures are the six reference apps, a drifting one and two '
      'flavor setups for Linux iOS builds', () {
    expect(names, [
      'captain',
      'companion',
      'customer',
      'drift',
      'firebase_script',
      'flavorizr',
      'guest',
      'room_spike',
      'vendor',
    ]);
  });

  test('every fixture has exactly one golden', () {
    final goldens =
        _goldens
            .listSync()
            .map((file) => file.uri.pathSegments.last.replaceAll('.json', ''))
            .toList()
          ..sort();

    expect(goldens, names);
  });

  for (final name in names) {
    test('$name produces the expected profile and findings', () async {
      final golden = File('${_goldens.path}/$name.json');
      final actual = _json(await _scan(Directory('${_fixtures.path}/$name')));
      if (_update) golden.writeAsStringSync(actual);

      expect(actual, golden.readAsStringSync());
    });
  }

  test('a scan writes nothing to the folder (D-04)', () async {
    final copy = Directory.systemTemp.createTempSync('xp_scan_');
    addTearDown(() => copy.deleteSync(recursive: true));
    final source = Directory('${_fixtures.path}/customer');
    for (final entity in source.listSync(recursive: true)) {
      final target = '${copy.path}${entity.path.substring(source.path.length)}';
      if (entity is File) {
        File(target)
          ..createSync(recursive: true)
          ..writeAsStringSync(entity.readAsStringSync());
      }
    }
    final before = _snapshot(copy);

    await _scan(copy);

    expect(_snapshot(copy), before);
  });

  group('the golden profiles', () {
    Future<ProjectProfile> profileOf(String name) async =>
        (await _scan(Directory('${_fixtures.path}/$name'))).profile;

    test('customer keeps the prod id mismatch and literal plists', () async {
      final prod = (await profileOf('customer')).apps.single.flavors.last;

      expect(prod.androidAppId, 'com.mataaa');
      expect(prod.iosBundleId, 'com.sixdtec.mata');
      expect(prod.versionFiles, ['pubspec.yaml', 'ios/Runner/Info.plist']);
    });

    test('captain keeps com.mataaa.captain.dev', () async {
      final dev = (await profileOf('captain')).apps.single.flavors.first;

      expect(dev.iosBundleId, 'com.mataaa.captain.dev');
      expect(dev.androidAppId, 'com.mataa.captain.dev');
      expect(dev.versionFiles, ['pubspec.yaml']);
    });

    test('guest is a monorepo with two apps', () async {
      final profile = await profileOf('guest');

      expect(profile.layout, ProjectLayout.melos);
      expect(profile.apps.map((app) => app.path), [
        'apps/mobile_app',
        'apps/tablet_app',
      ]);
    });

    test('room_spike uses Swift Package Manager', () async {
      final profile = await profileOf('room_spike');

      expect(profile.apps.single.iosPackageManager, IosPackageManager.spm);
      expect(profile.apps.single.flavors.single.implicit, isTrue);
    });

    test('room_spike, the stock template, has no Linux iOS limits', () async {
      final app = (await profileOf('room_spike')).apps.single;

      expect(app.iosLinuxLimits, isEmpty);
      expect(app.flavors.single.iosLinuxLimits, isEmpty);
    });

    test('flavorizr narrows only the flavor with a multi-size icon set, and '
        'names its configuration', () async {
      final result = await _scan(Directory('${_fixtures.path}/flavorizr'));
      final flavors = result.profile.apps.single.flavors;

      expect(
        {for (final flavor in flavors) flavor.name: flavor.iosLinuxLimits},
        {
          'dev': isEmpty,
          'staging': [
            startsWith(
              'its configuration Release-staging uses the app icon set '
              'AppIcon-staging, which has several sizes',
            ),
          ],
          'prod': isEmpty,
        },
      );
      final staging = result.findings.singleWhere(
        (finding) =>
            finding.code == 'ios_needs_mac' && finding.flavor == 'staging',
      );
      expect(staging.message, contains('Release-staging'));
      final missing = result.findings.singleWhere(
        (finding) => finding.code == 'ios_app_icon_missing',
      );
      expect(missing.flavor, 'prod');
      expect(missing.message, contains('AppIcon-prod'));
    });

    test('firebase_script narrows the whole app on its Run Script', () async {
      final app = (await profileOf('firebase_script')).apps.single;

      expect(app.iosLinuxLimits, [
        startsWith(
          'the Runner target runs the Run Script phase "Copy '
          'GoogleService-Info.plist"',
        ),
      ]);
      expect(app.flavors.map((flavor) => flavor.iosLinuxLimits), [
        isEmpty,
        isEmpty,
      ]);
    });
  });
}
