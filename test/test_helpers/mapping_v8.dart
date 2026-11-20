import 'dart:typed_data';

Uint8List mappingV8Fixture() => Uint8List.fromList([
  0, 1, 67, 5, 0, 1, 0, // CV, including an opaque flag
  74, 29, 3, 0, 0, 0, 0, 0, 127, // MIDI: suppress view + ignore bypass
  72, 1, 71, 0, 0, 0, 0, 0, 127, // I2C: ID 200, ignore + opaque flag
]);
