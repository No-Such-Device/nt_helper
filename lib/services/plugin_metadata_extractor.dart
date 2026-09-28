import 'dart:typed_data';
import 'package:nt_helper/utils/plugin_installation_path.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:nt_helper/models/gallery_models.dart';
import 'package:nt_helper/services/elf_guid_extractor.dart';

/// Service for extracting plugin metadata from collection archives
class PluginMetadataExtractor {
  /// Count installable plugin files in an archive (excludes source files like .cpp)
  static Future<int> countInstallablePlugins(
    List<int> archiveBytes,
    GalleryPlugin plugin,
  ) async {
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    final installation = plugin.installation;
    int count = 0;

    for (final file in archive) {
      if (!file.isFile) continue;

      String filePath = PluginInstallationPath.normalize(file.name);
      // Companion programs are dependencies, never selectable NT algorithms.
      if (PluginInstallationPath.isHelperCompanion(filePath)) continue;

      // Apply source directory filtering if specified
      if (installation.sourceDirectoryPath != null &&
          installation.sourceDirectoryPath!.isNotEmpty) {
        final sourceDir = installation.sourceDirectoryPath!;
        if (!filePath.startsWith('$sourceDir/') && filePath != sourceDir) {
          continue;
        }
        // Remove source directory prefix
        if (filePath.startsWith('$sourceDir/')) {
          filePath = filePath.substring(sourceDir.length + 1);
        }
      }

      if (PluginInstallationPath.isHelperCompanion(filePath)) continue;

      // Only count installable plugin files (exclude source files like .cpp)
      final extension = path.extension(filePath).toLowerCase();
      if (!const ['.o', '.lua', '.3pot'].contains(extension)) {
        continue;
      }

      // Skip build/template files and includes
      if (filePath.contains('/include/') ||
          filePath.contains('/make_plugins/') ||
          filePath.endsWith('template1.h') ||
          filePath.endsWith('template2.h') ||
          filePath.endsWith('templateKernels.h') ||
          filePath.endsWith('templateStereo.h')) {
        continue;
      }

      count++;
    }

    return count;
  }

  /// Extract plugin list from a collection archive
  static Future<List<CollectionPlugin>> extractPluginsFromArchive(
    List<int> archiveBytes,
    GalleryPlugin plugin,
  ) async {
    final archive = ZipDecoder().decodeBytes(archiveBytes);
    final plugins = <CollectionPlugin>[];
    final installation = plugin.installation;

    for (final file in archive) {
      if (!file.isFile) continue;

      String filePath = PluginInstallationPath.normalize(file.name);
      // Companion programs are dependencies, never selectable NT algorithms.
      if (PluginInstallationPath.isHelperCompanion(filePath)) continue;

      // Apply source directory filtering if specified
      if (installation.sourceDirectoryPath != null &&
          installation.sourceDirectoryPath!.isNotEmpty) {
        final sourceDir = installation.sourceDirectoryPath!;
        if (!filePath.startsWith('$sourceDir/') && filePath != sourceDir) {
          continue;
        }
        // Remove source directory prefix
        if (filePath.startsWith('$sourceDir/')) {
          filePath = filePath.substring(sourceDir.length + 1);
        }
      }

      if (PluginInstallationPath.isHelperCompanion(filePath)) continue;

      // Skip if not a plugin file (include both source and compiled files)
      final extension = path.extension(filePath).toLowerCase();
      if (!const ['.o', '.lua', '.3pot', '.cpp'].contains(extension)) {
        continue;
      }

      // Skip build/template files and includes
      if (filePath.contains('/include/') ||
          filePath.contains('/make_plugins/') ||
          filePath.endsWith('template1.h') ||
          filePath.endsWith('template2.h') ||
          filePath.endsWith('templateKernels.h') ||
          filePath.endsWith('templateStereo.h')) {
        continue;
      }

      final fileName = path.basenameWithoutExtension(filePath);
      final fileType = extension.substring(1); // Remove the dot
      String? description;

      // For .cpp files, treat them as equivalent to .o files for display purposes

      // Try to extract description based on file type
      try {
        if (fileType == 'o') {
          // For ELF files, try to extract GUID and derive name
          final fileBytes = Uint8List.fromList(file.content as List<int>);
          final guid = await ElfGuidExtractor.extractGuidFromBytes(
            fileBytes,
            fileName,
          );
          description = 'Plugin GUID: ${guid.guid}';
        } else if (fileType == 'lua') {
          // For Lua files, try to extract description from comments
          final content = String.fromCharCodes(file.content as List<int>);
          description = _extractLuaDescription(content);
        }
      } catch (e) {
        // If extraction fails, continue without description
      }

      plugins.add(
        CollectionPlugin(
          name: fileName,
          relativePath: filePath,
          fileType: fileType,
          description: description,
          fileSize: file.size,
          selected: false,
        ),
      );
    }

    // Sort plugins by name
    plugins.sort((a, b) => a.name.compareTo(b.name));
    return plugins;
  }

  /// Extract description from Lua script comments
  static String? _extractLuaDescription(String content) {
    final lines = content.split('\n');

    // Look for the second comment line (first line after the shebang/title)
    int commentCount = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('--')) {
        commentCount++;
        if (commentCount == 2) {
          // Return the second comment without the --
          return trimmed.substring(2).trim();
        }
      } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        // Stop if we hit non-comment, non-empty line
        break;
      }
    }

    return null;
  }
}
