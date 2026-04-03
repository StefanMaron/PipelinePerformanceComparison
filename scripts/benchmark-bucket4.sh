#!/usr/bin/env bash
# benchmark-bucket4.sh — End-to-end benchmark: fresh container → publish → run full Bucket 4 tests
#
# Bucket 4 = Tests-ERM + Tests-SCM + Tests-Misc + Tests-Workflow + Tests-SCM-Service + Tests-SINGLESERVER
# This matches Microsoft's "Base Application Test - Bucket 4" pipeline (170 min on Windows).
#
# Usage: ./scripts/benchmark-bucket4.sh

set -uo pipefail

BC_LINUX_DIR="/home/stefan/Documents/Repos/community/bc-linux"
AUTH="BCRUNNER:Admin123!"
DEV_URL="http://localhost:7049"
API_PORT="http://localhost:7052/BC"
CONTAINER="bc-linux-bc-1"
# Paths inside the container (capital A in Applications)
CONTAINER_ARTIFACTS="/bc/artifacts/platform/Applications"
RESULTS_DIR="/tmp/benchmark-bucket4-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Dependency apps to publish first (container paths)
BUCKET4_DEPS=(
    "$CONTAINER_ARTIFACTS/System Application/Test/Microsoft_System Application Test Library.app"
    "$CONTAINER_ARTIFACTS/BusinessFoundation/Test/Microsoft_Business Foundation Test Libraries.app"
    "$CONTAINER_ARTIFACTS/BaseApp/Test/Microsoft_Tests-TestLibraries.app"
)

# Bucket 4 test apps: name:container_path
BUCKET4_APPS=(
    "Tests-ERM:$CONTAINER_ARTIFACTS/BaseApp/Test/Microsoft_Tests-ERM.app"
    "Tests-SCM:$CONTAINER_ARTIFACTS/BaseApp/Test/Microsoft_Tests-SCM.app"
    "Tests-Misc:$CONTAINER_ARTIFACTS/BaseApp/Test/Microsoft_Tests-Misc.app"
    "Tests-Workflow:$CONTAINER_ARTIFACTS/BaseApp/Test/Microsoft_Tests-Workflow.app"
    "Tests-SCM-Service:$CONTAINER_ARTIFACTS/BaseApp/Test/Microsoft_Tests-SCM-Service.app"
    "Tests-SINGLESERVER:$CONTAINER_ARTIFACTS/BaseApp/Test/Microsoft_Tests-SINGLESERVER.app"
)

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$RESULTS_DIR/benchmark.log"; }
elapsed_since() { echo $(( $(date +%s) - $1 )); }
py3() { env -u PYTHONHOME -u PYTHONPATH python3 "$@"; }

# Publish an app from inside the container via docker exec + curl
publish_app() {
    local container_path="$1"
    docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" --max-time 600 \
        -u "$AUTH" -X POST \
        -F "file=@${container_path};type=application/octet-stream" \
        "$DEV_URL/apps?SchemaUpdateMode=forcesync" 2>/dev/null
}

# Extract codeunit IDs from an .app file (copies from container to host for unzip)
discover_codeunits() {
    local container_path="$1"
    local tmp_app="/tmp/_benchmark_app.app"
    docker cp "${CONTAINER}:${container_path}" "$tmp_app" 2>/dev/null
    unzip -p "$tmp_app" SymbolReference.json 2>/dev/null | py3 -c "
import sys, json
raw = sys.stdin.read()
data = json.loads(raw.lstrip('\ufeff'))
ids = []
def collect(node):
    for cu in node.get('Codeunits', []):
        props = {p['Name']: p['Value'] for p in cu.get('Properties', [])}
        if props.get('Subtype') == 'Test':
            ids.append(str(cu['Id']))
    for ns in node.get('Namespaces', []):
        collect(ns)
collect(data)
print(','.join(ids))
" 2>/dev/null
    rm -f "$tmp_app"
}

BENCHMARK_START=$(date +%s)

# ============================================================
# Phase 1: Fresh container
# ============================================================
log "=== Phase 1: Starting fresh container ==="
PHASE1_START=$(date +%s)

cd "$BC_LINUX_DIR"
log "Tearing down existing container..."
docker compose down -v 2>&1 | tail -3

log "Starting fresh container (BC_CLEAR_ALL_APPS=false)..."
BC_CLEAR_ALL_APPS=false docker compose up -d 2>&1 | tail -3

# Wait for BC to be healthy
log "Waiting for BC to become healthy..."
for i in $(seq 1 120); do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "starting")
    [ "$STATUS" = "healthy" ] && break
    [ "$STATUS" = "unhealthy" ] && log "ERROR: container unhealthy" && docker compose logs bc 2>&1 | tail -20 && exit 1
    [ $((i % 12)) -eq 0 ] && log "  $((i*5))s: $STATUS"
    sleep 5
