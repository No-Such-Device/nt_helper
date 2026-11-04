import UIKit
import Flutter
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Scene-based launch creates the engine after didFinishLaunchingWithOptions.
  // Register every plugin and channel against that engine, not the app delegate.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    let networkChannel = FlutterMethodChannel(
      name: "dev.nosuch.nt_helper/local_network",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    networkChannel.setMethodCallHandler { call, result in
      guard call.method == "addresses" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result([
        "isIpad": UIDevice.current.userInterfaceIdiom == .pad,
        "networks": Self.localNetworks()
      ])
    }
    // Register custom plugins
    IosFileAccessPlugin.register(with: registry.registrar(forPlugin: "com.example.nt_helper/ios_file_access")!)
    UsbVideoCapturePlugin.register(with: registry.registrar(forPlugin: "com.example.nt_helper/usb_video")!)
    #if INITIAL_SDP_EXPERIMENT
    InitialSdpPlugin.register(with: registry.registrar(forPlugin: "com.example.nt_helper/initial_sdp")!)
    #endif
    #if FIRMWARE_SESSION_V2
    FirmwareSessionPlugin.register(with: registry.registrar(forPlugin: "dev.nosuch.nt_helper/firmware_session_v2")!)
    #endif
  }

  // Wi-Fi and wired LAN interfaces are en*. Exclude cellular, VPNs and loopback.
  private static func localNetworks() -> [[String: [UInt8]]] {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0 else { return [] }
    defer { freeifaddrs(head) }
    var networks: [[String: [UInt8]]] = []
    var current = head
    while let item = current {
      defer { current = item.pointee.ifa_next }
      let info = item.pointee
      guard String(cString: info.ifa_name).hasPrefix("en"),
            info.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
            let address = info.ifa_addr, let mask = info.ifa_netmask else { continue }
      func bytes(_ pointer: UnsafeMutablePointer<sockaddr>) -> [UInt8]? {
        switch Int32(pointer.pointee.sa_family) {
        case AF_INET:
          var value = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
          return withUnsafeBytes(of: &value) { Array($0) }
        case AF_INET6:
          var value = UnsafeRawPointer(pointer).assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
          return withUnsafeBytes(of: &value) { Array($0) }
        default: return nil
        }
      }
      if let own = bytes(address), let netmask = bytes(mask), own.count == netmask.count {
        networks.append(["address": own, "netmask": netmask])
      }
    }
    return networks
  }
}
