import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/dispatch/ios_linux_limits.dart';
import 'package:xp_engine/src/scan/firebase_files.dart';
import 'package:xp_engine/src/scan/gradle_parser.dart';
import 'package:xp_engine/src/scan/ios_files.dart';
import 'package:xp_engine/src/scan/scan_context.dart';
import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/scan/xcode_project_parser.dart';
import 'package:yaml/yaml.dart';

const _prodNames = {'prod', 'production', 'release', 'live'};

/// The ids `flutter_flavorizr` says a flavor has.
class _Declared {
  const new({this.android, this.ios});

  final String? android;
  final String? ios;
}

/// The pubspec `version` split into its parts.
class _Version {
  const new(this.name, this.build);

  final String name;
  final String? build;
}

final _versionPattern = RegExp(r'^(\d+\.\d+\.\d+[^+\s]*)(?:\+(\d+))?$');

YamlMap? _map(Object? value) => value is YamlMap ? value : null;

/// Scans one Flutter app, the directory [dir] of the repository (`''` for the
/// root). Returns `null` if the directory is not a Flutter app.
Future<AppProfile?> scanApp(
  ScanContext context,
  String dir,
  YamlMap? pubspec,
) async {
  final name = pubspec?['name'];
  final hasIos = await context.source.exists(
    joinScanPath(dir, 'ios/Runner.xcodeproj'),
  );
  final hasAndroid = await context.source.exists(
    joinScanPath(dir, 'android/app'),
  );
  final flutterDependency = _map(
    _map(pubspec?['dependencies'])?['flutter'],
  )?['sdk'];
  final isPlugin = _map(pubspec?['flutter'])?['plugin'] != null;
  if (name is! String ||
      flutterDependency != 'flutter' ||
      isPlugin ||
      !(hasIos || hasAndroid)) {
    return null;
  }
  return await _AppScan(
    context,
    dir,
    name: name,
    pubspec: pubspec!,
    hasIos: hasIos,
    hasAndroid: hasAndroid,
  ).run();
}

class _AppScan {
  new(
    this._context,
    this._dir, {
    required this.name,
    required this.pubspec,
    required this.hasIos,
    required this.hasAndroid,
  }) : app = _dir.isEmpty ? '.' : _dir;

  final ScanContext _context;
  final String _dir;
  final String name;
  final YamlMap pubspec;
  final bool hasIos;
  final bool hasAndroid;

  /// The app path as the profile spells it.
  final String app;

  ScanSource get _source => _context.source;

  /// The path of [path] inside the app, relative to the repository root.
  String _at(String path) => joinScanPath(_dir, path);

  void _add(
    FindingSeverity severity,
    String code,
    String message,
    String fix, {
    String? path,
    String? flavor,
  }) => _context.add(
    severity,
    code,
    message,
    fix,
    path: path,
    app: app,
    flavor: flavor,
  );

  // Read once by `run` and shared by the steps below.
  GradleInfo? _gradle;
  XcodeProject? _xcode;
  var _declared = const <String, _Declared>{};
  var _schemes = const <String, String>{};
  var _entrypoints = const <String, String>{};
  final _plists = <String, PlistVersion>{};

