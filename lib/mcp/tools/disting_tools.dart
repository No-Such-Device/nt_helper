import 'dart:convert';
import 'dart:typed_data'; // Added for Uint8List

import 'package:collection/collection.dart';
import 'package:image/image.dart' as img; // For image processing
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show
        Algorithm,
        AlgorithmInfo,
        ParameterInfo,
        Mapping,
        ParameterValue,
        Specification;
import 'package:nt_helper/models/packed_mapping_data.dart' show MidiMappingType;
import 'package:nt_helper/cubit/disting_cubit.dart'
    show DistingCubit, DistingStateSynchronized;
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
// Re-added for Algorithm, ParameterInfo etc.
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';
import 'package:nt_helper/util/case_converter.dart';
import 'package:nt_helper/mcp/mcp_constants.dart';
import 'package:nt_helper/mcp/utils/bus_mapping.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Defines MCP tools for interacting with the Disting state (presets, slots, parameters)
/// via the DistingController.
class DistingTools {
  final DistingController _controller;
  final DistingCubit _distingCubit;

  // Use shared constants
  final int maxSlots = MCPConstants.maxSlots;
  static const int _defaultPresetParameterPageSize = 4;
  static const int _maxPresetParameterPageSize = 16;

  DistingTools(this._controller, this._distingCubit);

  DeviceIoProfile get _deviceIoProfile {
    final state = _distingCubit.state;
    return state is DistingStateSynchronized
        ? state.deviceIoProfile
        : DeviceIoProfile.distingLegacy;
  }

  bool get _hasExpressiveMidiMapping {
    final state = _distingCubit.state;
    if (state is DistingStateSynchronized) {
      return state.firmwareVersion.hasExpressiveMidiMapping;
    }
    return false;
  }

  // Use shared utility
  num _scaleForDisplay(int value, int? powerOfTen) =>
      MCPUtils.scaleForDisplay(value, powerOfTen);

  /// Returns all known algorithms by merging metadata DB with device state.
  /// Device-only algorithms (community/third-party) are appended after metadata.
  List<dynamic> _getAllKnownAlgorithms() {
    final metadataAlgorithms = AlgorithmMetadataService().getAllAlgorithms();
    final state = _distingCubit.state;
    if (state is DistingStateSynchronized) {
      final metadataGuids = metadataAlgorithms.map((a) => a.guid).toSet();
      final deviceOnly = state.algorithms.where(
        (a) => !metadataGuids.contains(a.guid),
      );
      return [...metadataAlgorithms, ...deviceOnly];
    }
    return metadataAlgorithms;
  }

  /// Adds an algorithm through the controller, which owns device verification.
  /// Returns the slot index where the algorithm was added.
  Future<int> _addAlgorithmAndVerify(Algorithm algorithm) async {
    final state = _distingCubit.state;
    final preAddCount = (state is DistingStateSynchronized)
        ? state.slots.length
        : 0;

    await _controller.addAlgorithm(algorithm);
    return preAddCount;
  }

  /// Looks up AlgorithmInfo from device state for a resolved GUID.
  AlgorithmInfo? _getDeviceAlgorithmInfo(String guid) {
    final state = _distingCubit.state;
    if (state is DistingStateSynchronized) {
      return state.algorithms.firstWhereOrNull((a) => a.guid == guid);
    }
    return null;
  }

  bool _isOfflineMode() {
    final state = _distingCubit.state;
    return state is DistingStateSynchronized && state.offline;
  }

  String _buildOfflineSpecsLimitation(String guid, List<Specification> specs) {
    final defaults = specs.map((s) => '${s.name}=${s.defaultValue}').join(', ');
    return 'Offline mode limitation: specifications for "$guid" are fixed to '
        'default values ($defaults). Any provided specifications are ignored.';
  }

  /// Builds an error response with specification details for algorithms that require specs.
  Map<String, dynamic> _buildSpecRequiredError(
    String guid,
    List<Specification> specs,
  ) {
    return {
      ...MCPUtils.buildError(
        'Algorithm "$guid" requires ${specs.length} specification(s). '
        'Provide "specifications" as a list of integers.',
      ),
      'specifications': specs
          .map(
            (s) => {
              'name': s.name,
              'min': s.min,
              'max': s.max,
              'default': s.defaultValue,
            },
          )
          .toList(),
    };
  }

  /// Retrieves enum values for a parameter if it's an enum type
  Future<List<String>?> _getParameterEnumValues(
    int slotIndex,
    int parameterNumber,
  ) async {
    try {
      // Get algorithm from slot
      final algorithm = await _controller.getAlgorithmInSlot(slotIndex);
      if (algorithm == null) return null;

      // Get enum strings from controller
      final enumStrings = await _controller.getParameterEnumStrings(
        slotIndex,
        parameterNumber,
      );
      return enumStrings?.values;
    } catch (e) {
      return null;
    }
  }

  /// Checks if a parameter is an enum type
  bool _isEnumParameter(ParameterInfo paramInfo) {
    return paramInfo.unit == 1;
  }

  /// Converts enum string to integer index (case-insensitive)
  int? _enumStringToIndex(List<String> enumValues, String value) {
    final lowerValue = value.toLowerCase();
    final index = enumValues.indexWhere((e) => e.toLowerCase() == lowerValue);
    return index >= 0 ? index : null;
  }

  /// Converts integer index to enum string
  String? _enumIndexToString(List<String> enumValues, int index) {
    if (index >= 0 && index < enumValues.length) {
      return enumValues[index];
    }
    return null;
  }