done
log "Container health: $STATUS"
[ "$STATUS" != "healthy" ] && log "ERROR: container did not become healthy" && exit 1

# Wait for BC ready marker (entrypoint publishes test framework)
log "Waiting for BC ready marker..."
for i in $(seq 1 60); do
    docker exec "$CONTAINER" test -f /tmp/bc-ready 2>/dev/null && break
    sleep 5
done

PHASE1_ELAPSED=$(elapsed_since $PHASE1_START)
log "Phase 1 complete: container startup took ${PHASE1_ELAPSED}s"
docker logs "$CONTAINER" > "$RESULTS_DIR/bc-log-after-startup.txt" 2>&1

# ============================================================
# Phase 2: Publish dependencies (from inside container)
# ============================================================
log ""
log "=== Phase 2: Publishing test dependencies ==="
PHASE2_START=$(date +%s)

for dep in "${BUCKET4_DEPS[@]}"; do
    name=$(basename "$dep" .app | sed 's/Microsoft_//')
    start=$(date +%s)
    HTTP=$(publish_app "$dep")
    elapsed=$(elapsed_since $start)
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "422" ]; then
        log "  $name: HTTP $HTTP (${elapsed}s)"
    else
        log "  $name: FAILED HTTP $HTTP (${elapsed}s)"
    fi
done

PHASE2_ELAPSED=$(elapsed_since $PHASE2_START)
log "Phase 2 complete: dependency publishing took ${PHASE2_ELAPSED}s"

# ============================================================
# Phase 3: Publish all Bucket 4 test apps (from inside container)
# ============================================================
log ""
log "=== Phase 3: Publishing Bucket 4 test apps ==="
PHASE3_START=$(date +%s)

for entry in "${BUCKET4_APPS[@]}"; do
    name="${entry%%:*}"
    path="${entry#*:}"
    start=$(date +%s)
    HTTP=$(publish_app "$path")
    elapsed=$(elapsed_since $start)
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "422" ]; then
        log "  $name: HTTP $HTTP (${elapsed}s)"
    else
        log "  $name: FAILED HTTP $HTTP (${elapsed}s)"
        # Check if BC crashed
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "dead")
        if [ "$HEALTH" != "healthy" ]; then
            log "  ERROR: BC crashed during publish of $name — aborting"
            docker logs "$CONTAINER" > "$RESULTS_DIR/bc-log-crash.txt" 2>&1
            exit 1
        fi
    fi
done

PHASE3_ELAPSED=$(elapsed_since $PHASE3_START)
log "Phase 3 complete: test app publishing took ${PHASE3_ELAPSED}s"

# ============================================================
# Phase 4: Detect company and API
# ============================================================
log ""
log "=== Phase 4: Detecting company and API ==="

COMPANIES_JSON=$(curl -sf --max-time 10 -u "$AUTH" "${API_PORT}/api/v2.0/companies" 2>/dev/null || true)
COMPANY=$(echo "$COMPANIES_JSON" | py3 -c "import sys,json; print(json.load(sys.stdin)['value'][0]['name'])" 2>/dev/null)
COMPANY_ID=$(echo "$COMPANIES_JSON" | py3 -c "import sys,json; print(json.load(sys.stdin)['value'][0]['id'])" 2>/dev/null)
API_BASE="${API_PORT}/api/custom/automation/v1.0/companies(${COMPANY_ID})"

log "Company: $COMPANY ($COMPANY_ID)"
HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -u "$AUTH" "${API_BASE}/codeunitRunRequests" 2>/dev/null)
log "TestRunner API: HTTP $HTTP"
[ "$HTTP" != "200" ] && log "ERROR: TestRunner API not available" && exit 1

# ============================================================
# Phase 5: Run each test app sequentially
# ============================================================
log ""
log "=== Phase 5: Running Bucket 4 tests ==="
PHASE5_START=$(date +%s)

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
TOTAL_METHODS=0

