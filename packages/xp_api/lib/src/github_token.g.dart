// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'github_token.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GitHubTokenStatus _$GitHubTokenStatusFromJson(Map<String, dynamic> json) =>
    GitHubTokenStatus(
      stored: json['stored'] as bool,
      status: $enumDecodeNullable(_$CredentialStatusEnumMap, json['status']),
      login: json['login'] as String?,
      message: json['message'] as String?,
      fix: json['fix'] as String?,
    );

Map<String, dynamic> _$GitHubTokenStatusToJson(GitHubTokenStatus instance) =>
    <String, dynamic>{
      'stored': instance.stored,
      'status': ?_$CredentialStatusEnumMap[instance.status],
      'login': ?instance.login,
      'message': ?instance.message,
      'fix': ?instance.fix,
    };

const _$CredentialStatusEnumMap = {
  CredentialStatus.unverified: 'unverified',
  CredentialStatus.verified: 'verified',
  CredentialStatus.rejected: 'rejected',
  CredentialStatus.unreachable: 'unreachable',
};

SetGitHubTokenRequest _$SetGitHubTokenRequestFromJson(
  Map<String, dynamic> json,
) => SetGitHubTokenRequest(json['token'] as String);

Map<String, dynamic> _$SetGitHubTokenRequestToJson(
  SetGitHubTokenRequest instance,
) => <String, dynamic>{'token': instance.token};
