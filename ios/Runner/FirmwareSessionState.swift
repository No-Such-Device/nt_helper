#if FIRMWARE_SESSION_V2 || FIRMWARE_SESSION_TEST
import Foundation

struct FirmwareDevice: Equatable {
    let id: UInt64
    let location: UInt64
    let vendor: Int
    let product: Int
    var rom: Bool { vendor == 0x1fc9 && product == 0x0135 }
    var loader: Bool { vendor == 0x15a2 && product == 0x0073 }
}
enum FirmwareOperation {
    case open, begin(Int), data(Data), advance, close
}
struct FirmwareReceipt {
    let phase: UInt64
    let count: Int
}
protocol FirmwareDeviceIO {
    func inventory() throws -> [FirmwareDevice]
    func perform(_ device: FirmwareDevice, _ operation: FirmwareOperation,
                 completion: @escaping (Result<FirmwareReceipt, Error>) -> Void)
}

// Main-queue session ownership. The I/O adapter uses a separate serial queue;
// cancellation invalidates pending completions immediately, without racing a
// close against a DriverKit call. Tests control time and each I/O completion.
final class FirmwareSessionState {
    static let api: UInt64 = 0x4e540002
    static let maxLoader = 0x1e400, maxApplication = 0x7ff000
    private let io: FirmwareDeviceIO
    private let now: () -> TimeInterval
    private let event: ([String: Any]) -> Void
    private(set) var session: String?
    private(set) var phase = "idle"
    private var generation = 0
    private var loader = Data(), application = Data()
    private var selected: FirmwareDevice?
    private var origin: FirmwareDevice?
    private var offset = 0
    private var pending = false
    private var deadline: TimeInterval = 0
    private var prepared = false
    private var resetAcknowledged = false
    private var recoveryDevice: FirmwareDevice?

