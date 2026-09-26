import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/plugin_metadata_extractor.dart';
import 'package:nt_helper/services/plugin_update_checker.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/plugin_installations_dao.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:nt_helper/utils/app_directory.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:nt_helper/utils/build_config.dart';

/// GraphQL queries for the gallery
const int _galleryPluginPageSize = 50;
const Duration _defaultGraphqlRequestTimeout = Duration(seconds: 30);
const List<Duration> _defaultGraphqlRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
];
const Set<int> _retryableGraphqlStatusCodes = {
  HttpStatus.badGateway,
  HttpStatus.serviceUnavailable,
};

const String _getPluginsQuery = r'''
  query GetPlugins(
    $filter: PluginFilterInput
    $limit: Int!
    $offset: Int!
  ) {
    plugins(filter: $filter, limit: $limit, offset: $offset) {
      slug
      name
      description
      pluginType
      categoryId
      authorId
      repositoryOwner
      repositoryName
      repositoryUrl
      installationPath
      minFirmwareVersion
      verified
      featured
      featuredReason
      latestReleaseTag
      latestReleaseUrl
      selectedArtifactUrl
      guid
      isCollection
      collectionGuids
      createdAt
      updatedAt
      downloadCount
    }
  }
''';

const String _getCategoriesQuery = r'''
  query GetCategories {
    categories {
      id
      name
      sortOrder
    }
  }
''';

/// Result of extracting a plugin archive, separating plugin files from sample files
class ExtractedArchiveContents {
  /// Plugin files (*.o, *.lua, *.3pot) to be installed
  final List<MapEntry<String, List<int>>> pluginFiles;

  /// Sample files from the samples/ directory
  final List<MapEntry<String, List<int>>> sampleFiles;

  const ExtractedArchiveContents({
    required this.pluginFiles,
    required this.sampleFiles,
  });

  /// Whether this archive contains sample files
  bool get hasSamples => sampleFiles.isNotEmpty;

  /// Total number of files in the archive
  int get totalFileCount => pluginFiles.length + sampleFiles.length;
}

/// Result of installing sample files for a plugin
class SampleInstallationResult {
  /// Sample files that were successfully installed
  final List<String> installedSamples;

  /// Sample files that were skipped because they already exist
  final List<String> skippedSamples;

  /// Sample files that failed to install, with error messages
  final Map<String, String> failedSamples;

  const SampleInstallationResult({
    this.installedSamples = const [],
    this.skippedSamples = const [],
    this.failedSamples = const {},
  });

  /// Total number of samples that were in the package
  int get totalSamples =>
      installedSamples.length + skippedSamples.length + failedSamples.length;

  /// Whether any samples failed to install
  bool get hasFailures => failedSamples.isNotEmpty;

  /// Whether any samples were installed or skipped (not all failed)
  bool get hasSuccesses =>
      installedSamples.isNotEmpty || skippedSamples.isNotEmpty;

  /// Number of samples that were actually installed (not skipped or failed)
  int get installedCount => installedSamples.length;

  /// Number of samples skipped because they already existed
  int get skippedCount => skippedSamples.length;

  /// Number of samples that failed to install
  int get failedCount => failedSamples.length;
}

/// Callback type for installing a single sample file to the SD card.
/// Returns `true` if installed, `false` if skipped (already exists).
/// Throws an exception on failure.
typedef SampleInstallCallback =
    Future<bool> Function(
      String targetPath,
      Uint8List data, {
      Function(double)? onProgress,
    });

/// Service for managing the plugin gallery
class GalleryService {
  final SettingsService _settingsService;
  final AppDatabase? _database;
  final Duration _graphqlRequestTimeout;
  final List<Duration> _graphqlRetryDelays;
  PluginUpdateChecker? _updateChecker;
  Gallery? _cachedGallery;

  /// Returns the cached gallery if available, without triggering a fetch.
  Gallery? get cachedGallery => _cachedGallery;
  DateTime? _lastFetch;
  DateTime? _persistedCacheTimestamp;
  final Duration _cacheTimeout = const Duration(hours: 1);
  final Duration _persistedCacheStaleTimeout = const Duration(hours: 24);
  static const String _cacheFileName = 'gallery_cache.json';

  /// GUID to GalleryPlugin lookup map for fast plugin discovery
  final Map<String, GalleryPlugin> _guidLookup = {};

  final List<QueuedPlugin> _installQueue = [];
  final StreamController<List<QueuedPlugin>> _queueController =
      StreamController<List<QueuedPlugin>>.broadcast();

  /// Constructor with optional database for installation tracking
  GalleryService({
    required SettingsService settingsService,
    AppDatabase? database,
    Duration graphqlRequestTimeout = _defaultGraphqlRequestTimeout,
    List<Duration> graphqlRetryDelays = _defaultGraphqlRetryDelays,
  }) : _settingsService = settingsService,
       _database = database,
       _graphqlRequestTimeout = graphqlRequestTimeout,
       _graphqlRetryDelays = List.unmodifiable(graphqlRetryDelays) {
    // Initialize update checker if database is available
    if (_database != null) {
      _updateChecker = PluginUpdateChecker(
        database: _database,
        galleryService: this,
      );
    }
  }

  /// Stream of install queue updates
  Stream<List<QueuedPlugin>> get queueStream => _queueController.stream;

  /// Current install queue
  List<QueuedPlugin> get installQueue => List.unmodifiable(_installQueue);

  /// Current gallery URL (legacy REST endpoint)
  String get galleryUrl => _settingsService.galleryUrl;

  /// Current GraphQL endpoint URL
  String get graphqlEndpoint => _settingsService.graphqlEndpoint;

  /// Force clear the cache (useful for testing new URLs)
  void clearCache() {
    _invalidateCache();
  }

  /// Fetch gallery data with caching via GraphQL
  ///
  /// Uses a multi-tier caching strategy:
  /// 1. Memory cache (1 hour TTL)
  /// 2. Persisted file cache (24 hour stale threshold)
  /// 3. Fresh fetch from GraphQL API
  Future<Gallery> fetchGallery({bool forceRefresh = false}) async {
    // Return memory cached data if valid and not forcing refresh
    if (!forceRefresh &&
        _cachedGallery != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheTimeout) {
      return _cachedGallery!;
    }

    // Try to load from persisted cache if memory cache is empty or stale
    if (!forceRefresh && _cachedGallery == null) {
      final persistedGallery = await _loadFromPersistedCache();
      if (persistedGallery != null) {
        _cachedGallery = persistedGallery;
        _lastFetch = _persistedCacheTimestamp;

        // Build GUID lookup from cached data
        _buildGuidLookup(persistedGallery);

        // Check if persisted cache is stale and trigger background refresh
        if (_persistedCacheTimestamp != null &&
            DateTime.now().difference(_persistedCacheTimestamp!) >
                _persistedCacheStaleTimeout) {
          // Background refresh - don't await
          _refreshInBackground();
        }

        return persistedGallery;
      }
    }

    try {
      // Fetch plugins and categories via GraphQL
      final plugins = await _fetchPluginsViaGraphQL();
      final categories = await _fetchCategoriesViaGraphQL();

      final gallery = _mapGraphQLToGallery(plugins, categories);

      _cachedGallery = gallery;
      _lastFetch = DateTime.now();

      // Build GUID lookup from fetched data
      _buildGuidLookup(gallery);

      // Persist to file cache
      await _saveToPersistedCache(gallery);

      return gallery;
    } catch (e) {
      // On network failure, try to return persisted cache if available
      if (_cachedGallery != null) {
        return _cachedGallery!;
      }

      final persistedGallery = await _loadFromPersistedCache();
      if (persistedGallery != null) {
        _cachedGallery = persistedGallery;
        _buildGuidLookup(persistedGallery);
        return persistedGallery;
      }

      if (e is GalleryException) rethrow;
      throw GalleryException('Network error: ${e.toString()}');
    }
  }

