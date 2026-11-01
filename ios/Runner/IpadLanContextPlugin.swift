import Darwin
import Flutter
import Network
import UIKit

struct LanPathInterface: Equatable {
    let index: Int
    let name: String
    let type: String
    let active: Bool
}

struct LanPathState: Equatable {
    let satisfied: Bool
    let interfaces: [LanPathInterface]

    init(satisfied: Bool, interfaces: [LanPathInterface]) {
        self.satisfied = satisfied
        self.interfaces = interfaces.sorted { $0.index == $1.index ? $0.name < $1.name : $0.index < $1.index }
    }

    init(_ path: NWPath) {
        self.init(satisfied: path.status == .satisfied, interfaces: path.availableInterfaces.map {
            let type: String
            switch $0.type {
            case .wifi: type = "wifi"
            case .wiredEthernet: type = "wiredEthernet"
            case .cellular: type = "cellular"
            case .loopback: type = "loopback"
            default: type = "other"
            }
            return LanPathInterface(index: $0.index, name: $0.name, type: type,
                                    active: path.usesInterfaceType($0.type))
        })
    }
}

struct LanAddressRow {
    let index: Int
    let name: String
    let flags: UInt32
    let family: String
    let bytes: [UInt8]
    let mask: [UInt8]
    let scopeId: UInt32
}

enum LanContextError: Error { case unavailable, contradictory }

/// Confined to the monitor queue. Each observed callback advances authority,
/// including callbacks with unchanged IPs; snapshots never initialize the path.
final class LanPathObservation {
    private(set) var generation: Int64 = 0
    private var observed: LanPathState?

    func observe(_ path: LanPathState) {
        guard generation < Int64.max else { observed = nil; return }
        generation += 1
        observed = path
    }

    static func idiom(_ idiom: UIUserInterfaceIdiom) -> String {
        switch idiom {
        case .pad: return "pad"
        case .phone: return "phone"
        case .unspecified: return "unknown"
        default: return "other"
        }
    }

    static func prefix(_ mask: [UInt8]) throws -> Int {
        var count = 0
        var zero = false
        for byte in mask {
            for bit in (0...7).reversed() {
                if byte & (1 << bit) == 0 { zero = true }
                else {
                    guard !zero else { throw LanContextError.contradictory }
                    count += 1
                }
            }
        }
        return count
    }

    func snapshot(idiom: UIUserInterfaceIdiom, rows: [LanAddressRow], current: LanPathState) throws -> [String: Any] {
        guard let observed = observed, observed.satisfied, observed == current, generation > 0 else {
            throw LanContextError.unavailable
        }
        var pathIndices = Set<Int>()
        var pathNames = Set<String>()
        for interface in current.interfaces {
            guard interface.index > 0, !interface.name.isEmpty,
                  pathIndices.insert(interface.index).inserted, pathNames.insert(interface.name).inserted else {
                throw LanContextError.contradictory
            }
        }
        var interfaces: [Int: [String: Any]] = [:]
        var identities: [Int: String] = [:]
        var nameIndices: [String: Int] = [:]
        var addresses = Set<String>()
        for row in rows {
            guard row.index > 0, !row.name.isEmpty,
                  identities[row.index] == nil || identities[row.index] == row.name,
                  nameIndices[row.name] == nil || nameIndices[row.name] == row.index else {
                throw LanContextError.contradictory
            }
            identities[row.index] = row.name
            nameIndices[row.name] = row.index
            // Normalize mapped bytes for duplicate detection without discarding scope.
            let mapped = row.bytes.count == 16 && row.bytes.prefix(10).allSatisfy { $0 == 0 }
                && row.bytes[10] == 255 && row.bytes[11] == 255
            let normalized = mapped ? Array(row.bytes.suffix(4)) : row.bytes
            let key = normalized.map(String.init).joined(separator: ".")
            guard addresses.insert(key).inserted else { throw LanContextError.contradictory }
            let matches = current.interfaces.filter { $0.index == row.index || $0.name == row.name }
            guard matches.count <= 1 else { throw LanContextError.contradictory }
            guard let interface = matches.first else { continue }
            guard interface.index == row.index, interface.name == row.name else { throw LanContextError.contradictory }
            guard interface.active, ["wifi", "wiredEthernet"].contains(interface.type) else { continue }
            guard row.flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                  row.flags & UInt32(IFF_LOOPBACK | IFF_POINTOPOINT) == 0 else { throw LanContextError.contradictory }
            let length = row.family == "ipv4" ? 4 : row.family == "ipv6" ? 16 : 0
            guard length > 0, row.bytes.count == length, row.mask.count == length else { throw LanContextError.contradictory }
            let address: [String: Any] = ["family": row.family, "bytes": row.bytes.map(Int.init),
                "mask": row.mask.map(Int.init), "prefix": try Self.prefix(row.mask), "scopeId": Int64(row.scopeId)]
            if var existing = interfaces[row.index] {
                guard existing["flags"] as? UInt32 == row.flags else { throw LanContextError.contradictory }
                var values = existing["addresses"] as! [[String: Any]]
                values.append(address)
                existing["addresses"] = values
                interfaces[row.index] = existing
            } else {
                interfaces[row.index] = ["index": row.index, "name": row.name, "type": interface.type,
                    "flags": row.flags, "addresses": [address]]
            }
        }
        return ["version": 1, "idiom": Self.idiom(idiom), "pathGeneration": generation, "pathCurrent": true,
                "interfaces": interfaces.keys.sorted().map { interfaces[$0]! }]
    }
}

