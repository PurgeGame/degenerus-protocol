#!/usr/bin/env bash
# Gas may select a certified checkpoint and measure miner compensation. It must
# never enter outcome derivation. Pin every reviewed read, including assembly gas().
# This is a drift gate, complemented by exact-outcome checkpoint runtime tests.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec python3 scripts/lib/check_gas_meter.py "$@"
