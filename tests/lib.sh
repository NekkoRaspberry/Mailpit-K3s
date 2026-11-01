# Shared helpers for the tests (loaded by each test file, not run directly)
# Use ~/.kube/config on the Pi; inside a pod (CI runner) kubectl uses the pod's own access
if [[ -z "${KUBECONFIG:-}" && -f "$HOME/.kube/config" ]]; then export KUBECONFIG="$HOME/.kube/config"; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS=email
TEST_NS=mailtest          # namespace for test apps (permanent, emptied after each test)
CLIENT=mailtest-client    # helper pod with curl, acts like an app
MAILPIT=mailpit.email.svc.cluster.local
FAILS=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
warn() { echo "  WARN  $1"; }

# check "<description>" <command...>  -> PASS if the command succeeds
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

# check_fails "<description>" <command...>  -> PASS if the command FAILS
check_fails() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$name"; else pass "$name"; fi
}

# Helper pod that talks to Mailpit like an app would
client_start() {
  kubectl run "$CLIENT" -n "$TEST_NS" --restart=Never --image=curlimages/curl:8.22.0 \
    --command -- sleep 600 >/dev/null
  kubectl wait -n "$TEST_NS" --for=condition=Ready "pod/$CLIENT" --timeout=90s >/dev/null
}
client_stop() { kubectl delete pod -n "$TEST_NS" "$CLIENT" --ignore-not-found --grace-period=1 >/dev/null 2>&1; }

# Send an email through Mailpit SMTP.
# Usage: send_mail <user> <password> <subject>   (empty user = no login)
send_mail() {
  local login=""
  [[ -n "$1" ]] && login="--user '$1:$2'"
  kubectl exec -n "$TEST_NS" "$CLIENT" -- sh -c "
    printf 'From: app@test.local\r\nTo: inbox@test.local\r\nSubject: $3\r\n\r\nTest email\r\n' |
    curl -sS --fail smtp://$MAILPIT:1025 --mail-from app@test.local --mail-rcpt inbox@test.local $login -T -"
}

# Call the Mailpit API with the web UI login. Usage: api <METHOD> <path>
api() {
  local pass
  pass="$(kubectl get secret -n "$NS" mailpit-ui -o jsonpath='{.data.password}' | base64 -d)"
  kubectl exec -n "$TEST_NS" "$CLIENT" -- curl -sS --fail -u "admin:$pass" -X "$1" "http://$MAILPIT:8025$2"
}

# Number of stored emails tagged with an app name
count_tag() { api GET "/api/v1/search?query=tag:$1" | grep -o '"messages_count":[0-9]*' | cut -d: -f2; }

# Delete all stored emails tagged with an app name
delete_tag() { api DELETE "/api/v1/search?query=tag:$1" >/dev/null 2>&1; }

# contains "<text>" "<part>"  -> succeeds if text contains part
contains() { grep -qF -- "$2" <<< "$1"; }

# Does Mailpit have a login for this app? (regex allowed, e.g. "mailtest[a-z]*")
has_login() {
  kubectl get secret -n "$NS" mailpit-smtp-users -o jsonpath='{.data.smtp-users}' | base64 -d | grep -q "^$1:"
}

# Print the result and exit with 0 (all good) or 1 (something failed)
finish() {
  if [[ "$FAILS" -eq 0 ]]; then echo "  -> all passed"; exit 0
  else echo "  -> $FAILS failed"; exit 1; fi
}
