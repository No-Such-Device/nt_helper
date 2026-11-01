#if INITIAL_SDP_EXPERIMENT
import Flutter
import UIKit

// iPadOS uses the bundled, Settings-enabled DriverKit extension. No macOS
// activation, desktop HID access, or flashing process is used here.
final class InitialSdpPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let queue = DispatchQueue(label: "dev.nosuch.ntHelper.initialSdp")
    private var sink: FlutterEventSink?
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private var service: io_service_t = 0
    private var connection: io_connect_t = 0
    private var generation = 0
    private var detectionDeadline: DispatchWorkItem?
    private let deliveryLock = NSLock()

    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = InitialSdpPlugin()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
            name: "com.example.nt_helper/initial_sdp", binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: "com.example.nt_helper/initial_sdp_events",
            binaryMessenger: registrar.messenger()).setStreamHandler(instance)
    }

    private func emit(_ stage: String, _ values: [String: Any] = [:]) {
        deliveryLock.lock()
        let epoch = generation
        deliveryLock.unlock()
        var event = values
        event["stage"] = stage
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deliveryLock.lock()
            let target = self.generation == epoch ? self.sink : nil
            self.deliveryLock.unlock()
            target?(event)
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // The channel never accepts arbitrary command selectors, identities or data.
        guard call.arguments == nil else {
            result(FlutterError(code: "rejected", message: "This status-only API takes no arguments.", details: nil))
            return
        }
        guard ["availability", "observe", "connect", "errorStatus", "close"].contains(call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        queue.async { [self] in
            var reply: Any?
            switch call.method {
            case "availability":
                reply = [
                    "osEligible": ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 16,
                    "isIPad": UIDevice.current.userInterfaceIdiom == .pad,
                    "driverObserved": service != 0,
                    // No public API proves M-series hardware or distinguishes a
                    // disabled driver from absent hardware. Never guess enablement.
                    "requirements": "M-series iPad, iPadOS 16+, development profiles; enable in Settings > General > Drivers; use USB data cable and independent NT power."
                ] as [String: Any]
            case "observe":
                reply = observe()
            case "connect":
                guard service != 0 else {
                    finish(result, error("connection", "Initial bootloader driver has not been observed."))
                    return
                }
                if connection == 0 {
                    let code = IOServiceOpen(service, mach_task_self_, 0, &connection)
                    if code != KERN_SUCCESS {
                        connection = 0
                        finish(result, error("connection", "IOServiceOpen failed: \(code). Check development communication entitlement and driver ownership."))
                        return
                    }
                }
                emit("connected")
                reply = ["stage": "connected"]
            case "errorStatus":
                guard connection != 0 else {
                    finish(result, error("query", "Connect to the initial bootloader driver first."))
                    return
                }
                var output = [UInt64](repeating: 0, count: 2)
                var count: UInt32 = 2
                let code = IOConnectCallScalarMethod(connection, 0, nil, 0, &output, &count)
                guard code == KERN_SUCCESS, count == 2 else {
                    closeConnection()
                    finish(result, error("query", "SDP error-status failed or was malformed: \(code). No status response confirmed. Reconnect USB before retrying; failed native sessions are not reused."))
                    return
                }
                reply = ["stage": "response", "hab": output[0], "status": output[1]]
                emit("response", ["hab": output[0], "status": output[1]])
            case "close":
                teardown()
            default: break
            }
            finish(result, reply)
        }
    }

    private func error(_ stage: String, _ message: String) -> FlutterError {
        emit("failure", ["failedStage": stage, "message": message])
        return FlutterError(code: stage, message: message, details: nil)
    }
    private func finish(_ result: @escaping FlutterResult, _ value: Any?) {
        DispatchQueue.main.async { result(value) }
    }
    private func matching() -> NSMutableDictionary {
        let match = IOServiceMatching("IOUserService") as NSMutableDictionary
        match["IOPropertyMatch"] = [
            "IOUserClass": "InitialSdpDriver",
            "NTInitialVendorID": 0x1fc9, "NTInitialProductID": 0x0135
        ]
        return match
    }
    private func observe() -> Any {
        guard port == nil else { return ["stage": service == 0 ? "waiting" : "detected"] }
        guard let notificationPort = IONotificationPortCreate(kIOMainPortDefault) else {
            return error("availability", "Cannot create DriverKit service notification port.")
        }
        port = notificationPort
        IONotificationPortSetDispatchQueue(notificationPort, queue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let onAdded: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            Unmanaged<InitialSdpPlugin>.fromOpaque(context).takeUnretainedValue().drain(iterator, isRemoval: false)
        }
        let onRemoved: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            Unmanaged<InitialSdpPlugin>.fromOpaque(context).takeUnretainedValue().drain(iterator, isRemoval: true)
        }
        let first = IOServiceAddMatchingNotification(notificationPort, kIOFirstMatchNotification,
            matching(), onAdded, context, &added)
        if first == KERN_SUCCESS { drain(added, isRemoval: false) }
        let second = IOServiceAddMatchingNotification(notificationPort, kIOTerminatedNotification,
            matching(), onRemoved, context, &removed)
        if second == KERN_SUCCESS { drain(removed, isRemoval: true) }
        guard first == KERN_SUCCESS, second == KERN_SUCCESS else {
            teardown()
            return error("availability", "Driver observation registration failed: \(first), \(second). Check development provisioning.")
        }
        if service == 0 {
            emit("waiting", ["message": "No initial driver service observed. Check driver enablement, USB identity, cable and power; hotplug may be required."])
            let deadline = DispatchWorkItem { [weak self] in
                guard let self, self.service == 0 else { return }
                self.teardown()
                _ = self.error("detection", "No initial bootloader driver observed within 15 seconds. Check Settings > General > Drivers, development profiles, cable and power; retry observation after hotplug if needed.")
            }
            detectionDeadline = deadline
            queue.asyncAfter(deadline: .now() + 15, execute: deadline)
        }
        return ["stage": service == 0 ? "waiting" : "detected"]
    }
    private func drain(_ iterator: io_iterator_t, isRemoval: Bool) {
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            if isRemoval {
                var entryID: UInt64 = 0, selectedID: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(entry, &entryID)
                if service != 0 { IORegistryEntryGetRegistryEntryID(service, &selectedID) }
                if entryID == selectedID {
                    // Stop this observation rather than silently selecting another NT.
                    // A new explicit observation enumerates any already-present service.
                    teardown()
                    emit("disconnected", ["message": "Initial bootloader USB driver disconnected. Observe again to retry."])
                    IOObjectRelease(entry)
                    return
                }
            } else if service == 0 {
                detectionDeadline?.cancel()
                detectionDeadline = nil
                IOObjectRetain(entry)
                service = entry
                emit("detected", ["vendorId": 0x1fc9, "productId": 0x0135])
            }
            IOObjectRelease(entry)
        }
    }
    private func closeConnection() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
    }
    private func teardown() {
        deliveryLock.lock()
        generation += 1
        deliveryLock.unlock()
        detectionDeadline?.cancel()
        detectionDeadline = nil
        closeConnection()
        if let port { IONotificationPortDestroy(port); self.port = nil }
        if added != 0 { IOObjectRelease(added); added = 0 }
        if removed != 0 { IOObjectRelease(removed); removed = 0 }
        if service != 0 { IOObjectRelease(service); service = 0 }
    }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        deliveryLock.lock()
        sink = events
        deliveryLock.unlock()
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        queue.sync { teardown() }
        deliveryLock.lock()
        sink = nil
        deliveryLock.unlock()
        return nil
    }
    func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        queue.sync { teardown() }
        deliveryLock.lock()
        sink = nil
        deliveryLock.unlock()
    }
}
#endif
