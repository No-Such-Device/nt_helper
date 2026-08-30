import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';

import 'package:collection/collection.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart' show AlgorithmInfo;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nt_helper/mcp/mcp_constants.dart';
import 'package:nt_helper/models/algorithm_metadata.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/ui/algorithm_documentation_screen.dart';
import 'package:nt_helper/ui/widgets/algorithm_specification_dialog.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

/// View modes for displaying algorithms in the Add Algorithm screen
enum AlgorithmViewMode { chipGrid, list }

class AddAlgorithmScreen extends StatefulWidget {
  const AddAlgorithmScreen({super.key});

  @override
  State<AddAlgorithmScreen> createState() => _AddAlgorithmScreenState();
}

class _AddAlgorithmScreenState extends State<AddAlgorithmScreen> {
  static const _favKey = 'favorite_algorithm_guids';
  static const _showFavOnlyKey =
      'add_algo_show_fav_only'; // Key for toggle state
  static const _pluginTypeKey = 'add_algo_plugin_type';
  static const _viewModeKey = 'add_algorithm_view_mode';
  static const _actionTransitionDuration = Duration(milliseconds: 180);
  static const _actionTransitionReverseDuration = Duration(milliseconds: 120);

  // Plugin type options
  static const String _pluginTypeAll = 'all';
  static const String _pluginTypeFactory = 'factory';
  static const String _pluginTypeCommunity = 'community';

  // State for new UI
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce; // Timer for debouncing search input
  List<AlgorithmInfo> _allAlgorithms = [];
  List<AlgorithmInfo> _filteredAlgorithms = [];
  Set<String> _favoriteGuids = {}; // Store favorite GUIDs
  bool _showFavoritesOnly = false; // State for the favorite toggle
  bool _isHelpAvailableForSelected = false;

  // New state for category filters
  List<String> _allCategories = [];
  Set<String> _selectedCategories = {};

  // Plugin type filter state
  String _selectedPluginType = _pluginTypeAll;

  // View mode state
  AlgorithmViewMode _selectedViewMode = AlgorithmViewMode.chipGrid;

  // Scroll controllers for algorithm views
  final ScrollController _chipScrollController = ScrollController();
  final ScrollController _listScrollController = ScrollController();

  // Cached metadata service instance
  final _metadataService = AlgorithmMetadataService();

  // Keyboard navigation state
  int _focusedIndex = -1;
  final FocusNode _viewFocusNode = FocusNode();

  // Original state variables
  String? selectedAlgorithmGuid;
  AlgorithmInfo? _currentAlgoInfo;
  List<int>? specValues;
  bool _shiftHeld = false;
  bool _isAddingAndStayingOpen = false;
  bool _isSubmittingAddAndStayOpen = false;

  @override
  void initState() {
    super.initState();
    _loadSettings(); // Load both favorites and toggle state
    _loadCategories();
    _searchController.addListener(_onSearchChanged); // Use debounced listener
    _shiftHeld = HardwareKeyboard.instance.isShiftPressed;
    HardwareKeyboard.instance.addHandler(_handleKeyboardEvent);

    // Initialize algorithm lists based on current DistingCubit state
    final distingState = context.read<DistingCubit>().state;
    if (distingState case DistingStateSynchronized(
      algorithms: final algorithms,
    )) {
      _allAlgorithms = List<AlgorithmInfo>.from(algorithms)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      // Initial filter
      _filterAlgorithms();
    } else {
      _allAlgorithms = [];
      _filteredAlgorithms = [];
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboardEvent);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _chipScrollController.dispose();
    _listScrollController.dispose();
    _viewFocusNode.dispose();
    super.dispose();
  }

  bool _handleKeyboardEvent(KeyEvent event) {
    final shiftHeld = HardwareKeyboard.instance.isShiftPressed;
    if (_shiftHeld != shiftHeld && mounted) {
      setState(() {
        _shiftHeld = shiftHeld;
      });
    }
    return false;
  }

  bool get _isAddBypassedRequested =>
      _shiftHeld || HardwareKeyboard.instance.isShiftPressed;

