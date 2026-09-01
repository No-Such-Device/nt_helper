import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/mock_disting_midi_manager.dart';
import 'package:nt_helper/models/slot_count_info.dart';

class _ExtendedSlotCountManager extends MockDistingMidiManager
    implements SlotCountInfoProvider {
  int extendedRequestCount = 0;
  Duration? receivedTimeout;
  int? receivedMaxRetries;

  @override
  Future<SlotCountInfo?> requestSlotCountInfo({
    Duration? timeout,
    int? maxRetries,
  }) async {
    extendedRequestCount++;
    receivedTimeout = timeout;
    receivedMaxRetries = maxRetries;
    return const SlotCountInfo(
      slotCount: 4,
      inputBusCount: 1,
      outputBusCount: 1,
      auxBusCount: 2,
    );
  }
}

void main() {
  test(
    'uses the extended slot-count provider through the manager interface',
    () async {
      final concreteManager = _ExtendedSlotCountManager();
      final IDistingMidiManager manager = concreteManager;
      addTearDown(manager.dispose);
      const timeout = Duration(milliseconds: 250);

      final info = await manager.requestSlotCountInfo(
        timeout: timeout,
        maxRetries: 2,
      );

      expect(
        info,
        const SlotCountInfo(
          slotCount: 4,
          inputBusCount: 1,
          outputBusCount: 1,
          auxBusCount: 2,
        ),
      );
      expect(concreteManager.extendedRequestCount, 1);
      expect(concreteManager.receivedTimeout, timeout);
      expect(concreteManager.receivedMaxRetries, 2);
    },
  );
}
