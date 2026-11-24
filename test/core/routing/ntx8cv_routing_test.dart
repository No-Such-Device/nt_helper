import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/ntx8cv_routing.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:nt_helper/ui/widgets/routing/connection_validator.dart';

import '../../test_helpers/ntx8cv_routing_fixture.dart';
import '../../test_helpers/cv_routing_fixture.dart';

void main() {
  const profile = DeviceIoProfile.distingExtended;
  Ntx8cvRouting config(ModuleSettingsState state) =>
      Ntx8cvRouting.fromSettings(state, profile)!;
  test(
    'observed schema, not numeric IDs, identifies fixed first-group taps',
    () {
      final a = config(ntxSettings(offset: 0));
      final b = config(ntxSettings(offset: 700));
      expect(a, b);
      final ports = a.ports(profile);
      expect(ports, hasLength(8));
      expect(Port.fromJson(ports.first.toJson()), ports.first);
      expect(ports.first.isBus, isTrue);
      expect(ports.first.isPhysicalOutput, isFalse);
      expect(ports.map((p) => p.busValue), [21, 22, 23, 24, 25, 26, 27, 28]);
      expect(ports.map((p) => p.hardwareIndex), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(
        ports.every((p) => p.effectiveRole == PortRole.expanderOutputBus),
        isTrue,
      );
      expect(profile.outputBuses, [13, 14, 15, 16, 17, 18, 19, 20]);
      expect(a.toJson(profile)['scope'], 'first_channel_group');
    },
  );
  test('sparse mask retains fixed holes and never packs enabled bits', () {
    final a = config(ntxSettings(mask: BigInt.from(0x85)));
    expect(
      a.ports(profile).where((p) => p.isActive).map((p) => p.hardwareIndex),
      [1, 3, 8],
    );
    expect(a.protectedBuses(profile), {21, 23, 28});
    final high = config(ntxSettings(mask: BigInt.one << 63));
    expect(high.ports(profile).any((p) => p.isActive), isFalse);
    expect(
      config(ntxSettings(mask: (BigInt.one << 64) - BigInt.one))
          .ports(profile)
          .every((p) => p.isActive),
      isTrue,
    );
  });
  test('audio transmit channels do not use the CV enable mask or claim local enable', () {
    for (final mode in [1, 2]) {
      final a = config(ntxSettings(mode: mode, mask: BigInt.zero));
      expect(a.ports(profile).every((p) => p.isActive), isTrue);
      expect(
        a.ports(profile).first.description,
        contains('local audio enable unknown'),
      );
      expect(a.protectedBuses(profile), {21, 22, 23, 24, 25, 26, 27, 28});
    }
  });
  test('drafts are not observed routing; uncertainty retains geometry but no active edges', () {
    final initial = config(ntxSettings());
    expect(config(ntxSettings(draftMode: 2)), initial);
    for (final state in [
      ntxSettings(busy: true),
      ntxSettings(uncertain: true),
      ntxSettings(needsRefresh: true),
      ntxSettings(mode: 8),
    ]) {
      final a = config(state);
      expect(a.available, isFalse);
      expect(
        a.ports(profile).map((p) => p.id),
        initial.ports(profile).map((p) => p.id),
      );
      expect(a.ports(profile).any((p) => p.isActive), isFalse);
      expect(a.protectedBuses(profile), hasLength(8));
    }
  });
  test(
    'unsupported, stale, malformed and unknown schema do not fabricate outputs',
    () {
      expect(
        Ntx8cvRouting.fromSettings(ModuleSettingsState(), profile),
        isNull,
      );
      expect(
        Ntx8cvRouting.fromSettings(
          ntxSettings(unavailable: 'Disconnected'),
          profile,
        ),
        isNull,
      );
      expect(
        Ntx8cvRouting.fromSettings(
          ntxSettings(),
          DeviceIoProfile.distingLegacy,
        ),
        isNull,
      );
      expect(
        Ntx8cvRouting.fromSettings(
          ntxSettings(modes: ['CV', 'Audio', 'Other']),
          profile,
        ),
        isNull,
      );
    },
  );
  test('tap edges supplement ordinary AUX readers and retain actual slot identities', () {
    final source = AlgorithmRouting.fromSlot(
      cvSlot(3, outputs: [21, 23]),
      algorithmUuid: 'source',
      deviceIoProfile: profile,
    );
    final reader = AlgorithmRouting.fromSlot(
      cvSlot(5, inputs: [21]),
      algorithmUuid: 'reader',
      deviceIoProfile: profile,
    );
    final ordinary = ConnectionDiscoveryService.discoverConnections([
      source,
      reader,
    ], deviceIoProfile: profile);
    final edges = ntx8cvConnections(
      ports: config(ntxSettings(mask: BigInt.one)).ports(profile),
      algorithms: [(id: 'source', index: 3, outputs: source.outputPorts)],
    );
    expect(
      ordinary.any((c) => c.destinationPortId.startsWith('reader')),
      isTrue,
    );
    expect(edges, hasLength(1));
    expect(edges.single.algorithmIndex, 3);
    expect(edges.single.destinationPortId, 'ntx8cv_out_1');
    expect(edges.single.busNumber, 21);
    expect(
      ConnectionValidator.isValidConnection(
        source.outputPorts.first,
        config(ntxSettings()).ports(profile).first,
      ),
      isFalse,
    );
  });
}
