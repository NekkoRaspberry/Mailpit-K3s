#!/usr/bin/env bash
# Is Mailpit running, protected and healthy? (changes nothing)
source "$(dirname "$0")/lib.sh"
echo "== 01 Running"

trap client_stop EXIT
client_start
POD="$(mailpit_pod)"

check "Mailpit pod is Ready" \
  kubectl wait -n "$NS" --for=condition=Ready "pod/$POD" --timeout=10s
check "storage (PVC) is Bound" \
  test "$(kubectl get pvc -n "$NS" mailpit-data -o jsonpath='{.status.phase}')" = Bound
check "service is internal only (ClusterIP)" \
  test "$(kubectl get svc -n "$NS" mailpit -o jsonpath='{.spec.type}')" = ClusterIP
check "login secrets exist" \
  kubectl get secret -n "$NS" mailpit-smtp-users mailpit-ui

check "web UI/API refuses access without login" \
  test "$(kubectl exec -n "$TEST_NS" "$CLIENT" -- curl -s -o /dev/null -w '%{http_code}' "http://$MAILPIT:8025/api/v1/info")" = 401
check "web UI/API works with login" api GET /api/v1/info
check "Mailpit version is v1.31.6" contains "$(api GET /api/v1/info)" '"Version":"v1.31.6"'

# Mailpit turns SMTP login off when the login list is empty; "_locked" prevents that
check "placeholder login '_locked' exists" has_login _locked
check_fails "SMTP refuses email without login" send_mail "" "" "no login"

# Memory: below 80% of the 128Mi limit
MEM="$(kubectl top pod -n "$NS" "$POD" --no-headers 2>/dev/null | awk '{print $3}' | tr -d 'Mi')"
if [[ -z "$MEM" ]]; then warn "memory usage unknown (metrics not ready yet)"
elif [[ "$MEM" -lt 102 ]]; then pass "memory usage ${MEM}Mi (< 80% of limit)"
else fail "memory usage ${MEM}Mi (>= 80% of 128Mi limit)"; fi

finish