  /// MCP Tool: Gets one bounded page of the current preset state.
  ///
  /// Pages contain at most one populated slot and a bounded parameter slice.
  /// The response includes the exact arguments for the next page so callers do
  /// not need to understand or reconstruct the paging algorithm.
  Future<String> getCurrentPreset(Map<String, dynamic> params) async {
    try {
      final rawSlotOffset = params['slot_offset'];
      final rawParameterOffset = params['parameter_offset'];
      final rawParameterLimit = params['parameter_limit'];
      if ((rawSlotOffset != null && rawSlotOffset is! int) ||
          (rawParameterOffset != null && rawParameterOffset is! int) ||
          (rawParameterLimit != null && rawParameterLimit is! int)) {
        return jsonEncode(
          MCPUtils.buildError(
            'slot_offset, parameter_offset, and parameter_limit must be integers.',
          ),
        );
      }

      final slotOffset = rawSlotOffset as int? ?? 0;
      final parameterOffset = rawParameterOffset as int? ?? 0;
      final parameterLimit =
          rawParameterLimit as int? ?? _defaultPresetParameterPageSize;
      if (slotOffset < 0 || parameterOffset < 0) {
        return jsonEncode(
          MCPUtils.buildError(
            'slot_offset and parameter_offset must be zero or greater.',
          ),
        );
      }
      if (parameterLimit < 1 || parameterLimit > _maxPresetParameterPageSize) {
        return jsonEncode(
          MCPUtils.buildError(
            'parameter_limit must be between 1 and '
            '$_maxPresetParameterPageSize.',
          ),
        );
      }

      final presetName = await _controller.getCurrentPresetName();
      final Map<int, Algorithm?> slotAlgorithms = await _controller
          .getAllSlots();

      final populatedSlots =
          slotAlgorithms.entries.where((entry) => entry.value != null).toList()
            ..sort((left, right) => left.key.compareTo(right.key));
      if (populatedSlots.isEmpty) {
        return jsonEncode({
          'success': true,
          'preset_name': presetName,
          'populated_slot_count': 0,
          'edit_slot_arguments': null,
          'restore_ready': true,
          'slot_parameter_count': 0,
          'paging': {
            'slot_offset': 0,
            'parameter_offset': 0,
            'parameter_limit': parameterLimit,
            'count': 0,
            'total': 0,
            'has_more': false,
            'next': null,
          },
        });
      }

      if (slotOffset >= populatedSlots.length) {
        return jsonEncode(
          MCPUtils.buildError(
            'slot_offset $slotOffset is outside the populated slot range '
            '(0-${populatedSlots.length - 1}).',
            details: {
              'populated_slot_count': populatedSlots.length,
              'restart': {
                'tool': 'get_preset',
                'arguments': {
                  'slot_offset': 0,
                  'parameter_offset': 0,
                  'parameter_limit': parameterLimit,
                },
              },
            },
          ),
        );
      }

      final slotEntry = populatedSlots[slotOffset];
      final slotIndex = slotEntry.key;
      final algorithm = slotEntry.value!;
      final parameterInfos = await _controller.getParametersForSlot(slotIndex);
      if (parameterOffset > parameterInfos.length) {
        return jsonEncode(
          MCPUtils.buildError(
            'parameter_offset $parameterOffset exceeds the slot parameter '
            'count (${parameterInfos.length}).',
            details: {
              'slot_index': slotIndex,
              'restart': {
                'tool': 'get_preset',
                'arguments': {
                  'slot_offset': slotOffset,
                  'parameter_offset': 0,
                  'parameter_limit': parameterLimit,
                },
              },
            },
          ),
        );
      }

      final end = parameterOffset + parameterLimit < parameterInfos.length
          ? parameterOffset + parameterLimit
          : parameterInfos.length;
      final parametersJsonList = <Map<String, dynamic>>[];
      for (final pInfo in parameterInfos.sublist(parameterOffset, end)) {
        final paramValue = await _controller.getParameterValue(
          slotIndex,
          pInfo.parameterNumber,
        );
        final liveRawValue = paramValue?.value;
        final paramData = <String, dynamic>{
          'parameter_number': pInfo.parameterNumber,
          'name': pInfo.name,
        };

        if (_isEnumParameter(pInfo)) {
          final enumValues = await _getParameterEnumValues(
            slotIndex,
            pInfo.parameterNumber,
          );
          if (enumValues != null) {
            if (liveRawValue != null) {
              paramData['value'] =
                  _enumIndexToString(enumValues, liveRawValue) ?? '';
            }
          }
        } else {
          paramData['value'] = liveRawValue != null
              ? _scaleForDisplay(liveRawValue, pInfo.powerOfTen)
              : null;
        }

        try {
          final mapping = await _controller.getParameterMapping(
            slotIndex,
            pInfo.parameterNumber,
          );
          final mappingJson = await _buildMappingJson(mapping);
          if (mappingJson != null) paramData['mapping'] = mappingJson;
        } catch (_) {
          // A missing mapping does not make the parameter unreadable.
        }
        parametersJsonList.add(paramData);
      }

      final requiredSpecifications =
          _getDeviceAlgorithmInfo(algorithm.guid)?.specifications ?? const [];
      final hasRequiredSpecifications = requiredSpecifications.isNotEmpty;
      final hasRestorableSpecifications =
          !hasRequiredSpecifications ||
          (algorithm.specifications.length == requiredSpecifications.length &&
              algorithm.specifications.indexed.every((entry) {
                final specification = requiredSpecifications[entry.$1];
                return entry.$2 >= specification.min &&
                    entry.$2 <= specification.max;
              }));
      final algorithmData = <String, dynamic>{
        'guid': algorithm.guid,
        'name': algorithm.name,
        if (algorithm.specifications.isNotEmpty)
          'specifications': algorithm.specifications,
      };
      String? slotName;
      try {
        slotName = await _controller.getSlotName(slotIndex);
      } catch (_) {
        // Fall back to the algorithm name if a custom name is unavailable.
      }

      Map<String, dynamic>? nextArguments;
      if (end < parameterInfos.length) {
        nextArguments = {
          'slot_offset': slotOffset,
          'parameter_offset': end,
          'parameter_limit': parameterLimit,
        };
      } else if (slotOffset + 1 < populatedSlots.length) {
        nextArguments = {
          'slot_offset': slotOffset + 1,
          'parameter_offset': 0,
          'parameter_limit': parameterLimit,
        };
      }

      return jsonEncode({
        'success': true,
        'preset_name': presetName,
        'populated_slot_count': populatedSlots.length,
        'edit_slot_arguments': {
          'slot_index': slotIndex,
          'data': {
            'name': slotName ?? algorithm.name,
            if (hasRestorableSpecifications) 'algorithm': algorithmData,
            'parameters': parametersJsonList,
          },
        },
        'restore_ready': hasRestorableSpecifications,
        if (!hasRestorableSpecifications) ...{
          'algorithm_identity': {
            'guid': algorithm.guid,
            'name': algorithm.name,
          },
          'restore_limitation':
              'Current specification values for required-spec algorithm '
              '"${algorithm.guid}" are unavailable. edit_slot_arguments '
              'omit the algorithm and can safely patch an existing matching '
              'slot, but cannot recreate it without known explicit '
              'specifications.',
        },
        'slot_parameter_count': parameterInfos.length,
        'paging': {
          'slot_offset': slotOffset,
          'parameter_offset': parameterOffset,
          'parameter_limit': parameterLimit,
          'count': parametersJsonList.length,
          'total': parameterInfos.length,
          'has_more': nextArguments != null,
          'next': nextArguments == null
              ? null
              : {'tool': 'get_preset', 'arguments': nextArguments},
        },
      });
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Adds an algorithm to the first available slot (determined by hardware).
  /// Parameters:
  ///   - algorithm_guid (string, required): The GUID of the algorithm to add.
  /// Returns:
  ///   A JSON string confirming the addition or an error.
  Future<String> addAlgorithm(Map<String, dynamic> params) async {
    final String? algorithmGuid = params['algorithm_guid'];
    final String? algorithmName = params['algorithm_name'];

    // Use shared algorithm resolver (includes device-only algorithms)
    final algorithms = _getAllKnownAlgorithms();
    final resolution = AlgorithmResolver.resolveAlgorithm(
      guid: algorithmGuid,
      algorithmName: algorithmName,
      allAlgorithms: algorithms,
    );

    if (!resolution.isSuccess) {
      return jsonEncode(convertToSnakeCaseKeys(resolution.error!));
    }

    try {
      final algoStub = Algorithm(
        algorithmIndex: -1,
        guid: resolution.resolvedGuid!,
        name: '',
      );

      final slotIndex = await _addAlgorithmAndVerify(algoStub);

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Algorithm ${resolution.resolvedGuid!} added to slot $slotIndex',
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Simple interface to add an algorithm to the preset.
  /// Designed for minimal cognitive load - flat parameter structure.
  /// Parameters:
  ///   - slot_index (int, optional): Target slot (0-39). If omitted, adds to first empty slot.
  ///   - name (string, optional): Algorithm name (fuzzy matching ≥70%)
  ///   - guid (string, optional): Algorithm GUID (exact match)
  ///   - specifications (list of ints, optional): Specification values for algorithms that require them
  /// Returns:
  ///   A JSON string with the slot index where the algorithm was added, or an error.
  Future<String> addSimple(Map<String, dynamic> params) async {
    // Extract algorithm identifier (name or guid)
    final String? name = params['name'] as String?;
    final String? guid = params['guid'] as String?;
    final int? slotIndex = params['slot_index'] as int?;
    final List<dynamic>? specifications =
        params['specifications'] as List<dynamic>?;

    // Validate that at least one of name or guid is provided
    if (name == null && guid == null) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Missing algorithm identifier. Use "name" (e.g., "VCO", "Delay") or "guid". '
            'Use search tool to find algorithms.',
          ),
        ),
      );
    }

    // Validate slot_index if provided
    if (slotIndex != null && (slotIndex < 0 || slotIndex >= maxSlots)) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'slot_index $slotIndex invalid. Must be 0-${maxSlots - 1}. Omit to auto-select first empty slot.',
          ),
        ),
      );
    }

    // Use shared algorithm resolver (includes device-only algorithms)
    final algorithms = _getAllKnownAlgorithms();
    final resolution = AlgorithmResolver.resolveAlgorithm(
      guid: guid,
      algorithmName: name,
      allAlgorithms: algorithms,
    );

    if (!resolution.isSuccess) {
      return jsonEncode(convertToSnakeCaseKeys(resolution.error!));
    }

    try {
      final resolvedGuid = resolution.resolvedGuid!;
      final algorithmMetadata = AlgorithmMetadataService().getAlgorithmByGuid(
        resolvedGuid,
      );

      // Check specification requirements from device state
      final deviceAlgoInfo = _getDeviceAlgorithmInfo(resolvedGuid);
      final requiredSpecs = deviceAlgoInfo?.specifications ?? [];
      final List<int> specValues = [];
      final offlineMode = _isOfflineMode();
      String? limitationMessage;

      if (requiredSpecs.isNotEmpty) {
        if (offlineMode) {
          specValues.addAll(requiredSpecs.map((s) => s.defaultValue));
          limitationMessage = _buildOfflineSpecsLimitation(
            resolvedGuid,
            requiredSpecs,
          );
        } else {
          if (specifications == null || specifications.isEmpty) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                _buildSpecRequiredError(resolvedGuid, requiredSpecs),
              ),
            );
          }

          if (specifications.length != requiredSpecs.length) {
            return jsonEncode(
              convertToSnakeCaseKeys({
                ..._buildSpecRequiredError(resolvedGuid, requiredSpecs),
                'error':
                    'Algorithm "$resolvedGuid" requires ${requiredSpecs.length} specification(s), got ${specifications.length}.',
              }),
            );
          }

          // Validate and convert spec values
          for (int i = 0; i < specifications.length; i++) {
            final spec = requiredSpecs[i];
            final value = specifications[i];
            if (value is! int) {
              return jsonEncode(
                convertToSnakeCaseKeys(
                  MCPUtils.buildError(
                    'Specification "${spec.name}" must be an integer, got ${value.runtimeType}',
                  ),
                ),
              );
            }
            if (value < spec.min || value > spec.max) {
              return jsonEncode(
                convertToSnakeCaseKeys(
                  MCPUtils.buildError(
                    'Specification "${spec.name}" value $value out of range (${spec.min}-${spec.max})',
                  ),
                ),
              );
            }
            specValues.add(value);
          }
        }
      }

      final algoStub = Algorithm(
        algorithmIndex: -1,
        guid: resolvedGuid,
        name: algorithmMetadata?.name ?? deviceAlgoInfo?.name ?? '',
        specifications: specValues,
      );

      // Add the algorithm and verify it was accepted
      final addedSlotIndex = await _addAlgorithmAndVerify(algoStub);

      // If a specific slot was requested and it's different from where it was added,
      // move the algorithm to the target slot (insert semantics - pushes others down)
      int finalSlotIndex = addedSlotIndex;
      if (slotIndex != null && slotIndex < addedSlotIndex) {
        // Move up from addedSlotIndex to slotIndex
        // Each moveAlgorithmUp swaps with the slot above, pushing others down
        for (
          int currentPos = addedSlotIndex;
          currentPos > slotIndex;
          currentPos--
        ) {
          await _controller.moveAlgorithmUp(currentPos);
        }
        finalSlotIndex = slotIndex;
      }

      final message =
          'Algorithm "${algorithmMetadata?.name ?? resolvedGuid}" inserted at slot $finalSlotIndex';

      final responseData = <String, dynamic>{
        'slot_index': finalSlotIndex,
        'algorithm_name': algorithmMetadata?.name ?? '',
        'algorithm_guid': resolvedGuid,
      };
      if (limitationMessage != null) {
        responseData['limitation'] = limitationMessage;
        responseData['effective_specifications'] = specValues;
      }

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(message, data: responseData),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Removes (clears) the algorithm from a specific slot.
  /// Parameters:
  ///   - slot_index (int, required): The index of the slot to clear (0-39).
  /// Returns:
  ///   A JSON string confirming the removal. Lenient if slot is already empty.
  Future<String> removeSlot(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;

    // Validate slot_index presence
    if (slotIndex == null) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Missing required parameter: "slot_index"'),
        ),
      );
    }

    // Validate slot_index range
    if (slotIndex < 0 || slotIndex >= maxSlots) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'slot_index $slotIndex out of range. Must be 0-${maxSlots - 1}.',
          ),
        ),
      );
    }

    try {
      // Check if slot is already empty
      final allSlots = await _controller.getAllSlots();
      final currentAlgorithm = allSlots[slotIndex];

      if (currentAlgorithm == null) {
        // Slot is already empty - be kind about it
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildSuccess('Slot $slotIndex is already empty'),
          ),
        );
      }

      // Clear the slot
      await _controller.clearSlot(slotIndex);
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Removed "${currentAlgorithm.name}" from slot $slotIndex',
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  // Updated method to set parameter value, handling display_value and powerOfTen
  Future<String> setParameterValue(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;
    final int? parameterNumberParam = params['parameter_number'] as int?;
    final String? parameterNameParam = params['parameter_name'] as String?;
    final dynamic value = params['value']; // Can be num or String for enums

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    // Validate value parameter
    final valueError = MCPUtils.validateRequiredParam(value, 'value');
    if (valueError != null) {
      return jsonEncode(convertToSnakeCaseKeys(valueError));
    }

    // Validate exactly one of parameter_number or parameter_name
    final paramError = MCPUtils.validateExactlyOne(params, [
      'parameter_number',
      'parameter_name',
    ]);
    if (paramError != null) {
      return jsonEncode(convertToSnakeCaseKeys(paramError));
    }

    try {
      final List<ParameterInfo> paramInfos = await _controller
          .getParametersForSlot(slotIndex!);

      int? targetParameterNumber;
      ParameterInfo? paramInfo;

      if (parameterNumberParam != null) {
        // Find parameter with matching parameterNumber (not array index)
        try {
          paramInfo = paramInfos.firstWhere(
            (p) => p.parameterNumber == parameterNumberParam,
          );
          targetParameterNumber = parameterNumberParam;
        } catch (e) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter number $parameterNumberParam not found in slot $slotIndex.',
              ),
            ),
          );
        }
      } else if (parameterNameParam != null) {
        final matchingParams = paramInfos
            .where(
              (p) => p.name.toLowerCase() == parameterNameParam.toLowerCase(),
            )
            .toList();

        if (matchingParams.isEmpty) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter with name "$parameterNameParam" not found in slot $slotIndex. Check `get_preset` for available parameters.',
              ),
            ),
          );
        }

        if (matchingParams.length > 1) {
          // Ambiguous parameter name - show all matching parameter numbers
          final paramNumbers = matchingParams
              .map((p) => p.parameterNumber)
              .join(', ');
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter name "$parameterNameParam" is ambiguous in slot $slotIndex. Found at parameter numbers: $paramNumbers. Please use parameter_number to disambiguate.',
              ),
            ),
          );
        }

        paramInfo = matchingParams.first;
        targetParameterNumber = paramInfo.parameterNumber;
      }

      if (paramInfo == null || targetParameterNumber == null) {
        // Should not happen if logic above is correct
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Failed to identify target parameter.'),
          ),
        );
      }

      int rawValue;
      if (_isEnumParameter(paramInfo)) {
        if (value is! String) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Enum parameter ${paramInfo.name} requires a string value '
                'from its valid_enum_values list.',
              ),
            ),
          );
        }
        final enumValues = await _getParameterEnumValues(
          slotIndex,
          targetParameterNumber,
        );
        if (enumValues == null) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Could not retrieve enum values for parameter ${paramInfo.name}',
              ),
            ),
          );
        }
        final enumIndex = _enumStringToIndex(enumValues, value);
        if (enumIndex == null) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Invalid value "$value" for parameter ${paramInfo.name}. '
                'Valid values: ${enumValues.join(", ")}',
              ),
            ),
          );
        }
        rawValue = enumIndex;
      } else {
        if (value is! num) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter ${paramInfo.name} requires a numeric value.',
              ),
            ),
          );
        }
        rawValue = MCPUtils.scaleToRaw(value, paramInfo.powerOfTen);
      }

      if (rawValue < paramInfo.min || rawValue > paramInfo.max) {
        final effectiveMin = _scaleForDisplay(
          paramInfo.min,
          paramInfo.powerOfTen,
        );
        final effectiveMax = _scaleForDisplay(
          paramInfo.max,
          paramInfo.powerOfTen,
        );
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Provided value $value (scaled to $rawValue) is out of range for parameter ${paramInfo.name} (effective range: $effectiveMin to $effectiveMax, raw range: ${paramInfo.min} to ${paramInfo.max}).',
            ),
          ),
        );
      }

      await _controller.updateParameterValue(
        slotIndex,
        targetParameterNumber,
        rawValue,
      );

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Parameter ${paramInfo.name} (number $targetParameterNumber) in slot $slotIndex set to $value.',
            data: {
              'value': value,
              'parameter_number': targetParameterNumber,
              'parameter_name': paramInfo.name,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Gets the value of a specific parameter.
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot.
  ///   - parameter_number (int, optional): The parameter number.
  ///   - parameter_name (string, optional): The parameter name (matches first occurrence if duplicates exist).
  /// Returns:
  ///   A JSON string with the parameter value or an error.
  Future<String> getParameterValue(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;
    final int? parameterNumber = params['parameter_number'] as int?;
    final String? parameterName = params['parameter_name'] as String?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    // Validate that at least one of parameter_number or parameter_name is provided
    if (parameterNumber == null && parameterName == null) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Either "parameter_number" or "parameter_name" must be provided.',
          ),
        ),
      );
    }

    try {
      // Resolve parameter number from name if needed
      int resolvedParameterNumber = parameterNumber ?? -1;
      if (parameterName != null) {
        final List<ParameterInfo> paramInfos = await _controller
            .getParametersForSlot(slotIndex!);
        final matchingParams = paramInfos
            .where((p) => p.name.toLowerCase() == parameterName.toLowerCase())
            .toList();
        if (matchingParams.isEmpty) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter with name "$parameterName" not found in slot $slotIndex.',
              ),
            ),
          );
        }
        if (matchingParams.length > 1) {
          final paramNumbers = matchingParams
              .map((p) => p.parameterNumber)
              .join(', ');
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter name "$parameterName" is ambiguous in slot $slotIndex. Found at parameter numbers: $paramNumbers. Please use parameter_number to disambiguate.',
              ),
            ),
          );
        }
        resolvedParameterNumber = matchingParams.first.parameterNumber;
      }

      final ParameterValue? paramValue = await _controller.getParameterValue(
        slotIndex!,
        resolvedParameterNumber,
      );

      if (paramValue == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Could not retrieve value for parameter $resolvedParameterNumber in slot $slotIndex.',
            ),
          ),
        );
      }

      final int liveRawValue = paramValue.value;

      // Fetch parameter info to get powerOfTen for scaling
      final List<ParameterInfo> paramInfos = await _controller
          .getParametersForSlot(slotIndex);

      // Find parameter with matching parameterNumber (not array index)
      ParameterInfo? paramInfo;
      try {
        paramInfo = paramInfos.firstWhere(
          (p) => p.parameterNumber == resolvedParameterNumber,
        );
      } catch (e) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Parameter number $resolvedParameterNumber not found in slot $slotIndex.',
            ),
          ),
        );
      }

      final responseData = <String, dynamic>{
        'slot_index': slotIndex,
        'parameter_number': resolvedParameterNumber,
        'parameter_name': paramInfo.name,
        'is_disabled': paramValue.isDisabled,
        'is_input': paramInfo.isInput,
        'is_output': paramInfo.isOutput,
        'is_audio': paramInfo.isAudio,
        'is_output_mode': paramInfo.isOutputMode,
      };

      if (_isEnumParameter(paramInfo)) {
        final enumValues = await _getParameterEnumValues(
          slotIndex,
          resolvedParameterNumber,
        );
        if (enumValues != null) {
          responseData['is_enum'] = true;
          responseData['valid_enum_values'] = enumValues;
          responseData['value'] =
              _enumIndexToString(enumValues, liveRawValue) ?? '';
        }
      } else {
        responseData['value'] = _scaleForDisplay(
          liveRawValue,
          paramInfo.powerOfTen,
        );
      }

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Parameter value retrieved successfully',
            data: responseData,
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Sets the name of the current preset.
  /// Parameters:
  ///   - name (string, required): The new name for the preset.
  /// Returns:
  ///   A JSON string confirming the action or an error.
  Future<String> setPresetName(Map<String, dynamic> params) async {
    final String? name = params['name'] as String?;

    final trimmedName = name?.trim();
    if (trimmedName == null || trimmedName.isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Preset name must contain 1-31 characters.'),
        ),
      );
    }
    if (trimmedName.length > 31) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Preset name is ${trimmedName.length} characters; the maximum is 31.',
          ),
        ),
      );
    }

    try {
      await _controller.setPresetName(trimmedName);
      final appliedName = await _controller.getCurrentPresetName();
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Preset renamed to "$appliedName" and saved without changing its contents.',
            data: {'preset_name': appliedName, 'persisted': true},
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Sets the custom name for an algorithm in a specific slot.
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot.
  ///   - name (string, required): The desired custom name.
  /// Returns:
  ///   A JSON string confirming the action or an error.
  Future<String> setSlotName(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;
    final String? name = params['name'] as String?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    // Validate name parameter
    final nameError = MCPUtils.validateRequiredParam(name, 'name');
    if (nameError != null) {
      return jsonEncode(convertToSnakeCaseKeys(nameError));
    }

    try {
      await _controller.setSlotName(slotIndex!, name!);
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess('Name for slot $slotIndex set to "$name".'),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Tells the device to clear the current preset and start a new, empty one.
  /// Parameters: None (can accept a dummy string for consistency if MCP requires it).
  /// Returns: A JSON string confirming the action or an error.
  Future<String> newPreset(Map<String, dynamic> params) async {
    try {
      await _controller.newPreset();
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess('New empty preset initiated on the device.'),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Tells the device to save the current working preset.
  /// Parameters: None.
  /// Returns: A JSON string confirming the action or an error.
  Future<String> savePreset(Map<String, dynamic> params) async {
    try {
      if (!_controller.isSynchronized) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Device not synchronized. Cannot save preset.'),
          ),
        );
      }

      final presetName = await _controller.getCurrentPresetName();
      if (presetName.isEmpty || presetName == 'Init') {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Cannot save preset named "Init". Use new tool to create a preset with a name first.',
            ),
          ),
        );
      }

      await _controller.savePreset();
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess('Preset "$presetName" saved to device.'),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: applies selected slots from a saved template to the device or
  /// to another saved local preset.
  Future<String> applyTemplateToPreset(Map<String, dynamic> params) async {
    try {
      final db = _distingCubit.database;
      final dao = db.presetsDao;

      final templateResolution = await _resolveTemplatePreset(dao, params);
      if (templateResolution.error != null) {
        return jsonEncode(convertToSnakeCaseKeys(templateResolution.error!));
      }
      final template = templateResolution.details!;

      final slotIndicesOrError = _resolveTemplateSlotIndices(
        params['slot_indices'],
        template.slots.length,
      );
      if (slotIndicesOrError.error != null) {
        return jsonEncode(convertToSnakeCaseKeys(slotIndicesOrError.error!));
      }
      final slotIndices = slotIndicesOrError.slotIndices!;

      final target = (params['target'] as String?) ?? 'device';
      if (target != 'device' && target != 'preset') {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('target must be "device" or "preset".'),
          ),
        );
      }

      if (target == 'device') {
        return _applyTemplateToDeviceTarget(
          db: db,
          template: template,
          slotIndices: slotIndices,
        );
      }

      final targetResolution = await _resolveTargetPreset(dao, params);
      if (targetResolution.error != null) {
        return jsonEncode(convertToSnakeCaseKeys(targetResolution.error!));
      }
      final targetPreset = targetResolution.preset!;
      if (targetPreset.isTemplate && targetPreset.id != template.preset.id) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Target preset must not be a template. Use target_preset_id for the same template only when self-extending.',
            ),
          ),
        );
      }

      final result = await dao.applyTemplateSlots(
        templateId: template.preset.id,
        targetPresetId: targetPreset.id,
        templateSlotIndices: slotIndices,
        insertionOffset: (params['insertion_offset'] as int?) ?? 0,
        overwrite: (params['overwrite'] as bool?) ?? false,
      );

      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': true,
          'target': 'preset',
          'target_preset_id': result.targetPresetId,
          'applied_slot_count': result.insertedSlotIndices.length,
          'inserted_slot_indices': result.insertedSlotIndices,
          'skipped_template_slot_indices': result.skippedTemplateSlotIndices,
          'warning': result.warning,
        }),
      );
    } on TemplateSpaceException catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'space',
          'current': e.current,
          'applied': e.applied,
          'limit': e.limit,
        }),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error applying template: ${e.toString()}'),
        ),
      );
    }
  }

  Future<String> _applyTemplateToDeviceTarget({
    required AppDatabase db,
    required FullPresetDetails template,
    required List<int> slotIndices,
  }) async {
    if (_isOfflineMode()) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Device target requires connected mode; offline mode cannot apply templates to hardware.',
          ),
        ),
      );
    }

    final cubit = MetadataSyncCubit(db, _distingCubit);
    var appliedCount = 0;
    String? failureMessage;
    try {
      final subscription = cubit.stream.listen((state) {
        if (state is InjectingTemplate) {
          appliedCount = state.applied;
        } else if (state is PresetLoadFailure) {
          failureMessage = state.error;
        }
      });
      try {
        await cubit.applyTemplateToDevice(
          template: template,
          templateSlotIndices: slotIndices,
          manager: _distingCubit.requireDisting(),
        );
        final finalState = cubit.state;
        if (finalState is PresetLoadFailure) {
          failureMessage = finalState.error;
        } else if (finalState is InjectingTemplate) {
          appliedCount = finalState.applied;
        }
      } finally {
        await subscription.cancel();
        await cubit.close();
      }
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'partial_apply',
          'applied_slot_count': appliedCount,
          'message': e.toString(),
        }),
      );
    }

    if (failureMessage != null) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'partial_apply',
          'applied_slot_count': appliedCount,
          'message': failureMessage,
        }),
      );
    }

    return jsonEncode(
      convertToSnakeCaseKeys({
        'success': true,
        'target': 'device',
        'target_preset_id': null,
        'applied_slot_count': slotIndices.length,
        'inserted_slot_indices': const <int>[],
        'skipped_template_slot_indices': const <int>[],
        'warning': null,
      }),
    );
  }

  Future<_TemplateResolution> _resolveTemplatePreset(
    PresetsDao dao,
    Map<String, dynamic> params,
  ) async {
    final templateId = params['template_id'] as int?;
    if (templateId != null) {
      final details = await dao.getFullPresetDetails(templateId);
      if (details == null) {
        return _TemplateResolution.error(
          MCPUtils.buildError('Template preset $templateId not found.'),
        );
      }
      if (!details.preset.isTemplate) {
        return _TemplateResolution.error(
          MCPUtils.buildError('Preset $templateId is not a template.'),
        );
      }
      return _TemplateResolution.details(details);
    }

    final templateName = params['template_name'] as String?;
    if (templateName == null || templateName.trim().isEmpty) {
      return _TemplateResolution.error(
        MCPUtils.buildError('Provide template_id or template_name.'),
      );
    }

    final preset = await _resolvePresetByName(
      dao,
      templateName,
      (p) => p.isTemplate,
      'template',
    );
    if (preset.error != null) {
      return _TemplateResolution.error(preset.error!);
    }
    final details = await dao.getFullPresetDetails(preset.preset!.id);
    if (details == null) {
      return _TemplateResolution.error(
        MCPUtils.buildError(
          'Template "${preset.preset!.name}" could not be loaded.',
        ),
      );
    }
    return _TemplateResolution.details(details);
  }

  Future<_PresetResolution> _resolveTargetPreset(
    PresetsDao dao,
    Map<String, dynamic> params,
  ) async {
    final targetId = params['target_preset_id'] as int?;
    if (targetId != null) {
      final preset = await dao.getPresetById(targetId);
      if (preset == null) {
        return _PresetResolution.error(
          MCPUtils.buildError('Target preset $targetId not found.'),
        );
      }
      return _PresetResolution.preset(preset);
    }

    final targetName = params['target_preset_name'] as String?;
    if (targetName == null || targetName.trim().isEmpty) {
      return _PresetResolution.error(
        MCPUtils.buildError(
          'target_preset_id or target_preset_name is required when target is "preset".',
        ),
      );
    }
    return _resolvePresetByName(dao, targetName, (_) => true, 'target preset');
  }

  Future<_PresetResolution> _resolvePresetByName(
    PresetsDao dao,
    String name,
    bool Function(PresetEntry preset) filter,
    String label,
  ) async {
    final candidates = (await dao.getAllPresets()).where(filter).toList();
    final exact = candidates.where((p) => p.name == name).toList();
    if (exact.length == 1) {
      return _PresetResolution.preset(exact.single);
    }
    if (exact.length > 1) {
      return _PresetResolution.error(
        MCPUtils.buildError(
          'Multiple $label presets exactly match "$name": ${_candidateNames(exact)}. Use an id.',
        ),
      );
    }

    final lower = name.toLowerCase();
    final ci = candidates.where((p) => p.name.toLowerCase() == lower).toList();
    if (ci.length == 1) {
      return _PresetResolution.preset(ci.single);
    }
    if (ci.isEmpty) {
      return _PresetResolution.error(
        MCPUtils.buildError(
          'No $label preset named "$name". Candidates: ${_candidateNames(candidates)}.',
        ),
      );
    }
    return _PresetResolution.error(
      MCPUtils.buildError(
        'Multiple $label presets case-insensitively match "$name": ${_candidateNames(ci)}. Use an id.',
      ),
    );
  }

  _SlotIndicesResolution _resolveTemplateSlotIndices(
    Object? raw,
    int slotCount,
  ) {
    if (raw == null) {
      return _SlotIndicesResolution.slotIndices(
        List<int>.generate(slotCount, (i) => i),
      );
    }
    if (raw is! List) {
      return _SlotIndicesResolution.error(
        MCPUtils.buildError('slot_indices must be an array of integers.'),
      );
    }

    final indices = <int>[];
    for (final item in raw) {
      if (item is! int) {
        return _SlotIndicesResolution.error(
          MCPUtils.buildError('slot_indices must contain only integers.'),
        );
      }
      if (item < 0 || item >= slotCount) {
        return _SlotIndicesResolution.error(
          MCPUtils.buildError(
            'slot_indices value $item out of range [0, $slotCount).',
          ),
        );
      }
      indices.add(item);
    }
    if (indices.isEmpty) {
      return _SlotIndicesResolution.error(
        MCPUtils.buildError('slot_indices cannot be empty.'),
      );
    }
    return _SlotIndicesResolution.slotIndices(indices);
  }

  String _candidateNames(List<PresetEntry> presets) {
    if (presets.isEmpty) return '(none)';
    final sorted = presets.map((p) => '"${p.name}" (${p.id})').toList()..sort();
    return sorted.join(', ');
  }

  /// MCP Tool: Moves an algorithm in a specified slot one position up in the slot list.
  /// The evaluation order of algorithms is from top to bottom (slot 0 to N).
  /// If an algorithm expects modulation from another, the modulating algorithm
  /// must appear in an earlier slot (lower index).
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot to move up.
  /// Returns:
  ///   A JSON string confirming the move or an error.
  Future<String> moveAlgorithmUp(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    if (slotIndex == 0) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Cannot move algorithm in slot 0 further up.'),
        ),
      );
    }
    // Ensure slotIndex is within a reasonable range if needed, though controller might handle this.
    // For now, just check against 0. Max slot check can be added if necessary or rely on controller.

    final int sourceSlotIndex = slotIndex!;

    try {
      await _controller.moveAlgorithmUp(sourceSlotIndex);
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Algorithm from slot $sourceSlotIndex moved up.',
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Moves an algorithm in a specified slot one position down in the slot list.
  /// The evaluation order of algorithms is from top to bottom (slot 0 to N).
  /// If an algorithm expects modulation from another, the modulating algorithm
  /// must appear in an earlier slot (lower index).
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot to move down.
  /// Returns:
  ///   A JSON string confirming the move or an error.
  Future<String> moveAlgorithmDown(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    // Assuming maxSlots is available or a way to check upper bound exists.
    // For simplicity, we'll rely on the controller to handle upper boundary errors if any.
    // A check like `if (slotIndex >= maxSlots - 1)` could be added.
    // For now, we'll assume maxSlots is dynamic or handled by the controller.

    final int sourceSlotIndex = slotIndex!;

    try {
      // Check if sourceSlotIndex is already the last possible slot.
      // This requires knowing the total number of slots, which is `maxSlots`.
      if (sourceSlotIndex >= maxSlots - 1) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Cannot move algorithm in slot ${maxSlots - 1} further down.',
            ),
          ),
        );
      }
      await _controller.moveAlgorithmDown(sourceSlotIndex);
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Algorithm from slot $sourceSlotIndex moved down.',
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Moves an algorithm to a specified direction or position.
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot to move.
  ///   - direction (string, required): Direction to move ('up' or 'down').
  ///   - steps (int, optional): Number of steps to move (default: 1).
  /// Returns:
  ///   A JSON string confirming the move or an error.
  Future<String> moveAlgorithm(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;
    final String? direction = params['direction'] as String?;
    final int steps = (params['steps'] as int?) ?? 1;

    // Validate required parameters
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    final directionError = MCPUtils.validateRequiredParam(
      direction,
      'direction',
    );
    if (directionError != null) {
      return jsonEncode(convertToSnakeCaseKeys(directionError));
    }

    // Validate direction parameter
    if (direction != 'up' && direction != 'down') {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Invalid direction. Must be "up" or "down".'),
        ),
      );
    }

    // Validate steps parameter
    if (steps < 1) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Steps must be at least 1.'),
        ),
      );
    }

    final int sourceSlotIndex = slotIndex!;

    try {
      // Perform multiple move operations
      for (int i = 0; i < steps; i++) {
        if (direction == 'up') {
          // Check if we're already at the top
          if (sourceSlotIndex - i <= 0) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Cannot move algorithm further up. Already at or above slot 0.',
                ),
              ),
            );
          }
          await _controller.moveAlgorithmUp(sourceSlotIndex - i);
        } else {
          // direction == 'down'
          // Check if we're already at the bottom
          if (sourceSlotIndex + i >= maxSlots - 1) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Cannot move algorithm further down. Already at or below slot ${maxSlots - 1}.',
                ),
              ),
            );
          }
          await _controller.moveAlgorithmDown(sourceSlotIndex + i);
        }
      }

      final String stepText = steps == 1 ? 'step' : 'steps';
      final int finalSlot = direction == 'up'
          ? sourceSlotIndex - steps
          : sourceSlotIndex + steps;
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Algorithm moved $steps $stepText $direction from slot $sourceSlotIndex to slot $finalSlot.',
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Retrieves the current module screenshot data.
  /// Parameters: None
  /// Returns:
  ///   A Map containing success status, and either base64 encoded screenshot_base64
  ///   and format, or an error message.
  Future<Map<String, dynamic>> getModuleScreenshot(
    Map<String, dynamic> params,
  ) async {
    try {
      final Uint8List? pngBytesFromController = await _controller
          .getModuleScreenshot(); // Assumed to be PNG bytes

      if (pngBytesFromController != null && pngBytesFromController.isNotEmpty) {
        // 1. Decode PNG bytes (directly from controller) into an Image object
        final img.Image? image = img.decodeImage(pngBytesFromController);

        if (image != null) {
          // 2. Encode the Image object to JPEG bytes
          final Uint8List jpegBytes = img.encodeJpg(image);

          if (jpegBytes.isNotEmpty) {
            final String base64Image = base64Encode(jpegBytes);
            return {
              'success': true,
              'screenshot_base64': base64Image,
              'format': 'jpeg', // Format is JPEG
            };
          } else {
            return {
              'success': false,
              'error': 'Failed to encode screenshot to JPEG after decoding.',
            };
          }
        } else {
          return {
            'success': false,
            'error':
                'Failed to decode PNG bytes (from controller) into an image object.',
          };
        }
      } else {
        return {
          'success': false,
          'error':
              'Module screenshot is currently unavailable (controller returned null/empty) or device not connected.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Exception in get_module_screenshot: ${e.toString()}',
      };
    }
  }

  /// MCP Tool: Retrieves the current CPU usage information from the device.
  /// Parameters: None
  /// Returns:
  ///   A JSON string with CPU usage data including overall CPU1 and CPU2 usage
  ///   percentages and per-slot usage information, or an error message.
  Future<String> getCpuUsage(Map<String, dynamic> params) async {
    try {
      final CpuUsage? cpuUsage = await _controller.getCpuUsage();

      if (cpuUsage != null) {
        // Build slot usage details
        final List<Map<String, dynamic>> slotUsageList = [];
        for (int i = 0; i < cpuUsage.slotUsages.length; i++) {
          slotUsageList.add({
            'slot_index': i,
            'usage_percentage': cpuUsage.slotUsages[i],
          });
        }

        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildSuccess(
              'CPU usage retrieved successfully',
              data: {
                'cpu1_percentage': cpuUsage.cpu1,
                'cpu2_percentage': cpuUsage.cpu2,
                'total_slots': cpuUsage.slotUsages.length,
                'slot_usage': slotUsageList,
              },
            ),
          ),
        );
      } else {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'CPU usage data is currently unavailable. Device may not be connected or synchronized.',
            ),
          ),
        );
      }
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error retrieving CPU usage: ${e.toString()}'),
        ),
      );
    }
  }

  /// MCP Tool: Sets notes text by adding/updating a Notes algorithm and moving it to slot 0.
  /// Parameters:
  ///   - text (string, required): The note text content (max 7 lines, 31 characters each).
  /// Returns:
  ///   A JSON string confirming the action or an error.
  Future<String> setNotes(Map<String, dynamic> params) async {
    final String? text = params['text'];

    // Validate text parameter
    final textError = MCPUtils.validateRequiredParam(text, 'text');
    if (textError != null) {
      return jsonEncode(convertToSnakeCaseKeys(textError));
    }

    try {
      // Split and validate text using the same logic as NotesAlgorithmView
      final lines = _splitTextIntoLines(text!);

      if (!_validateNotesText(lines)) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Text validation failed. Maximum 7 lines of 31 characters each.',
            ),
          ),
        );
      }

      // Find existing Notes algorithm or add one
      final notesSlotIndex = await _findOrAddNotesAlgorithm();

      if (notesSlotIndex == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Failed to create Notes algorithm.'),
          ),
        );
      }

      // Set text parameters (parameters 1-7)
      for (int i = 0; i < 7; i++) {
        final lineText = i < lines.length ? lines[i] : '';
        await _controller.updateParameterString(
          notesSlotIndex,
          i + 1, // Parameters 1-7, not 0-6
          lineText,
        );
      }

      // Move Notes algorithm to slot 0 if it's not already there
      if (notesSlotIndex != 0) {
        int currentSlotIndex = notesSlotIndex;
        while (currentSlotIndex > 0) {
          await _controller.moveAlgorithmUp(currentSlotIndex);
          currentSlotIndex--;
        }
      }

      // Refresh slot 0 to ensure UI is updated with the latest notes content
      await _controller.refreshSlot(0);

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Notes algorithm updated with text and moved to slot 0.',
            data: {'lines_set': lines.length},
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Gets the current notes content from the Notes algorithm if it exists.
  /// Parameters: None
  /// Returns:
  ///   A JSON string with the notes content or an error if no notes exist.
  Future<String> getNotes(Map<String, dynamic> params) async {
    try {
      const String notesGuid = 'note';

      // Find Notes algorithm in any slot
      final Map<int, Algorithm?> allSlots = await _controller.getAllSlots();
      int? notesSlotIndex;

      for (int i = 0; i < maxSlots; i++) {
        final algorithm = allSlots[i];
        if (algorithm != null && algorithm.guid == notesGuid) {
          notesSlotIndex = i;
          break;
        }
      }

      if (notesSlotIndex == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'No Notes algorithm found in current preset',
              helpCommand: 'Use `set_notes` to create notes',
            ),
          ),
        );
      }

      // Get the notes content from parameters 1-7
      // Collect all 7 lines, then trim trailing empty lines
      final List<String> allLines = [];
      for (int i = 1; i <= 7; i++) {
        final String? lineContent = await _controller.getParameterStringValue(
          notesSlotIndex,
          i,
        );
        allLines.add(lineContent ?? '');
      }

      // Remove trailing empty lines but preserve intermediate empty lines
      while (allLines.isNotEmpty && allLines.last.isEmpty) {
        allLines.removeLast();
      }

      final List<String> lines = allLines;

      // Join lines with newline characters
      final String notesText = lines.join('\n');

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Notes content retrieved successfully',
            data: {
              'slot_index': notesSlotIndex,
              'text': notesText,
              'lines': lines,
              'line_count': lines.length,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error retrieving notes: ${e.toString()}'),
        ),
      );
    }
  }

  /// MCP Tool: Gets the current preset name.
  /// Parameters: None
  /// Returns:
  ///   A JSON string with the preset name or an error.
  Future<String> getPresetName(Map<String, dynamic> params) async {
    try {
      final String presetName = await _controller.getCurrentPresetName();

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Preset name retrieved successfully',
            data: {'preset_name': presetName},
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error retrieving preset name: ${e.toString()}'),
        ),
      );
    }
  }

  /// MCP Tool: Gets the custom name for an algorithm in a specific slot.
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot.
  /// Returns:
  ///   A JSON string with the slot name or an error.
  Future<String> getSlotName(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    try {
      final String? slotName = await _controller.getSlotName(slotIndex!);

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Slot name retrieved successfully',
            data: {'slot_index': slotIndex, 'slot_name': slotName ?? ''},
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error retrieving slot name: ${e.toString()}'),
        ),
      );
    }
  }

  /// MCP Tool: Finds if a specific algorithm exists in the current preset.
  /// Parameters:
  ///   - algorithm_guid (string): The unique identifier of the algorithm.
  ///   - algorithm_name (string): The name of the algorithm.
  /// Returns:
  ///   A JSON string with algorithm location or an error if not found.
  Future<String> findAlgorithmInPreset(Map<String, dynamic> params) async {
    final String? algorithmGuid = params['algorithm_guid'];
    final String? algorithmName = params['algorithm_name'];

    // Validate exactly one of algorithm_guid or algorithm_name
    final paramError = MCPUtils.validateExactlyOne(params, [
      'algorithm_guid',
      'algorithm_name',
    ], helpCommand: MCPConstants.getAlgorithmHelp);
    if (paramError != null) {
      return jsonEncode(convertToSnakeCaseKeys(paramError));
    }

    try {
      // Use shared algorithm resolver to get the target GUID
      final algorithms = _getAllKnownAlgorithms();
      final resolution = AlgorithmResolver.resolveAlgorithm(
        guid: algorithmGuid,
        algorithmName: algorithmName,
        allAlgorithms: algorithms,
      );

      if (!resolution.isSuccess) {
        return jsonEncode(convertToSnakeCaseKeys(resolution.error!));
      }

      final String targetGuid = resolution.resolvedGuid!;

      // Search through all slots to find the algorithm
      final Map<int, Algorithm?> allSlots = await _controller.getAllSlots();
      final List<Map<String, dynamic>> foundSlots = [];

      for (int i = 0; i < maxSlots; i++) {
        final algorithm = allSlots[i];
        if (algorithm != null && algorithm.guid == targetGuid) {
          foundSlots.add({
            'slot_index': i,
            'algorithm_name': algorithm.name,
            'algorithm_guid': algorithm.guid,
            'algorithm_index': algorithm.algorithmIndex,
          });
        }
      }

      if (foundSlots.isEmpty) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Algorithm with GUID "$targetGuid" not found in current preset',
              helpCommand: 'Use `add_algorithm` to add it to the preset',
            ),
          ),
        );
      }

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Algorithm found in preset',
            data: {
              'algorithm_guid': targetGuid,
              'found_in_slots': foundSlots,
              'slot_count': foundSlots.length,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error searching for algorithm: ${e.toString()}'),
        ),
      );
    }
  }

  /// MCP Tool: Sets multiple parameters for an algorithm in one operation.
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot.
  ///   - parameters (array, required): Array of parameter objects with parameter_number/parameter_name and value.
  /// Returns:
  ///   A JSON string with results for each parameter or an error.
  Future<String> setMultipleParameters(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;
    final List<dynamic>? parameters = params['parameters'] as List<dynamic>?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    // Validate parameters array
    final paramError = MCPUtils.validateRequiredParam(parameters, 'parameters');
    if (paramError != null) {
      return jsonEncode(convertToSnakeCaseKeys(paramError));
    }

    if (parameters!.isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Parameters array cannot be empty'),
        ),
      );
    }

    try {
      final List<Map<String, dynamic>> results = [];
      bool hasErrors = false;

      for (int i = 0; i < parameters.length; i++) {
        final param = parameters[i];
        if (param is! Map<String, dynamic>) {
          results.add({'error': 'Parameter at index $i must be an object'});
          hasErrors = true;
          continue;
        }

        final paramMap = param;
        final dynamic value =
            paramMap['value']; // Can be num or String for enums
        final int? parameterNumber = paramMap['parameter_number'] as int?;
        final String? parameterName = paramMap['parameter_name'] as String?;

        // Validate this parameter
        if (value == null) {
          results.add({'error': 'Missing "value" field'});
          hasErrors = true;
          continue;
        }

        if (parameterNumber == null && parameterName == null) {
          results.add({
            'error':
                'Must provide either "parameter_number" or "parameter_name"',
          });
          hasErrors = true;
          continue;
        }

        if (parameterNumber != null && parameterName != null) {
          results.add({
            'error':
                'Provide only one of "parameter_number" or "parameter_name"',
          });
          hasErrors = true;
          continue;
        }

        // Create individual parameter update request
        final Map<String, dynamic> individualParams = {
          'slot_index': slotIndex,
          'value': value,
        };
        if (parameterNumber != null) {
          individualParams['parameter_number'] = parameterNumber;
        } else {
          individualParams['parameter_name'] = parameterName!;
        }

        // Call the individual setParameterValue method
        final result = await setParameterValue(individualParams);
        final resultMap = jsonDecode(result) as Map<String, dynamic>;

        if (resultMap['success'] == true) {
          results.add({
            'parameter_number':
                resultMap['parameter_number'] ?? parameterNumber,
            'parameter_name': resultMap['parameter_name'] ?? parameterName,
            'value': resultMap['value'] ?? value,
          });
        } else {
          results.add({'error': resultMap['error'] ?? 'Unknown error'});
          hasErrors = true;
        }
      }

      final successCount = results.where((r) => r.containsKey('value')).length;
      final totalCount = results.length;

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Batch parameter update completed',
            data: {
              'slot_index': slotIndex,
              'total_parameters': totalCount,
              'successful_updates': successCount,
              'failed_updates': totalCount - successCount,
              'has_errors': hasErrors,
              'results': results,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Error in batch parameter update: ${e.toString()}',
          ),
        ),
      );
    }
  }

  /// MCP Tool: Gets multiple parameter values for an algorithm in one operation.
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot.
  ///   - parameter_numbers (array, required): Array of parameter numbers to retrieve.
  /// Returns:
  ///   A JSON string with values for each parameter or an error.
  Future<String> getMultipleParameters(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;
    final List<dynamic>? parameterNumbers =
        params['parameter_numbers'] as List<dynamic>?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    // Validate parameter_numbers array
    final paramError = MCPUtils.validateRequiredParam(
      parameterNumbers,
      'parameter_numbers',
    );
    if (paramError != null) {
      return jsonEncode(convertToSnakeCaseKeys(paramError));
    }

    if (parameterNumbers!.isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Parameter numbers array cannot be empty'),
        ),
      );
    }

    try {
      final List<Map<String, dynamic>> results = [];
      bool hasErrors = false;

      for (int i = 0; i < parameterNumbers.length; i++) {
        final paramNum = parameterNumbers[i];
        if (paramNum is! int) {
          results.add({
            'parameter_number': paramNum,
            'error': 'Parameter number at index $i must be an integer',
          });
          hasErrors = true;
          continue;
        }

        // Call the individual getParameterValue method
        final Map<String, dynamic> individualParams = {
          'slot_index': slotIndex,
          'parameter_number': paramNum,
        };

        final result = await getParameterValue(individualParams);
        final resultMap = jsonDecode(result) as Map<String, dynamic>;

        if (resultMap['success'] == true) {
          results.add({
            'parameter_number': paramNum,
            'value': resultMap['value'],
            'parameter_name': resultMap['parameter_name'],
          });
        } else {
          results.add({
            'parameter_number': paramNum,
            'error': resultMap['error'] ?? 'Unknown error',
          });
          hasErrors = true;
        }
      }

      final successCount = results.where((r) => r.containsKey('value')).length;
      final totalCount = results.length;

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Batch parameter retrieval completed',
            data: {
              'slot_index': slotIndex,
              'total_parameters': totalCount,
              'successful_retrievals': successCount,
              'failed_retrievals': totalCount - successCount,
              'has_errors': hasErrors,
              'results': results,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Error in batch parameter retrieval: ${e.toString()}',
          ),
        ),
      );
    }
  }

  /// MCP Tool: Build a complete preset from JSON data.
  /// Parameters:
  ///   - preset_data (object, required): JSON object with preset_name and slots array.
  ///   - clear_existing (bool, optional): Clear existing preset first (default: true).
  /// Returns:
  ///   A JSON string confirming preset creation or error details.
  Future<String> buildPresetFromJson(Map<String, dynamic> params) async {
    final Map<String, dynamic>? presetData =
        params['preset_data'] as Map<String, dynamic>?;
    final bool clearExisting = params['clear_existing'] ?? true;

    // Validate preset_data parameter
    final presetError = MCPUtils.validateRequiredParam(
      presetData,
      'preset_data',
    );
    if (presetError != null) {
      return jsonEncode(convertToSnakeCaseKeys(presetError));
    }

    try {
      // Validate preset structure
      if (!presetData!.containsKey('preset_name')) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('preset_data must contain "preset_name" field'),
          ),
        );
      }

      if (!presetData.containsKey('slots') || presetData['slots'] is! List) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('preset_data must contain "slots" array'),
          ),
        );
      }

      final String presetName = presetData['preset_name'].toString();
      final List<dynamic> slots = presetData['slots'] as List<dynamic>;

      // Clear existing preset if requested
      if (clearExisting) {
        await _controller.newPreset();
      }

      // Set preset name
      await _controller.setPresetName(presetName);

      final List<Map<String, dynamic>> results = [];
      int successCount = 0;
      int errorCount = 0;

      // Process each slot
      for (
        int slotIndex = 0;
        slotIndex < slots.length && slotIndex < maxSlots;
        slotIndex++
      ) {
        final slotData = slots[slotIndex];

        if (slotData == null) {
          continue; // Skip empty slots
        }

        if (slotData is! Map<String, dynamic>) {
          results.add({
            'slot_index': slotIndex,
            'success': false,
            'error': 'Slot data must be an object',
          });
          errorCount++;
          continue;
        }

        try {
          // Process algorithm
          if (slotData.containsKey('algorithm')) {
            final algorithmData =
                slotData['algorithm'] as Map<String, dynamic>?;
            if (algorithmData != null) {
              final String? algorithmGuid = algorithmData['guid']?.toString();
              final String? algorithmName = algorithmData['name']?.toString();

              // Use AlgorithmResolver to find the algorithm
              final resolution = AlgorithmResolver.resolveAlgorithm(
                guid: algorithmGuid,
                algorithmName: algorithmName,
                allAlgorithms: _getAllKnownAlgorithms(),
              );

              if (resolution.isSuccess) {
                // Add algorithm (this will be added to the first available slot)
                final Map<String, dynamic> addParams = {
                  'algorithm_guid': resolution.resolvedGuid,
                };
                await addAlgorithm(addParams);

                // Process parameters if provided
                if (slotData.containsKey('parameters') &&
                    slotData['parameters'] is List) {
                  final List<dynamic> parameters =
                      slotData['parameters'] as List<dynamic>;
                  final List<Map<String, dynamic>> parameterList = [];

                  for (final param in parameters) {
                    if (param is Map<String, dynamic> &&
                        param.containsKey('value')) {
                      parameterList.add({
                        'parameter_number':
                            param['parameter_number'] ??
                            param['parameterNumber'],
                        'value': param['value'],
                      });
                    }
                  }

                  if (parameterList.isNotEmpty) {
                    final Map<String, dynamic> setParams = {
                      'slot_index': slotIndex,
                      'parameters': parameterList,
                    };
                    await setMultipleParameters(setParams);
                  }
                }

                results.add({
                  'slot_index': slotIndex,
                  'success': true,
                  'algorithm_guid': resolution.resolvedGuid,
                  'parameters_set': slotData.containsKey('parameters')
                      ? (slotData['parameters'] as List).length
                      : 0,
                });
                successCount++;
              } else {
                results.add({
                  'slot_index': slotIndex,
                  'success': false,
                  'error':
                      'Failed to resolve algorithm: ${resolution.error!['error']}',
                });
                errorCount++;
              }
            }
          }
        } catch (e) {
          results.add({
            'slot_index': slotIndex,
            'success': false,
            'error': 'Error processing slot: ${e.toString()}',
          });
          errorCount++;
        }
      }

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Preset built from JSON',
            data: {
              'preset_name': presetName,
              'total_slots_processed': results.length,
              'successful_slots': successCount,
              'failed_slots': errorCount,
              'cleared_existing': clearExisting,
              'results': results,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Error building preset from JSON: ${e.toString()}',
          ),
        ),
      );
    }
  }

  /// MCP Tool: Gets available enum values for an enum parameter
  /// Parameters:
  ///   - slot_index (int, required): The 0-based index of the slot
  ///   - parameter_number (int, optional): The parameter number
  ///   - parameter_name (String, optional): The parameter name
  /// Returns:
  ///   A JSON string with enum values or an error
  Future<String> getParameterEnumValues(Map<String, dynamic> params) async {
    final int? slotIndex = params['slot_index'] as int?;
    final int? parameterNumber = params['parameter_number'] as int?;
    final String? parameterName = params['parameter_name'] as String?;

    // Validate slot index
    final slotError = MCPUtils.validateSlotIndex(slotIndex);
    if (slotError != null) {
      return jsonEncode(convertToSnakeCaseKeys(slotError));
    }

    // Validate exactly one of parameter_number or parameter_name
    final paramError = MCPUtils.validateExactlyOne(params, [
      'parameter_number',
      'parameter_name',
    ]);
    if (paramError != null) {
      return jsonEncode(convertToSnakeCaseKeys(paramError));
    }

    try {
      // Get parameter info to validate it's an enum
      final List<ParameterInfo> paramInfos = await _controller
          .getParametersForSlot(slotIndex!);

      // Find target parameter
      int? targetParamNumber;
      ParameterInfo? paramInfo;

      if (parameterNumber != null) {
        // Find parameter with matching parameterNumber (not array index)
        try {
          paramInfo = paramInfos.firstWhere(
            (p) => p.parameterNumber == parameterNumber,
          );
          targetParamNumber = parameterNumber;
        } catch (e) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter number $parameterNumber not found in slot $slotIndex',
              ),
            ),
          );
        }
      } else if (parameterName != null) {
        // Find by name
        final matchingParams = paramInfos
            .where((p) => p.name.toLowerCase() == parameterName.toLowerCase())
            .toList();

        if (matchingParams.isEmpty) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter name "$parameterName" not found in slot $slotIndex',
              ),
            ),
          );
        }

        if (matchingParams.length > 1) {
          final paramNumbers = matchingParams
              .map((p) => p.parameterNumber)
              .join(', ');
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter name "$parameterName" is ambiguous in slot $slotIndex. Found at parameter numbers: $paramNumbers. Please use parameter_number to disambiguate.',
              ),
            ),
          );
        }

        paramInfo = matchingParams.first;
        targetParamNumber = paramInfo.parameterNumber;
      }

      if (paramInfo == null || targetParamNumber == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Parameter not found in slot $slotIndex'),
          ),
        );
      }

      if (!_isEnumParameter(paramInfo)) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Parameter ${paramInfo.name} is not an enum type',
            ),
          ),
        );
      }

      final enumValues = await _getParameterEnumValues(
        slotIndex,
        targetParamNumber,
      );

      if (enumValues == null || enumValues.isEmpty) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Could not retrieve enum values for parameter ${paramInfo.name}',
            ),
          ),
        );
      }

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Enum values retrieved successfully',
            data: {
              'slot_index': slotIndex,
              'parameter_number': targetParamNumber,
              'parameter_name': paramInfo.name,
              'enum_values': enumValues,
              'current_value_index': (await _controller.getParameterValue(
                slotIndex,
                targetParamNumber,
              ))?.value,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// Helper method to split text into lines with same logic as NotesAlgorithmView
  List<String> _splitTextIntoLines(String text) {
    const int maxLinesCount = 7;
    const int maxLineLength = 31;
    final lines = <String>[];

    if (text.trim().isEmpty) {
      return lines;
    }

    // Split by user line breaks first
    final userLines = text.split('\n');

    for (final userLine in userLines) {
      // Stop if we've already reached the maximum number of lines
      if (lines.length >= maxLinesCount) {
        break;
      }

      // Clean up the current user line (collapse multiple spaces)
      final cleanLine = userLine.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (cleanLine.isEmpty) {
        // User entered an empty line - add it as empty
        lines.add('');
        continue;
      }

      // If the line fits within the character limit, add it as-is
      if (cleanLine.length <= maxLineLength) {
        lines.add(cleanLine);
      } else {
        // Line is too long, need to wrap it
        final words = cleanLine.split(' ');
        String currentLine = '';

        for (final word in words) {
          // Check if adding this word would exceed line length
          final testLine = currentLine.isEmpty ? word : '$currentLine $word';

          if (testLine.length <= maxLineLength) {
            currentLine = testLine;
          } else {
            // Current line is full, start a new one
            if (currentLine.isNotEmpty) {
              lines.add(currentLine);
              currentLine = word;
            } else {
              // Single word is too long, truncate it
              lines.add(word.substring(0, maxLineLength));
              currentLine = '';
            }

            // Stop if we've reached the maximum number of lines
            if (lines.length >= maxLinesCount) {
              break;
            }
          }
        }

        // Add the last line if it's not empty and we haven't exceeded max lines
        if (currentLine.isNotEmpty && lines.length < maxLinesCount) {
          lines.add(currentLine);
        }

        // Stop processing if we've reached the line limit
        if (lines.length >= maxLinesCount) {
          break;
        }
      }
    }

    return lines;
  }

  /// Helper method to validate notes text
  bool _validateNotesText(List<String> lines) {
    const int maxLinesCount = 7;
    const int maxLineLength = 31;

    // Check if we have too many lines
    if (lines.length > maxLinesCount) {
      return false;
    }

    // Check if any individual line exceeds the character limit
    for (final line in lines) {
      if (line.length > maxLineLength) {
        return false;
      }
    }

    return true;
  }

  /// Helper method to find existing Notes algorithm or add one
  Future<int?> _findOrAddNotesAlgorithm() async {
    const String notesGuid = 'note';

    // First, check if Notes algorithm already exists in any slot
    final Map<int, Algorithm?> allSlots = await _controller.getAllSlots();

    for (int i = 0; i < maxSlots; i++) {
      final algorithm = allSlots[i];
      if (algorithm != null && algorithm.guid == notesGuid) {
        return i; // Found existing Notes algorithm
      }
    }

    // Notes algorithm not found, add it
    try {
      final notesAlgorithm = Algorithm(
        algorithmIndex: -1, // Will be assigned by hardware
        guid: notesGuid,
        name: 'Notes',
      );

      final slotIndex = await _addAlgorithmAndVerify(notesAlgorithm);
      return slotIndex;
    } catch (e) {
      return null;
    }
  }

  /// MCP Tool: Creates a new blank preset or preset with initial algorithms.
  /// Parameters:
  ///   - name (string, required): The name for the new preset.
  ///   - algorithms (array, optional): Array of algorithms to add, each with:
  ///     - guid (string): The GUID of the algorithm (alternative to name).
  ///     - name (string): The name of the algorithm (fuzzy matching ≥70%, alternative to guid).
  ///     - specifications (array, optional): Algorithm-specific specification values.
  /// Returns:
  ///   A JSON string with the created preset state including all slots, default
  ///   parameter values, and disabled mappings, or an error message.
  Future<String> newWithAlgorithms(Map<String, dynamic> params) async {
    try {
      // Step 1: Extract and validate parameters
      final String? name = params['name'] as String?;
      if (name == null || name.isEmpty) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Missing "name". Example: {"name": "My Preset", "algorithms": [{"name": "VCO"}]}',
            ),
          ),
        );
      }

      final List<dynamic>? algorithmsArray =
          params['algorithms'] as List<dynamic>?;
      final offlineMode = _isOfflineMode();

      // Step 2: Verify device is in connected mode (SynchronizedState)
      // This check would normally be done by the DistingCubit state,
      // but we're working with the controller directly.
      // If the controller throws an error for offline mode, we'll catch it.

      // Step 3: Clear current preset
      try {
        await _controller.newPreset();
      } catch (e) {
        // Check if error indicates offline/demo mode
        if (e.toString().contains('offline') ||
            e.toString().contains('demo') ||
            e.toString().contains('not synchronized')) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Cannot create preset in offline or demo mode. Device must be in connected mode.',
              ),
            ),
          );
        }
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Failed to clear preset: ${e.toString()}'),
          ),
        );
      }

      // Step 4: Set preset name
      try {
        await _controller.setPresetName(name);
      } catch (e) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Failed to set preset name: ${e.toString()}'),
          ),
        );
      }

      // Step 5: Add algorithms if provided
      final List<Map<String, dynamic>> algorithmResults = [];

      if (algorithmsArray != null && algorithmsArray.isNotEmpty) {
        final metadataService = AlgorithmMetadataService();
        final allAlgorithms = _getAllKnownAlgorithms();

        for (int i = 0; i < algorithmsArray.length; i++) {
          final algoSpec = algorithmsArray[i];

          if (algoSpec is! Map<String, dynamic>) {
            algorithmResults.add({
              'index': i,
              'success': false,
              'error': 'Algorithm specification must be an object',
            });
            continue;
          }

          final String? algoGuid = algoSpec['guid'] as String?;
          final String? algoName = algoSpec['name'] as String?;
          final List<dynamic>? specifications =
              algoSpec['specifications'] as List<dynamic>?;

          // Resolve algorithm
          final resolution = AlgorithmResolver.resolveAlgorithm(
            guid: algoGuid,
            algorithmName: algoName,
            allAlgorithms: allAlgorithms,
          );

          if (!resolution.isSuccess) {
            algorithmResults.add({
              'index': i,
              'success': false,
              'error':
                  resolution.error!['error'] ?? 'Failed to resolve algorithm',
            });
            continue;
          }

          final resolvedGuid = resolution.resolvedGuid!;

          // Get name from metadata or device state
          final algorithmMetadata = metadataService.getAlgorithmByGuid(
            resolvedGuid,
          );
          final deviceAlgoInfo = _getDeviceAlgorithmInfo(resolvedGuid);
          final algoDisplayName =
              algorithmMetadata?.name ?? deviceAlgoInfo?.name ?? resolvedGuid;

          // Validate specifications against device state
          final requiredSpecs = deviceAlgoInfo?.specifications ?? [];
          final List<int> specValues = [];
          String? limitationMessage;

          if (requiredSpecs.isNotEmpty) {
            if (offlineMode) {
              specValues.addAll(requiredSpecs.map((s) => s.defaultValue));
              limitationMessage = _buildOfflineSpecsLimitation(
                resolvedGuid,
                requiredSpecs,
              );
            } else {
              if (specifications == null || specifications.isEmpty) {
                algorithmResults.add({
                  'index': i,
                  'success': false,
                  'error':
                      'Algorithm "$algoDisplayName" requires ${requiredSpecs.length} specification(s)',
                  'specifications': requiredSpecs
                      .map(
                        (s) => {
                          'name': s.name,
                          'min': s.min,
                          'max': s.max,
                          'default': s.defaultValue,
                        },
                      )
                      .toList(),
                });
                continue;
              }

              if (specifications.length != requiredSpecs.length) {
                algorithmResults.add({
                  'index': i,
                  'success': false,
                  'error':
                      'Algorithm "$algoDisplayName" requires ${requiredSpecs.length} specification(s), got ${specifications.length}',
                  'specifications': requiredSpecs
                      .map(
                        (s) => {
                          'name': s.name,
                          'min': s.min,
                          'max': s.max,
                          'default': s.defaultValue,
                        },
                      )
                      .toList(),
                });
                continue;
              }

              bool specError = false;
              for (int j = 0; j < specifications.length; j++) {
                final spec = requiredSpecs[j];
                final value = specifications[j];
                if (value is! int) {
                  algorithmResults.add({
                    'index': i,
                    'success': false,
                    'error':
                        'Specification "${spec.name}" must be an integer, got ${value.runtimeType}',
                  });
                  specError = true;
                  break;
                }
                if (value < spec.min || value > spec.max) {
                  algorithmResults.add({
                    'index': i,
                    'success': false,
                    'error':
                        'Specification "${spec.name}" value $value out of range (${spec.min}-${spec.max})',
                  });
                  specError = true;
                  break;
                }
                specValues.add(value);
              }
              if (specError) continue;
            }
          } else if (specifications != null && specifications.isNotEmpty) {
            specValues.addAll(specifications.whereType<int>());
          }

          // Add algorithm to preset
          try {
            final algorithm = Algorithm(
              algorithmIndex: -1,
              guid: resolvedGuid,
              name: algoDisplayName,
              specifications: specValues,
            );
            await _addAlgorithmAndVerify(algorithm);

            algorithmResults.add({
              'index': i,
              'success': true,
              'guid': resolvedGuid,
              'name': algoDisplayName,
              // ignore: use_null_aware_elements
              if (limitationMessage != null) 'limitation': limitationMessage,
              if (limitationMessage != null)
                'effective_specifications': specValues,
            });
          } catch (e) {
            algorithmResults.add({
              'index': i,
              'success': false,
              'error': 'Failed to add algorithm: ${e.toString()}',
            });
          }
        }
      }

      // Step 6: Query current preset state
      try {
        final presetName = await _controller.getCurrentPresetName();
        final Map<int, Algorithm?> slotAlgorithms = await _controller
            .getAllSlots();

        List<Map<String, dynamic>?> slotsJsonList = List.filled(maxSlots, null);

        for (int i = 0; i < maxSlots; i++) {
          final algorithm = slotAlgorithms[i];
          if (algorithm != null) {
            final List<ParameterInfo> parameterInfos = await _controller
                .getParametersForSlot(i);

            List<Map<String, dynamic>> parametersJsonList = [];
            for (
              int paramIndex = 0;
              paramIndex < parameterInfos.length;
              paramIndex++
            ) {
              final pInfo = parameterInfos[paramIndex];
              final ParameterValue? paramValue = await _controller
                  .getParameterValue(i, pInfo.parameterNumber);
              final int? liveRawValue = paramValue?.value;

              final paramData = <String, dynamic>{
                'parameter_number': pInfo.parameterNumber,
                'parameter_name': pInfo.name,
                'is_disabled': paramValue?.isDisabled ?? false,
              };

              if (_isEnumParameter(pInfo)) {
                final enumValues = await _getParameterEnumValues(
                  i,
                  pInfo.parameterNumber,
                );
                if (enumValues != null) {
                  paramData['is_enum'] = true;
                  paramData['valid_enum_values'] = enumValues;
                  if (liveRawValue != null) {
                    paramData['value'] =
                        _enumIndexToString(enumValues, liveRawValue) ?? '';
                  }
                }
              } else {
                paramData['value'] = liveRawValue != null
                    ? _scaleForDisplay(liveRawValue, pInfo.powerOfTen)
                    : null;
                paramData['min_value'] = _scaleForDisplay(
                  pInfo.min,
                  pInfo.powerOfTen,
                );
                paramData['max_value'] = _scaleForDisplay(
                  pInfo.max,
                  pInfo.powerOfTen,
                );
                paramData['default_value'] = _scaleForDisplay(
                  pInfo.defaultValue,
                  pInfo.powerOfTen,
                );
              }

              // Add mapping information
              try {
                final mapping = await _controller.getParameterMapping(
                  i,
                  pInfo.parameterNumber,
                );
                if (mapping != null) {
                  final perfPageIndex = mapping.packedMappingData.perfPageIndex;
                  if (perfPageIndex > 0) {
                    paramData['performance_page'] = perfPageIndex;
                  }
                }
              } catch (e) {
                // Intentionally empty
              }

              parametersJsonList.add(paramData);
            }

            slotsJsonList[i] = {
              'slot_index': i,
              'algorithm': {
                'guid': algorithm.guid,
                'name': algorithm.name,
                'algorithm_index': algorithm.algorithmIndex,
              },
              'parameters': parametersJsonList,
            };
          }
        }

        final Map<String, dynamic> responseData = {
          'preset_name': presetName,
          'slots': slotsJsonList,
          'algorithms_added': algorithmResults
              .where((r) => r['success'] == true)
              .length,
          'algorithms_failed': algorithmResults
              .where((r) => r['success'] == false)
              .length,
        };

        // Only include algorithm_results if there were algorithms to add
        if (algorithmsArray != null && algorithmsArray.isNotEmpty) {
          responseData['algorithm_results'] = algorithmResults;
        }

        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildSuccess(
              'Preset created successfully',
              data: responseData,
            ),
          ),
        );
      } catch (e) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Failed to retrieve preset state: ${e.toString()}',
            ),
          ),
        );
      }
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error in new tool: ${e.toString()}'),
        ),
      );
    }
  }

  /// MCP Tool: Edit preset with preset-level granularity
  /// Accepts a complete preset state and applies only necessary changes
  /// Parameters:
  ///   - data (object, required): Preset JSON with name and slots array
  /// Returns:
  ///   Updated preset state after successful application or detailed error
  Future<String> editPreset(Map<String, dynamic> params) async {
    try {
      final Map<String, dynamic>? data =
          params['data'] as Map<String, dynamic>?;
      if (data == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('${MCPConstants.missingParamError}: "data"'),
          ),
        );
      }

      // Step 2: Parse and validate desired preset data
      final String? desiredName = data['name'] as String?;
      final List<dynamic>? desiredSlotsData = data['slots'] as List<dynamic>?;

      if (desiredName == null || desiredName.isEmpty) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Preset name is required and must not be empty',
            ),
          ),
        );
      }

      // Step 2.5: Check if we're only changing the name
      final bool isNameOnlyChange =
          desiredSlotsData == null || desiredSlotsData.isEmpty;

      // Step 2.6: Validate connection mode (AC #16) - after basic parameter checks
      if (!_controller.isSynchronized) {
        // Allow name-only changes even when not fully synchronized
        if (!isNameOnlyChange) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Device is not in a synchronized state, cannot edit preset slots.',
              ),
            ),
          );
        }
      }

      // Step 3: Get current preset state (requires device connection)
      final Map<int, Algorithm?> currentSlotAlgorithms = await _controller
          .getAllSlots();
      final String currentPresetName = await _controller.getCurrentPresetName();

      // Step 4: Build desired slots map from input data
      // If no slots provided, we're only updating the name
      final Map<int, DesiredSlot> desiredSlots = {};
      if (desiredSlotsData != null && desiredSlotsData.isNotEmpty) {
        for (int i = 0; i < desiredSlotsData.length; i++) {
          final slotData = desiredSlotsData[i];
          if (slotData is! Map<String, dynamic>) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError('Slot at index $i must be an object'),
              ),
            );
          }

          final Map<String, dynamic>? algoData =
              slotData['algorithm'] as Map<String, dynamic>?;
          if (algoData == null) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Slot at index $i is missing algorithm object',
                ),
              ),
            );
          }

          final String? algoGuid = algoData['guid'] as String?;
          final String? algoName = algoData['name'] as String?;

          if (algoGuid == null && algoName == null) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Algorithm in slot $i must have either guid or name',
                ),
              ),
            );
          }

          desiredSlots[i] = DesiredSlot(
            guid: algoGuid,
            name: algoName,
            parameters: slotData['parameters'] as List<dynamic>?,
            mapping: slotData['mapping'] as Map<String, dynamic>?,
          );
        }
      }

      // Step 5: Validate diff
      final validationError = await _validateDiff(
        currentSlotAlgorithms,
        desiredSlots,
        desiredName,
      );
      if (validationError != null) {
        return jsonEncode(convertToSnakeCaseKeys(validationError));
      }

      // Step 6: Apply diff changes
      final applyError = await _applyDiff(
        currentSlotAlgorithms,
        desiredSlots,
        desiredName,
        currentPresetName,
      );
      if (applyError != null) {
        return jsonEncode(convertToSnakeCaseKeys(applyError));
      }

      // Step 7: Flush queued writes then save
      try {
        await _controller.flushParameterQueue();
        await _controller.savePreset();
      } catch (e) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Failed to save preset: ${e.toString()}'),
          ),
        );
      }

      // Step 8: Get updated state and return
      try {
        final presetName = await _controller.getCurrentPresetName();
        final Map<int, Algorithm?> slotAlgorithms = await _controller
            .getAllSlots();

        List<Map<String, dynamic>?> slotsJsonList = List.filled(maxSlots, null);

        for (int i = 0; i < maxSlots; i++) {
          final algorithm = slotAlgorithms[i];
          if (algorithm != null) {
            final List<ParameterInfo> parameterInfos = await _controller
                .getParametersForSlot(i);

            List<Map<String, dynamic>> parametersJsonList = [];
            for (
              int paramIndex = 0;
              paramIndex < parameterInfos.length;
              paramIndex++
            ) {
              final pInfo = parameterInfos[paramIndex];
              final ParameterValue? paramValue = await _controller
                  .getParameterValue(i, pInfo.parameterNumber);
              final int? liveRawValue = paramValue?.value;

              final paramData = {
                'parameter_number': pInfo.parameterNumber,
                'parameter_name': pInfo.name,
                'value': liveRawValue != null
                    ? _scaleForDisplay(liveRawValue, pInfo.powerOfTen)
                    : null,
                'is_disabled': paramValue?.isDisabled ?? false,
              };

              parametersJsonList.add(paramData);
            }

            slotsJsonList[i] = {
              'slot_index': i,
              'algorithm': {'guid': algorithm.guid, 'name': algorithm.name},
              'parameters': parametersJsonList,
            };
          }
        }

        return jsonEncode(
          convertToSnakeCaseKeys({
            'success': true,
            'persisted': true,
            'preset_name': presetName,
            'slots': slotsJsonList,
          }),
        );
      } catch (e) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Failed to retrieve updated preset state: ${e.toString()}',
            ),
          ),
        );
      }
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error in edit tool: ${e.toString()}'),
        ),
      );
    }
  }

  /// Edits a single slot with slot-level or parameter-level granularity
  /// Applies only necessary changes to the specified slot or parameter while preserving other data
  Future<String> editSlot(Map<String, dynamic> params) async {
    try {
      final int? slotIndex = params['slot_index'] as int?;
      if (slotIndex == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Missing "slot_index". Use show_preset to see occupied slots.',
            ),
          ),
        );
      }

      // Validate slot_index range
      if (slotIndex < 0 || slotIndex >= maxSlots) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'slot_index $slotIndex out of range. Must be 0-${maxSlots - 1}.',
            ),
          ),
        );
      }

      final Map<String, dynamic>? data =
          params['data'] as Map<String, dynamic>?;
      if (data == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Missing "data" object. Example: {"data": {"algorithm": {"name": "VCO"}}}',
            ),
          ),
        );
      }

      // Step 2: Validate connection mode
      if (!_controller.isSynchronized) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Device is not in a synchronized state, cannot edit slot.',
            ),
          ),
        );
      }

      // Step 3: Get current slot state
      final Algorithm? currentAlgorithm = await _controller.getAlgorithmInSlot(
        slotIndex,
      );

      // Step 4: Parse desired slot data
      final Map<String, dynamic>? algorithmData =
          data['algorithm'] as Map<String, dynamic>?;
      final String? desiredName = data['name'] as String?;
      final List<dynamic>? parametersData =
          data['parameters'] as List<dynamic>?;

      // Step 5: Validate algorithm (if specified)
      String? resolvedAlgorithmGuid;
      String? limitationMessage;
      List<int>? effectiveOfflineSpecifications;
      if (algorithmData != null) {
        final String? algoGuid = algorithmData['guid'] as String?;
        final String? algoName = algorithmData['name'] as String?;

        if (algoGuid == null && algoName == null) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError('Algorithm must have either guid or name'),
            ),
          );
        }

        final allAlgorithms = _getAllKnownAlgorithms();

        final resolution = AlgorithmResolver.resolveAlgorithm(
          guid: algoGuid,
          algorithmName: algoName,
          allAlgorithms: allAlgorithms,
        );

        if (!resolution.isSuccess) {
          return jsonEncode(convertToSnakeCaseKeys(resolution.error));
        }

        resolvedAlgorithmGuid = resolution.resolvedGuid!;

        // Validate specifications using device state
        final deviceAlgoInfo = _getDeviceAlgorithmInfo(resolvedAlgorithmGuid);
        final List<dynamic>? specifications =
            algorithmData['specifications'] as List<dynamic>?;
        final requiredSpecs = deviceAlgoInfo?.specifications ?? [];
        final offlineMode = _isOfflineMode();
        final isCurrentAlgorithm =
            currentAlgorithm?.guid == resolvedAlgorithmGuid;

        if (requiredSpecs.isNotEmpty) {
          if (isCurrentAlgorithm &&
              (specifications == null || specifications.isEmpty)) {
            // Algorithm identity in a patch is redundant when the requested
            // GUID is already instantiated. Its construction specifications
            // are not needed to update parameters, mappings, or the slot name.
          } else if (offlineMode) {
            effectiveOfflineSpecifications = requiredSpecs
                .map((s) => s.defaultValue)
                .toList();
            limitationMessage = _buildOfflineSpecsLimitation(
              resolvedAlgorithmGuid,
              requiredSpecs,
            );
          } else {
            if (specifications == null || specifications.isEmpty) {
              return jsonEncode(
                convertToSnakeCaseKeys(
                  _buildSpecRequiredError(resolvedAlgorithmGuid, requiredSpecs),
                ),
              );
            }

            if (specifications.length != requiredSpecs.length) {
              return jsonEncode(
                convertToSnakeCaseKeys({
                  ..._buildSpecRequiredError(
                    resolvedAlgorithmGuid,
                    requiredSpecs,
                  ),
                  'error':
                      'Algorithm "$resolvedAlgorithmGuid" requires ${requiredSpecs.length} specification(s), got ${specifications.length}.',
                }),
              );
            }

            for (int j = 0; j < specifications.length; j++) {
              final spec = requiredSpecs[j];
              final value = specifications[j];
              if (value is! int) {
                return jsonEncode(
                  convertToSnakeCaseKeys(
                    MCPUtils.buildError(
                      'Specification "${spec.name}" must be an integer, got ${value.runtimeType}',
                    ),
                  ),
                );
              }
              if (value < spec.min || value > spec.max) {
                return jsonEncode(
                  convertToSnakeCaseKeys(
                    MCPUtils.buildError(
                      'Specification "${spec.name}" value $value out of range (${spec.min}-${spec.max})',
                    ),
                  ),
                );
              }
            }
          }
        } else if (!offlineMode &&
            specifications != null &&
            specifications.isNotEmpty) {
          // Algorithm has no specs but some were provided - validate count from metadata
          final metadataService = AlgorithmMetadataService();
          final algorithmMetadata = metadataService.getAlgorithmByGuid(
            resolvedAlgorithmGuid,
          );
          if (algorithmMetadata != null &&
              specifications.length > algorithmMetadata.specifications.length) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Algorithm "$resolvedAlgorithmGuid" expects ${algorithmMetadata.specifications.length} specification(s), got ${specifications.length}',
                ),
              ),
            );
          }
        }
      }

      // Step 6: Validate parameters (if specified)
      final Map<int, Map<String, dynamic>> parametersMap = {};
      if (parametersData != null) {
        for (int i = 0; i < parametersData.length; i++) {
          final paramData = parametersData[i];
          if (paramData is! Map<String, dynamic>) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError('Parameter at index $i must be an object'),
              ),
            );
          }

          final int? paramNumber = paramData['parameter_number'] as int?;
          if (paramNumber == null) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Parameter at index $i is missing "parameter_number"',
                ),
              ),
            );
          }

          // Get parameter infos for validation
          final List<ParameterInfo> parameterInfos = await _controller
              .getParametersForSlot(slotIndex);

          // Validate parameter number (by hardware parameter number, not array index)
          final paramIdx = parameterInfos.indexWhere(
            (p) => p.parameterNumber == paramNumber,
          );
          if (paramIdx == -1) {
            final available = parameterInfos
                .map((p) => p.parameterNumber)
                .toList();
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Parameter number $paramNumber not found. Available parameter numbers: $available',
                ),
              ),
            );
          }

          // Validate parameter value if specified
          final dynamic paramValue = paramData['value'];
          if (paramValue != null) {
            final pInfo = parameterInfos[paramIdx];

            if (_isEnumParameter(pInfo)) {
              if (paramValue is! String) {
                return jsonEncode(
                  convertToSnakeCaseKeys(
                    MCPUtils.buildError(
                      'Enum parameter "${pInfo.name}" requires a string value '
                      'from its valid_enum_values list.',
                    ),
                  ),
                );
              }
              final enumValues = await _getParameterEnumValues(
                slotIndex,
                pInfo.parameterNumber,
              );
              if (enumValues == null) {
                return jsonEncode(
                  convertToSnakeCaseKeys(
                    MCPUtils.buildError(
                      'Could not retrieve enum values for parameter "${pInfo.name}"',
                    ),
                  ),
                );
              }
              final enumIndex = _enumStringToIndex(enumValues, paramValue);
              if (enumIndex == null) {
                return jsonEncode(
                  convertToSnakeCaseKeys(
                    MCPUtils.buildError(
                      'Invalid value "$paramValue" for parameter "${pInfo.name}". '
                      'Valid values: ${enumValues.join(", ")}',
                    ),
                  ),
                );
              }
              // Store resolved enum index for later application
              paramData['value'] = enumIndex;
            } else {
              if (paramValue is! num) {
                return jsonEncode(
                  convertToSnakeCaseKeys(
                    MCPUtils.buildError(
                      'Parameter "${pInfo.name}" requires a numeric value.',
                    ),
                  ),
                );
              }

              final rawValue = MCPUtils.scaleToRaw(
                paramValue,
                pInfo.powerOfTen,
              );

              // Validate against parameter bounds (raw)
              if (rawValue < pInfo.min || rawValue > pInfo.max) {
                final displayMin = _scaleForDisplay(
                  pInfo.min,
                  pInfo.powerOfTen,
                );
                final displayMax = _scaleForDisplay(
                  pInfo.max,
                  pInfo.powerOfTen,
                );
                return jsonEncode(
                  convertToSnakeCaseKeys(
                    MCPUtils.buildError(
                      'Value $paramValue out of range for parameter "${pInfo.name}" ($displayMin-$displayMax)',
                    ),
                  ),
                );
              }
            }
          }

          // Validate mapping if specified
          final Map<String, dynamic>? mapping =
              paramData['mapping'] as Map<String, dynamic>?;
          if (mapping != null) {
            final mappingError = _validateMapping(
              mapping,
              slotIndex,
              paramNumber,
            );
            if (mappingError != null) {
              return jsonEncode(convertToSnakeCaseKeys(mappingError));
            }
          }

          parametersMap[paramNumber] = paramData;
        }
      }

      // Step 7: Apply changes
      // If algorithm changes, clear slot and add new algorithm
      if (resolvedAlgorithmGuid != null &&
          currentAlgorithm?.guid != resolvedAlgorithmGuid) {
        try {
          // Collect spec values if provided
          final List<int> specValues = [];
          if (effectiveOfflineSpecifications != null) {
            specValues.addAll(effectiveOfflineSpecifications);
          } else {
            final algorithmData2 = data['algorithm'] as Map<String, dynamic>?;
            final specList =
                algorithmData2?['specifications'] as List<dynamic>?;
            if (specList != null) {
              specValues.addAll(specList.whereType<int>());
            }
          }

          await _controller.clearSlot(slotIndex);
          final newAlgorithm = Algorithm(
            algorithmIndex: -1,
            guid: resolvedAlgorithmGuid,
            name: '',
            specifications: specValues,
          );
          await _addAlgorithmAndVerify(newAlgorithm);
        } catch (e) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Failed to change algorithm: ${e.toString()}',
              ),
            ),
          );
        }
      }

      // Update parameters if specified
      for (final entry in parametersMap.entries) {
        final paramNumber = entry.key;
        final paramData = entry.value;
        final paramValue = paramData['value'];

        if (paramValue != null) {
          try {
            final allParams = await _controller.getParametersForSlot(slotIndex);
            final pInfo = allParams.firstWhere(
              (p) => p.parameterNumber == paramNumber,
            );
            // Enum values are already resolved to raw ints during validation;
            // only scale display→raw for regular numeric params.
            final int rawValue = _isEnumParameter(pInfo)
                ? (paramValue as num).toInt()
                : MCPUtils.scaleToRaw(paramValue, pInfo.powerOfTen);
            await _controller.updateParameterValue(
              slotIndex,
              paramNumber,
              rawValue,
            );
          } catch (e) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Failed to update parameter $paramNumber: ${e.toString()}',
                ),
              ),
            );
          }
        }

        // Handle mapping updates
        final Map<String, dynamic>? mapping =
            paramData['mapping'] as Map<String, dynamic>?;
        if (mapping != null) {
          await _applyMappingUpdates(slotIndex, paramNumber, mapping);
        }
      }

      // Update slot name if specified
      if (desiredName != null && desiredName.isNotEmpty) {
        try {
          await _controller.setSlotName(slotIndex, desiredName);
        } catch (e) {
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Failed to update slot name: ${e.toString()}',
              ),
            ),
          );
        }
      }

      // Step 8: Flush queued writes then save
      try {
        await _controller.flushParameterQueue();
        await _controller.savePreset();
      } catch (e) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Failed to save preset: ${e.toString()}'),
          ),
        );
      }

      // Step 9: Get updated slot state and return
      try {
        final updatedAlgorithm = await _controller.getAlgorithmInSlot(
          slotIndex,
        );
        final updatedParameterInfos = await _controller.getParametersForSlot(
          slotIndex,
        );

        if (updatedAlgorithm == null) {
          return jsonEncode(
            convertToSnakeCaseKeys({
              'success': true,
              'slot_index': slotIndex,
              'algorithm': null,
              'parameters': [],
            }),
          );
        }

        List<Map<String, dynamic>> parametersJsonList = [];
        for (int i = 0; i < updatedParameterInfos.length; i++) {
          final pInfo = updatedParameterInfos[i];
          final ParameterValue? paramValue = await _controller
              .getParameterValue(slotIndex, pInfo.parameterNumber);
          final int? liveRawValue = paramValue?.value;

          final paramData = <String, dynamic>{
            'parameter_number': pInfo.parameterNumber,
            'parameter_name': pInfo.name,
            'is_disabled': paramValue?.isDisabled ?? false,
          };

          if (_isEnumParameter(pInfo) && liveRawValue != null) {
            final enumValues = await _getParameterEnumValues(
              slotIndex,
              pInfo.parameterNumber,
            );
            if (enumValues != null) {
              paramData['is_enum'] = true;
              paramData['valid_enum_values'] = enumValues;
              paramData['value'] =
                  _enumIndexToString(enumValues, liveRawValue) ?? '';
            }
          } else {
            paramData['value'] = liveRawValue != null
                ? _scaleForDisplay(liveRawValue, pInfo.powerOfTen)
                : null;
          }

          parametersJsonList.add(paramData);
        }

        final slotName = await _controller.getSlotName(slotIndex);

        final response = <String, dynamic>{
          'success': true,
          'persisted': true,
          'slot_index': slotIndex,
          'algorithm': {
            'guid': updatedAlgorithm.guid,
            'name': updatedAlgorithm.name,
          },
          'name': slotName,
          'parameters': parametersJsonList,
        };
        if (limitationMessage != null) {
          response['limitation'] = limitationMessage;
          response['effective_specifications'] = effectiveOfflineSpecifications;
        }

        return jsonEncode(convertToSnakeCaseKeys(response));
      } catch (e) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Failed to retrieve updated slot state: ${e.toString()}',
            ),
          ),
        );
      }
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error in editSlot tool: ${e.toString()}'),
        ),
      );
    }
  }

  /// Edits a single parameter with parameter-level granularity
  /// Allows updating parameter value and/or mapping without sending full slot data
  Future<String> editParameter(Map<String, dynamic> params) async {
    try {
      // Step 1: Validate input parameters
      final int? slotIndex = params['slot_index'] as int?;
      if (slotIndex == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Missing "slot_index". Use show_preset to see occupied slots.',
            ),
          ),
        );
      }

      // Validate slot_index range
      if (slotIndex < 0 || slotIndex >= maxSlots) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'slot_index $slotIndex out of range. Must be 0-${maxSlots - 1}.',
            ),
          ),
        );
      }

      // Get parameter identifier (name or number)
      final dynamic parameterIdent = params['parameter_number'];
      if (parameterIdent == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Missing "parameter_number". Use show_slot tool with slot_index: $slotIndex to see parameter numbers and names.',
            ),
          ),
        );
      }

      // Get value and mapping (at least one must be provided)
      final dynamic value = params['value'];
      final Map<String, dynamic>? mapping =
          params['mapping'] as Map<String, dynamic>?;

      if (value == null && (mapping == null || mapping.isEmpty)) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Missing "value" or "mapping". Provide at least one. Example: {"value": 100}',
            ),
          ),
        );
      }

      // Step 2: Validate connection mode
      if (!_controller.isSynchronized) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Device is not in a synchronized state, cannot edit parameter.',
            ),
          ),
        );
      }

      // Step 3: Get current slot state and parameter info
      final Algorithm? algorithm = await _controller.getAlgorithmInSlot(
        slotIndex,
      );
      if (algorithm == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Slot $slotIndex is empty. Use add tool to add an algorithm first, '
              'or show_preset to see which slots have algorithms.',
            ),
          ),
        );
      }

      // Step 4: Resolve parameter identifier (by number or by name)
      final List<ParameterInfo> parameters = await _controller
          .getParametersForSlot(slotIndex);

      int? parameterNumber;
      String? parameterName;

      if (parameterIdent is int) {
        // Parameter identified by hardware parameter number
        final idx = parameters.indexWhere(
          (p) => p.parameterNumber == parameterIdent,
        );
        if (idx == -1) {
          final available = parameters
              .map((p) => '${p.parameterNumber}: ${p.name}')
              .toList()
              .join(', ');
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter number $parameterIdent not found. Available parameters: $available',
              ),
            ),
          );
        }
        parameterNumber = parameterIdent;
        parameterName = parameters[idx].name;
      } else if (parameterIdent is String) {
        // Parameter identified by name (exact match)
        bool found = false;
        for (int i = 0; i < parameters.length; i++) {
          if (parameters[i].name == parameterIdent) {
            parameterNumber = parameters[i].parameterNumber;
            parameterName = parameterIdent;
            found = true;
            break;
          }
        }
        if (!found) {
          final availableNames = parameters
              .map((p) => p.name)
              .toList()
              .join(', ');
          return jsonEncode(
            convertToSnakeCaseKeys(
              MCPUtils.buildError(
                'Parameter "$parameterIdent" not found. Available parameters: $availableNames',
              ),
            ),
          );
        }
      } else {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Parameter must be a string name or integer number',
            ),
          ),
        );
      }

      final int resolvedParameterNumber = parameterNumber!;
      final ParameterInfo paramInfo = parameters.firstWhere(
        (p) => p.parameterNumber == resolvedParameterNumber,
      );

      // Step 5: Validate value (if provided) — convert display→raw
      int? rawValue;
      if (value != null) {
        if (_isEnumParameter(paramInfo)) {
          if (value is! String) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Enum parameter "$parameterName" requires a string value '
                  'from its valid_enum_values list.',
                ),
              ),
            );
          }
          final enumValues = await _getParameterEnumValues(
            slotIndex,
            resolvedParameterNumber,
          );
          if (enumValues == null) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Could not retrieve enum values for parameter "$parameterName"',
                ),
              ),
            );
          }
          final enumIndex = _enumStringToIndex(enumValues, value);
          if (enumIndex == null) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Invalid value "$value" for parameter "$parameterName". '
                  'Valid values: ${enumValues.join(", ")}',
                ),
              ),
            );
          }
          rawValue = enumIndex;
        } else {
          if (value is! num) {
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Parameter "$parameterName" requires a numeric value.',
                ),
              ),
            );
          }
          rawValue = MCPUtils.scaleToRaw(value, paramInfo.powerOfTen);
          if (rawValue < paramInfo.min || rawValue > paramInfo.max) {
            final displayMin = _scaleForDisplay(
              paramInfo.min,
              paramInfo.powerOfTen,
            );
            final displayMax = _scaleForDisplay(
              paramInfo.max,
              paramInfo.powerOfTen,
            );
            return jsonEncode(
              convertToSnakeCaseKeys(
                MCPUtils.buildError(
                  'Value $value out of range for parameter "$parameterName" ($displayMin-$displayMax)',
                ),
              ),
            );
          }
        }
      }

      // Step 6: Validate mapping (if provided)
      if (mapping != null && mapping.isNotEmpty) {
        final validationError = await _validateMappingFields(
          slotIndex,
          resolvedParameterNumber,
          mapping,
        );
        if (validationError != null) {
          return jsonEncode(convertToSnakeCaseKeys(validationError));
        }
      }

      // Step 7: Apply changes
      // Update value if provided (use raw value converted from display scale)
      if (value != null && rawValue != null) {
        await _controller.updateParameterValue(
          slotIndex,
          resolvedParameterNumber,
          rawValue,
        );
      }

      // Update mappings if provided
      if (mapping != null && mapping.isNotEmpty) {
        await _applyMappingUpdates(slotIndex, resolvedParameterNumber, mapping);
      }

      // Flush queued parameter writes, then save so the preset includes them.
      await _controller.flushParameterQueue();
      await _controller.savePreset();

      // Step 8: Format return value
      final updatedParamValue = await _controller.getParameterValue(
        slotIndex,
        resolvedParameterNumber,
      );
      final updatedValue = updatedParamValue?.value ?? 0;

      final Map<String, dynamic> result = {
        'persisted': true,
        'slot_index': slotIndex,
        'parameter_number': resolvedParameterNumber,
        'parameter_name': parameterName,
        'is_disabled': updatedParamValue?.isDisabled ?? false,
      };

      if (_isEnumParameter(paramInfo)) {
        final enumValues = await _getParameterEnumValues(
          slotIndex,
          resolvedParameterNumber,
        );
        if (enumValues != null) {
          result['is_enum'] = true;
          result['valid_enum_values'] = enumValues;
          result['value'] = _enumIndexToString(enumValues, updatedValue) ?? '';
        }
      } else {
        result['value'] = _scaleForDisplay(updatedValue, paramInfo.powerOfTen);
      }

      // Include mappings if any are enabled
      final updatedMapping = await _controller.getParameterMapping(
        slotIndex,
        resolvedParameterNumber,
      );
      final mappingJson = await _buildMappingJson(updatedMapping);
      if (mappingJson != null && (mappingJson as Map).isNotEmpty) {
        result['mapping'] = mappingJson;
      }

      return jsonEncode(convertToSnakeCaseKeys(result));
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError('Error in editParameter tool: ${e.toString()}'),
        ),
      );
    }
  }

  /// Validates all mapping fields
  Future<Map<String, dynamic>?> _validateMappingFields(
    int slotIndex,
    int parameterNumber,
    Map<String, dynamic> mapping,
  ) async {
    for (final entry in mapping.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key == 'cv' && value is Map<String, dynamic>) {
        final cvInput = value['cv_input'];
        if (cvInput != null) {
          int? resolved;
          resolved = BusMapping.parseBus(
            cvInput,
            deviceIoProfile: _deviceIoProfile,
            includeEs5: false,
          );
          if (resolved == null) {
            return MCPUtils.buildError(
              'CV input must be None or an available device bus, got $cvInput',
            );
          }
          value['cv_input'] = resolved;
        }
      } else if (key == 'midi' && value is Map<String, dynamic>) {
        // Check if is_midi_enabled flag is present when MIDI mapping is specified
        final isMidiEnabled = value['is_midi_enabled'];
        if (isMidiEnabled == null) {
          return MCPUtils.buildError(
            'MIDI mapping requires "is_midi_enabled" field (true/false). Include this field to enable MIDI control.',
          );
        }

        final midiChannel = value['midi_channel'];
        if (midiChannel != null) {
          if (midiChannel is! int || midiChannel < 0 || midiChannel > 15) {
            return MCPUtils.buildError(
              'midi_channel must be 0-15 (where 0=MIDI Channel 1, 15=MIDI Channel 16), got $midiChannel',
            );
          }
        }

        final midiCc = value['midi_cc'];
        if (midiCc != null) {
          if (midiCc is! int || midiCc < 0 || midiCc > 128) {
            return MCPUtils.buildError(
              'midi_cc must be 0-128 (standard Control Change values), got $midiCc',
            );
          }
        }

        final midiType = value['midi_type'];
        if (midiType != null) {
          final validTypes = [
            'cc',
            'note_momentary',
            'note_toggle',
            'cc_14bit_low',
            'cc_14bit_high',
            'pitch_bend',
            'channel_pressure',
          ];
          if (!validTypes.contains(midiType)) {
            return MCPUtils.buildError(
              'MIDI type must be one of: ${validTypes.join(", ")}, got "$midiType"',
            );
          }
          if (_isExpressiveMidiTypeString(midiType) &&
              !_hasExpressiveMidiMapping) {
            return MCPUtils.buildError(
              'MIDI type "$midiType" requires firmware 1.17.0 or newer',
            );
          }
        }
      } else if (key == 'i2c' && value is Map<String, dynamic>) {
        final i2cCc = value['i2c_cc'];
        if (i2cCc != null) {
          if (i2cCc is! int || i2cCc < 0 || i2cCc > 255) {
            return MCPUtils.buildError('i2c CC must be 0-255, got $i2cCc');
          }
        }
      } else if (key == 'performance_page' && value != null) {
        if (value is! int || value < 0 || value > 30) {
          return MCPUtils.buildError(
            'Performance page must be 0-30, got $value',
          );
        }
      }
    }
    return null;
  }

  /// Applies mapping updates while preserving unspecified mappings
  Future<void> _applyMappingUpdates(
    int slotIndex,
    int parameterNumber,
    Map<String, dynamic> desiredMapping,
  ) async {
    await _applyMappingUpdate(slotIndex, parameterNumber, desiredMapping, null);
  }

  /// Builds mapping JSON object from current mapping state
  /// Only includes enabled mappings (disabled mappings omitted per AC #16)
  Future<Map<String, dynamic>?> _buildMappingJson(Mapping? mapping) async {
    if (mapping == null) {
      return null;
    }

    final result = <String, dynamic>{};
    final packed = mapping.packedMappingData;

    // Include CV mapping if enabled
    if (packed.cvInput > 0 || packed.source > 0) {
      result['cv'] = {
        'source': packed.source,
        'cv_input': packed.cvInput,
        'is_unipolar': packed.isUnipolar,
        'is_gate': packed.isGate,
        'volts': packed.volts,
        'delta': packed.delta,
      };
    }

    // Include MIDI mapping if enabled
    if (packed.isMidiEnabled) {
      result['midi'] = {
        'is_midi_enabled': packed.isMidiEnabled,
        'midi_channel': packed.midiChannel,
        'midi_type': _midiTypeValueToString(packed.midiMappingType.value),
        'midi_cc': packed.midiCC,
        'is_midi_symmetric': packed.isMidiSymmetric,
        'is_midi_relative': packed.isMidiRelative,
        'midi_min': packed.midiMin,
        'midi_max': packed.midiMax,
      };
    }

    // Include i2c mapping if enabled
    if (packed.isI2cEnabled) {
      result['i2c'] = {
        'is_i2c_enabled': packed.isI2cEnabled,
        'i2c_cc': packed.i2cCC,
        'is_i2c_symmetric': packed.isI2cSymmetric,
        'i2c_min': packed.i2cMin,
        'i2c_max': packed.i2cMax,
      };
    }

    // Include performance page if assigned
    if (packed.perfPageIndex > 0) {
      result['performance_page'] = packed.perfPageIndex;
    }

    return result.isNotEmpty ? result : null;
  }

  /// Validates the diff before applying changes
  Future<Map<String, dynamic>?> _validateDiff(
    Map<int, Algorithm?> currentSlots,
    Map<int, DesiredSlot> desiredSlots,
    String desiredName,
  ) async {
    // Validate preset name
    if (desiredName.isEmpty) {
      return MCPUtils.buildError('Preset name cannot be empty');
    }

    final metadataService = AlgorithmMetadataService();
    final allAlgorithms = _getAllKnownAlgorithms();

    // Validate algorithms in desired slots
    for (final entry in desiredSlots.entries) {
      final slotIndex = entry.key;
      final desiredSlot = entry.value;

      if (slotIndex < 0 || slotIndex >= maxSlots) {
        return MCPUtils.buildError(
          'Slot index $slotIndex is out of valid range (0-${maxSlots - 1})',
        );
      }

      // Resolve algorithm
      final resolution = AlgorithmResolver.resolveAlgorithm(
        guid: desiredSlot.guid,
        algorithmName: desiredSlot.name,
        allAlgorithms: allAlgorithms,
      );

      if (!resolution.isSuccess) {
        return resolution.error;
      }

      final resolvedGuid = resolution.resolvedGuid!;

      // Validate algorithm exists in metadata
      final algorithmMetadata = metadataService.getAlgorithmByGuid(
        resolvedGuid,
      );
      if (algorithmMetadata == null) {
        return MCPUtils.buildError(
          'Algorithm with GUID "$resolvedGuid" not found in metadata',
        );
      }

      // Validate parameters if provided
      if (desiredSlot.parameters != null &&
          desiredSlot.parameters!.isNotEmpty) {
        for (int i = 0; i < desiredSlot.parameters!.length; i++) {
          final paramData = desiredSlot.parameters![i];
          if (paramData is! Map<String, dynamic>) {
            return MCPUtils.buildError(
              'Parameter at index $i in slot $slotIndex must be an object',
            );
          }

          final int? paramNumber = paramData['parameter_number'] as int?;
          final dynamic paramValue = paramData['value'];
          final Map<String, dynamic>? mappingData =
              paramData['mapping'] as Map<String, dynamic>?;

          if (paramNumber == null) {
            return MCPUtils.buildError(
              'Parameter in slot $slotIndex must have parameter_number',
            );
          }

          // Validate parameter number and bounds
          final currentAlgo = currentSlots[slotIndex];
          if (currentAlgo != null && currentAlgo.guid == resolvedGuid) {
            // Same algorithm — validate using hardware parameter numbers
            final parameterInfos = await _controller.getParametersForSlot(
              slotIndex,
            );
            final paramIdx = parameterInfos.indexWhere(
              (p) => p.parameterNumber == paramNumber,
            );
            if (paramIdx == -1) {
              final available = parameterInfos
                  .map((p) => p.parameterNumber)
                  .toList();
              return MCPUtils.buildError(
                'Parameter number $paramNumber not found. Available parameter numbers: $available',
              );
            }
            if (paramValue != null && paramValue is num) {
              final pInfo = parameterInfos[paramIdx];
              final rawValue = MCPUtils.scaleToRaw(
                paramValue,
                pInfo.powerOfTen,
              );
              if (rawValue < pInfo.min || rawValue > pInfo.max) {
                final displayMin = MCPUtils.scaleForDisplay(
                  pInfo.min,
                  pInfo.powerOfTen,
                );
                final displayMax = MCPUtils.scaleForDisplay(
                  pInfo.max,
                  pInfo.powerOfTen,
                );
                return MCPUtils.buildError(
                  'Parameter $paramNumber value $paramValue exceeds bounds ($displayMin-$displayMax)',
                );
              }
            }
          } else {
            // New algorithm — validate against metadata (best-effort length check)
            final algorithmParameters = metadataService.getExpandedParameters(
              resolvedGuid,
            );
            if (paramNumber >= algorithmParameters.length) {
              return MCPUtils.buildError(
                'Parameter number $paramNumber exceeds algorithm parameter count',
                details: {
                  'algorithm': algorithmMetadata.name,
                  'valid_range': '0-${algorithmParameters.length - 1}',
                  'attempted': paramNumber,
                  'total_parameters': algorithmParameters.length,
                },
              );
            }
            final paramInfo = algorithmParameters[paramNumber];
            if (paramValue != null && paramValue is num) {
              if (paramValue < paramInfo.min || paramValue > paramInfo.max) {
                return MCPUtils.buildError(
                  'Parameter $paramNumber value $paramValue exceeds bounds (${paramInfo.min}-${paramInfo.max})',
                );
              }
            }
          }

          // Validate mapping if provided
          if (mappingData != null) {
            final mappingError = _validateMapping(
              mappingData,
              slotIndex,
              paramNumber,
            );
            if (mappingError != null) {
              return mappingError;
            }
          }
        }
      }
    }

    return null;
  }

  /// Validates mapping structure
  Map<String, dynamic>? _validateMapping(
    Map<String, dynamic> mappingData,
    int slotIndex,
    int paramNumber,
  ) {
    // Validate MIDI mapping if present
    if (mappingData.containsKey('midi')) {
      final midi = mappingData['midi'] as Map<String, dynamic>?;
      if (midi != null) {
        if (!midi.containsKey('is_midi_enabled')) {
          return MCPUtils.buildError(
            'MIDI mapping requires "is_midi_enabled" field (true/false). Include this field to enable MIDI control.',
          );
        }
        if (midi.containsKey('midi_channel')) {
          final channel = midi['midi_channel'] as int?;
          if (channel != null && (channel < 0 || channel > 15)) {
            return MCPUtils.buildError(
              'MIDI channel must be 0-15, got $channel at slot $slotIndex parameter $paramNumber',
            );
          }
        }
        if (midi.containsKey('midi_cc')) {
          final cc = midi['midi_cc'] as int?;
          if (cc != null && (cc < 0 || cc > 128)) {
            return MCPUtils.buildError(
              'MIDI CC must be 0-128, got $cc at slot $slotIndex parameter $paramNumber',
            );
          }
        }
        final midiType = midi['midi_type'] as String?;
        if (midiType != null) {
          final validTypes = [
            'cc',
            'note_momentary',
            'note_toggle',
            'cc_14bit_low',
            'cc_14bit_high',
            'pitch_bend',
            'channel_pressure',
          ];
          if (!validTypes.contains(midiType)) {
            return MCPUtils.buildError(
              'MIDI type must be one of: ${validTypes.join(", ")}, got "$midiType"',
            );
          }
          if (_isExpressiveMidiTypeString(midiType) &&
              !_hasExpressiveMidiMapping) {
            return MCPUtils.buildError(
              'MIDI type "$midiType" requires firmware 1.17.0 or newer',
            );
          }
        }
      }
    }

    // Validate CV mapping if present
    if (mappingData.containsKey('cv')) {
      final cv = mappingData['cv'] as Map<String, dynamic>?;
      if (cv != null) {
        if (cv.containsKey('cv_input')) {
          final input = cv['cv_input'] as int?;
          if (input != null && (input < 0 || input > 12)) {
            return MCPUtils.buildError(
              'CV input must be 0-12, got $input at slot $slotIndex parameter $paramNumber',
            );
          }
        }
      }
    }

    // Validate i2c mapping if present
    if (mappingData.containsKey('i2c')) {
      final i2c = mappingData['i2c'] as Map<String, dynamic>?;
      if (i2c != null) {
        if (i2c.containsKey('i2c_cc')) {
          final cc = i2c['i2c_cc'] as int?;
          if (cc != null && (cc < 0 || cc > 255)) {
            return MCPUtils.buildError(
              'i2c CC must be 0-255, got $cc at slot $slotIndex parameter $paramNumber',
            );
          }
        }
      }
    }

    // Validate performance_page
    if (mappingData.containsKey('performance_page')) {
      final perfPage = mappingData['performance_page'] as int?;
      if (perfPage != null && (perfPage < 0 || perfPage > 30)) {
        return MCPUtils.buildError(
          'Performance page must be 0-30, got $perfPage at slot $slotIndex parameter $paramNumber',
        );
      }
    }

    return null;
  }

  /// Applies the diff to the device
  /// Implements atomic change handling: validates all changes before applying any
  Future<Map<String, dynamic>?> _applyDiff(
    Map<int, Algorithm?> currentSlots,
    Map<int, DesiredSlot> desiredSlots,
    String desiredName,
    String currentPresetName,
  ) async {
    try {
      // Pre-apply validation: get all current mappings (for preservation during updates)
      final Map<int, Map<int, Mapping?>> currentMappings = {};
      final metadataService = AlgorithmMetadataService();

      for (final entry in currentSlots.entries) {
        final slotIndex = entry.key;
        final algorithm = entry.value;
        if (algorithm != null) {
          final mappings = <int, Mapping?>{};
          final paramList = await _controller.getParametersForSlot(slotIndex);
          for (int i = 0; i < paramList.length; i++) {
            final paramNumber = paramList[i].parameterNumber;
            final mapping = await _controller.getParameterMapping(
              slotIndex,
              paramNumber,
            );
            mappings[paramNumber] = mapping;
          }
          currentMappings[slotIndex] = mappings;
        }
      }

      // Step 1: Clear slots that should be empty in desired state but aren't in current
      for (int i = 0; i < maxSlots; i++) {
        if (!desiredSlots.containsKey(i) && currentSlots[i] != null) {
          await _controller.clearSlot(i);
        }
      }

      // Step 2: Add or update algorithms in desired slots
      final allAlgorithms = _getAllKnownAlgorithms();

      for (final entry in desiredSlots.entries) {
        final slotIndex = entry.key;
        final desiredSlot = entry.value;

        // Resolve algorithm
        final resolution = AlgorithmResolver.resolveAlgorithm(
          guid: desiredSlot.guid,
          algorithmName: desiredSlot.name,
          allAlgorithms: allAlgorithms,
        );

        if (!resolution.isSuccess) {
          return resolution.error;
        }

        final resolvedGuid = resolution.resolvedGuid!;
        final algorithmMetadata = metadataService.getAlgorithmByGuid(
          resolvedGuid,
        );

        // Check if we need to add this algorithm
        final currentAlgo = currentSlots[slotIndex];
        if (currentAlgo == null || currentAlgo.guid != resolvedGuid) {
          // Clear if different algorithm is there
          if (currentAlgo != null) {
            await _controller.clearSlot(slotIndex);
          }

          // Add new algorithm
          final algorithm = Algorithm(
            algorithmIndex: -1,
            guid: resolvedGuid,
            name: algorithmMetadata!.name,
          );
          await _addAlgorithmAndVerify(algorithm);
        }

        // Step 3: Update parameters if provided
        if (desiredSlot.parameters != null &&
            desiredSlot.parameters!.isNotEmpty) {
          for (final paramData in desiredSlot.parameters!) {
            if (paramData is Map<String, dynamic>) {
              final int? paramNumber = paramData['parameter_number'] as int?;
              final dynamic paramValue = paramData['value'];
              final Map<String, dynamic>? mappingData =
                  paramData['mapping'] as Map<String, dynamic>?;

              if (paramNumber != null && paramValue != null) {
                try {
                  final paramList = await _controller.getParametersForSlot(
                    slotIndex,
                  );
                  final pInfo = paramList.firstWhere(
                    (p) => p.parameterNumber == paramNumber,
                  );
                  final rawValue = MCPUtils.scaleToRaw(
                    paramValue,
                    pInfo.powerOfTen,
                  );
                  await _controller.updateParameterValue(
                    slotIndex,
                    paramNumber,
                    rawValue,
                  );
                } catch (e) {
                  return MCPUtils.buildError(
                    'Failed to update parameter $paramNumber in slot $slotIndex: ${e.toString()}',
                  );
                }
              }

              // Step 4: Apply mapping updates (AC #6-8, #10)
              if (mappingData != null && paramNumber != null) {
                try {
                  await _applyMappingUpdate(
                    slotIndex,
                    paramNumber,
                    mappingData,
                    currentMappings[slotIndex]?[paramNumber],
                  );
                } catch (e) {
                  return MCPUtils.buildError(
                    'Failed to update mapping for parameter $paramNumber in slot $slotIndex: ${e.toString()}',
                  );
                }
              }
              // If mapping is omitted, preserve existing mapping (AC #6)
            }
          }
        }
      }

      // Step 5: Handle algorithm reordering (AC #10)
      final reorderError = await _applyAlgorithmReordering(
        currentSlots,
        desiredSlots,
        metadataService,
        allAlgorithms,
      );
      if (reorderError != null) {
        return reorderError;
      }

      // Step 6: Update preset name if different
      if (desiredName != currentPresetName) {
        try {
          await _controller.setPresetName(desiredName);
        } catch (e) {
          return MCPUtils.buildError(
            'Failed to set preset name: ${e.toString()}',
          );
        }
      }

      return null; // No error
    } catch (e) {
      return MCPUtils.buildError('Failed to apply changes: ${e.toString()}');
    }
  }

  /// Applies mapping updates to a parameter, preserving omitted fields
  /// Handles partial mapping updates as required by AC #8
  Future<void> _applyMappingUpdate(
    int slotIndex,
    int paramNumber,
    Map<String, dynamic> desiredMapping,
    Mapping? currentMapping,
  ) async {
    if (desiredMapping.isEmpty) {
      return;
    }

    // Get the current mapping to use as base for preservation
    final Mapping? existing =
        currentMapping ??
        await _controller.getParameterMapping(slotIndex, paramNumber);

    if (existing == null) {
      return; // No current mapping to update
    }

    // Build updated mapping by preserving omitted fields
    var updatedPacked = existing.packedMappingData;

    // Apply CV mapping updates if provided
    if (desiredMapping.containsKey('cv')) {
      final cvData = desiredMapping['cv'] as Map<String, dynamic>?;
      if (cvData != null) {
        updatedPacked = updatedPacked.copyWith(
          source: cvData['source'] as int? ?? updatedPacked.source,
          cvInput: cvData['cv_input'] as int? ?? updatedPacked.cvInput,
          isUnipolar:
              cvData['is_unipolar'] as bool? ?? updatedPacked.isUnipolar,
          isGate: cvData['is_gate'] as bool? ?? updatedPacked.isGate,
          volts: cvData['volts'] as int? ?? updatedPacked.volts,
          delta: cvData['delta'] as int? ?? updatedPacked.delta,
        );
      }
    }

    // Apply MIDI mapping updates if provided
    if (desiredMapping.containsKey('midi')) {
      final midiData = desiredMapping['midi'] as Map<String, dynamic>?;
      if (midiData != null) {
        updatedPacked = updatedPacked.copyWith(
          midiChannel:
              midiData['midi_channel'] as int? ?? updatedPacked.midiChannel,
          midiCC: midiData['midi_cc'] as int? ?? updatedPacked.midiCC,
          isMidiEnabled:
              midiData['is_midi_enabled'] as bool? ??
              updatedPacked.isMidiEnabled,
          isMidiSymmetric:
              midiData['is_midi_symmetric'] as bool? ??
              updatedPacked.isMidiSymmetric,
          isMidiRelative:
              midiData['is_midi_relative'] as bool? ??
              updatedPacked.isMidiRelative,
          midiMin: midiData['midi_min'] as int? ?? updatedPacked.midiMin,
          midiMax: midiData['midi_max'] as int? ?? updatedPacked.midiMax,
        );

        if (midiData.containsKey('midi_type')) {
          final midiType = midiData['midi_type'] as String?;
          if (midiType != null) {
            final mappingTypeValue = _midiTypeStringToValue(midiType);
            if (mappingTypeValue >= 0) {
              updatedPacked = updatedPacked.copyWith(
                midiMappingType: MidiMappingType.values[mappingTypeValue],
                midiCC: _isExpressiveMidiTypeString(midiType)
                    ? 0
                    : updatedPacked.midiCC,
                isMidiRelative: _isExpressiveMidiTypeString(midiType)
                    ? false
                    : updatedPacked.isMidiRelative,
                version: _isExpressiveMidiTypeString(midiType)
                    ? 7
                    : updatedPacked.version,
              );
            }
          }
        }
      }
    }

    // Apply i2c mapping updates if provided
    if (desiredMapping.containsKey('i2c')) {
      final i2cData = desiredMapping['i2c'] as Map<String, dynamic>?;
      if (i2cData != null) {
        updatedPacked = updatedPacked.copyWith(
          i2cCC: i2cData['i2c_cc'] as int? ?? updatedPacked.i2cCC,
          isI2cEnabled:
              i2cData['is_i2c_enabled'] as bool? ?? updatedPacked.isI2cEnabled,
          isI2cSymmetric:
              i2cData['is_i2c_symmetric'] as bool? ??
              updatedPacked.isI2cSymmetric,
          i2cMin: i2cData['i2c_min'] as int? ?? updatedPacked.i2cMin,
          i2cMax: i2cData['i2c_max'] as int? ?? updatedPacked.i2cMax,
        );
      }
    }

    // Apply performance page update if provided
    if (desiredMapping.containsKey('performance_page')) {
      final perfPage = desiredMapping['performance_page'] as int?;
      if (perfPage != null) {
        updatedPacked = updatedPacked.copyWith(perfPageIndex: perfPage);
      }
    }

    // Save the updated mapping via DistingCubit
    await _controller.saveMapping(
      existing.algorithmIndex,
      existing.parameterNumber,
      updatedPacked,
    );
  }

  /// Converts MIDI type string (snake_case) to enum value
  int _midiTypeStringToValue(String typeString) {
    switch (typeString) {
      case 'cc':
        return 0;
      case 'note_momentary':
        return 1;
      case 'note_toggle':
        return 2;
      case 'cc_14bit_low':
        return 3;
      case 'cc_14bit_high':
        return 4;
      case 'pitch_bend':
        return 5;
      case 'channel_pressure':
        return 6;
      default:
        return -1; // Invalid type
    }
  }

  bool _isExpressiveMidiTypeString(String typeString) {
    return typeString == 'pitch_bend' || typeString == 'channel_pressure';
  }

  /// Converts MIDI type enum value to string (snake_case)
  String _midiTypeValueToString(int typeValue) {
    switch (typeValue) {
      case 0:
        return 'cc';
      case 1:
        return 'note_momentary';
      case 2:
        return 'note_toggle';
      case 3:
        return 'cc_14bit_low';
      case 4:
        return 'cc_14bit_high';
      case 5:
        return 'pitch_bend';
      case 6:
        return 'channel_pressure';
      default:
        return 'cc'; // Default fallback
    }
  }

  /// Handles algorithm reordering to match desired slot positions (AC #10)
  /// Detects when algorithms need to move and uses moveAlgorithmUp/Down
  Future<Map<String, dynamic>?> _applyAlgorithmReordering(
    Map<int, Algorithm?> currentSlots,
    Map<int, DesiredSlot> desiredSlots,
    AlgorithmMetadataService metadataService,
    List<dynamic> allAlgorithms,
  ) async {
    // Build a map of current algorithm GUIDs to their positions
    final Map<String, List<int>> currentPositions = {};
    for (final entry in currentSlots.entries) {
      if (entry.value != null) {
        currentPositions
            .putIfAbsent(entry.value!.guid, () => [])
            .add(entry.key);
      }
    }

    // Build a map of desired algorithm GUIDs to their positions
    final Map<String, List<int>> desiredPositions = {};
    final Map<String, String> guidMap = {}; // Maps name->guid for resolution

    for (final entry in desiredSlots.entries) {
      final desiredSlot = entry.value;

      // Resolve algorithm GUID
      final resolution = AlgorithmResolver.resolveAlgorithm(
        guid: desiredSlot.guid,
        algorithmName: desiredSlot.name,
        allAlgorithms: allAlgorithms,
      );

      if (!resolution.isSuccess) {
        return resolution.error;
      }

      final resolvedGuid = resolution.resolvedGuid!;
      desiredPositions.putIfAbsent(resolvedGuid, () => []).add(entry.key);
      guidMap[desiredSlot.name ?? ''] = resolvedGuid;
    }

    // For now, implement simple reordering: move algorithms one by one
    // This is a basic implementation that handles slot position changes
    // A more optimized version could minimize the number of moves
    for (final entry in desiredPositions.entries) {
      final guid = entry.key;
      final desiredPos = entry.value;

      if (desiredPos.isNotEmpty) {
        final currentPos = currentPositions[guid];
        if (currentPos != null && currentPos.isNotEmpty) {
          var currentSlot = currentPos[0]; // Get first occurrence
          final targetSlot = desiredPos[0];

          // Move algorithm if position differs
          if (currentSlot != targetSlot) {
            // Calculate move direction and distance
            while (currentSlot < targetSlot) {
              await _controller.moveAlgorithmDown(currentSlot);
              currentSlot++;
            }
            while (currentSlot > targetSlot) {
              await _controller.moveAlgorithmUp(currentSlot);
              currentSlot--;
            }
          }
        }
      }
    }

    return null; // No error
  }

  /// MCP Tool: Search for parameters by name
  /// Parameters:
  ///   - query (string, required): Parameter name to search for
  ///   - scope (string, required): "preset" or "slot"
  ///   - slot_index (int, optional): Required if scope="slot"
  ///   - partial_match (boolean, optional, default false): If true, find parameters containing the query
  /// Returns:
  ///   A JSON string with search results
  Future<String> searchParameters(Map<String, dynamic> params) async {
    final String? query = params['query'] as String?;
    final String? scope = params['scope'] as String?;
    final int? slotIndex = params['slot_index'] as int?;
    final bool partialMatch = params['partial_match'] as bool? ?? false;

    // Validate parameters
    if (query == null || query.trim().isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Parameter "query" is required and cannot be empty.',
          ),
        ),
      );
    }

    if (scope == null || scope.isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Parameter "scope" is required. Must be "preset" or "slot".',
          ),
        ),
      );
    }

    if (scope == 'preset') {
      return searchParametersInPreset(query.trim(), partialMatch);
    } else if (scope == 'slot') {
      if (slotIndex == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError(
              'Parameter "slot_index" is required when scope="slot".',
            ),
          ),
        );
      }
      return searchParametersInSlot(slotIndex, query.trim(), partialMatch);
    } else {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            'Invalid scope "$scope". Must be "preset" or "slot".',
          ),
        ),
      );
    }
  }

  /// Helper method to find matching parameters by name
  /// Returns all parameters where the name matches (exact or partial)
  List<ParameterInfo> _findMatchingParameters(
    List<ParameterInfo> parameters,
    String searchQuery,
    bool partialMatch,
  ) {
    final normalizedQuery = _normalizeParameterSearchText(searchQuery);
    return parameters.where((p) {
      final normalizedName = _normalizeParameterSearchText(p.name);
      if (partialMatch) {
        return normalizedName.contains(normalizedQuery);
      } else {
        return normalizedName == normalizedQuery;
      }
    }).toList();
  }

  String _normalizeParameterSearchText(String value) {
    final withStandardSpaces = value.replaceAll('\u00A0', ' ');
    return withStandardSpaces
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  /// MCP Tool: Search for parameters in the entire preset
  /// Parameters:
  ///   - query (string, required): Parameter name to search for
  ///   - partial_match (boolean, optional, default false): If true, find parameters containing the query
  /// Returns:
  ///   A JSON string with results showing which slots have matching parameters
  Future<String> searchParametersInPreset(
    String query,
    bool partialMatch,
  ) async {
    try {
      final normalizedQuery = query.trim();
      if (normalizedQuery.isEmpty) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Search query cannot be empty.'),
          ),
        );
      }

      final Map<int, Algorithm?> slotAlgorithms = await _controller
          .getAllSlots();

      List<Map<String, dynamic>> results = [];
      int totalMatches = 0;

      for (int i = 0; i < maxSlots; i++) {
        final algorithm = slotAlgorithms[i];
        if (algorithm != null) {
          List<ParameterInfo> parameterInfos = await _controller
              .getParametersForSlot(i);

          // Force refresh slot if parameters haven't loaded yet
          if (parameterInfos.isEmpty) {
            try {
              await _controller.refreshSlot(i);
              parameterInfos = await _controller.getParametersForSlot(i);
            } catch (_) {
              // Best effort
            }
          }

          final matchingParams = _findMatchingParameters(
            parameterInfos,
            normalizedQuery,
            partialMatch,
          );

          if (matchingParams.isNotEmpty) {
            totalMatches += matchingParams.length;

            List<Map<String, dynamic>> matches = [];
            for (final param in matchingParams) {
              final ParameterValue? paramValue = await _controller
                  .getParameterValue(i, param.parameterNumber);
              final matchData = <String, dynamic>{
                'parameter_number': param.parameterNumber,
                'parameter_name': param.name,
                'is_disabled': paramValue?.isDisabled ?? false,
              };
              if (_isEnumParameter(param)) {
                final enumValues = await _getParameterEnumValues(
                  i,
                  param.parameterNumber,
                );
                if (enumValues != null) {
                  matchData['is_enum'] = true;
                  matchData['valid_enum_values'] = enumValues;
                  if (paramValue != null) {
                    matchData['value'] =
                        _enumIndexToString(enumValues, paramValue.value) ?? '';
                  }
                }
              } else {
                matchData['value'] = paramValue != null
                    ? _scaleForDisplay(paramValue.value, param.powerOfTen)
                    : null;
                matchData['min'] = _scaleForDisplay(
                  param.min,
                  param.powerOfTen,
                );
                matchData['max'] = _scaleForDisplay(
                  param.max,
                  param.powerOfTen,
                );
              }
              matches.add(matchData);
            }

            results.add({
              'slot_index': i,
              'algorithm_name': algorithm.name,
              'algorithm_guid': algorithm.guid,
              'matches': matches,
            });
          }
        }
      }

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Parameter search completed',
            data: {
              'scope': 'preset',
              'query': normalizedQuery,
              'partial_match': partialMatch,
              'total_matches': totalMatches,
              'results': results,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }

  /// MCP Tool: Search for parameters within a specific slot
  /// Parameters:
  ///   - slot_index (int, required): Which slot to search in
  ///   - query (string, required): Parameter name to search for
  ///   - partial_match (boolean, optional, default false): If true, find parameters containing the query
  /// Returns:
  ///   A JSON string with all matching parameters in the slot
  Future<String> searchParametersInSlot(
    int slotIndex,
    String query,
    bool partialMatch,
  ) async {
    try {
      final normalizedQuery = query.trim();
      final slotError = MCPUtils.validateSlotIndex(slotIndex);
      if (slotError != null) {
        return jsonEncode(convertToSnakeCaseKeys(slotError));
      }

      if (normalizedQuery.isEmpty) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Search query cannot be empty.'),
          ),
        );
      }

      final algorithm = await _controller.getAlgorithmInSlot(slotIndex);
      if (algorithm == null) {
        return jsonEncode(
          convertToSnakeCaseKeys(
            MCPUtils.buildError('Slot $slotIndex is empty.'),
          ),
        );
      }

      final List<ParameterInfo> parameterInfos = await _controller
          .getParametersForSlot(slotIndex);

      final matchingParams = _findMatchingParameters(
        parameterInfos,
        normalizedQuery,
        partialMatch,
      );

      List<Map<String, dynamic>> matches = [];
      for (final param in matchingParams) {
        final ParameterValue? paramValue = await _controller.getParameterValue(
          slotIndex,
          param.parameterNumber,
        );
        final matchData = <String, dynamic>{
          'parameter_number': param.parameterNumber,
          'parameter_name': param.name,
          'is_disabled': paramValue?.isDisabled ?? false,
        };
        if (_isEnumParameter(param)) {
          final enumValues = await _getParameterEnumValues(
            slotIndex,
            param.parameterNumber,
          );
          if (enumValues != null) {
            matchData['is_enum'] = true;
            matchData['valid_enum_values'] = enumValues;
            if (paramValue != null) {
              matchData['value'] =
                  _enumIndexToString(enumValues, paramValue.value) ?? '';
            }
          }
        } else {
          matchData['value'] = paramValue != null
              ? _scaleForDisplay(paramValue.value, param.powerOfTen)
              : null;
          matchData['min'] = _scaleForDisplay(param.min, param.powerOfTen);
          matchData['max'] = _scaleForDisplay(param.max, param.powerOfTen);
        }
        matches.add(matchData);
      }

      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildSuccess(
            'Parameter search in slot completed',
            data: {
              'scope': 'slot',
              'slot_index': slotIndex,
              'algorithm_name': algorithm.name,
              'algorithm_guid': algorithm.guid,
              'query': normalizedQuery,
              'partial_match': partialMatch,
              'total_matches': matchingParams.length,
              'matches': matches,
            },
          ),
        ),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys(MCPUtils.buildError(e.toString())),
      );
    }
  }
}

/// Helper class to represent a desired slot state
class DesiredSlot {
  final String? guid;
  final String? name;
  final List<dynamic>? parameters;
  final Map<String, dynamic>? mapping;

  DesiredSlot({this.guid, this.name, this.parameters, this.mapping});
}

class _TemplateResolution {
  final FullPresetDetails? details;
  final Map<String, dynamic>? error;

  const _TemplateResolution.details(this.details) : error = null;
  const _TemplateResolution.error(this.error) : details = null;
}

class _PresetResolution {
  final PresetEntry? preset;
  final Map<String, dynamic>? error;

  const _PresetResolution.preset(this.preset) : error = null;
  const _PresetResolution.error(this.error) : preset = null;
}

class _SlotIndicesResolution {
  final List<int>? slotIndices;
  final Map<String, dynamic>? error;

  const _SlotIndicesResolution.slotIndices(this.slotIndices) : error = null;
  const _SlotIndicesResolution.error(this.error) : slotIndices = null;
}
