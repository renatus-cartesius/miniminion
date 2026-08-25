#!/bin/bash
set -euo pipefail

PASS=0
FAIL=0
CONTROLLER_PORT=9091
CTRL_PID=""
ETCD_CID=""

cleanup() {
  set +e
  [ -n "$CTRL_PID" ] && kill "$CTRL_PID" 2>/dev/null
  [ -n "$ETCD_CID" ] && docker rm -f "$ETCD_CID" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== Starting etcd ==="
ETCD_CID=$(docker run -d --rm -p 2379:2379 gcr.io/etcd-development/etcd:v3.5.17 etcd \
  --name etcd0 \
  --advertise-client-urls http://0.0.0.0:2379 \
  --listen-client-urls http://0.0.0.0:2379 \
  --initial-advertise-peer-urls http://0.0.0.0:2380 \
  --listen-peer-urls http://0.0.0.0:2380 \
  --initial-cluster etcd0=http://0.0.0.0:2380 \
  --initial-cluster-token tkn \
  --initial-cluster-state new)
sleep 3

# Verify etcd is up
curl -sf http://127.0.0.1:2379/version > /dev/null 2>&1 || { echo "etcd not ready"; exit 1; }
echo "etcd ready"

echo "=== Starting controller ==="
./zig-out/bin/minim-controller test/stack.jsonnet $CONTROLLER_PORT 127.0.0.1 2379 &
CTRL_PID=$!
sleep 2
echo "controller ready"

echo ""
echo "=== Test 1: Agent with no deps gets manifest ==="
if curl -s --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest?hostname=master-01" | grep -q 'dummy'; then
  pass "master-01 received state manifest"
else
  fail "master-01: state manifest missing 'dummy' resource"
fi

echo ""
echo "=== Test 2: Agent with unmet deps gets 202 ==="
BODY=$(curl -s --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest?hostname=worker-01")
if echo "$BODY" | grep -q '"retry_after"'; then
  pass "worker-01 received 202 with retry_after"
else
  fail "worker-01: expected 202, got: $BODY"
fi

echo ""
echo "=== Test 3: 202 includes waiting_for ==="
BODY=$(curl -s --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest?hostname=worker-01")
if echo "$BODY" | grep -q '"waiting_for"'; then
  pass "worker-01 response includes waiting_for"
else
  fail "worker-01: expected waiting_for, got: $BODY"
fi

echo ""
echo "=== Test 4: Report status success ==="
BODY=$(curl -s --max-time 3 -X POST -d '{"hostname":"master-01","status":"success"}' "http://127.0.0.1:$CONTROLLER_PORT/status")
if echo "$BODY" | grep -q '"ok"'; then
  pass "status report for master-01 accepted"
else
  fail "status report: expected ok, got: $BODY"
fi

echo ""
echo "=== Test 5: Worker still waits after partial deps ==="
BODY=$(curl -s --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest?hostname=worker-01")
if echo "$BODY" | grep -q '"master-02"'; then
  pass "worker-01 still waiting for master-02"
else
  fail "worker-01: expected waiting_for master-02, got: $BODY"
fi

echo ""
echo "=== Test 6: Complete all masters -> worker gets manifest ==="
curl -s --max-time 3 -X POST -d '{"hostname":"master-02","status":"success"}' "http://127.0.0.1:$CONTROLLER_PORT/status" > /dev/null
BODY=$(curl -s --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest?hostname=worker-01")
if echo "$BODY" | grep -q 'dummy'; then
  pass "worker-01 received manifest after all deps met"
else
  fail "worker-01: expected manifest after deps, got: $(echo "$BODY" | head -c 200)"
fi

echo ""
echo "=== Test 7: Report status failed ==="
BODY=$(curl -s --max-time 3 -X POST -d '{"hostname":"worker-01","status":"failed"}' "http://127.0.0.1:$CONTROLLER_PORT/status")
if echo "$BODY" | grep -q '"ok"'; then
  pass "failed status report accepted"
else
  fail "failed status: expected ok, got: $BODY"
fi

echo ""
echo "=== Test 8: Unknown hostname returns 404 ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest?hostname=nonexistent")
[ "$HTTP_CODE" = "404" ] && pass "unknown hostname returns 404" || fail "expected 404, got $HTTP_CODE"

echo ""
echo "=== Test 9: Missing hostname returns 400 ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest")
[ "$HTTP_CODE" = "400" ] && pass "missing hostname returns 400" || fail "expected 400, got $HTTP_CODE"

echo ""
echo "=== Test 10: Independent agents not blocked by failed sibling ==="
curl -s --max-time 3 -X POST -d '{"hostname":"master-01","status":"success"}' "http://127.0.0.1:$CONTROLLER_PORT/status" > /dev/null
curl -s --max-time 3 -X POST -d '{"hostname":"master-02","status":"success"}' "http://127.0.0.1:$CONTROLLER_PORT/status" > /dev/null
BODY=$(curl -s --max-time 3 "http://127.0.0.1:$CONTROLLER_PORT/manifest?hostname=worker-02")
if echo "$BODY" | grep -q 'dummy'; then
  pass "worker-02 gets manifest independently of worker-01 failure"
else
  fail "worker-02: expected manifest, got: $(echo "$BODY" | head -c 200)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1