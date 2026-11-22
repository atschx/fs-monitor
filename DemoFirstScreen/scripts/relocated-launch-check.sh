#!/bin/sh
# Unzip the finished app, move it away from the repo and .build, and launch it.
# Also launches the already published preview zip as a control. Does not scan a
# startup disk, request FDA, or change security settings.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ZIP="$ROOT/dist/DemoFirstScreen.app.zip"
PUBLISHED_URL="https://github.com/atschx/fs-monitor/releases/download/v0.1.0-demo-preview.1/DemoFirstScreen.app.zip"
PUBLISHED_SHA="91dd03b57d0fcae67d622b0fb3520580dc5c6bbf1ba0d0ccdd4c3e36236e008d"
WORK="${TMPDIR:-/tmp}/fs-monitor-relocated-launch"
rm -rf "$WORK"
mkdir -p "$WORK"
LOG="$ROOT/dist/LAUNCH_CHECK.txt"
: > "$LOG"
note() { printf '%s\n' "$1" | tee -a "$LOG"; }

if [ -d "$ROOT/.build" ]; then
  mv "$ROOT/.build" "$WORK/hidden-build"
  note "build_dir_hidden=yes"
else
  note "build_dir_hidden=absent"
fi

cleanup() {
  if [ -n "${VOLUME_MOUNT:-}" ]; then
    hdiutil detach "$VOLUME_MOUNT" >/dev/null 2>&1 || true
  fi
  pkill -x DemoFirstScreen >/dev/null 2>&1 || true
}
trap cleanup EXIT

ditto -x -k "$ZIP" "$WORK/unzipped"
APP="$WORK/unzipped/DemoFirstScreen.app"
test -d "$APP"
test ! -L "$APP/Contents/Resources/DemoFirstScreen_DemoFirstScreenCore.bundle"
test -d "$APP/Contents/Resources/DemoFirstScreen_DemoFirstScreenCore.bundle"
test -d "$APP/Contents/Resources/DemoFirstScreen_DemoFirstScreenApp.bundle"
test -f "$APP/Contents/Resources/DemoFirstScreen_DemoFirstScreenApp.bundle/Contents/Resources/Resources/Eyes.metal" \
  -o -f "$APP/Contents/Resources/DemoFirstScreen_DemoFirstScreenApp.bundle/Resources/Eyes.metal"

BIN="$APP/Contents/MacOS/DemoFirstScreen"
note "unzipped_lipo=$(lipo -archs "$BIN")"
note "unzipped_plist_min=$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")"
otool -l "$BIN" | awk '/cmd LC_BUILD_VERSION/{p=1} p && /minos/{print "unzipped_minos="$2; exit}' | tee -a "$LOG"
codesign --verify --strict --verbose=2 "$APP"
note "unzipped_codesign_strict=ok"
test "$(lipo -archs "$BIN")" = "arm64"
test "$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")" = "13.0"

python3 - "$WORK" "$LOG" "$APP" "$PUBLISHED_URL" "$PUBLISHED_SHA" <<'PY'
import os, pathlib, shutil, signal, subprocess, sys, time, urllib.request

work, log_path, app_src, published_url, published_sha = sys.argv[1:]
log = pathlib.Path(log_path)

def record(line):
    print(line, flush=True)
    with log.open("a", encoding="utf-8") as handle:
        handle.write(line + "\n")

