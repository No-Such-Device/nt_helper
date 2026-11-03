#pragma once
#include <stddef.h>
#include <stdint.h>

namespace InitialSdp {
constexpr uint16_t vendor = 0x1fc9, product = 0x0135;
constexpr uint32_t timeoutMs = 1000;
constexpr uint64_t statusSelector = 0;
enum class Result { ok, rejected, malformed, transport, unavailable };

// No caller-supplied command, address, report, or payload exists at this seam.
struct Control {
    uint8_t requestType, request;
    uint16_t value, index, length;
};
// These are the production USB API submission sites. Tests substitute the USB
// objects here, below the dispatcher/encoder, rather than mocking its result.
template <class Device, class Client, class Memory>
int submitControl(Device *device, Client *client, const Control &request,
                  Memory *buffer, uint16_t *transferred, uint32_t timeout) {
    return device->DeviceRequest(client, request.requestType, request.request,
        request.value, request.index, request.length, buffer, transferred, timeout);
}
struct ReadResult {
    bool done = false, expired = false;
    int status = 0;
    uint32_t bytes = 0;
    void complete(int result, uint32_t count) {
        if (expired) return;
        status = result;
        bytes = count;
        done = true;
    }
};
// Interrupt pipes require a zero USB timeout. The caller waits on a separate
// deadline and aborts pending I/O on expiry; late callbacks cannot publish data.
template <class Pipe, class Memory, class Action, class Wait>
int submitRead(Pipe *pipe, Memory *buffer, uint32_t capacity,
               uint32_t *transferred, Action *action, ReadResult &completion,
               Wait wait, int abortedError) {
    *transferred = 0;
    int result = pipe->AsyncIO(buffer, capacity, action, 0);
    if (result != 0) return result;
    result = wait();
    if (result != 0) {
        completion.expired = true;
        pipe->Abort(0, abortedError, nullptr);
        return result;
    }
    if (completion.status == 0) *transferred = completion.bytes;
    return completion.status;
}
struct Usb {
    void *context;
    uint8_t interfaceNumber;
    int (*control)(void *, const Control &, const uint8_t *, uint32_t);
    int (*readReport)(void *, uint8_t *, size_t, size_t *, uint32_t);
};
struct Response { uint32_t hab; uint32_t status; };
struct Call {
    uint64_t selector;
    uint32_t scalarInputs;
    size_t structureInputs;
    uint32_t scalarOutputs;
    size_t structureOutputs;
    bool hasDescriptors;
    bool hasCompletion;
};
inline bool accepts(const Call &call) {
    return call.selector == statusSelector && call.scalarInputs == 0 &&
        call.structureInputs == 0 && call.scalarOutputs == 2 &&
        call.structureOutputs == 0 && !call.hasDescriptors && !call.hasCompletion;
}
inline bool initialIdentity(uint16_t vid, uint16_t pid) {
    return vid == vendor && pid == product;
}
inline Result exchange(const Usb &usb, Response &response) {
    // NXP SDP report 1: error-status (0505), with all unused fields zero.
    // BLFWK SDPCommand/SDPUsbHidPacketizer, revision 6797678f142a8c0f.
    const uint8_t report[17] = {1, 5, 5};
    response = {};
    const Control request = {0x21, 0x09, 0x0201, usb.interfaceNumber, sizeof(report)};
    if (usb.control(usb.context, request, report, timeoutMs))
        return Result::transport;
    uint32_t words[2] = {};
    for (unsigned i = 0; i < 2; ++i) {
        uint8_t input[65] = {};
        size_t size = 0;
        if (usb.readReport(usb.context, input, sizeof(input), &size, timeoutMs))
            return Result::transport;
        // HAB is report 3 (4 data bytes); status is report 4 (64 data bytes).
        if (size != (i == 0 ? 5u : 65u) || input[0] != (i == 0 ? 3 : 4))
            return Result::malformed;
        words[i] = uint32_t(input[1]) | uint32_t(input[2]) << 8 |
            uint32_t(input[3]) << 16 | uint32_t(input[4]) << 24;
        if (i == 0 && words[0] != 0x12343412 && words[0] != 0x56787856)
            return Result::malformed;
    }
    response = {words[0], words[1]};
    return Result::ok;
}
inline Result dispatch(const Call &call, uint16_t vid, uint16_t pid,
                       const Usb &usb, Response &response) {
    response = {};
    if (!accepts(call) || !initialIdentity(vid, pid)) return Result::rejected;
    return exchange(usb, response);
}
// SDP has no request correlation token. After incomplete I/O the service must
// not reuse a delayed reply, even when called directly without the Flutter app.
// Only hardware re-enumeration creates a fresh service/session.
struct Session {
    bool failed;
    Result query(const Call &call, uint16_t vid, uint16_t pid,
                 const Usb &usb, Response &response) {
        response = {};
        if (failed) return Result::unavailable;
        auto result = dispatch(call, vid, pid, usb, response);
        if (result == Result::transport || result == Result::malformed) failed = true;
        return result;
    }
};
} // namespace InitialSdp
