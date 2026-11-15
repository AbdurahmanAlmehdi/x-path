// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'session.g.dart';

/// A one-time sign-in code for the web dashboard (ADR 0018): the answer of
/// `POST /people/{id}/sign-in-codes`. It works once, for ten minutes, and is
/// shown this once.
@JsonSerializable()
class SignInCode extends Equatable {
  /// Creates the code.
  const new({
    required this.code,
    required this.personId,
    required this.expiresAt,
  });

  /// Reads the code from its JSON form.
  factory SignInCode.fromJson(Map<String, dynamic> json) =>
      _$SignInCodeFromJson(json);

  /// The code, `XXXX-XXXX-XXXX-XXXX` in Crockford base32. Never logged.
  final String code;

  /// The person it signs in, for example `per_1a2b3c4d5e6f7a8b`.
  final String personId;

  /// When it stops working, in UTC.
  final DateTime expiresAt;

  /// The page of the dashboard at [origin] that signs in with this code.
  ///
  /// The code is in the fragment, which a browser never sends to a server,
  /// so no log has it.
  Uri signInUrl(Uri origin) => Uri(
    scheme: origin.scheme,
    host: origin.host,
    port: origin.hasPort ? origin.port : null,
    path: '/sign-in',
    fragment: 'code=$code',
  );

  /// The JSON form.
  Map<String, dynamic> toJson() => _$SignInCodeToJson(this);

  @override
  List<Object?> get props => [code, personId, expiresAt];

  @override
  String toString() => 'SignInCode($personId, <code>, $expiresAt)';
}

/// The body of `POST /session`: the sign-in code a browser exchanges for a
/// session.
@JsonSerializable(checked: true)
class SignInRequest extends Equatable {
  /// Creates the request.
  const new({required this.code});

  /// Reads the request from its JSON form.
  factory SignInRequest.fromJson(Map<String, dynamic> json) =>
      _$SignInRequestFromJson(json);

  /// The sign-in code, with or without its dashes, in any case.
  @JsonKey(required: true)
  final String code;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$SignInRequestToJson(this);

  @override
  List<Object?> get props => [code];

  @override
  String toString() => 'SignInRequest(<code>)';
}

/// The HTTPS address browsers reach the engine at through a proxy that
/// terminates TLS: the body of `GET` and `PUT /settings/public-url`. Browser
/// sign-in works on this machine, or through it (ADR 0018).
@JsonSerializable(includeIfNull: false)
class PublicUrl extends Equatable {
  /// Creates the setting.
  const new({this.url});

  /// Reads the setting from its JSON form.
  factory PublicUrl.fromJson(Map<String, dynamic> json) =>
      _$PublicUrlFromJson(json);

  /// The origin, for example `https://xpath.example.com`, or `null` when
  /// none is set.
  final String? url;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PublicUrlToJson(this);

  @override
  List<Object?> get props => [url];
}

/// The body of `PUT /settings/public-url`.
@JsonSerializable(checked: true)
class SetPublicUrlRequest extends Equatable {
  /// Creates a request; a `null` [url] clears the setting.
  const new({required this.url});

  /// Reads a request from its JSON form.
  factory SetPublicUrlRequest.fromJson(Map<String, dynamic> json) =>
      _$SetPublicUrlRequestFromJson(json);

  /// The public URL, or `null` to clear it. The key must be there.
  @JsonKey(required: true)
  final String? url;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$SetPublicUrlRequestToJson(this);

  @override
  List<Object?> get props => [url];
}
