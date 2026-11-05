#pragma once
#include "Programming.hpp"
namespace FirmwareSession {
inline bool accepts(const InitialSdp::Call &c) {
    if (c.hasDescriptors || c.hasCompletion || c.structureOutputs) return false;
    if (c.selector == identify)
        return !c.scalarInputs && !c.structureInputs && c.scalarOutputs == 4;
    if (c.selector == handshake)
        return !c.scalarInputs && !c.structureInputs && c.scalarOutputs == 3;
    if (c.scalarOutputs != 2) return false;
    if (c.selector == begin) return c.scalarInputs == 1 && !c.structureInputs;
    if (c.selector == append) return !c.scalarInputs && c.structureInputs && c.structureInputs <= chunkSize;
    return (c.selector == advance || c.selector == cancel) && !c.scalarInputs && !c.structureInputs;
}
}
