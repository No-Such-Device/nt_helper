import 'dart:convert';
import 'package:nt_helper/models/algorithm_metadata.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show ParameterInfo, ParameterValue, Mapping, DisplayMode;
import 'package:nt_helper/util/case_converter.dart';
import 'package:nt_helper/mcp/mcp_constants.dart';
import 'package:nt_helper/mcp/utils/bus_mapping.dart';

/// Class containing methods representing MCP tools.
/// Requires DistingController for accessing state and DistingCubit for
/// operations not yet migrated to the controller (routing, screen, CPU).
class MCPAlgorithmTools {
  // Make service instance-based if needed, or keep static if stateless
  static final _metadataService = AlgorithmMetadataService();
  static const int _defaultShowSlotParameterLimit = 8;
  static const int _maxShowSlotParameterLimit = 16;
  final DistingController _controller;
  final DistingCubit _distingCubit;

  MCPAlgorithmTools(this._controller, this._distingCubit);

  /// Returns all known algorithms by merging metadata DB with device state.
  List<dynamic> _getAllKnownAlgorithms() {
    final metadataAlgorithms = _metadataService.getAllAlgorithms();
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

  /// MCP Tool: Retrieves full metadata for a specific algorithm.
  /// Parameters:
  ///   - algorithm_guid (string): The unique identifier of the algorithm.
  ///   - algorithm_name (string): The name of the algorithm (alternative to GUID).
  ///   - expand_features (bool, optional, default: false): Expand feature parameters.
  /// Returns:
  ///   A JSON string representing the AlgorithmMetaor an error JSON if not found or ambiguous.
  Future<String> getAlgorithmDetails(Map<String, dynamic> params) async {
    final String? algorithmGuid = params['algorithm_guid'];
    final String? algorithmName = params['algorithm_name'];
    final bool expandFeatures = params['expand_features'] ?? false;

    // Use shared algorithm resolver (includes device-only algorithms)
    List<dynamic> algorithms;
    try {
      algorithms = _getAllKnownAlgorithms();
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'AlgorithmMetadataService error: ${e.toString()}',
        }),
      );
    }
    final resolution = AlgorithmResolver.resolveAlgorithm(
      guid: algorithmGuid,
      algorithmName: algorithmName,
      allAlgorithms: algorithms,
    );

    if (!resolution.isSuccess) {
      return jsonEncode(convertToSnakeCaseKeys(resolution.error!));
    }

    final algorithm = _metadataService.getAlgorithmByGuid(
      resolution.resolvedGuid!,
    );
    if (algorithm == null) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            '${MCPConstants.notFoundError}: Algorithm with GUID "${resolution.resolvedGuid!}"',
            helpCommand: MCPConstants.getAlgorithmHelp,
          ),
        ),
      );
    }

    AlgorithmMetadata algoToProcess;
    if (expandFeatures) {
      final expandedParams = _metadataService.getExpandedParameters(
        resolution.resolvedGuid!,
      );
      algoToProcess = algorithm.copyWith(parameters: expandedParams);
    } else {
      algoToProcess = algorithm;
    }

    Map<String, dynamic> algoJson;
    try {
      algoJson = algoToProcess.toJson();
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Failed to serialize algorithm: ${e.toString()}',
        }),
      );
    }

    // Remove parameterNumber from params to clean up response
    try {
      if (algoJson['parameters'] is List) {
        List<dynamic> paramsList = algoJson['parameters'] as List<dynamic>;
        for (var param in paramsList) {
          if (param is Map<String, dynamic>) {
            param.remove('parameterNumber');
          }
        }
      }
    } catch (e) {
      // If parameter processing fails, return the algorithm without modification
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Failed to process parameters: ${e.toString()}',
        }),
      );
    }

    try {
      return jsonEncode(convertToSnakeCaseKeys(algoJson));
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Failed to encode response: ${e.toString()}',
        }),
      );
    }
  }

  /// MCP Tool: Retrieves documentation-style metadata for a specific algorithm.
  ///
  /// This is the public, compact tool shape for the same data used by
  /// [getAlgorithmDetails]. It accepts short parameter names that fit the
  /// simplified MCP/chat tool set, then delegates to the existing metadata
  /// implementation used by the algorithm documentation UI.
  Future<String> algorithmInfo(Map<String, dynamic> params) {
    return getAlgorithmDetails({
      'algorithm_guid': params['guid'] ?? params['algorithm_guid'],
      'algorithm_name': params['name'] ?? params['algorithm_name'],
      'expand_features': params['expand_features'] ?? false,
    });
  }

  /// MCP Tool: Lists algorithms, optionally filtered by category or a text query.
  /// Parameters:
  ///   - category (string, optional): Filter by category.
  ///   - query (string, optional): Filter by a text search query.
  /// Returns:
  ///   A JSON string representing a list of AlgorithmMetadata objects, containing
  ///   only guid, name, and the first sentence of the description.
  Future<String> listAlgorithms(Map<String, dynamic> params) async {
    final String? category = params['category'];
    final String? query = params['query']; // Added query parameter

    List<AlgorithmMetadata> algorithms;
    try {
      algorithms = _metadataService.getAllAlgorithms();
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'AlgorithmMetadataService error: ${e.toString()}',
        }),
      );
    }

    // Apply filters
    if (category != null && category.isNotEmpty) {
      algorithms = algorithms
          .where(
            (alg) => alg.categories.any(
              (cat) =>
                  cat.toLowerCase() == category.toLowerCase() ||
                  MCPUtils.similarity(cat, category) >= 0.7,
            ),
          )
          .toList();
    }

    if (query != null && query.isNotEmpty) {
      final lowercaseQuery = query.toLowerCase();
      algorithms = algorithms.where((alg) {
        return alg.name.toLowerCase().contains(lowercaseQuery) ||
            alg.description.toLowerCase().contains(lowercaseQuery) ||
            alg.categories.any(
              (cat) => cat.toLowerCase().contains(lowercaseQuery),
            ) ||
            alg.features.any(
              (feature) => feature.toLowerCase().contains(lowercaseQuery),
            );
      }).toList();
    }

    List<Map<String, dynamic>> resultList = [];
    for (var alg in algorithms) {
      String firstSentenceDescription = '';
      if (alg.description.isNotEmpty) {
        int firstPeriod = alg.description.indexOf('.');
        if (firstPeriod != -1) {
          firstSentenceDescription = alg.description.substring(
            0,
            firstPeriod + 1,
          );
        } else {
          firstSentenceDescription =
              alg.description; // No period, take whole description
        }
      }
      resultList.add({
        'guid': alg.guid,
        'name': alg.name,
        'description': firstSentenceDescription,
      });
    }
    return jsonEncode(convertToSnakeCaseKeys(resultList));
  }

  /// MCP Tool: Retrieves the current routing state derived from slot parameters.
  /// Uses the same parameter-based approach as the routing editor UI,
  /// which works in connected, offline, and demo modes.
  /// Parameters: None
  /// Returns:
  ///   A JSON string representing the input and output buses of each slot.
  ///   Returns an empty list '[]' if the state is not synchronized.
  Future<String> getCurrentRoutingState(Map<String, dynamic> params) async {
    final state = _distingCubit.state;
    if (state is! DistingStateSynchronized) {
      return jsonEncode([]);
    }

    final slots = state.slots;
    final routings = <AlgorithmRouting>[];

    for (final slot in slots) {
      routings.add(
        AlgorithmRouting.fromSlot(slot, deviceIoProfile: state.deviceIoProfile),
      );
    }

    // Discover connections (not needed for bus lists, but validates the data)
    // We extract bus usage directly from ports
    final slotDataList = <Map<String, dynamic>>[];

    for (int i = 0; i < slots.length; i++) {
      final slot = slots[i];
      final routing = routings[i];

      final inputBuses = <int>{};
      final outputBuses = <int>{};

      for (final port in routing.inputPorts) {
        final busValue = port.busValue;
        if (busValue != null && busValue > 0) {
          inputBuses.add(busValue);
        }
      }

      for (final port in routing.outputPorts) {
        final busValue = port.busValue;
        if (busValue != null && busValue > 0) {
          outputBuses.add(busValue);
        }
      }

      final sortedInputs = inputBuses.toList()..sort();
      final sortedOutputs = outputBuses.toList()..sort();

      slotDataList.add({
        'slotIndex': i,
        'algorithmName': slot.algorithm.name,
        'inputBuses': sortedInputs
            .map(
              (b) => BusMapping.busToName(
                b,
                deviceIoProfile: state.deviceIoProfile,
              ),
            )
            .toList(),
        'outputBuses': sortedOutputs
            .map(
              (b) => BusMapping.busToName(
                b,
                deviceIoProfile: state.deviceIoProfile,
              ),
            )
            .toList(),
      });
    }

    return jsonEncode(convertToSnakeCaseKeys(slotDataList));
  }

  /// MCP Tool: Search for algorithms by name/category with fuzzy matching.
  /// Parameters:
  ///   - query (string, required): Search query (algorithm name, partial name, or category).
  /// Returns:
  ///   A JSON string representing an array of matching algorithms sorted by relevance.
  ///   Each result contains: guid, name, category, description, general_parameters
  ///   Maximum 10 results returned. Empty array with helpful message if no matches found.
  /// Note: Called via the 'search' tool when target="algorithm". Target validation
  /// is handled by the dispatcher in mcp_server_service.dart.
  Future<String> searchAlgorithms(Map<String, dynamic> params) async {
    final String? query = params['query'];

    if (query == null || query.isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys(
          MCPUtils.buildError(
            '${MCPConstants.missingParamError}: "query" is required',
          ),
        ),
      );
    }

    // Get all algorithms
    List<AlgorithmMetadata> algorithms;
    try {
      algorithms = _metadataService.getAllAlgorithms();
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'AlgorithmMetadataService error: ${e.toString()}',
        }),
      );
    }

    // Score and filter algorithms
    final List<_SearchResult> results = [];
    final lowerQuery = query.toLowerCase();

    // Run BM25 text search once for all algorithms
    final textScores = _metadataService.searchIndex.search(lowerQuery);

    for (final algorithm in algorithms) {
      double score = _calculateSearchScore(
        algorithm,
        lowerQuery,
        textScore: textScores[algorithm.guid],
      );

      // Only include results that meet minimum threshold
      if (score >= 30) {
        results.add(_SearchResult(algorithm: algorithm, score: score));
      }
    }

    // Sort by relevance score (descending)
    results.sort((a, b) => b.score.compareTo(a.score));

    // Limit to top 10 results
    final limitedResults = results.take(10).toList();

    // Build response
    if (limitedResults.isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'results': [],
          'message':
              'No algorithms found matching "$query". Try searching by algorithm name or category.',
          'suggestions':
              'Use `search_algorithms` with a broader query or `algorithm_info` for specific algorithms.',
        }),
      );
    }

    final List<Map<String, dynamic>> resultList = [];
    for (final result in limitedResults) {
      final algorithm = result.algorithm;
      final generalParams = _generateGeneralParameterDescription(algorithm);

      resultList.add({
        'guid': algorithm.guid,
        'name': algorithm.name,
        'category': algorithm.categories.isNotEmpty
            ? algorithm.categories[0]
            : 'Unknown',
        'categories': algorithm.categories,
        'description': algorithm.description,
        'general_parameters': generalParams,
      });
    }

    return jsonEncode(
      convertToSnakeCaseKeys({
        'results': resultList,
        'count': resultList.length,
        'message': 'Found ${resultList.length} matching algorithm(s)',
      }),
    );
  }

  /// Calculate relevance score for algorithm based on query.
  /// Returns score between 0-100.
  /// Score ranges:
  ///   Exact GUID/name = 100
  ///   Partial name (contains) = 85
  ///   Fuzzy name (>=70% Levenshtein) = 70-84
  ///   Text search (BM25) = 30-69
  ///   Category fuzzy match = 20-29
  double _calculateSearchScore(
    AlgorithmMetadata algorithm,
    String lowerQuery, {
    double? textScore,
  }) {
    final lowerName = algorithm.name.toLowerCase();

    // Exact GUID match = 100
    if (algorithm.guid.toLowerCase() == lowerQuery) {
      return 100.0;
    }

    // Exact name match = 100
    if (lowerName == lowerQuery) {
      return 100.0;
    }

    // Partial exact match in name = 85
    if (lowerName.contains(lowerQuery)) {
      return 85.0;
    }

    // Fuzzy name matching >= 70% similarity = 70-84
    final similarity = MCPUtils.similarity(algorithm.name, lowerQuery);
    if (similarity >= 0.70) {
      final score = 70.0 + (similarity - 0.70) * (84.0 - 70.0) / (1.0 - 0.70);
      return score;
    }

    // BM25 text search = 30-69
    if (textScore != null && textScore > 0) {
      return 30.0 + textScore * 39.0;
    }

    // Category fuzzy match = 20-29
    for (final category in algorithm.categories) {
      final catSimilarity = MCPUtils.similarity(category, lowerQuery);
      if (catSimilarity >= 0.70 ||
          category.toLowerCase().contains(lowerQuery)) {
        return 20.0 + (catSimilarity * 9.0);
      }
    }

    // No match
    return 0.0;
  }

  /// Generate general parameter description without specific indices.
  /// Describes what kinds of parameters the algorithm has.
  String _generateGeneralParameterDescription(AlgorithmMetadata algorithm) {
    if (algorithm.parameters.isEmpty) {
      return 'No parameters available';
    }

    // Categorize parameters by their names to provide meaningful descriptions
    final paramCategories = <String>[];
    final paramNames = <String>{};

    for (final param in algorithm.parameters) {
      paramNames.add(param.name.toLowerCase());
    }

    // Check for common parameter patterns
    if (paramNames.any(
      (name) => name.contains('freq') || name.contains('pitch'),
    )) {
      paramCategories.add('frequency/pitch controls');
    }
    if (paramNames.any(
      (name) =>
          name.contains('resonance') || name == 'q' || name.contains('filter'),
    )) {
      paramCategories.add('resonance/filter emphasis controls');
    }
    if (paramNames.any(
      (name) =>
          name.contains('attack') ||
          name.contains('decay') ||
          name.contains('sustain') ||
          name.contains('release'),
    )) {
      paramCategories.add('envelope controls');
    }
    if (paramNames.any(
      (name) =>
          name.contains('amount') ||
          name.contains('depth') ||
          name.contains('level') ||
          name.contains('volume') ||
          name.contains('gain'),
    )) {
      paramCategories.add('level/amplitude controls');
    }
    if (paramNames.any(
      (name) =>
          name.contains('rate') ||
          name.contains('speed') ||
          name.contains('tempo'),
    )) {
      paramCategories.add('rate/speed controls');
    }
    if (paramNames.any(
      (name) =>
          name.contains('mix') ||
          name.contains('balance') ||
          name.contains('blend'),
    )) {
      paramCategories.add('mix/blend controls');
    }
    if (paramNames.any(
      (name) =>
          name.contains('mode') ||
          name.contains('type') ||
          name.contains('shape') ||
          name.contains('form'),
    )) {
      paramCategories.add('mode/type selectors');
    }
    if (paramNames.any(
      (name) => name.contains('time') || name.contains('duration'),
    )) {
      paramCategories.add('time/duration controls');
    }

    if (paramCategories.isEmpty) {
      return 'Algorithm has ${algorithm.parameters.length} parameters';
    }

    return 'Parameters: ${paramCategories.join(', ')}';
  }

  /// MCP Tool: Show tool for flexible state inspection with multiple target types.
  /// Parameters:
  ///   - target (string, required): One of "preset", "slot", "parameter", "screen", "routing"
  ///   - identifier (string or int, optional): Required for slot and parameter targets
  /// Returns:
  ///   Target-specific JSON response with state information
  Future<String> show(Map<String, dynamic> params) async {
    try {
      final String? target = params['target'];
      final dynamic identifier = params['identifier'];
      final dynamic displayMode = params['display_mode'];

      // Validate target parameter
      if (target == null || target.isEmpty) {
        return jsonEncode(
          convertToSnakeCaseKeys({
            'success': false,
            'error': 'Missing required parameter: target',
            'valid_targets': [
              'preset',
              'slot',
              'parameter',
              'screen',
              'routing',
              'cpu',
            ],
          }),
        );
      }

      switch (target.toLowerCase()) {
        case 'preset':
          return showPreset();
        case 'slot':
          return showSlot(identifier);
        case 'parameter':
          return showParameter(identifier);
        case 'screen':
          return showScreen(displayMode: displayMode);
        case 'routing':
          return showRouting();
        case 'cpu':
          return showCpu();
        default:
          return jsonEncode(
            convertToSnakeCaseKeys({
              'success': false,
              'error': 'Invalid target: $target',
              'valid_targets': [
                'preset',
                'slot',
                'parameter',
                'screen',
                'routing',
                'cpu',
              ],
            }),
          );
      }
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Tool execution failed: ${e.toString()}',
        }),
      );
    }
  }

  /// Show compact preset overview: name, slot list with algorithm names and parameter counts.
  /// Does NOT include parameter values or mappings. Use show_slot to drill into a specific slot.
  Future<String> showPreset() async {
    if (!_controller.isSynchronized) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Device not synchronized',
        }),
      );
    }

    final presetName = await _controller.getCurrentPresetName();
    final allSlots = await _controller.getAllSlots();
    final slotsJson = <Map<String, dynamic>>[];

    for (int i = 0; i < allSlots.length; i++) {
      final algorithm = allSlots[i];
      if (algorithm == null) continue;
      final parameters = await _controller.getParametersForSlot(i);
      slotsJson.add({
        'slot_index': i,
        'algorithm': {'guid': algorithm.guid, 'name': algorithm.name},
        'parameter_count': parameters.length,
      });
    }

    return jsonEncode(
      convertToSnakeCaseKeys({'name': presetName, 'slots': slotsJson}),
    );
  }

  /// Show a slot with parameter summaries.
  /// Use show_parameter for full detail (enum value lists, mapping details).
  Future<String> showSlot(
    dynamic identifier, {
    int offset = 0,
    int? limit,
  }) async {
    if (identifier == null) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': '${MCPConstants.missingParamError}: identifier',
        }),
      );
    }

    int slotIndex = -1;
    try {
      slotIndex = (identifier is int)
          ? identifier
          : int.parse(identifier.toString());
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Invalid identifier format: identifier must be an integer (0-${MCPConstants.maxSlots - 1}).',
        }),
      );
    }

    if (slotIndex < 0 || slotIndex >= MCPConstants.maxSlots) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Invalid slot index: $slotIndex. Must be 0-${MCPConstants.maxSlots - 1}.',
        }),
      );
    }

    final effectiveLimit = limit ?? _defaultShowSlotParameterLimit;
    if (offset < 0) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'parameter_offset must be zero or greater.',
        }),
      );
    }
    if (effectiveLimit < 1 || effectiveLimit > _maxShowSlotParameterLimit) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'parameter_limit must be between 1 and $_maxShowSlotParameterLimit per page.',
        }),
      );
    }

    if (!_controller.isSynchronized) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Device not synchronized',
        }),
      );
    }

    final algorithm = await _controller.getAlgorithmInSlot(slotIndex);
    if (algorithm == null) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'slot_index': slotIndex,
          'algorithm': {'guid': '', 'name': ''},
          'parameter_count': 0,
          'offset': 0,
          'limit': effectiveLimit,
          'count': 0,
          'has_more': false,
          'next': null,
          'parameters': <dynamic>[],
        }),
      );
    }

    var parameters = await _controller.getParametersForSlot(slotIndex);
    if (parameters.isEmpty) {
      await _ensureSlotReady(slotIndex);
      parameters = await _controller.getParametersForSlot(slotIndex);
    }
    final values = await _controller.getValuesForSlot(slotIndex);
    final mappings = await _controller.getMappingsForSlot(slotIndex);

    final totalCount = parameters.length;
    final clampedOffset = offset.clamp(0, totalCount);
    final endIndex = (clampedOffset + effectiveLimit).clamp(0, totalCount);
    final hasMore = endIndex < totalCount;

    final parametersJson = <Map<String, dynamic>>[];
    for (int i = clampedOffset; i < endIndex; i++) {
      parametersJson.add(
        await _buildParameterSummaryJson(
          slotIndex,
          parameters[i],
          values[i],
          mappings[i],
        ),
      );
    }

    return jsonEncode(
      convertToSnakeCaseKeys({
        'slot_index': slotIndex,
        'algorithm': {
          'guid': algorithm.guid,
          'name': algorithm.name,
          if (algorithm.specifications.isNotEmpty)
            'specifications': algorithm.specifications,
        },
        'parameter_count': totalCount,
        'offset': clampedOffset,
        'limit': effectiveLimit,
        'count': parametersJson.length,
        'has_more': hasMore,
        'next': hasMore
            ? {
                'tool': 'show_slot',
                'arguments': {
                  'slot_index': slotIndex,
                  'parameter_offset': endIndex,
                  'parameter_limit': effectiveLimit,
                },
              }
            : null,
        'parameters': parametersJson,
      }),
    );
  }

  /// Force one slot to be re-read from the NT, then return its compact state.
  Future<String> refreshSlot(int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= MCPConstants.maxSlots) {
      return jsonEncode({
        'success': false,
        'error':
            'Invalid slot index: $slotIndex. Must be 0-${MCPConstants.maxSlots - 1}.',
      });
    }
    if (!_controller.isSynchronized) {
      return jsonEncode({'success': false, 'error': 'Device not synchronized'});
    }

    try {
      await _controller.refreshSlot(slotIndex);
      final refreshedSlot = jsonDecode(await showSlot(slotIndex));
      return jsonEncode({
        'success': true,
        'refreshed': true,
        'slot_index': slotIndex,
        'slot': refreshedSlot,
      });
    } catch (e) {
      return jsonEncode({
        'success': false,
        'slot_index': slotIndex,
        'error': 'Failed to refresh slot from the NT: ${e.toString()}',
      });
    }
  }

  /// Show the complete metadata shape reported by the connected device for a
  /// slot. This intentionally returns raw values so automated hardware suites
  /// can compare the device with the offline metadata resolver exactly.
  Future<String> showSlotMetadata(dynamic identifier) async {
    final slotIndex = switch (identifier) {
      int value => value,
      String value => int.tryParse(value),
      _ => null,
    };
    if (slotIndex == null) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Invalid slot index: expected an integer',
        }),
      );
    }
    if (slotIndex < 0 || slotIndex >= MCPConstants.maxSlots) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Invalid slot index: $slotIndex. Must be 0-${MCPConstants.maxSlots - 1}.',
        }),
      );
    }
    if (!_controller.isSynchronized) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Device not synchronized',
        }),
      );
    }

    await _ensureSlotReady(slotIndex);
    final algorithm = await _controller.getAlgorithmInSlot(slotIndex);
    final snapshot = await _controller.getAlgorithmShapeForSlot(slotIndex);
    if (algorithm == null || snapshot == null) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Slot $slotIndex is empty',
        }),
      );
    }

    return jsonEncode(
      convertToSnakeCaseKeys({
        'success': true,
        'slot_index': slotIndex,
        'algorithm': {'guid': algorithm.guid, 'name': algorithm.name},
        'specification_values': snapshot.specificationValues,
        'parameters': [
          for (final parameter in snapshot.parameters)
            {
              'name': parameter.name,
              'min': parameter.min,
              'max': parameter.max,
              'default_value': parameter.defaultValue,
              'raw_unit_index': parameter.rawUnitIndex,
              'power_of_ten': parameter.powerOfTen,
              'io_flags': parameter.ioFlags,
              'enum_strings': parameter.enumStrings,
            },
        ],
        'pages': [
          for (final page in snapshot.pages) {'name': page.name},
        ],
        'page_memberships': [
          for (final edge in snapshot.pageMemberships)
            {
              'page_index': edge.pageIndex,
              'parameter_number': edge.parameterNumber,
            },
        ],
        'output_usage': [
          for (final edge in snapshot.outputUsage)
            {
              'parameter_number': edge.parameterNumber,
              'affected_parameter_number': edge.affectedParameterNumber,
            },
        ],
      }),
    );
  }

  /// Show single parameter with value and optional mapping.
  /// Accepts identifier in "slot_index:parameter_number" format.
  Future<String> showParameter(dynamic identifier) async {
    if (identifier == null) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': '${MCPConstants.missingParamError}: identifier',
        }),
      );
    }

    // Parse identifier in format "slot_index:parameter_number"
    final parts = identifier.toString().split(':');
    if (parts.length != 2) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Invalid identifier format: expected slot_index:parameter_number.',
        }),
      );
    }
    if (parts[0].isEmpty || parts[1].isEmpty) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Invalid identifier format: expected slot_index:parameter_number.',
        }),
      );
    }

    int slotIndex = -1;
    int parameterNumber = -1;
    try {
      slotIndex = int.parse(parts[0]);
      parameterNumber = int.parse(parts[1]);
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'slot_index and parameter_number must be integers.',
        }),
      );
    }

    if (slotIndex < 0 || slotIndex >= MCPConstants.maxSlots) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Invalid slot index: $slotIndex. Must be 0-${MCPConstants.maxSlots - 1}.',
        }),
      );
    }

    if (!_controller.isSynchronized) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Device not synchronized',
        }),
      );
    }

    final parameters = await _controller.getParametersForSlot(slotIndex);
    final paramIdx = parameters.indexWhere(
      (p) => p.parameterNumber == parameterNumber,
    );
    if (paramIdx == -1) {
      final available = parameters.map((p) => p.parameterNumber).toList();
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Parameter number $parameterNumber not found in slot $slotIndex. Available parameter numbers: $available',
        }),
      );
    }

    final values = await _controller.getValuesForSlot(slotIndex);
    final mappings = await _controller.getMappingsForSlot(slotIndex);

    final parameter = parameters[paramIdx];
    final value = values[paramIdx];
    final mapping = mappings[paramIdx];

    final paramJson = await _buildParameterJson(
      slotIndex,
      parameter.parameterNumber,
      parameter,
      value,
      mapping,
    );

    return jsonEncode(convertToSnakeCaseKeys(paramJson));
  }

  /// Show single parameter by separate slot_index and parameter identifier.
  /// Accepts integer parameter number or string parameter name.
  Future<String> showParameterByIndex(
    int slotIndex,
    dynamic parameterIdent,
  ) async {
    if (parameterIdent is int) {
      return showParameter('$slotIndex:$parameterIdent');
    }
    if (parameterIdent is String) {
      // Resolve parameter name to number
      if (!_controller.isSynchronized) {
        return jsonEncode(
          convertToSnakeCaseKeys({
            'success': false,
            'error': 'Device not synchronized',
          }),
        );
      }
      final parameters = await _controller.getParametersForSlot(slotIndex);
      for (final p in parameters) {
        if (p.name == parameterIdent) {
          return showParameter('$slotIndex:${p.parameterNumber}');
        }
      }
      final availableNames = parameters.map((p) => p.name).join(', ');
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error':
              'Parameter "$parameterIdent" not found in slot $slotIndex. Available: $availableNames',
        }),
      );
    }
    return jsonEncode(
      convertToSnakeCaseKeys({
        'success': false,
        'error': 'parameter_number must be an integer or string name.',
      }),
    );
  }

  /// Show current device screen as base64 PNG image.
  Future<String> showScreen({dynamic displayMode}) async {
    try {
      // Validate display_mode parameter first, before checking device state
      if (displayMode != null) {
        if (displayMode is! String) {
          return jsonEncode(
            convertToSnakeCaseKeys({
              'success': false,
              'error':
                  'Invalid display_mode: expected a string, got ${displayMode.runtimeType}',
              'valid_modes': [
                'parameter',
                'algorithm',
                'overview',
                'vu_meters',
              ],
            }),
          );
        }
        final modeEnum = _stringToDisplayMode(displayMode);
        if (modeEnum == null) {
          return jsonEncode(
            convertToSnakeCaseKeys({
              'success': false,
              'error': 'Invalid display_mode: $displayMode',
              'valid_modes': [
                'parameter',
                'algorithm',
                'overview',
                'vu_meters',
              ],
            }),
          );
        }
      }

      final state = _distingCubit.state;
      if (state is! DistingStateSynchronized) {
        return jsonEncode(
          convertToSnakeCaseKeys({
            'success': false,
            'error': 'Device not synchronized',
          }),
        );
      }

      // Handle display_mode parameter if provided and validated
      if (displayMode != null && displayMode is String) {
        final modeEnum = _stringToDisplayMode(displayMode)!;

        // Set the display mode
        _distingCubit.setDisplayMode(modeEnum);

        // Wait for screen update
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final manager = state.disting;
      final screenshotData = await manager.encodeTakeScreenshot();

      if (screenshotData == null) {
        return jsonEncode(
          convertToSnakeCaseKeys({
            'success': false,
            'error': 'Screenshot not supported in current mode',
          }),
        );
      }

      // Convert to base64
      final base64Data = _base64Encode(screenshotData);

      return jsonEncode(
        convertToSnakeCaseKeys({
          'type': 'image/png',
          'data': base64Data,
          'size': screenshotData.length,
        }),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Failed to capture screenshot: ${e.toString()}',
        }),
      );
    }
  }

  /// List one directory on the connected NT without sorting its response.
  ///
  /// The absolute [ordinal] values deliberately preserve the order returned by
  /// the device. Agents can recurse through entries whose [is_directory] field
  /// is true and compare that raw order with a parameter catalogue.
  Future<String> listSdDirectory(Map<String, dynamic> params) async {
    final rawPath = params['path'];
    if (rawPath is! String || rawPath.trim().isEmpty) {
      return jsonEncode({
        'success': false,
        'error': 'path must be a non-empty absolute NT SD card path.',
      });
    }

    final trimmedPath = rawPath.trim();
    if (!trimmedPath.startsWith('/')) {
      return jsonEncode({
        'success': false,
        'error': 'path must be an absolute NT SD card path starting with /.',
      });
    }

    final path = trimmedPath == '/'
        ? '/'
        : trimmedPath.replaceFirst(RegExp(r'/+$'), '');
    final offset = params['offset'] as int? ?? 0;
    final limit = params['limit'] as int? ?? 128;
    if (offset < 0) {
      return jsonEncode({
        'success': false,
        'error': 'offset must be zero or greater.',
      });
    }
    if (limit < 1 || limit > 512) {
      return jsonEncode({
        'success': false,
        'error': 'limit must be between 1 and 512.',
      });
    }

    final state = _distingCubit.state;
    if (state is! DistingStateSynchronized) {
      return jsonEncode({'success': false, 'error': 'Device not synchronized'});
    }

    try {
      final listing = await state.disting.requestDirectoryListing(path);
      if (listing == null) {
        return jsonEncode({
          'success': false,
          'path': path,
          'error': 'The NT did not return a directory listing.',
        });
      }

      final total = listing.entries.length;
      final safeOffset = offset.clamp(0, total);
      final end = (safeOffset + limit).clamp(safeOffset, total);
      final entries = <Map<String, dynamic>>[];
      for (var ordinal = safeOffset; ordinal < end; ordinal++) {
        final entry = listing.entries[ordinal];
        entries.add({
          'ordinal': ordinal,
          'name': entry.name,
          'is_directory': entry.isDirectory,
          'attributes': entry.attributes,
          'date': entry.date,
          'time': entry.time,
          'size': entry.size,
        });
      }

      final hasMore = end < total;
      return jsonEncode({
        'path': path,
        'order': 'device_response',
        'total': total,
        'offset': safeOffset,
        'limit': limit,
        'count': entries.length,
        'has_more': hasMore,
        if (hasMore)
          'next': {
            'tool': 'list_sd_directory',
            'arguments': {'path': path, 'offset': end, 'limit': limit},
          },
        'entries': entries,
      });
    } catch (e) {
      return jsonEncode({
        'success': false,
        'path': path,
        'error': 'Failed to list NT SD directory: ${e.toString()}',
      });
    }
  }

  /// Show current routing state using physical names.
  Future<String> showRouting() async {
    try {
      // Reuse existing routing implementation
      return await getCurrentRoutingState({});
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Failed to get routing state: ${e.toString()}',
        }),
      );
    }
  }

  /// Ensure a slot has real parameter data, not an optimistic placeholder.
  /// Force-refreshes from hardware/offline data if parameters are empty.
  Future<void> _ensureSlotReady(int slotIndex) async {
    try {
      await _controller.refreshSlot(slotIndex);
    } catch (_) {
      // Slot may genuinely have no parameters
    }
  }

  /// Build lightweight parameter summary for show_slot paginated output.
  /// Omits valid_enum_values and full mapping objects to keep payload small.
  /// Use show_parameter for full detail.
  Future<Map<String, dynamic>> _buildParameterSummaryJson(
    int slotIndex,
    ParameterInfo parameter,
    ParameterValue value,
    Mapping mapping,
  ) async {
    final isEnum = parameter.unit == 1;

    final paramJson = <String, dynamic>{
      'parameter_number': parameter.parameterNumber,
      'parameter_name': parameter.name,
      if (value.isDisabled) 'is_disabled': true,
    };

    if (isEnum) {
      final strings = await _controller.getParameterEnumStrings(
        slotIndex,
        parameter.parameterNumber,
      );
      final enumValues = strings?.values;
      String? currentEnumValue;
      if (enumValues != null &&
          value.value >= 0 &&
          value.value < enumValues.length) {
        currentEnumValue = enumValues[value.value];
      }
      paramJson['is_enum'] = true;
      paramJson['value'] = currentEnumValue ?? '';
    } else {
      paramJson['value'] = MCPUtils.scaleForDisplay(
        value.value,
        parameter.powerOfTen,
      );
    }

    final data = mapping.packedMappingData;
    final hasMapping =
        data.cvInput > 0 ||
        data.source > 0 ||
        data.isMidiEnabled ||
        data.isI2cEnabled ||
        data.perfPageIndex > 0;
    if (hasMapping) {
      paramJson['has_mapping'] = true;
      if (data.perfPageIndex > 0) {
        paramJson['performance_page'] = data.perfPageIndex;
      }
    }

    return paramJson;
  }

  /// Build JSON representation of a parameter with optional mapping.
  Future<Map<String, dynamic>> _buildParameterJson(
    int slotIndex,
    int parameterNumber,
    ParameterInfo parameter,
    ParameterValue value,
    Mapping mapping,
  ) async {
    final isEnum = parameter.unit == 1;

    final paramJson = <String, dynamic>{
      'parameter_number': parameterNumber,
      'parameter_name': parameter.name,
      'unit': parameter.unit,
      'is_disabled': value.isDisabled,
    };

    if (isEnum) {
      final strings = await _controller.getParameterEnumStrings(
        slotIndex,
        parameterNumber,
      );
      final enumValues = strings?.values;
      String? currentEnumValue;
      if (enumValues != null &&
          value.value >= 0 &&
          value.value < enumValues.length) {
        currentEnumValue = enumValues[value.value];
      }
      paramJson['is_enum'] = true;
      paramJson['value'] = currentEnumValue ?? '';
      paramJson['default'] = parameter.defaultValue;
      if (enumValues != null) {
        paramJson['valid_enum_values'] = enumValues;
        if (parameter.defaultValue >= 0 &&
            parameter.defaultValue < enumValues.length) {
          paramJson['default'] = enumValues[parameter.defaultValue];
        }
      }
    } else {
      paramJson['value'] = MCPUtils.scaleForDisplay(
        value.value,
        parameter.powerOfTen,
      );
      paramJson['min'] = MCPUtils.scaleForDisplay(
        parameter.min,
        parameter.powerOfTen,
      );
      paramJson['max'] = MCPUtils.scaleForDisplay(
        parameter.max,
        parameter.powerOfTen,
      );
      paramJson['default'] = MCPUtils.scaleForDisplay(
        parameter.defaultValue,
        parameter.powerOfTen,
      );
    }

    // Include mapping only if at least one type is enabled
    final mappingJson = _buildMappingJson(mapping);
    if (mappingJson.isNotEmpty) {
      paramJson['mapping'] = mappingJson;
    }

    return paramJson;
  }

  /// Build mapping JSON with only enabled mapping types included.
  /// Returns empty map if all types disabled.
  Map<String, dynamic> _buildMappingJson(Mapping mapping) {
    final data = mapping.packedMappingData;
    final result = <String, dynamic>{};

    // Check CV mapping enabled: cv_input > 0 OR source > 0
    final cvEnabled = data.cvInput > 0 || data.source > 0;
    if (cvEnabled) {
      result['cv'] = {
        'source': data.source,
        'cv_input': data.cvInput,
        'is_unipolar': data.isUnipolar,
        'is_gate': data.isGate,
        'volts': data.volts,
        'delta': data.delta,
      };
    }

    // Check MIDI mapping enabled
    if (data.isMidiEnabled) {
      result['midi'] = {
        'is_midi_enabled': data.isMidiEnabled,
        'midi_channel': data.midiChannel,
        'midi_type': _midiTypeValueToString(data.midiMappingType.value),
        'midi_cc': data.midiCC,
        'is_midi_symmetric': data.isMidiSymmetric,
        'is_midi_relative': data.isMidiRelative,
        'midi_min': data.midiMin,
        'midi_max': data.midiMax,
      };
    }

    // Check i2c mapping enabled
    if (data.isI2cEnabled) {
      result['i2c'] = {
        'is_i2c_enabled': data.isI2cEnabled,
        'i2c_cc': data.i2cCC,
        'is_i2c_symmetric': data.isI2cSymmetric,
        'i2c_min': data.i2cMin,
        'i2c_max': data.i2cMax,
      };
    }

    // Check performance page assigned: perfPageIndex > 0 (1-30)
    if (data.perfPageIndex > 0) {
      result['performance_page'] = data.perfPageIndex;
    }

    return result;
  }

  /// Helper to encode bytes to base64 string.
  String _base64Encode(List<int> bytes) {
    return base64.encode(bytes);
  }

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
        return 'cc';
    }
  }

  /// Convert string display mode to DisplayMode enum.
  /// Maps: "parameter" → DisplayMode.parameters
  ///       "algorithm" → DisplayMode.algorithmUI
  ///       "overview" → DisplayMode.overview
  ///       "vu_meters" → DisplayMode.overviewVUs
  DisplayMode? _stringToDisplayMode(String mode) {
    switch (mode.toLowerCase()) {
      case 'parameter':
        return DisplayMode.parameters;
      case 'algorithm':
        return DisplayMode.algorithmUI;
      case 'overview':
        return DisplayMode.overview;
      case 'vu_meters':
        return DisplayMode.overviewVUs;
      default:
        return null;
    }
  }

  Future<String> showCpu() async {
    try {
      final state = _distingCubit.state;
      if (state is! DistingStateSynchronized) {
        return jsonEncode(
          convertToSnakeCaseKeys({
            'success': false,
            'error': 'Device not synchronized. Connect to device first.',
          }),
        );
      }

      final cpuUsage = await _distingCubit.getCpuUsage();
      if (cpuUsage == null) {
        return jsonEncode(
          convertToSnakeCaseKeys({
            'success': false,
            'error': 'Could not retrieve CPU usage from device',
          }),
        );
      }

      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': true,
          'cpu_usage': {
            'cpu1_percent': cpuUsage.cpu1,
            'cpu2_percent': cpuUsage.cpu2,
            'total_usage_percent': (cpuUsage.cpu1 + cpuUsage.cpu2) / 2.0,
            'slot_usages': cpuUsage.slotUsages
                .asMap()
                .map(
                  (index, usage) => MapEntry(index.toString(), {
                    'slot_index': index,
                    'usage_percent': usage,
                  }),
                )
                .values
                .toList(),
          },
        }),
      );
    } catch (e) {
      return jsonEncode(
        convertToSnakeCaseKeys({
          'success': false,
          'error': 'Error retrieving CPU usage: ${e.toString()}',
        }),
      );
    }
  }
}

/// Internal class to hold search results with relevance scores
class _SearchResult {
  final AlgorithmMetadata algorithm;
  final double score;

  _SearchResult({required this.algorithm, required this.score});
}
