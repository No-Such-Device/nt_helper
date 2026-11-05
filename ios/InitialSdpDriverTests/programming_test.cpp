#include "../FirmwareSessionDriver/SessionCall.hpp"
#include <assert.h>
#include <stdio.h>
#include <vector>
using namespace FirmwareSession;
using Bytes = std::vector<uint8_t>;
struct Transfer { bool output; Bytes bytes; };
static Bytes word(uint8_t id, uint32_t value, size_t size) {
    Bytes b(size); b[0]=id; put(b.data()+1,value); return b;
}
static Bytes command(uint8_t tag, uint8_t flags, std::initializer_list<uint32_t> params) {
    Bytes b(8+4*params.size()); b[0]=1; b[2]=uint8_t(b.size()-4);
    b[4]=tag; b[5]=flags; b[7]=uint8_t(params.size());
    size_t i=8; for(auto p:params) { put(b.data()+i,p); i+=4; } return b;
}
static Bytes response(uint8_t tag) {
    Bytes b={3,0,12,0,0xa0,0,0,2,0,0,0,0,tag,0,0,0}; return b;
}
static Bytes data(uint8_t id, size_t size, uint8_t value, bool rom) {
    Bytes b(rom?1025:4+size); b[0]=id;
    if(!rom) {b[2]=uint8_t(size); b[3]=uint8_t(size>>8);}
    for(size_t i=rom?1:4;i<(rom?1+size:b.size());++i)b[i]=value;
    return b;
}
// Existing status-only tests cannot reach the programming encoder or these USB
// submissions. This transcript is the wire contract, not mocked phase completion.
struct Probe {
    std::vector<Transfer> transcript;
    size_t cursor=0; int failAt=-1, corruptAt=-1, corruptKind=0;
    size_t pending=0; bool aborted=false, readFailure=false;
    int DeviceRequest(void *, uint8_t type, uint8_t request, uint16_t value,
        uint16_t index, uint16_t length, const uint8_t *bytes, uint16_t *transferred, uint32_t timeout) {
        assert(cursor<transcript.size()); auto &t=transcript[cursor];
        assert(t.output && type==0x21 && request==9 && value==(0x200|bytes[0]) && index==2);
        assert(timeout==ioTimeout && length==t.bytes.size());
        assert(Bytes(bytes,bytes+length)==t.bytes);
        *transferred=length;
        if(int(cursor)==corruptAt) --*transferred;
        return int(cursor++)==failAt?-1:0;
    }
    int AsyncIO(uint8_t *bytes, uint32_t capacity, InitialSdp::ReadResult *completion, uint32_t timeout) {
        assert(cursor<transcript.size()); auto t=transcript[cursor];
        assert(!t.output && timeout==0 && capacity>=t.bytes.size());
        pending=cursor++;
        if(int(pending)==failAt) {
            if(readFailure) completion->complete(-4,0);
            return 0; // Accepted, but failed or no receipt before the deadline.
        }
        size_t n=t.bytes.size();
        if(int(pending)==corruptAt) {
            if(corruptKind==0) --n;
            if(corruptKind==1) t.bytes[0]^=1;
            if(corruptKind==2) t.bytes[1]^=1;
            if(corruptKind==3) t.bytes[4]^=1;
            if(corruptKind==4) t.bytes.back()^=1;
            if(corruptKind==5) n=0;
            if(corruptKind==6) {completion->complete(0,capacity+1); return 0;}
            if(corruptKind==7) t.bytes[12]^=1;
            if(corruptKind==8) t.bytes[2]^=1;
            if(corruptKind==9) t.bytes[7]^=1;
            if(corruptKind==10) t.bytes[5]^=1;
        }
        memcpy(bytes,t.bytes.data(),n); completion->complete(0,uint32_t(n)); return 0;
    }
    int Abort(unsigned, int, void *) { aborted=true; return 0; }
    Usb usb() {return {this,
        [](void *c,const uint8_t *p,size_t n,uint32_t timeout) {
            auto probe=static_cast<Probe*>(c);
            return submitOutput(probe,c,2,p[0],uint16_t(n),p,timeout);
        },
        [](void *c,uint8_t *p,size_t capacity,size_t *n,uint32_t timeout) {
            assert(timeout==ioTimeout || timeout==eraseTimeout);
            auto probe=static_cast<Probe*>(c); InitialSdp::ReadResult completion;
            uint32_t transferred=0;
            int result=InitialSdp::submitRead(probe,p,uint32_t(capacity),&transferred,&completion,
                completion,[&]{return completion.done?0:-2;},-3);
            *n=transferred;
            if(completion.expired) {completion.complete(0,16); assert(!completion.done);}
            return result;
        }};}
};
static Probe romTranscript(size_t n) {
    Probe p;
    Bytes write={1,4,4,0x20,0,0x1c,0,0,0,0,0,0,0,0,0,0,0};
    for(unsigned i=0;i<4;++i)write[8+i]=uint8_t(n>>(24-i*8));
    p.transcript.push_back({true,write});
    for(size_t sent=0;sent<n;sent+=1024)p.transcript.push_back({true,data(2,std::min(size_t(1024),n-sent),0x55,true)});
    p.transcript.push_back({false,word(3,0x56787856,5)});
    p.transcript.push_back({false,word(4,0x88888888,65)});
    p.transcript.push_back({true,{1,0x0b,0x0b,0x20,0,0x1c,0,0,0,0,0,0,0,0,0,0,0}});
    p.transcript.push_back({false,word(3,0x56787856,5)}); return p;
}
static Probe appTranscript(size_t n) {
    Probe p;
    auto cmd=[&](uint8_t tag,std::initializer_list<uint32_t> params,uint8_t flags=0) {
        p.transcript.push_back({true,command(tag,flags,params)});
        p.transcript.push_back({false,response(tag)});
    };
    p.transcript.push_back({true,command(7,0,{0x0b,0})});
    p.transcript.push_back({false,{3,0,12,0,0xa7,0,0,2,0,0,0,0,0,4,0,0}});
    cmd(5,{0x2000,4,0xc0000008}); cmd(0x11,{9,0x2000});
    cmd(2,{0x60000000,uint32_t((n+0x1fff)&~size_t(0xfff)),0});
    cmd(5,{0x2000,4,0xf000000f}); cmd(0x11,{9,0x2000});
    cmd(4,{0x60001000,uint32_t(n),0},1);
    for(size_t sent=0;sent<n;sent+=1024)p.transcript.push_back({true,data(2,std::min(size_t(1024),n-sent),0xaa,false)});
    p.transcript.push_back({false,response(4)}); cmd(0x0b,{}); return p;
}
static bool run(Programmer &engine,Probe &p,size_t n,bool rom) {
    const uint16_t vid=rom?0x1fc9:0x15a2,pid=rom?0x0135:0x0073;
    auto call=[&](uint64_t s,uint64_t length=0,const uint8_t *b=nullptr,size_t size=0) {
        return engine.call(s,vid,pid,p.usb(),length,b,size);
    };
    if(!call(begin,n))return false;
    if(!rom)for(int i=0;i<4;++i)if(!call(advance))return false;
    Bytes bytes(1024,rom?0x55:0xaa);
    for(size_t i=0;i<n;i+=1024)if(!call(append,0,bytes.data(),std::min(size_t(1024),n-i)))return false;
    return call(advance);
}
static void complete_two_stage_transcript_validates_all_submissions() {
    for(size_t n:{size_t(1),size_t(1024),size_t(1025),size_t(4097)})for(bool rom:{true,false}) {
        auto p=rom?romTranscript(n):appTranscript(n); Programmer e(rom);
        assert(run(e,p,n,rom)); assert(p.cursor==p.transcript.size() && e.sent()==n);
        assert(e.phase()==(rom?Phase::jumped:Phase::reset));
    }
    for(bool rom:{true,false}) {
        size_t n=rom?maxLoader:maxApplication;
        auto p=rom?romTranscript(n):appTranscript(n); Programmer e(rom);
        assert(run(e,p,n,rom) && e.sent()==n && p.cursor==p.transcript.size());
    }
}
static void every_missing_receipt_or_short_submission_poison_session_without_retry() {
    for(bool rom:{true,false}) {
        auto original=rom?romTranscript(1025):appTranscript(1025);
        for(size_t i=0;i<original.transcript.size();++i) {
            auto p=original; p.failAt=int(i); Programmer e(rom);
            assert(!run(e,p,1025,rom)); assert(e.phase()==Phase::failed);
            auto before=p.cursor; assert(!e.call(begin,rom?0x1fc9:0x15a2,rom?0x135:0x73,p.usb(),1025));
            assert(p.cursor==before);
            if(original.transcript[i].output) {
                p=original; p.corruptAt=int(i); Programmer shortWrite(rom);
                assert(!run(shortWrite,p,1025,rom));
            } else {
                p=original; p.failAt=int(i); p.readFailure=true; Programmer unplugged(rom);
                assert(!run(unplugged,p,1025,rom));
            }
        }
    }
}
static void malformed_status_framing_length_and_command_echo_fail_closed() {
    for(bool rom:{true,false}) {
        auto original=rom?romTranscript(1):appTranscript(1);
        for(size_t i=0;i<original.transcript.size();++i)if(!original.transcript[i].output) {
            for(int kind:{0,1,2,3,5,6}) {
                auto p=original; p.corruptAt=int(i); p.corruptKind=kind; Programmer e(rom);
                assert(!run(e,p,1,rom));
            }
            if(!rom && original.transcript[i].bytes[4]==0xa0) for(int kind:{7,8,9,10}) {
                auto p=original; p.corruptAt=int(i); p.corruptKind=kind; Programmer e(false);
                assert(!run(e,p,1,false));
            }
        }
    }
    // A missing final reset ACK cannot inherit the desktop reset-success shortcut.
    auto p=appTranscript(1); p.corruptAt=int(p.transcript.size()-1); p.corruptKind=4;
    Programmer e(false); assert(!run(e,p,1,false));
}
static void forbidden_identities_selectors_ranges_and_out_of_order_data_never_submit() {
    assert(lengths(1,1) && lengths(maxLoader,maxApplication));
    assert(!lengths(0,1) && !lengths(1,0) && !lengths(UINT64_MAX,1));
    for(auto id:std::vector<std::pair<uint16_t,uint16_t>>{{0,0},{0x15a2,0x135},{0x1fc9,0x73},{0x15a2,0x73}}) {
        Probe p; Programmer e(true); assert(!e.call(begin,id.first,id.second,p.usb(),1)); assert(!p.cursor);
    }
    for(uint64_t n:{uint64_t(0),uint64_t(maxLoader)+1,UINT64_MAX}) {
        Probe p; Programmer e(true); assert(!e.call(begin,0x1fc9,0x135,p.usb(),n)); assert(!p.cursor);
    }
    for(uint64_t n:{uint64_t(0),uint64_t(maxApplication)+1,UINT64_MAX}) {
        Probe p; Programmer e(false); assert(!e.call(begin,0x15a2,0x73,p.usb(),n)); assert(!p.cursor);
    }
    for(uint64_t selector:{uint64_t(0),uint64_t(0x0404),uint64_t(0x60001000),advance,append,cancel}) {
        Probe p; Programmer e(true); assert(!e.call(selector,0x1fc9,0x135,p.usb())); assert(!p.cursor);
    }
    for(uint64_t selector:{uint64_t(0),uint64_t(0x0505),UINT64_MAX})
        assert(!accepts({selector,0,0,2,0,false,false}));
    assert(accepts({handshake,0,0,3,0,false,false}));
    assert(!accepts({begin,1,1,2,0,false,false}));
    assert(!accepts({append,0,1025,2,0,false,false}));
    assert(!accepts({advance,0,0,2,0,true,false}));
    assert(!accepts({advance,0,0,2,0,false,true}));
}
static void cancellation_and_incomplete_data_cannot_jump_or_reset() {
    auto p=romTranscript(1025); Programmer e(true);
    assert(e.call(begin,0x1fc9,0x135,p.usb(),1025));
    assert(!e.call(advance,0x1fc9,0x135,p.usb())); assert(p.cursor==1);
    p=romTranscript(1025); Programmer canceled(true);
    assert(canceled.call(begin,0x1fc9,0x135,p.usb(),1025));
    assert(!canceled.call(cancel,0x1fc9,0x135,p.usb()));
    uint8_t b=0; assert(!canceled.call(append,0x1fc9,0x135,p.usb(),0,&b,1)); assert(p.cursor==1);
}
static void loader_reads_end_at_one_endpoint_packet_not_an_extra_four_bytes() {
    assert(inputRequestSize(false, 1028, 1024) == 1024);
    assert(inputRequestSize(false, 1028, 512) == 512);
    assert(inputRequestSize(false, 1028, 64) == 64);
    assert(inputRequestSize(false, 16, 1024) == 16);
    assert(inputRequestSize(false, 1028, 0) == 0);
    assert(inputRequestSize(false, 1028, 8) == 0);
    assert(inputRequestSize(true, 65, 512) == 65);
}
static void rom_uses_control_and_flashloader_uses_interrupt_without_fallback() {
    int controls = 0, interrupts = 0;
    auto control = [&]() { ++controls; return 7; };
    auto interrupt = [&]() { ++interrupts; return 9; };
    assert(submitReport(0x1fc9, 0x135, control, interrupt) == 7);
    assert(controls == 1 && interrupts == 0);
    assert(submitReport(0x15a2, 0x73, control, interrupt) == 9);
    assert(controls == 1 && interrupts == 1);
    assert(submitReport(0x15a2, 0x135, control, interrupt) == -1);
    assert(controls == 1 && interrupts == 1);
}
static void readonly_identity_accepts_only_empty_input_and_four_scalar_outputs() {
    assert(accepts({0x205,0,0,4,0,false,false}));
    assert(!accepts({0x205,1,0,4,0,false,false}));
    assert(!accepts({0x205,0,1,4,0,false,false}));
    assert(!accepts({0x205,0,0,3,0,false,false}));
    assert(!accepts({0x205,0,0,4,1,false,false}));
    assert(!accepts({0x205,0,0,4,0,true,false}));
    assert(!accepts({0x205,0,0,4,0,false,true}));
    assert(!InitialSdp::accepts({0x205,0,0,4,0,false,false}));
    assert(!accepts({0x206,0,0,8,0,false,false}));
}
#ifdef FIRMWARE_TRANSCRIPT_BRIDGE
int programmingTestMain() {
#else
int main() {
#endif
    loader_reads_end_at_one_endpoint_packet_not_an_extra_four_bytes();
    rom_uses_control_and_flashloader_uses_interrupt_without_fallback();
    readonly_identity_accepts_only_empty_input_and_four_scalar_outputs();
    complete_two_stage_transcript_validates_all_submissions();
    every_missing_receipt_or_short_submission_poison_session_without_retry();
    malformed_status_framing_length_and_command_echo_fail_closed();
    forbidden_identities_selectors_ranges_and_out_of_order_data_never_submit();
    cancellation_and_incomplete_data_cannot_jump_or_reset();
    puts("AC-003: two-stage production USB submissions and fail-closed negatives passed");
    return 0;
}

#ifdef FIRMWARE_TRANSCRIPT_BRIDGE
// The Swift session test drives the same production encoder and USB probes
// through both observed identities, not a second flashing implementation.
struct NativeTranscript {
    Probe rom = romTranscript(1025), app = appTranscript(1025);
    Programmer romEngine{true}, appEngine{false};
};
extern "C" void *firmwareTranscriptCreate() { return new NativeTranscript; }
extern "C" void firmwareTranscriptDestroy(void *opaque) { delete static_cast<NativeTranscript *>(opaque); }
extern "C" int firmwareTranscriptComplete(void *opaque) {
    auto t=static_cast<NativeTranscript *>(opaque);
    return t->rom.cursor==t->rom.transcript.size() && t->app.cursor==t->app.transcript.size();
}
extern "C" int firmwareTranscriptCall(void *opaque, uint32_t rom, uint64_t selector,
    uint64_t length, const uint8_t *data, size_t size, uint64_t *phase, uint64_t *count) {
    auto t=static_cast<NativeTranscript *>(opaque);
    auto &engine=rom?t->romEngine:t->appEngine;
    auto &probe=rom?t->rom:t->app;
    if(selector==handshake) {
        assert(accepts({selector,0,0,3,0,false,false}));
        assert(!InitialSdp::accepts({selector,0,0,3,0,false,false}));
        *phase=0; *count=0; return engine.phase()==Phase::ready?0:-1;
    }
    if(selector==cancel) {engine.fail(); *phase=*count=0; return 0;}
    assert(accepts({selector,uint32_t(selector==begin),size,2,0,false,false}));
    bool ok=engine.call(selector,rom?0x1fc9:0x15a2,rom?0x135:0x73,probe.usb(),length,data,size);
    *phase=uint64_t(engine.phase()); *count=engine.sent(); return ok?0:-1;
}
#endif
