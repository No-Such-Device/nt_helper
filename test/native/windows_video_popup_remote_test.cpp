#include <flutter/standard_method_codec.h>
#include "../../windows/runner/windows_video_popup_remote.h"
#include <cassert>
#include <iostream>
#include <vector>

using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

class Messenger : public flutter::BinaryMessenger {
 public:
  mutable flutter::BinaryReply reply;
  mutable std::unique_ptr<flutter::MethodCall<Value>> call;
  void Send(const std::string& channel, const uint8_t* bytes, size_t size,
            flutter::BinaryReply result) const override {
    assert(channel == "nt_helper/windows_video_popup");
    call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(bytes, size);
    reply = std::move(result);
  }
  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler) override {}
  void Success(const Value& value) {
    auto bytes = flutter::StandardMethodCodec::GetInstance().EncodeSuccessEnvelope(&value);
    reply(bytes->data(), bytes->size());
  }
  void Error(const std::string& code) {
    Value detail("original connection");
    auto bytes = flutter::StandardMethodCodec::GetInstance().EncodeErrorEnvelope(code, "device state is unknown", &detail);
    reply(bytes->data(), bytes->size());
  }
};

int main() {
  Messenger messenger;
  flutter::MethodChannel<Value> main(&messenger, "nt_helper/windows_video_popup",
                                     &flutter::StandardMethodCodec::GetInstance());
  auto alive = std::make_shared<bool>(true);
  Value payload(Map{{Value("hostId"), Value("host-1")}, {Value("connectionId"), Value(7)},
                    {Value("sessionId"), Value("7:1")}});
  Value snapshot(Map{{Value("hostId"), Value("host-1")}, {Value("potValues"), Value(std::vector<Value>{Value(2080), Value(2016), Value(2072)})}});
  int successes = 0, errors = 0;
  std::string last_error;
  const auto result = [&]() {
    return std::make_unique<flutter::MethodResultFunctions<Value>>(
        [&](const Value* value) { ++successes; assert(*value == snapshot); },
        [&](const std::string& code, const std::string&, const Value*) { ++errors; last_error = code; },
        []() { assert(false); });
  };
  for (const auto* method : {"remoteAcquire", "remoteRead", "remoteOpen", "remoteAction", "remoteClose", "remoteDetach"}) {
    ForwardVideoPopupRemote(&main, method, &payload, result(), alive);
    assert(messenger.call->method_name() == method);
    assert(*messenger.call->arguments() == payload);
    assert(successes == 0); // Never fire-and-forget success.
    messenger.Success(snapshot);
    assert(successes == 1);
    successes = 0;
  }
  // Screenshot fallback uses the same result bridge, preserving binary PNG data.
  Value png(std::vector<uint8_t>{137, 80, 78, 71, 13, 10, 26, 10});
  int screenshots = 0;
  auto screenshot_result = std::make_unique<flutter::MethodResultFunctions<Value>>(
      [&](const Value* value) { ++screenshots; assert(*value == png); },
      [](const std::string&, const std::string&, const Value*) { assert(false); },
      []() { assert(false); });
  ForwardVideoPopupRemote(&main, "getHardwareScreenshot", nullptr,
                         std::move(screenshot_result), alive);
  assert(messenger.call->method_name() == "getHardwareScreenshot");
  assert(screenshots == 0);
  messenger.Success(png);
  assert(screenshots == 1);

  // Malformed input reaches main validation unchanged, and real errors return.
  Value invalid("not a map");
  ForwardVideoPopupRemote(&main, "remoteAction", &invalid, result(), alive);
  assert(*messenger.call->arguments() == invalid);
  messenger.Error("remote_failed");
  assert(errors == 1 && last_error == "remote_failed");
  ForwardVideoPopupRemote(nullptr, "remoteAction", &payload, result(), alive);
  assert(errors == 2 && last_error == "remote_unavailable");
  ForwardVideoPopupRemote(&main, "remoteAction", &payload, result(), alive);
  messenger.reply(nullptr, 0); // Unavailable main Dart handler.
  assert(errors == 3 && last_error == "remote_unavailable");
  ForwardVideoPopupRemote(&main, "remoteAction", &payload, result(), alive);
  *alive = false; // Native destruction while a main result is outstanding.
  messenger.Success(snapshot);
  assert(successes == 0);
  messenger.Error("late failure");
  assert(errors == 3);
  std::cout << "Windows native production remote bridge: codec, identities, actual results/errors, unavailable main and destroyed-child cancellation passed. No Win32 GUI/device execution.\n";
}
