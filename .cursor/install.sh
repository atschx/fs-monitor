#!/usr/bin/env bash
# Idempotent bootstrap for the portable core. No third-party Swift packages.
set -euo pipefail

swift package resolve
swift build --build-tests