for entry in "${BUCKET4_APPS[@]}"; do
    name="${entry%%:*}"
    path="${entry#*:}"

    # Discover codeunits
    CU_IDS=$(discover_codeunits "$path")
    CU_COUNT=$(echo "$CU_IDS" | tr ',' '\n' | wc -l)

    log ""
    log "--- $name ($CU_COUNT codeunits) ---"
    APP_START=$(date +%s)

    # Setup suite
    SETUP_START=$(date +%s)
    CREATE_RESP=$(curl -s --max-time 30 -u "$AUTH" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"CodeunitIds\": \"$CU_IDS\"}" \
        "${API_BASE}/codeunitRunRequests" 2>/dev/null)
    REQUEST_ID=$(echo "$CREATE_RESP" | py3 -c "import sys,json; print(json.load(sys.stdin)['Id'])" 2>/dev/null || true)

    if [ -z "$REQUEST_ID" ]; then
        log "  ERROR: Failed to create run request for $name"
        log "  Response: $(echo "$CREATE_RESP" | head -c 200)"
        continue
    fi

    SETUP_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 600 -u "$AUTH" -X POST \
        "${API_BASE}/codeunitRunRequests(${REQUEST_ID})/Microsoft.NAV.setupSuite" 2>/dev/null)
    SETUP_ELAPSED=$(elapsed_since $SETUP_START)
    log "  Suite setup: HTTP $SETUP_HTTP (${SETUP_ELAPSED}s)"

    if [ "$SETUP_HTTP" != "200" ] && [ "$SETUP_HTTP" != "204" ]; then
        log "  ERROR: Suite setup failed, skipping $name"
        continue
    fi

    # Execute tests
    EXEC_START=$(date +%s)
    MAX_ITER=$(( CU_COUNT * 3 + 20 ))

    set +e  # Don't exit on test runner failure
    dotnet run --project "$BC_LINUX_DIR/tools/TestRunner" -v q -- \
        --host "localhost:7085" \
        --odata-host "localhost:7052" \
        --company "$COMPANY" \
        --user "${AUTH%%:*}" \
        --password "${AUTH#*:}" \
        --suite "DEFAULT" \
        --num-codeunits "$CU_COUNT" \
        --timeout 120 \
        --codeunit-timeout 10 \
        --max-iterations "$MAX_ITER" 2>&1 | tee "$RESULTS_DIR/${name}-results.txt"
    RUNNER_EXIT=$?
    set -o pipefail

    EXEC_ELAPSED=$(elapsed_since $EXEC_START)
    APP_ELAPSED=$(elapsed_since $APP_START)

    # Count results from runner output
    APP_PASS=$(grep -c '    PASS' "$RESULTS_DIR/${name}-results.txt" 2>/dev/null || echo 0)
    APP_FAIL=$(grep -c '    FAIL' "$RESULTS_DIR/${name}-results.txt" 2>/dev/null || echo 0)
    APP_SKIP=$(grep -c '    SKIP' "$RESULTS_DIR/${name}-results.txt" 2>/dev/null || echo 0)
    APP_TOTAL=$((APP_PASS + APP_FAIL + APP_SKIP))
    TOTAL_PASS=$((TOTAL_PASS + APP_PASS))
    TOTAL_FAIL=$((TOTAL_FAIL + APP_FAIL))
    TOTAL_SKIP=$((TOTAL_SKIP + APP_SKIP))
    TOTAL_METHODS=$((TOTAL_METHODS + APP_TOTAL))

    if [ "$RUNNER_EXIT" -ne 0 ] && [ "$APP_PASS" -eq 0 ] && [ "$APP_FAIL" -eq 0 ]; then
        log "  $name: CRASHED (exit $RUNNER_EXIT, ${APP_ELAPSED}s)"
        # Check if BC is still alive, wait for recovery
        for retry in $(seq 1 10); do
            HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 -u "$AUTH" \
                "${API_BASE}/codeunitRunRequests" 2>/dev/null || echo "000")
            [ "$HTTP" = "200" ] && break
            log "  Waiting for BC recovery ($retry/10)..."
            sleep 10
        done
    else
        log "  $name: ${APP_PASS}p/${APP_FAIL}f/${APP_SKIP}s (${APP_TOTAL} methods) — setup ${SETUP_ELAPSED}s + exec ${EXEC_ELAPSED}s = ${APP_ELAPSED}s total"
    fi
done

PHASE5_ELAPSED=$(elapsed_since $PHASE5_START)
log ""
log "Phase 5 complete: all test execution took ${PHASE5_ELAPSED}s"

# Capture final BC log
docker logs "$CONTAINER" > "$RESULTS_DIR/bc-log-final.txt" 2>&1

# ============================================================
# Phase 6: SQL-based result verification
# ============================================================
log ""
log "=== Phase 6: SQL Result Verification ==="

