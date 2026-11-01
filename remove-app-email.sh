#!/usr/bin/env bash
# Remove one app's SMTP login (it can no longer send) and its "<app>-email" Secret.
# Emails it already sent stay in Mailpit.
# Usage: ./remove-app-email.sh <app-name> <app-namespace>
set -euo pipefail
# Use ~/.kube/config on the Pi; inside a pod (CI runner) kubectl uses the pod's own access
if [[ -z "${KUBECONFIG:-}" && -f "$HOME/.kube/config" ]]; then export KUBECONFIG="$HOME/.kube/config"; fi

APP="${1:-}"
NS="${2:-}"
if [[ -z "$APP" || -z "$NS" ]]; then
  echo "Usage: $0 <app-name> <app-namespace>"
  exit 1
fi
# Same rule as new-app-email.sh (also protects the "_locked" placeholder login)
if [[ ! "$APP" =~ ^[a-z][a-z0-9]*$ ]]; then
  echo "App name must be lowercase letters and digits, starting with a letter."
  exit 1
fi

USERS="$(kubectl get secret -n email mailpit-smtp-users -o jsonpath='{.data.smtp-users}' | base64 -d)"
if ! grep -q "^$APP:" <<< "$USERS"; then
  echo "App '$APP' has no login."
  exit 1
fi

# Remove the login from Mailpit and restart it to load the change
NEW_USERS="$(grep -v "^$APP:" <<< "$USERS" || true)"
kubectl patch secret -n email mailpit-smtp-users --type merge \
  -p "{\"data\":{\"smtp-users\":\"$(printf '%s\n' "$NEW_USERS" | sed '/^$/d' | base64 -w0)\"}}" >/dev/null
kubectl rollout restart statefulset/mailpit -n email >/dev/null
kubectl rollout status statefulset/mailpit -n email --timeout=120s >/dev/null

kubectl delete secret -n "$NS" "$APP-email" --ignore-not-found >/dev/null

echo "Done: login '$APP' removed. Its old emails stay in Mailpit (tag '$APP')."
