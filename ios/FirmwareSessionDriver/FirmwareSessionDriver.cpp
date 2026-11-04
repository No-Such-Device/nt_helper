#include <DriverKit/IOLib.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSNumber.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IODispatchQueue.h>
#include <DriverKit/IOTimerDispatchSource.h>
#include <DriverKit/OSAction.h>
#include <time.h>
#include <new>
#include <USBDriverKit/USBDriverKit.h>
#include "FirmwareSessionDriver.h"
#include "FirmwareSessionUserClient.h"
#include "SessionCall.hpp"

struct FirmwareSessionDriver_IVars {
    IOLock *lock;
    IODispatchQueue *readQueue;
    IOUSBHostDevice *device;
    IOUSBHostInterface *interface;
    IOUSBHostPipe *input;
    uint8_t interfaceNumber;
    bool stopped;
    bool connected;
    FirmwareSession::Programmer programmer{true};
    uint16_t vid, pid;
};

bool FirmwareSessionDriver::init() {
    if (!super::init()) return false;
    ivars = IONew(FirmwareSessionDriver_IVars, 1);
    if (!ivars) return false;
    new (ivars) FirmwareSessionDriver_IVars{};
    ivars->lock = IOLockAlloc();
    return ivars->lock != nullptr;
}
void FirmwareSessionDriver::free() {
    if (ivars) {
        OSSafeReleaseNULL(ivars->device);
        OSSafeReleaseNULL(ivars->readQueue);
        IOLockFreeZero(ivars->lock);
        ivars->~FirmwareSessionDriver_IVars();
        IOSafeDeleteNULL(ivars, FirmwareSessionDriver_IVars, 1);
    }
    super::free();
}
kern_return_t FirmwareSessionDriver::Start_Impl(IOService *provider) {
    auto ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    auto device = OSDynamicCast(IOUSBHostDevice, provider);
    if (!device) return kIOReturnUnsupported;
    auto descriptor = device->CopyDeviceDescriptor();
    if (!descriptor) return kIOReturnNotReady;
    bool allowed = FirmwareSession::identity(descriptor->idVendor, descriptor->idProduct);
    ivars->vid = descriptor->idVendor; ivars->pid = descriptor->idProduct;
    ivars->programmer = FirmwareSession::Programmer(ivars->vid == 0x1fc9);
    IOUSBHostFreeDescriptor(descriptor);
    if (!allowed) return kIOReturnUnsupported;
    ret = IODispatchQueue::Create("FirmwareSessionRead", kIODispatchQueueReentrant,
        0, &ivars->readQueue);
    if (ret != kIOReturnSuccess) return ret;
    ret = SetDispatchQueue("FirmwareSessionRead", ivars->readQueue);
    if (ret != kIOReturnSuccess) return ret;
    device->retain();
    ivars->device = device;
    // Properties are published only after checking the actual device descriptor.
    auto properties = OSDictionary::withCapacity(2);
    auto vid = OSNumber::withNumber(ivars->vid, 32);
    auto pid = OSNumber::withNumber(ivars->pid, 32);
    if (!properties || !vid || !pid) {
        OSSafeReleaseNULL(properties); OSSafeReleaseNULL(vid); OSSafeReleaseNULL(pid);
        return kIOReturnNoMemory;
    }
    properties->setObject("NTFirmwareVendorID", vid);
    properties->setObject("NTFirmwareProductID", pid);
    ret = SetProperties(properties);
    properties->release(); vid->release(); pid->release();
    if (ret != kIOReturnSuccess) return ret;
    return RegisterService();
}
kern_return_t FirmwareSessionDriver::Stop_Impl(IOService *provider) {
    IOLockLock(ivars->lock);
    ivars->stopped = true;
    IOLockUnlock(ivars->lock);
    Disconnect();
    return Stop(provider, SUPERDISPATCH);
}
kern_return_t FirmwareSessionDriver::NewUserClient_Impl(uint32_t type, IOUserClient **client) {
    if (type != 0) return kIOReturnUnsupported;
    IOService *service = nullptr;
    auto ret = Create(this, "UserClientProperties", &service);
    if (ret != kIOReturnSuccess) return ret;
    *client = OSDynamicCast(FirmwareSessionUserClient, service);
    if (!*client) { service->release(); return kIOReturnError; }
    return kIOReturnSuccess;
}

