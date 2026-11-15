// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SignInCode _$SignInCodeFromJson(Map<String, dynamic> json) => SignInCode(
  code: json['code'] as String,
  personId: json['personId'] as String,
  expiresAt: DateTime.parse(json['expiresAt'] as String),
);

Map<String, dynamic> _$SignInCodeToJson(SignInCode instance) =>
    <String, dynamic>{
      'code': instance.code,
      'personId': instance.personId,
      'expiresAt': instance.expiresAt.toIso8601String(),
    };

SignInRequest _$SignInRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SignInRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['code']);
      final val = SignInRequest(
        code: $checkedConvert('code', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$SignInRequestToJson(SignInRequest instance) =>
    <String, dynamic>{'code': instance.code};

PublicUrl _$PublicUrlFromJson(Map<String, dynamic> json) =>
    PublicUrl(url: json['url'] as String?);

Map<String, dynamic> _$PublicUrlToJson(PublicUrl instance) => <String, dynamic>{
  'url': ?instance.url,
};

SetPublicUrlRequest _$SetPublicUrlRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SetPublicUrlRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['url']);
      final val = SetPublicUrlRequest(
        url: $checkedConvert('url', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$SetPublicUrlRequestToJson(
  SetPublicUrlRequest instance,
) => <String, dynamic>{'url': instance.url};