  Future<AppProfile> run() async {
    final versionText = pubspec['version'];
    final version = versionText is String
        ? _versionPattern.firstMatch(versionText)
        : null;
    if (version == null) {
      _add(
        FindingSeverity.error,
        'pubspec_version_missing',
        versionText == null
            ? 'The pubspec has no version.'
            : 'The pubspec version "$versionText" is not x.y.z+build.',
        'Set `version: x.y.z+build` in ${_at('pubspec.yaml')}.',
        path: _at('pubspec.yaml'),
      );
    }

    _gradle = hasAndroid ? await _readGradle() : null;
    _declared = await _readFlavorizr();
    _xcode = hasIos ? await _readXcode() : null;
    _schemes = hasIos ? await _readSchemes() : const {};
    _entrypoints = await _readEntrypoints();

    final names = _flavorNames();
    final implicit = names.isEmpty;
    final shorebird = await _readShorebird();
    final flavors = <FlavorProfile>[
      for (final flavorName in implicit ? const ['default'] : names)
        await _flavor(flavorName, implicit: implicit, shorebird: shorebird),
    ];

    _checkVersions(
      version == null ? null : _Version(version.group(1)!, version.group(2)),
      versionText,
    );
    final literal = {
      for (final plist in _plists.values)
        if (plist.literal) plist.path,
    };
    _checkShorebird(shorebird, names, implicit: implicit);
    final firebase = await readFirebaseFiles(_source, _dir);
    final firebaseIds = {
      for (final flavor in flavors)
        flavor.name: firebase.idsOf(flavor, one: flavors.length == 1),
    };
    _checkFirebase(firebase, flavors, firebaseIds, implicit: implicit);
    if (!implicit && !flavors.any((flavor) => flavor.prod)) {
      _add(
        FindingSeverity.info,
        'no_prod_flavor',
        'None of the flavors looks like production.',
        'Mark the production flavor in the profile.',
      );
    }
    for (final plist in _plists.values.where((plist) => plist.literal)) {
      _add(
        FindingSeverity.warning,
        'plist_literal_version',
        '${plist.path} hard-codes its version, so flutter build --build-name '
            'and --build-number do not reach iOS.',
        r'Use $(FLUTTER_BUILD_NAME) and $(FLUTTER_BUILD_NUMBER) in the '
            'plist, or let XPath write the version into it: the plist is '
            'listed in the version files of its flavors.',
        path: plist.path,
      );
    }

    final pin = await _context.pin(_dir);
    if (pin == null) {
      _add(
        FindingSeverity.warning,
        'fvmrc_missing',
        'There is no .fvmrc, so XPath does not know which Flutter version '
            'to build with.',
        'Add a .fvmrc with {"flutter": "x.y.z"} to the app or to the '
            'repository root.',
        path: _at('.fvmrc'),
      );
    }

    final packageManager = await _packageManager();
    final extensions = [
      for (final target in _xcode?.targets ?? const <XcodeTarget>[])
        if (target.isAppExtension) target.name,
    ];
    final linuxLimits = hasIos
        ? await _iosLinuxLimits(packageManager, pin?.version)
        : const <String>[];
    if (hasIos) {
      _checkIosLinux(
        extensions: extensions,
        limits: [
          ...linuxLimits,
          if (implicit) ...flavors.single.iosLinuxLimits,
        ],
      );
      if (!implicit) flavors.forEach(_checkFlavorIosLinux);
    }

    return AppProfile(
      name: name,
      path: app,
      version: versionText is String ? versionText : null,
      flutterVersion: pin?.version,
      flutterVersionSource: pin?.source,
      hasIos: hasIos,
      hasAndroid: hasAndroid,
      iosPackageManager: packageManager,
      iosAppExtensions: extensions,
      iosLinuxLimits: linuxLimits,
      flavors: [
        for (final flavor in flavors)
          flavor.copyWith(
            versionFiles: [
              _at('pubspec.yaml'),
              if (flavor.infoPlist != null &&
                  literal.contains(flavor.infoPlist))
                flavor.infoPlist!,
            ],
            firebaseAppId: switch (firebaseIds[flavor.name]!) {
              final ids when ids.isEmpty => null,
              final ids => () => ids,
            },
          ),
      ],
      plists: _plists.values.toList(),
      keystore: await _keystore(),
      shorebird: shorebird,
    );
  }

  // ------------------------------------------------------- iOS on Linux

  /// The Flutter version Linux iOS builds need at least (omarchy-apple-dev
  /// builds with `flutter assemble` of 3.47).
  static const _linuxMinimumFlutter = (3, 47);

  /// Why Linux runners cannot build the iOS app, from the project alone
  /// (ADR 0014): plugins that build with CocoaPods, Run Script phases beyond
  /// Flutter's own, a Flutter older than 3.47. A storyboard Linux cannot
  /// compile fails the build with ibtool's error instead; the owner can turn
  /// Linux iOS builds off for the app.
  Future<List<String>> _iosLinuxLimits(
    IosPackageManager packageManager,
    String? flutterVersion,
  ) async {
    final pods = await _cocoaPodsPlugins();
    final (major, minor) = _linuxMinimumFlutter;
    final version = RegExp(r'^(\d+)\.(\d+)').firstMatch(flutterVersion ?? '');
    final (pinMajor, pinMinor) = version == null
        ? (major, minor)
        : (int.parse(version[1]!), int.parse(version[2]!));
    final tooOld = pinMajor < major || (pinMajor == major && pinMinor < minor);
    final reasons = <String>[];
    if (packageManager == IosPackageManager.cocoapods) {
      reasons.add(
        'the app builds its iOS plugins with CocoaPods, and Linux iOS builds '
        'need Swift Package Manager (flutter config '
        '--enable-swift-package-manager)',
      );
    } else if (pods.isNotEmpty) {
      final one = pods.length == 1;
      reasons.add(
        'the plugin${one ? '' : 's'} ${pods.join(', ')} '
        '${one ? 'builds' : 'build'} with CocoaPods, without a Package.swift, '
        'which Linux iOS builds cannot (omarchy-apple-dev: SwiftPM plugins '
        'only)',
      );
    }
    final target = _xcode?.appTarget;
    final scripts = [
      for (final phase in target?.scriptPhases ?? const <XcodeScriptPhase>[])
        if (!phase.isFlutter && !phase.isCocoaPods) '"${phase.name}"',
    ];
    if (scripts.isNotEmpty) {
      final one = scripts.length == 1;
      reasons.add(
        'the ${target!.name} target runs the Run Script phase${one ? '' : 's'} '
        '${scripts.join(', ')}, which Linux iOS builds skip, so what '
        "${one ? 'it does' : 'they do'} (such as copying the flavor's "
        'GoogleService-Info.plist) would be missing from the build',
      );
    }
    if (tooOld) {
      reasons.add(
        'the app pins Flutter $flutterVersion, and Linux iOS builds need '
        '$major.$minor or later',
      );
    }
    return reasons;
  }

