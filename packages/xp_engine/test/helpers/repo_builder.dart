import 'package:xp_engine/xp_engine.dart';

/// A `project.pbxproj` with a `Runner` application target.
///
/// [runner] maps a configuration name to the target's settings for it,
/// [project] does the same for the project. [spm] adds a Swift package
/// reference, [extensions] app extension targets of those names.
/// [scripts] are Run Script phases of the Runner target (name to script),
/// [resources] what its Copy Bundle Resources phase copies, and [xcconfigs]
/// the `.xcconfig` a configuration of the target is based on, both relative
/// to `ios`.
String pbxproj({
  Map<String, Map<String, String>> runner = const {},
  Map<String, Map<String, String>> project = const {},
  bool spm = false,
  List<String> extensions = const [],
  Map<String, String> scripts = const {},
  List<String> resources = const [],
  Map<String, String> xcconfigs = const {},
}) {
  var next = 0;
  String id() => (0xA000 + next++).toRadixString(16).toUpperCase();
  final blocks = StringBuffer();
  String file(String path) {
    final fileId = id();
    blocks.writeln(
      '$fileId = { isa = PBXFileReference; path = "$path"; '
      'sourceTree = SOURCE_ROOT; };',
    );
    return fileId;
  }

  String list(
    Map<String, Map<String, String>> configs, {
    Map<String, String> bases = const {},
  }) {
    final listId = id();
    final ids = <String>[];
    for (final entry in configs.entries) {
      final configId = id();
      ids.add(configId);
      final settings = entry.value.entries
          .map((setting) => '${setting.key} = "${setting.value}";')
          .join('\n');
      final base = bases[entry.key];
      blocks.writeln('''
$configId = {
isa = XCBuildConfiguration;
${base == null ? '' : 'baseConfigurationReference = ${file(base)};'}
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

  final runnerList = list(runner, bases: xcconfigs);
  final phases = <String>[];
  for (final entry in scripts.entries) {
    final phaseId = id();
    phases.add(phaseId);
    final script = entry.value.replaceAll('"', r'\"').replaceAll('\n', r'\n');
    blocks.writeln(
      '$phaseId = { isa = PBXShellScriptBuildPhase; name = "${entry.key}"; '
      'shellScript = "$script"; };',
    );
  }
  if (resources.isNotEmpty) {
    final phaseId = id();
    phases.add(phaseId);
    String buildFile(String path) {
      final buildFileId = id();
      blocks.writeln(
        '$buildFileId = { isa = PBXBuildFile; fileRef = ${file(path)}; };',
      );
      return buildFileId;
    }

    blocks.writeln(
      '$phaseId = { isa = PBXResourcesBuildPhase; '
      'files = ( ${resources.map(buildFile).join(', ')} ); };',
    );
  }
  final projectList = list(project);
  final extensionIds = [
    for (final name in extensions) 'EXT_${name.toUpperCase()}',
  ];
  for (final (index, name) in extensions.indexed) {
    blocks.writeln('''
${extensionIds[index]} = {
isa = PBXNativeTarget;
buildConfigurationList = ${list(const {})};
name = $name;
productType = "com.apple.product-type.app-extension";
};''');
  }
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
buildPhases = ( ${phases.map((phaseId) => '$phaseId, ').join()});
name = Runner;
productType = "com.apple.product-type.application";
};
PROJECT = {
isa = PBXProject;
buildConfigurationList = $projectList;
targets = ( RUNNER, ${extensionIds.map((id) => '$id, ').join()});
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
