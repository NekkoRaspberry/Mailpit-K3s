#!/usr/bin/env bash
# Did the tests clean up after themselves? (run last)
source "$(dirname "$0")/lib.sh"
echo "== 99 Leftovers"

check_fails "no test logins left" has_login "mailtest[a-z0-9]*"
check "no test app secrets left" \
  test -z "$(kubectl get secrets -n "$TEST_NS" -o name 2>/dev/null)"

trap client_stop EXIT
client_start
for APP in mailtesta mailtestb mailtestp; do
  check "no test emails left ($APP)" test "$(count_tag "$APP")" = 0
done

finish
