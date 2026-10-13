// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'finding.g.dart';

/// How much a [Finding] matters to a release.
enum FindingSeverity {
  /// A release would fail or ship something wrong until it is fixed.
  error,

  /// Probably unintended or fragile; a release can still go ahead.
  warning,

  /// Worth knowing; no action needed.
  info,
}

/// Something a scan noticed about a repository, with what to do about it.
@JsonSerializable(includeIfNull: false)
class Finding extends Equatable {
  /// Creates a finding.
  const new({
    required this.severity,
    required this.code,
    required this.message,
    required this.fix,
    this.path,
    this.app,
    this.flavor,
  });

  /// Reads a finding from its JSON form.
  factory Finding.fromJson(Map<String, dynamic> json) =>
      _$FindingFromJson(json);

  /// How much it matters.
  final FindingSeverity severity;

  /// A stable snake_case identifier, for example `plist_literal_version`.
  final String code;

  /// What was found.
  final String message;

  /// What to change to resolve it. Never an instruction for XPath itself to
  /// edit the scanned repository (D-04).
  final String fix;

  /// The file the finding is about, relative to the repository root.
  final String? path;

  /// The path of the app it is about, relative to the repository root.
  final String? app;

  /// The flavor it is about.
  final String? flavor;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$FindingToJson(this);

  @override
  List<Object?> get props => [severity, code, message, fix, path, app, flavor];
}
