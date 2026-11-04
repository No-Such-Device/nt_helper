import Foundation

@_silgen_name("firmwareTranscriptCreate") private func transcriptCreate() -> UnsafeMutableRawPointer
@_silgen_name("firmwareTranscriptDestroy") private func transcriptDestroy(_ pointer: UnsafeMutableRawPointer)
@_silgen_name("firmwareTranscriptComplete") private func transcriptComplete(_ pointer: UnsafeMutableRawPointer) -> Int32
@_silgen_name("firmwareTranscriptCall") private func transcriptCall(_ pointer: UnsafeMutableRawPointer,
    _ rom: UInt32, _ selector: UInt64, _ length: UInt64, _ data: UnsafeRawPointer?, _ size: Int,
    _ phase: UnsafeMutablePointer<UInt64>, _ count: UnsafeMutablePointer<UInt64>) -> Int32

private let rom = FirmwareDevice(id: 1, location: 42, vendor: 0x1fc9, product: 0x135)
private let loader = FirmwareDevice(id: 2, location: 42, vendor: 0x15a2, product: 0x73)
private final class DeviceIO: FirmwareDeviceIO {
    var devices: [FirmwareDevice] = []
    var calls: [String] = []
    var completions: [(Result<FirmwareReceipt, Error>) -> Void] = []
    func inventory() throws -> [FirmwareDevice] { devices }
    func perform(_ device: FirmwareDevice, _ operation: FirmwareOperation,
                 completion: @escaping (Result<FirmwareReceipt, Error>) -> Void) {
        switch operation {
        case .open: calls.append("open:\(device.id)")
        case .begin(let n): calls.append("begin:\(n)")
        case .data(let bytes): calls.append("data:\(bytes.count)")
        case .advance: calls.append("advance")
        case .close: calls.append("close:\(device.id)"); completion(.success(FirmwareReceipt(phase: 0, count: 0))); return
        }
        completions.append(completion)
    }
    func reply(_ phase: UInt64, _ count: Int = 0) {
        precondition(!completions.isEmpty)
        completions.removeFirst()(.success(FirmwareReceipt(phase: phase, count: count)))
    }
}
private final class Fixture {
    var time: TimeInterval = 0
    let io = DeviceIO()
    var events: [[String: Any]] = []
    lazy var state = FirmwareSessionState(io: io, now: { [unowned self] in time }, event: { [unowned self] in events.append($0) })
    func start() throws -> String {
        let id = try state.prepare()
        try state.start(id: id, loader: Data(repeating: 0x55, count: 1025), application: Data(repeating: 0xaa, count: 1025))
        io.devices = [rom]; state.poll()
        return id
    }
    var last: String? { events.last?["phase"] as? String }
    func finishRom() {
        io.reply(0); io.reply(1); io.reply(1, 1024); io.reply(2, 1025)
        precondition(last == "jumping")
        io.devices = []; state.poll(); precondition(state.session != nil)
        io.reply(3, 1025); precondition(last == "waitingLoader")
    }
}
// End-to-end native contract: real Swift ownership/phase orchestration calls the
// production C++ programmer and its actual USB submission templates at both stages.
private func complete_session_runs_production_two_stage_usb_transcript() throws {
    final class TranscriptIO: FirmwareDeviceIO {
        let native = transcriptCreate()
        var devices: [FirmwareDevice] = []
        deinit { transcriptDestroy(native) }
        func inventory() throws -> [FirmwareDevice] { devices }
        func perform(_ device: FirmwareDevice, _ operation: FirmwareOperation,
                     completion: @escaping (Result<FirmwareReceipt, Error>) -> Void) {
            var phase: UInt64 = 0, count: UInt64 = 0
            var selector: UInt64 = 0, length: UInt64 = 0, bytes = Data()
            switch operation {
            case .open: selector = 0x200
            case .begin(let n): selector = 0x201; length = UInt64(n)
            case .data(let data): selector = 0x202; bytes = data
            case .advance: selector = 0x203
            case .close: selector = 0x204
            }
            let code = bytes.withUnsafeBytes { data in
                transcriptCall(native, device.rom ? 1 : 0, selector, length,
                    bytes.isEmpty ? nil : data.baseAddress, bytes.count, &phase, &count)
            }
            precondition(code == 0)
            if phase == 3 { devices = [] }
            if phase == 10 { devices = [] }
            completion(.success(FirmwareReceipt(phase: phase, count: Int(count))))
        }
    }
    let io = TranscriptIO()
    var phases: [String] = []
    let state = FirmwareSessionState(io: io, now: { 0 }, event: { phases.append($0["phase"] as! String) })
    let id = try state.prepare()
    try state.start(id: id, loader: Data(repeating: 0x55, count: 1025), application: Data(repeating: 0xaa, count: 1025))
    io.devices = [rom]; state.poll()
    precondition(phases.last == "waitingLoader")
    io.devices = [loader]; state.poll()
    precondition(phases.last == "programmed" && transcriptComplete(io.native) == 1)
    precondition(phases.filter { $0 == "programmed" }.count == 1)
}
private func complete_session_requires_attributed_reenumeration_and_reset_receipt() throws {
    let f = Fixture(); let id = try f.start()
    f.finishRom()
    f.io.devices = [loader]; f.state.poll()
    f.io.reply(0); f.io.reply(4); f.io.reply(5); f.io.reply(6); f.io.reply(7); f.io.reply(8)
    f.io.reply(8, 1024); f.io.reply(9, 1025)
    precondition(f.last == "resetting")
    f.io.devices = []; f.state.poll()
    precondition(f.last == "resetting") // Disconnect alone is not a validated reset.
    f.io.reply(10, 1025)
    precondition(f.last == "programmed" && f.state.session == nil)
    precondition(f.events.allSatisfy { $0["sessionId"] as? String == id })
    precondition(f.io.calls == ["open:1", "begin:1025", "data:1024", "data:1", "advance", "close:1",
        "open:2", "begin:1025", "advance", "advance", "advance", "advance", "data:1024", "data:1", "advance", "close:2"])
    precondition(f.events.filter { $0["phase"] as? String == "programmed" }.count == 1)
}
private func cancellation_and_lifecycle_reject_late_callbacks_and_do_not_retry() throws {
    for lifecycle in [false, true] {
        let f = Fixture(); let id = try f.start()
        if lifecycle { f.state.interrupt() } else { try f.state.cancel(id: id) }
        let before = f.io.calls.count
        precondition(f.state.session == nil && f.last == (lifecycle ? "failed" : "canceled"))
        f.io.devices = []
        let next = try f.state.prepare(); precondition(next != id)
        f.io.reply(0); f.state.poll() // Old open completes after a new reservation.
        precondition(f.io.calls.count == before && f.state.session == next)
        do { try f.state.cancel(id: id); preconditionFailure("stale cancel accepted") } catch {}
        precondition(f.state.session == next)
    }
}
private func preexisting_ambiguous_wrong_location_and_unexpected_loss_fail_closed() throws {
    let preexisting = Fixture(); preexisting.io.devices = [loader]
    do { _ = try preexisting.state.prepare(); preconditionFailure("preexisting accepted") } catch {}
    for devices in [[rom,loader], [FirmwareDevice(id: 3, location: 42, vendor: 0x15a2, product: 0x135)], []] {
        let f = Fixture(); _ = try f.start(); f.io.devices = devices; f.state.poll()
        precondition(f.last == "failed"); f.io.reply(0)
        precondition(!f.io.calls.contains("begin:1025"))
    }
    let f = Fixture(); _ = try f.start(); f.finishRom()
    f.io.devices = [FirmwareDevice(id: 3, location: 43, vendor: 0x15a2, product: 0x73)]; f.state.poll()
    precondition(f.last == "failed" && !f.io.calls.contains("open:3"))
}
private func bounded_transition_io_and_malformed_receipts_cannot_advance() throws {
    for mode in 0..<4 {
        let f = Fixture(); _ = try f.start()
        switch mode {
        case 0: f.time = 121; f.state.poll(); f.io.reply(0)
        case 1: f.io.reply(99)
        case 2: f.io.reply(0, 1)
        default:
            f.finishRom(); f.time = 16; f.state.poll()
        }
        precondition(f.last == "failed" && f.state.session == nil)
        precondition(!f.events.contains { $0["phase"] as? String == "programmed" })
    }
}
private func concurrent_start_and_invalid_lengths_do_not_program() throws {
    let f = Fixture(); let id = try f.state.prepare()
    do { _ = try f.state.prepare(); preconditionFailure("concurrent prepare") } catch {}
    do { try f.state.start(id: id, loader: Data(), application: Data([1])); preconditionFailure("empty loader") } catch {}
    do { try f.state.start(id: id, loader: Data([1]), application: Data(repeating: 0, count: FirmwareSessionState.maxApplication+1)); preconditionFailure("oversize app") } catch {}
    precondition(f.io.calls.isEmpty)
    try f.state.start(id: id, loader: Data([1]), application: Data([1]))
    do { try f.state.start(id: id, loader: Data([1]), application: Data([1])); preconditionFailure("concurrent start") } catch {}
}
@main struct SessionStateTests {
    static func main() throws {
        try complete_session_runs_production_two_stage_usb_transcript()
        try complete_session_requires_attributed_reenumeration_and_reset_receipt()
        try cancellation_and_lifecycle_reject_late_callbacks_and_do_not_retry()
        try preexisting_ambiguous_wrong_location_and_unexpected_loss_fail_closed()
        try bounded_transition_io_and_malformed_receipts_cannot_advance()
        try concurrent_start_and_invalid_lengths_do_not_program()
        print("V2 session ownership, transitions, cancellation, deadlines and stale callbacks passed")
    }
}
