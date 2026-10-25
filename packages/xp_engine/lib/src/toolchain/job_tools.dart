import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';
import 'package:xp_engine/src/toolchain/tool_report.dart';

/// The versions of the tools a job ran with (D-20), recorded with the job.
///
/// A Shorebird patch is built with the Flutter version of the release it
/// patches, which is the [flutter] recorded for the job that made the release.
class JobTools extends Equatable {
  /// Creates the record. A tool that is absent is `null`.
  const new({
    this.flutter,
    this.dart,
    this.shorebird,
    this.gh,
    this.xcode,
    this.iosLinux,
  });

  /// The versions of the Flutter SDK a job resolved and of the other tools
  /// that [reports] found. A tool that is not available is not recorded.
  /// [iosLinux] is what built iOS on Linux, if anything did.
  factory from({
    ResolvedFlutter? flutter,
    Iterable<ToolReport> reports = const [],
    String? iosLinux,
  }) {
    String? versionOf(String tool) => reports
        .where((report) => report.tool == tool && report.isAvailable)
        .map((report) => report.version)
        .firstOrNull;
    return JobTools(
      flutter: flutter?.version,
      dart: flutter?.dartVersion,
      shorebird: versionOf('shorebird'),
      gh: versionOf('gh'),
      xcode: versionOf('xcode'),
      iosLinux: iosLinux,
    );
  }

  /// Reads the record from its JSON form.
  ///
  /// Throws a [FormatException] if a field is not a string.
  factory fromJson(Map<String, dynamic> json) => JobTools(
    flutter: optionalString(json, 'flutter'),
    dart: optionalString(json, 'dart'),
    shorebird: optionalString(json, 'shorebird'),
    gh: optionalString(json, 'gh'),
    xcode: optionalString(json, 'xcode'),
    iosLinux: optionalString(json, 'iosLinux'),
  );

  /// The Flutter version, such as `3.47.6`.
  final String? flutter;

  /// The Dart version of that Flutter SDK.
  final String? dart;

  /// The Shorebird CLI version.
  final String? shorebird;

  /// The GitHub CLI version.
  final String? gh;

  /// The Xcode version; `null` on Linux.
  final String? xcode;

  /// What built the iOS app on Linux (ADR 0014): "Linux, omarchy-apple-dev
  /// `<commit>`"; `null` for any other build.
  final String? iosLinux;

  /// The JSON form; a tool that is absent is left out.
  Map<String, dynamic> toJson() => {
    'flutter': ?flutter,
    'dart': ?dart,
    'shorebird': ?shorebird,
    'gh': ?gh,
    'xcode': ?xcode,
    'iosLinux': ?iosLinux,
  };

  @override
  List<Object?> get props => [flutter, dart, shorebird, gh, xcode, iosLinux];
}