  // --- Debounced Search Handler ---
  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      // Check if mounted before calling _filterAlgorithms, as timer might fire after dispose
      if (mounted) {
        _filterAlgorithms();
      }
    });
  }

  // --- Settings Management (Favorites + Toggle State) ---

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList(_favKey) ?? [];
    final showOnlyFavs = prefs.getBool(_showFavOnlyKey) ?? false;
    final pluginType = prefs.getString(_pluginTypeKey) ?? _pluginTypeAll;
    final modeIndex = prefs.getInt(_viewModeKey) ?? 0;
    setState(() {
      _favoriteGuids = favs.toSet();
      _showFavoritesOnly = showOnlyFavs;
      _selectedPluginType = pluginType;
      _selectedViewMode = AlgorithmViewMode.values[modeIndex.clamp(0, 1)];
      // Re-filter after loading settings
      _filterAlgorithms();
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favKey, _favoriteGuids.toList());
  }

  Future<void> _saveShowFavoritesOnlyState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showFavOnlyKey, _showFavoritesOnly);
  }

  Future<void> _savePluginTypeState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pluginTypeKey, _selectedPluginType);
  }

  Future<void> _saveViewModeState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_viewModeKey, _selectedViewMode.index);
  }

  void _toggleFavorite(String guid) {
    final wasAdded = !_favoriteGuids.contains(guid);
    setState(() {
      if (wasAdded) {
        _favoriteGuids.add(guid);
      } else {
        _favoriteGuids.remove(guid);
      }
      _saveFavorites();
      _filterAlgorithms();
    });
    final algoName =
        _allAlgorithms.firstWhereOrNull((a) => a.guid == guid)?.name ?? guid;
    SemanticsService.sendAnnouncement(
      View.of(context),
      wasAdded
          ? '$algoName added to favorites'
          : '$algoName removed from favorites',
      TextDirection.ltr,
    );
  }

  void _toggleShowFavoritesOnly() {
    // Unfocus search field when toggling favorites
    FocusScope.of(context).unfocus();
    setState(() {
      _showFavoritesOnly = !_showFavoritesOnly;
      _saveShowFavoritesOnlyState(); // Save toggle state changes
      _filterAlgorithms(); // Re-filter based on new toggle state
    });
  }

  // --- Documentation Navigation ---
  void _showDocumentation(String guid) async {
    // Unfocus search field when showing docs
    FocusScope.of(context).unfocus();
    final metadata = _metadataService.getAlgorithmByGuid(guid);
    if (metadata != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              AlgorithmDocumentationScreen(metadata: metadata),
        ),
      );
    } else {
      // Optional: Show a snackbar or dialog if metadata is not found
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Full documentation for this algorithm is not available.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _loadCategories() {
    final allAlgos = _metadataService.getAllAlgorithms();
    final allCats = allAlgos.expand((algo) => algo.categories).toSet().toList();
    allCats.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (mounted) {
      setState(() {
        _allCategories = allCats;
      });
    }
  }

  // --- Plugin Type Detection ---
  String _getPluginType(String guid) {
    // Factory algorithms have all lowercase GUIDs
    // Plugins have any uppercase characters
    return guid == guid.toLowerCase()
        ? _pluginTypeFactory
        : _pluginTypeCommunity;
  }

  bool _isPlugin(String guid) {
    return guid != guid.toLowerCase();
  }

  bool _needsLoading(AlgorithmInfo algorithm) {
    return _isPlugin(algorithm.guid) && !algorithm.isLoaded;
  }

  // --- Filtering Logic ---

  void _filterAlgorithms() {
    final query = _searchController.text.toLowerCase();
    // No need for setState here if only called from debounced handler or initState/load
    // setState is handled in the calling methods (_onSearchChanged, _loadSettings, etc.)

    List<AlgorithmInfo> baseList;
    if (_showFavoritesOnly) {
      baseList = _allAlgorithms
          .where((algo) => _favoriteGuids.contains(algo.guid))
          .toList();
    } else {
      baseList = List.from(_allAlgorithms);
    }

    // Filter by plugin type
    if (_selectedPluginType != _pluginTypeAll) {
      baseList = baseList.where((algo) {
        final pluginType = _getPluginType(algo.guid);
        return pluginType == _selectedPluginType;
      }).toList();
    }

    // Filter by selected categories
    if (_selectedCategories.isNotEmpty) {
      baseList = baseList.where((algoInfo) {
        // Normalize GUID to lowercase for consistent lookup
        final metadata = _metadataService.getAlgorithmByGuid(
          algoInfo.guid.toLowerCase(),
        );
        // If no metadata, show algorithm (don't filter it out)
        if (metadata == null) return true;
        return metadata.categories.any(
          (cat) => _selectedCategories.contains(cat),
        );
      }).toList();
    }

    if (query.isEmpty) {
      _filteredAlgorithms = baseList;
    } else {
      _filteredAlgorithms = baseList
          .where((algo) => algo.name.toLowerCase().contains(query))
          .toList();
    }

    _filteredAlgorithms.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    // Use WidgetsBinding to ensure setState is called safely after build if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // If the currently selected algorithm is no longer in the filtered list, deselect it
      if (selectedAlgorithmGuid != null &&
          !_filteredAlgorithms.any(
            (algo) => algo.guid == selectedAlgorithmGuid,
          )) {
        _clearSelection(); // Calls setState internally
      } else {
        // Trigger UI rebuild with the filtered list
        setState(() {});
      }
    });
  }

  // --- Selection Logic ---
  void _selectAlgorithm(String? guid) {
    // Unfocus search field when selecting an algorithm
    FocusScope.of(context).unfocus();
    setState(() {
      selectedAlgorithmGuid = guid;
      _currentAlgoInfo = _allAlgorithms.firstWhereOrNull((a) => a.guid == guid);
      specValues = _currentAlgoInfo?.specifications
          .map((s) => s.safeDefaultValue)
          .toList();

      if (guid != null) {
        final metadata = _metadataService.getAlgorithmByGuid(guid);
        _isHelpAvailableForSelected = metadata != null;
      } else {
        _isHelpAvailableForSelected = false;
      }
    });
    if (guid != null) {
      final name = _currentAlgoInfo?.name ?? 'algorithm';
      SemanticsService.sendAnnouncement(
        WidgetsBinding.instance.platformDispatcher.views.first,
        '$name selected',
        TextDirection.ltr,
      );

      final algorithm = _currentAlgoInfo;
      final state = context.read<DistingCubit>().state;
      if (algorithm != null &&
          _needsLoading(algorithm) &&
          state is DistingStateSynchronized &&
          !state.offline) {
        _loadPlugin(algorithm.guid);
      }
    }
  }

  void _clearSelection() {
    // No need to unfocus here as it happens when list updates remove selection
    setState(() {
      selectedAlgorithmGuid = null;
      _currentAlgoInfo = null;
      specValues = null;
      _isHelpAvailableForSelected = false;
    });
  }

  /// Load a plugin to get its full specifications
  void _loadPlugin(String algorithmGuid) async {
    final algorithm = _allAlgorithms.firstWhereOrNull(
      (algo) => algo.guid == algorithmGuid,
    );
    if (algorithm == null) return;

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loading plugin ${algorithm.name}...'),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    try {
      final cubit = context.read<DistingCubit>();

      final loadedInfo = await cubit.loadPlugin(algorithmGuid);

      if (loadedInfo != null && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        // The cubit has already updated the global state, no need for manual local updates
        // Just update the currently selected algorithm info if it matches
        if (selectedAlgorithmGuid == algorithmGuid) {
          setState(() {
            _currentAlgoInfo = loadedInfo;
            specValues = loadedInfo.specifications
                .map((s) => s.safeDefaultValue)
                .toList();
          });
          // Trigger filtering to update the display
          _filterAlgorithms();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load ${algorithm.name}'),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading ${algorithm.name}: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final distingState = context.watch<DistingCubit>().state;
    final bool isOffline = switch (distingState) {
      DistingStateSynchronized(offline: final o) => o,
      _ => false,
    };
    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final actionTransitionDuration = animationsDisabled
        ? Duration.zero
        : _actionTransitionDuration;
    final actionTransitionReverseDuration = animationsDisabled
        ? Duration.zero
        : _actionTransitionReverseDuration;

    // Update allAlgorithms if the state changes (e.g., going online/offline)
    if (distingState case DistingStateSynchronized(
      algorithms: final algorithms,
    )) {
      if (!listEquals(_allAlgorithms, algorithms)) {
        _allAlgorithms = List<AlgorithmInfo>.from(
          algorithms,
        )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        // If we have a currently selected algorithm, update it to reflect the latest state
        if (selectedAlgorithmGuid != null) {
          final updatedAlgo = _allAlgorithms.firstWhereOrNull(
            (a) => a.guid == selectedAlgorithmGuid,
          );
          if (updatedAlgo != null && _currentAlgoInfo != null) {
            _currentAlgoInfo = updatedAlgo;
            // Update specValues if the number of specifications changed
            if (_currentAlgoInfo!.specifications.length !=
                (specValues?.length ?? 0)) {
              specValues = _currentAlgoInfo!.specifications
                  .map((s) => s.safeDefaultValue)
                  .toList();
            }
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _filterAlgorithms();
          }
        });
      }
    } else {
      if (_allAlgorithms.isNotEmpty) {
        _allAlgorithms = [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _filterAlgorithms();
          }
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Algorithm'),
        actions: [
          // Rescan Plugins button - only visible when connected to real hardware
          if (!isOffline)
            IconButton(
              icon: const Icon(
                Icons.sync,
                semanticLabel: 'Rescan Plugins on Hardware',
              ),
              tooltip: 'Rescan Plugins on Hardware',
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Rescanning plugins on hardware...'),
                    duration: Duration(seconds: 2),
                  ),
                );
                await context.read<DistingCubit>().rescanPlugins();
              },
            ),
          IconButton(
            icon: const Icon(
              Icons.refresh,
              semanticLabel: 'Refresh Algorithm List',
            ),
            tooltip: 'Refresh Algorithm List',
            onPressed: () {
              // Call the refresh method from DistingCubit
              context.read<DistingCubit>().refreshAlgorithms();

              // Show a brief feedback to user
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing algorithm list...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, semanticLabel: 'Help'),
            tooltip: 'Help',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Add Algorithm Help'),
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• Long press any algorithm to add/remove from favorites',
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Selecting a plugin automatically loads it when needed',
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Plugins show full specifications only after being loaded',
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: _isHelpAvailableForSelected
          ? FloatingActionButton(
              tooltip: 'View algorithm documentation',
              onPressed: () => _showDocumentation(selectedAlgorithmGuid!),
              child: const Icon(Icons.question_mark),
            )
          : null,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: switch (distingState) {
          DistingStateSynchronized() => () {
            if (_allAlgorithms.isEmpty && !_showFavoritesOnly) {
              // Show only if not in fav-only mode and list is truly empty
              return const Center(
                child: Text('No algorithms available in current state.'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Top Section with padding ---
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- Filter Header (wrapped in Material to prevent ink bleed) ---
                        Material(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // --- Search Row ---
                                DigitShortcutBlocker(
                                  child: TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      labelText: 'Search Algorithms',
                                      hintText: _showFavoritesOnly
                                          ? 'Search within favorites...'
                                          : 'Enter algorithm name...',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon:
                                          _searchController.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                semanticLabel: 'Clear search',
                                              ),
                                              tooltip: 'Clear search',
                                              onPressed: () {
                                                _searchController.clear();
                                              },
                                            )
                                          : null,
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // --- Filter Controls Row ---
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _showFavoritesOnly
                                            ? Icons.star
                                            : Icons.star_border,
                                        semanticLabel: 'Show Favorites Only',
                                      ),
                                      tooltip: 'Show Favorites Only',
                                      color: _showFavoritesOnly
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : null,
                                      onPressed: _toggleShowFavoritesOnly,
                                      style: const ButtonStyle(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.filter_alt_off,
                                        semanticLabel: 'Clear Filters',
                                      ),
                                      tooltip: 'Clear Filters',
                                      style: ButtonStyle(
                                        foregroundColor: WidgetStatePropertyAll(
                                          Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      onPressed: () {
                                        FocusScope.of(context).unfocus();
                                        setState(() {
                                          _searchController.clear();
                                          _showFavoritesOnly = false;
                                          _selectedCategories.clear();
                                          _selectedPluginType = _pluginTypeAll;
                                          _saveShowFavoritesOnlyState();
                                          _filterAlgorithms();
                                        });
                                      },
                                    ),
                                    _buildPluginTypeFilterButton(),
                                    _buildCategoryFilterButton(),
                                    _buildViewModeSelector(),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Showing ${_filteredAlgorithms.length} of ${_allAlgorithms.length} algorithms',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                                const Divider(),
                              ],
                            ),
                          ),
                        ),

                        // --- Algorithm Display (Expanded to take remaining space) ---
                        Expanded(
                          child: _filteredAlgorithms.isEmpty
                              ? Center(
                                  child: Text(
                                    _showFavoritesOnly
                                        ? (_favoriteGuids.isEmpty
                                              ? 'No algorithms marked as favorite.'
                                              : 'No favorites match "${_searchController.text}".')
                                        : 'No algorithms match "${_searchController.text}".',
                                  ),
                                )
                              : _buildAlgorithmView(),
                        ),
                      ],
                    ),
                  ),
                ),

                // --- Bottom Section with background (outside padding) ---
                SafeArea(
                  top: false,
                  child: Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      bottom: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- Action Buttons (fixed at the bottom) ---
                        AnimatedContainer(
                          duration: actionTransitionDuration,
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.only(
                            top: 16.0,
                            // Add extra padding when FAB is visible to prevent overlap
                            right: _isHelpAvailableForSelected ? 72.0 : 0.0,
                          ),
                          child: AnimatedSwitcher(
                            key: const ValueKey('algorithm_action_switcher'),
                            duration: actionTransitionDuration,
                            reverseDuration: actionTransitionReverseDuration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final offset = Tween<Offset>(
                                begin: const Offset(0, 0.06),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: offset,
                                  child: child,
                                ),
                              );
                            },
                            child: _buildActionButton(isOffline),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }(),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  // --- Plugin Type Filter Button (Dialog-based Select) ---
  Widget _buildPluginTypeFilterButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.extension, size: 18),
      label: Text(
        _selectedPluginType == _pluginTypeAll
            ? 'Plugin Type'
            : _selectedPluginType == _pluginTypeFactory
            ? 'Factory'
            : 'Community',
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () async {
        final selected = await showDialog<String>(
          context: context,
          builder: (context) {
            String tempSelected = _selectedPluginType;
            return StatefulBuilder(
              builder: (context, setStateDialog) => AlertDialog(
                title: const Text('Select Plugin Type'),
                content: RadioGroup<String>(
                  groupValue: tempSelected,
                  onChanged: (value) {
                    setStateDialog(() {
                      tempSelected = value!;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Radio<String>(value: _pluginTypeAll),
                        title: const Text('All Plugins'),
                        onTap: () {
                          setStateDialog(() {
                            tempSelected = _pluginTypeAll;
                          });
                        },
                      ),
                      ListTile(
                        leading: Radio<String>(value: _pluginTypeFactory),
                        title: const Text('Factory'),
                        subtitle: const Text(
                          'Algorithms with all lowercase GUIDs',
                        ),
                        onTap: () {
                          setStateDialog(() {
                            tempSelected = _pluginTypeFactory;
                          });
                        },
                      ),
                      ListTile(
                        leading: Radio<String>(value: _pluginTypeCommunity),
                        title: const Text('Community'),
                        subtitle: const Text(
                          'Algorithms with uppercase characters in GUID',
                        ),
                        onTap: () {
                          setStateDialog(() {
                            tempSelected = _pluginTypeCommunity;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, _selectedPluginType),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, tempSelected),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            );
          },
        );
        if (selected != null) {
          setState(() {
            _selectedPluginType = selected;
            _savePluginTypeState();
            _filterAlgorithms();
          });
        }
      },
    );
  }

  // --- View Mode Selector ---
  Widget _buildViewModeSelector() {
    return SegmentedButton<AlgorithmViewMode>(
      segments: const [
        ButtonSegment(
          value: AlgorithmViewMode.chipGrid,
          icon: Icon(Icons.grid_view, size: 18),
          label: Text('Chips'),
          tooltip: 'Chip Grid',
        ),
        ButtonSegment(
          value: AlgorithmViewMode.list,
          icon: Icon(Icons.view_list, size: 18),
          label: Text('List'),
          tooltip: 'List',
        ),
      ],
      selected: {_selectedViewMode},
      onSelectionChanged: (selected) {
        setState(() => _selectedViewMode = selected.first);
        _saveViewModeState();
        // Scroll to selected item after view rebuilds
        if (selectedAlgorithmGuid != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _scrollToSelectedItem();
          });
        }
      },
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }

  // --- Algorithm View (Conditional Rendering) ---
  Widget _buildAlgorithmView() {
    return Focus(
      focusNode: _viewFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: switch (_selectedViewMode) {
        AlgorithmViewMode.chipGrid => _buildChipGridView(),
        AlgorithmViewMode.list => _buildListView(),
      },
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_filteredAlgorithms.isEmpty) return KeyEventResult.ignored;

    // Initialize focus index if not set
    if (_focusedIndex < 0 && selectedAlgorithmGuid != null) {
      _focusedIndex = _filteredAlgorithms.indexWhere(
        (algo) => algo.guid == selectedAlgorithmGuid,
      );
    }
    if (_focusedIndex < 0) _focusedIndex = 0;

    int newIndex = _focusedIndex;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      newIndex = (_focusedIndex + 1).clamp(0, _filteredAlgorithms.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      newIndex = (_focusedIndex - 1).clamp(0, _filteredAlgorithms.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      if (_focusedIndex >= 0 && _focusedIndex < _filteredAlgorithms.length) {
        _selectAlgorithm(_filteredAlgorithms[_focusedIndex].guid);
        return KeyEventResult.handled;
      }
    } else {
      return KeyEventResult.ignored;
    }

    if (newIndex != _focusedIndex) {
      setState(() {
        _focusedIndex = newIndex;
      });
      _scrollToIndex(newIndex);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToSelectedItem() {
    if (selectedAlgorithmGuid == null) return;

    final index = _filteredAlgorithms.indexWhere(
      (algo) => algo.guid == selectedAlgorithmGuid,
    );
    if (index < 0) return;

    final ScrollController controller = switch (_selectedViewMode) {
      AlgorithmViewMode.chipGrid => _chipScrollController,
      AlgorithmViewMode.list => _listScrollController,
    };

    if (!controller.hasClients) return;

    final viewportHeight = controller.position.viewportDimension;
    final maxScroll = controller.position.maxScrollExtent;

    final double itemHeight = switch (_selectedViewMode) {
      AlgorithmViewMode.chipGrid => 48.0,
      AlgorithmViewMode.list => 120.0,
    };
    final targetOffset =
        (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);

    final scrollTo = targetOffset.clamp(0.0, maxScroll);

    controller.animateTo(
      scrollTo,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToIndex(int index) {
    if (_filteredAlgorithms.isEmpty) return;

    // Estimate item height based on view mode
    final double estimatedItemHeight = switch (_selectedViewMode) {
      AlgorithmViewMode.chipGrid => 40.0,
      AlgorithmViewMode.list => 72.0,
    };

    final ScrollController controller = switch (_selectedViewMode) {
      AlgorithmViewMode.chipGrid => _chipScrollController,
      AlgorithmViewMode.list => _listScrollController,
    };

    if (!controller.hasClients) return;

    // For list view, we can calculate exact position
    if (_selectedViewMode == AlgorithmViewMode.list) {
      final targetOffset = index * estimatedItemHeight;
      final viewportHeight = controller.position.viewportDimension;
      final maxScroll = controller.position.maxScrollExtent;
      final scrollTo =
          (targetOffset - viewportHeight / 2 + estimatedItemHeight / 2).clamp(
            0.0,
            maxScroll,
          );
      controller.animateTo(
        scrollTo,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
    }
  }

  // --- Chip Grid View (Original View) ---
  Widget _buildChipGridView() {
    return Scrollbar(
      controller: _chipScrollController,
      child: SingleChildScrollView(
        controller: _chipScrollController,
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: _filteredAlgorithms.map((algo) {
            final bool isSelected = selectedAlgorithmGuid == algo.guid;
            final bool isFavorite = _favoriteGuids.contains(algo.guid);
            final bool isCommunityPlugin = algo.guid != algo.guid.toLowerCase();
            return Semantics(
              button: true,
              selected: isSelected,
              label:
                  '${algo.name}${isFavorite ? ', favorite' : ''}${isCommunityPlugin ? ', community plugin' : ''}',
              hint: 'Double tap to ${isSelected ? 'deselect' : 'select'}',
              customSemanticsActions: {
                CustomSemanticsAction(
                  label: isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                ): () =>
                    _toggleFavorite(algo.guid),
              },
              child: GestureDetector(
                excludeFromSemantics: true,
                onLongPress: () => _toggleFavorite(algo.guid),
                child: ExcludeSemantics(
                  child: ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            algo.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isFavorite) ...[
                          const SizedBox(width: 4.0),
                          Icon(
                            Icons.star,
                            size: 16,
                            semanticLabel: 'Favorite',
                            color: isSelected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ],
                        if (isCommunityPlugin) ...[
                          const SizedBox(width: 4.0),
                          Icon(
                            Icons.extension,
                            size: 14,
                            semanticLabel: 'Community plugin',
                            color: isSelected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.secondary,
                          ),
                        ],
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      if (selected) {
                        _selectAlgorithm(algo.guid);
                      } else {
                        if (isSelected) {
                          _selectAlgorithm(null);
                        }
                      }
                    },
                    selectedColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // --- List View ---
  Widget _buildListView() {
    return Scrollbar(
      controller: _listScrollController,
      child: ListView.separated(
        controller: _listScrollController,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _filteredAlgorithms.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final algo = _filteredAlgorithms[index];
          final isSelected = algo.guid == selectedAlgorithmGuid;
          final isFavorite = _favoriteGuids.contains(algo.guid);
          final isCommunityPlugin = _isPlugin(algo.guid);
          final metadata = _metadataService.getAlgorithmByGuid(
            algo.guid.toLowerCase(),
          );

          return Semantics(
            button: true,
            selected: isSelected,
            label:
                '${algo.name}${isFavorite ? ', favorite' : ''}${isCommunityPlugin ? ', community plugin' : ''}',
            hint: 'Double tap to ${isSelected ? 'deselect' : 'select'}',
            customSemanticsActions: {
              CustomSemanticsAction(
                label: isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
              ): () =>
                  _toggleFavorite(algo.guid),
            },
            child: Material(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              child: ExcludeSemantics(
                child: InkWell(
                  onTap: () => _selectAlgorithm(isSelected ? null : algo.guid),
                  onLongPress: () => _toggleFavorite(algo.guid),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      algo.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (isCommunityPlugin)
                                    Icon(
                                      Icons.extension,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondary,
                                    ),
                                ],
                              ),
                              _buildListSubtitle(metadata, isCommunityPlugin),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite
                                ? Theme.of(context).colorScheme.tertiary
                                : null,
                            size: 20,
                            semanticLabel: isFavorite
                                ? 'Remove from favorites'
                                : 'Add to favorites',
                          ),
                          tooltip: isFavorite
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          onPressed: () => _toggleFavorite(algo.guid),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListSubtitle(
    AlgorithmMetadata? metadata,
    bool isCommunityPlugin,
  ) {
    // For community plugins, show simplified metadata
    final categories = isCommunityPlugin
        ? ['Community Plugin']
        : (metadata?.categories ?? <String>[]);
    final description = isCommunityPlugin
        ? 'Manually installed community plugin.'
        : (metadata?.description ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (categories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: categories
                  .take(3)
                  .map(
                    (cat) => Chip(
                      label: Text(cat, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
          ),
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  // --- Category Filter Button (Dialog-based Multi-Select) ---
  Widget _buildCategoryFilterButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.filter_list, size: 18),
      label: Text(
        _selectedCategories.isEmpty
            ? 'Category'
            : 'Category (${_selectedCategories.length})',
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () async {
        final selected = await showDialog<Set<String>>(
          context: context,
          builder: (context) {
            final tempSelected = Set<String>.from(_selectedCategories);
            return StatefulBuilder(
              builder: (context, setStateDialog) => AlertDialog(
                title: const Text('Select Categories'),
                content: SizedBox(
                  width: 320,
                  height: 300,
                  child: ListView(
                    shrinkWrap: true,
                    children: _allCategories.map((category) {
                      return CheckboxListTile(
                        value: tempSelected.contains(category),
                        title: Text(category),
                        onChanged: (checked) {
                          setStateDialog(() {
                            if (checked == true) {
                              tempSelected.add(category);
                            } else {
                              tempSelected.remove(category);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setStateDialog(() {
                        tempSelected.clear();
                      });
                    },
                    child: const Text('Clear'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, _selectedCategories),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, tempSelected),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            );
          },
        );
        if (selected != null) {
          setState(() {
            _selectedCategories = selected;
            _filterAlgorithms();
          });
        }
      },
    );
  }

  Widget _buildActionButton(bool isOffline) {
    if (_currentAlgoInfo == null) {
      return ElevatedButton(
        key: const ValueKey('select_algorithm_action'),
        onPressed: null,
        child: const Text('Select Algorithm'),
      );
    }

    final algorithm = _currentAlgoInfo!;

    // Show Load button for unloaded plugins
    if (_needsLoading(algorithm) && !isOffline) {
      return ElevatedButton(
        key: const ValueKey('load_plugin_action'),
        onPressed: () => _loadPlugin(algorithm.guid),
        child: const Text('Load Plugin'),
      );
    }

    final canAdd = specValues != null;
    final addBypassed = _shiftHeld;
    final addButton = ElevatedButton(
      onPressed: canAdd && !_isAddingAndStayingOpen
          ? () => _addAndClose(addBypassed: _isAddBypassedRequested)
          : null,
      child: Text(addBypassed ? 'Add Algorithm Bypassed' : 'Add Algorithm'),
    );

    if (!canAdd || !_canStayOpen()) {
      return KeyedSubtree(
        key: const ValueKey('add_algorithm_action'),
        child: addButton,
      );
    }

    return Row(
      key: const ValueKey('add_algorithm_actions'),
      children: [
        Expanded(child: addButton),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: _isAddingAndStayingOpen
                ? null
                : () => _addAndStayOpen(addBypassed: _isAddBypassedRequested),
            child: _buildAddAnotherContent(addBypassed: addBypassed),
          ),
        ),
      ],
    );
  }

  Widget _buildAddAnotherContent({required bool addBypassed}) {
    if (!_isSubmittingAddAndStayOpen) {
      return Text(addBypassed ? 'Add Another Bypassed' : 'Add Another');
    }

    final animationsDisabled =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      key: const ValueKey('add_another_progress_semantics'),
      container: true,
      liveRegion: true,
      label: 'Adding algorithm',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (animationsDisabled)
              const Icon(Icons.hourglass_top, size: 16)
            else
              SizedBox(
                key: const ValueKey('add_another_progress_indicator'),
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 8),
            const Text('Adding...'),
          ],
        ),
      ),
    );
  }

  bool _canStayOpen() {
    final state = context.read<DistingCubit>().state;
    if (state is! DistingStateSynchronized) return false;
    return state.slots.length < MCPConstants.maxSlots;
  }

  Future<List<int>?> _resolveSpecificationValues(
    AlgorithmInfo algorithm,
  ) async {
    final currentSpecValues =
        specValues ??
        algorithm.specifications.map((s) => s.safeDefaultValue).toList();
    if (algorithm.numSpecifications == 0) {
      return List<int>.from(currentSpecValues);
    }

    final selectedValues = await AlgorithmSpecificationDialog.show(
      context: context,
      algorithm: algorithm,
      initialValues: currentSpecValues,
      readOnly: false,
    );

    if (selectedValues != null && mounted) {
      setState(() {
        specValues = List<int>.from(selectedValues);
      });
    }

    return selectedValues;
  }

  Future<void> _addAndClose({required bool addBypassed}) async {
    final algorithm = _currentAlgoInfo;
    if (algorithm == null) return;

    final selectedValues = await _resolveSpecificationValues(algorithm);
    if (selectedValues == null || !mounted) return;

    Navigator.pop(context, {
      'algorithm': algorithm,
      'specValues': selectedValues,
      'addBypassed': addBypassed,
    });
  }

  Future<void> _addAndStayOpen({required bool addBypassed}) async {
    if (_isAddingAndStayingOpen) return;

    final algorithm = _currentAlgoInfo;
    if (algorithm == null) return;

    setState(() {
      _isAddingAndStayingOpen = true;
    });

    try {
      final specs = await _resolveSpecificationValues(algorithm);
      if (specs == null || !mounted) return;

      setState(() {
        _isSubmittingAddAndStayOpen = true;
      });

      final messenger = ScaffoldMessenger.of(context);
      final name = algorithm.name;
      try {
        await context.read<DistingCubit>().onAlgorithmSelected(
          algorithm,
          List<int>.from(specs),
          addBypassed: addBypassed,
        );
      } on AlgorithmAddFailedException {
        if (!mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text(algorithmAddFailedMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        SemanticsService.sendAnnouncement(
          View.of(context),
          algorithmAddFailedMessage,
          TextDirection.ltr,
        );
        return;
      } on AlgorithmAddBypassFailedException {
        if (!mounted) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text(algorithmAddBypassFailedMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        SemanticsService.sendAnnouncement(
          View.of(context),
          algorithmAddBypassFailedMessage,
          TextDirection.ltr,
        );
        _clearSelection();
        return;
      }

      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        '$name added',
        TextDirection.ltr,
      );
      _clearSelection();
    } finally {
      if (mounted) {
        setState(() {
          _isAddingAndStayingOpen = false;
          _isSubmittingAddAndStayOpen = false;
        });
      } else {
        _isAddingAndStayingOpen = false;
        _isSubmittingAddAndStayOpen = false;
      }
    }
  }
}
