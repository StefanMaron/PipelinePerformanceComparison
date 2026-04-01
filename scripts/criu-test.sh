#!/usr/bin/env bash
# criu-test.sh — Test CRIU checkpoint/restore with BC+SQL in a podman pod
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
podman pod rm -f bc-pod-restored 2>/dev/null || true

# Create a pod (shared network namespace)
podman pod create --name bc-pod \
  -p 7048:7048 -p 7049:7049 -p 7052:7052 -p 7085:7085 -p 1433:1433

# Start SQL
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

# Start BC (SQL reachable at localhost since they share the pod network)
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
echo "BC is alive."

# Checkpoint BC (CRIU — freezes running process)
echo "Checkpointing BC..."
TIME_START=$(date +%s%N)
podman container checkpoint bc-pm \
  --tcp-established --file-locks \
  --create-image bc-checkpoint:latest \
  --print-stats 2>&1
BC_CP_EXIT=$?
TIME_END=$(date +%s%N)
echo "BC checkpoint exit: $BC_CP_EXIT, took: $(( (TIME_END - TIME_START) / 1000000 ))ms"

# Commit SQL (CRIU doesn't work with SQL Server — fsnotify issue)
echo "Committing SQL..."
podman commit sql-pm sql-committed:latest 2>&1
echo "SQL committed."

echo ""
podman images | grep -E "checkpoint|committed"
echo ""

fi  # end of HAVE_CHECKPOINT=false block

echo "=== Phase 3: Destroy and restore ==="
podman pod rm -f bc-pod 2>/dev/null || true
podman pod rm -f bc-pod-restored 2>/dev/null || true
podman volume rm bc-pod-service 2>/dev/null || true
echo "Pod destroyed. Restoring..."

# Create a new pod with the same ports
podman pod create --name bc-pod-restored \
  -p 7048:7048 -p 7049:7049 -p 7052:7052 -p 7085:7085 -p 1433:1433

# Start SQL from committed image (normal start, ~10-20s)
echo "Starting SQL from committed image..."
TIME_START=$(date +%s%N)
podman run -d --pod bc-pod-restored --name sql-restored \
  -e ACCEPT_EULA=Y \
  -e "MSSQL_SA_PASSWORD=Passw0rd123!" \
  sql-committed:latest
TIME_END=$(date +%s%N)
echo "SQL container started in $(( (TIME_END - TIME_START) / 1000000 ))ms"

# Wait for SQL to be ready
echo "Waiting for SQL..."
for i in $(seq 1 12); do
  podman exec sql-restored /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "Passw0rd123!" -C -No -Q "SELECT 1" &>/dev/null \
    && echo "SQL ready after $((i*3))s" && break
  sleep 3
done

# Restore BC from CRIU checkpoint (the magic moment!)
echo ""
echo "Restoring BC from CRIU checkpoint..."
TIME_START=$(date +%s%N)
podman container restore \
  --pod bc-pod-restored \
  --tcp-established --file-locks \
  --print-stats \
  localhost/bc-checkpoint:latest 2>&1
BC_RESTORE_EXIT=$?
TIME_END=$(date +%s%N)
RESTORE_MS=$(( (TIME_END - TIME_START) / 1000000 ))
echo "BC restore exit: $BC_RESTORE_EXIT, took: ${RESTORE_MS}ms"

# Test if BC responds immediately
echo ""
echo "=== Phase 4: Verify BC responds ==="
HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -u admin:Admin123! \
  http://localhost:7048/BC/ODataV4/Company 2>/dev/null || echo "000")
echo "OData response: HTTP $HTTP"

if [ "$HTTP" = "200" ]; then
  echo ""
  echo "========================================="
  echo "  CRIU CHECKPOINT/RESTORE WORKS!"
  echo "  BC restore time: ${RESTORE_MS}ms"
  echo "========================================="
else
  echo "BC not responding immediately. Waiting..."
  for i in $(seq 1 24); do
    HTTP=$(curl -sf -o /dev/null -w "%{http_code}" -u admin:Admin123! \
      http://localhost:7048/BC/ODataV4/Company 2>/dev/null || echo "000")
    if [ "$HTTP" = "200" ]; then
      echo "BC responded after $((i*2))s (restore + TCP recovery)"
      echo ""
      echo "========================================="
      echo "  CRIU WORKS (with $((i*2))s TCP recovery)"
      echo "  BC restore time: ${RESTORE_MS}ms"
      echo "========================================="
      break
    fi
    sleep 2
  done
fi

echo ""
echo "=== Cleanup ==="
podman pod rm -f bc-pod-restored 2>/dev/null || true
podman pod rm -f bc-pod 2>/dev/null || true
podman volume rm bc-pod-service 2>/dev/null || true
podman rmi bc-checkpoint:latest sql-committed:latest 2>/dev/null || true
echo "Done."
