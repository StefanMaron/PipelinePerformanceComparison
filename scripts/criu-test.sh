#!/usr/bin/env bash
# criu-test.sh — Test CRIU checkpoint/restore: full vs lean (--ignore-rootfs)
# Run with: sudo bash scripts/criu-test.sh
set -uo pipefail

# Check if checkpoint images already exist — skip Phase 1 & 2 if so
HAVE_CHECKPOINT=false
if podman image exists localhost/bc-checkpoint:latest 2>/dev/null && \
   podman image exists localhost/sql-committed:latest 2>/dev/null; then
  echo "Checkpoint images found — skipping Phase 1 & 2"
  HAVE_CHECKPOINT=true
fi

if [ "$HAVE_CHECKPOINT" = "false" ]; then

echo "=== Phase 1: Start BC+SQL in a podman pod ==="

# Clean up any previous run
podman pod rm -f bc-pod 2>/dev/null || true
podman pod rm -f bc-pod-full 2>/dev/null || true
podman pod rm -f bc-pod-lean 2>/dev/null || true

podman pod create --name bc-pod \
  -p 7048:7048 -p 7049:7049 -p 7052:7052 -p 7085:7085 -p 1433:1433

podman run -d --pod bc-pod --name sql-pm \
  -e ACCEPT_EULA=Y \
  -e "MSSQL_SA_PASSWORD=Passw0rd123!" \
  -e MSSQL_MEMORY_LIMIT_MB=2048 \
  -v /var/lib/docker/volumes/bc-linux_bc-artifacts/_data:/bc/artifacts \
  mcr.microsoft.com/mssql/server:2022-latest

echo "Waiting for SQL..."
for i in $(seq 1 24); do
  podman exec sql-pm /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "Passw0rd123!" -C -No -Q "SELECT 1" &>/dev/null \
    && echo "SQL ready after $((i*5))s" && break
  sleep 5
done

podman volume rm bc-pod-service 2>/dev/null || true
podman run -d --pod bc-pod --name bc-pm \
  -v /var/lib/docker/volumes/bc-linux_bc-artifacts/_data:/bc/artifacts \
  -v bc-pod-service:/bc/service \
  -e SQL_SERVER=localhost \
  -e SA_PASSWORD="Passw0rd123!" \
  -e BC_CLEAR_ALL_APPS=false \
  -e BC_SKIP_APP_PUBLISH=true \
  docker.io/library/bc-runner:local

echo "Waiting for BC..."
for i in $(seq 1 80); do
  HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -u admin:Admin123! \
    http://localhost:7048/BC/ODataV4/Company 2>/dev/null || echo "000")
  if [ "$HTTP" = "200" ]; then
    echo "BC healthy after $((i*5))s"
    break
  fi
  [ $((i % 6)) -eq 0 ] && echo "  $((i*5))s: HTTP $HTTP" || true
  sleep 5
done

echo ""
echo "=== Phase 2: Checkpoint BC + commit SQL ==="
curl -sf -u admin:Admin123! http://localhost:7048/BC/ODataV4/Company | head -c 200
echo ""
echo "BC is alive. Checkpointing..."

TIME_START=$(date +%s%N)
podman container checkpoint bc-pm \
  --tcp-established --file-locks \
  --create-image bc-checkpoint:latest \
  --print-stats 2>&1
TIME_END=$(date +%s%N)
echo "Checkpoint took: $(( (TIME_END - TIME_START) / 1000000 ))ms"

podman commit sql-pm sql-committed:latest 2>&1
echo "SQL committed."
echo ""
echo "Checkpoint image size: $(podman images bc-checkpoint:latest --format '{{.Size}}')"

fi  # end of HAVE_CHECKPOINT=false block

echo ""
echo "=== Checkpoint image: $(podman images bc-checkpoint:latest --format '{{.Size}}') ==="
echo ""

# ============================================================
# Test A: Restore FULL (normal, no --ignore-rootfs)
# ============================================================
echo "=== Test A: FULL restore ==="
podman pod rm -f bc-pod 2>/dev/null || true
podman pod rm -f bc-pod-full 2>/dev/null || true
podman volume rm bc-pod-service 2>/dev/null || true

podman pod create --name bc-pod-full \
  -p 7048:7048 -p 7049:7049 -p 7052:7052 -p 7085:7085 -p 1433:1433

