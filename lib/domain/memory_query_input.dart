import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';

/// The catalogue-derived algorithm tuple required by a memory query.
///
/// The GUID bytes and specification defaults come directly from one live
/// built-in catalogue record. Specification positions not declared by that
/// record are padded with zero to the protocol's fixed three-field shape.
final class MemoryQueryInput {
  static const int specificationFieldCount = 3;

  MemoryQueryInput._({
    required List<int> guidBytes,
    required List<int> specificationValues,
  }) : guidBytes = List<int>.unmodifiable(guidBytes),
       specificationValues = List<int>.unmodifiable(specificationValues);

  /// The exact four GUID bytes returned by the catalogue response.
  final List<int> guidBytes;

  /// The returned defaults, padded only after all declared specifications.
  final List<int> specificationValues;

  /// Requests the connected device's catalogue and selects its first usable
  /// built-in record without consulting or modifying preset slots.
  ///
  /// Returns `null` when the catalogue is missing or has no suitable record.
  /// Transport and response-parsing failures remain errors rather than being
  /// converted into fabricated input values.
  static Future<MemoryQueryInput?> requestFromCatalogue(
    IDistingMidiManager midiManager,
  ) async {
    final numberOfAlgorithms = await midiManager.requestNumberOfAlgorithms();
    if (numberOfAlgorithms == null || numberOfAlgorithms <= 0) {
      return null;
    }

    for (var index = 0; index < numberOfAlgorithms; index++) {
      final algorithm = await midiManager.requestAlgorithmInfo(index);
      final input = _tryFromAlgorithm(algorithm, expectedIndex: index);
      if (input != null) {
        return input;
      }
    }

    return null;
  }

  static MemoryQueryInput? _tryFromAlgorithm(
    AlgorithmInfo? algorithm, {
    required int expectedIndex,
  }) {
    if (algorithm == null ||
        algorithm.algorithmIndex != expectedIndex ||
        algorithm.isPlugin) {
      return null;
    }

    // AlgorithmInfoResponse creates the GUID string with String.fromCharCodes,
    // so these code units preserve the four response bytes without case or
    // whitespace normalization.
    final guidBytes = algorithm.guid.codeUnits;
    if (guidBytes.length != 4 ||
        guidBytes.every((byte) => byte == 0) ||
        guidBytes.any((byte) => byte < 0 || byte > 0x7F)) {
      return null;
    }

    final specifications = algorithm.specifications;
    if (specifications.length > specificationFieldCount) {
      return null;
    }

    final defaults = specifications
        .map((specification) => specification.defaultValue)
        .toList(growable: true);
    if (defaults.any((value) => value < -0x8000 || value > 0x7FFF)) {
      return null;
    }

    defaults.addAll(
      List<int>.filled(specificationFieldCount - defaults.length, 0),
    );

    return MemoryQueryInput._(
      guidBytes: guidBytes,
      specificationValues: defaults,
    );
  }
}
