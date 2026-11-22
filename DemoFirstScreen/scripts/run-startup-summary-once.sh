#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]
[ ! -e dist ] && [ ! -e verification-r2 ]
export MACOSX_DEPLOYMENT_TARGET=13.0
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/local-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/local-swift-cache"
ARGS=(-c release --arch arm64 -Xswiftc -target -Xswiftc arm64-apple-macos13.0)
export FS_TEST_FIXTURE_PARENT="$ROOT/OWN-CREATED-test-fixtures"
mkdir -p "$FS_TEST_FIXTURE_PARENT" logs
swift test "${ARGS[@]}" > logs/release-tests-r2.log 2>&1
swift build "${ARGS[@]}" > logs/release-build-r2.log 2>&1
BIN="$(swift build "${ARGS[@]}" --show-bin-path)";EXE="$BIN/DemoFirstScreen"
lipo -archs "$EXE" > logs/architecture.log
[ "$(lipo -archs "$EXE")" = arm64 ]
otool -l "$EXE" > logs/load-commands.log
python3 - <<'PY'
import pathlib,re
s=pathlib.Path('logs/load-commands.log').read_text();m=re.search(r'cmd LC_BUILD_VERSION.*?\bminos\s+(\S+)',s,re.S);assert m and m[1] in ('13.0','13.0.0')
PY
"$EXE" --startup-metadata-verify-only > logs/startup-mapping-metadata-only.json
"$EXE" --gpu-verify-only "$ROOT/verification-r2" > logs/verification-r2.log 2>&1
python3 - <<'PY'
import json,pathlib
b=json.loads(pathlib.Path('/Users/huluwa/FSMonitor-GPUIntegrated-20261121-183046-PT/DemoFirstScreen/verification-r2/gpu-cpu-verification.json').read_text());n=json.loads(pathlib.Path('verification-r2/safe-gaze/legacy-uniform-material-canonical.json').read_text());out=[]
for original,c in zip(b['cases'],n):
 assert original['pose']==c['pose']
 for eye,x in enumerate(original['eyesLeftRight']):out.append({'pose':c['pose'],'eye':eye,'sameFrozenLegacyUniformInput':True,'zeroRGBAByteDifference':x['gpuRGBA_SHA256']==c['GPUrawSHA256'][eye]})
pathlib.Path('verification-r2/SAME-UNIFORM-MATERIAL-vs183046.json').write_text(json.dumps(out,indent=2));assert len(out)==6 and all(r['zeroRGBAByteDifference'] for r in out)
f=json.loads(pathlib.Path('verification-r2/full-demo/integrated-full-evidence-report.json').read_text());assert all(x['nonEyeDifferentRGBABytesVsSame163929CPUUI']==0 and x['foregroundEyeOverlapPixels']==0 for x in f['cases'])
PY
python3 - <<'CHECK'
import json,pathlib
base=pathlib.Path('/Users/huluwa/FSMonitor-SafeIdle-20261121-191639-PT/DemoFirstScreen/verification-r2')
a=json.loads((base/'gpu-cpu-verification.json').read_text());b=json.loads(pathlib.Path('verification-r2/gpu-cpu-verification.json').read_text());out=[]
for aa,bb in zip(a['cases'],b['cases']):
 assert aa['pose']==bb['pose']
 for i,(x,y)in enumerate(zip(aa['eyesLeftRight'],bb['eyesLeftRight'])):out.append({'pose':aa['pose'],'eye':i,'GPUrawRGBAZeroDifferenceVs191639':x['gpuRGBA_SHA256']==y['gpuRGBA_SHA256']})
pathlib.Path('verification-r2/SAME-SAFE-UNIFORM-vs191639.json').write_text(json.dumps(out,indent=2));assert len(out)==6 and all(x['GPUrawRGBAZeroDifferenceVs191639']for x in out)
f=json.loads(pathlib.Path('verification-r2/startup-summary/summary-fixture-evidence.json').read_text());assert all(x['scansStarted']==0 for x in f['cases'])
CHECK
mkdir -p dist/DemoFirstScreen-GPU.app/Contents/MacOS dist/DemoFirstScreen-GPU.app/Contents/Resources
APP="$ROOT/dist/DemoFirstScreen-GPU.app";cp "$EXE" "$APP/Contents/MacOS/DemoFirstScreen"
for target in DemoFirstScreenCore DemoFirstScreenApp;do
 bundle="";for candidate in "$BIN/DemoFirstScreen_${target}.bundle" "$BIN/${target}.bundle";do if [ -d "$candidate" ];then bundle="$candidate";break;fi;done
 [ -n "$bundle" ]
 for dest in "$APP/Contents/MacOS" "$APP/Contents/Resources";do cp -R "$bundle" "$dest/";codesign --force --sign - --timestamp=none "$dest/$(basename "$bundle")";done
done
python3 - "$APP" <<'PY'
import pathlib,sys,plistlib
p=pathlib.Path(sys.argv[1]);d={'CFBundleExecutable':'DemoFirstScreen','CFBundleIdentifier':'local.fsmonitor.integrated-gpu-demo','CFBundleName':'FSMonitor Integrated GPU Demo','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'0.5-consented-startup-summary','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True};(p/'Contents/Info.plist').write_bytes(plistlib.dumps(d))
PY
cp Sources/DemoFirstScreenApp/Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP" > logs/codesign-verify.log 2>&1
codesign -d --verbose=4 "$APP" > logs/codesign-details.log 2>&1
ditto -c -k --keepParent "$APP" dist/DemoFirstScreen-GPU.app.zip
if [ "${1:-}" = --launch ];then
 "$APP/Contents/MacOS/DemoFirstScreen" --integrated-gpu-diagnostics-dir "$ROOT/integrated-diagnostics" > logs/app-stdout.log 2> logs/app-stderr.log &
 printf '%s\n' "$!" > logs/launched.pid
fi
