import Darwin
import Flutter
import UIKit
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
    private func path(type: String = "wifi", index: Int = 7, name: String = "arbitrary", active: Bool = true) -> LanPathState {
        LanPathState(satisfied: true, interfaces: [LanPathInterface(index: index, name: name, type: type, active: active)])
    }

    private func row(index: Int = 7, name: String = "arbitrary", flags: UInt32 = UInt32(IFF_UP | IFF_RUNNING),
                     family: String = "ipv4", bytes: [UInt8] = [192, 168, 2, 1],
                     mask: [UInt8] = [255, 255, 254, 0], scope: UInt32 = 0) -> LanAddressRow {
        LanAddressRow(index: index, name: name, flags: flags, family: family, bytes: bytes, mask: mask, scopeId: scope)
    }

    // REQ-003: the old placeholder did not prove native identity, and screen width cannot identify iPad.
    func testReq003NativeIdiomRemainsPadInCompactSplitView() throws {
        for sizeClass in [UIUserInterfaceSizeClass.compact, .regular] {
            let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceIdiom: .pad),
                UITraitCollection(horizontalSizeClass: sizeClass)])
            let observation = LanPathObservation()
            observation.observe(path())
            let value = try observation.snapshot(idiom: traits.userInterfaceIdiom, rows: [row()], current: path())
            XCTAssertEqual(value["idiom"] as? String, "pad")
        }
        XCTAssertEqual(LanPathObservation.idiom(.phone), "phone")
        XCTAssertEqual(LanPathObservation.idiom(.unspecified), "unknown")
        XCTAssertEqual(LanPathObservation.idiom(.tv), "other")
    }

    // AC-002: native provenance cannot be established by Dart address-only fixtures.
    func testAc002RequiresInitializedCurrentPathAndAdvancesSameIpGeneration() throws {
        let observation = LanPathObservation()
        XCTAssertThrowsError(try observation.snapshot(idiom: .pad, rows: [row()], current: path()))
        observation.observe(path())
        XCTAssertThrowsError(try observation.snapshot(idiom: .pad, rows: [row()], current: path(type: "wiredEthernet")))
        let first = try observation.snapshot(idiom: .pad, rows: [row()], current: path())
        observation.observe(path())
        let second = try observation.snapshot(idiom: .pad, rows: [row()], current: path())
        XCTAssertEqual(first["pathGeneration"] as? Int64, 1)
        XCTAssertEqual(second["pathGeneration"] as? Int64, 2)
        XCTAssertEqual(second["version"] as? Int, 1)
        let unavailable = LanPathState(satisfied: false, interfaces: path().interfaces)
        observation.observe(unavailable)
        XCTAssertThrowsError(try observation.snapshot(idiom: .pad, rows: [row()], current: unavailable))
    }

    // AC-002: require the index/name join, not names like en0 or available-interface order.
    func testAc002JoinsWifiAndEthernetByIdentityAndPreservesNativeMaskAndScope() throws {
        for type in ["wifi", "wiredEthernet"] {
            let observation = LanPathObservation()
            let state = LanPathState(satisfied: true, interfaces: [
                LanPathInterface(index: 9, name: "en0", type: "other", active: true),
                LanPathInterface(index: 7, name: "arbitrary", type: type, active: true)])
            observation.observe(state)
            let ipv6 = row(family: "ipv6", bytes: [0xfd, 0x12] + Array(repeating: 0, count: 13) + [1],
                mask: Array(repeating: 255, count: 8) + Array(repeating: 0, count: 8), scope: 7)
            let value = try observation.snapshot(idiom: .pad, rows: [row(index: 9, name: "en0", bytes: [10, 0, 0, 1]), row(), ipv6], current: state)
            let interfaces = try XCTUnwrap(value["interfaces"] as? [[String: Any]])
            XCTAssertEqual(interfaces.count, 1)
            XCTAssertEqual(interfaces[0]["index"] as? Int, 7)
            XCTAssertEqual(interfaces[0]["name"] as? String, "arbitrary")
            XCTAssertEqual(interfaces[0]["type"] as? String, type)
            let addresses = try XCTUnwrap(interfaces[0]["addresses"] as? [[String: Any]])
            XCTAssertEqual(addresses[0]["mask"] as? [Int], [255, 255, 254, 0])
            XCTAssertEqual(addresses[0]["prefix"] as? Int, 23)
            XCTAssertEqual(addresses[1]["scopeId"] as? Int64, 7) // preserved for Dart rejection, never stripped
            XCTAssertEqual(addresses[1]["family"] as? String, "ipv6")
            // Prove these native number/list types survive the actual Flutter codec.
            let codec = FlutterStandardMessageCodec.sharedInstance()
            let decoded = try XCTUnwrap(codec.decode(codec.encode(value)!) as? [String: Any])
            XCTAssertEqual(decoded as NSDictionary, value as NSDictionary)
        }
    }

    // AC-002: valid joins do not exercise contradictory identities or duplicate interfaces/addresses.
    func testAc002RejectsAmbiguousDuplicateAndContradictoryInterfaceData() {
        let states = [
            LanPathState(satisfied: true, interfaces: path().interfaces + path().interfaces),
            LanPathState(satisfied: true, interfaces: path().interfaces + path(index: 8).interfaces),
            LanPathState(satisfied: true, interfaces: path().interfaces + path(name: "other").interfaces),
            path(index: 8), path(name: "other"), path(index: 0)
        ]
        for state in states {
            let observation = LanPathObservation()
            observation.observe(state)
            XCTAssertThrowsError(try observation.snapshot(idiom: .pad, rows: [row()], current: state))
        }
        let mapped = row(index: 8, name: "mapped", family: "ipv6",
            bytes: Array(repeating: 0, count: 10) + [255, 255, 192, 168, 2, 1],
            mask: Array(repeating: 255, count: 15) + [0])
        for rows in [[row(), row()], [row(), mapped], [row(), row(index: 8, name: "other")],
                     [row(), row(index: 8)], [row(), row(name: "other")],
                     [row(), row(flags: UInt32(IFF_UP | IFF_RUNNING | IFF_BROADCAST), bytes: [192, 168, 2, 2])]] {
            let observation = LanPathObservation()
            observation.observe(path())
            XCTAssertThrowsError(try observation.snapshot(idiom: .pad, rows: rows, current: path()))
        }
    }

    // AC-002: interface type/flags and native masks are independent of address pool validation.
    func testAc002RejectsInvalidFlagsFamiliesAndMasksAndNeverInfersLanType() throws {
        for flags in [UInt32(0), UInt32(IFF_UP), UInt32(IFF_RUNNING),
                      UInt32(IFF_UP | IFF_RUNNING | IFF_LOOPBACK), UInt32(IFF_UP | IFF_RUNNING | IFF_POINTOPOINT)] {
            let observation = LanPathObservation()
            observation.observe(path())
            XCTAssertThrowsError(try observation.snapshot(idiom: .pad, rows: [row(flags: flags)], current: path()))
        }
        for bad in [row(family: "unknown"), row(mask: [255, 0, 255, 0]), row(mask: [255, 255, 255]), row(bytes: [192, 168, 2])] {
            let observation = LanPathObservation()
            observation.observe(path())
            XCTAssertThrowsError(try observation.snapshot(idiom: .pad, rows: [bad], current: path()))
        }
        for state in [path(type: "cellular"), path(type: "loopback"), path(type: "other"), path(active: false),
                      LanPathState(satisfied: true, interfaces: [])] {
            let observation = LanPathObservation()
            observation.observe(state)
            let result = try observation.snapshot(idiom: .pad, rows: [row()], current: state)
            XCTAssertEqual((result["interfaces"] as? [[String: Any]])?.count, 0)
        }
        for (mask, prefix) in [([255, 255, 255, 0], 24), ([255, 255, 254, 0], 23),
                               ([255, 255, 255, 254], 31), ([255, 255, 255, 255], 32),
                               (Array(repeating: 255, count: 16), 128)] {
            XCTAssertEqual(try LanPathObservation.prefix(mask.map(UInt8.init)), prefix)
        }
    }

    // REQ-003: pure fixtures alone cannot prove Flutter dispatch and fail-closed bridge errors.
    func testReq003InjectablePluginReturnsContextOrBoundedFailureWithoutFallback() throws {
        final class Provider: IpadLanContextProviding {
            var fail = false
            var seen: UIUserInterfaceIdiom?
            func snapshot(idiom: UIUserInterfaceIdiom, completion: @escaping (Result<[String: Any], Error>) -> Void) {
                seen = idiom
                completion(fail ? .failure(LanContextError.unavailable) : .success(["idiom": LanPathObservation.idiom(idiom)]))
            }
        }
        let provider = Provider()
        let plugin = IpadLanContextPlugin(provider: provider, idiom: { .pad })
        var response: Any?
        plugin.handle(FlutterMethodCall(methodName: "snapshot", arguments: nil)) { response = $0 }
        XCTAssertEqual(provider.seen, .pad)
        XCTAssertEqual((response as? [String: Any])?["idiom"] as? String, "pad")
        provider.fail = true
        plugin.handle(FlutterMethodCall(methodName: "snapshot", arguments: nil)) { response = $0 }
        XCTAssertEqual((response as? FlutterError)?.code, "LAN_CONTEXT_UNAVAILABLE")
        plugin.handle(FlutterMethodCall(methodName: "other", arguments: nil)) { response = $0 }
        XCTAssertTrue((response as AnyObject?) === FlutterMethodNotImplemented)
    }
}
