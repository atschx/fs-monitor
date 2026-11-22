#!/usr/bin/env python3
import pathlib,tarfile,json,hashlib,re,subprocess
p=pathlib.Path(__file__).resolve().parents[1]
# Manifest generated from exact163929 original package and174831 validated shader/support.
m=json.loads((p.parent/'frozen-integration-reference.json').read_text())
for path,sha in m.items():assert hashlib.sha256((p/path).read_bytes()).hexdigest()==sha,path
files=list((p/'Sources').rglob('*.swift'))+[p/'Sources/DemoFirstScreenApp/Resources/Eyes.metal']
for f in files:
 s=f.read_text();v=re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"','',s,flags=re.S);stack=[]
 for c in v:
  if c in '([{':stack.append(c)
  elif c in ')]}':assert stack and stack.pop()=={')':'(',']':'[','}':'{'}[c],f
 assert not stack,f
 assert not re.search(r'addGlobalMonitorForEvents|CGEventTapCreate|CGRequestScreenCaptureAccess|CGWindowListCreateImage|SCShareableContent',s),f
n=sum(len(re.findall(r'\bfunc test\w+\s*\(',f.read_text()))for f in (p/'Tests').rglob('*.swift'));assert n==126,n
subprocess.run(['bash','-n',str(p/'scripts/build-integrated-once.sh')],check=True)
print(json.dumps({'sourceStaticOnly':True,'frozenFilesMatched':len(m),'preparedTestMethods_NOT_RUN':n,'SwiftOrMSLCompiledByThisCheck':False,'MacExecutedByThisCheck':False},indent=2))

assert not any('MonitorSession' in f.name or 'ProcessIO' in f.name or 'FSEvent' in f.name for f in (p/'Sources/ReadOnlyScanner').glob('*'))
assert not re.search(r'\bNSOpenPanel\s*\(',''.join(f.read_text() for f in (p/'Sources/DemoFirstScreenCore').glob('*.swift')))
app=(p/'Sources/DemoFirstScreenApp/AppDelegate.swift').read_text();live=app[app.index('func applicationDidFinishLaunching'):]
assert 'DirectoryScanner.scan' not in live and 'chooseFolder()' not in live and 'loadBundledProduction()' not in live
assert 'StartupSummaryRootView(store:store' in live and 'FolderSnapshotRootView(store:store' not in live
