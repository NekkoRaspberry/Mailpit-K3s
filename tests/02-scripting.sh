#!/usr/bin/env bash
# Do new-app-email.sh and remove-app-email.sh work, and can apps be told apart?
# Creates temporary apps and removes them at the end.
# NOTE: adding/removing an app restarts Mailpit (a few seconds each).
source "$(dirname "$0")/lib.sh"
echo "== 02 Scripting (new-app-email.sh, remove-app-email.sh)"

A=mailtesta
B=mailtestb

cleanup() {
  for APP in "$A" "$B"; do
    has_login "$APP" && "$ROOT/remove-app-email.sh" "$APP" "$TEST_NS" >/dev/null 2>&1
    kubectl delete secret -n "$TEST_NS" "$APP-email" --ignore-not-found >/dev/null 2>&1
    delete_tag "$APP"
  done
}
trap 'cleanup; client_stop' EXIT
client_start
cleanup   # start from a clean state

check_fails "rejects missing arguments" "$ROOT/new-app-email.sh"
check_fails "rejects invalid app name"  "$ROOT/new-app-email.sh" Bad-Name "$TEST_NS"
check "creates login for app A"         "$ROOT/new-app-email.sh" "$A" "$TEST_NS"
check "creates login for app B"         "$ROOT/new-app-email.sh" "$B" "$TEST_NS"
check_fails "refuses to create the same app twice" "$ROOT/new-app-email.sh" "$A" "$TEST_NS"

for KEY in host port username password from; do
  check "secret contains '$KEY'" \
    test -n "$(kubectl get secret -n "$TEST_NS" "$A-email" -o jsonpath="{.data.$KEY}")"
done
PASS_A="$(kubectl get secret -n "$TEST_NS" "$A-email" -o jsonpath='{.data.password}' | base64 -d)"
PASS_B="$(kubectl get secret -n "$TEST_NS" "$B-email" -o jsonpath='{.data.password}' | base64 -d)"

STORED="$(kubectl get secret -n "$NS" mailpit-smtp-users -o jsonpath='{.data.smtp-users}' | base64 -d)"
check_fails "Mailpit stores only a hash, not the password" contains "$STORED" "$PASS_A"

check "app A can send with its login" send_mail "$A" "$PASS_A" "hello from A"
check "app B can send with its login" send_mail "$B" "$PASS_B" "hello from B"
check "A's email is tagged A (1 email)" test "$(count_tag "$A")" = 1
check "B's email is tagged B (1 email)" test "$(count_tag "$B")" = 1

check_fails "wrong password is rejected"          send_mail "$A" wrongpassword "bad"
check_fails "app cannot use another app's login"  send_mail "$B" "$PASS_A" "bad"

check "removes app B"                          "$ROOT/remove-app-email.sh" "$B" "$TEST_NS"
check_fails "removed app can no longer send"   send_mail "$B" "$PASS_B" "after removal"
check_fails "removed app's secret is deleted"  kubectl get secret -n "$TEST_NS" "$B-email"
check "other apps keep working"                send_mail "$A" "$PASS_A" "A still works"
check "A now has 2 emails"                     test "$(count_tag "$A")" = 2
check_fails "removing an unknown app fails"    "$ROOT/remove-app-email.sh" "$B" "$TEST_NS"
check_fails "placeholder '_locked' cannot be removed" "$ROOT/remove-app-email.sh" _locked "$TEST_NS"

finish
