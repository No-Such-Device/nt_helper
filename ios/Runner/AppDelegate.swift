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
    IpadLanContextPlugin.register(with: self.registrar(forPlugin: "com.example.nt_helper/ipad_lan_context")!)
    IosFileAccessPlugin.register(with: self.registrar(forPlugin: "com.example.nt_helper/ios_file_access")!)
    UsbVideoCapturePlugin.register(with: self.registrar(forPlugin: "com.example.nt_helper/usb_video")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
