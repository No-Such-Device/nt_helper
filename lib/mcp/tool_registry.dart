import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';
import 'package:nt_helper/chat/models/allowed_file_root.dart';
import 'package:nt_helper/chat/services/local_file_tools.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/chat/services/memory_tools.dart';
import 'package:nt_helper/chat/utils/image_result_detector.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/mcp/mcp_constants.dart';
import 'package:nt_helper/mcp/tool_reference_store.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:nt_helper/services/disting_controller_impl.dart';

/// A single tool entry in the shared registry.
class ToolRegistryEntry {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<String> Function(Map<String, dynamic> args) handler;
  final Duration timeout;

  const ToolRegistryEntry({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.timeout = const Duration(seconds: 10),
  });
}

/// Shared registry of tool definitions consumed by both the MCP server
/// and the in-app chat's ToolBridgeService.
class ToolRegistry {
  static const _slotMinimum = 0;
  static const _slotMaximum = MCPConstants.maxSlotIndex;
  static const _slotRangeDescription = '0-$_slotMaximum';

  static const _memoryToolNames = {
    'memory_read',
    'memory_write',
    'memory_append_daily',
    'memory_read_daily',
  };
  static const _chatOnlyToolNames = {
    ..._memoryToolNames,
    ...localFileToolNames,
  };

  final List<ToolRegistryEntry> _entries = [];
  final ToolReferenceStore _referenceStore;
  late final DistingController _controller;
  late final MCPAlgorithmTools _algoTools;
  late final DistingTools _distingTools;

  ToolRegistry(
    DistingCubit distingCubit, {
    MemoryService? memoryService,
    List<ToolRegistryEntry> extraEntries = const [],
    ToolReferenceStore? referenceStore,
  }) : _referenceStore = referenceStore ?? ToolReferenceStore() {
    _controller = DistingControllerImpl(distingCubit);
    _algoTools = MCPAlgorithmTools(_controller, distingCubit);
    _distingTools = DistingTools(_controller, distingCubit);
    _registerAll();
    _entries.addAll(extraEntries);
    if (memoryService != null) {
      registerMemoryTools(_entries, memoryService);
      registerLocalFileTools(_entries, actor: FileRootActor.chat);
    }
  }

  List<ToolRegistryEntry> get entries => List.unmodifiable(_entries);

  ToolRegistryEntry? findByName(String name) {
    for (final entry in _entries) {
      if (entry.name == name) return entry;
    }
    return null;
  }

