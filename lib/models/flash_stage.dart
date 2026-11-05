/// Stages of the firmware flash process
enum FlashStage {
  sdpConnect('SDP_CONNECT'),
  blCheck('BL_CHECK'),
  sdpUpload('SDP_UPLOAD'),
  write('WRITE'),
  configure('CONFIGURE'),
  reset('RESET'),
  complete('COMPLETE'),
  programmingComplete('PROGRAMMING_COMPLETE');

  final String machineValue;

  const FlashStage(this.machineValue);

  /// Parse a stage from the machine output format
  static FlashStage? fromMachineValue(String value) {
    for (final stage in FlashStage.values) {
      if (stage.machineValue == value) {
        return stage;
      }
    }
    return null;
  }
}