podman run -d --pod bc-pod-full --name sql-full \
  -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=Passw0rd123!" \
  sql-committed:latest
for i in $(seq 1 12); do
  podman exec sql-full /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "Passw0rd123!" -C -No -Q "SELECT 1" &>/dev/null \
    && echo "SQL ready after $((i*3))s" && break
  sleep 3
done

echo "Restoring BC (FULL)..."
TIME_START=$(date +%s%N)
podman container restore \
  --pod bc-pod-full \
  --tcp-established --file-locks \
  --print-stats \
  localhost/bc-checkpoint:latest 2>&1
FULL_EXIT=$?
TIME_END=$(date +%s%N)
FULL_MS=$(( (TIME_END - TIME_START) / 1000000 ))

FULL_HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -u admin:Admin123! \
  http://localhost:7048/BC/ODataV4/Company 2>/dev/null || echo "000")
echo "FULL: exit=$FULL_EXIT, restore=${FULL_MS}ms, HTTP=$FULL_HTTP"

# Tear down
podman pod rm -f bc-pod-full 2>/dev/null || true
podman volume rm bc-pod-service 2>/dev/null || true

# ============================================================
# Test B: Restore LEAN (--ignore-rootfs on restore side)
# ============================================================
echo ""
echo "=== Test B: LEAN restore (--ignore-rootfs) ==="

podman pod create --name bc-pod-lean \
  -p 7048:7048 -p 7049:7049 -p 7052:7052 -p 7085:7085 -p 1433:1433

podman run -d --pod bc-pod-lean --name sql-lean \
  -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=Passw0rd123!" \
  sql-committed:latest
for i in $(seq 1 12); do
  podman exec sql-lean /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "Passw0rd123!" -C -No -Q "SELECT 1" &>/dev/null \
    && echo "SQL ready after $((i*3))s" && break
  sleep 3
done

echo "Restoring BC (LEAN — --ignore-rootfs)..."
TIME_START=$(date +%s%N)
podman container restore \
  --pod bc-pod-lean \
  --tcp-established --file-locks \
  --ignore-rootfs \
  --print-stats \
  localhost/bc-checkpoint:latest 2>&1
LEAN_EXIT=$?
TIME_END=$(date +%s%N)
LEAN_MS=$(( (TIME_END - TIME_START) / 1000000 ))

LEAN_HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -u admin:Admin123! \
  http://localhost:7048/BC/ODataV4/Company 2>/dev/null || echo "000")
echo "LEAN: exit=$LEAN_EXIT, restore=${LEAN_MS}ms, HTTP=$LEAN_HTTP"

if [ "$LEAN_HTTP" != "200" ]; then
  echo "Waiting for BC to recover..."
  for i in $(seq 1 15); do
    LEAN_HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -u admin:Admin123! \
      http://localhost:7048/BC/ODataV4/Company 2>/dev/null || echo "000")
    [ "$LEAN_HTTP" = "200" ] && echo "BC responded after $((i*2))s" && break
    sleep 2
  done
fi

# ============================================================
# Results
# ============================================================
echo ""
echo "========================================="
echo "  RESULTS"
echo "========================================="
echo "  Checkpoint image: $(podman images bc-checkpoint:latest --format '{{.Size}}')"
echo ""
echo "  FULL restore: ${FULL_MS}ms → HTTP $FULL_HTTP"
echo "  LEAN restore: ${LEAN_MS}ms → HTTP $LEAN_HTTP"
echo ""
if [ "$LEAN_HTTP" = "200" ]; then
  echo "  --ignore-rootfs WORKS on restore!"
  echo "  This means we can push a smaller image"
  echo "  (checkpoint without rootfs) to cut transfer time."
else
  echo "  --ignore-rootfs FAILED on restore."
  echo "  Full checkpoint image ($(podman images bc-checkpoint:latest --format '{{.Size}}')) required."
fi
echo "========================================="

echo ""
echo "=== Cleanup ==="
podman pod rm -f bc-pod-full 2>/dev/null || true
podman pod rm -f bc-pod-lean 2>/dev/null || true
podman pod rm -f bc-pod 2>/dev/null || true
podman volume rm bc-pod-service 2>/dev/null || true
podman rmi bc-checkpoint:latest sql-committed:latest 2>/dev/null || true
echo "Done."
