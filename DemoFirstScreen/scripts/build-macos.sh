#!/bin/sh
# Run on the target Mac only. Refuses Linux / non-Darwin.
# Builds and tests for arm64 with a macOS 13 deployment target.
# Does not push, tag, publish, scan the disk, or change system settings.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "build-macos.sh must run on macOS. This host is $(uname -s)." >&2
  exit 2
fi

arch="$(uname -m)"
if [ "$arch" != "arm64" ]; then
  echo "This checkpoint expects Apple Silicon (arm64). Host arch is $arch." >&2
  exit 2
fi

export MACOSX_DEPLOYMENT_TARGET=13.0
cd "$ROOT"

echo "==> swift test (arm64, deployment 13.0)"
swift test --arch arm64 -Xswiftc -target -Xswiftc arm64-apple-macos13.0

echo "==> swift build -c release --arch arm64"
swift build -c release --arch arm64 -Xswiftc -target -Xswiftc arm64-apple-macos13.0

echo "build-macos.sh finished. Use scripts/package-macos.sh to wrap the executable."