  /// Refresh gallery data in background without blocking
  Future<void> _refreshInBackground() async {
    try {
      final plugins = await _fetchPluginsViaGraphQL();
      final categories = await _fetchCategoriesViaGraphQL();

      final gallery = _mapGraphQLToGallery(plugins, categories);

      _cachedGallery = gallery;
      _lastFetch = DateTime.now();

      // Rebuild GUID lookup with fresh data
      _buildGuidLookup(gallery);

      await _saveToPersistedCache(gallery);
    } catch (e) {
      // Silently fail background refresh - we still have cached data
    }
  }

  /// Get the cache file path
  Future<File> _getCacheFile() async {
    final directory = await getAppDirectory();
    return File(path.join(directory.path, _cacheFileName));
  }

  /// Save gallery data to persisted file cache
  Future<void> _saveToPersistedCache(Gallery gallery) async {
    try {
      final file = await _getCacheFile();
      final timestamp = DateTime.now().toIso8601String();

      final cacheData = {'timestamp': timestamp, 'gallery': gallery.toJson()};

      await file.writeAsString(json.encode(cacheData));
      _persistedCacheTimestamp = DateTime.now();
    } catch (e) {
      // Silently fail cache write - not critical
    }
  }

  /// Load gallery data from persisted file cache
  Future<Gallery?> _loadFromPersistedCache() async {
    try {
      final file = await _getCacheFile();

      if (!await file.exists()) {
        return null;
      }

      final contents = await file.readAsString();
      final cacheData = json.decode(contents) as Map<String, dynamic>;

      final timestampStr = cacheData['timestamp'] as String?;
      if (timestampStr != null) {
        _persistedCacheTimestamp = DateTime.parse(timestampStr);
      }

      final galleryJson = cacheData['gallery'] as Map<String, dynamic>;
      return Gallery.fromJson(galleryJson);
    } catch (e) {
      // Return null if cache is corrupted or unreadable
      return null;
    }
  }

  /// Build the GUID lookup map from gallery data
  ///
  /// Indexes plugins by:
  /// - Single plugins: their `guid` field
  /// - Collection plugins: each GUID in `collectionGuids`
  void _buildGuidLookup(Gallery gallery) {
    _guidLookup.clear();
    for (final plugin in gallery.plugins) {
      // Index single plugins by their GUID
      if (plugin.guid != null && plugin.guid!.isNotEmpty) {
        _guidLookup[plugin.guid!] = plugin;
      }
      // Index collection plugins by each GUID in collectionGuids
      for (final guid in plugin.collectionGuids) {
        _guidLookup[guid] = plugin;
      }
    }
  }

  /// Initialize the GUID lookup from a gallery (for testing purposes)
  @visibleForTesting
  void initializeGuidLookup(Gallery gallery) {
    _buildGuidLookup(gallery);
  }

  /// Extract archive contents for testing purposes
  @visibleForTesting
  Future<ExtractedArchiveContents> extractArchiveForTesting(
    List<int> archiveBytes,
    GalleryPlugin plugin, {
    QueuedPlugin? queuedPlugin,
  }) {
    return _extractArchive(archiveBytes, plugin, queuedPlugin: queuedPlugin);
  }

  /// Check if a file path is a sample file (for testing purposes)
  @visibleForTesting
  static bool isSampleFileForTesting(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return lowerPath.startsWith('samples/') ||
        lowerPath.startsWith('/samples/');
  }

  /// Look up a plugin by its 4-character GUID
  ///
  /// Returns the GalleryPlugin matching the GUID, or null if not found.
  /// For C++ collections, each individual algorithm GUID maps to the parent collection.
  GalleryPlugin? getPluginByGuid(String guid) {
    // Try exact match first
    if (_guidLookup.containsKey(guid)) {
      return _guidLookup[guid];
    }
    // Try case-insensitive match as fallback (GUIDs should be consistent but be lenient)
    final upperGuid = guid.toUpperCase();
    for (final entry in _guidLookup.entries) {
      if (entry.key.toUpperCase() == upperGuid) {
        return entry.value;
      }
    }
    return null;
  }

  /// Fetch plugins via GraphQL API
  Future<List<dynamic>> _fetchPluginsViaGraphQL() async {
    final plugins = <dynamic>[];
    var offset = 0;

    while (true) {
      final response = await _postGraphQL(
        query: _getPluginsQuery,
        variables: {
          'filter': {'verified': true},
          'limit': _galleryPluginPageSize,
          'offset': offset,
        },
      );

      if (response.statusCode != 200) {
        throw GalleryException(
          'GraphQL request failed: HTTP ${response.statusCode}',
        );
      }

      // Explicitly decode as UTF-8 to handle special characters correctly
      // (http package defaults to latin-1 if charset not specified in headers)
      final jsonData =
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (jsonData.containsKey('errors')) {
        throw GalleryException('GraphQL error: ${jsonData['errors']}');
      }

      final page = jsonData['data']['plugins'] as List<dynamic>;
      plugins.addAll(page);

      if (page.length < _galleryPluginPageSize) {
        return plugins;
      }

      offset += _galleryPluginPageSize;
    }
  }

  /// Fetch categories via GraphQL API
  Future<List<dynamic>> _fetchCategoriesViaGraphQL() async {
    final response = await _postGraphQL(query: _getCategoriesQuery);

    if (response.statusCode != 200) {
      throw GalleryException(
        'GraphQL request failed: HTTP ${response.statusCode}',
      );
    }

    // Explicitly decode as UTF-8 to handle special characters correctly
    final jsonData =
        json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (jsonData.containsKey('errors')) {
      throw GalleryException('GraphQL error: ${jsonData['errors']}');
    }

    return jsonData['data']['categories'] as List<dynamic>;
  }

