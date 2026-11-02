import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

void main() {
  group('Algorithm Movement - ioFlags Preservation', () {
    

    test('ParameterInfo ioFlags helper methods work correctly', () {
      final inputParam = ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 0,
        name: 'Input',
        powerOfTen: 0,
        ioFlags: 1, // Bit 0 set
      );

      final outputParam = ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 1,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 0,
        name: 'Output',
        powerOfTen: 0,
        ioFlags: 2, // Bit 1 set
      );

      final audioOutputParam = ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 2,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 0,
        name: 'Audio Output',
        powerOfTen: 0,
        ioFlags: 6, // Bits 1 and 2 set (2 | 4)
      );

      // Test input parameter
      expect(inputParam.isInput, true);
      expect(inputParam.isOutput, false);
      expect(inputParam.isAudio, false);

      // Test output parameter
      expect(outputParam.isInput, false);
      expect(outputParam.isOutput, true);
      expect(outputParam.isAudio, false);

      // Test audio output parameter
      expect(audioOutputParam.isInput, false);
      expect(audioOutputParam.isOutput, true);
      expect(audioOutputParam.isAudio, true);
    });

    test('Default ioFlags value is 0 when not specified', () {
      final param = ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 0,
        name: 'Test',
        powerOfTen: 0,
        // ioFlags not specified, should default to 0
      );

      expect(param.ioFlags, 0);
      expect(param.isInput, false);
      expect(param.isOutput, false);
      expect(param.isAudio, false);
    });
  });
}