protocol IpadLanContextProviding {
    func snapshot(idiom: UIUserInterfaceIdiom, completion: @escaping (Result<[String: Any], Error>) -> Void)
}

final class NativeIpadLanContext: IpadLanContextProviding {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.nosuch.ntHelper.ipad-lan-context")
    private let observation = LanPathObservation()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.observation.observe(LanPathState(path)) }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }

    func snapshot(idiom: UIUserInterfaceIdiom, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        queue.async {
            let result = Result { () throws -> [String: Any] in
                let before = LanPathState(self.monitor.currentPath)
                let rows = try Self.addressRows()
                let after = LanPathState(self.monitor.currentPath)
                guard before == after else { throw LanContextError.unavailable }
                return try self.observation.snapshot(idiom: idiom, rows: rows, current: after)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func addressRows() throws -> [LanAddressRow] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { throw LanContextError.unavailable }
        defer { freeifaddrs(first) }
        var rows: [LanAddressRow] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let entry = pointer.pointee
            cursor = entry.ifa_next
            guard let address = entry.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            guard let netmask = entry.ifa_netmask, Int32(netmask.pointee.sa_family) == family else {
                throw LanContextError.contradictory
            }
            let name = String(cString: entry.ifa_name)
            let index = Int(if_nametoindex(entry.ifa_name))
            let bytes: [UInt8]
            let mask: [UInt8]
            let scope: UInt32
            if family == AF_INET {
                var ip = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var bits = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                bytes = withUnsafeBytes(of: &ip) { Array($0) }
                mask = withUnsafeBytes(of: &bits) { Array($0) }
                scope = 0
            } else {
                let socket = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee
                var ip = socket.sin6_addr
                var bits = UnsafeRawPointer(netmask).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                bytes = withUnsafeBytes(of: &ip) { Array($0) }
                mask = withUnsafeBytes(of: &bits) { Array($0) }
                scope = socket.sin6_scope_id
            }
            rows.append(LanAddressRow(index: index, name: name, flags: entry.ifa_flags,
                family: family == AF_INET ? "ipv4" : "ipv6", bytes: bytes, mask: mask, scopeId: scope))
        }
        return rows
    }
}

final class IpadLanContextPlugin: NSObject, FlutterPlugin {
    private let provider: IpadLanContextProviding
    private let idiom: () -> UIUserInterfaceIdiom

    init(provider: IpadLanContextProviding, idiom: @escaping () -> UIUserInterfaceIdiom = { UIDevice.current.userInterfaceIdiom }) {
        self.provider = provider
        self.idiom = idiom
        super.init()
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.example.nt_helper/ipad_lan_context", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(IpadLanContextPlugin(provider: NativeIpadLanContext()), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "snapshot" else { result(FlutterMethodNotImplemented); return }
        provider.snapshot(idiom: idiom()) { response in
            switch response {
            case .success(let snapshot): result(snapshot)
            case .failure: result(FlutterError(code: "LAN_CONTEXT_UNAVAILABLE", message: "Current LAN context is unavailable. Retry explicitly.", details: nil))
            }
        }
    }
}
