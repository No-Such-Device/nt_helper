# iPad initial-SDP development experiment

This is a local, development-signed experiment for Neal's **M1 iPad Pro on
iPadOS 16+**, not a firmware updater or a distribution build. It requests normal
MIDI bootloader entry, observes **1FC9:0135**, connects the bundled DriverKit
extension, and queries initial SDP error-status only. It cannot upload a loader,
jump, enter the second stage, erase, program firmware, configure flash or use
fuses. A returned status (even a nonzero error-status word) proves a decoded
protocol response, not firmware-update feasibility.

## Setup and local build

Use a Mac with Xcode, its iOS/DriverKit SDKs, Flutter and CocoaPods. Sign into
Xcode with the authorized developer account/team **KN424RZG26**. Connect/register
the intended iPad with Xcode and enable Developer Mode on the iPad when prompted.
Do not substitute a personal team, distribution certificate, unsigned build,
simulator or desktop USB proxy.

The isolated `RunnerInitialSdp` scheme uses **Debug**, arm64, iPad-only deployment
16.0+, automatic **Apple Development** signing, and these explicit app IDs:

- App: `dev.nosuch.ntHelper.initialSdp`; development profile must allow
  `com.apple.developer.driverkit.communicates-with-drivers`.
- Embedded driver: `dev.nosuch.ntHelper.initialSdp.driver`; DriverKit App
  Development profile must allow `com.apple.developer.driverkit` and
  `com.apple.developer.driverkit.transport.usb` for vendor **8137 / 0x1FC9**,
  product **309 / 0x0135**. Matching remains scoped to that initial device.

Use Apple's self-service development capabilities/profile route, not an
application for customer-distribution approval. Xcode automatic provisioning is
attempted by the command below; if manual setup is necessary, enable those
capabilities for the explicit IDs in Certificates, Identifiers & Profiles,
create/download the corresponding **development** profiles, and refresh Xcode's
profiles. Never export signing keys or bypass entitlement/profile validation.
See [DriverKit development profiles](https://developer.apple.com/help/account/provisioning-profiles/create-a-driverkit-development-provisioning-profile/)
and [Bring your driver to iPad](https://developer.apple.com/videos/play/wwdc2022/110373/).

From the repository root:

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
(cd ios && pod install)
xcodebuild -workspace ios/Runner.xcworkspace -scheme RunnerInitialSdp \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/initial-sdp -allowProvisioningUpdates build
```

The scheme prepares Flutter's Swift-package framework before compiling plugins;
its target sets `NT_INITIAL_SDP_EXPERIMENT=true` for Dart and
`INITIAL_SDP_EXPERIMENT` for Swift. Ordinary Runner/release builds expose neither
the experiment menu nor its native channel. Keep the desktop firmware gate intact.
Use Xcode's `RunnerInitialSdp` scheme with the physical iPad selected and Run to
install/launch both app and embedded driver. A generic-device build alone does
not prove installation on the owner's device.

If provisioning returns **“PLA Update available”**, the account holder must sign
into the Apple Developer account and accept the latest Program License Agreement,
then rerun the same command. That concrete account error does not call for a
release entitlement application. Preserve all other exact provisioning errors;
request only the account/profile/device action they actually identify.

## Inspect the signed product before installation

```sh
APP=build/initial-sdp/Build/Products/Debug-iphoneos/RunnerInitialSdp.app
DRIVER="$APP/SystemExtensions/dev.nosuch.ntHelper.initialSdp.driver.dext"
codesign --verify --strict --verbose=2 "$DRIVER"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP"
codesign -dvv "$DRIVER"
codesign -d --entitlements :- "$APP"
codesign -d --entitlements :- "$DRIVER"
find "$APP" -name '*.mobileprovision' -o -name '*.provisionprofile'
# For each actual embedded profile path printed above:
security cms -D -i /actual/path/to/embedded-profile
```

Require actual Apple Development signatures for the authorized team on **both**
products, matching app identifiers, unexpired development profiles permitting
the signed entitlements above, and device authorization as required by each
profile. Inspect development `get-task-allow` where applicable. Do not call an
ad-hoc signature, missing profile, failed build or unsigned compile installable.

## Owner's physical run (record observations, not assumptions)

1. Record actual M1 iPad/OS, app/driver build, installed NT firmware and normal
   operation **before** the experiment. Enable the bundled driver in **Settings
   > General > Drivers**. Use a USB **data** cable and power the NT independently.
2. Synchronize the selected live NT in the development app. Open **More > Initial
   SDP experiment**. Opening sends nothing and retains MIDI ownership. Demo,
   offline, unknown firmware and firmware below 1.15 cannot request entry.
3. Explicitly choose **Request bootloader and read status**. Record separately:
   request sent, observed 1FC9:0135, driver connected, decoded response/HAB/status
   words or the precise failed stage. MIDI disappearance and a timer prove none
   of the USB/protocol stages. Public service observation cannot distinguish a
   disabled driver from missing hardware; check Settings, profiles, cable/power
   if no service appears. If physical unplug/replug is needed, record it rather
   than claiming uninterrupted switchover.
4. Close the experiment. **Power-cycle the NT**, verify return to normal operation,
   and compare the installed firmware with the baseline. Record the actual
   outcome even after a failed attempt. Reconnect/synchronize and reopen for a
   new attempt; the consumed MIDI manager is never reused.

Automated controlled-transport tests and native builds do not establish any of
these physical observations. No TestFlight, App Store, release tag or public
asset is part of this development configuration.