    init(io: FirmwareDeviceIO, now: @escaping () -> TimeInterval,
         event: @escaping ([String: Any]) -> Void) {
        self.io = io; self.now = now; self.event = event
    }
    func prepare(allowAttachedBootloader: Bool = false) throws -> String {
        guard session == nil else { throw failure("A firmware session already owns USB.") }
        let devices = try io.inventory()
        recoveryDevice = nil
        if allowAttachedBootloader {
            guard devices.count == 1, let device = devices.first, (device.rom || device.loader), device.location != 0 else {
                throw failure("Recovery requires exactly one identified ROM bootloader or RAM flashloader.")
            }
            recoveryDevice = device
        } else if !devices.isEmpty {
            throw failure("A bootloader is already attached; it cannot be attributed to this update.")
        }
        let id = UUID().uuidString
        session = id; prepared = true; phase = "prepared"; deadline = now()+30
        return id
    }
    func start(id: String, loader: Data, application: Data) throws {
        guard id == session, prepared, now() < deadline,
              !loader.isEmpty, loader.count <= Self.maxLoader,
              !application.isEmpty, application.count <= Self.maxApplication else {
            throw failure("Invalid, expired or concurrent firmware session, or out-of-range bytes.")
        }
        prepared = false; self.loader = loader; self.application = application
        if let recoveryDevice, recoveryDevice.loader {
            origin = recoveryDevice; selected = recoveryDevice
            setPhase("configuringNor", timeout: 15)
            openThenBegin(recoveryDevice, bytes: application, rom: false)
        } else {
            setPhase("waitingRom", timeout: 15)
            poll()
        }
    }
    func cancel(id: String) throws {
        guard id == session else { throw failure("Stale firmware session.") }
        terminate("canceled", message: "Programming canceled; installed firmware is not verified.")
    }
    func interrupt() {
        if session != nil { terminate("failed", message: "App lifecycle interrupted the firmware session.") }
    }
    private func failure(_ message: String) -> NSError {
        NSError(domain: "FirmwareSession", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func emit(_ extra: [String: Any] = [:]) {
        guard let session else { return }
        var values = extra; values["sessionId"] = session; values["phase"] = phase
        event(values)
    }
    private func setPhase(_ value: String, timeout: TimeInterval = 10) {
        phase = value; deadline = now()+timeout; emit()
    }
    private func terminate(_ value: String, message: String? = nil) {
        generation += 1; phase = value
        emit(message.map { ["message": $0] } ?? [:])
        if let selected { io.perform(selected, .close) { _ in } }
        selected = nil; origin = nil; loader = Data(); application = Data()
        session = nil; prepared = false; pending = false; resetAcknowledged = false
    }
    func poll() {
        guard session != nil else { return }
        guard now() < deadline else {
            terminate("failed", message: "Firmware USB operation or transition timed out."); return
        }
        if prepared { return }
        do {
            let devices = try io.inventory()
            guard devices.count <= 1, devices.allSatisfy({ $0.rom || $0.loader }) else {
                throw failure("Ambiguous or forbidden USB devices.")
            }
            switch phase {
            case "waitingRom":
                guard let device = devices.first else { return }
                guard device.rom, device.location != 0 else { throw failure("Expected attributed ROM device.") }
                if let recoveryDevice, recoveryDevice != device { throw failure("Recovery ROM identity changed after confirmation.") }
                origin = device; selected = device
                setPhase("uploadingLoader", timeout: 120)
                openThenBegin(device, bytes: loader, rom: true)
            case "waitingLoader":
                guard let device = devices.first else { return }
                if device == origin { return } // ROM must actually re-enumerate.
                guard let origin, device.loader, device.id != origin.id,
                      device.location == origin.location else {
                    throw failure("Flashloader did not re-enumerate at the selected USB location.")
                }
                selected = device; offset = 0
                setPhase("configuringNor", timeout: 15)
                openThenBegin(device, bytes: application, rom: false)
            case "resetting":
                if devices.isEmpty && resetAcknowledged { terminate("programmed") }
                else if let device = devices.first, device != selected {
                    throw failure("Device identity changed during reset.")
                }
            case "jumping":
                // Removal is permitted only here, but completion still requires
                // the validated SDP HAB response before waitingLoader is entered.
                if let device = devices.first, device != selected &&
                    !(device.loader && device.location == origin?.location) {
                    throw failure("Unattributed device during jump.")
                }
            default:
                guard devices.first == selected else { throw failure("Unexpected firmware USB loss.") }
            }
        } catch { terminate("failed", message: error.localizedDescription) }
    }
    private func perform(_ operation: FirmwareOperation, phase expected: UInt64,
                         count: Int, then: @escaping () -> Void) {
        guard let device = selected, session != nil, !pending else { return }
        // Recheck inventory immediately before every operation, not only polling.
        do {
            guard try io.inventory() == [device] else { throw failure("USB ownership changed before submission.") }
        } catch { terminate("failed", message: error.localizedDescription); return }
        let epoch = generation
        pending = true
        io.perform(device, operation) { [weak self] result in
            guard let self, self.generation == epoch, self.session != nil else { return }
            self.pending = false
            guard self.now() < self.deadline else {
                self.terminate("failed", message: "Firmware operation deadline expired."); return
            }
            switch result {
            case .success(let receipt):
                guard receipt.phase == expected, receipt.count == count else {
                    self.terminate("failed", message: "Malformed native phase or byte-count receipt."); return
                }
                then()
            case .failure(let error): self.terminate("failed", message: error.localizedDescription)
            }
        }
    }
    private func openThenBegin(_ device: FirmwareDevice, bytes: Data, rom: Bool) {
        perform(.open, phase: 0, count: 0) { [self] in
            perform(.begin(bytes.count), phase: rom ? 1 : 4, count: 0) { [self] in
                if rom { offset = 0; writeChunk(rom: true) }
                else { configure() }
            }
        }
    }
    private func configure() {
        perform(.advance, phase: 5, count: 0) { [self] in
            setPhase("erasing", timeout: 35)
            perform(.advance, phase: 6, count: 0) { [self] in
                setPhase("creatingFcb", timeout: 15)
                perform(.advance, phase: 7, count: 0) { [self] in
                    setPhase("writingApplication", timeout: 600)
                    perform(.advance, phase: 8, count: 0) { [self] in writeChunk(rom: false) }
                }
            }
        }
    }
    private func writeChunk(rom: Bool) {
        let bytes = rom ? loader : application
        let end = min(offset+1024, bytes.count)
        let final = end == bytes.count
        perform(.data(bytes.subdata(in: offset..<end)), phase: rom ? (final ? 2 : 1) : (final ? 9 : 8), count: end) { [self] in
            offset = end
            emit(["transferred": offset, "total": bytes.count])
            if !final { writeChunk(rom: rom); return }
            if rom {
                setPhase("jumping", timeout: 5)
                perform(.advance, phase: 3, count: offset) { [self] in
                    if let selected { io.perform(selected, .close) { _ in } }
                    self.selected = nil
                    setPhase("waitingLoader", timeout: 15)
                    poll()
                }
            } else {
                setPhase("resetting", timeout: 10)
                perform(.advance, phase: 10, count: offset) { [self] in
                    resetAcknowledged = true; poll()
                }
            }
        }
    }
}
#endif
