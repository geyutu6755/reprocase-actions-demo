#!/bin/bash
# ReproCase v0.6.0 scenario verification script.
# Usage: verify-scenario.sh <scenario> <reprocase-ref>
#
# Installs ReproCase, starts the server, runs the scan, and (optionally)
# runs the compare — ALL in the same process lifetime, so the server is
# guaranteed to be alive during the scan. This is the "same-step
# server+scan" pattern that avoids the GitHub Actions orphan process
# cleanup limitation.
set -euo pipefail

SCENARIO="$1"
REPROCASE_REF="${2:-v0.6.0}"
SITE_URL="http://127.0.0.1:4173/"
SITE_PORT=4173
SITE_DIR="site"

echo "=== Scenario: $SCENARIO (reprocase-ref: $REPROCASE_REF) ==="

# ── Install ReproCase ──────────────────────────────────────────────────────
echo "--- Installing ReproCase from $REPROCASE_REF ---"
SRC="$RUNNER_TEMP/reprocase-src"
rm -rf "$SRC"
git clone --depth 1 --branch "$REPROCASE_REF" https://github.com/geyutu6755/ReproCase.git "$SRC" 2>/dev/null \
  || { git clone https://github.com/geyutu6755/ReproCase.git "$SRC" && cd "$SRC" && git checkout "$REPROCASE_REF" && cd ..; }
cd "$SRC"
npm ci --no-fund --no-audit > /dev/null 2>&1
npm run build > /dev/null 2>&1
npm install -g --no-fund --no-audit . > /dev/null 2>&1
VERSION=$(reprocase --version)
COMMIT=$(git rev-parse HEAD)
echo "Installed ReproCase v$VERSION (commit $COMMIT)"

# ── Prepare site ──────────────────────────────────────────────────────────
cd - > /dev/null
if [ "$SCENARIO" = "gate-new-fault-fon-true" ] || [ "$SCENARIO" = "gate-new-fault-fon-false" ]; then
  cat > "$SITE_DIR/verification-fault.html" << 'PAGE'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Verification Fault</title></head>
<body><p>Verification fault page</p><img src="./missing-verification.png" alt="x" width="10" height="10">
<script>document.addEventListener("DOMContentLoaded",function(){throw new Error("VerifyBoom: scenario verification fault")});</script>
</body></html>
PAGE
  node -e 'const fs=require("fs");let t=fs.readFileSync("'"$SITE_DIR"'/index.html","utf8");t=t.replace("</main>","<p><a href=\"./verification-fault.html\">Verification fault</a></p></main>");fs.writeFileSync("'"$SITE_DIR"'/index.html",t)'
fi

# ── Start server ──────────────────────────────────────────────────────────
echo "--- Starting server on port $SITE_PORT ---"
node server.mjs "$SITE_DIR" &
SERVER_PID=$!
for i in $(seq 1 20); do
  curl -s "$SITE_URL" > /dev/null 2>&1 && break
  sleep 0.5
done
if ! curl -s "$SITE_URL" > /dev/null 2>&1; then
  echo "::error::Server did not start"
  kill $SERVER_PID 2>/dev/null
  exit 2
fi
echo "Server ready on port $SITE_PORT"

# ── Run scan ──────────────────────────────────────────────────────────────
echo "--- Running scan ---"
SCAN_EXIT=0
case "$SCENARIO" in
  scanner-error)
    # Point at a port with nothing listening
    reprocase scan --url http://127.0.0.1:59999/ --out scan-output --fail-on verified --no-traces --max-pages 10
    SCAN_EXIT=$?
    EXPECTED_EXIT=2
    ;;
  *)
    reprocase scan --url "$SITE_URL" --out scan-output --fail-on never --no-traces --max-pages 15
    SCAN_EXIT=$?
    EXPECTED_EXIT=0
    ;;
esac
echo "Scan exit: $SCAN_EXIT (expected: $EXPECTED_EXIT)"

if [ "$SCENARIO" = "scanner-error" ]; then
  if [ "$SCAN_EXIT" != "$EXPECTED_EXIT" ]; then
    echo "::error::Expected exit $EXPECTED_EXIT but got $SCAN_EXIT"
    kill $SERVER_PID 2>/dev/null
    exit 1
  fi
  echo "✅ PASS: scanner exit 2 confirmed"
  kill $SERVER_PID 2>/dev/null
  exit 0
fi

# ── Run compare (if baseline provided) ────────────────────────────────────
if [ -f "baseline/result.json" ] && [ "$SCENARIO" != "first-run" ]; then
  echo "--- Running compare ---"
  COMPARE_EXIT=0
  case "$SCENARIO" in
    gate-new-fault-fon-true)
      reprocase compare baseline/result.json scan-output/result.json --out compare-output --fail-on new
      COMPARE_EXIT=$?
      ;;
    gate-new-fault-fon-false)
      reprocase compare baseline/result.json scan-output/result.json --out compare-output
      COMPARE_EXIT=$?
      ;;
    *)
      reprocase compare baseline/result.json scan-output/result.json --out compare-output
      COMPARE_EXIT=$?
      ;;
  esac
  echo "Compare exit: $COMPARE_EXIT"
fi

# ── Assert scenario expectations ──────────────────────────────────────────
echo "--- Verifying scenario expectations ---"
case "$SCENARIO" in
  clean-scan)
    FINDINGS=$(node -e "const r=require('./scan-output/result.json');console.log(r.findings.length)")
    if [ "$FINDINGS" != "0" ]; then echo "::error::Expected 0 findings but got $FINDINGS"; exit 1; fi
    echo "✅ PASS: clean scan, 0 findings"
    ;;
  gate-no-new)
    NEW=$(node -e "const r=require('./compare-output/compare.json');console.log(r.summary.newCount)")
    if [ "$NEW" != "0" ]; then echo "::error::Expected New=0 but got $NEW"; exit 1; fi
    echo "✅ PASS: no new findings"
    ;;
  gate-new-fault-fon-true)
    NEW=$(node -e "const r=require('./compare-output/compare.json');console.log(r.summary.newCount)")
    if [ "$NEW" = "0" ]; then echo "::error::Expected new findings > 0"; exit 1; fi
    echo "✅ PASS: $NEW new finding(s), gate correctly fired (fail-on-new=true)"
    ;;
  gate-new-fault-fon-false)
    NEW=$(node -e "const r=require('./compare-output/compare.json');console.log(r.summary.newCount)")
    if [ "$NEW" = "0" ]; then echo "::error::Expected new findings > 0 in report"; exit 1; fi
    echo "✅ PASS: $NEW new finding(s) reported, gate correctly PASSED (fail-on-new=false)"
    ;;
  first-run)
    echo "✅ PASS: first run without baseline completed"
    ;;
esac

# ── Cleanup ───────────────────────────────────────────────────────────────
kill $SERVER_PID 2>/dev/null
echo "=== Scenario $SCENARIO: COMPLETE ==="