  /// The plugins `ios/Podfile.lock` installs with CocoaPods: those of its
  /// `DEPENDENCIES` from `.symlinks/plugins`.
  Future<List<String>> _cocoaPodsPlugins() async {
    final lock = await _source.read(_at('ios/Podfile.lock'));
    if (lock == null) return const [];
    return [
      for (final match in RegExp(
        r'^  - (\S+) \(from `\.symlinks/plugins/',
        multiLine: true,
      ).allMatches(lock))
        match[1]!,
    ]..sort();
  }

  static const _needsMacFix =
      'Nothing to do to build on a Mac. To build on Linux (ADR 0014), lift '
      'each reason; until then its iOS jobs wait for a Mac (ios-sign).';

  /// Says that the iOS app needs a Mac, and why, when it has [extensions] or
  /// other [limits].
  void _checkIosLinux({
    required List<String> extensions,
    required List<String> limits,
  }) {
    final reasons = [
      if (extensions.isNotEmpty) extensionsLimit(extensions),
      ...limits,
    ];
    if (reasons.isEmpty) return;
    _add(
      FindingSeverity.info,
      'ios_needs_mac',
      'Needs a Mac for iOS: Linux runners cannot build it because '
          '${reasons.join('; ')}.',
      _needsMacFix,
      path: _at('ios'),
    );
  }

  /// Says that the iOS app of [flavor] needs a Mac, and why, when its own
  /// configuration rules Linux out.
  void _checkFlavorIosLinux(FlavorProfile flavor) {
    if (flavor.iosLinuxLimits.isEmpty) return;
    _add(
      FindingSeverity.info,
      'ios_needs_mac',
      'Flavor ${flavor.name} needs a Mac for iOS: Linux runners cannot build '
          'it because ${flavor.iosLinuxLimits.join('; ')}.',
      _needsMacFix,
      path: _at('ios'),
      flavor: flavor.name,
    );
  }

  /// Why Linux runners cannot build [flavor] from its own configuration, the
  /// one `flutter build` picks, where a Mac builds it: an Info.plist other
  /// than `Runner/Info.plist`, an app icon set outside
  /// `Runner/Assets.xcassets`, a multi-size app icon set. Warns about what
  /// fails on a Mac as much: no such configuration (unless the scan [warned]
  /// already) or several, a missing app icon set.
  Future<List<String>> _flavorIosLinuxLimits(
    String flavor, {
    required bool implicit,
    required XcodeProject xcode,
    required XcodeTarget target,
    required bool warned,
  }) async {
    final pbxproj = _at('ios/Runner.xcodeproj/project.pbxproj');
    final build = implicit ? 'flutter build' : 'flutter build --flavor $flavor';
    final candidates = xcode.releaseConfigurationsFor(
      target,
      implicit ? null : flavor,
    );
    if (candidates.isEmpty && !warned) {
      _add(
        FindingSeverity.warning,
        'ios_flavor_configuration_missing',
        '$build looks for the build configuration Release-$flavor, which '
            'the Xcode project does not have.',
        'Name the Release configuration of $flavor Release-$flavor, for '
            'example by running flutter_flavorizr.',
        path: pbxproj,
        flavor: flavor,
      );
    }
    if (candidates.length > 1) {
      _add(
        FindingSeverity.warning,
        'ios_flavor_configuration_ambiguous',
        '$build matches the build configurations ${candidates.join(', ')}, '
            'and builds none of them.',
        'Rename them so that one is called '
            '${implicit ? 'Release' : 'Release-$flavor'}.',
        path: pbxproj,
        flavor: implicit ? null : flavor,
      );
    }
    if (candidates.length != 1) return const [];

    final configuration = candidates.single;
    final settings = xcode.layeredSettingsOf(target, configuration, {
      for (final path in xcode.baseConfigurationsOf(target, configuration))
        path: await _xcconfig(
          normalizeScanPath(joinScanPath(_at('ios'), path)),
        ),
    });
    final plist = normalizeScanPath(
      expandBuildSetting(
        (settings['INFOPLIST_FILE'] ?? '')
            .replaceFirst(r'$(SRCROOT)/', '')
            .replaceFirst(r'$(PROJECT_DIR)/', ''),
        settings,
      ),
    );
    final limits = <String>[];
    if (plist.isNotEmpty && plist != _linuxInfoPlist) {
      limits.add(
        'its configuration $configuration reads the Info.plist $plist, and '
        'Linux iOS builds read $_linuxInfoPlist only (omarchy-apple-dev: an '
        'Info.plist per configuration)',
      );
    }
    final icon = expandBuildSetting(
      settings['ASSETCATALOG_COMPILER_APPICON_NAME'] ?? '',
      settings,
    );
    if (icon.isEmpty || icon.contains(r'$')) return limits;
    final linuxCatalog = normalizeScanPath(_at('ios/$_linuxAssetCatalog'));
    final catalogs = [
      for (final resource in target.resources)
        if (resource.endsWith('.xcassets'))
          if (normalizeScanPath(joinScanPath(_at('ios'), resource))
              case final catalog when await _source.exists(catalog))
            catalog,
    ];
    // The catalog Linux builds compile first, as the set is taken from it
    // when several have one.
    for (final catalog in [
      ...catalogs.where((catalog) => catalog == linuxCatalog),
      ...catalogs.where((catalog) => catalog != linuxCatalog),
    ]) {
      final contents = await _source.read(
        joinScanPath(catalog, '$icon.appiconset/Contents.json'),
      );
      if (contents == null) continue;
      if (catalog != linuxCatalog) {
        limits.add(
          'its configuration $configuration takes the app icon set $icon '
          'from $catalog, and Linux iOS builds take app icons from '
          '$linuxCatalog only (omarchy-apple-dev: asset catalogs beyond '
          '$_linuxAssetCatalog)',
        );
      }
      if (_multiSize(contents)) {
        limits.add(
          'its configuration $configuration uses the app icon set $icon, '
          'which has several sizes, and App Store processing of a Linux build '
          'can get stuck on one without an error (omarchy-apple-dev: '
          'single-size app icons; a single 1024x1024 icon lifts it)',
        );
      }
      return limits;
    }
    if (catalogs.isNotEmpty) {
      _add(
        FindingSeverity.warning,
        'ios_app_icon_missing',
        'The configuration $configuration of '
            '${implicit ? 'the app' : 'flavor $flavor'} '
            'uses the app icon set $icon, which no asset catalog of the '
            '${target.name} target has.',
        'Add $icon.appiconset to ${catalogs.join(' or ')}, or set '
            'ASSETCATALOG_COMPILER_APPICON_NAME of $configuration to an icon '
            'set it has.',
        path: catalogs.first,
        flavor: implicit ? null : flavor,
      );
    }
    return limits;
  }

