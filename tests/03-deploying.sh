#!/usr/bin/env bash
# Are the files valid, does the cluster match them, and do emails/logins survive a restart?
# With NO_RESTART=1 (run-all.sh --no-restart) only the restart part is skipped.
source "$(dirname "$0")/lib.sh"
echo "== 03 Deploying"

check "manifest is valid (server dry-run)" kubectl apply --dry-run=server -f "$ROOT/mailpit.yaml"
# kubectl diff returns 0 when the cluster matches the file exactly
check "cluster matches the file (no drift)" kubectl diff -f "$ROOT/mailpit.yaml"
for SCRIPT in "$ROOT"/*.sh; do
  check "script syntax OK: ${SCRIPT#$ROOT/}" bash -n "$SCRIPT"
done

if [[ "${NO_RESTART:-}" == 1 ]]; then
  echo "  (restart test skipped)"
  finish
fi

# Persistence: send an email, restart Mailpit, check email and login are still there
P=mailtestp
cleanup() {
  has_login "$P" && "$ROOT/remove-app-email.sh" "$P" "$TEST_NS" >/dev/null 2>&1
  kubectl delete secret -n "$TEST_NS" "$P-email" --ignore-not-found >/dev/null 2>&1
  delete_tag "$P"
}
trap 'cleanup; client_stop' EXIT
client_start
cleanup

"$ROOT/new-app-email.sh" "$P" "$TEST_NS" >/dev/null
PASS_P="$(kubectl get secret -n "$TEST_NS" "$P-email" -o jsonpath='{.data.password}' | base64 -d)"
send_mail "$P" "$PASS_P" "before restart" >/dev/null

echo "  ...restarting mailpit-0"
kubectl delete pod -n "$NS" mailpit-0 >/dev/null
check "pod comes back Ready after restart" \
  kubectl wait -n "$NS" --for=condition=Ready pod/mailpit-0 --timeout=120s
check "emails survive a restart"  test "$(count_tag "$P")" = 1
check "logins survive a restart"  send_mail "$P" "$PASS_P" "after restart"

finish
