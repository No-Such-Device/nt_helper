#include "../InitialSdpDriver/StatusOnly.hpp"
#include <assert.h>
#include <stdio.h>
#include <string.h>
using namespace InitialSdp;

struct Probe {
    unsigned writes = 0, reads = 0;
    int failAt = -1;
    int malformedAt = -1;
    int malformedKind = 0;
    int DeviceRequest(void *, uint8_t type, uint8_t request, uint16_t value,
                      uint16_t index, uint16_t length, const uint8_t *data,
                      uint16_t *transferred, uint32_t timeout) {
        assert(writes++ == 0 && reads == 0);
        assert(type == 0x21 && request == 9 && value == 0x0201 && index == 2 && length == 17);
        assert(timeout == 1000);
        const uint8_t expected[17] = {1, 5, 5};
        assert(memcmp(data, expected, sizeof(expected)) == 0);
        *transferred = length;
        return failAt == 0 ? -1 : 0;
    }
    int AsyncIO(uint8_t *data, uint32_t capacity, ReadResult *completion, uint32_t timeout) {
        assert(writes == 1 && reads < 2);
        assert(capacity == 65 && timeout == 0);
        uint32_t count = 0;
        auto size = &count;
        unsigned index = reads++;
        if (failAt == int(index + 1)) return -1;
        *size = index == 0 ? 5 : 65;
        data[0] = index == 0 ? 3 : 4;
        uint32_t word = index == 0 ? 0x56787856 : 0xf0f0f0f0;
        for (int b = 0; b < 4; ++b) data[b + 1] = uint8_t(word >> (b * 8));
        if (malformedAt == int(index)) {
            if (malformedKind == 0) *size = 0;
            if (malformedKind == 1) --*size;
            if (malformedKind == 2) ++*size;
            if (malformedKind == 3) data[0] = index == 0 ? 4 : 3;
            if (malformedKind == 4) data[1] ^= 1;
        }
        completion->complete(0, count);
        return 0;
    }
    int Abort(unsigned, int, void *) { assert(false); return 0; }
    Usb usb() {
        return {this, 2,
            [](void *context, const Control &request, const uint8_t *data, uint32_t timeout) {
                auto p = static_cast<Probe *>(context);
                uint16_t transferred = 0;
                return submitControl(p, context, request, data, &transferred, timeout);
            },
            [](void *context, uint8_t *data, size_t capacity, size_t *size, uint32_t timeout) {
                auto p = static_cast<Probe *>(context);
                uint32_t transferred = 0;
                ReadResult completion;
                assert(timeout == 1000);
                int result = submitRead(p, data, uint32_t(capacity), &transferred,
                    &completion, completion, [&] {
                        assert(completion.done);
                        return 0;
                    }, -2);
                *size = transferred;
                return result;
            }};
    }
};
constexpr Call query = {0, 0, 0, 2, 0, false, false};

// AC-004: desktop/MIDI tests cannot observe the DriverKit USB submission seam.
// Exercise the production encoder/dispatcher, including control fields, exact
// outgoing bytes, endpoint read direction, transfer bounds, and response decoding.
static void ac004_only_fixed_error_status_reaches_usb() {
    Probe probe;
    Response response = {};
    assert(dispatch(query, vendor, product, probe.usb(), response) == Result::ok);
    assert(probe.writes == 1 && probe.reads == 2);
    assert(response.hab == 0x56787856 && response.status == 0xf0f0f0f0);
}

// AC-004: UI-only allowlists do not protect a direct native user-client caller.
// Reject selectors, arbitrary data/descriptors/async calls, output mismatches,
// and any identity other than the initial ROM before the USB callbacks run.
static void ac004_rejected_operations_never_reach_usb() {
    const Call rejected[] = {
        {1,0,0,2,0,false,false}, {0x0505,0,0,2,0,false,false},
        {0x0404,0,0,2,0,false,false}, {0x0b0b,0,0,2,0,false,false},
        {UINT64_MAX,0,0,2,0,false,false}, {0,1,0,2,0,false,false},
        {0,0,1,2,0,false,false}, {0,0,1024,2,0,false,false},
        {0,0,0,0,0,false,false}, {0,0,0,3,0,false,false},
        {0,0,0,2,1,false,false}, {0,0,0,2,0,true,false},
        {0,0,0,2,0,false,true}
    };
    for (auto call : rejected) {
        Probe probe;
        Response response = {123, 456};
        assert(dispatch(call, vendor, product, probe.usb(), response) == Result::rejected);
        assert(probe.writes == 0 && probe.reads == 0);
        assert(response.hab == 0 && response.status == 0);
    }
    const uint16_t identities[][2] = {{0x15a2,0x0073},{0x1fc9,0x0073},{0x15a2,0x0135},{0,0}};
    for (const auto &identity : identities) {
        Probe probe;
        Response response = {};
        assert(dispatch(query, identity[0], identity[1], probe.usb(), response) == Result::rejected);
        assert(probe.writes == 0 && probe.reads == 0);
    }
}

