import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

final _flavorName = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

/// What `build.android` and `build.ios` have in common: where to build, which
/// flavor and version, and the inputs of the build.
///
/// The workflow engine fills it in when the job is created (Phase 11), so the
/// stored input is all a resumed job needs.
class BuildSettings extends Equatable {
  /// Creates the settings.
  const new({
    required this.worktree,
    required this.version,
    this.flavor,
    this.target,
    this.flutterVersion,
    this.dartDefineFile,
    this.obfuscate = false,
    this.secretEnvironment = const {},
    this.secretFiles = const {},
    this.passThroughEnvironment = const [],
  });

  /// Reads the settings from their stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// `version` is not `x.y.z+build`, `flavor` is not a Gradle flavor name or a
  /// path leaves the app.
  factory fromJson(Map<String, dynamic> json) {
    final version = AppVersion.parse(requiredString(json, 'version'));
    if (version.build == null) {
      throw const FormatException('"version" needs a build number.');
    }
    final flavor = optionalString(json, 'flavor');
    if (flavor != null && !_flavorName.hasMatch(flavor)) {
      throw FormatException('"$flavor" is not a flavor name.');
    }
    return BuildSettings(
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      version: version,
      flavor: flavor,
      target: _relativePath(json, 'target'),
      flutterVersion: optionalString(json, 'flutterVersion'),
      dartDefineFile: _relativePath(json, 'dartDefineFile'),
      obfuscate: optionalFlag(json, 'obfuscate'),
      secretEnvironment: stringMap(json, 'secretEnvironment'),
      secretFiles: stringMap(json, 'secretFiles'),
      passThroughEnvironment: stringList(json, 'passThroughEnvironment'),
    );
  }

  /// The worktree of the job and the app in it.
  final ReleaseWorktree worktree;

  /// The version to build. The build number comes from the build counter,
  /// allocated when the release was dispatched (D-11).
  final AppVersion version;

  /// The flavor (`--flavor`), or `null` for an app without flavors.
  final String? flavor;

  /// The entrypoint (`--target`), relative to the app, such as
  /// `lib/main_dev.dart`; `null` for `lib/main.dart`.
  final String? target;

  /// The Flutter version the app pins in `.fvmrc`, as the scan read it.
  final String? flutterVersion;

  /// The file for `--dart-define-from-file`, relative to the app.
  final String? dartDefineFile;

  /// Whether to obfuscate the Dart code and split the debug info out
  /// (`--obfuscate --split-debug-info`).
  final bool obfuscate;

  /// Secrets passed to the build in environment variables (variable name to
  /// secret key), for example the passwords of an Android keystore. Never
  /// arguments.
  final Map<String, String> secretEnvironment;

  /// Secrets passed to the build as files (variable name to secret key): the
  /// variable holds the path of a file with mode 0600 that is deleted when the
  /// job ends, for example the keystore.
  final Map<String, String> secretFiles;

  /// Variables of the engine's own environment the build needs on top of the
  /// ones that every build gets.
  final List<String> passThroughEnvironment;

  /// The app's directory.
  String get appDirectory => worktree.appPath == '.'
      ? worktree.path
      : '${worktree.path}/${worktree.appPath}';

  /// The build number; it is always there.
  int get build => version.build!;

  /// What names the files of this build: `dev-1.2.3+45`.
  String get label => '${flavor ?? 'app'}-$version';

  /// The flags that every `flutter build` of a release takes.
  ///
  /// The build name and number are passed even where a platform file carries a
  /// literal version: Flutter ignores them there, and `version.bump` wrote the
  /// same numbers.
  List<String> flutterArguments({String? debugInfoDirectory}) => [
    '--release',
    if (flavor != null) ...['--flavor', flavor!],
    if (target != null) ...['--target', target!],
    '--build-name=${version.name}',
    '--build-number=$build',
    if (dartDefineFile != null) '--dart-define-from-file=$dartDefineFile',
    if (obfuscate && debugInfoDirectory != null) ...[
      '--obfuscate',
      '--split-debug-info=$debugInfoDirectory',
    ],
  ];

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'version': '$version',
    'flavor': ?flavor,
    'target': ?target,
    'flutterVersion': ?flutterVersion,
    'dartDefineFile': ?dartDefineFile,
    'obfuscate': obfuscate,
    'secretEnvironment': secretEnvironment,
    'secretFiles': secretFiles,
    'passThroughEnvironment': passThroughEnvironment,
  };

  @override
  List<Object?> get props => [
    worktree,
    version,
    flavor,
    target,
    flutterVersion,
    dartDefineFile,
    obfuscate,
    secretEnvironment,
    secretFiles,
    passThroughEnvironment,
  ];
}

/// The path at [field], which must stay inside the app: relative, not
/// starting with `-`, without `..`.
String requiredRelative(Map<String, dynamic> json, String field) {
  final path = requiredString(json, field);
  _checkRelative(path, field);
  return path;
}

String? _relativePath(Map<String, dynamic> json, String field) {
  final path = optionalString(json, field);
  if (path != null) _checkRelative(path, field);
  return path;
}

void _checkRelative(String path, String field) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith('-') ||
      path.split('/').contains('..')) {
    throw FormatException('"$field" must be a path inside the app.');
  }
}
