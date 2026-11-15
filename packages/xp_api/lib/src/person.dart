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

/// The body of `GET /people`: every person, removed ones included, oldest
/// first.
@JsonSerializable(explicitToJson: true)
class PeopleResponse extends Equatable {
  /// Creates the response.
  const new(this.people);

  /// Reads the response from its JSON form.
  factory PeopleResponse.fromJson(Map<String, dynamic> json) =>
      _$PeopleResponseFromJson(json);

  /// The people, oldest first.
  final List<Person> people;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PeopleResponseToJson(this);

  @override
  List<Object?> get props => [people];
}

/// The body of `POST /people`: a new person called [name] with [role].
@JsonSerializable(checked: true)
class CreatePersonRequest extends Equatable {
  /// Creates the request.
  const new({required this.name, required this.role});

  /// Reads the request from its JSON form.
  factory CreatePersonRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePersonRequestFromJson(json);

  /// What the person is called, 1 to 80 characters.
  final String name;

  /// What the person may do.
  final PersonRole role;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CreatePersonRequestToJson(this);

  @override
  List<Object?> get props => [name, role];
}

/// The body of `PATCH /people/{id}`: a new [name], a new [role], or both.
@JsonSerializable(includeIfNull: false, checked: true)
class UpdatePersonRequest extends Equatable {
  /// Creates the request.
  const new({this.name, this.role});

  /// Reads the request from its JSON form.
  factory UpdatePersonRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdatePersonRequestFromJson(json);

  /// The new name, 1 to 80 characters.
  final String? name;

  /// The new role. It applies to the person's next request.
  final PersonRole? role;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$UpdatePersonRequestToJson(this);

  @override
  List<Object?> get props => [name, role];
}
