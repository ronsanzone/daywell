#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${repo_root}"

swiftlint="${repo_root}/.build/tools/swiftlint"
if [[ ! -x "${swiftlint}" ]]; then
  echo "SwiftLint is missing. Run: bash scripts/bootstrap-tools.sh" >&2
  exit 1
fi
if [[ "$("${swiftlint}" version)" != "0.65.1" ]]; then
  echo "SwiftLint version mismatch. Run: bash scripts/bootstrap-tools.sh" >&2
  exit 1
fi

echo "==> Formatting"
swift format lint --strict --recursive Sources Tests Package.swift

echo "==> SwiftLint"
developer_dir=$(xcode-select -p)
if [[ -d "${developer_dir}/usr/lib/sourcekitdInProc.framework" ]]; then
  export DYLD_FRAMEWORK_PATH="${developer_dir}/usr/lib${DYLD_FRAMEWORK_PATH:+:${DYLD_FRAMEWORK_PATH}}"
fi
"${swiftlint}" lint --strict --config .swiftlint.yml

echo "==> Dependency boundaries"
bash scripts/check-boundaries.sh

echo "==> Build"
swift build --product Daywell

echo "==> Tests"
swift test --disable-xctest
