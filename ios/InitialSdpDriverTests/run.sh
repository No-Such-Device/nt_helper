#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
  ios/InitialSdpDriverTests/status_only_test.cpp -o "$build_dir/status_only_test"
"$build_dir/status_only_test"
