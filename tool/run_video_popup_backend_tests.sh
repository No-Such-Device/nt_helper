#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_root="${FLUTTER_ROOT:-$(python3 -c 'import pathlib,shutil; print(pathlib.Path(shutil.which("flutter")).resolve().parent.parent)')}"
wrapper="$flutter_root/engine/src/flutter/shell/platform/common/client_wrapper"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
c++ -std=c++17 -Wall -Wextra -Werror -I"$wrapper/include" \
  test/native/windows_video_popup_remote_test.cpp "$wrapper/standard_codec.cc" \
  -o "$tmp/windows-remote-test"
"$tmp/windows-remote-test"
if [[ "$(uname)" == Darwin ]]; then
  framework="$flutter_root/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64"
  plugin="$(python3 -c 'import json,pathlib,urllib.parse; c=pathlib.Path(".dart_tool/package_config.json").resolve(); p=next(p for p in json.loads(c.read_text())["packages"] if p["name"]=="desktop_multi_window"); print(pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(urllib.parse.urljoin(c.as_uri(),p["rootUri"])).path)))')"
  swiftc -F "$framework" -framework FlutterMacOS -Xlinker -rpath -Xlinker "$framework" \
    "$plugin/macos/Classes/WindowChannel.swift" test/native/desktop_multi_window_remote_test.swift \
    -o "$tmp/desktop-remote-test"
  "$tmp/desktop-remote-test"
fi
# Verify that the tested bridge is wired into the production Windows adapter,
# including cleanup paths that portable codec tests cannot execute as a GUI.
python3 - <<'PY'
from pathlib import Path
s = Path('windows/runner/windows_video_popup_manager.cpp').read_text()
for method in ['remoteAcquire', 'remoteRead', 'remoteOpen', 'remoteAction', 'remoteClose', 'remoteDetach', 'getHardwareScreenshot']:
    assert f'call.method_name() == "{method}"' in s
assert 'ForwardVideoPopupRemote(main_channel_.get(), method, arguments,' in s
assert 'WM_SHOWWINDOW' in s and 'WA_INACTIVE' in s and 'SIZE_MINIMIZED' in s
assert 'EndRemoteHost(*remote_host_, true)' in s and '*alive_ = false' in s
assert 'remote_expanded_ ? 352 : 100' in s
assert '"remoteLifecycle"' in s and '"close"' in s
print('Windows production lifecycle/sizing/forwarding call-site checks passed (source binding, not Win32 execution).')
PY
