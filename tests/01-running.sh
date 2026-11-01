#!/usr/bin/env bash
# Is Mailpit running, protected and healthy? (changes nothing)
source "$(dirname "$0")/lib.sh"
echo "== 01 Running"

trap client_stop EXIT
client_start

check "pod mailpit-0 is Ready" \
  kubectl wait -n "$NS" --for=condition=Ready pod/mailpit-0 --timeout=10s
check "storage (PVC) is Bound" \
  test "$(kubectl get pvc -n "$NS" data-mailpit-0 -o jsonpath='{.status.phase}')" = Bound
check "service has an endpoint" \
  test -n "$(kubectl get endpointslice -n "$NS" -l kubernetes.io/service-name=mailpit -o jsonpath='{.items[*].endpoints[*].addresses[*]}')"
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

# Restarts are not always errors (e.g. after a reboot or adding an app), so only warn
RESTARTS="$(kubectl get pod -n "$NS" mailpit-0 -o jsonpath='{.status.containerStatuses[0].restartCount}')"
if [[ "$RESTARTS" -eq 0 ]]; then pass "no container restarts"; else warn "container restarted $RESTARTS time(s): check 'kubectl logs -n $NS mailpit-0 --previous'"; fi

# Memory: below 80% of the 128Mi limit
MEM="$(kubectl top pod -n "$NS" mailpit-0 --no-headers 2>/dev/null | awk '{print $3}' | tr -d 'Mi')"
if [[ -z "$MEM" ]]; then warn "memory usage unknown (metrics not ready yet)"
elif [[ "$MEM" -lt 102 ]]; then pass "memory usage ${MEM}Mi (< 80% of limit)"
else fail "memory usage ${MEM}Mi (>= 80% of 128Mi limit)"; fi

finish