  Future<http.Response> _postGraphQL({
    required String query,
    Map<String, dynamic>? variables,
  }) async {
    final requestBody = <String, dynamic>{'query': query};
    if (variables != null) {
      requestBody['variables'] = variables;
    }

    for (var attempt = 0; ; attempt++) {
      final hasRetryRemaining = attempt < _graphqlRetryDelays.length;

      try {
        final response = await http
            .post(
              Uri.parse(graphqlEndpoint),
              headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json; charset=utf-8',
                'Accept-Charset': 'utf-8',
                'User-Agent': 'Disting-NT-Helper/1.0',
              },
              body: json.encode(requestBody),
            )
            .timeout(_graphqlRequestTimeout);

        if (!_retryableGraphqlStatusCodes.contains(response.statusCode) ||
            !hasRetryRemaining) {
          return response;
        }
      } on TimeoutException {
        if (!hasRetryRemaining) rethrow;
      }

      await Future.delayed(_graphqlRetryDelays[attempt]);
    }
  }

  /// Map GraphQL response to Gallery model
  Gallery _mapGraphQLToGallery(
    List<dynamic> pluginsData,
    List<dynamic> categoriesData,
  ) {
    // Map categories
    final categories = categoriesData.map((cat) {
      return PluginCategory(
        id: cat['id'] as String,
        name: cat['name'] as String,
      );
    }).toList();

    // Build authors map from plugin data (use repositoryOwner as author)
    final Map<String, PluginAuthor> authors = {};

    // Map plugins
    final plugins = pluginsData.map((p) {
      final repositoryOwner = p['repositoryOwner'] as String? ?? '';
      final repositoryName = p['repositoryName'] as String? ?? '';
      final repositoryUrl = p['repositoryUrl'] as String? ?? '';

      // Add author to map if not already present
      if (repositoryOwner.isNotEmpty && !authors.containsKey(repositoryOwner)) {
        authors[repositoryOwner] = PluginAuthor(name: repositoryOwner);
      }

      // Map plugin type (LUA, THREEPOT, CPP -> lua, threepot, cpp)
      final pluginTypeStr = (p['pluginType'] as String? ?? 'LUA').toLowerCase();
      final pluginType = switch (pluginTypeStr) {
        'lua' => GalleryPluginType.lua,
        'threepot' => GalleryPluginType.threepot,
        'cpp' => GalleryPluginType.cpp,
        _ => GalleryPluginType.lua,
      };

      // Parse dates safely
      DateTime? createdAt;
      DateTime? updatedAt;
      if (p['createdAt'] != null) {
        createdAt = DateTime.tryParse(p['createdAt'] as String);
      }
      if (p['updatedAt'] != null) {
        updatedAt = DateTime.tryParse(p['updatedAt'] as String);
      }

      // Parse collectionGuids safely
      final collectionGuidsRaw = p['collectionGuids'] as List<dynamic>?;
      final collectionGuids =
          collectionGuidsRaw?.map((g) => g as String).toList() ?? [];

      return GalleryPlugin(
        id: p['slug'] as String? ?? '',
        name: p['name'] as String? ?? '',
        description: p['description'] as String? ?? '',
        longDescription: p['description'] as String?,
        type: pluginType,
        category: p['categoryId'] as String?,
        author: repositoryOwner,
        repository: PluginRepository(
          owner: repositoryOwner,
          name: repositoryName,
          url: repositoryUrl,
        ),
        releases: PluginReleases(
          latest: p['latestReleaseTag'] as String? ?? '',
        ),
        installation: PluginInstallation(
          targetPath: p['installationPath'] as String? ?? '',
          downloadUrl: p['selectedArtifactUrl'] as String?,
        ),
        compatibility: PluginCompatibility(
          minFirmwareVersion: p['minFirmwareVersion'] as String?,
        ),
        metrics: PluginMetrics(downloads: (p['downloadCount'] as int?) ?? 0),
        featured: p['featured'] as bool? ?? false,
        verified: p['verified'] as bool? ?? false,
        isCollection: p['isCollection'] as bool? ?? false,
        guid: p['guid'] as String?,
        collectionGuids: collectionGuids,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }).toList();

    return Gallery(
      version: '2.0.0',
      lastUpdated: DateTime.now(),
      metadata: const GalleryMetadata(
        name: 'Disting NT Plugin Gallery',
        description: 'Community plugins for the Disting NT',
        maintainer: GalleryMaintainer(name: 'NT Gallery'),
      ),
      categories: categories,
      authors: authors,
      plugins: plugins,
    );
  }

  /// Search plugins with optional filters
  List<GalleryPlugin> searchPlugins(
    Gallery gallery, {
    String? query,
    String? category,
    GalleryPluginType? type,
    bool? featured,
    bool? verified,
  }) {
    var plugins = gallery.plugins;

    // Filter by search query
    if (query != null && query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      plugins = plugins.where((plugin) {
        return plugin.name.toLowerCase().contains(lowerQuery) ||
            plugin.description.toLowerCase().contains(lowerQuery) ||
            plugin.tags.any((tag) => tag.toLowerCase().contains(lowerQuery)) ||
            plugin.author.toLowerCase().contains(lowerQuery);
      }).toList();
    }

    // Filter by category
    if (category != null && category.isNotEmpty) {
      plugins = plugins.where((plugin) => plugin.category == category).toList();
    }

    // Filter by type
    if (type != null) {
      plugins = plugins.where((plugin) => plugin.type == type).toList();
    }

    // Filter by featured status
    if (featured == true) {
      plugins = plugins.where((plugin) => plugin.featured).toList();
    }

    // Filter by verified status
    if (verified == true) {
      plugins = plugins.where((plugin) => plugin.verified).toList();
    }

    return plugins;
  }

  /// Add plugin to install queue with metadata extraction
  Future<void> addToQueue(
    GalleryPlugin plugin, {
    String version = 'latest',
  }) async {
    // Check if already in queue
    final existingIndex = _installQueue.indexWhere(
      (q) => q.plugin.id == plugin.id,
    );

    QueuedPlugin queuedPlugin;

    if (existingIndex >= 0) {
      // Update existing entry
      queuedPlugin = _installQueue[existingIndex].copyWith(
        selectedVersion: version,
        status: QueuedPluginStatus.queued,
        errorMessage: null,
        progress: null,
      );
      _installQueue[existingIndex] = queuedPlugin;
    } else {
      // Add new entry
      final bool isCollection = await isActualCollection(
        plugin,
        downloadPluginArchive,
      );
      queuedPlugin = QueuedPlugin(
        plugin: plugin,
        selectedVersion: version,
        isCollection: isCollection,
      );
      _installQueue.add(queuedPlugin);
    }

    _notifyQueueChanged();

    // Extract metadata asynchronously to determine if it's a collection
    _extractPluginMetadata(queuedPlugin);
  }

  /// Extract plugin metadata to determine if it's a collection
  Future<void> _extractPluginMetadata(QueuedPlugin queuedPlugin) async {
    try {
      final plugin = queuedPlugin.plugin;

      // Skip if already processed or if it's clearly not a collection
      if (queuedPlugin.selectedPlugins.isNotEmpty ||
          !queuedPlugin.isCollection) {
        return;
      }

      // Update status to analyzing
      final queueIndex = _installQueue.indexWhere(
        (q) => q.plugin.id == plugin.id,
      );
      if (queueIndex >= 0) {
        _installQueue[queueIndex] = _installQueue[queueIndex].copyWith(
          status: QueuedPluginStatus.analyzing,
        );
        _notifyQueueChanged();
      }

      // Download the plugin archive
      final archiveBytes = await downloadPluginArchive(
        plugin,
        queuedPlugin.selectedVersion,
      );

      // Count installable plugins to determine if it's a collection
      final pluginCount = await PluginMetadataExtractor.countInstallablePlugins(
        archiveBytes,
        plugin,
      );

      if (pluginCount > 1) {
        // This is a collection - extract the plugin list
        final collectionPlugins =
            await PluginMetadataExtractor.extractPluginsFromArchive(
              archiveBytes,
              plugin,
            );

        // Filter to only include installable plugins (.o, .lua, .3pot files)
        final installablePlugins = collectionPlugins
            .where((p) => const ['o', 'lua', '3pot'].contains(p.fileType))
            .map((p) => p.copyWith(selected: true)) // Default to all selected
            .toList();

        // Update the queued plugin with the collection data
        final queueIndex = _installQueue.indexWhere(
          (q) => q.plugin.id == plugin.id,
        );
        if (queueIndex >= 0) {
          _installQueue[queueIndex] = _installQueue[queueIndex].copyWith(
            selectedPlugins: installablePlugins,
            status: QueuedPluginStatus.queued,
          );
          _notifyQueueChanged();
        }
      } else {
        // Reset status back to queued for singular plugins
        final queueIndex = _installQueue.indexWhere(
          (q) => q.plugin.id == plugin.id,
        );
        if (queueIndex >= 0) {
          _installQueue[queueIndex] = _installQueue[queueIndex].copyWith(
            status: QueuedPluginStatus.queued,
          );
          _notifyQueueChanged();
        }
      }
    } catch (e) {
      // Don't fail the queue operation if metadata extraction fails
      // The plugin will be treated as a singular plugin
    }
  }

  /// Remove plugin from install queue
  void removeFromQueue(String pluginId) {
    _installQueue.removeWhere((q) => q.plugin.id == pluginId);
    _notifyQueueChanged();
  }

  /// Clear all plugins from install queue
  void clearQueue() {
    _installQueue.clear();
    _notifyQueueChanged();
  }

  /// Check if plugin is in queue
  bool isInQueue(String pluginId) {
    return _installQueue.any((q) => q.plugin.id == pluginId);
  }

  /// Get queued plugin by ID
  QueuedPlugin? getQueuedPlugin(String pluginId) {
    try {
      return _installQueue.firstWhere((q) => q.plugin.id == pluginId);
    } catch (e) {
      return null;
    }
  }

  /// Update selected plugins for a queued plugin collection
  void updateQueuedPluginSelection(
    String pluginId,
    List<CollectionPlugin> selectedPlugins,
  ) {
    final index = _installQueue.indexWhere((q) => q.plugin.id == pluginId);
    if (index >= 0) {
      _installQueue[index] = _installQueue[index].copyWith(
        selectedPlugins: selectedPlugins,
      );
      _notifyQueueChanged();
    } else {}
  }

  /// Download plugin archive for a specific version
  Future<List<int>> downloadPluginArchive(
    GalleryPlugin plugin,
    String version,
  ) async {
    if (kPlayStoreBuild) {
      throw UnsupportedError('Not available on Play Store build');
    }
    final release = plugin.getVersionTag(version);
    final downloadUrl = await _getDownloadUrl(plugin, release);

    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw GalleryException(
        'Failed to download plugin archive: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    return response.bodyBytes;
  }

  /// Install a single plugin directly (no queue), reporting progress via callbacks.
  ///
  /// If [cachedArchiveBytes] is provided, skips downloading.
  /// [selectedPlugins] filters which files to install from a collection archive.
  Future<SampleInstallationResult?> installPlugin(
    GalleryPlugin plugin, {
    required Function(
      String fileName,
      Uint8List fileData, {
      Function(double)? onProgress,
      String? galleryPluginId,
      String? galleryPluginVersion,
    })
    distingInstallPlugin,
    SampleInstallCallback? distingInstallSample,
    Function(PluginInstallPhase phase, double progress)? onProgress,
    List<int>? cachedArchiveBytes,
    List<CollectionPlugin>? selectedPlugins,
    void Function(PluginCleanupOutcome outcome)? onCleanupOutcome,
  }) async {
    final version = plugin.getVersionTag('latest');

    // Download
    onProgress?.call(PluginInstallPhase.downloading, 0.0);
    List<int> fileBytes;
    if (cachedArchiveBytes != null) {
      fileBytes = cachedArchiveBytes;
      onProgress?.call(PluginInstallPhase.downloading, 0.5);
    } else {
      final downloadUrl = await _getDownloadUrl(plugin, version);
      fileBytes = await _downloadWithProgress(downloadUrl, (progress) {
        onProgress?.call(PluginInstallPhase.downloading, progress * 0.5);
      });
    }

    // Determine file type
    final downloadUrl = cachedArchiveBytes != null
        ? 'archive.zip'
        : await _getDownloadUrl(plugin, version);
    final fileName = path.basename(Uri.parse(downloadUrl).path);
    final fileExtension = path.extension(fileName).toLowerCase();

    List<MapEntry<String, List<int>>> filesToInstall;
    ExtractedArchiveContents? extractedContents;

    if (fileExtension == '.zip' || cachedArchiveBytes != null) {
      onProgress?.call(PluginInstallPhase.extracting, 0.5);

      // Build a temporary QueuedPlugin-like filter using selectedPlugins
      // We pass selectedPlugins directly to _extractArchive via a synthetic QueuedPlugin
      QueuedPlugin? filterPlugin;
      if (selectedPlugins != null && selectedPlugins.isNotEmpty) {
        filterPlugin = QueuedPlugin(
          plugin: plugin,
          selectedVersion: 'latest',
          isCollection: true,
          selectedPlugins: selectedPlugins,
        );
      }

      extractedContents = await _extractArchive(
        fileBytes,
        plugin,
        queuedPlugin: filterPlugin,
      );
      filesToInstall = extractedContents.pluginFiles;
    } else if (_isRawPluginFile(fileExtension)) {
      filesToInstall = [MapEntry(fileName, fileBytes)];
    } else {
      throw GalleryException('Unsupported file type: $fileExtension');
    }

    // Install
    onProgress?.call(PluginInstallPhase.installing, 0.6);
    final cleanupOutcomes = await _installFilesViaDisting(
      filesToInstall,
      plugin,
      version,
      distingInstallPlugin,
      (uploadProgress) {
        onProgress?.call(
          PluginInstallPhase.installing,
          0.6 + (uploadProgress * 0.2),
        );
      },
    );
    cleanupOutcomes.forEach(onCleanupOutcome ?? (_) {});

    // Install samples if present
    SampleInstallationResult? sampleResult;
    if (extractedContents != null &&
        extractedContents.hasSamples &&
        distingInstallSample != null) {
      sampleResult = await _installSampleFiles(
        extractedContents.sampleFiles,
        distingInstallSample,
        (sampleProgress) {
          onProgress?.call(
            PluginInstallPhase.installing,
            0.8 + (sampleProgress * 0.2),
          );
        },
      );
    }

    onProgress?.call(PluginInstallPhase.completed, 1.0);
    return sampleResult;
  }

  /// Install all plugins in the queue using Disting upload functionality
  ///
  /// [distingInstallPlugin] - Callback to install plugin files (.o, .lua, .3pot)
  /// [distingInstallSample] - Optional callback to install sample files.
  ///   If provided, sample files in plugin zips will be installed to /samples/.
  ///   The callback should return true if installed, false if skipped (file exists).
  Future<void> installQueuedPlugins({
    required Function(
      String fileName,
      Uint8List fileData, {
      Function(double)? onProgress,
      String? galleryPluginId,
      String? galleryPluginVersion,
    })
    distingInstallPlugin,
    SampleInstallCallback? distingInstallSample,
    Function(QueuedPlugin)? onPluginStart,
    Function(QueuedPlugin, double)? onProgress,
    Function(QueuedPlugin)? onPluginComplete,
    Function(QueuedPlugin, String)? onPluginError,
    Function(QueuedPlugin, SampleInstallationResult)? onSampleInstallComplete,
    Function(QueuedPlugin, PluginCleanupOutcome)? onCleanupOutcome,
  }) async {
    final pluginsToInstall = _installQueue
        .where((q) => q.status == QueuedPluginStatus.queued)
        .toList();

    for (final queuedPlugin in pluginsToInstall) {
      try {
        onPluginStart?.call(queuedPlugin);

        // Track installation details for database recording
        SampleInstallationResult? sampleResult;

        sampleResult = await _installSinglePluginViaDisting(
          queuedPlugin,
          distingInstallPlugin,
          distingInstallSample: distingInstallSample,
          onProgress: onProgress,
          onInstallationDetails: (files, bytes) {
            // Installation details tracked
          },
          onCleanupOutcome: onCleanupOutcome == null
              ? null
              : (outcome) => onCleanupOutcome(queuedPlugin, outcome),
        );

        // Notify about sample installation results
        if (sampleResult != null && sampleResult.totalSamples > 0) {
          onSampleInstallComplete?.call(queuedPlugin, sampleResult);
        }

        _updateQueuedPlugin(
          queuedPlugin.plugin.id,
          status: QueuedPluginStatus.completed,
        );

        // Note: Database recording is now handled by DistingCubit.installPlugin()
        // which records all installs (gallery and local) in one place using the
        // installation path as the primary identifier.

        onPluginComplete?.call(queuedPlugin);

        // Remove successfully completed plugin from queue
        removeFromQueue(queuedPlugin.plugin.id);
      } catch (e) {
        final errorMessage = e.toString();
        _updateQueuedPlugin(
          queuedPlugin.plugin.id,
          status: QueuedPluginStatus.failed,
          errorMessage: errorMessage,
        );
        onPluginError?.call(queuedPlugin, errorMessage);

        // Note: No database recording for failed installs - the cubit won't
        // record if the upload fails, which is the desired behavior.

        // Keep failed plugin in queue so user can see the error message
        // They can manually remove it if desired
      }
    }
  }

  /// Install a single plugin using Disting upload functionality
  ///
  /// Returns [SampleInstallationResult] if samples were processed, null otherwise.
  Future<SampleInstallationResult?> _installSinglePluginViaDisting(
    QueuedPlugin queuedPlugin,
    Function(
      String fileName,
      Uint8List fileData, {
      Function(double)? onProgress,
      String? galleryPluginId,
      String? galleryPluginVersion,
    })
    distingInstallPlugin, {
    SampleInstallCallback? distingInstallSample,
    Function(QueuedPlugin, double)? onProgress,
    Function(int, int)? onInstallationDetails,
    void Function(PluginCleanupOutcome outcome)? onCleanupOutcome,
  }) async {
    final plugin = queuedPlugin.plugin;
    final version = plugin.getVersionTag(queuedPlugin.selectedVersion);

    // Update status to downloading
    _updateQueuedPlugin(
      plugin.id,
      status: QueuedPluginStatus.downloading,
      progress: 0.0,
    );

    // Download the release file
    final downloadUrl = await _getDownloadUrl(plugin, version);
    final fileBytes = await _downloadWithProgress(downloadUrl, (progress) {
      _updateQueuedPlugin(
        plugin.id,
        progress: progress * 0.5,
      ); // 50% for download (reduced to make room for samples)
      onProgress?.call(queuedPlugin, progress * 0.5);
    });

    // Determine file type from download URL
    final downloadUri = Uri.parse(downloadUrl);
    final fileName = path.basename(downloadUri.path);
    final fileExtension = path.extension(fileName).toLowerCase();

    List<MapEntry<String, List<int>>> filesToInstall;
    ExtractedArchiveContents? extractedContents;

    if (fileExtension == '.zip') {
      // Update status to extracting for zip files
      _updateQueuedPlugin(
        plugin.id,
        status: QueuedPluginStatus.extracting,
        progress: 0.5,
      );

      // Extract the zip archive
      extractedContents = await _extractArchive(
        fileBytes,
        plugin,
        queuedPlugin: queuedPlugin,
      );
      filesToInstall = extractedContents.pluginFiles;
    } else if (_isRawPluginFile(fileExtension)) {
      // Handle raw plugin files (.o, .lua, .3pot)

      // Create a single file entry for installation
      filesToInstall = [MapEntry(fileName, fileBytes)];
    } else {
      throw GalleryException(
        'Unsupported file type: $fileExtension. Supported types are: .zip, .o, .lua, .3pot',
      );
    }

    // Update status to installing
    _updateQueuedPlugin(
      plugin.id,
      status: QueuedPluginStatus.installing,
      progress: 0.6,
    );

    // Install plugin files using Disting upload functionality
    final cleanupOutcomes = await _installFilesViaDisting(
      filesToInstall,
      plugin,
      version,
      distingInstallPlugin,
      (uploadProgress) {
        // Plugin files take 60-80% of progress
        final totalProgress = 0.6 + (uploadProgress * 0.2);
        _updateQueuedPlugin(plugin.id, progress: totalProgress);
        onProgress?.call(queuedPlugin, totalProgress);
      },
    );
    cleanupOutcomes.forEach(onCleanupOutcome ?? (_) {});

    // Install sample files if present and callback is provided
    SampleInstallationResult? sampleResult;
    if (extractedContents != null &&
        extractedContents.hasSamples &&
        distingInstallSample != null) {
      sampleResult = await _installSampleFiles(
        extractedContents.sampleFiles,
        distingInstallSample,
        (sampleProgress) {
          // Sample files take 80-100% of progress
          final totalProgress = 0.8 + (sampleProgress * 0.2);
          _updateQueuedPlugin(plugin.id, progress: totalProgress);
          onProgress?.call(queuedPlugin, totalProgress);
        },
      );
    }

    // Update progress to complete
    _updateQueuedPlugin(plugin.id, progress: 1.0);

    // Notify installation details
    if (onInstallationDetails != null) {
      final totalBytes = fileBytes.length;
      onInstallationDetails(filesToInstall.length, totalBytes);
    }

    return sampleResult;
  }

  /// Install sample files to the SD card
  ///
  /// Returns [SampleInstallationResult] with details about installed/skipped/failed samples.
  Future<SampleInstallationResult> _installSampleFiles(
    List<MapEntry<String, List<int>>> sampleFiles,
    SampleInstallCallback installSample,
    Function(double)? onProgress,
  ) async {
    final installedSamples = <String>[];
    final skippedSamples = <String>[];
    final failedSamples = <String, String>{};

    int filesProcessed = 0;

    for (final sampleEntry in sampleFiles) {
      final samplePath = sampleEntry.key;
      final sampleData = Uint8List.fromList(sampleEntry.value);

      // Transform path: "samples/x.wav" -> "/samples/x.wav"
      final targetPath = _getSampleTargetPath(samplePath);

      try {
        final wasInstalled = await _installSampleWithRetry(
          targetPath,
          sampleData,
          installSample,
          onProgress: (fileProgress) {
            final overallProgress =
                (filesProcessed + fileProgress) / sampleFiles.length;
            onProgress?.call(overallProgress);
          },
        );

        if (wasInstalled) {
          installedSamples.add(targetPath);
        } else {
          skippedSamples.add(targetPath);
        }
      } catch (e) {
        // Log the error but continue with remaining samples
        failedSamples[targetPath] = e.toString();
      }

      filesProcessed++;
      onProgress?.call(filesProcessed / sampleFiles.length);
    }

    return SampleInstallationResult(
      installedSamples: installedSamples,
      skippedSamples: skippedSamples,
      failedSamples: failedSamples,
    );
  }

  /// Install a sample file with retry logic for transient failures
  ///
  /// Retries up to [maxRetries] times with exponential backoff.
  /// SD card operations can be flaky due to device sleep or USB issues.
  Future<bool> _installSampleWithRetry(
    String targetPath,
    Uint8List sampleData,
    SampleInstallCallback installSample, {
    Function(double)? onProgress,
    int maxRetries = 2,
  }) async {
    Exception? lastException;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await installSample(
          targetPath,
          sampleData,
          onProgress: onProgress,
        );
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());

        // Don't retry on the last attempt
        if (attempt < maxRetries) {
          // Exponential backoff: 200ms, 400ms
          await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        }
      }
    }

    // All retries exhausted
    throw lastException ?? Exception('Sample installation failed');
  }

  /// Transform sample path from zip format to SD card target path
  ///
  /// Normalizes the path to lowercase to avoid case-sensitivity issues
  /// on different filesystems. The samples/ prefix is always lowercase.
  String _getSampleTargetPath(String zipPath) {
    // zipPath: "samples/drums/kick.wav" or "Samples/drums/kick.wav"
    // returns: "/samples/drums/kick.wav" (normalized to lowercase samples/)
    String path = zipPath;
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    // Normalize the samples directory prefix to lowercase
    // This ensures consistent paths regardless of zip file case
    if (path.toLowerCase().startsWith('/samples/')) {
      path = '/samples/${path.substring('/samples/'.length)}';
    }
    return path;
  }

  /// Get download URL for a plugin - prioritizes downloadUrl from installation config
  Future<String> _getDownloadUrl(GalleryPlugin plugin, String version) async {
    final repo = plugin.repository;

    // Priority 1: Use direct download URL from installation config if available
    if (plugin.installation.downloadUrl != null &&
        plugin.installation.downloadUrl!.isNotEmpty) {
      return plugin.installation.downloadUrl!;
    }

    // Priority 2: Fall back to GitHub API release asset discovery

    // Get release with assets
    final apiUrl =
        'https://api.github.com/repos/${repo.owner}/${repo.name}/releases/tags/$version';

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final releaseData =
            json.decode(utf8.decode(response.bodyBytes))
                as Map<String, dynamic>;
        final assets = releaseData['assets'] as List;

        if (assets.isNotEmpty) {
          // Filter out GitHub's automatic source code assets
          final pluginAssets = assets.where((asset) {
            final name = asset['name'] as String;
            final lowerName = name.toLowerCase();

            // Skip GitHub's automatic source code assets
            if (lowerName == 'source code (zip)' ||
                lowerName == 'source code (tar.gz)' ||
                name == 'Source code (zip)' ||
                name == 'Source code (tar.gz)') {
              return false;
            }

            // Accept plugin assets (.o, .lua, .3pot, .zip but not source.zip)
            return lowerName.endsWith('.o') ||
                lowerName.endsWith('.lua') ||
                lowerName.endsWith('.3pot') ||
                (lowerName.endsWith('.zip') && !lowerName.contains('source'));
          }).toList();

          if (pluginAssets.isNotEmpty) {
            final asset = pluginAssets.first as Map<String, dynamic>;
            final assetUrl = asset['browser_download_url'] as String;
            asset['name'] as String;
            return assetUrl;
          } else {
            throw GalleryException(
              'Release has no plugin assets - only source code found',
            );
          }
        } else {
          throw GalleryException('Release has no assets');
        }
      } else {
        throw GalleryException(
          'Release $version not found for ${repo.owner}/${repo.name}',
        );
      }
    } catch (e) {
      if (e is GalleryException) rethrow;
      throw GalleryException(
        'Failed to fetch release $version for ${repo.owner}/${repo.name}: $e',
      );
    }
  }

  /// Download file with progress tracking
  Future<List<int>> _downloadWithProgress(
    String url,
    Function(double) onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw GalleryException(
        'Download failed: HTTP ${response.statusCode} for URL: $url',
      );
    }

    final contentLength = response.contentLength;
    final bytes = <int>[];

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      if (contentLength != null && contentLength > 0) {
        final progress = bytes.length / contentLength;
        onProgress(progress);
      }
    }

    return bytes;
  }

  /// Check if a file path is a sample file (case-insensitive check for samples/ prefix)
  bool _isSampleFile(String filePath) {
    final lowerPath = filePath.toLowerCase();
    return lowerPath.startsWith('samples/') ||
        lowerPath.startsWith('/samples/');
  }

  /// Extract archive and filter relevant files, separating plugin files from sample files
  Future<ExtractedArchiveContents> _extractArchive(
    List<int> archiveBytes,
    GalleryPlugin plugin, {
    QueuedPlugin? queuedPlugin,
  }) async {
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    final pluginFiles = <MapEntry<String, List<int>>>[];
    final sampleFiles = <MapEntry<String, List<int>>>[];
    final installation = plugin.installation;

    // Compile regex pattern for file filtering if extractPattern is provided
    RegExp? extractRegex;
    if (installation.extractPattern != null &&
        installation.extractPattern!.isNotEmpty) {
      try {
        extractRegex = RegExp(installation.extractPattern!);
      } catch (e) {
        // Continue without pattern filtering if regex is invalid
      }
    }

    for (final file in archive) {
      if (!file.isFile) continue;

      String filePath = file.name;
      final originalFilePath = filePath;

      // Check for sample files first (before any path manipulation)
      // Sample files are extracted with their full relative path preserved
      if (_isSampleFile(originalFilePath)) {
        sampleFiles.add(MapEntry(originalFilePath, file.content as List<int>));
        continue;
      }

      // For directory-based installations, filter by source directory
      if (installation.sourceDirectoryPath != null &&
          installation.sourceDirectoryPath!.isNotEmpty) {
        final sourceDir = installation.sourceDirectoryPath!;

        // Check if file is within the source directory
        if (!filePath.startsWith('$sourceDir/') && filePath != sourceDir) {
          continue;
        }

        // Remove the source directory prefix for installation
        if (filePath.startsWith('$sourceDir/')) {
          filePath = filePath.substring(sourceDir.length + 1);
        } else if (filePath == sourceDir) {
          continue; // Skip the directory itself
        }
      }

      // Skip empty paths
      if (filePath.isEmpty) continue;

      // C++ release archives can contain licenses, checksums, and other
      // supporting files that do not belong in /programs/plug-ins.
      if (plugin.type == GalleryPluginType.cpp &&
          path.extension(filePath).toLowerCase() != '.o') {
        continue;
      }

      // Apply extract pattern filtering if specified
      if (extractRegex != null) {
        // Check both the processed filePath and original file.name against the pattern
        final fileNameOnly = path.basename(filePath);
        final originalFileNameOnly = path.basename(originalFilePath);

        if (!extractRegex.hasMatch(filePath) &&
            !extractRegex.hasMatch(fileNameOnly) &&
            !extractRegex.hasMatch(originalFilePath) &&
            !extractRegex.hasMatch(originalFileNameOnly)) {
          continue;
        }
      }

      // Check if this file should be included based on plugin selection
      if (queuedPlugin?.hasSelectedPlugins == true) {
        final selectedPaths = queuedPlugin!.selectedPlugins
            .where((p) => p.selected)
            .map((p) => p.relativePath)
            .toSet();

        if (!selectedPaths.contains(filePath)) {
          continue;
        }
      }

      pluginFiles.add(MapEntry(filePath, file.content as List<int>));
    }

    if (pluginFiles.isEmpty) {
      throw GalleryException(
        'No plugin files found in archive for ${plugin.name}. Extract pattern: ${installation.extractPattern ?? "none"}',
      );
    }

    return ExtractedArchiveContents(
      pluginFiles: pluginFiles,
      sampleFiles: sampleFiles,
    );
  }

  /// Install extracted files using Disting upload functionality
  ///
  /// Returns the non-skipped root-duplicate cleanup outcomes reported by
  /// [distingInstallPlugin] for the uploads that actually succeeded.
  Future<List<PluginCleanupOutcome>> _installFilesViaDisting(
    List<MapEntry<String, List<int>>> files,
    GalleryPlugin plugin,
    String resolvedVersion,
    Function(
      String fileName,
      Uint8List fileData, {
      Function(double)? onProgress,
      String? galleryPluginId,
      String? galleryPluginVersion,
    })
    distingInstallPlugin,
    Function(double)? onProgress,
  ) async {
    int filesProcessed = 0;
    final cleanupOutcomes = <PluginCleanupOutcome>[];
    void recordOutcome(Object? result) {
      if (result is PluginCleanupOutcome && result is! PluginCleanupSkipped) {
        cleanupOutcomes.add(result);
      }
    }

    for (final fileEntry in files) {
      final relativePath = fileEntry.key;
      final fileData = Uint8List.fromList(fileEntry.value);
      final fileName = path.basename(relativePath);

      try {
        // Try to upload with directory structure first (if path contains directories)
        if (relativePath.contains('/') && relativePath != fileName) {
          try {
            final result = await distingInstallPlugin(
              relativePath,
              fileData,
              onProgress: (fileProgress) {
                final overallProgress =
                    (filesProcessed + fileProgress) / files.length;
                onProgress?.call(overallProgress);
              },
              galleryPluginId: plugin.id,
              galleryPluginVersion: resolvedVersion,
            );

            recordOutcome(result);
            filesProcessed++;
            onProgress?.call(filesProcessed / files.length);
            continue; // Success, move to next file
          } catch (pathError) {
            // Intentionally empty
          }
        }

        // Fallback: upload to plugin root directory with just filename.
        // A root upload never triggers cleanup, so its outcome is skipped.
        final result = await distingInstallPlugin(
          fileName,
          fileData,
          onProgress: (fileProgress) {
            final overallProgress =
                (filesProcessed + fileProgress) / files.length;
            onProgress?.call(overallProgress);
          },
          galleryPluginId: plugin.id,
          galleryPluginVersion: resolvedVersion,
        );

        recordOutcome(result);
        filesProcessed++;
        onProgress?.call(filesProcessed / files.length);
      } catch (e) {
        throw GalleryException('Failed to upload $fileName: $e');
      }
    }
    return cleanupOutcomes;
  }

  /// Update a queued plugin's status
  void _updateQueuedPlugin(
    String pluginId, {
    QueuedPluginStatus? status,
    String? errorMessage,
    double? progress,
  }) {
    final index = _installQueue.indexWhere((q) => q.plugin.id == pluginId);
    if (index >= 0) {
      _installQueue[index] = _installQueue[index].copyWith(
        status: status ?? _installQueue[index].status,
        errorMessage: errorMessage,
        progress: progress,
      );
      _notifyQueueChanged();
    }
  }

  /// Notify listeners of queue changes
  void _notifyQueueChanged() {
    _queueController.add(List.unmodifiable(_installQueue));
  }

  // --- Plugin Update Methods ---

  /// Check for updates for all installed plugins
  Future<UpdateCheckResult?> checkAllPluginUpdates({
    bool forceCheck = false,
  }) async {
    return await _updateChecker?.checkAllPluginUpdates(forceCheck: forceCheck);
  }

  /// Check for updates for a specific plugin
  Future<PluginUpdateResult?> checkPluginUpdate(String pluginId) async {
    return await _updateChecker?.checkPluginUpdate(pluginId);
  }

  /// Get current update status for all installed plugins
  Future<Map<String, PluginUpdateInfo>?> getUpdateStatus() async {
    return await _updateChecker?.getUpdateStatus();
  }

  /// Get plugins that have updates available
  Future<List<PluginInstallationEntry>?> getPluginsWithUpdates() async {
    return await _updateChecker?.getPluginsWithUpdates();
  }

  /// Force refresh all plugin update information
  Future<UpdateCheckResult?> forceRefreshAllUpdates() async {
    return await _updateChecker?.forceRefreshAll();
  }

  /// Check if batch update check is needed
  bool get needsUpdateCheck => _updateChecker?.needsBatchCheck ?? false;

  /// Get the gallery data (used by update checker)
  Future<Gallery?> getGalleryData() async {
    try {
      return await fetchGallery();
    } catch (e) {
      return null;
    }
  }

  /// Invalidate cached gallery data
  void _invalidateCache() {
    _cachedGallery = null;
    _lastFetch = null;
  }

  Set<String> _normalizeDeviceGuids(Set<String> devicePluginGuids) {
    return devicePluginGuids.map((guid) => guid.toUpperCase()).toSet();
  }

  /// Remove a plugin installation record from the database
  Future<void> removePluginInstallation(String pluginId) async {
    if (_database == null) return;
    await _database.pluginInstallationsDao.removeAllPluginVersions(pluginId);
  }

  /// Sync database records with actual device state
  /// @deprecated Cleanup is now handled by PluginManagerScreen._cleanupStaleRecords()
  /// which uses installation path matching instead of GUID matching (GUIDs only
  /// work for C++ plugins, not Lua/3pot).
  @Deprecated('Use path-based cleanup in PluginManagerScreen instead')
  Future<void> syncDatabaseWithDevice(
    Gallery gallery,
    Set<String> devicePluginGuids,
  ) async {
    // No-op: cleanup is now handled by PluginManagerScreen._cleanupStaleRecords()
    // using path-based matching which works for all plugin types.
  }

  /// Compare gallery plugins with installed versions and return update info
  ///
  /// Checks both:
  /// 1. Database records (for plugins installed via gallery)
  /// 2. Device GUIDs (for manually installed plugins)
  Future<Map<String, PluginUpdateInfo>> compareWithInstalledVersions(
    Gallery gallery, {
    Set<String>? devicePluginGuids,
    Map<String, String>? devicePluginPaths,
  }) async {
    final Map<String, PluginUpdateInfo> updateInfo = {};
    final normalizedDeviceGuids = devicePluginGuids == null
        ? null
        : _normalizeDeviceGuids(devicePluginGuids);

    if (_database == null) {
      return updateInfo;
    }

    try {
      // Clean up any old records that have channel names instead of versions
      // This is a one-time migration for records created before the bug fix
      await _database.pluginInstallationsDao.cleanupChannelVersionRecords();

      // Get all installed plugins from database
      final installedPlugins = await _database.pluginInstallationsDao
          .getAllInstalledPlugins();

      for (final galleryPlugin in gallery.plugins) {
        // Check 1: Find matching installed plugin(s) in database by ID
        final matchingInstalled = installedPlugins
            .where(
              (installed) =>
                  installed.pluginId == galleryPlugin.id &&
                  installed.installationStatus == 'completed',
            )
            .toList();

        // Check 2: Also check if plugin GUID exists on device
        // (catches manually installed plugins not in database)
        // For collections, check if ANY of the collection's plugins are installed
        final isInstalledOnDevice =
            normalizedDeviceGuids != null &&
            ((galleryPlugin.guid != null &&
                    normalizedDeviceGuids.contains(
                      galleryPlugin.guid!.toUpperCase(),
                    )) ||
                galleryPlugin.collectionGuids.any(
                  (guid) => normalizedDeviceGuids.contains(guid.toUpperCase()),
                ));

        if (matchingInstalled.isEmpty && !isInstalledOnDevice) {
          // Plugin not installed - no update info needed
          continue;
        }

        // Get the best available version from gallery channels
        final availableVersion = _getBestAvailableVersion(galleryPlugin);

        if (availableVersion == null) {
          continue;
        }

        if (matchingInstalled.isNotEmpty) {
          // Use database version info for comparison
          final latestInstalled = matchingInstalled.reduce((a, b) {
            final cmp = _tryCompareVersions(a.pluginVersion, b.pluginVersion);
            if (cmp != null) return cmp > 0 ? a : b;
            // Fall back to installation date if versions aren't comparable
            return a.installedAt.isAfter(b.installedAt) ? a : b;
          });

          // Compare versions, with date fallback for plugins without versions
          final hasUpdate = _hasUpdateAvailable(
            installedVersion: latestInstalled.pluginVersion,
            availableVersion: availableVersion,
            installedAt: latestInstalled.installedAt,
            galleryUpdatedAt: galleryPlugin.updatedAt,
          );

          updateInfo[galleryPlugin.id] = PluginUpdateInfo(
            pluginId: galleryPlugin.id,
            pluginName: latestInstalled.pluginName,
            installedVersion: latestInstalled.pluginVersion,
            availableVersion: availableVersion,
            updateAvailable: hasUpdate,
            lastChecked: DateTime.now(),
          );
        } else if (isInstalledOnDevice) {
          // Plugin is on device (detected via GUID for C++ plugins)
          // Note: Database recording is now handled by DistingCubit.installPlugin()
          // using path-based tracking. GUID matching only works for C++ plugins.

          // Show as installed with unknown version, suggest update since we
          // can't verify the installed version matches the gallery version
          updateInfo[galleryPlugin.id] = PluginUpdateInfo(
            pluginId: galleryPlugin.id,
            pluginName: galleryPlugin.name,
            installedVersion: 'unknown',
            availableVersion: availableVersion,
            updateAvailable: true,
            lastChecked: DateTime.now(),
          );
        }
      }
    } catch (e) {
      // Intentionally empty
    }

    return updateInfo;
  }

  /// Get the best available version from a plugin's release channels
  String? _getBestAvailableVersion(GalleryPlugin plugin) {
    // Prefer latest, then stable, then beta
    if (plugin.releases.latest.isNotEmpty) {
      return plugin.releases.latest;
    }
    if (plugin.releases.stable?.isNotEmpty == true) {
      return plugin.releases.stable;
    }
    if (plugin.releases.beta?.isNotEmpty == true) {
      return plugin.releases.beta;
    }
    return null;
  }

  /// Determine if an update is available using version comparison with date fallback
  ///
  /// Handles cases where:
  /// 1. Untracked versions (unknown, user-installed, device-detected) - always true
  /// 2. Both versions are valid semver - uses version comparison
  /// 3. Versions are invalid - falls back to date comparison
  /// 4. Dates are missing - returns false (conservative approach)
  bool _hasUpdateAvailable({
    required String installedVersion,
    required String availableVersion,
    required DateTime installedAt,
    DateTime? galleryUpdatedAt,
  }) {
    // Versions that can't be compared should always suggest an update
    if (installedVersion == 'unknown' ||
        installedVersion == 'user-installed' ||
        installedVersion == 'device-detected') {
      return true;
    }

    // Try version comparison first
    final versionComparison = _tryCompareVersions(
      installedVersion,
      availableVersion,
    );

    if (versionComparison != null) {
      // Valid version comparison succeeded
      return versionComparison < 0; // Update available if installed < available
    }

    // Version comparison failed - fall back to date comparison
    if (galleryUpdatedAt != null) {
      // Plugin was updated in gallery after local installation
      return galleryUpdatedAt.isAfter(installedAt);
    }

    // No way to determine - conservative approach
    return false;
  }

  /// Try to compare two version strings, returns null if comparison fails
  /// Returns -1 if v1 < v2, 0 if equal, 1 if v1 > v2
  int? _tryCompareVersions(String version1, String version2) {
    // Skip comparison for unknown versions
    if (version1 == 'unknown' || version2 == 'unknown') {
      return null;
    }

    // Skip comparison for empty versions
    if (version1.isEmpty || version2.isEmpty) {
      return null;
    }

    try {
      // Try semantic version comparison, extracting semver from prefixed strings
      final v1 = Version.parse(extractSemver(version1));
      final v2 = Version.parse(extractSemver(version2));
      return v1.compareTo(v2);
    } catch (e) {
      // Semantic version parsing failed - return null to trigger date fallback
      return null;
    }
  }

  /// Extract a semver string from a potentially prefixed version tag.
  ///
  /// Handles mono-repo tags like `plugin-name-v1.2.3` or `plugin-name-1.2.3`
  /// by finding the semver portion at the end. Returns the input unchanged
  /// if no prefix is detected.
  static String extractSemver(String version) {
    // Match optional v prefix followed by semver at end of string
    final match = RegExp(r'v?(\d+\.\d+\.\d+.*)$').firstMatch(version);
    return match != null ? match.group(1)! : version;
  }

  /// Dispose of resources
  void dispose() {
    _queueController.close();
  }

  /// Check if a file extension corresponds to a raw plugin file
  bool _isRawPluginFile(String extension) {
    const rawPluginExtensions = {'.o', '.lua', '.3pot'};
    return rawPluginExtensions.contains(extension);
  }
}

/// Exception thrown by gallery operations
class GalleryException implements Exception {
  final String message;

  const GalleryException(this.message);

  @override
  String toString() => 'GalleryException: $message';
}
