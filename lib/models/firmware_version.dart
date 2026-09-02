class FirmwareVersion {
  final String versionString;
  final String? date;
  late final int major;
  late final int minor;
  late final int patch;
  late final List<int> _parts;

  FirmwareVersion(this.versionString, {this.date}) {
    try {
      final matches = RegExp(r'\d+').allMatches(versionString);
      _parts = matches.map((m) => int.tryParse(m.group(0)!) ?? 0).toList();
      major = _parts.isNotEmpty ? _parts[0] : 0;
      minor = _parts.length > 1 ? _parts[1] : 0;
      patch = _parts.length > 2 ? _parts[2] : 0;
    } catch (e) {
      _parts = [0, 0, 0];
      major = 0;
      minor = 0;
      patch = 0;
    }
  }

  /// Firmware 1.16+ supports performance page items via SysEx 0x57/0x58.
  bool get hasPerfPageItems {
    return major > 1 || (major == 1 && minor >= 16);
  }

  /// Firmware 1.17+ supports MIDI mapping types for pitch bend and channel pressure.
  bool get hasExpressiveMidiMapping {
    return isSupported('1.17.0');
  }

  /// Firmware 1.17+ exposes generated wave-cache files in SD-card listings.
  bool get hasWaveCacheListing {
    return isSupported('1.17.0');
  }

  /// Firmware 1.18+ exposes per-algorithm overview styling via SysEx 0x40/0x54.
  bool get hasAlgorithmVisualStyle {
    return isSupported('1.18.0');
  }

  /// Firmware 1.15+ supports entering bootloader mode via SysEx.
  bool get hasBootloaderSysEx {
    return major > 1 || (major == 1 && minor >= 15);
  }

  /// Firmware 1.15 expanded AUX buses from 8 (21-28) to 44 (21-64).
  bool get hasExtendedAuxBuses {
    return major > 1 || (major == 1 && minor >= 15);
  }

  /// The disting firmware added SD card sysex support in version 1.10.
  bool get hasSdCardSupport {
    return major > 1 || (major == 1 && minor >= 10);
  }

  /// The disting firmware added setParameterString support in version 1.10.
  bool get hasSetPropertyStringSupport {
    return major > 1 || (major == 1 && minor >= 10);
  }

  /// Checks if the current version is at least the minimum required for the app.
  bool isSupported(String minimumVersionString) {
    final minimum = FirmwareVersion(minimumVersionString);
    final length = _parts.length > minimum._parts.length
        ? _parts.length
        : minimum._parts.length;

    for (var i = 0; i < length; i++) {
      final currentSegment = i < _parts.length ? _parts[i] : 0;
      final minimumSegment = i < minimum._parts.length ? minimum._parts[i] : 0;
      if (currentSegment < minimumSegment) {
        return false; // Current is lower, so unsupported
      }
      if (currentSegment > minimumSegment) {
        return true; // Current is higher, so supported
      }
    }
    return true; // Versions are equal, so supported
  }

  bool isGreaterThan(FirmwareVersion other) {
    if (major > other.major) return true;
    if (major < other.major) return false;
    if (minor > other.minor) return true;
    if (minor < other.minor) return false;
    if (patch > other.patch) return true;
    return false;
  }

  bool isExactly(String otherVersionString) {
    final other = FirmwareVersion(otherVersionString);
    return major == other.major && minor == other.minor && patch == other.patch;
  }

  @override
  String toString() => versionString;
}
