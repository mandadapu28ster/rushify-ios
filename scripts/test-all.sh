#!/bin/bash
# Fast full test run: build once, unit tests, then UI tests in parallel on cloned simulators.
# Usage: scripts/test-all.sh [simulator-udid] [workers]
set -u
cd "$(dirname "$0")/.."
SIM="${1:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)}"
WORKERS="${2:-4}"
DEST="platform=iOS Simulator,id=$SIM"
T0=$(date +%s)
summ(){ python3 - "$1" <<'PY'
import json,subprocess,sys
out=subprocess.run(["xcrun","xcresulttool","get","test-results","summary","--path",sys.argv[1]],capture_output=True,text=True).stdout
d=json.loads(out); print({k:d[k] for k in ('result','totalTestCount','passedTests','failedTests','skippedTests') if k in d})
for f in d.get('testFailures',[])[:30]: print(' FAIL:',f.get('testName'),'|',(f.get('failureText') or '')[:200].replace('\n',' '))
PY
}
rm -rf build/results; mkdir -p build/results
echo "== BUILD"; xcodebuild build-for-testing -project Rushify.xcodeproj -scheme Rushify -destination "$DEST" -derivedDataPath build -quiet > build/results/build.log 2>&1 || { tail -20 build/results/build.log; exit 1; }
echo "== UNIT";  xcodebuild test-without-building -project Rushify.xcodeproj -scheme Rushify -destination "$DEST" -derivedDataPath build -only-testing:RushifyTests -resultBundlePath build/results/unit.xcresult -quiet > build/results/unit.log 2>&1; summ build/results/unit.xcresult
echo "== UI ($WORKERS parallel simulators)"
xcodebuild test-without-building -project Rushify.xcodeproj -scheme Rushify -destination "$DEST" -derivedDataPath build -only-testing:RushifyUITests -parallel-testing-enabled YES -parallel-testing-worker-count "$WORKERS" -resultBundlePath build/results/ui.xcresult -quiet > build/results/ui.log 2>&1; summ build/results/ui.xcresult
echo "== DONE in $(( $(date +%s) - T0 ))s"
