import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:yaml/yaml.dart';

/// The `.fvmrc` a Flutter version was pinned in.
class FlutterPin {
  /// Creates a pin.
  const new({required this.version, required this.source});

  /// The pinned version, or `null` if the file could not be read.
  final String? version;

  /// The file, relative to the repository root.
  final String source;
}

/// What one scan shares: the source it reads, the findings it collects and
/// the files read more than once.
class ScanContext {
  /// Creates a context reading [source].
  new(this.source);

  /// The repository.
  final ScanSource source;

  /// The findings so far, in the order they were noticed.
  final findings = <Finding>[];

  final _pins = <String, FlutterPin?>{};

  /// Records a finding.
  void add(
    FindingSeverity severity,
    String code,
    String message,
    String fix, {
    String? path,
    String? app,
    String? flavor,
  }) => findings.add(
    Finding(
      severity: severity,
      code: code,
      message: message,
      fix: fix,
      path: path,
      app: app,
      flavor: flavor,
    ),
  );

  /// The YAML mapping in [path], or `null` if the file is missing, empty or
  /// not a mapping. A syntax error is passed to [invalid] first.
  Future<YamlMap?> yaml(
    String path, {
    void Function(String error)? invalid,
  }) async {
    final text = await source.read(path);
    if (text == null) return null;
    try {
      final document = loadYaml(text);
      return document is YamlMap ? document : null;
    } on YamlException catch (error) {
      invalid?.call(error.message);
      return null;
    }
  }

  /// The Flutter version pinned for the app in [dir]: its own `.fvmrc`, else
  /// the one at the repository root. `null` if there is none.
  Future<FlutterPin?> pin(String dir) async {
    for (final path in {joinScanPath(dir, '.fvmrc'), '.fvmrc'}) {
      final pin = await _readPin(path);
      if (pin != null) return pin;
    }
    return null;
  }

  Future<FlutterPin?> _readPin(String path) async {
    if (_pins.containsKey(path)) return _pins[path];
    final text = await source.read(path);
    return _pins[path] = text == null ? null : _parsePin(path, text);
  }

  FlutterPin _parsePin(String path, String text) {
    final version = _pinVersion(text);
    if (version == null) {
      add(
        FindingSeverity.error,
        'fvmrc_invalid',
        '$path is not a JSON object with a "flutter" version.',
        'Write it as {"flutter": "x.y.z"}.',
        path: path,
      );
    } else if (!_exactVersion.hasMatch(version)) {
      add(
        FindingSeverity.warning,
        'fvmrc_not_exact',
        '$path pins "$version", which is not an exact Flutter version, so '
            'builds change when the channel moves.',
        'Pin an exact version such as 3.47.4.',
        path: path,
      );
    }
    return FlutterPin(version: version, source: path);
  }

  static final _exactVersion = RegExp(r'^\d+\.\d+\.\d+([-+][\w.]+)?$');
}

String? _pinVersion(String text) {
  try {
    final json = jsonDecode(text);
    final flutter = json is Map<String, Object?> ? json['flutter'] : null;
    // `3.47.4@stable` pins a version on a channel; the version is what counts.
    return flutter is String ? flutter.split('@').first.trim() : null;
  } on FormatException {
    return null;
  }
}
