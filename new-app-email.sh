#!/usr/bin/env bash
# Create an SMTP login for one app, and save it as a Secret named "<app>-email"
# in the app's namespace. Emails sent with this login are tagged "<app>" in Mailpit.
# Usage: ./new-app-email.sh <app-name> <app-namespace>
set -euo pipefail
# Use ~/.kube/config on the Pi; inside a pod (CI runner) kubectl uses the pod's own access
if [[ -z "${KUBECONFIG:-}" && -f "$HOME/.kube/config" ]]; then export KUBECONFIG="$HOME/.kube/config"; fi

APP="${1:-}"
NS="${2:-}"
if [[ -z "$APP" || -z "$NS" ]]; then
  echo "Usage: $0 <app-name> <app-namespace>"
  exit 1
fi
# Lowercase letters and digits only (same rule as Postgres-K3s)
if [[ ! "$APP" =~ ^[a-z][a-z0-9]*$ ]]; then
  echo "App name must be lowercase letters and digits, starting with a letter."
  exit 1
fi

# Current logins, one "user:hash" per line
USERS="$(kubectl get secret -n email mailpit-smtp-users -o jsonpath='{.data.smtp-users}' | base64 -d)"

# Stop before changing anything if the app already exists
if grep -q "^$APP:" <<< "$USERS"; then
  echo "App '$APP' already has a login."
  exit 1
fi
if kubectl get secret -n "$NS" "$APP-email" >/dev/null 2>&1; then
  echo "Secret '$APP-email' already exists in namespace '$NS'."
  exit 1
fi

# Random password, never printed. Mailpit only stores its hash.
PASS="$(openssl rand -hex 24)"
HASH="$(openssl passwd -6 -stdin <<< "$PASS")"

# 1. Save the connection details where the app can read them
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl create secret generic "$APP-email" -n "$NS" \
  --from-literal=host=mailpit.email.svc.cluster.local \
  --from-literal=port=1025 \
  --from-literal=username="$APP" \
  --from-literal=password="$PASS" \
  --from-literal=from="$APP@nekkoraspberry.local" >/dev/null

# 2. Add the login to Mailpit and restart it to load the change (a few seconds)
NEW_USERS="$(printf '%s\n%s:%s\n' "$USERS" "$APP" "$HASH" | sed '/^$/d')"
kubectl patch secret -n email mailpit-smtp-users --type merge \
  -p "{\"data\":{\"smtp-users\":\"$(printf '%s\n' "$NEW_USERS" | base64 -w0)\"}}" >/dev/null
kubectl rollout restart statefulset/mailpit -n email >/dev/null
kubectl rollout status statefulset/mailpit -n email --timeout=120s >/dev/null

echo "Done: SMTP login '$APP', credentials in Secret '$APP-email' (namespace '$NS')."
