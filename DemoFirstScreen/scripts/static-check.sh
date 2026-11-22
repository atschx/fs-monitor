#!/bin/sh
# Safe to run on Linux. Source/static checks only — not a compile or test run.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fail=0
echo "static-check: $ROOT"

if grep -R -n -E "import[[:space:]]+FSMonitor(Core|Proc)?\\b" "$ROOT/Sources" "$ROOT/Tests" "$ROOT/Package.swift"; then
  echo "FAIL: demo sources import FSMonitor targets" >&2
  fail=1
else
  echo "OK: no FSMonitor imports"
fi

if grep -R -n -E "(DirectoryScanner|MonitorSession|MonitorController|MacFSEventsMonitor|MacProcessProbe)[[:space:]]*\\(" "$ROOT/Sources"; then
  echo "FAIL: demo sources appear to construct original services" >&2
  fail=1
else
  echo "OK: no original service constructors in Sources"
fi

# Ignore // comments; only fail if Package.swift actually depends on the original package.
if grep -v "^[[:space:]]*//" "$ROOT/Package.swift" | grep -E "dependencies:.*FSMonitor" >/dev/null; then
  echo "FAIL: Package.swift depends on FSMonitor" >&2
  fail=1
else
  echo "OK: Package.swift does not depend on FSMonitor"
fi

python3 - "$ROOT" <<"PY"
import json, sys
from pathlib import Path
root = Path(sys.argv[1])
prod = json.loads((root / "Sources/DemoFirstScreenCore/Resources/eric-du-20261121-readonly.json").read_text())
fix = json.loads((root / "Tests/DemoFirstScreenCoreTests/Fixtures/chartable-four-sectors-testOnly.json").read_text())
assert prod.get("testOnly") is False, "production snapshot must not be testOnly"
assert fix.get("testOnly") is True, "fixture must be testOnly"
assert prod["id"] == "eric-du-20261121-readonly"
bytes_sum = sum(i["bytes"] for i in prod["items"])
assert bytes_sum != 200_000_000_000
assert prod["nonOverlapVerified"] is False
assert prod["apfsRootDataDedupVerified"] is False
print("OK: bundled JSON parses and production is not the old example / not chartable flags")
ex = json.loads((root / "Sources/DemoFirstScreenCore/Resources/example-interaction-five-sectors.json").read_text())
assert ex.get("testOnly") is False
assert ex.get("exampleInteraction") is True
assert ex["id"] == "demo-example-five-sectors-20261121"
assert ex["id"] != prod["id"]
assert len(ex["items"]) == 5
ex_sum = sum(i["bytes"] for i in ex["items"])
assert ex_sum == 240_000_000_000
assert ex_sum != 200_000_000_000
assert {i["id"] for i in ex["items"]}.isdisjoint({i["id"] for i in prod["items"]})
assert {i["bytes"] for i in ex["items"]}.isdisjoint({20_000_000_000, 30_000_000_000, 50_000_000_000, 100_000_000_000, 10_000_000_000, 15_000_000_000, 25_000_000_000})
print("OK: example-interaction JSON is isolated, five addable sectors, not the old 4-sector templates")
art = root / "Sources/DemoFirstScreenCore/Resources/artwork"
for name in ["d2-hub.png", "d2-eyes-rest.png", "d2-eyes-gaze-left.png", "d2-eyes-gaze-right.png", "ASSET-SOURCES.json"]:
    assert (art / name).is_file(), name
print("OK: documented D2 eye and hub crops are present with provenance")
PY

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "static-check passed (not a Swift compile)"
