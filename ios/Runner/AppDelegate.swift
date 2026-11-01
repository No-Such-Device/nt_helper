import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // Register custom plugins
    IosFileAccessPlugin.register(with: self.registrar(forPlugin: "com.example.nt_helper/ios_file_access")!)
    UsbVideoCapturePlugin.register(with: self.registrar(forPlugin: "com.example.nt_helper/usb_video")!)
    #if INITIAL_SDP_EXPERIMENT
    InitialSdpPlugin.register(with: self.registrar(forPlugin: "com.example.nt_helper/initial_sdp")!)
    #endif
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
