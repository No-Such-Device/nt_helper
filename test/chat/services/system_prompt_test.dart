import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/services/system_prompt.dart';

void main() {
  test('bakes durable user setup rules into the stable prompt prefix', () {
    final prompt = distingNtSystemPrompt();

    expect(prompt, contains('`yymmdd-[description]`'));
    expect(prompt, contains('Never reuse a preset name'));
    expect(prompt, contains('USB Filesystem mode'));
    expect(prompt, contains('`midi_channel: 14`'));
    expect(prompt, contains("Use its GUID and `algorithm_info`"));
  });
}
