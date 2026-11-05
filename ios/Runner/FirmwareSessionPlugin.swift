#if FIRMWARE_SESSION_V2
import Flutter
import UIKit

// Only the V2 development target compiles this adapter. It owns a separate
// channel/user client; InitialSdpPlugin and selector 0 remain status-only.
private final class FirmwareDriverIO: FirmwareDeviceIO {
    private let queue = DispatchQueue(label: "dev.nosuch.ntHelper.firmwareUSB")
    private var connection: io_connect_t = 0
    private var selectedID: UInt64 = 0
    private let identityLock = NSLock()
    private var identities: [UInt64: FirmwareDevice] = [:]

    private func services() throws -> [io_service_t] {
        var found: [io_service_t] = []
        // Include the original running driver so it cannot be mistaken for absence.
        for name in ["FirmwareSessionDriver", "InitialSdpDriver"] {
            let match = IOServiceMatching("IOUserService") as NSMutableDictionary
            match["IOPropertyMatch"] = ["IOUserClass": name]
            var iterator: io_iterator_t = 0
            let status = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
            guard status == KERN_SUCCESS else {
                found.forEach { IOObjectRelease($0) }
                throw error("Cannot enumerate firmware drivers: \(status)")
            }
            while true {
                let service = IOIteratorNext(iterator)
                if service == 0 { break }
                found.append(service)
            }
            IOObjectRelease(iterator)
        }
        return found
    }
    private func matches(_ entry: io_service_t, _ values: [String: Any]) throws -> Bool {
        var matched: boolean_t = 0
        let status = IOServiceMatchPropertyTable(entry,
            ["IOPropertyMatch": values] as CFDictionary, &matched)
        guard status == KERN_SUCCESS else { throw error("Kernel USB identity match failed: \(status)") }
        return matched != 0
    }
    func inventory() throws -> [FirmwareDevice] {
        let entries = try services()
        defer { entries.forEach { IOObjectRelease($0) } }
        return try entries.map { entry in
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS else {
                throw error("Cannot attribute driver registry identity.")
            }
            // iPadOS filters direct registry reads, but matching evaluates the
            // real published properties in the kernel (as in InitialSdpPlugin).
            let v2 = try matches(entry, ["IOUserClass": "FirmwareSessionDriver"])
            let rom = try matches(entry, ["NTFirmwareVendorID": 0x1fc9, "NTFirmwareProductID": 0x0135])
            let loader = try matches(entry, ["NTFirmwareVendorID": 0x15a2, "NTFirmwareProductID": 0x0073])
            guard v2, rom != loader else {
                return FirmwareDevice(id: id, location: 0, vendor: 0, product: 0)
            }
            guard try matches(entry, ["NTFirmwareDriverRevision": 8]) else {
                throw error("An older firmware driver is still running. Toggle the driver off and on in Settings, then reconnect USB.")
            }
            // Descriptor and port identity are immutable for a registry entry.
            // Do not block the main-queue poll on the driver's programming lock
            // while a flash erase or transfer is in progress.
            identityLock.lock()
            let cached = identities[id]
            identityLock.unlock()
            if let cached {
                guard cached.rom == rom, cached.loader == loader else {
                    throw error("Firmware device identity changed without re-enumeration.")
                }
                return cached
            }
            // A separate, read-only client asks the driver for descriptor and
            // port identity. It must never claim USB or close a programming client.
            var observer: io_connect_t = 0
            let openStatus = IOServiceOpen(entry, mach_task_self_, 0, &observer)
            guard openStatus == KERN_SUCCESS else {
                throw error("Cannot inspect the firmware driver: \(openStatus)")
            }
            defer { IOServiceClose(observer) }
            var output = [UInt64](repeating: 0, count: 4), count: UInt32 = 4
            let status = IOConnectCallScalarMethod(observer, 0x205, nil, 0, &output, &count)
            guard status == KERN_SUCCESS, count == 4, output[0] == FirmwareSessionState.api else {
                throw error("Cannot identify the firmware device. Check the updated driver is enabled.")
            }
            let expectedVendor: UInt64 = rom ? 0x1fc9 : 0x15a2
            let expectedProduct: UInt64 = rom ? 0x0135 : 0x0073
            guard output[1] == expectedVendor, output[2] == expectedProduct else {
                throw error("Descriptor disagrees with kernel USB identity.")
            }
            let device = FirmwareDevice(id: id, location: output[3],
                vendor: Int(output[1]), product: Int(output[2]))
            identityLock.lock()
            if identities.count >= 2 { identities.removeAll() }
            identities[id] = device
            identityLock.unlock()
            return device
        }
    }
    private func error(_ message: String) -> NSError {
        NSError(domain: "FirmwareDriver", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    func perform(_ device: FirmwareDevice, _ operation: FirmwareOperation,
                 completion: @escaping (Result<FirmwareReceipt, Error>) -> Void) {
        queue.async { [self] in
            let result: Result<FirmwareReceipt, Error>
            do { result = .success(try execute(device, operation)) }
            catch { close(); result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    private func close() {
        if connection != 0 { IOServiceClose(connection) }
        connection = 0; selectedID = 0
    }
    private func execute(_ device: FirmwareDevice, _ operation: FirmwareOperation) throws -> FirmwareReceipt {
        if case .close = operation {
            if selectedID == device.id { close() }
            return FirmwareReceipt(phase: 0, count: 0)
        }
        guard try inventory() == [device] else { throw error("Ambiguous or changed firmware USB ownership.") }
        if case .open = operation {
            guard connection == 0 else { throw error("Concurrent driver connection.") }
            let entries = try services()
            defer { entries.forEach { IOObjectRelease($0) } }
            guard let service = entries.first(where: { entry in
                var id: UInt64 = 0
                return IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS && id == device.id
            }) else { throw error("Selected driver disappeared.") }
            guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
                connection = 0; throw error("Cannot exclusively open the firmware driver.")
            }
            selectedID = device.id
            var output = [UInt64](repeating: 0, count: 3), count: UInt32 = 3
            let code = IOConnectCallScalarMethod(connection, 0x200, nil, 0, &output, &count)
            guard code == KERN_SUCCESS, count == 3, output == [FirmwareSessionState.api,
                UInt64(FirmwareSessionState.maxLoader), UInt64(FirmwareSessionState.maxApplication)] else {
                throw error("Incompatible running firmware driver; no programming submitted.")
            }
            return FirmwareReceipt(phase: 0, count: 0)
        }
        guard connection != 0, selectedID == device.id else { throw error("No attributed driver connection.") }
        var output = [UInt64](repeating: 0, count: 2), count: UInt32 = 2
        let code: kern_return_t
        switch operation {
        case .begin(let length):
            var input = UInt64(length)
            code = IOConnectCallScalarMethod(connection, 0x201, &input, 1, &output, &count)
        case .data(let bytes):
            code = bytes.withUnsafeBytes { buffer in
                IOConnectCallMethod(connection, 0x202, nil, 0, buffer.baseAddress, bytes.count,
                                    &output, &count, nil, nil)
            }
        case .advance:
            code = IOConnectCallScalarMethod(connection, 0x203, nil, 0, &output, &count)
        default: throw error("Unsupported firmware operation.")
        }
        guard code == KERN_SUCCESS, count == 2, output[1] <= UInt64(FirmwareSessionState.maxApplication) else {
            throw error("Firmware transfer failed or receipt malformed: \(code)")
        }
        return FirmwareReceipt(phase: output[0], count: Int(output[1]))
    }
}

final class FirmwareSessionPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private var timer: Timer?
    private var lifecycle: NSObjectProtocol?
    private lazy var state = FirmwareSessionState(io: FirmwareDriverIO(),
        now: { ProcessInfo.processInfo.systemUptime }, event: { [weak self] event in self?.sink?(event) })
    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FirmwareSessionPlugin()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
            name: "dev.nosuch.nt_helper/firmware_session_v2", binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: "dev.nosuch.nt_helper/firmware_session_v2_events",
            binaryMessenger: registrar.messenger()).setStreamHandler(instance)
        instance.lifecycle = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak instance] _ in
                instance?.state.interrupt()
            }
        instance.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak instance] _ in instance?.state.poll() }
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            guard UIDevice.current.userInterfaceIdiom == .pad,
                  ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 16 else {
                throw NSError(domain: "FirmwareSession", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "V2 requires a supported development iPad."])
            }
            if call.method == "availability", call.arguments == nil {
                result(["api": FirmwareSessionState.api, "isIPad": true, "osEligible": true,
                        "maxLoader": FirmwareSessionState.maxLoader,
                        "maxApplication": FirmwareSessionState.maxApplication]); return
            }
            if call.method == "prepare" {
                let arguments = call.arguments as? [String: Any]
                guard call.arguments == nil || (arguments?.count == 1 && arguments?["allowAttachedBootloader"] is Bool) else {
                    throw NSError(domain: "FirmwareSession", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Only a typed recovery flag is accepted for preparation."])
                }
                result(["sessionId": try state.prepare(allowAttachedBootloader: arguments?["allowAttachedBootloader"] as? Bool ?? false)]); return
            }
            guard let args = call.arguments as? [String: Any], let id = args["sessionId"] as? String else {
                throw NSError(domain: "FirmwareSession", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Typed firmware session arguments required."])
            }
            switch call.method {
            case "start":
                guard Set(args.keys) == ["sessionId", "loader", "application"],
                      let loader = args["loader"] as? FlutterStandardTypedData,
                      let application = args["application"] as? FlutterStandardTypedData else {
                    throw NSError(domain: "FirmwareSession", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Only bounded loader/application bytes are accepted."])
                }
                try state.start(id: id, loader: loader.data, application: application.data)
            case "cancel", "close":
                guard Set(args.keys) == ["sessionId"] else {
                    throw NSError(domain: "FirmwareSession", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unexpected firmware session argument."])
                }
                try state.cancel(id: id)
            default: result(FlutterMethodNotImplemented); return
            }
            result(nil)
        } catch { result(FlutterError(code: "firmwareSession", message: error.localizedDescription, details: nil)) }
    }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events; return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        state.interrupt(); sink = nil; return nil
    }
    func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        state.interrupt(); sink = nil; timer?.invalidate(); timer = nil
        if let lifecycle { NotificationCenter.default.removeObserver(lifecycle); self.lifecycle = nil }
    }
}
#endif
