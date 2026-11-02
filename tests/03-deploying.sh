#!/usr/bin/env bash
# Is the file valid, does the cluster match it, and do logins/emails survive a restart?
# Adding an app restarts Mailpit, so this must always work.
source "$(dirname "$0")/lib.sh"
echo "== 03 Deploying"

check "manifest is valid (server dry-run)" kubectl apply --dry-run=server -f "$ROOT/mailpit.yaml"
# kubectl diff returns 0 when the cluster matches the file exactly
check "cluster matches the file (no drift)" kubectl diff -f "$ROOT/mailpit.yaml"

# Send an email, restart Mailpit, check the email and the login are still there
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

echo "  ...restarting Mailpit"
kubectl rollout restart deployment/mailpit -n "$NS" >/dev/null
check "Mailpit comes back Ready after restart" \
  kubectl rollout status deployment/mailpit -n "$NS" --timeout=120s
check "emails survive a restart"  test "$(count_tag "$P")" = 1
check "logins survive a restart"  send_mail "$P" "$PASS_P" "after restart"

finish
