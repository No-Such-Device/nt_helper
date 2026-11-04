#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include "FirmwareSessionDriver.h"
#include "FirmwareSessionUserClient.h"
#include "SessionCall.hpp"

struct FirmwareSessionUserClient_IVars { FirmwareSessionDriver *driver; };
bool FirmwareSessionUserClient::init() {
    if (!super::init()) return false;
    ivars = IONewZero(FirmwareSessionUserClient_IVars, 1);
    return ivars != nullptr;
}
void FirmwareSessionUserClient::free() {
    if (ivars) {
        OSSafeReleaseNULL(ivars->driver);
        IOSafeDeleteNULL(ivars, FirmwareSessionUserClient_IVars, 1);
    }
    super::free();
}
kern_return_t FirmwareSessionUserClient::Start_Impl(IOService *provider) {
    auto ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    auto driver = OSDynamicCast(FirmwareSessionDriver, provider);
    if (!driver) return kIOReturnBadArgument;
    ret = driver->Connect();
    if (ret == kIOReturnSuccess) {
        driver->retain();
        ivars->driver = driver;
    }
    return ret;
}
kern_return_t FirmwareSessionUserClient::Stop_Impl(IOService *provider) {
    if (ivars->driver) ivars->driver->Disconnect();
    OSSafeReleaseNULL(ivars->driver);
    return Stop(provider, SUPERDISPATCH);
}
kern_return_t FirmwareSessionUserClient::ExternalMethod(uint64_t selector,
    IOUserClientMethodArguments *args, const IOUserClientMethodDispatch *,
    OSObject *, void *) {
    if (!args || !args->scalarOutput) return kIOReturnBadArgument;
    InitialSdp::Call call = {selector, args->scalarInputCount,
        args->structureInput ? args->structureInput->getLength() : 0,
        args->scalarOutputCount, size_t(args->structureOutputMaximumSize),
        bool(args->structureInputDescriptor || args->structureOutputDescriptor),
        args->completion != nullptr};
    if (!FirmwareSession::accepts(call)) return kIOReturnBadArgument;
    args->scalarOutput[0] = args->scalarOutput[1] = 0;
    if (!ivars->driver) return kIOReturnNotAttached;
    if (selector == FirmwareSession::handshake) {
        args->scalarOutput[0] = FirmwareSession::api;
        args->scalarOutput[1] = FirmwareSession::maxLoader;
        args->scalarOutput[2] = FirmwareSession::maxApplication;
        return kIOReturnSuccess;
    }
    return ivars->driver->Execute(selector,
        args->scalarInputCount ? args->scalarInput[0] : 0,
        args->structureInput ? static_cast<const uint8_t *>(args->structureInput->getBytesNoCopy()) : nullptr,
        call.structureInputs, &args->scalarOutput[0], &args->scalarOutput[1]);
}
