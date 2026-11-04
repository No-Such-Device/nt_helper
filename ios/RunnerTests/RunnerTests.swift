import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testLaunchManifestUsesFlutterSceneAndExistingStoryboard() throws {
    let manifest = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any]
    )
    XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
    let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
    let scenes = try XCTUnwrap(configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]])
    XCTAssertEqual(scenes.count, 1)
    let scene = try XCTUnwrap(scenes.first)
    XCTAssertEqual(scene["UISceneClassName"] as? String, "UIWindowScene")
    XCTAssertEqual(scene["UISceneDelegateClassName"] as? String, "FlutterSceneDelegate")
    XCTAssertEqual(scene["UISceneStoryboardFile"] as? String, "Main")
  }

  @MainActor
  func testSceneLaunchRendersFlutterAndRegistersGeneratedAndCustomPlugins() throws {
    // Dart widget tests do not launch UIKit or exercise the implicit-engine callback.
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    XCTAssertTrue(scene.delegate is FlutterSceneDelegate)
    let controller = try XCTUnwrap(
      scene.windows.compactMap { $0.rootViewController as? FlutterViewController }.first
    )
    let engine = try XCTUnwrap(controller.engine)
    for key in [
      "SwiftFlutterMidiCommandPlugin", "SharedPreferencesPlugin", "FilePickerPlugin",
      "com.example.nt_helper/ios_file_access", "com.example.nt_helper/usb_video"
    ] {
      XCTAssertTrue(engine.hasPlugin(key), "Scene engine is missing plugin: \(key)")
    }
    let rendered = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in controller.isDisplayingFlutterUI }, object: nil
    )
    // Bounded wait for a real engine frame, not a guessed startup delay.
    wait(for: [rendered], timeout: 30)
  }

}
