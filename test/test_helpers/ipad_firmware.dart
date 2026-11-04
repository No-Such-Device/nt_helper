import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/services/ipad_firmware_session.dart';

const ipadLoaderName = 'bootable_images/unsigned_MIMXRT1060_flashloader.bin';
const ipadApplicationName = 'bootable_images/disting_NT.bin';
final ipadRelease = FirmwareRelease(
  version: '1.19.0',
  releaseDate: DateTime(2026),
  changelog: const [],
  downloadUrl:
      'https://expert-sleepers.co.uk/downloads/firmware/distingNT_1.19.0.zip',
);

Uint8List ipadImage({
  bool application = false,
  int? wordOffset,
  int? wordValue,
}) {
  final bytes = Uint8List(64);
  final data = ByteData.sublistView(bytes);
  final base = application ? 0x60001000 : 0x20001c00;
  for (final entry in {
    0: 0x402000d1,
    4: base + 49,
    16: base + 32,
    20: base,
    32: application ? base - 0x1000 : base,
    36: bytes.length + (application ? 0x1000 : 0),
  }.entries) {
    data.setUint32(entry.key, entry.value, Endian.little);
  }
  if (wordOffset != null) data.setUint32(wordOffset, wordValue!, Endian.little);
  return bytes;
}

List<int> ipadPackageBytes({
  Map<String, dynamic>? manifestChanges,
  String? omit,
  String? extra,
  List<int>? loader,
  List<int>? application,
}) {
  final manifest = {
    'processor': 'MIMXRT1060',
    'mfp_type': 'write_script',
    'provisioning_type': 'disabled',
    'boot_type': 'unsigned',
    'life_cycle': 'open_develop',
    'app_firmware': ipadApplicationName,
    'connection': {
      'connection_type': 'usb',
      'usb_hid': {'usbVid_int': '0x1FC9', 'usbPid_int': '0x0135'},
    },
    ...?manifestChanges,
  };
  final members = <String, List<int>>{
    'MANIFEST.json': utf8.encode(jsonEncode(manifest)),
    ipadLoaderName: loader ?? ipadImage(),
    ipadApplicationName: application ?? ipadImage(application: true),
    ?extra: [9],
  }..remove(omit);
  final archive = Archive();
  for (final entry in members.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encode(archive);
}

/// Acquisition is controlled; preflight remains the production validator.
class IpadPackageAcquisition extends FirmwareVersionService {
  List<int> bytes = ipadPackageBytes();
  int downloads = 0;
  PreparedFirmwarePackage? prepared;
  @override
  Future<List<FirmwareRelease>> fetchAvailableVersions({
    bool forceRefresh = false,
  }) async => [ipadRelease];
  @override
  Future<String> downloadFirmware(
    FirmwareRelease version, {
    void Function(double)? onProgress,
  }) async {
    downloads++;
    onProgress?.call(1);
    return '/not-on-disk/download.zip';
  }

  @override
  Future<PreparedFirmwarePackage> prepareIpadPackage(
    FirmwareRelease release,
    String downloadedPath,
  ) async {
    return prepared = FirmwareVersionService.validateIpadPackage(
      release,
      '/not-on-disk/session/package.zip',
      bytes,
    );
  }
}

class ControlledIpadSession implements IpadFirmwareSession {
  late final controller = StreamController<IpadFirmwareEvent>(
    sync: true,
    onCancel: () async {},
  );
  late final result = Completer<IpadProgrammingResult>();
  final started = Completer<void>();
  Completer<String>? preparation;
  bool supported = true;
  Object? prepareError;
  int prepares = 0, starts = 0, closes = 0;
  Uint8List? loader, application;
  bool listened = false;
  @override
  Stream<IpadFirmwareEvent> get events {
    listened = true;
    return controller.stream;
  }

  Future<void> dispose() async {
    if (!listened) controller.stream.listen((_) {});
    await controller.close();
  }

  @override
  Future<IpadFirmwareAvailability> availability() async =>
      IpadFirmwareAvailability(isIPad: supported, osEligible: supported);
  @override
  Future<String> prepare() async {
    prepares++;
    if (prepareError != null) throw prepareError!;
    return preparation?.future ?? Future.value('session-1');
  }

  @override
  Future<IpadProgrammingResult> start({
    required String sessionId,
    required Uint8List loader,
    required Uint8List application,
  }) {
    starts++;
    this.loader = loader;
    this.application = application;
    started.complete();
    return result.future;
  }

  void phase(IpadProgrammingPhase phase, {String sessionId = 'session-1'}) =>
      controller.add(
        IpadFirmwareEvent(
          sessionId: sessionId,
          phase: phase,
          transferred: 2,
          total: 4,
        ),
      );
  void finish([
    IpadProgrammingOutcome outcome = IpadProgrammingOutcome.programmed,
  ]) => result.complete(IpadProgrammingResult('session-1', outcome, null));
  @override
  Future<void> cancel(String sessionId) async {
    closes++;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

/// Alter central and local lengths without allocating attacker-declared data.
List<int> ipadDeclaredLength(List<int> source, String member, int length) {
  final bytes = Uint8List.fromList(source);
  final data = ByteData.sublistView(bytes);
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  final header = directory.fileHeaders.singleWhere((h) => h.filename == member);
  data.setUint32(header.localHeaderOffset + 22, length, Endian.little);
  for (var p = 0; p + 46 < bytes.length; p++) {
    if (data.getUint32(p, Endian.little) == 0x02014b50 &&
        data.getUint32(p + 42, Endian.little) == header.localHeaderOffset) {
      data.setUint32(p + 24, length, Endian.little);
    }
  }
  return bytes;
}

List<int> duplicateIpadMember(String name) {
  final alias = '${name.substring(0, name.length - 1)}x';
  final bytes = Uint8List.fromList(ipadPackageBytes(extra: alias));
  final from = utf8.encode(alias), to = utf8.encode(name);
  for (var p = 0; p <= bytes.length - from.length; p++) {
    if (List.generate(
      from.length,
      (i) => bytes[p + i] == from[i],
    ).every((v) => v)) {
      bytes.setRange(p, p + to.length, to);
    }
  }
  return bytes;
}

Map<String, List<int>> invalidIpadPackages() => {
  for (final name in ['MANIFEST.json', ipadLoaderName, ipadApplicationName])
    'duplicate $name': duplicateIpadMember(name),
  'corrupt archive': [1, 2, 3],
  'malformed loader IVT': ipadPackageBytes(loader: [1, 2, 3]),
  'incompatible application IVT': ipadPackageBytes(
    application: ipadImage(application: true, wordOffset: 0, wordValue: 0),
  ),
  'signed application CSF': ipadPackageBytes(
    application: ipadImage(
      application: true,
      wordOffset: 24,
      wordValue: 0x60002000,
    ),
  ),
  'overflowing loader entry': ipadPackageBytes(
    loader: ipadImage(wordOffset: 4, wordValue: 0xffffffff),
  ),
  'out-of-range loader boot pointer': ipadPackageBytes(
    loader: ipadImage(wordOffset: 16, wordValue: 0x20020000),
  ),
  'out-of-range flash self pointer': ipadPackageBytes(
    application: ipadImage(
      application: true,
      wordOffset: 20,
      wordValue: 0x60800000,
    ),
  ),
  'overflowing image length': ipadPackageBytes(
    application: ipadImage(
      application: true,
      wordOffset: 36,
      wordValue: 0xffffffff,
    ),
  ),
  'wrong transport': ipadPackageBytes(
    manifestChanges: {
      'connection': {'connection_type': 'uart'},
    },
  ),
  'malformed manifest': ipadPackageBytes(manifestChanges: {'processor': null}),
  'wrong processor': ipadPackageBytes(
    manifestChanges: {'processor': 'MIMXRT1170'},
  ),
  'incompatible signed format': ipadPackageBytes(
    manifestChanges: {'boot_type': 'signed'},
  ),
  for (final name in ['MANIFEST.json', ipadLoaderName, ipadApplicationName])
    'missing $name': ipadPackageBytes(omit: name),
  for (final name in [
    '../unsafe',
    '/unsafe',
    'a/../unsafe',
    'a\\unsafe',
    'C:/unsafe',
  ])
    'unsafe $name': ipadPackageBytes(extra: name),
  'empty loader': ipadPackageBytes(loader: []),
  'empty application': ipadPackageBytes(application: []),
  'oversized loader': ipadDeclaredLength(
    ipadPackageBytes(),
    ipadLoaderName,
    0x1e401,
  ),
  'out-of-range flash': ipadDeclaredLength(
    ipadPackageBytes(),
    ipadApplicationName,
    0x7ff001,
  ),
  'overflowing length': ipadDeclaredLength(
    ipadPackageBytes(),
    ipadApplicationName,
    0xffffffff,
  ),
  'invalid actual length': ipadDeclaredLength(
    ipadPackageBytes(),
    ipadApplicationName,
    3,
  ),
};
