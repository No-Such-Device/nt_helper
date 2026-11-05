#pragma once
// Protocol adapted from nt-flash e5f47b1c and NXP BLFWK 6797678f.
// Copyright (c) 2025 Neal Sanche; Copyright (c) 2015 Freescale Semiconductor, Inc.
// Copyright 2016-2018 NXP. BSD-3-Clause; see NOTICES.txt.
#include "../InitialSdpDriver/StatusOnly.hpp"
#include <string.h>

namespace FirmwareSession {
constexpr uint64_t api = 0x4e540002;
constexpr uint32_t driverRevision = 8;
constexpr uint64_t identify = 0x205;
constexpr uint64_t handshake = 0x200, begin = 0x201, append = 0x202,
                   advance = 0x203, cancel = 0x204;
constexpr uint32_t ram = 0x20001c00, flash = 0x60000000, application = flash + 0x1000;
constexpr uint32_t maxLoader = 0x20020000 - ram, maxApplication = 0x800000 - 0x1000;
constexpr uint32_t chunkSize = 1024, ioTimeout = 2000, eraseTimeout = 30000;
enum class Phase : uint64_t {
    ready, uploading, uploaded, jumped, loaderReady, configured, erased,
    fcbCreated, writing, written, reset, failed
};
inline bool identity(uint16_t vid, uint16_t pid) {
    return (vid == 0x1fc9 && pid == 0x0135) || (vid == 0x15a2 && pid == 0x0073);
}
inline bool lengths(uint64_t loader, uint64_t app) {
    return loader && loader <= maxLoader && app && app <= maxApplication;
}
inline uint32_t le(const uint8_t *p) {
    return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
inline void put(uint8_t *p, uint32_t n) {
    for (unsigned i = 0; i < 4; ++i) p[i] = uint8_t(n >> (8*i));
}
// Both production and transcript devices pass through this exact submission and
// byte-count check, below the encoder. No caller can supply control fields.
template<class Device, class Client, class Memory>
int submitOutput(Device *device, Client *client, uint8_t interfaceNumber,
                 uint8_t reportID, uint16_t length, Memory *buffer, uint32_t timeout) {
    uint16_t transferred = 0;
    InitialSdp::Control request = {0x21, 9, uint16_t(0x0200 | reportID), interfaceNumber, length};
    int error = InitialSdp::submitControl(device, client, request, buffer, &transferred, timeout);
    return error ? error : transferred == length ? 0 : -1;
}
// ROM exposes control SET_REPORT output; the running flashloader exposes an
// interrupt OUT endpoint. Never silently fall back after a failed submission.
template<class Control, class Interrupt>
int submitReport(uint16_t vendor, uint16_t product, Control control, Interrupt interrupt) {
    if (!identity(vendor, product)) return -1;
    return vendor == 0x1fc9 ? control() : interrupt();
}
// A raw interrupt transfer is not a HID report read. Requesting more than
// one full loader endpoint packet can wait for a nonexistent following packet.
inline uint32_t inputRequestSize(bool rom, uint32_t capacity, uint32_t endpointPacketSize) {
    if (rom) return capacity;
    if (endpointPacketSize < 16) return 0;
    return capacity < endpointPacketSize ? capacity : endpointPacketSize;
}
struct Usb {
    void *context;
    int (*output)(void *, const uint8_t *, size_t, uint32_t);
    int (*input)(void *, uint8_t *, size_t, size_t *, uint32_t);
};
// One device lifetime, one sequence. A partial/invalid call poisons the session;
// there is deliberately no retry, address, opcode, erase-all or read API.
class Programmer {
    Phase phase_ = Phase::ready;
    bool rom_;
    uint32_t total_ = 0, sent_ = 0, packetSize_ = chunkSize;
    bool send(const Usb &usb, const uint8_t *bytes, size_t size) {
        return usb.output(usb.context, bytes, size, ioTimeout) == 0;
    }
    bool hab(const Usb &usb) {
        uint8_t report[65] = {}; size_t n = 0;
        return usb.input(usb.context, report, sizeof(report), &n, ioTimeout) == 0 &&
            n == 5 && report[0] == 3 && le(report+1) == 0x56787856;
        // This package recipe is unsigned: secure/HAB-enabled parts fail closed.
    }
    bool romCommand(const Usb &usb, uint8_t tag, uint32_t count) {
        uint8_t report[17] = {1, tag, tag};
        for (unsigned i = 0; i < 4; ++i) {
            report[3+i] = uint8_t(ram >> (24-8*i));
            report[8+i] = uint8_t(count >> (24-8*i));
        }
        return send(usb, report, sizeof(report));
    }
    bool romReceipt(const Usb &usb) {
        if (!hab(usb)) return false;
        uint8_t report[65] = {}; size_t n = 0;
        return usb.input(usb.context, report, sizeof(report), &n, ioTimeout) == 0 &&
            n == sizeof(report) && report[0] == 4 && le(report+1) == 0x88888888;
    }
    bool command(const Usb &usb, uint8_t tag, uint8_t flags,
                 uint32_t a = 0, uint32_t b = 0, uint32_t c = 0, uint8_t count = 3) {
        uint8_t report[20] = {1, 0, uint8_t(4+4*count), 0, tag, flags, 0, count};
        if (count > 0) put(report+8, a);
        if (count > 1) put(report+12, b);
        if (count > 2) put(report+16, c);
        return send(usb, report, 8+4*count);
    }
    bool response(const Usb &usb, uint8_t tag, uint32_t timeout = ioTimeout) {
        uint8_t report[1028] = {}; size_t n = 0;
        if (usb.input(usb.context, report, sizeof(report), &n, timeout) != 0) return false;
        // HID devices may pad a report; the declared payload must be exactly the
        // generic response, and must be wholly present in the transfer.
        return n >= 16 && n <= sizeof(report) && report[0] == 3 && report[1] == 0 &&
            report[2] == 12 && report[3] == 0 && report[4] == 0xa0 &&
            report[5] == 0 && report[6] == 0 && report[7] == 2 &&
            le(report+8) == 0 && le(report+12) == tag;
    }
    bool fixed(const Usb &usb, uint8_t tag, uint32_t a, uint32_t b, uint32_t c,
               uint8_t count = 3, uint32_t timeout = ioTimeout) {
        return command(usb, tag, 0, a, b, c, count) && response(usb, tag, timeout);
    }
    bool packetSize(const Usb &usb) {
        if (!command(usb, 7, 0, 0x0b, 0, 0, 2)) return false;
        uint8_t report[1028] = {}; size_t n = 0;
        if (usb.input(usb.context, report, sizeof(report), &n, ioTimeout) != 0 ||
            n < 16 || n > sizeof(report) || report[0] != 3 || report[1] != 0 ||
            report[2] != 12 || report[3] != 0 || report[4] != 0xa7 ||
            report[5] || report[6] || report[7] != 2 || le(report+8) != 0) return false;
        auto size = le(report+12);
        if (!size || size > 8192) return false;
        packetSize_ = size < chunkSize ? size : chunkSize;
        return true;
    }
public:
    explicit Programmer(bool rom) : rom_(rom) {}
    Phase phase() const { return phase_; }
    uint32_t sent() const { return sent_; }
    bool call(uint64_t selector, uint16_t vid, uint16_t pid, const Usb &usb,
              uint64_t length = 0, const uint8_t *bytes = nullptr, size_t size = 0) {
        bool ok = false;
        if (phase_ == Phase::failed) return false;
        if (!identity(vid,pid) || rom_ != (vid == 0x1fc9)) return fail();
        if (selector == cancel) return fail();
        if (selector == begin && phase_ == Phase::ready && !bytes && !size &&
            length && length <= (rom_ ? maxLoader : maxApplication)) {
            total_ = uint32_t(length);
            if (rom_) { ok = romCommand(usb, 4, total_); if (ok) phase_ = Phase::uploading; }
            else { ok = packetSize(usb); if (ok) phase_ = Phase::loaderReady; }
        } else if (selector == append && !length && bytes && size && size <= chunkSize &&
                   (phase_ == Phase::uploading || phase_ == Phase::writing) && size <= total_-sent_) {
            ok = true;
            for (size_t offset = 0; ok && offset < size;) {
                size_t count = size-offset;
                if (count > packetSize_) count = packetSize_;
                uint8_t report[1028] = {2};
                size_t header = rom_ ? 1 : 4;
                if (!rom_) { report[2] = uint8_t(count); report[3] = uint8_t(count >> 8); }
                memcpy(report+header, bytes+offset, count);
                ok = send(usb, report, rom_ ? 1025 : header+count);
                if (ok) { sent_ += uint32_t(count); offset += count; }
            }
            if (ok && sent_ == total_) {
                ok = rom_ ? romReceipt(usb) : response(usb, 4);
                if (ok) phase_ = rom_ ? Phase::uploaded : Phase::written;
            }
        } else if (selector == advance && !length && !bytes && !size) {
            switch (phase_) {
            case Phase::uploaded:
                ok = romCommand(usb, 0x0b, 0) && hab(usb);
                if (ok) phase_ = Phase::jumped;
                break;
            case Phase::loaderReady:
                ok = fixed(usb, 5, 0x2000, 4, 0xc0000008) && fixed(usb, 0x11, 9, 0x2000, 0, 2);
                if (ok) phase_ = Phase::configured;
                break;
            case Phase::configured: {
                const uint32_t erase = (total_ + 0x1000 + 0xfff) & ~uint32_t(0xfff);
                ok = erase <= 0x800000 && fixed(usb, 2, flash, erase, 0, 3, eraseTimeout);
                if (ok) phase_ = Phase::erased;
                break;
            }
            case Phase::erased:
                ok = fixed(usb, 5, 0x2000, 4, 0xf000000f) && fixed(usb, 0x11, 9, 0x2000, 0, 2);
                if (ok) phase_ = Phase::fcbCreated;
                break;
            case Phase::fcbCreated:
                ok = command(usb, 4, 1, application, total_, 0) && response(usb, 4);
                if (ok) phase_ = Phase::writing;
                break;
            case Phase::written:
                // Unlike desktop nt-flash, missing reset acknowledgment is not success.
                ok = fixed(usb, 0x0b, 0, 0, 0, 0);
                if (ok) phase_ = Phase::reset;
                break;
            default: break;
            }
        }
        return ok ? true : fail();
    }
    bool fail() { phase_ = Phase::failed; return false; }
};
} // namespace FirmwareSession