  /// The Info.plist of the Runner target, relative to `ios`, the only one
  /// Linux iOS builds read.
  static const _linuxInfoPlist = 'Runner/Info.plist';

  /// The asset catalog of the Runner target, relative to `ios`, the only one
  /// Linux iOS builds take app icons from.
  static const _linuxAssetCatalog = 'Runner/Assets.xcassets';

  /// The settings of the `.xcconfig` at [path] over those of its includes;
  /// none when it cannot be read.
  Future<Map<String, String>> _xcconfig(String path, [int depth = 0]) async {
    final text = depth > 8 ? null : await _source.read(path);
    if (text == null) return const {};
    final file = parseXcconfig(text);
    return {
      for (final include in file.includes)
        ...await _xcconfig(normalizeScanPath('$path/../$include'), depth + 1),
      ...file.settings,
    };
  }

  /// Whether the `Contents.json` of an app icon set has an icon of another
  /// size than the single 1024x1024 one.
  static bool _multiSize(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      return false;
    }
    return switch (json) {
      {'images': final List<Object?> images} => images.any(
        (image) => switch (image) {
          {'size': final String size} => size != '1024x1024',
          _ => false,
        },
      ),
      _ => false,
    };
  }

  /// Says which flavor the Firebase files of a platform leave out: its
  /// builds then need an id to be uploaded to Firebase.
  void _checkFirebase(
    FirebaseFiles firebase,
    List<FlavorProfile> flavors,
    Map<String, Map<String, String>> ids, {
    required bool implicit,
  }) {
    for (final flavor in flavors) {
      for (final platform in [if (hasAndroid) 'android', if (hasIos) 'ios']) {
        if (!firebase.covers(platform)) continue;
        if (ids[flavor.name]!.containsKey(platform)) continue;
        final appId = platform == 'android'
            ? flavor.androidAppId
            : flavor.iosBundleId;
        final subject = implicit ? 'the app' : 'flavor ${flavor.name}';
        _add(
          FindingSeverity.info,
          'firebase_app_id_missing',
          'The Firebase files name no $platform app for $subject'
              '${appId == null ? '' : ' ($appId)'}, so its builds are not '
              'uploaded to Firebase until it has an id.',
          'Set the Firebase app id of $subject in XPath, or add '
              '${appId ?? 'the app'} to the Firebase project and download '
              'its config file again.',
          flavor: implicit ? null : flavor.name,
        );
      }
    }
  }

  // ------------------------------------------------------- build systems

  Future<GradleInfo> _readGradle() async {
    final directory = _at('android/app');
    final files = [
      for (final entry in await _source.list(directory))
        if (!entry.isDirectory &&
            (entry.name.endsWith('.gradle') ||
                entry.name.endsWith('.gradle.kts')))
          entry.name,
    ];
    // `build.gradle` first: the generated flavor scripts only add to it.
    int rank(String file) => file.startsWith('build.gradle') ? 0 : 1;
    files.sort(
      (a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.compareTo(b),
    );
    var info = const GradleInfo();
    for (final file in files) {
      final text = await _source.read(joinScanPath(directory, file));
      if (text != null) info = info.merge(parseGradle(text));
    }
    final gradle = info;
    if (gradle.dimensions.length > 1) {
      _add(
        FindingSeverity.warning,
        'gradle_multiple_dimensions',
        'Gradle has several flavor dimensions '
            '(${(gradle.dimensions.toList()..sort()).join(', ')}); XPath '
            'reads flavors one dimension deep.',
        'Edit the flavors of the profile by hand.',
        path: directory,
      );
    }
    if (gradle.mentionsProductFlavors && gradle.flavors.isEmpty) {
      _add(
        FindingSeverity.warning,
        'gradle_flavors_unreadable',
        'Gradle declares productFlavors but none could be read.',
        'Write each flavor as `name { applicationId "..." }` or '
            '`create("name") { applicationId = "..." }`, or fill the flavors '
            'in by hand.',
        path: directory,
      );
    }
    return gradle;
  }

  Future<Map<String, _Declared>> _readFlavorizr() async {
    final path = _at('flavorizr.yaml');
    final yaml = await _context.yaml(
      path,
      invalid: (error) => _add(
        FindingSeverity.warning,
        'flavorizr_yaml_invalid',
        '$path is not valid YAML: $error',
        'Fix the syntax error in flavorizr.yaml.',
        path: path,
      ),
    );
    final flavors = _map(yaml?['flavors']);
    return {
      if (flavors != null)
        for (final entry in flavors.entries)
          '${entry.key}': _Declared(
            android: _string(
              _map(_map(entry.value)?['android'])?['applicationId'],
            ),
            ios: _string(_map(_map(entry.value)?['ios'])?['bundleId']),
          ),
    };
  }

  Future<XcodeProject?> _readXcode() async {
    final path = _at('ios/Runner.xcodeproj/project.pbxproj');
    final text = await _source.read(path);
    final project = text == null ? null : parseXcodeProject(text);
    if (project == null) {
      _add(
        FindingSeverity.warning,
        'xcode_project_unreadable',
        'The Xcode project could not be read, so iOS ids, teams and '
            'plists are unknown.',
        'Open the project in Xcode to repair it, or fill the iOS values in '
            'by hand.',
        path: path,
      );
    }
    return project;
  }

  /// The flavor schemes: scheme name to the configuration it archives with.
  /// The plain `Runner` scheme of an app without flavors archives `Release`
  /// and is not one.
  Future<Map<String, String>> _readSchemes() async {
    final directory = _at('ios/Runner.xcodeproj/xcshareddata/xcschemes');
    final schemes = <String, String>{};
    for (final entry in await _source.list(directory)) {
      if (entry.isDirectory || !entry.name.endsWith('.xcscheme')) continue;
      final text = await _source.read(joinScanPath(directory, entry.name));
      final archive = text == null ? null : schemeArchiveConfiguration(text);
      if (archive != null && archive.startsWith('Release-')) {
        schemes[entry.name.substring(
              0,
              entry.name.length - '.xcscheme'.length,
            )] =
            archive;
      }
    }
    return schemes;
  }

  /// `lib/main_<flavor>.dart` files: flavor to the entrypoint, relative to
  /// the app.
  Future<Map<String, String>> _readEntrypoints() async {
    final pattern = RegExp(r'^main_(.+)\.dart$');
    return {
      for (final entry in await _source.list(_at('lib')))
        if (!entry.isDirectory)
          if (pattern.firstMatch(entry.name) case final match?)
            match.group(1)!: 'lib/${entry.name}',
    };
  }

  /// The flavor names, in the order Gradle, flavorizr, Xcode (and, when none
  /// of them declares a flavor, the entrypoints) give them. Empty when the
  /// app has no flavors.
  List<String> _flavorNames() {
    final fromBuildSystems = <String>{
      ...?_gradle?.flavors.map((flavor) => flavor.name),
      ..._declared.keys,
      ..._schemes.keys,
    };
    if (fromBuildSystems.isEmpty) return _entrypoints.keys.toList();
    for (final extra in _entrypoints.keys.where(
      (entry) => !fromBuildSystems.contains(entry),
    )) {
      _add(
        FindingSeverity.info,
        'entrypoint_without_flavor',
        'lib/main_$extra.dart has no flavor of that name in Gradle, '
            'flutter_flavorizr or Xcode, so it is not treated as a flavor.',
        'Ignore this if it is a special build of another flavor; otherwise '
            'add the flavor to the Android and iOS projects.',
        path: _at('lib/main_$extra.dart'),
      );
    }
    return fromBuildSystems.toList();
  }

  // -------------------------------------------------------------- flavor

  Future<FlavorProfile> _flavor(
    String flavor, {
    required bool implicit,
    required ShorebirdProfile? shorebird,
  }) async {
    final gradle = _gradle;
    final gradleFlavor = gradle?.flavors
        .where((candidate) => candidate.name == flavor)
        .firstOrNull;
    final declared = _declared[flavor];
    final androidActual = implicit
        ? gradle?.defaultApplicationId
        : (gradleFlavor == null ? null : gradle!.applicationIdOf(gradleFlavor));

    // Xcode: the configuration that archiving the flavor's scheme uses.
    final suffix = implicit ? '' : '-$flavor';
    final releaseConfiguration = _schemes[flavor] ?? 'Release$suffix';
    final xcode = _xcode;
    final target = xcode?.appTarget;
    final settings = target == null
        ? null
        : xcode!.settingsOf(target, releaseConfiguration);
    if (xcode != null && !implicit && settings == null) {
      _add(
        FindingSeverity.warning,
        'ios_flavor_without_scheme',
        'Flavor $flavor has no Xcode scheme or "$releaseConfiguration" '
            'build configuration.',
        'Create a scheme called $flavor that archives with '
            '"$releaseConfiguration", for example by running '
            'flutter_flavorizr.',
        path: _at('ios/Runner.xcodeproj'),
        flavor: flavor,
      );
    }
    if (hasAndroid && !implicit && gradleFlavor == null) {
      _add(
        FindingSeverity.warning,
        'android_flavor_missing',
        'Flavor $flavor is not a productFlavor in the Gradle scripts.',
        'Add $flavor to productFlavors, for example by running '
            'flutter_flavorizr.',
        path: _at('android/app'),
        flavor: flavor,
      );
    }

    final iosActual = _iosBundleId(flavor, settings);
    if (settings != null && iosActual != null) {
      final others = {
        for (final kind in const ['Debug', 'Profile'])
          xcode!.settingsOf(
            target!,
            '$kind$suffix',
          )?['PRODUCT_BUNDLE_IDENTIFIER'],
      }..remove(null);
      if (others.any((other) => other != iosActual)) {
        _add(
          FindingSeverity.warning,
          'bundle_id_configs_differ',
          'The Debug, Profile and Release configurations of $flavor have '
              'different bundle ids.',
          'Give the three configurations of $flavor the same '
              'PRODUCT_BUNDLE_IDENTIFIER.',
          path: _at('ios/Runner.xcodeproj/project.pbxproj'),
          flavor: flavor,
        );
      }
    }
    final team = settings?['DEVELOPMENT_TEAM'];
    final literalTeam = team != null && !team.contains(r'$') ? team : null;
    if (settings != null && literalTeam == null) {
      _add(
        FindingSeverity.warning,
        'ios_team_missing',
        'Flavor $flavor builds without a DEVELOPMENT_TEAM.',
        "Select the team in Xcode, or keep one in the flavor's XPath "
            'credentials.',
        path: _at('ios/Runner.xcodeproj/project.pbxproj'),
        flavor: flavor,
      );
    }

    final declaredAndroid = declared?.android;
    if (declaredAndroid != null &&
        androidActual != null &&
        declaredAndroid != androidActual) {
      _add(
        FindingSeverity.error,
        'bundle_id_config_drift',
        'flutter_flavorizr says $flavor is $declaredAndroid on Android, but '
            'Gradle builds $androidActual.',
        'Run flutter_flavorizr again, or make flavorizr.yaml and Gradle '
            'agree.',
        path: _at('flavorizr.yaml'),
        flavor: flavor,
      );
    }
    final declaredIos = declared?.ios;
    if (declaredIos != null && iosActual != null && declaredIos != iosActual) {
      _add(
        FindingSeverity.error,
        'bundle_id_config_drift',
        'flutter_flavorizr says $flavor is $declaredIos on iOS, but Xcode '
            'builds $iosActual.',
        'Run flutter_flavorizr again, or make flavorizr.yaml and the Xcode '
            'project agree.',
        path: _at('flavorizr.yaml'),
        flavor: flavor,
      );
    }
    final android = androidActual ?? declaredAndroid;
    final ios = iosActual ?? declaredIos;
    if (android != null && ios != null && android != ios) {
      final typo = editDistance(android, ios) <= 2;
      _add(
        FindingSeverity.warning,
        'bundle_id_platform_mismatch',
        'Flavor $flavor is $android on Android and $ios on iOS'
            '${typo ? ', which looks like a typo' : ''}.',
        typo
            ? 'If the two should match, fix the one that is misspelled; '
                  'otherwise ignore this.'
            : 'Ignore this if the apps are meant to have different ids; '
                  'otherwise make them agree.',
        flavor: flavor,
      );
    }

    final entrypoint = _entrypoints[flavor];
    if (!implicit && entrypoint == null && _entrypoints.isNotEmpty) {
      _add(
        FindingSeverity.warning,
        'entrypoint_missing',
        'Flavor $flavor has no lib/main_$flavor.dart, so it would build '
            'lib/main.dart.',
        'Add lib/main_$flavor.dart, or set the entrypoint in the profile.',
        path: _at('lib/main_$flavor.dart'),
        flavor: flavor,
      );
    }

    final shorebirdId = implicit
        ? shorebird?.appId
        : shorebird?.flavorAppIds[flavor];
    final iosLinuxLimits = xcode != null && target != null
        ? await _flavorIosLinuxLimits(
            flavor,
            implicit: implicit,
            xcode: xcode,
            target: target,
            warned: settings == null,
          )
        : const <String>[];
    return FlavorProfile(
      name: flavor,
      implicit: implicit,
      entrypoint: entrypoint ?? 'lib/main.dart',
      iosBundleId: ios,
      androidAppId: android,
      iosTeam: literalTeam,
      iosScheme: _schemes.containsKey(flavor) ? flavor : null,
      infoPlist: await _infoPlist(flavor, settings),
      shorebird: shorebirdId != null,
      shorebirdAppId: shorebirdId,
      prod: implicit || _prodNames.contains(flavor),
      sources: [
        if (!implicit) ...[
          if (gradleFlavor != null) 'gradle',
          if (declared != null) 'flavorizr',
          if (_schemes.containsKey(flavor)) 'xcscheme',
          if (entrypoint != null) 'entrypoint',
        ],
      ],
      iosLinuxLimits: iosLinuxLimits,
    );
  }

  String? _iosBundleId(String flavor, Map<String, String>? settings) {
    final id = settings?['PRODUCT_BUNDLE_IDENTIFIER'];
    if (id == null) return null;
    if (!id.contains(r'$')) return id;
    _add(
      FindingSeverity.warning,
      'ios_bundle_id_unresolved',
      'The bundle id of $flavor is $id, a build variable.',
      'Set PRODUCT_BUNDLE_IDENTIFIER to a literal in the target, or edit the '
          'bundle id in the profile.',
      path: _at('ios/Runner.xcodeproj/project.pbxproj'),
      flavor: flavor,
    );
    return null;
  }

  /// Reads the `Info.plist` of [settings] once and returns its path, or
  /// `null` if the flavor has none or it is missing.
  Future<String?> _infoPlist(
    String flavor,
    Map<String, String>? settings,
  ) async {
    final setting = settings?['INFOPLIST_FILE'];
    if (setting == null) return null;
    final path = normalizeScanPath(
      joinScanPath(
        _at('ios'),
        setting
            .replaceFirst(r'$(SRCROOT)/', '')
            .replaceFirst(r'$(PROJECT_DIR)/', ''),
      ),
    );
    if (_plists.containsKey(path)) return path;
    final text = await _source.read(path);
    if (text == null) {
      _add(
        FindingSeverity.warning,
        'plist_missing',
        'The Info.plist of $flavor, $path, does not exist.',
        'Create it or point INFOPLIST_FILE at the right file.',
        path: path,
        flavor: flavor,
      );
      return null;
    }
    final shortVersion = plistString(text, 'CFBundleShortVersionString');
    final buildNumber = plistString(text, 'CFBundleVersion');
    _plists[path] = PlistVersion(
      path: path,
      shortVersion: shortVersion,
      buildNumber: buildNumber,
      literal: [
        shortVersion,
        buildNumber,
      ].any((value) => value != null && !isBuildVariable(value)),
    );
    return path;
  }

  // ---------------------------------------------------------- the rest

  void _checkVersions(_Version? version, Object? versionText) {
    if (version == null) return;
    for (final plist in _plists.values.where((plist) => plist.literal)) {
      final shortVersion = plist.shortVersion;
      final buildNumber = plist.buildNumber;
      final shortDiffers =
          shortVersion != null &&
          !isBuildVariable(shortVersion) &&
          shortVersion != version.name;
      final buildDiffers =
          buildNumber != null &&
          !isBuildVariable(buildNumber) &&
          buildNumber != version.build;
      if (shortDiffers || buildDiffers) {
        _add(
          FindingSeverity.error,
          'version_files_out_of_sync',
          '${plist.path} says ${shortVersion ?? '?'}+${buildNumber ?? '?'} '
              'but the pubspec says $versionText.',
          'Set the plist to the pubspec version, or bump both together.',
          path: plist.path,
        );
      }
    }
  }

  Future<ShorebirdProfile?> _readShorebird() async {
    final path = _at('shorebird.yaml');
    if (!await _source.exists(path)) return null;
    var reported = false;
    final yaml = await _context.yaml(
      path,
      invalid: (error) {
        reported = true;
        _add(
          FindingSeverity.error,
          'shorebird_yaml_invalid',
          '$path is not valid YAML: $error',
          'Fix the syntax error in shorebird.yaml.',
          path: path,
        );
      },
    );
    final appId = _string(yaml?['app_id']);
    final flavors = _map(yaml?['flavors']);
    if (appId == null && (flavors == null || flavors.isEmpty)) {
      if (!reported) {
        _add(
          FindingSeverity.error,
          'shorebird_yaml_invalid',
          '$path has no app_id.',
          'Run `shorebird init` to create a valid shorebird.yaml.',
          path: path,
        );
      }
      return null;
    }
    return ShorebirdProfile(
      appId: appId,
      flavorAppIds: {
        if (flavors != null)
          for (final entry in flavors.entries)
            '${entry.key}': ?_string(entry.value),
      },
    );
  }

  void _checkShorebird(
    ShorebirdProfile? shorebird,
    List<String> names, {
    required bool implicit,
  }) {
    if (shorebird == null) return;
    final path = _at('shorebird.yaml');
    if (!implicit && shorebird.flavorAppIds.isEmpty) {
      _add(
        FindingSeverity.warning,
        'shorebird_no_flavor_ids',
        'shorebird.yaml has an app_id but no flavors, while the app has '
            'flavors: every flavor would share one Shorebird app.',
        'Add a flavors: map to shorebird.yaml with one app id per flavor.',
        path: path,
      );
    }
    if (!implicit && shorebird.flavorAppIds.isNotEmpty) {
      for (final flavor in names.where(
        (flavor) => !shorebird.flavorAppIds.containsKey(flavor),
      )) {
        _add(
          FindingSeverity.info,
          'shorebird_flavor_without_id',
          'shorebird.yaml has no app id for flavor $flavor, so it cannot '
              'receive patches.',
          'Add $flavor to the flavors of shorebird.yaml if it should.',
          path: path,
          flavor: flavor,
        );
      }
    }
    for (final extra in shorebird.flavorAppIds.keys.where(
      (flavor) => !names.contains(flavor),
    )) {
      _add(
        FindingSeverity.warning,
        'shorebird_unknown_flavor',
        'shorebird.yaml lists flavor $extra, which the app does not have.',
        'Remove it from shorebird.yaml or add the flavor.',
        path: path,
        flavor: extra,
      );
    }
  }

  Future<IosPackageManager> _packageManager() async {
    final hasPodfile = hasIos && await _source.exists(_at('ios/Podfile'));
    final usesSwiftPackages = _xcode?.usesSwiftPackages ?? false;
    final manager = switch ((hasPodfile, usesSwiftPackages)) {
      (true, true) => IosPackageManager.both,
      (true, false) => IosPackageManager.cocoapods,
      (false, true) => IosPackageManager.spm,
      (false, false) => IosPackageManager.none,
    };
    if (manager == IosPackageManager.both) {
      _add(
        FindingSeverity.info,
        'ios_spm_and_cocoapods',
        'The iOS project uses both CocoaPods and Swift Package Manager.',
        'Nothing to do; builds run pod install and resolve the packages.',
        path: _at('ios'),
      );
    }
    return manager;
  }

  Future<KeystoreProfile?> _keystore() async {
    final gradle = _gradle;
    if (gradle == null) return null;
    final reference = gradle.keyPropertiesReference;
    if (reference == null) {
      _add(
        FindingSeverity.info,
        'keystore_not_referenced',
        'The Gradle scripts do not read a key.properties file, so release '
            'builds are not signed with a release keystore from there.',
        'Ignore this if signing is configured another way; otherwise add a '
            'release signingConfig that reads key.properties.',
        path: _at('android/app'),
      );
      return null;
    }
    final path = normalizeScanPath(joinScanPath(_at('android'), reference));
    final properties = await _source.read(path);
    if (properties == null) {
      _add(
        FindingSeverity.warning,
        'keystore_properties_missing',
        'Gradle reads $path for the release keystore, but the scanned '
            'folder has none (it is normally ignored by git).',
        'Store the keystore and its passwords in XPath; it writes '
            "key.properties into each job's own checkout, never into the "
            'repository.',
        path: path,
      );
    }
    return KeystoreProfile(
      propertiesPath: path,
      propertiesPresent: properties != null,
      storeFile: properties == null ? null : _storeFile(properties),
    );
  }
}

/// The `storeFile` entry of a `key.properties`. Nothing else is read: the
/// other entries are passwords.
String? _storeFile(String properties) => RegExp(
  r'^\s*storeFile\s*[=:]\s*(.+?)\s*$',
  multiLine: true,
).firstMatch(properties)?.group(1);

String? _string(Object? value) => value == null ? null : '$value';
