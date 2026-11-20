import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/db/tables.dart';

import '../test_helpers/mapping_v8.dart';

// Existing forward-compatibility tests use zero extension bits and cannot
// detect destructive v8 rewrites during an unrelated CV or MIDI edit.

void main() {
  test('v8 roundtrip preserves bypass, view and opaque flags', () {
    final bytes = mappingV8Fixture();
    final mapping = PackedMappingData.fromBytes(8, bytes);
    expect(mapping.version, 8);
    expect(mapping.toBytes(), bytes);
  });

  test('editing only CV preserves every unrelated v8 mapping byte', () {
    final bytes = mappingV8Fixture();
    final mapping = PackedMappingData.fromBytes(8, bytes);
    final expected = Uint8List.fromList(bytes)..[1] = 2;
    expect(mapping.copyWith(cvInput: 2).toBytes(), expected);
  });
  test('v8 toggles change only their own wire bits and equality', () {
    final original = PackedMappingData.fromBytes(8, mappingV8Fixture());
    for (final (updated, offset, mask) in [
      (original.copyWith(midiViewChange: true), 8, 4),
      (original.copyWith(midiIgnoreWhenBypassed: false), 9, 2),
      (original.copyWith(i2cIgnoreWhenBypassed: false), 18, 4),
    ]) {
      final expected = mappingV8Fixture()..[offset] ^= mask;
      expect(updated.toBytes(), expected);
      expect(updated, isNot(original));
      expect(updated.copyWith(), updated);
    }
  });

  test('v8 signed ranges and SQLite blobs preserve every mapping option', () {
    final original = PackedMappingData.fromBytes(
      8,
      mappingV8Fixture(),
    ).copyWith(midiMin: -32768, midiMax: 32767, i2cMin: -200, i2cMax: 201);
    const converter = PackedMappingDataConverter();
    final restored = converter.fromSql(converter.toSql(original));
    expect(restored, original);
    expect(restored.hashCode, original.hashCode);
    expect(restored.version, 8);
    expect(restored.i2cCC, 200);
  });

  test(
    'legacy model defaults leave v8 options off without altering old encodings',
    () {
      final old = PackedMappingData.filler();
      expect(old.midiViewChange, isTrue);
      expect(old.midiIgnoreWhenBypassed, isFalse);
      expect(old.i2cIgnoreWhenBypassed, isFalse);
      for (final version in [1, 2, 3, 4, 5, 6, 7]) {
        final data = old.copyWith(version: version);
        expect(
          PackedMappingData.fromBytes(version, data.toBytes()).hasV8Options,
          isFalse,
        );
      }
    },
  );

  test('unknown wire versions and MIDI types cannot be silently written', () {
    final future = PackedMappingData.fromBytes(9, mappingV8Fixture());
    expect(
      () => future.validateForFirmware(FirmwareVersion('2.0')),
      throwsUnsupportedError,
    );
    final bytes = mappingV8Fixture()..[9] = 31 << 2;
    final unknown = PackedMappingData.fromBytes(8, bytes);
    expect(unknown.toBytes(), bytes);
    expect(
      () => unknown.validateForFirmware(FirmwareVersion('1.20')),
      throwsUnsupportedError,
    );
  });

  test('new options require wire v8 even on firmware 1.20', () {
    final data = PackedMappingData.filler().copyWith(
      version: 7,
      midiIgnoreWhenBypassed: true,
    );
    expect(
      () => data.validateForFirmware(FirmwareVersion('1.20')),
      throwsUnsupportedError,
    );
  });
}
