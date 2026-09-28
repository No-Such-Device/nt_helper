/// SD paths shared by local ZIPs, gallery archives, and individual uploads.
abstract final class PluginInstallationPath {
  static String normalize(String fileName) {
    final parts = fileName.replaceAll(r'\', '/').split('/');
    if (parts.contains('..') || RegExp(r'[:\x00-\x1f]').hasMatch(fileName)) {
      throw FormatException('Invalid plugin path: $fileName');
    }
    return parts.where((part) => part.isNotEmpty && part != '.').join('/');
  }

  static bool isHelperCompanion(String fileName) {
    final normalized = normalize(fileName).toLowerCase();
    return normalized.startsWith('programs/helper/') &&
        normalized.endsWith('.lua');
  }

  static String target(String fileName) {
    final normalized = normalize(fileName);
    final extension = normalized.toLowerCase().split('.').last;
    final directory = switch (extension) {
      'lua' =>
        isHelperCompanion(normalized) ? 'programs/helper' : 'programs/lua',
      '3pot' => 'programs/three_pot',
      'o' => 'programs/plug-ins',
      _ => throw FormatException('Unsupported plugin file type: .$extension'),
    };
    if (normalized.toLowerCase().startsWith('$directory/')) {
      return '/$directory/${normalized.substring(directory.length + 1)}';
    }
    if (normalized.toLowerCase().startsWith('programs/')) {
      throw FormatException('Wrong SD directory for plugin: $fileName');
    }
    return '/$directory/$normalized';
  }
}
