#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include "InitialSdpDriver.h"
#include "InitialSdpUserClient.h"
#include "StatusOnly.hpp"

struct InitialSdpUserClient_IVars { InitialSdpDriver *driver; };
bool InitialSdpUserClient::init() {
    if (!super::init()) return false;
    ivars = IONewZero(InitialSdpUserClient_IVars, 1);
    return ivars != nullptr;
}
void InitialSdpUserClient::free() {
    if (ivars) {
        OSSafeReleaseNULL(ivars->driver);
        IOSafeDeleteNULL(ivars, InitialSdpUserClient_IVars, 1);
    }
    super::free();
}
kern_return_t InitialSdpUserClient::Start_Impl(IOService *provider) {
    auto ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    auto driver = OSDynamicCast(InitialSdpDriver, provider);
    if (!driver) return kIOReturnBadArgument;
    ret = driver->Connect();
    if (ret == kIOReturnSuccess) {
        driver->retain();
        ivars->driver = driver;
    }
    return ret;
}
kern_return_t InitialSdpUserClient::Stop_Impl(IOService *provider) {
    if (ivars->driver) ivars->driver->Disconnect();
    OSSafeReleaseNULL(ivars->driver);
    return Stop(provider, SUPERDISPATCH);
}
kern_return_t InitialSdpUserClient::ExternalMethod(uint64_t selector,
    IOUserClientMethodArguments *args, const IOUserClientMethodDispatch *,
    OSObject *, void *) {
    if (!args || !args->scalarOutput) return kIOReturnBadArgument;
    InitialSdp::Call call = {selector, args->scalarInputCount,
        args->structureInput ? args->structureInput->getLength() : 0,
        args->scalarOutputCount, size_t(args->structureOutputMaximumSize),
        bool(args->structureInputDescriptor || args->structureOutputDescriptor),
        args->completion != nullptr};
    if (!InitialSdp::accepts(call)) return kIOReturnBadArgument;
    args->scalarOutput[0] = args->scalarOutput[1] = 0;
    if (!ivars->driver) return kIOReturnNotAttached;
    return ivars->driver->Query(&args->scalarOutput[0], &args->scalarOutput[1]);
}