# Query actual method counts from SQL to verify no methods were skipped due to crashes
SQLCMD="docker exec bc-linux-sql-1 /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P Passw0rd123! -C -No -d CRONUS"
SQL_RESULTS=$($SQLCMD -h -1 -W -Q "
SET NOCOUNT ON;
SELECT
    SUM(CASE WHEN [Result]=0 THEN 1 ELSE 0 END) as not_run,
    SUM(CASE WHEN [Result]=1 THEN 1 ELSE 0 END) as failed,
    SUM(CASE WHEN [Result]=2 THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN [Result]=3 THEN 1 ELSE 0 END) as skipped,
    COUNT(*) as total
FROM [CRONUS International Ltd_\$Test Method Line\$23de40a6-dfe8-4f80-80db-d70f83ce8caf]
WHERE [Test Suite]='DEFAULT' AND [Line Type]=1
" 2>/dev/null | head -1)

SQL_NOTRUN=$(echo "$SQL_RESULTS" | awk '{print $1}')
SQL_FAILED=$(echo "$SQL_RESULTS" | awk '{print $2}')
SQL_PASSED=$(echo "$SQL_RESULTS" | awk '{print $3}')
SQL_SKIPPED=$(echo "$SQL_RESULTS" | awk '{print $4}')
SQL_TOTAL=$(echo "$SQL_RESULTS" | awk '{print $5}')

log "SQL verification (all apps combined):"
log "  Not-run: $SQL_NOTRUN  Failed: $SQL_FAILED  Passed: $SQL_PASSED  Skipped: $SQL_SKIPPED  Total: $SQL_TOTAL"
if [ "${SQL_NOTRUN:-0}" -gt 0 ]; then
    log "  WARNING: $SQL_NOTRUN methods were never executed (possible session crashes)"
fi

# Top failure reasons
log ""
log "Top 10 failure reasons:"
$SQLCMD -W -Q "
SET NOCOUNT ON;
SELECT TOP 10 LEFT([Error Message Preview], 100) as error, COUNT(*) as cnt
FROM [CRONUS International Ltd_\$Test Method Line\$23de40a6-dfe8-4f80-80db-d70f83ce8caf]
WHERE [Test Suite]='DEFAULT' AND [Line Type]=1 AND [Result]=1
GROUP BY LEFT([Error Message Preview], 100) ORDER BY cnt DESC
" 2>/dev/null | tee -a "$RESULTS_DIR/benchmark.log"

# ============================================================
# Phase 7: .NET Error Analysis
# ============================================================
log ""
log "=== Phase 7: .NET Error Analysis ==="

grep -iE "Exception|error.*dotnet|System\.\w+Exception|NullReference|InvalidOperation|TypeLoad|MissingMethod|FileNotFound.*dll|DllNotFound|EntryPointNotFound|PlatformNotSupported|NotImplemented|SIGABRT|SIGSEGV|abort|fatal" \
    "$RESULTS_DIR/bc-log-final.txt" 2>/dev/null | \
    grep -v "error AL\|ErrorMessage\|error_message\|\"error\":\|SideService\|Reporting.Service\|NoOp IReporting" | \
    sort -u > "$RESULTS_DIR/dotnet-errors.txt"

DOTNET_ERROR_COUNT=$(wc -l < "$RESULTS_DIR/dotnet-errors.txt")
log ".NET errors found: $DOTNET_ERROR_COUNT unique patterns"

# ============================================================
# Summary
# ============================================================
BENCHMARK_ELAPSED=$(elapsed_since $BENCHMARK_START)

log ""
log "============================================================"
log "=== BUCKET 4 BENCHMARK SUMMARY ==="
log "============================================================"
log ""
log "Phase 1 — Container startup:      ${PHASE1_ELAPSED}s"
log "Phase 2 — Dependency publishing:   ${PHASE2_ELAPSED}s"
log "Phase 3 — Test app publishing:     ${PHASE3_ELAPSED}s"
log "Phase 5 — Test execution:          ${PHASE5_ELAPSED}s"
log ""
log "Total wall clock:                  ${BENCHMARK_ELAPSED}s ($(( BENCHMARK_ELAPSED / 60 ))m $(( BENCHMARK_ELAPSED % 60 ))s)"
log ""
log "Test Results (runner output):"
log "  Passed:  $TOTAL_PASS"
log "  Failed:  $TOTAL_FAIL"
log "  Skipped: $TOTAL_SKIP"
log "  Total:   $TOTAL_METHODS"
log ""
log "Test Results (SQL verification):"
log "  Passed:  ${SQL_PASSED:-?}  Failed: ${SQL_FAILED:-?}  Not-run: ${SQL_NOTRUN:-?}  Total: ${SQL_TOTAL:-?}"
log ""
log "Microsoft reference: Bucket 4 = ~170 min on Windows (4 runners, AL-Go)"
log ".NET errors: $DOTNET_ERROR_COUNT unique patterns"
log ""
log "Results saved to: $RESULTS_DIR"
log "============================================================"
