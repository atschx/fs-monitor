#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)";RUN_ROOT="$(dirname "$ROOT")"
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]
case "$RUN_ROOT" in "$HOME"/FSMonitor-GPUIntegrated-20*-PT) ;; *) exit 2;; esac
cd "$ROOT"
for d in .build logs dist verification integrated-diagnostics;do [ ! -e "$d" ] || { echo "Refuse existing $d";exit 2; };done
mkdir logs
export MACOSX_DEPLOYMENT_TARGET=13.0
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/local-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/local-swift-cache"
python3 scripts/integration-static.py > logs/static-audit.json
ARGS=(-c release --arch arm64 -Xswiftc -target -Xswiftc arm64-apple-macos13.0)
swift test "${ARGS[@]}" > logs/release-tests.log 2>&1
swift build "${ARGS[@]}" > logs/release-build.log 2>&1
BIN="$(swift build "${ARGS[@]}" --show-bin-path)";EXE="$BIN/DemoFirstScreen"
lipo -archs "$EXE" > logs/architecture.log
[ "$(lipo -archs "$EXE")" = arm64 ]
otool -l "$EXE" > logs/load-commands.log
python3 - <<'PY'
import pathlib,re
s=pathlib.Path('logs/load-commands.log').read_text();m=re.search(r'cmd LC_BUILD_VERSION.*?\bminos\s+(\S+)',s,re.S);assert m and m[1] in ('13.0','13.0.0')
PY
"$EXE" --gpu-verify-only "$ROOT/verification" > logs/verification.log 2>&1
python3 - <<'PY'
import json,pathlib
b=json.loads(pathlib.Path('/Users/huluwa/FSMonitor-EyeGPUStudy-20261121-174831-PT/EyeGPUStudy/verification/gpu-cpu-verification.json').read_text());n=json.loads(pathlib.Path('verification/gpu-cpu-verification.json').read_text());out=[]
assert b['shaderSHA256']==n['shaderSHA256']
for a,c in zip(b['cases'],n['cases']):
 assert a['pose']==c['pose'] and a['target']==c['target']
 for eye,(x,y)in enumerate(zip(a['eyesLeftRight'],c['eyesLeftRight'])):out.append({'pose':a['pose'],'eye':eye,'zeroRGBAByteDifference':x['gpuRGBA_SHA256']==y['gpuRGBA_SHA256'],'pixelsMatch':x['pixelCount']==y['pixelCount']})
pathlib.Path('verification/GPU-vs-174831.json').write_text(json.dumps(out,indent=2));assert len(out)==6 and all(r['zeroRGBAByteDifference']and r['pixelsMatch']for r in out)
f=json.loads(pathlib.Path('verification/full-demo/integrated-full-evidence-report.json').read_text());assert all(x['nonEyeDifferentRGBABytesVsSame163929CPUUI']==0 and x['foregroundEyeOverlapPixels']==0 for x in f['cases'])
PY
mkdir -p dist/DemoFirstScreen-GPU.app/Contents/MacOS dist/DemoFirstScreen-GPU.app/Contents/Resources
APP="$ROOT/dist/DemoFirstScreen-GPU.app";cp "$EXE" "$APP/Contents/MacOS/DemoFirstScreen"
for target in DemoFirstScreenCore DemoFirstScreenApp;do
 bundle="";for candidate in "$BIN/DemoFirstScreen_${target}.bundle" "$BIN/${target}.bundle";do if [ -d "$candidate" ];then bundle="$candidate";break;fi;done
 [ -n "$bundle" ]
 for dest in "$APP/Contents/MacOS" "$APP/Contents/Resources";do cp -R "$bundle" "$dest/";codesign --force --sign - --timestamp=none "$dest/$(basename "$bundle")";done
done
python3 - "$APP" <<'PY'
import pathlib,sys,plistlib
p=pathlib.Path(sys.argv[1]);d={'CFBundleExecutable':'DemoFirstScreen','CFBundleIdentifier':'local.fsmonitor.integrated-gpu-demo','CFBundleName':'FSMonitor Integrated GPU Demo','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.1-gpu-integrated','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True};(p/'Contents/Info.plist').write_bytes(plistlib.dumps(d))
PY
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP" > logs/codesign-verify.log 2>&1
codesign -d --verbose=4 "$APP" > logs/codesign-details.log 2>&1
ditto -c -k --keepParent "$APP" dist/DemoFirstScreen-GPU.app.zip
if [ "${1:-}" = --launch ];then
 "$APP/Contents/MacOS/DemoFirstScreen" --integrated-gpu-diagnostics-dir "$ROOT/integrated-diagnostics" > logs/app-stdout.log 2> logs/app-stderr.log &
 printf '%s\n' "$!" > logs/launched.pid
fi
