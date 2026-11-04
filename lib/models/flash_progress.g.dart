// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flash_progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FlashProgress _$FlashProgressFromJson(Map<String, dynamic> json) =>
    _FlashProgress(
      stage: $enumDecode(_$FlashStageEnumMap, json['stage']),
      percent: (json['percent'] as num).toInt(),
      message: json['message'] as String,
      isError: json['isError'] as bool? ?? false,
      isSandboxError: json['isSandboxError'] as bool? ?? false,
    );

Map<String, dynamic> _$FlashProgressToJson(_FlashProgress instance) =>
    <String, dynamic>{
      'stage': _$FlashStageEnumMap[instance.stage]!,
      'percent': instance.percent,
      'message': instance.message,
      'isError': instance.isError,
      'isSandboxError': instance.isSandboxError,
    };

const _$FlashStageEnumMap = {
  FlashStage.sdpConnect: 'sdpConnect',
  FlashStage.blCheck: 'blCheck',
  FlashStage.sdpUpload: 'sdpUpload',
  FlashStage.write: 'write',
  FlashStage.configure: 'configure',
  FlashStage.reset: 'reset',
  FlashStage.complete: 'complete',
  FlashStage.programmingComplete: 'programmingComplete',
};
