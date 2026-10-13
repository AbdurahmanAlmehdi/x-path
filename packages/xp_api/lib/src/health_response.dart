// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'health_response.g.dart';

/// The body of `GET /health`.
@JsonSerializable()
class HealthResponse extends Equatable {
  /// Creates a health response. [status] is `ok` while the engine serves.
  const new({this.status = 'ok'});

  /// Reads a health response from its JSON form.
  factory HealthResponse.fromJson(Map<String, dynamic> json) =>
      _$HealthResponseFromJson(json);

  /// Always `ok`: an engine that cannot answer is not healthy.
  final String status;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$HealthResponseToJson(this);

  @override
  List<Object?> get props => [status];
}
