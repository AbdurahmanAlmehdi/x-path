// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'person.g.dart';

/// What a person may do (ADR 0017). Each role may do everything the roles
/// before it may.
enum PersonRole {
  /// Reads everything a token can read, and changes nothing.
  viewer,

  /// Dispatches workflows, runs tests and edits workflows.
  developer,

  /// Decides approvals and drives releases.
  releaser,

  /// Changes the engine: projects, credentials, runners, storage, people.
  admin;

  /// Whether this role may do everything [other] may.
  bool isAtLeast(PersonRole other) => index >= other.index;
}

/// Someone who uses the engine. Every token but a runner's belongs to one
/// (ADR 0017).
@JsonSerializable(includeIfNull: false)
class Person extends Equatable {
  /// Creates a person.
  const new({
    required this.id,
    required this.name,
    required this.role,
    required this.createdAt,
    this.removedAt,
  });

  /// Reads a person from its JSON form.
  factory Person.fromJson(Map<String, dynamic> json) => _$PersonFromJson(json);

  /// The engine's id, for example `per_1a2b3c4d5e6f7a8b`.
  final String id;

  /// What the person is called, for example `Sam`.
  final String name;

  /// What the person may do.
  final PersonRole role;

  /// When the person was added, in UTC.
  final DateTime createdAt;

  /// When the person was removed, in UTC, or `null` while they are active. A
  /// removed person's tokens are revoked; approvals keep their name.
  final DateTime? removedAt;

  /// Whether the person was removed.
  bool get isRemoved => removedAt != null;

  /// This person with a new [name], [role] or [removedAt].
  Person copyWith({String? name, PersonRole? role, DateTime? removedAt}) =>
      Person(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        createdAt: createdAt,
        removedAt: removedAt ?? this.removedAt,
      );

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PersonToJson(this);

  @override
  List<Object?> get props => [id, name, role, createdAt, removedAt];
}
