import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/request_key.dart';
import 'package:nt_helper/domain/sd_card_operation.dart';
import 'package:nt_helper/domain/sysex/sysex_parser.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';

void main() {
  group('RequestKey SD-card operation matching', () {
    test('successful response must carry the requested operation', () {
      final key = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respDirectoryListing,
        sdCardOperation: SdCardOperation.directoryListing,
      );

      expect(
        key.matches(_sdMessage([0, SdCardOperation.directoryListing.code])),
        isTrue,
      );
      expect(
        key.matches(_sdMessage([0, SdCardOperation.fileUpload.code])),
        isFalse,
      );
      expect(
        key.matchesStrict(_sdMessage([0, SdCardOperation.fileUpload.code])),
        isFalse,
      );
    });

    test('operation-less error matches the active SD request', () {
      final key = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respDirectoryListing,
        sdCardOperation: SdCardOperation.fileUpload,
      );
      final error = _sdMessage([1, 110, 111, 112, 101, 0]);

      expect(key.matches(error), isTrue);
      expect(key.matchesStrict(error), isTrue);
    });

    test('operation participates in key equality and hashing', () {
      final listing = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respDirectoryListing,
        sdCardOperation: SdCardOperation.directoryListing,
      );
      final upload = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respDirectoryListing,
        sdCardOperation: SdCardOperation.fileUpload,
      );

      expect(listing, isNot(upload));
      expect({listing, upload}, hasLength(2));
    });
  });

  group('RequestKey algorithm info libraryIndex matching', () {
    test(
      'extracts libraryIndex and checks it in both matches and matchesStrict',
      () {
        final key5 = RequestKey(
          sysExId: 0,
          messageType: DistingNTRespMessageType.respAlgorithmInfo,
          libraryIndex: 5,
        );
        final key6 = RequestKey(
          sysExId: 0,
          messageType: DistingNTRespMessageType.respAlgorithmInfo,
          libraryIndex: 6,
        );
        final msg5 = _algorithmInfoMessage(5);
        final msg300 = _algorithmInfoMessage(300);

        expect(RequestKey.fromDistingNTParsedMessage(msg5).libraryIndex, 5);
        expect(RequestKey.fromDistingNTParsedMessage(msg300).libraryIndex, 300);

        expect(key5.matches(msg5), isTrue);
        expect(key5.matchesStrict(msg5), isTrue);
        expect(key6.matches(msg5), isFalse);
        expect(key6.matchesStrict(msg5), isFalse);
      },
    );

    test('rejects truncated or invalid-header respAlgorithmInfo payloads', () {
      final key0 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respAlgorithmInfo,
        libraryIndex: 0,
      );
      final truncated = DistingNTParsedMessage(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respAlgorithmInfo,
        payload: Uint8List.fromList([0x00, 0x00]),
        rawBytes: Uint8List(0),
      );
      final badHeader = DistingNTParsedMessage(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respAlgorithmInfo,
        payload: Uint8List.fromList([0x04, 0x00, 0x00]),
        rawBytes: Uint8List(0),
      );

      expect(key0.matches(truncated), isFalse);
      expect(key0.matchesStrict(truncated), isFalse);
      expect(key0.matches(badHeader), isFalse);
      expect(key0.matchesStrict(badHeader), isFalse);
    });
  });

  group('RequestKey enum string matching leniency and quarantine overlap', () {
    test('preserves intentional enum parameterNumber leniency in matches but not matchesStrict', () {
      final key = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respEnumStrings,
        algorithmIndex: 2,
        parameterNumber: 7,
      );
      final corruptedParamMsg = DistingNTParsedMessage(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respEnumStrings,
        payload: Uint8List.fromList([2, ...encode16(99), 0]),
        rawBytes: Uint8List(0),
      );
      final wrongSlotMsg = DistingNTParsedMessage(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respEnumStrings,
        payload: Uint8List.fromList([3, ...encode16(7), 0]),
        rawBytes: Uint8List(0),
      );

      expect(key.matches(corruptedParamMsg), isTrue);
      expect(key.matchesStrict(corruptedParamMsg), isFalse);
      expect(key.matches(wrongSlotMsg), isFalse);
      expect(key.matchesStrict(wrongSlotMsg), isFalse);
    });

    test('overlapsForQuarantine captures SD/enum wildcards while isolating unrelated classes', () {
      final sdListing = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respDirectoryListing,
        sdCardOperation: SdCardOperation.directoryListing,
      );
      final sdUpload = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respDirectoryListing,
        sdCardOperation: SdCardOperation.fileUpload,
      );
      expect(sdListing.overlapsForQuarantine(sdUpload), isTrue);

      final enumSlot1Param2 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respEnumStrings,
        algorithmIndex: 1,
        parameterNumber: 2,
      );
      final enumSlot1Param9 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respEnumStrings,
        algorithmIndex: 1,
        parameterNumber: 9,
      );
      final enumSlot2Param2 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respEnumStrings,
        algorithmIndex: 2,
        parameterNumber: 2,
      );
      expect(enumSlot1Param2.overlapsForQuarantine(enumSlot1Param9), isTrue);
      expect(enumSlot1Param2.overlapsForQuarantine(enumSlot2Param2), isFalse);

      final lib5 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respAlgorithmInfo,
        libraryIndex: 5,
      );
      final lib6 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respAlgorithmInfo,
        libraryIndex: 6,
      );
      expect(lib5.overlapsForQuarantine(lib6), isFalse);

      final setting5 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respSettingValue,
        settingId: 5,
      );
      final setting9 = RequestKey(
        sysExId: 0,
        messageType: DistingNTRespMessageType.respSettingValue,
        settingId: 9,
      );
      expect(setting5.overlapsForQuarantine(setting9), isFalse);
    });
  });
}

DistingNTParsedMessage _algorithmInfoMessage(int libraryIndex) {
  return DistingNTParsedMessage(
    sysExId: 0,
    messageType: DistingNTRespMessageType.respAlgorithmInfo,
    payload: Uint8List.fromList([
      ...encode16(libraryIndex),
      ...'test'.codeUnits,
      0,
      ...'Test'.codeUnits,
      0,
    ]),
    rawBytes: Uint8List(0),
  );
}

DistingNTParsedMessage _sdMessage(List<int> payload) {
  return DistingNTParsedMessage(
    sysExId: 0,
    messageType: DistingNTRespMessageType.respDirectoryListing,
    payload: Uint8List.fromList(payload),
    rawBytes: Uint8List(0),
  );
}
