#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
  ios/InitialSdpDriverTests/status_only_test.cpp -o "$build_dir/status_only_test"
"$build_dir/status_only_test"
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
  ios/InitialSdpDriverTests/programming_test.cpp -o "$build_dir/programming_test"
"$build_dir/programming_test"
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -D FIRMWARE_TRANSCRIPT_BRIDGE \
  -c ios/InitialSdpDriverTests/programming_test.cpp -o "$build_dir/transcript.o"
xcrun swiftc -D FIRMWARE_SESSION_TEST ios/Runner/FirmwareSessionState.swift \
  ios/InitialSdpDriverTests/session_state_test.swift "$build_dir/transcript.o" \
  -lc++ -o "$build_dir/session_state_test"
"$build_dir/session_state_test"
