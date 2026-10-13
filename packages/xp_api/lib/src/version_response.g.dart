// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'version_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VersionResponse _$VersionResponseFromJson(Map<String, dynamic> json) =>
    VersionResponse(
      version: json['version'] as String,
      apiVersion: json['apiVersion'] as String,
    );

Map<String, dynamic> _$VersionResponseToJson(VersionResponse instance) =>
    <String, dynamic>{
      'version': instance.version,
      'apiVersion': instance.apiVersion,
    };
