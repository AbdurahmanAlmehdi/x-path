// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'version_response.g.dart';

/// The body of `GET /version`.
@JsonSerializable()
class VersionResponse extends Equatable {
  /// Creates a version response.
  const new({required this.version, required this.apiVersion});

  /// Reads a version response from its JSON form.
  factory VersionResponse.fromJson(Map<String, dynamic> json) =>
      _$VersionResponseFromJson(json);

  /// The engine's own version, for example `0.0.1`.
  final String version;

  /// The major version of the API the engine serves.
  final String apiVersion;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$VersionResponseToJson(this);

  @override
  List<Object?> get props => [version, apiVersion];
}
