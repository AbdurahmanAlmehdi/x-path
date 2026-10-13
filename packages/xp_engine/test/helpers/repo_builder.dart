import 'package:xp_engine/xp_engine.dart';

/// A `project.pbxproj` with a `Runner` application target.
///
/// [runner] maps a configuration name to the target's settings for it,
/// [project] does the same for the project. [spm] adds a Swift package
/// reference.
String pbxproj({
  Map<String, Map<String, String>> runner = const {},
  Map<String, Map<String, String>> project = const {},
  bool spm = false,
}) {
  var next = 0;
  String id() => (0xA000 + next++).toRadixString(16).toUpperCase();
  final blocks = StringBuffer();
  String list(Map<String, Map<String, String>> configs) {
    final listId = id();
    final ids = <String>[];
    for (final entry in configs.entries) {
      final configId = id();
      ids.add(configId);
      final settings = entry.value.entries
          .map((setting) => '${setting.key} = "${setting.value}";')
          .join('\n');
      blocks.writeln('''
$configId = {
isa = XCBuildConfiguration;
buildSettings = {
$settings
};
name = "${entry.key}";
};''');
    }
    blocks.writeln('''
$listId = {
isa = XCConfigurationList;
buildConfigurations = (
${ids.map((configId) => '$configId,').join('\n')}
);
};''');
    return listId;
  }

  final runnerList = list(runner);
  final projectList = list(project);
  if (spm) {
    blocks.writeln('''
${id()} = {
isa = XCLocalSwiftPackageReference;
relativePath = Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage;
};''');
  }
  return '''
// !\$*UTF8*\$!
{
objects = {
RUNNER = {
isa = PBXNativeTarget;
buildConfigurationList = $runnerList;
name = Runner;
productType = "com.apple.product-type.application";
};
PROJECT = {
isa = PBXProject;
buildConfigurationList = $projectList;
targets = ( RUNNER, );
};
$blocks
};
rootObject = PROJECT;
}
''';
}

/// Settings of a Runner configuration.
Map<String, String> iosSettings({
  String? bundleId,
  String? team,
  String? plist = 'Runner/Info.plist',
}) => {
  'PRODUCT_BUNDLE_IDENTIFIER': ?bundleId,
  'DEVELOPMENT_TEAM': ?team,
  'INFOPLIST_FILE': ?plist,
};

/// The Debug, Profile and Release configurations of [flavor] (`null` for the
/// plain ones) with the same [settings].
Map<String, Map<String, String>> configurations(
  String? flavor,
  Map<String, String> settings,
) => {
  for (final kind in ['Debug', 'Profile', 'Release'])
    flavor == null ? kind : '$kind-$flavor': settings,
};

/// An Xcode scheme that archives with [archive].
String scheme(String archive) => [
  '<Scheme>',
  '<ArchiveAction buildConfiguration = "$archive"></ArchiveAction>',
  '</Scheme>',
].join();

/// An `Info.plist` with the two version keys; `null` leaves a key out.
String plist({String? shortVersion, String? build}) {
  final short = shortVersion == null
      ? ''
      : '<key>CFBundleShortVersionString</key><string>$shortVersion</string>';
  final number = build == null
      ? ''
      : '<key>CFBundleVersion</key><string>$build</string>';
  return '<dict>$short$number</dict>';
}

/// A pubspec for a Flutter app.
String pubspec({
  String name = 'demo',
  String? version = '1.0.0+1',
  String extra = '',
}) =>
    'name: $name\n'
    '${version == null ? '' : 'version: $version\n'}'
    'dependencies:\n  flutter:\n    sdk: flutter\n$extra';

/// A Gradle script for a plain app: [applicationId] and optionally a
/// `key.properties` reference.
String gradle({
  String applicationId = 'com.example.demo',
  bool keystore = true,
  String flavors = '',
}) =>
    '''
${keystore ? 'val p = rootProject.file("key.properties")' : ''}
android {
    defaultConfig { applicationId = "$applicationId" }
    $flavors
}
''';

/// The files of a plain Flutter app (no flavors) below [dir], with
/// [overrides] on top. A `null` override removes the file.
Map<String, String> app({
  String dir = '',
  Map<String, String?> overrides = const {},
}) {
  final base = <String, String?>{
    'pubspec.yaml': pubspec(),
    'lib/main.dart': '',
    '.fvmrc': '{"flutter": "3.47.4"}',
    'android/app/build.gradle': gradle(),
    'android/key.properties': 'storeFile=release.jks\nstorePassword=x\n',
    'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
      runner: configurations(
        null,
        iosSettings(bundleId: 'com.example.demo', team: 'TEAM000001'),
      ),
    ),
    'ios/Runner/Info.plist': plist(
      shortVersion: r'$(FLUTTER_BUILD_NAME)',
      build: r'$(FLUTTER_BUILD_NUMBER)',
    ),
    'ios/Podfile': '',
    ...overrides,
  };
  return {
    for (final entry in base.entries)
      if (entry.value != null)
        dir.isEmpty ? entry.key : '$dir/${entry.key}': entry.value!,
  };
}

/// Scans [files] and returns the result.
Future<ScanResult> scanFiles(Map<String, String> files) =>
    const ProjectScanner().scan(InMemoryScanSource(files));