  Future<String> executeTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final entry = findByName(name);
    if (entry == null) {
      return jsonEncode({'success': false, 'error': 'Unknown tool: $name'});
    }
    return _executeEntry(entry, arguments);
  }

  String storeReferenceIfLarge({
    required String toolName,
    required String result,
  }) {
    return _referenceStore.storeIfLarge(toolName: toolName, result: result);
  }

  Future<String> _executeEntry(
    ToolRegistryEntry entry,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final resultJson = await entry
          .handler(arguments)
          .timeout(
            entry.timeout,
            onTimeout: () => jsonEncode({
              'success': false,
              'error':
                  'Tool execution timed out after ${entry.timeout.inSeconds} seconds',
            }),
          );
      return _referenceStore.storeIfLarge(
        toolName: entry.name,
        result: resultJson,
      );
    } catch (e) {
      return jsonEncode({
        'success': false,
        'error': 'Tool execution failed: ${e.toString()}',
      });
    }
  }

  /// Apply all registered tools to an MCP server instance.
  /// Memory tools are excluded — they are for the in-app chat only.
  void applyToMcpServer(McpServer server) {
    for (final entry in _entries) {
      if (_chatOnlyToolNames.contains(entry.name)) continue;
      _registerMcpEntry(server, entry);
    }

    final mcpFileEntries = <ToolRegistryEntry>[];
    registerLocalFileTools(mcpFileEntries, actor: FileRootActor.mcp);
    for (final entry in mcpFileEntries) {
      _registerMcpEntry(server, entry);
    }
  }

  void _registerMcpEntry(McpServer server, ToolRegistryEntry entry) {
    server.registerTool(
      entry.name,
      description: entry.description,
      inputSchema: ToolInputSchema.fromJson(
        _deepCastMap({
          'type': 'object',
          'properties': entry.inputSchema['properties'] ?? {},
          if (entry.inputSchema['required'] != null)
            'required': entry.inputSchema['required'],
        }),
      ),
      callback: (args, extra) async {
        final resultJson = await _executeEntry(entry, args);
        final image = tryParseImageResult(resultJson);
        if (image != null) {
          return CallToolResult.fromContent([
            ImageContent(data: image.data, mimeType: image.mimeType),
          ]);
        }
        return CallToolResult.fromContent([TextContent(text: resultJson)]);
      },
    );
  }

  /// Recursively cast Map literals to `Map<String, dynamic>` for mcp_dart.
  static Map<String, dynamic> _deepCastMap(Map map) {
    return map.map((key, value) {
      if (value is Map) {
        return MapEntry(key.toString(), _deepCastMap(value));
      } else if (value is List) {
        return MapEntry(
          key.toString(),
          value.map((e) => e is Map ? _deepCastMap(e) : e).toList(),
        );
      }
      return MapEntry(key.toString(), value);
    });
  }

  void _registerAll() {
    _registerReferenceTools();
    _registerSearchTools();
    _registerShowTools();
    _registerEditTools();
    _registerPresetTools();
  }

  void _registerReferenceTools() {
    _entries.add(
      ToolRegistryEntry(
        name: ToolReferenceStore.readToolName,
        description:
            'Read a page from a large tool result reference returned by any tool.',
        inputSchema: {
          'properties': {
            'reference_id': {
              'type': 'string',
              'description': 'Reference ID returned by a previous tool result.',
            },
            'offset': {
              'type': 'integer',
              'minimum': 0,
              'description':
                  'Character offset to start reading from. Default: 0.',
            },
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': ToolReferenceStore.maxReadLimitChars,
              'description':
                  'Maximum characters to return. Default: 8000, max: 16000.',
            },
          },
          'required': ['reference_id'],
        },
        handler: _referenceStore.readReference,
        timeout: const Duration(seconds: 5),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: ToolReferenceStore.searchToolName,
        description:
            'Search within a large tool result reference returned by any tool.',
        inputSchema: {
          'properties': {
            'reference_id': {
              'type': 'string',
              'description': 'Reference ID returned by a previous tool result.',
            },
            'query': {
              'type': 'string',
              'description': 'Case-insensitive text to search for.',
            },
            'start_offset': {
              'type': 'integer',
              'minimum': 0,
              'description':
                  'Character offset to begin searching from. Default: 0.',
            },
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': ToolReferenceStore.maxSearchLimit,
              'description': 'Maximum matches to return. Default: 20, max: 50.',
            },
            'context_chars': {
              'type': 'integer',
              'minimum': 0,
              'maximum': ToolReferenceStore.maxSearchContextChars,
              'description':
                  'Context characters around each match. Default: 120, max: 500.',
            },
          },
          'required': ['reference_id', 'query'],
        },
        handler: _referenceStore.searchReference,
        timeout: const Duration(seconds: 5),
      ),
    );
  }

  void _registerSearchTools() {
    _entries.add(
      ToolRegistryEntry(
        name: 'search_algorithms',
        description:
            'Search for algorithms by name/category. Uses fuzzy matching (70% threshold). Returns up to 10 results sorted by relevance.',
        inputSchema: {
          'properties': {
            'query': {
              'type': 'string',
              'description':
                  'Search query: algorithm name, partial name, or category.',
            },
          },
          'required': ['query'],
        },
        handler: (args) => _algoTools.searchAlgorithms(args),
        timeout: const Duration(seconds: 5),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'algorithm_info',
        description:
            'Show documentation-style metadata for an algorithm, matching the parameter editor Help screen: description, categories, ports, specifications, parameters, and features. Requires either guid or name.',
        inputSchema: {
          'properties': {
            'guid': {
              'type': 'string',
              'description': 'Algorithm GUID, for example "clck".',
            },
            'name': {
              'type': 'string',
              'description': 'Algorithm name. Used if guid is omitted.',
            },
            'expand_features': {
              'type': 'boolean',
              'description':
                  'If true, expand feature-provided parameters into the parameter list. Default: false.',
            },
          },
        },
        handler: (args) => _algoTools.algorithmInfo(args),
        timeout: const Duration(seconds: 5),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'search_parameters',
        description:
            'Search for parameters by name within the current preset or a specific slot. '
            'Prefer this over browsing show_slot pages when you know all or part of the name.',
        inputSchema: {
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Parameter name to search for (case-insensitive).',
            },
            'scope': {
              'type': 'string',
              'description':
                  'Search scope: "preset" (all slots) or "slot" (specific slot).',
              'enum': ['preset', 'slot'],
            },
            'slot_index': {
              'type': 'integer',
              'description':
                  'Slot index ($_slotRangeDescription). Required when scope is "slot".',
            },
            'partial_match': {
              'type': 'boolean',
              'description':
                  'If true, find parameters containing the query. Default: false (exact match).',
            },
          },
          'required': ['query', 'scope'],
        },
        handler: (args) => _distingTools.searchParameters(args),
        timeout: const Duration(seconds: 5),
      ),
    );
  }

  void _registerShowTools() {
    _entries.add(
      ToolRegistryEntry(
        name: 'show_preset',
        description:
            'Show a compact preset overview: preset name and slot list with algorithm names and parameter counts. '
            'Does NOT include parameter values or mappings. Use show_slot to drill into a specific slot.',
        inputSchema: {'properties': {}},
        handler: (_) => _algoTools.showPreset(),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'get_preset',
        description:
            'Read the current preset without changing it, one bounded page at a '
            'time. Each response contains one populated slot and at most 4 '
            'parameters by default as compact edit_slot_arguments: custom name, '
            'algorithm/specifications, exact current values, and enabled mappings. '
            'Use those arguments directly with edit_slot when creating or restoring '
            'a preset. Follow paging.next until has_more is false; never assume the '
            'first page is complete or change the source preset between pages.',
        inputSchema: {
          'properties': {
            'slot_offset': {
              'type': 'integer',
              'minimum': 0,
              'default': 0,
              'description': 'Zero-based offset into populated slots.',
            },
            'parameter_offset': {
              'type': 'integer',
              'minimum': 0,
              'default': 0,
              'description': 'Zero-based parameter offset in this slot.',
            },
            'parameter_limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 16,
              'default': 4,
              'description': 'Parameters to return in this page (1-16).',
            },
          },
        },
        handler: (args) => _distingTools.getCurrentPreset(args),
        timeout: const Duration(seconds: 30),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'show_slot',
        description:
            'Show a slot with compact, paged parameter summaries (name and current value). '
            'Returns at most 8 parameters by default. Follow next exactly when has_more is true. '
            'Does NOT include ranges, enum value lists, or full mappings; use show_parameter for those. '
            'is_enum, is_disabled, and has_mapping are included only when true.',
        inputSchema: {
          'properties': {
            'slot_index': {
              'type': 'integer',
              'minimum': _slotMinimum,
              'maximum': _slotMaximum,
              'description': 'Slot index ($_slotRangeDescription).',
            },
            'parameter_offset': {
              'type': 'integer',
              'minimum': 0,
              'default': 0,
              'description': 'Zero-based parameter offset in the slot.',
            },
            'parameter_limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 16,
              'default': 8,
              'description':
                  'Parameters in this response (1-16); this does not limit the slot total.',
            },
          },
          'required': ['slot_index'],
        },
        handler: (args) => _algoTools.showSlot(
          args['slot_index'],
          offset: args['parameter_offset'] as int? ?? 0,
          limit: args['parameter_limit'] as int?,
        ),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'show_parameter',
        description:
            'Show one parameter with exact edit-preparation metadata: current and default values, '
            'range, unit, complete enum vocabulary, disabled state, and enabled mappings.',
        inputSchema: {
          'properties': {
            'slot_index': {
              'type': 'integer',
              'minimum': _slotMinimum,
              'maximum': _slotMaximum,
              'description': 'Slot index ($_slotRangeDescription).',
            },
            'parameter_number': {
              'description':
                  'Parameter identifier: integer number (0-based) or string name.',
              'oneOf': [
                {'type': 'string'},
                {'type': 'integer'},
              ],
            },
          },
          'required': ['slot_index', 'parameter_number'],
        },
        handler: (args) => _algoTools.showParameterByIndex(
          args['slot_index'],
          args['parameter_number'],
        ),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'show_slot_metadata',
        description:
            'Show the complete raw metadata shape currently reported by the connected device for a slot: specifications, parameters, enums, pages, page memberships, and output-mode usage. Intended for deterministic hardware validation; large results may be returned as references.',
        inputSchema: {
          'properties': {
            'slot_index': {
              'type': 'integer',
              'minimum': _slotMinimum,
              'maximum': _slotMaximum,
              'description': 'Slot index ($_slotRangeDescription).',
            },
          },
          'required': ['slot_index'],
        },
        handler: (args) => _algoTools.showSlotMetadata(args['slot_index']),
        timeout: const Duration(seconds: 30),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'show_screen',
        description:
            'Capture and return the current device screen as a base64 PNG image.',
        inputSchema: {
          'properties': {
            'display_mode': {
              'type': 'string',
              'description':
                  'Optional display mode to switch to before capturing. Options: "parameter" (hardware parameter list), "algorithm" (custom algorithm interface), "overview" (all slots overview), "vu_meters" (VU meter display)',
              'enum': ['parameter', 'algorithm', 'overview', 'vu_meters'],
            },
          },
        },
        handler: (args) =>
            _algoTools.showScreen(displayMode: args['display_mode']),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'show_routing',
        description:
            'Show the current signal routing state with input/output bus assignments for all slots.',
        inputSchema: {'properties': {}},
        handler: (_) => _algoTools.showRouting(),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'show_cpu',
        description:
            'Show CPU usage for the device and per-slot usage breakdown.',
        inputSchema: {'properties': {}},
        handler: (_) => _algoTools.showCpu(),
      ),
    );
  }

  void _registerEditTools() {
    _entries.add(
      ToolRegistryEntry(
        name: 'edit_preset',
        description:
            'Edit the entire preset state including name and all slots. WARNING: Replaces the full preset.',
        inputSchema: {
          'properties': {
            'data': {
              'type': 'object',
              'description': 'Full preset data with name and slots array.',
              'properties': {
                'name': {'type': 'string', 'description': 'Preset name'},
                'slots': {
                  'type': 'array',
                  'description':
                      'Array of slot objects with algorithm and parameters',
                },
              },
            },
          },
          'required': ['data'],
        },
        handler: (args) => _distingTools.editPreset(args),
        timeout: const Duration(seconds: 30),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'edit_slot',
        description:
            'Edit a specific slot: change algorithm, set parameters, or rename. Device must be in connected mode.',
        inputSchema: {
          'properties': {
            'slot_index': {
              'type': 'integer',
              'minimum': _slotMinimum,
              'maximum': _slotMaximum,
              'description': 'Slot index ($_slotRangeDescription).',
            },
            'data': {
              'type': 'object',
              'description':
                  'Slot data with optional algorithm, parameters, and name.',
              'properties': {
                'algorithm': {
                  'type': 'object',
                  'description':
                      'Algorithm specification (guid or name, plus optional specifications)',
                  'properties': {
                    'guid': {'type': 'string', 'description': 'Algorithm GUID'},
                    'name': {
                      'type': 'string',
                      'description': 'Algorithm name (fuzzy matching)',
                    },
                    'specifications': {
                      'type': 'array',
                      'description': 'Algorithm-specific specification values',
                      'items': {'type': 'integer'},
                    },
                  },
                },
                'name': {'type': 'string', 'description': 'Custom slot name'},
                'parameters': {
                  'type': 'array',
                  'description':
                      'Array of parameter objects with values and/or mappings',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'parameter_number': {
                        'type': 'integer',
                        'description': 'Parameter index',
                      },
                      'value': {
                        'description':
                            'Parameter value. For enum parameters, use one of the exact strings from valid_enum_values. For numeric parameters, use a number.',
                      },
                      'mapping': {
                        'type': 'object',
                        'description':
                            'Mapping with CV, MIDI, i2c, and performance page fields. Supports partial updates.',
                      },
                    },
                  },
                },
              },
            },
          },
          'required': ['slot_index', 'data'],
        },
        handler: (args) => _distingTools.editSlot(args),
        timeout: const Duration(seconds: 30),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'edit_parameter',
        description:
            'Edit a single parameter value and/or mapping. Validation errors include '
            'allowed enum labels or numeric ranges for a corrected retry. Device must be in connected mode.',
        inputSchema: {
          'properties': {
            'slot_index': {
              'type': 'integer',
              'minimum': _slotMinimum,
              'maximum': _slotMaximum,
              'description': 'Slot index ($_slotRangeDescription).',
            },
            'parameter_number': {
              'description':
                  'Parameter identifier: integer number (0-based) or string name.',
              'oneOf': [
                {'type': 'string'},
                {'type': 'integer'},
              ],
            },
            'value': {
              'description':
                  'Parameter value. For enum parameters, use one of the exact strings from valid_enum_values. For numeric parameters, use a number. If omitted, mapping must be provided.',
            },
            'mapping': {
              'type': 'object',
              'description':
                  'Parameter mapping with CV, MIDI, i2c, and performance page controls. Supports partial updates.',
              'properties': {
                'cv': {
                  'type': 'object',
                  'description':
                      'CV mapping: source, cv_input (0-12), is_unipolar, is_gate, volts, delta',
                },
                'midi': {
                  'type': 'object',
                  'description':
                      'MIDI mapping: is_midi_enabled, midi_channel (0-15), midi_cc (0-128; ignored for pitch_bend/channel_pressure), midi_type, is_midi_symmetric, is_midi_relative, midi_min, midi_max',
                },
                'i2c': {
                  'type': 'object',
                  'description':
                      'i2c mapping: is_i2c_enabled, i2c_cc (0-255), is_i2c_symmetric, i2c_min, i2c_max',
                },
                'performance_page': {
                  'type': 'integer',
                  'description':
                      'Performance page index (0=not assigned, 1-30=page number)',
                },
              },
            },
          },
          'required': ['slot_index', 'parameter_number'],
        },
        handler: (args) => _distingTools.editParameter(args),
        timeout: const Duration(seconds: 15),
      ),
    );
  }

  void _registerPresetTools() {
    _entries.add(
      ToolRegistryEntry(
        name: 'rename_preset',
        description:
            'Non-destructively rename the current preset and save it. Preserves '
            'every slot, algorithm, parameter value, specification, slot name, '
            'and mapping. Use this instead of edit_preset for a name-only change. '
            'The name is trimmed and must be 1-31 characters.',
        inputSchema: {
          'properties': {
            'name': {
              'type': 'string',
              'minLength': 1,
              'maxLength': 31,
              'description': 'New preset name (1-31 characters).',
            },
          },
          'required': ['name'],
        },
        handler: (args) => _distingTools.setPresetName(args),
        timeout: const Duration(seconds: 15),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'new',
        description:
            'Create new blank preset or preset with initial algorithms. WARNING: Clears current preset.',
        inputSchema: {
          'properties': {
            'name': {
              'type': 'string',
              'description': 'Name for the new preset.',
            },
            'algorithms': {
              'type': 'array',
              'description':
                  'Algorithms to add. Each: {name: string} or {guid: string}. Added to slots 0, 1, 2, etc.',
              'items': {
                'type': 'object',
                'properties': {
                  'guid': {
                    'type': 'string',
                    'description': 'Algorithm GUID (alternative to name)',
                  },
                  'name': {
                    'type': 'string',
                    'description': 'Algorithm name (fuzzy matching)',
                  },
                  'specifications': {
                    'type': 'array',
                    'description': 'Algorithm-specific specification values',
                    'items': {'type': 'integer'},
                  },
                },
              },
            },
          },
          'required': ['name'],
        },
        handler: (args) => _distingTools.newWithAlgorithms(args),
        timeout: const Duration(seconds: 30),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'save',
        description: 'Save the current preset to the device.',
        inputSchema: {'properties': {}},
        handler: (args) => _distingTools.savePreset(args),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'add',
        description: 'Add an algorithm to the preset. Requires name or guid.',
        inputSchema: {
          'properties': {
            'name': {
              'type': 'string',
              'description':
                  'Algorithm name (fuzzy matching). Required if no guid.',
            },
            'guid': {
              'type': 'string',
              'description': 'Algorithm GUID. Required if no name.',
            },
            'slot_index': {
              'type': 'integer',
              'description':
                  'Insert position ($_slotRangeDescription). Omit for first empty slot.',
            },
            'specifications': {
              'type': 'array',
              'items': {'type': 'integer'},
              'description':
                  'Specification values for algorithms that require them (e.g., channel count, max delay time).',
            },
          },
        },
        handler: (args) =>
            _distingTools.addSimple({...args, 'target': 'algorithm'}),
        timeout: const Duration(seconds: 30),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'apply_template_to_preset',
        description:
            'Apply selected slots from a saved template to the connected device or to a saved local preset.',
        inputSchema: {
          'properties': {
            'template_id': {
              'type': 'integer',
              'description': 'Template preset id.',
            },
            'template_name': {
              'type': 'string',
              'description':
                  'Alternative to template_id; resolved by exact match, then case-insensitive exact match.',
            },
            'slot_indices': {
              'type': 'array',
              'items': {'type': 'integer', 'minimum': 0},
              'description':
                  'Which template slots to apply. Omit to apply all.',
            },
            'target': {
              'type': 'string',
              'enum': ['device', 'preset'],
              'description': 'Where to apply. Default: device.',
            },
            'target_preset_id': {
              'type': 'integer',
              'description': 'Required when target is "preset".',
            },
            'target_preset_name': {
              'type': 'string',
              'description': 'Alternative to target_preset_id.',
            },
            'insertion_offset': {
              'type': 'integer',
              'description':
                  'Slot index in target. Default: append for device, 0 for preset.',
            },
            'overwrite': {
              'type': 'boolean',
              'description':
                  'Replace target slots starting at insertion_offset. Default: false.',
            },
          },
        },
        handler: (args) => _distingTools.applyTemplateToPreset(args),
        timeout: const Duration(seconds: 120),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'remove',
        description:
            'Remove the algorithm from a slot, leaving it empty. Succeeds gracefully if slot is already empty.',
        inputSchema: {
          'properties': {
            'slot_index': {
              'type': 'integer',
              'description': 'Slot index to clear ($_slotRangeDescription).',
            },
          },
          'required': ['slot_index'],
        },
        handler: (args) =>
            _distingTools.removeSlot({...args, 'target': 'slot'}),
      ),
    );

    _entries.add(
      ToolRegistryEntry(
        name: 'move_algorithm',
        description:
            'Move an algorithm up or down in the slot list. '
            'Algorithms swap positions with adjacent slots.',
        inputSchema: {
          'properties': {
            'slot_index': {
              'type': 'integer',
              'description':
                  'Current slot index of the algorithm to move ($_slotRangeDescription).',
            },
            'direction': {
              'type': 'string',
              'enum': ['up', 'down'],
              'description':
                  'Direction to move: "up" (lower slot number) or "down" (higher slot number).',
            },
            'steps': {
              'type': 'integer',
              'description': 'Number of positions to move (default: 1).',
            },
          },
          'required': ['slot_index', 'direction'],
        },
        handler: (args) => _distingTools.moveAlgorithm(args),
      ),
    );
  }
}
