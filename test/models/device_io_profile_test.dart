import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/slot_count_info.dart';

void main() {
  group('DeviceIoProfile', () {
    test('builds contiguous ranges for a reported topology', () {
      final profile = DeviceIoProfile.tryCreate(
        inputBusCount: 4,
        outputBusCount: 3,
        auxBusCount: 5,
      )!;

      expect(profile.inputBuses, [1, 2, 3, 4]);
      expect(profile.outputBuses, [5, 6, 7]);
      expect(profile.auxBuses, [8, 9, 10, 11, 12]);
      expect(profile.contextualEs5Buses, [13, 14]);
      expect(profile.labelForBus(6), 'Output 2');
      expect(profile.busForLocalNumber(DeviceBusGroup.aux, 3), 10);
    });

    test('accepts zero-count groups', () {
      final profile = DeviceIoProfile.tryCreate(
        inputBusCount: 0,
        outputBusCount: 2,
        auxBusCount: 0,
      )!;

      expect(profile.inputBuses, isEmpty);
      expect(profile.outputBuses, [1, 2]);
      expect(profile.auxBuses, isEmpty);
    });

    test('caps general buses at 64 and keeps ES-5 contextual', () {
      final profile = DeviceIoProfile.tryCreate(
        inputBusCount: 12,
        outputBusCount: 8,
        auxBusCount: 44,
      )!;

      expect(DeviceIoProfile.maximumBusNumber, 64);
      expect(profile.maxBus, 64);
      expect(profile.contextualEs5Buses, [65, 66]);
      expect(
        DeviceIoProfile.tryCreate(
          inputBusCount: 12,
          outputBusCount: 8,
          auxBusCount: 45,
        ),
        isNull,
      );
    });

    test('rejects negative, oversized, and overflowing counts', () {
      expect(
        DeviceIoProfile.tryCreate(
          inputBusCount: -1,
          outputBusCount: 2,
          auxBusCount: 3,
        ),
        isNull,
      );
      expect(
        DeviceIoProfile.tryCreate(
          inputBusCount: 128,
          outputBusCount: 0,
          auxBusCount: 0,
        ),
        isNull,
      );
      expect(
        DeviceIoProfile.tryCreate(
          inputBusCount: 64,
          outputBusCount: 64,
          auxBusCount: 0,
        ),
        isNull,
      );
    });

    test('uses complete reported topology', () {
      final profile = DeviceIoProfile.resolve(
        slotCountInfo: const SlotCountInfo(
          slotCount: 8,
          inputBusCount: 4,
          outputBusCount: 3,
          auxBusCount: 5,
        ),
        firmwareVersion: FirmwareVersion('1.15'),
      );

      expect(
        profile,
        DeviceIoProfile.tryCreate(
          inputBusCount: 4,
          outputBusCount: 3,
          auxBusCount: 5,
        ),
      );
    });

    test('falls back completely for missing, partial, or invalid topology', () {
      expect(
        DeviceIoProfile.resolve(
          slotCountInfo: const SlotCountInfo(slotCount: 8),
          firmwareVersion: FirmwareVersion('1.14'),
        ),
        DeviceIoProfile.distingLegacy,
      );
      expect(
        DeviceIoProfile.resolve(
          slotCountInfo: const SlotCountInfo(
            slotCount: 8,
            inputBusCount: 4,
            outputBusCount: 3,
          ),
          firmwareVersion: FirmwareVersion('1.15'),
        ),
        DeviceIoProfile.distingExtended,
      );
      expect(
        DeviceIoProfile.resolve(
          slotCountInfo: const SlotCountInfo(
            slotCount: 8,
            inputBusCount: 127,
            outputBusCount: 1,
            auxBusCount: 0,
          ),
          firmwareVersion: FirmwareVersion('1.14'),
        ),
        DeviceIoProfile.distingLegacy,
      );
      expect(
        DeviceIoProfile.resolve(
          slotCountInfo: const SlotCountInfo(
            slotCount: 8,
            inputBusCount: -1,
            outputBusCount: 3,
            auxBusCount: 5,
          ),
          firmwareVersion: FirmwareVersion('1.15'),
        ),
        DeviceIoProfile.distingExtended,
      );
    });
  });
}
