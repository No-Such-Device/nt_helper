// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'port.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Port _$PortFromJson(Map<String, dynamic> json) => _Port(
  id: json['id'] as String,
  name: json['name'] as String,
  type: $enumDecode(_$PortTypeEnumMap, json['type']),
  direction: $enumDecode(_$PortDirectionEnumMap, json['direction']),
  description: json['description'] as String?,
  constraints: json['constraints'] as Map<String, dynamic>?,
  isActive: json['isActive'] as bool? ?? true,
  outputMode: $enumDecodeNullable(_$OutputModeEnumMap, json['outputMode']),
  isPolyVoice: json['isPolyVoice'] as bool? ?? false,
  voiceNumber: (json['voiceNumber'] as num?)?.toInt(),
  isVirtualCV: json['isVirtualCV'] as bool? ?? false,
  isMultiChannel: json['isMultiChannel'] as bool? ?? false,
  channelNumber: (json['channelNumber'] as num?)?.toInt(),
  isStereoChannel: json['isStereoChannel'] as bool? ?? false,
  stereoSide: json['stereoSide'] as String?,
  isMasterMix: json['isMasterMix'] as bool? ?? false,
  busValue: (json['busValue'] as num?)?.toInt(),
  busParam: json['busParam'] as String?,
  parameterNumber: (json['parameterNumber'] as num?)?.toInt(),
  modeParameterNumber: (json['modeParameterNumber'] as num?)?.toInt(),
  hardwareIndex: (json['hardwareIndex'] as num?)?.toInt(),
  nodeId: json['nodeId'] as String?,
  role: $enumDecodeNullable(_$PortRoleEnumMap, json['role']),
);

Map<String, dynamic> _$PortToJson(_Port instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'type': _$PortTypeEnumMap[instance.type]!,
  'direction': _$PortDirectionEnumMap[instance.direction]!,
  'description': instance.description,
  'constraints': instance.constraints,
  'isActive': instance.isActive,
  'outputMode': _$OutputModeEnumMap[instance.outputMode],
  'isPolyVoice': instance.isPolyVoice,
  'voiceNumber': instance.voiceNumber,
  'isVirtualCV': instance.isVirtualCV,
  'isMultiChannel': instance.isMultiChannel,
  'channelNumber': instance.channelNumber,
  'isStereoChannel': instance.isStereoChannel,
  'stereoSide': instance.stereoSide,
  'isMasterMix': instance.isMasterMix,
  'busValue': instance.busValue,
  'busParam': instance.busParam,
  'parameterNumber': instance.parameterNumber,
  'modeParameterNumber': instance.modeParameterNumber,
  'hardwareIndex': instance.hardwareIndex,
  'nodeId': instance.nodeId,
  'role': _$PortRoleEnumMap[instance.role],
};

const _$PortTypeEnumMap = {PortType.audio: 'audio', PortType.cv: 'cv'};

const _$PortDirectionEnumMap = {
  PortDirection.input: 'input',
  PortDirection.output: 'output',
  PortDirection.bidirectional: 'bidirectional',
};

const _$OutputModeEnumMap = {
  OutputMode.add: 'add',
  OutputMode.replace: 'replace',
};

const _$PortRoleEnumMap = {
  PortRole.busReader: 'busReader',
  PortRole.busWriter: 'busWriter',
  PortRole.physicalInputBus: 'physicalInputBus',
  PortRole.physicalOutputBus: 'physicalOutputBus',
  PortRole.es5Bus: 'es5Bus',
  PortRole.expanderOutputBus: 'expanderOutputBus',
};
