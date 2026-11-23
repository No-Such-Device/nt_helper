import 'package:nt_helper/domain/disting_nt_sysex.dart'
    show DistingNTRespMessageType;
import 'package:nt_helper/domain/sd_card_operation.dart';
import 'package:nt_helper/domain/sysex/sysex_parser.dart';
import 'package:nt_helper/domain/sysex/sysex_utils.dart';

class RequestKey {
  final int sysExId;
  final DistingNTRespMessageType?
  messageType; // Optional in the case of messages that don't return a value
  final int? algorithmIndex; // Optional - slot index (0-7)
  final int? parameterNumber; // Optional
  final int? settingId;
  final int? libraryIndex; // Optional - algorithm library index (0-N)
  final SdCardOperation? sdCardOperation; // Optional - SD operation (1-8)

  RequestKey({
    required this.sysExId,
    this.messageType,
    this.algorithmIndex,
    this.parameterNumber,
    this.libraryIndex,
    this.settingId,
    this.sdCardOperation,
  });

  factory RequestKey.fromDistingNTParsedMessage(DistingNTParsedMessage msg) {
    int? algorithmIndex;
    int? parameterNumber;
    int? settingId;
    SdCardOperation? sdCardOperation;

    switch (msg.messageType) {
      case DistingNTRespMessageType.respSettingInfo:
      case DistingNTRespMessageType.respSettingValue:
        if (msg.payload.length >= 3 && msg.payload[0] <= 3) {
          settingId = decode16(msg.payload, 0);
        }
        break;
      // These messages have an algorithm index as the first payload byte.
      case DistingNTRespMessageType.respNumParameters:
      case DistingNTRespMessageType.respAllParameterValues:
      case DistingNTRespMessageType.respAlgorithm:
      case DistingNTRespMessageType.respParameterPages:
      case DistingNTRespMessageType.respRouting:
        if (msg.payload.isNotEmpty) {
          algorithmIndex = msg.payload[0];
        }
        break;

      // These messages have both algorithm and parameter indices.
      case DistingNTRespMessageType.respParameterInfo:
      case DistingNTRespMessageType.respParameterValue:
      case DistingNTRespMessageType.respEnumStrings:
      case DistingNTRespMessageType.respMapping:
      case DistingNTRespMessageType.respParameterValueString:
        if (msg.payload.isNotEmpty) {
          algorithmIndex = msg.payload[0];
        }
        if (msg.payload.length >= 4) {
          // decode16 reads 3 bytes at offset 1, so we need indices 1,2,3
          parameterNumber = decode16(msg.payload, 1);
        }
        break;
      case DistingNTRespMessageType.respOutputModeUsage:
        if (msg.payload.isNotEmpty) {
          algorithmIndex = msg.payload[0];
        }
        if (msg.payload.length >= 4) {
          // Output mode usage uses unsigned parameter numbers
          parameterNumber = decode16Unsigned(msg.payload, 1);
        }
        break;

      // Perf page item response: payload[1] = item index (used as parameterNumber for matching)
      case DistingNTRespMessageType.respPerfPageItem:
        if (msg.payload.length >= 2) {
          parameterNumber = msg.payload[1];
        }
        break;

      // Successful SD responses carry [status, operation, ...data].
      // Error responses carry [status, ...message] and cannot be attributed to
      // an operation from their wire payload.
      case DistingNTRespMessageType.respDirectoryListing:
        if (msg.payload.length >= 2 && msg.payload[0] == 0) {
          sdCardOperation = SdCardOperation.fromCode(msg.payload[1]);
        }
        break;

      // Other messages don't have these indices.
      case DistingNTRespMessageType.respAlgorithmInfo:
      default:
        break;
    }

    return RequestKey(
      sysExId: msg.sysExId,
      messageType: msg.messageType,
      algorithmIndex: algorithmIndex,
      parameterNumber: parameterNumber,
      sdCardOperation: sdCardOperation,
      settingId: settingId,
    );
  }

  bool matches(DistingNTParsedMessage msg) {
    if (sysExId != msg.sysExId) return false;
    if (messageType != msg.messageType) return false;

    // Create a key from the message to easily access its embedded indices
    final responseKey = RequestKey.fromDistingNTParsedMessage(msg);

    if (algorithmIndex != null &&
        algorithmIndex != responseKey.algorithmIndex) {
      return false;
    }

    // For enum strings, be lenient with parameterNumber matching since firmware
    // may return corrupted values for some algorithms (e.g., Macro Oscillator).
    // We still require algorithmIndex to match to avoid out-of-order issues.
    if (messageType == DistingNTRespMessageType.respEnumStrings) {
      return true;
    }

    if (parameterNumber != null &&
        parameterNumber != responseKey.parameterNumber) {
      return false;
    }

    if (settingId != null && settingId != responseKey.settingId) return false;

    if (!_matchesSdCardOperation(msg, responseKey)) {
      return false;
    }

    return true;
  }

  /// Strict matching — like [matches] but without the lenient enum string
  /// workaround. Used by expired handlers to avoid cross-contamination between
  /// different parameter requests on the same slot.
  bool matchesStrict(DistingNTParsedMessage msg) {
    if (sysExId != msg.sysExId) return false;
    if (messageType != msg.messageType) return false;

    final responseKey = RequestKey.fromDistingNTParsedMessage(msg);

    if (algorithmIndex != null &&
        algorithmIndex != responseKey.algorithmIndex) {
      return false;
    }

    if (parameterNumber != null &&
        parameterNumber != responseKey.parameterNumber) {
      return false;
    }

    if (settingId != null && settingId != responseKey.settingId) return false;

    if (!_matchesSdCardOperation(msg, responseKey)) {
      return false;
    }

    return true;
  }

  bool _matchesSdCardOperation(
    DistingNTParsedMessage msg,
    RequestKey responseKey,
  ) {
    if (sdCardOperation == null) {
      return true;
    }

    final isSdError =
        messageType == DistingNTRespMessageType.respDirectoryListing &&
        msg.payload.isNotEmpty &&
        msg.payload[0] != 0;
    if (isSdError) {
      return true;
    }

    return sdCardOperation == responseKey.sdCardOperation;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RequestKey &&
          runtimeType == other.runtimeType &&
          sysExId == other.sysExId &&
          messageType == other.messageType &&
          algorithmIndex == other.algorithmIndex &&
          parameterNumber == other.parameterNumber &&
          libraryIndex == other.libraryIndex &&
          settingId == other.settingId &&
          sdCardOperation == other.sdCardOperation;

  @override
  int get hashCode => Object.hash(
    sysExId,
    messageType,
    algorithmIndex,
    parameterNumber,
    libraryIndex,
    settingId,
    sdCardOperation,
  );

  @override
  String toString() =>
      "RequestKey(settingId: $settingId, sysExId: $sysExId, algorithmIndex: $algorithmIndex, parameterNumber: $parameterNumber, libraryIndex: $libraryIndex, sdCardOperation: $sdCardOperation, messageType: $messageType)";
}