def run_direct(binary, receipt, timeout=12):
    env = os.environ.copy()
    env.pop("PACKAGE_RESOURCE_BUNDLE_PATH", None)
    env.pop("PACKAGE_RESOURCE_BUNDLE_URL", None)
    if receipt:
        env["FS_MONITOR_STARTUP_RECEIPT"] = receipt
    process = subprocess.Popen(
        [binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=env, start_new_session=True,
    )
    try:
        out, err = process.communicate(timeout=timeout)
        return {"alive": False, "code": process.returncode, "out": out.decode(errors="replace"), "err": err.decode(errors="replace")}
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        out, err = process.communicate()
        return {"alive": True, "code": "timeout", "out": out.decode(errors="replace"), "err": err.decode(errors="replace")}

def assert_receipt(path):
    text = pathlib.Path(path).read_text(encoding="utf-8")
    values = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    record("receipt=" + text.replace("\n", " "))
    for key in ("hub_bytes", "rest_bytes", "metal_bytes"):
        if int(values.get(key, "-1")) <= 0:
            raise SystemExit(f"startup resource was not loaded: {key}")
    if values.get("window") != "ready":
        raise SystemExit("window was not prepared")
    if values.get("scansStarted") != "0":
        raise SystemExit("startup scan started without consent")

def launch_fixed(label, app_path):
    binary = str(pathlib.Path(app_path) / "Contents" / "MacOS" / "DemoFirstScreen")
    receipt = str(pathlib.Path(work) / f"{label}.receipt")
    result = run_direct(binary, receipt, 15)
    record(f"{label}_direct_alive={result['alive']} code={result['code']}")
    if result["err"].strip():
        record(f"{label}_stderr=" + result["err"].strip().splitlines()[-1][:300])
    if not result["alive"]:
        raise SystemExit(f"{label} exited before the window stayed up")
    assert_receipt(receipt)
    record(f"{label}_direct=ok")

def launchservices(label, app_path):
    reports = pathlib.Path.home() / "Library" / "Logs" / "DiagnosticReports"
    before = set(reports.glob("DemoFirstScreen*")) if reports.is_dir() else set()
    subprocess.run(["pkill", "-x", "DemoFirstScreen"], check=False)
    opened = subprocess.run(["open", app_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    record(f"{label}_launchservices_open={opened.returncode}")
    if opened.returncode != 0:
        record(f"{label}_launchservices_open_error=" + (opened.stderr or opened.stdout).strip()[:300])
        return False
    time.sleep(4)
    alive = subprocess.run(["pgrep", "-x", "DemoFirstScreen"], stdout=subprocess.PIPE, text=True)
    pids = [line for line in alive.stdout.splitlines() if line.strip()]
    record(f"{label}_launchservices_alive={bool(pids)}")
    after = set(reports.glob("DemoFirstScreen*")) if reports.is_dir() else set()
    new_reports = after - before
    trapped = False
    for report in new_reports:
        text = report.read_text(errors="replace")
        if "DemoArtwork" in text or "Bundle.module" in text or "assertionFailure" in text or "unable to find bundle" in text:
            trapped = True
    record(f"{label}_launchservices_new_crash_report={bool(new_reports)} startup_trap={trapped}")
    subprocess.run(["pkill", "-x", "DemoFirstScreen"], check=False)
    return bool(pids) and not trapped

plain = pathlib.Path(work) / "plain" / "DemoFirstScreen.app"
spaced = pathlib.Path(work) / "path with spaces" / "DemoFirstScreen.app"
shutil.copytree(app_src, plain, symlinks=True)
shutil.copytree(app_src, spaced, symlinks=True)
launch_fixed("plain", plain)
launch_fixed("spaces", spaced)
plain_ls = launchservices("plain", str(plain))
spaces_ls = launchservices("spaces", str(spaced))
if not plain_ls or not spaces_ls:
    raise SystemExit("LaunchServices launch did not keep the relocated app alive")
record("launchservices=ok")

def resign(app):
    bundles = sorted((path for path in pathlib.Path(app).rglob("*.bundle") if path.is_dir()), key=lambda path: len(path.parts), reverse=True)
    for bundle in bundles:
        subprocess.check_call(["codesign", "--force", "--sign", "-", "--timestamp=none", str(bundle)])
    subprocess.check_call(["codesign", "--force", "--sign", "-", "--timestamp=none", "--identifier", "me.atschx.fsmonitor.demofirstscreen", str(app)])

missing = pathlib.Path(work) / "missing artwork" / "DemoFirstScreen.app"
shutil.copytree(app_src, missing, symlinks=True)
for relative in (
    "Contents/Resources/DemoFirstScreen_DemoFirstScreenCore.bundle",
    "Contents/MacOS/DemoFirstScreen_DemoFirstScreenCore.bundle",
):
    target = missing / relative
    if target.is_symlink() or target.exists():
        if target.is_dir() and not target.is_symlink():
            shutil.rmtree(target)
        else:
            target.unlink()
resign(missing)
result = run_direct(str(missing / "Contents" / "MacOS" / "DemoFirstScreen"), None, 12)
record(f"missing_artwork_alive={result['alive']} code={result['code']}")
record("missing_artwork_stderr=" + result["err"].strip().splitlines()[-1][:300] if result["err"].strip() else "missing_artwork_stderr=")
if result["alive"] or result["code"] in (133, 134, 138, -5, -6) or "assertionFailure" in result["err"] or "Fatal error" in result["err"]:
    raise SystemExit("missing artwork still trapped or stayed running")
if result["code"] != 1 or "Startup resources unavailable" not in result["err"]:
    raise SystemExit("missing artwork did not exit with a startup resource diagnostic")
record("missing_artwork=controlled")

missing_metal = pathlib.Path(work) / "missing metal" / "DemoFirstScreen.app"
shutil.copytree(app_src, missing_metal, symlinks=True)
metal_files = list(missing_metal.rglob("Eyes.metal"))
if not metal_files:
    raise SystemExit("Eyes.metal was not inside the packaged app")
for path in metal_files:
    path.unlink()
resign(missing_metal)
result = run_direct(str(missing_metal / "Contents" / "MacOS" / "DemoFirstScreen"), None, 12)
record(f"missing_metal_alive={result['alive']} code={result['code']}")
record("missing_metal_stderr=" + result["err"].strip().splitlines()[-1][:300] if result["err"].strip() else "missing_metal_stderr=")
if result["alive"] or result["code"] in (133, 134, 138, -5, -6) or "assertionFailure" in result["err"] or "Fatal error" in result["err"]:
    raise SystemExit("missing Eyes.metal still trapped or stayed running")
if result["code"] != 1 or "Startup resources unavailable" not in result["err"]:
    raise SystemExit("missing Eyes.metal did not exit with a startup resource diagnostic")
record("missing_metal=controlled")

published = pathlib.Path(work) / "published.zip"
urllib.request.urlretrieve(published_url, published)
digest = subprocess.check_output(["shasum", "-a", "256", str(published)], text=True).split()[0]
record(f"published_sha256={digest}")
if digest != published_sha:
    raise SystemExit("published preview zip hash changed")
published_dir = pathlib.Path(work) / "published unzip"
published_dir.mkdir()
subprocess.check_call(["ditto", "-x", "-k", str(published), str(published_dir)])
published_app = published_dir / "DemoFirstScreen.app"
resource = published_app / "Contents" / "Resources" / "DemoFirstScreen_DemoFirstScreenCore.bundle"
record(f"published_resource_is_symlink={resource.is_symlink()}")
probe_src = pathlib.Path(work) / "bundle_probe.swift"
probe_bin = pathlib.Path(work) / "bundle_probe"
probe_src.write_text(
    "import Foundation\n"
    "let url = URL(fileURLWithPath: CommandLine.arguments[1])\n"
    "fputs(Bundle(url: url) == nil ? \"rejected\\n\" : \"accepted\\n\", stdout)\n",
    encoding="utf-8",
)
subprocess.check_call(["swiftc", "-o", str(probe_bin), str(probe_src)])
probe = subprocess.run([str(probe_bin), str(resource)], stdout=subprocess.PIPE, text=True)
record("published_symlink_bundle_open=" + probe.stdout.strip())
result = run_direct(str(published_app / "Contents" / "MacOS" / "DemoFirstScreen"), None, 12)
record(f"published_direct_alive={result['alive']} code={result['code']}")
err = result["err"]
record("published_direct_trapped=" + str((not result["alive"]) and ("Fatal error" in err or "unable to find bundle" in err or result["code"] in (133, 134, -5, -6))))
if err.strip():
    record("published_direct_stderr=" + err.strip().splitlines()[-1][:300])
published_ls = launchservices("published", str(published_app))
record(f"published_launchservices_survived={published_ls}")

volume_dir = pathlib.Path(work) / "volume"
volume_dir.mkdir()
image = volume_dir / "preview.dmg"
created = subprocess.run(
    ["hdiutil", "create", "-size", "80m", "-fs", "APFS", "-volname", f"FSMCI{os.getpid()}", str(image)],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
)
mount = None
if created.returncode != 0:
    record("volume=unavailable " + (created.stderr.strip().splitlines() or ["hdiutil create failed"])[-1][:300])
else:
    attached = subprocess.run(
        ["hdiutil", "attach", "-nobrowse", str(image)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    if attached.returncode != 0:
        record("volume=unavailable " + (attached.stderr.strip().splitlines() or ["hdiutil attach failed"])[-1][:300])
    else:
        try:
            mount = next(line.split("\t")[-1] for line in attached.stdout.splitlines() if "/Volumes/" in line)
            record("volume_attached=yes")
            volume_app = pathlib.Path(mount) / "DemoFirstScreen.app"
            subprocess.check_call(["ditto", str(app_src), str(volume_app)])
            launch_fixed("volume", volume_app)
            volume_ls = launchservices("volume", str(volume_app))
            if not volume_ls:
                raise SystemExit("LaunchServices launch from the temporary volume did not stay alive")
            record("volume=ok")
        finally:
            if mount:
                subprocess.run(["hdiutil", "detach", mount], check=False)

record("relocated_launch=ok")
PY

printf '\n' >> "$ROOT/dist/BUILD_INFO.txt"
cat "$LOG" >> "$ROOT/dist/BUILD_INFO.txt"
echo "relocated-launch-check finished."
