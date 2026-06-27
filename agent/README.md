# Degenerus adversarial agent — a connect-and-play external attacker

A live, off-chain **external attacker** (ethers v6) that connects to an
already-running Degenerus testnet and plays adversarially 24/7: it holds its own
funded wallets and continuously tries to **(a) brick / corrupt the protocol** or
**(b) extract more value than the rules allow**, *attempting* the exploits it
hypothesizes — alongside the honest actors already on the chain.

It is **only a client**. It does **not** run the game: no deploy, no clock
control, no VRF, no stETH, no honest-actor puppetry. On the real testnet the
environment (the 15-min-day clock, real Chainlink VRF, stETH rebases, honest
24/7 traffic) is driven by a **separate sim repo**; this agent connects to that
running chain and plays. Pointing it at the live testnet vs. a local stand-in is
**just config** (`--mode live` vs `--mode local`).

This is milestone **v74.0 Phase 462 (AGENT-BUILD)**. The contract subject is the
v73 byte-frozen tree; the agent is additive, new-files-only.

## What it checks

The agent's runtime oracle is the single shared **MAN-01 manifest**
([`manifest/invariants.json`](manifest/invariants.json)) — the *same* invariant
set the C4A README's Main-Invariants section quotes. After every external action
it asserts each invariant from live chain state:

- **SOLVENCY** (`SOLV-01..05`) — game balance covers the canonical obligation
  set; pools fully backed by ETH+stETH; claimable always backed.
- **REDEMPTION** (`REDEEM-01..07`) — segregation, no double-claim, 50% cap, roll
  bounds, split conservation.
- **SUPPLY** (`COIN-01`, `VAULT-01/02`) — FLIP supply identity holds after vault ops.
- **LIVENESS / no-brick** (`FSM-01..03`) — level monotonic, gameOver one-way,
  exactly one FSM state, no permanent dead-state.
- **RNG-FREEZE / VRF lifecycle** (`RNG-01/02`, `VRF-01/02`) — in-window slots
  frozen, index lifecycle, swap preserves lock.
- **DEGENERETTE economics** (`DEG-01/02/03`) — honest EV ≤ 100 centi-x per
  `(N, heroIsGold)`; held-fixed P(S=9)/RTP/ROI pins; the WWXRP rig can never
  fabricate an S=9 jackpot.
- **CURSE neutrality** (`CURSE-01`).

A conservation break (solvency/backing/supply) is **always real** and records
immediately. A "win more than you should" signal is gated: it fires only when an
actor's realized protocol-value profit exceeds the modeled EV by **k·σ over a
counted sample** (never per-spin), and only after the by-design **allowlist**
([`manifest/allowlist.json`](manifest/allowlist.json)) fails to explain it
(deity refund/boon, redemption/salvage exchange, foil subsidy, owner knob, a
documented WONTFIX). Mainnet-gas-viability is annotated **separately** so free
testnet gas can't mask — or fake — a finding.

Mocks (VRF, stETH) are **trusted stand-ins**: their quirks are never findings;
only the protocol's *handling* of randomness / stETH backing is in scope.

## Layout

```
agent/
  manifest/
    invariants.json     MAN-01 — the canonical 34-invariant runtime oracle (shared with the README)
    allowlist.json      13 by-design false-positive suppressors for the profit gate
    MAIN-INVARIANTS.md  human-readable rendering of the manifest (for the C4A README)
  src/
    config.js           mode/RPC/wallet/gate config (default + per-mode JSON + AGENT_* env)
    connection.js       loads deployments + ABIs; merged GAME+modules facade handle
    wallets.js          funded wallet pool, NonceManager, drip-refill
    legs.js             per-actor value legs -> one numeraire (ETH wei; stETH 1:1)
    ledger.js           per-actor P&L vs modeled EV (better-sqlite3; checkpoint/resume)
    pricing.js          on-chain price reads + replicated ROI/RTP EV bounds
    oracle.js           MAN-01 runtime asserter (block-pinned, window-aware)
    gate.js             by-design allowlist + k·σ statistical gate
    records.js          structured, replayable finding records
    actions.js          external action-surface driver (mirrors test/fuzz/handlers)
    strategy.js         the adversarial probe set
    mempool.js          live mempool/event watcher (front-run/sandwich/shared-window targets)
    agent.js            campaign orchestrator (act -> assert -> mark-to-market -> gate)
    index.js            CLI entry
  dev/
    env-driver.js       DEV-ONLY local stand-in for the sim repo (clock + honest VRF + honest actors)
  test/
    unit.test.js        pure-logic tests (ledger/gate/EV/manifest) — `node --test`
  config/
    local.json          local validation config (dev-driver on)
    live.example.json    template for the live testnet (copy to live.json, fill keys)
```

## Run

**Unit tests (no chain):**
```
npm run agent:test
```

**Local validation** (build/iterate against a local stand-in node). One terminal
runs a node + deploy; the agent run interleaves the dev-driver:
```
npm run node                 # terminal 1: a local node
npm run deploy:local         # terminal 2: deploy + write deployments/localhost.json + ABIs
npm run agent:local          # terminal 2: connect + play, with the DEV env-driver
```

**Live soak** against the running 15-min-day testnet (the sim repo owns the
environment; the agent only connects and plays):
```
cp agent/config/live.example.json agent/config/live.json   # fill rpcUrl + attacker keys + deployments path
npm run agent:live
```
or directly: `node agent/src/index.js --mode live --k-sigma 4`.

Findings are written as self-contained, replayable records under
`agent/.state/findings/` (a JSON per finding + `INDEX.jsonl`); the per-actor
ledger persists to `agent/.state/ledger.db` so a soak checkpoints and resumes.

## Local stand-in caveat (honest)

The local `deploy:local` deploys the **frozen contracts at full mainnet prices**
(a level-0 prize-pool target of 50 ETH). The **/1e6 cost scaling** that makes
levels trivially fillable is a property of how the **sim repo** deploys the
*testnet*, not of the local hardhat node. So local validation exercises the
live-game surface and the terminal game-over path and proves the oracle / ledger
/ gate are correct, but does **not** drive deep multi-level progression (filling
a 50-ETH level locally would take thousands of ETH of purchases). Against the
real /1e6 testnet, level progression is automatic and the same agent code runs
unchanged. Because the agent reads all prices/payouts **on-chain**, its EV model
and ledger are auto-correct at either scale.

## Relationship to the Foundry invariant suite

The in-repo Foundry invariant suite (`test/fuzz/invariant/*.inv.t.sol`,
`FOUNDRY_PROFILE=deep`) remains a **separate white-box net** run with
`npm run fuzz` — complementary breadth coverage. This agent is the
**external, live** net; the two are run and recorded side by side (AGT-07).
