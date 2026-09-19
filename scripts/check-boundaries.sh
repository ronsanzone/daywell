#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${repo_root}"

if matches=$(grep -RInE \
  --include='*.swift' \
  '^[[:space:]]*(@[A-Za-z]+[[:space:]]+)?(public[[:space:]]+|internal[[:space:]]+|private[[:space:]]+)?import[[:space:]]+((class|struct|enum|func|var|let|typealias|protocol)[[:space:]]+)?(SwiftUI|AppKit|EventKit|DaywellKit)([.[:space:]]|$)' \
  Sources/DaywellCore); then
  echo "DaywellCore must not import UI, EventKit, or DaywellKit modules:" >&2
  echo "${matches}" >&2
  exit 1
else
  status=$?
  if [[ ${status} -ne 1 ]]; then
    echo "Dependency boundary scan failed (${status})" >&2
    exit "${status}"
  fi
fi

echo "Dependency boundaries passed"
