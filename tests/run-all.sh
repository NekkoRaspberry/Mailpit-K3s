#!/usr/bin/env bash
# Run every test and print a summary.
# Usage: ./run-all.sh              (all tests)
#        ./run-all.sh --no-restart (skip only the pod restart in 03)
cd "$(dirname "$0")"
[[ "${1:-}" == "--no-restart" ]] && export NO_RESTART=1

FAILED=()
for TEST in [0-9][0-9]-*.sh; do
  bash "$TEST" || FAILED+=("$TEST")
  echo
done

if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "ALL TESTS PASSED"
else
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
