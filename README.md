# Mailpit-K3s

One shared Mailpit instance on K3s that catches the emails of all applications. Each application gets its own SMTP login, and its emails are tagged with its name. Nothing is delivered to real inboxes.

## Overview

| Item | Value |
|---|---|
| Namespace | `email` |
| Image | `axllent/mailpit:v1.31.6` |
| SMTP (inside the cluster) | `mailpit.email.svc.cluster.local:1025` |
| Web UI + API (inside the cluster) | `mailpit.email.svc.cluster.local:8025` |
| Exposure | ClusterIP only |
| Storage | 1 Gi, `local-path`, newest 500 emails kept |
| Memory limit | 128 Mi |
| App logins | Secret `mailpit-smtp-users` (hashed) |
| Web UI login | Secret `mailpit-ui` (user `admin`) |

## Files

| File | Purpose |
|---|---|
| `mailpit.yaml` | Namespace, service and Mailpit |
| `new-app-email.sh` | Creates an SMTP login for one app |
| `remove-app-email.sh` | Removes one app's login |
| `tests/` | Health, scripting and deploy tests |
| `ci/` | Runner access and runner set for GitHub Actions |
| `.github/workflows/tests.yml` | Runs the tests on push to `main` and `dev` |

## Install

```bash
export KUBECONFIG=~/.kube/config
kubectl create namespace email
UI_PASS="$(openssl rand -hex 16)"
kubectl create secret generic mailpit-ui -n email \
  --from-literal=username=admin --from-literal=password="$UI_PASS" \
  --from-literal=ui-users="admin:$(openssl passwd -6 -stdin <<< "$UI_PASS")"
unset UI_PASS
# "_locked" keeps SMTP login enforced while no app exists (Mailpit disables it for an empty list)
kubectl create secret generic mailpit-smtp-users -n email \
  --from-literal=smtp-users="_locked:$(openssl rand -hex 32 | openssl passwd -6 -stdin)"
kubectl apply -f mailpit.yaml
```

## Add an app

```bash
./new-app-email.sh <app-name> <app-namespace>
# example: ./new-app-email.sh nextcloud nextcloud
```

Creates a login `<app-name>` and a Secret `<app-name>-email` in the app's namespace with `host`, `port`, `username`, `password` and `from`. Mailpit restarts for a few seconds; stored emails are kept.

```yaml
env:
  - name: SMTP_HOST
    valueFrom: { secretKeyRef: { name: nextcloud-email, key: host } }
  - name: SMTP_PORT
    valueFrom: { secretKeyRef: { name: nextcloud-email, key: port } }
  - name: SMTP_USER
    valueFrom: { secretKeyRef: { name: nextcloud-email, key: username } }
  - name: SMTP_PASSWORD
    valueFrom: { secretKeyRef: { name: nextcloud-email, key: password } }
  - name: SMTP_FROM
    valueFrom: { secretKeyRef: { name: nextcloud-email, key: from } }
```
SMTP without encryption (no TLS/STARTTLS), login type PLAIN or LOGIN.

## Remove an app

```bash
./remove-app-email.sh <app-name> <app-namespace>
```

## View emails

```bash
kubectl port-forward -n email svc/mailpit 8025:8025
```
Open http://localhost:8025 (VS Code forwards the port automatically). Filter by app with the tag, e.g. `tag:nextcloud`.

Web UI password:
```bash
kubectl get secret -n email mailpit-ui -o jsonpath='{.data.password}' | base64 -d; echo
```

## Useful commands

```bash
kubectl get pods,pvc -n email                         # status
kubectl logs -n email mailpit-0 --tail=50             # logs
kubectl get secret -n email mailpit-smtp-users -o jsonpath='{.data.smtp-users}' | base64 -d | cut -d: -f1   # app logins
```

## Tests

```bash
./tests/run-all.sh               # all tests
./tests/run-all.sh --no-restart  # skip only the pod restart in 03
```

| Test | Checks |
|---|---|
| `01-running.sh` | Pod, storage, service, logins required (SMTP and web UI), version, memory |
| `02-scripting.sh` | Add/remove apps, emails tagged per app, wrong or other app's password rejected |
| `03-deploying.sh` | Manifest valid, no drift, scripts, emails and logins survive a restart |
| `99-leftovers.sh` | Nothing left behind by the tests |

Adding and removing test apps restarts Mailpit a few times (a few seconds each).

### CI (GitHub Actions)

`.github/workflows/tests.yml` runs the tests (without the restart) on every push to `main` and `dev`, on the `mailpit-runners` runner set.

```bash
kubectl apply -f ci/test-runner-permissions.yaml   # runner account, its permissions, test namespace mailtest
helm install mailpit-runners -n arc-runners -f ci/test-runner-helm-values.yaml \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --version 0.15.1
```
Needs the Secret `arc-mailpit-github-app` (GitHub App with Administration access to this repo only).

## Notes

- Only apps inside the cluster can reach Mailpit.
- Do not remove the `_locked` login.
