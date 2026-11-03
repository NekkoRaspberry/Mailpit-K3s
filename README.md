# Mailpit-K3s

One shared Mailpit instance on K3s that catches the emails of all applications. Each application gets its own SMTP login, and its emails are tagged with its name. Nothing is delivered to real inboxes.

## Overview

| Item | Value |
|---|---|
| Namespace | `email` |
| Image | `axllent/mailpit:v1.31.6` |
| SMTP (inside the cluster) | `mailpit.email.svc.cluster.local:1025` |
| Web UI + API (inside the cluster) | `mailpit.email.svc.cluster.local:8025` |
| Web UI (home network) | `https://mailpit.home.arpa` (Traefik, name from Pi-hole) |
| Exposure | Web UI on the home network over HTTPS only, SMTP inside the cluster only |
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
| `tests/` | Tests, run on the Pi |
| `.github/workflows/tests.yml` | Checks scripts and manifest on push to `main` and `dev` |

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

Open https://mailpit.home.arpa from any device at home that uses Pi-hole for DNS (install the home CA once, see Pihole-K3s). Filter by app with the tag, e.g. `tag:nextcloud`.

Web UI password:
```bash
kubectl get secret -n email mailpit-ui -o jsonpath='{.data.password}' | base64 -d; echo
```

## Useful commands

```bash
kubectl get pods,pvc -n email                         # status
kubectl logs -n email deploy/mailpit --tail=50        # logs
kubectl get secret -n email mailpit-smtp-users -o jsonpath='{.data.smtp-users}' | base64 -d | cut -d: -f1   # app logins
```

## Tests

Run on the Pi:
```bash
./tests/run-all.sh
```

| Test | Checks |
|---|---|
| `01-running.sh` | Pod, storage, service, logins required (SMTP and web UI), version, memory |
| `02-apps.sh` | Add/remove apps, emails tagged per app, wrong or other app's password rejected |
| `03-deploying.sh` | Manifest valid, no drift, emails and logins survive a restart |
| `99-leftovers.sh` | Nothing left behind by the tests |

Test apps use the temporary namespace `mailtest`, deleted at the end. Adding and removing them restarts Mailpit a few times (a few seconds each).

On push, `.github/workflows/tests.yml` checks script syntax (shellcheck) and the manifest (kubeconform) on `ubuntu-latest` (it also works on `nekko-runners`). It has no access to the cluster.

## Notes

- Only apps inside the cluster can reach Mailpit.
- Do not remove the `_locked` login.