// Called under the lock, including all partial-setup error paths.
static void closeUsb(FirmwareSessionDriver_IVars *v, IOService *owner) {
    OSSafeReleaseNULL(v->input);
    if (v->interface) {
        v->interface->Close(owner, 0);
        OSSafeReleaseNULL(v->interface);
    }
    if (v->connected) v->device->Close(owner, 0);
    v->connected = false;
}
kern_return_t FirmwareSessionDriver::Connect() {
    IOLockLock(ivars->lock);
    auto ret = kIOReturnNotAttached;
    if (ivars->stopped || !ivars->device) goto done;
    if (ivars->programmer.phase() == FirmwareSession::Phase::failed) { ret = kIOReturnNotReady; goto done; }
    if (ivars->connected) { ret = kIOReturnExclusiveAccess; goto done; }
    ret = ivars->device->Open(this, 0, 0);
    if (ret != kIOReturnSuccess) goto done;
    ivars->connected = true;
    {
        auto config = ivars->device->CopyConfigurationDescriptor(uint8_t(0));
        if (!config) { ret = kIOReturnNotReady; goto failed; }
        // Device-level claim: do not register interfaces for competing HID drivers.
        ret = ivars->device->SetConfiguration(config->bConfigurationValue, false);
        IOUSBHostFreeDescriptor(config);
        if (ret != kIOReturnSuccess) goto failed;
    }
    {
        uintptr_t iterator = 0;
        ret = ivars->device->CreateInterfaceIterator(&iterator);
        if (ret != kIOReturnSuccess) goto failed;
        IOUSBHostInterface *candidate = nullptr;
        while (ivars->device->CopyInterface(iterator, &candidate) == kIOReturnSuccess && candidate) {
            auto config = candidate->CopyConfigurationDescriptor();
            auto descriptor = config ? candidate->GetInterfaceDescriptor(config) : nullptr;
            if (descriptor && descriptor->bInterfaceClass == 3 && descriptor->bAlternateSetting == 0) {
                const IOUSBEndpointDescriptor *endpoint = nullptr;
                while ((endpoint = IOUSBGetNextEndpointDescriptor(config, descriptor,
                           reinterpret_cast<const IOUSBDescriptorHeader *>(endpoint)))) {
                    if ((endpoint->bEndpointAddress & 0x80) && (endpoint->bmAttributes & 3) == 3) {
                        ret = candidate->Open(this, 0, nullptr);
                        if (ret == kIOReturnSuccess) {
                            ivars->interface = candidate;
                            candidate = nullptr;
                            ivars->interfaceNumber = descriptor->bInterfaceNumber;
                            ret = ivars->interface->CopyPipe(endpoint->bEndpointAddress, &ivars->input);
                        }
                        break;
                    }
                }
            }
            if (config) IOUSBHostFreeDescriptor(config);
            OSSafeReleaseNULL(candidate);
            if (ivars->interface) break;
        }
        ivars->device->DestroyInterfaceIterator(iterator);
        if (!ivars->input) { if (ret == kIOReturnSuccess) ret = kIOReturnNotFound; goto failed; }
    }
    ret = kIOReturnSuccess;
    goto done;
failed:
    closeUsb(ivars, this);
done:
    IOLockUnlock(ivars->lock);
    return ret;
}
void FirmwareSessionDriver::Disconnect() {
    IOLockLock(ivars->lock);
    ivars->programmer.fail();
    closeUsb(ivars, this);
    IOLockUnlock(ivars->lock);
}
// The OSAction owns this context through delivery of the completion, including
// a late callback after timeout. No callback references the caller's stack.
struct InterruptReadContext {
    InitialSdp::ReadResult result;
    IOBufferMemoryDescriptor *buffer;
};
void FirmwareSessionDriver::ReadComplete_Impl(OSAction *action, IOReturn status,
    uint32_t actualByteCount, uint64_t) {
    auto context = static_cast<InterruptReadContext *>(action->GetReference());
    context->result.complete(status, actualByteCount);
    OSSafeReleaseNULL(context->buffer);
    if (!context->result.expired) ivars->readQueue->Wakeup(action);
}
kern_return_t FirmwareSessionDriver::ReadInterrupt(IOBufferMemoryDescriptor *buffer,
    uint32_t capacity, uint32_t *transferred, uint32_t timeout) {
    OSAction *action = nullptr;
    auto ret = CreateActionReadComplete(sizeof(InterruptReadContext), &action);
    if (ret != kIOReturnSuccess) return ret;
    auto context = static_cast<InterruptReadContext *>(action->GetReference());
    *context = {};
    buffer->retain();
    context->buffer = buffer;
    ret = ivars->readQueue->RunAction(^kern_return_t {
        const uint64_t deadline = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) +
            uint64_t(timeout) * 1000000;
        const auto result = InitialSdp::submitRead(ivars->input, buffer, capacity,
            transferred, action, context->result, [&]() -> int {
                while (!context->result.done) {
                    auto waited = ivars->readQueue->SleepWithDeadline(action,
                        kIOTimerClockUptimeRaw, deadline);
                    if (context->result.done) break;
                    if (waited != kIOReturnSuccess) return waited;
                }
                return kIOReturnSuccess;
            }, kIOReturnAborted);
        // A rejected submission has no callback. Accepted transfers retain the
        // buffer until ReadComplete, even after abort/timeout or unplug.
        if (!context->result.done && !context->result.expired)
            OSSafeReleaseNULL(context->buffer);
        return result;
    });
    action->release();
    return ret;
}
kern_return_t FirmwareSessionDriver::Execute(uint64_t selector, uint64_t length,
    const uint8_t *bytes, size_t size, uint64_t *phase, uint64_t *sent) {
    *phase = *sent = 0;
    IOLockLock(ivars->lock);
    if (ivars->stopped || !ivars->input) {
        IOLockUnlock(ivars->lock);
        return kIOReturnNotAttached;
    }
    struct Context { FirmwareSessionDriver_IVars *v; FirmwareSessionDriver *owner; IOReturn error; };
    Context ctx = {ivars, this, kIOReturnSuccess};
    FirmwareSession::Usb usb = {&ctx,
        [](void *opaque, const uint8_t *report, size_t size, uint32_t timeout) -> int {
            auto c = static_cast<Context *>(opaque);
            IOBufferMemoryDescriptor *buffer = nullptr;
            c->error = IOBufferMemoryDescriptor::Create(kIOMemoryDirectionOut, size, 0, &buffer);
            if (c->error != kIOReturnSuccess) return 1;
            IOAddressSegment range = {};
            c->error = buffer->SetLength(size);
            if (c->error == kIOReturnSuccess) c->error = buffer->GetAddressRange(&range);
            if (c->error == kIOReturnSuccess) {
                memcpy(reinterpret_cast<void *>(range.address), report, size);
                c->error = FirmwareSession::submitOutput(c->v->device, c->owner,
                    c->v->interfaceNumber, report[0], uint16_t(size), buffer, timeout);
            }
            buffer->release();
            return c->error != kIOReturnSuccess;
        },
        [](void *opaque, uint8_t *report, size_t capacity, size_t *size, uint32_t timeout) -> int {
            auto c = static_cast<Context *>(opaque);
            IOBufferMemoryDescriptor *buffer = nullptr;
            c->error = IOBufferMemoryDescriptor::Create(kIOMemoryDirectionIn, capacity, 0, &buffer);
            if (c->error != kIOReturnSuccess) return 1;
            IOAddressSegment range = {};
            c->error = buffer->SetLength(capacity);
            if (c->error == kIOReturnSuccess) c->error = buffer->GetAddressRange(&range);
            uint32_t transferred = 0;
            if (c->error == kIOReturnSuccess)
                c->error = c->owner->ReadInterrupt(buffer, uint32_t(capacity), &transferred, timeout);
            if (c->error == kIOReturnSuccess && transferred <= capacity) {
                memcpy(report, reinterpret_cast<void *>(range.address), transferred);
                *size = transferred;
            } else if (c->error == kIOReturnSuccess) c->error = kIOReturnOverrun;
            buffer->release();
            return c->error != kIOReturnSuccess;
        }};
    bool ok = ivars->programmer.call(selector, ivars->vid, ivars->pid, usb, length, bytes, size);
    *phase = uint64_t(ivars->programmer.phase()); *sent = ivars->programmer.sent();
    if (!ok) closeUsb(ivars, this);
    IOLockUnlock(ivars->lock);
    return ok ? kIOReturnSuccess : (ctx.error ? ctx.error : kIOReturnBadArgument);
}
