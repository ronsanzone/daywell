#!/usr/bin/env bash
set -euo pipefail

readonly SWIFTLINT_VERSION="0.65.1"
readonly SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
readonly SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir="${repo_root}/.build/tools"
swiftlint="${tools_dir}/swiftlint"

if [[ -x "${swiftlint}" ]] && [[ "$("${swiftlint}" version)" == "${SWIFTLINT_VERSION}" ]]; then
  echo "SwiftLint ${SWIFTLINT_VERSION} is already installed at ${swiftlint}"
  exit 0
fi

mkdir -p "${tools_dir}"
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/daywell-tools.XXXXXX")
trap 'rm -rf "${temporary_dir}"' EXIT

archive="${temporary_dir}/swiftlint.zip"
echo "Downloading SwiftLint ${SWIFTLINT_VERSION}..."
curl --fail --location --silent --show-error "${SWIFTLINT_URL}" --output "${archive}"

actual_sha256=$(shasum -a 256 "${archive}" | awk '{print $1}')
if [[ "${actual_sha256}" != "${SWIFTLINT_SHA256}" ]]; then
  echo "SwiftLint checksum mismatch: expected ${SWIFTLINT_SHA256}, got ${actual_sha256}" >&2
  exit 1
fi

unzip -q "${archive}" swiftlint -d "${temporary_dir}"
install -m 0755 "${temporary_dir}/swiftlint" "${swiftlint}"
echo "Installed $("${swiftlint}" version) at ${swiftlint}"
