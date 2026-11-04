"""Guard device-only experimental targets that cannot run in Simulator.

RunnerTests exercises actual scene launch and rendering. These configuration
checks complement it for the DriverKit targets; they do not prove device launch.
"""

import json
from pathlib import Path
import plistlib
import re
import subprocess
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]


class IosSceneConfigurationTests(unittest.TestCase):
    def test_all_app_targets_share_scene_manifest_and_engine_registration(self):
        project = json.loads(subprocess.check_output([
            "plutil", "-convert", "json", "-o", "-",
            str(ROOT / "ios/Runner.xcodeproj/project.pbxproj"),
        ]))["objects"]
        delegate = (ROOT / "ios/Runner/AppDelegate.swift").read_text()
        self.assertIn("FlutterImplicitEngineDelegate", delegate)
        callback = delegate.split("func didInitializeImplicitFlutterEngine(", 1)[1]
        callback = callback.split("private static func localNetworks", 1)[0]
        self.assertIn("let registry = engineBridge.pluginRegistry", callback)
        self.assertIn("GeneratedPluginRegistrant.register(with: registry)", callback)
        self.assertIn("engineBridge.applicationRegistrar.messenger()", callback)
        self.assertNotRegex(delegate, r"self\.registrar|rootViewController|override func application")

        for target_name, flag, plugin, key in [
            ("Runner", None, None, None),
            ("RunnerInitialSdp", "INITIAL_SDP_EXPERIMENT", "InitialSdpPlugin",
             "com.example.nt_helper/initial_sdp"),
            ("RunnerFirmwareV2", "FIRMWARE_SESSION_V2", "FirmwareSessionPlugin",
             "dev.nosuch.nt_helper/firmware_session_v2"),
        ]:
            with self.subTest(target=target_name):
                scheme = ET.parse(ROOT / f"ios/Runner.xcodeproj/xcshareddata/xcschemes/{target_name}.xcscheme")
                reference = scheme.find("./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference")
                target = project[reference.attrib["BlueprintIdentifier"]]
                self.assertEqual(target["name"], target_name)
                sources = {
                    project[project[file_id]["fileRef"]]["path"]
                    for phase_id in target["buildPhases"]
                    if project[phase_id]["isa"] == "PBXSourcesBuildPhase"
                    for file_id in project[phase_id]["files"]
                }
                self.assertIn("AppDelegate.swift", sources)
                configs = project[target["buildConfigurationList"]]["buildConfigurations"]
                debug = next(project[c]["buildSettings"] for c in configs if project[c]["name"] == "Debug")
                manifest = plistlib.loads((ROOT / "ios" / debug["INFOPLIST_FILE"]).read_bytes())
                scenes = manifest["UIApplicationSceneManifest"]["UISceneConfigurations"]["UIWindowSceneSessionRoleApplication"]
                self.assertEqual(len(scenes), 1)
                self.assertEqual(scenes[0]["UISceneDelegateClassName"], "FlutterSceneDelegate")
                self.assertEqual(scenes[0]["UISceneStoryboardFile"], "Main")
                if flag:
                    self.assertIn(flag, debug["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split())
                    self.assertIn(f"{plugin}.swift", sources)
                    conditional = re.search(rf"#if {flag}\b(.*?)#endif", callback, re.S)
                    self.assertIsNotNone(conditional)
                    self.assertIn(
                        f'{plugin}.register(with: registry.registrar(forPlugin: "{key}")!)',
                        conditional.group(1),
                    )


if __name__ == "__main__":
    unittest.main()