// AC-004: a valid outgoing query is not proof of a decoded reply. Existing
// firmware tests do not cover short/wrong SDP reports or partial USB failure.
static void ac004_malformed_and_failed_io_never_returns_status() {
    for (int step = 0; step < 3; ++step) {
        Probe probe; probe.failAt = step;
        Response response = {123,456};
        assert(dispatch(query, vendor, product, probe.usb(), response) == Result::transport);
        assert(response.hab == 0 && response.status == 0);
        assert(probe.reads == unsigned(step));
    }
    for (int report = 0; report < 2; ++report) {
        for (int kind = 0; kind < (report == 0 ? 5 : 4); ++kind) {
            Probe probe; probe.malformedAt = report; probe.malformedKind = kind;
            Response response = {123,456};
            assert(dispatch(query, vendor, product, probe.usb(), response) == Result::malformed);
            assert(response.hab == 0 && response.status == 0);
            assert(probe.reads == unsigned(report + 1));
        }
    }
}
// AC-004 distinct native retry regression from independent inspection: a failed
// direct user-client exchange must be poisoned even without Flutter cleanup.
// The per-call malformed-response tests above cannot detect stale-reply reuse.
static void ac004_incomplete_exchange_requires_new_native_session() {
    for (int scenario = 0; scenario < 2; ++scenario) {
        const bool malformed = scenario == 1;
        Session session = {};
        Probe probe;
        if (malformed) probe.malformedAt = 1; else probe.failAt = 2;
        Response response = {};
        assert(session.query(query, vendor, product, probe.usb(), response) != Result::ok);
        assert(session.failed);
        probe.failAt = -1; probe.malformedAt = -1;
        unsigned writes = probe.writes, reads = probe.reads;
        assert(session.query(query, vendor, product, probe.usb(), response) == Result::unavailable);
        assert(response.hab == 0 && response.status == 0);
        assert(probe.writes == writes && probe.reads == reads);
    }
}
// The original probe incorrectly accepted a nonzero USB interrupt timeout.
// Exercise the actual submission/wait/abort seam with controlled completion,
// rather than sleeping or merely asserting the protocol encoder's output.
static void interrupt_read_uses_zero_usb_timeout_and_separate_deadline() {
    struct Pipe {
        bool submitted = false, aborted = false;
        int submitError = 0;
        int AsyncIO(uint8_t *, uint32_t capacity, ReadResult *, uint32_t timeout) {
            assert(capacity == 65 && timeout == 0);
            submitted = true;
            return submitError;
        }
        int Abort(unsigned options, int error, void *client) {
            assert(submitted && options == 0 && error == -2 && client == nullptr);
            aborted = true;
            return 0;
        }
    };
    for (int scenario = 0; scenario < 4; ++scenario) {
        Pipe pipe;
        ReadResult completion;
        uint8_t bytes[65] = {};
        uint32_t transferred = 999;
        bool waited = false;
        if (scenario == 3) pipe.submitError = -3;
        int result = submitRead(&pipe, bytes, 65, &transferred, &completion,
            completion, [&] {
                waited = true;
                assert(pipe.submitted && !completion.done && !pipe.aborted);
                // Simulate a response before the deadline, an unplug, or expiry.
                if (scenario == 0) completion.complete(0, 5);
                if (scenario == 1) completion.complete(-4, 0);
                return scenario == 2 ? -1 : 0;
            }, -2);
        assert(waited == (scenario != 3));
        assert(pipe.aborted == (scenario == 2));
        assert(result == (scenario == 0 ? 0 : scenario == 1 ? -4 : scenario == 2 ? -1 : -3));
        assert(transferred == (scenario == 0 ? 5u : 0u));
        if (scenario == 2) {
            completion.complete(0, 65); // A late reply cannot revive a timed-out read.
            assert(completion.expired && !completion.done && completion.bytes == 0);
            assert(transferred == 0);
        }
    }
}
int main() {
    interrupt_read_uses_zero_usb_timeout_and_separate_deadline();
    ac004_only_fixed_error_status_reaches_usb();
    ac004_rejected_operations_never_reach_usb();
    ac004_malformed_and_failed_io_never_returns_status();
    ac004_incomplete_exchange_requires_new_native_session();
    puts("AC-004: fixed USB boundary, rejected operations, malformed/failed responses passed");
}
