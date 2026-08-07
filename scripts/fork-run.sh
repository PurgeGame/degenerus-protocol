#!/usr/bin/env bash
# Mainnet-fork deploy rehearsal.
#
# Runs the REAL production deploy script (scripts/deploy.js) against an anvil
# fork of Ethereum mainnet, then scripts/fork-probe.js asserts the external
# integrations that mock-based runs structurally cannot cover: Chainlink VRF
# V2.5, the 300k callback budget, Lido, and ENS.
#
# This is the one test that exercises the production deploy path end to end.
# A wrong-version VRF coordinator reverts DegenerusAdmin's constructor at
# contract #24 of 28 — here that costs nothing instead of 23 mainnet deploys.
#
# Required env (put them in .env):
#   MAINNET_FORK_URL        archive-capable RPC to fork from
#   VRF_COORDINATOR         REAL Chainlink VRF *V2.5* coordinator (NOT the V2 one)
#   VRF_KEY_HASH            a V2.5 gas lane for that coordinator
#   STETH_TOKEN             0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
#   LINK_TOKEN              0x514910771AF9Ca656af840dff83E8264EcF986CA
# Optional:
#   ENS_REVERSE_REGISTRAR   set it to exercise the one-shot constructor setName
#   FORK_BLOCK              pin a block for reproducibility
#
# Usage: ./scripts/fork-run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ANVIL_PORT="${ANVIL_PORT:-8545}"
ANVIL_PID=""
CA="contracts/ContractAddresses.sol"
CA_BACKUP="$(mktemp)"

cleanup() {
  # Stop anvil by recorded PID only. Never pkill by pattern — the pattern
  # self-matches this script.
  if [ -n "$ANVIL_PID" ] && kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
  # deploy.js patches ContractAddresses.sol in place by design. Restore the
  # EXACT bytes we started with rather than `git checkout` — the file may have
  # been legitimately dirty before this run.
  if [ -s "$CA_BACKUP" ]; then
    cp "$CA_BACKUP" "$CA"
    echo "Restored $CA to its pre-run contents."
  fi
  rm -f "$CA_BACKUP"
}
trap cleanup EXIT

# ── Preflight ────────────────────────────────────────────────────────────────
if [ -f .env ]; then set -a; . ./.env; set +a; fi

missing=0
for v in MAINNET_FORK_URL VRF_COORDINATOR VRF_KEY_HASH STETH_TOKEN LINK_TOKEN; do
  if [ -z "${!v:-}" ]; then echo "ERROR: $v is not set"; missing=1; fi
done
[ "$missing" -eq 0 ] || { echo "Set them in .env — see .env.example."; exit 1; }

# The single most expensive mistake this harness exists to catch early.
if [ "${VRF_COORDINATOR,,}" = "0x271682deb8c4e0901d1a1550ad2e64d568e69909" ]; then
  cat >&2 <<'EOF'
ERROR: VRF_COORDINATOR is the Chainlink VRF **V2** mainnet coordinator.

contracts/interfaces/IVRFCoordinator.sol targets V2.5 Plus (RandomWordsRequest
with extraArgs). V2's addConsumer takes uint64, V2.5's takes uint256 — different
selector — so DegenerusAdmin's constructor reverts at contract #24 of 28.

Use the V2.5 coordinator: https://docs.chain.link/vrf/v2-5/supported-networks
EOF
  exit 1
fi

command -v anvil >/dev/null || { echo "ERROR: anvil not found (foundryup)"; exit 1; }

# hardhat.config.js pins the `localhost` network to 127.0.0.1:8545. Moving anvil
# without moving that would silently deploy to whatever is on 8545 instead.
if [ "$ANVIL_PORT" != "8545" ]; then
  echo "ERROR: ANVIL_PORT=$ANVIL_PORT but hardhat.config.js hardcodes the" >&2
  echo "       localhost network to 127.0.0.1:8545. Change both or neither." >&2
  exit 1
fi

# Refuse to run against a node that is already up — otherwise the 'wait for
# anvil' loop succeeds instantly against the wrong chain and the deploy lands
# somewhere unintended.
if curl -s -X POST "http://127.0.0.1:$ANVIL_PORT" \
     -H 'Content-Type: application/json' \
     --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     >/dev/null 2>&1; then
  echo "ERROR: something is already listening on 127.0.0.1:$ANVIL_PORT." >&2
  echo "       Stop it first — this harness must own the fork." >&2
  exit 1
fi

cp "$CA" "$CA_BACKUP"

# ── Fork ─────────────────────────────────────────────────────────────────────
echo "Starting anvil fork on port $ANVIL_PORT..."
ANVIL_ARGS=(--fork-url "$MAINNET_FORK_URL" --port "$ANVIL_PORT" --silent
            --accounts 10 --balance 100000)
[ -n "${FORK_BLOCK:-}" ] && ANVIL_ARGS+=(--fork-block-number "$FORK_BLOCK")

anvil "${ANVIL_ARGS[@]}" &
ANVIL_PID=$!

for i in $(seq 1 60); do
  if curl -s -X POST "http://127.0.0.1:$ANVIL_PORT" \
       -H 'Content-Type: application/json' \
       --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
       >/dev/null 2>&1; then break; fi
  kill -0 "$ANVIL_PID" 2>/dev/null || { echo "ERROR: anvil died on startup"; exit 1; }
  sleep 1
  [ "$i" -eq 60 ] && { echo "ERROR: anvil did not come up in 60s"; exit 1; }
done
echo "anvil up (pid $ANVIL_PID), forked from $MAINNET_FORK_URL"
echo ""

# ── Deploy (the real production script, verbatim) ─────────────────────────────
echo "=== Running the PRODUCTION deploy script against the fork ==="
npx hardhat run scripts/deploy.js --network localhost

echo ""
echo "=== Probing the external integrations ==="
npx hardhat run scripts/fork-probe.js --network localhost
