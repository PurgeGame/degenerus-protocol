#!/usr/bin/env bash
# Raw selector & hand-rolled calldata check — see Phase 221 plan.
# Task 1 installs this skeleton; Task 2 replaces the body with real scanning.
set -euo pipefail
cd "$(dirname "$0")/.."
CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
printf "Raw selector & calldata check\n"
printf "=============================\n"
printf "scanning: %s\n" "$CONTRACTS_DIR"
printf "\n(skeleton — full scan installed by Task 2)\n"
exit 0
