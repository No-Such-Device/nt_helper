#include <DriverKit/IOLib.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSNumber.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <USBDriverKit/USBDriverKit.h>
#include "InitialSdpDriver.h"
#include "InitialSdpUserClient.h"
#include "StatusOnly.hpp"

struct InitialSdpDriver_IVars {
    IOLock *lock;
    IOUSBHostDevice *device;
    IOUSBHostInterface *interface;
    IOUSBHostPipe *input;
    uint8_t interfaceNumber;
    bool stopped;
    bool connected;
    InitialSdp::Session session;
};

bool InitialSdpDriver::init() {
    if (!super::init()) return false;
    ivars = IONewZero(InitialSdpDriver_IVars, 1);
    if (!ivars) return false;
    ivars->lock = IOLockAlloc();
    return ivars->lock != nullptr;
}
void InitialSdpDriver::free() {
    if (ivars) {
        OSSafeReleaseNULL(ivars->device);
        IOLockFreeZero(ivars->lock);
        IOSafeDeleteNULL(ivars, InitialSdpDriver_IVars, 1);
    }
    super::free();
}
kern_return_t InitialSdpDriver::Start_Impl(IOService *provider) {
    auto ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    auto device = OSDynamicCast(IOUSBHostDevice, provider);
    if (!device) return kIOReturnUnsupported;
    auto descriptor = device->CopyDeviceDescriptor();
    if (!descriptor) return kIOReturnNotReady;
    bool allowed = InitialSdp::initialIdentity(descriptor->idVendor, descriptor->idProduct);
    IOUSBHostFreeDescriptor(descriptor);
    if (!allowed) return kIOReturnUnsupported;
    device->retain();
    ivars->device = device;
    // Properties are published only after checking the actual device descriptor.
    auto properties = OSDictionary::withCapacity(2);
    auto vid = OSNumber::withNumber(InitialSdp::vendor, 32);
    auto pid = OSNumber::withNumber(InitialSdp::product, 32);
    if (!properties || !vid || !pid) {
        OSSafeReleaseNULL(properties); OSSafeReleaseNULL(vid); OSSafeReleaseNULL(pid);
        return kIOReturnNoMemory;
    }
    properties->setObject("NTInitialVendorID", vid);
    properties->setObject("NTInitialProductID", pid);
    ret = SetProperties(properties);
    properties->release(); vid->release(); pid->release();
    if (ret != kIOReturnSuccess) return ret;
    return RegisterService();
}
kern_return_t InitialSdpDriver::Stop_Impl(IOService *provider) {
    IOLockLock(ivars->lock);
    ivars->stopped = true;
    IOLockUnlock(ivars->lock);
    Disconnect();
    return Stop(provider, SUPERDISPATCH);
}
kern_return_t InitialSdpDriver::NewUserClient_Impl(uint32_t type, IOUserClient **client) {
    if (type != 0) return kIOReturnUnsupported;
    IOService *service = nullptr;
    auto ret = Create(this, "UserClientProperties", &service);
    if (ret != kIOReturnSuccess) return ret;
    *client = OSDynamicCast(InitialSdpUserClient, service);
    if (!*client) { service->release(); return kIOReturnError; }
    return kIOReturnSuccess;
}

// Called under the lock, including all partial-setup error paths.
static void closeUsb(InitialSdpDriver_IVars *v, IOService *owner) {
    OSSafeReleaseNULL(v->input);
    if (v->interface) {
        v->interface->Close(owner, 0);
        OSSafeReleaseNULL(v->interface);
    }
    if (v->connected) v->device->Close(owner, 0);
    v->connected = false;
}
kern_return_t InitialSdpDriver::Connect() {
    IOLockLock(ivars->lock);
    auto ret = kIOReturnNotAttached;
    if (ivars->stopped || !ivars->device) goto done;
    if (ivars->session.failed) { ret = kIOReturnNotReady; goto done; }
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
void InitialSdpDriver::Disconnect() {
    IOLockLock(ivars->lock);
    closeUsb(ivars, this);
    IOLockUnlock(ivars->lock);
}
kern_return_t InitialSdpDriver::Query(uint64_t *hab, uint64_t *status) {
    *hab = *status = 0;
    IOLockLock(ivars->lock);
    if (ivars->stopped || !ivars->input) {
        IOLockUnlock(ivars->lock);
        return kIOReturnNotAttached;
    }
    struct Context { InitialSdpDriver_IVars *v; IOService *owner; IOReturn error; };
    Context ctx = {ivars, this, kIOReturnSuccess};
    InitialSdp::Usb usb = {&ctx, ivars->interfaceNumber,
        [](void *opaque, const InitialSdp::Control &request,
           const uint8_t *report, uint32_t timeout) -> int {
            auto c = static_cast<Context *>(opaque);
            const auto size = request.length;
            IOBufferMemoryDescriptor *buffer = nullptr;
            c->error = IOBufferMemoryDescriptor::Create(kIOMemoryDirectionOut, size, 0, &buffer);
            if (c->error != kIOReturnSuccess) return 1;
            IOAddressSegment range = {};
            c->error = buffer->GetAddressRange(&range);
            if (c->error == kIOReturnSuccess) c->error = buffer->SetLength(size);
            if (c->error == kIOReturnSuccess) {
                memcpy(reinterpret_cast<void *>(range.address), report, size);
                uint16_t transferred = 0;
                // HID SET_REPORT(Output, report 1); no other control request is exposed.
                c->error = InitialSdp::submitControl(c->v->device, c->owner,
                    request, buffer, &transferred, timeout);
                if (c->error == kIOReturnSuccess && transferred != size) c->error = kIOReturnUnderrun;
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
            c->error = buffer->GetAddressRange(&range);
            if (c->error == kIOReturnSuccess) c->error = buffer->SetLength(capacity);
            uint32_t transferred = 0;
            if (c->error == kIOReturnSuccess)
                c->error = InitialSdp::submitRead(c->v->input, buffer, uint32_t(capacity), &transferred, timeout);
            if (c->error == kIOReturnSuccess && transferred <= capacity) {
                memcpy(report, reinterpret_cast<void *>(range.address), transferred);
                *size = transferred;
            } else if (c->error == kIOReturnSuccess) c->error = kIOReturnOverrun;
            buffer->release();
            return c->error != kIOReturnSuccess;
        }};
    InitialSdp::Response response = {};
    auto result = ivars->session.query({0, 0, 0, 2, 0, false, false},
        InitialSdp::vendor, InitialSdp::product, usb, response);
    if (result == InitialSdp::Result::ok) { *hab = response.hab; *status = response.status; }
    else closeUsb(ivars, this);
    IOLockUnlock(ivars->lock);
    if (result == InitialSdp::Result::transport) return ctx.error;
    return result == InitialSdp::Result::ok ? kIOReturnSuccess : kIOReturnBadMessageID;
}
