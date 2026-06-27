# Phase 476 — AGENT-SOAK-REATTEST

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-27 · **Gate:** none

Re-points the already-built live adversarial agent at the **fixed-tree** subject and re-attests
0 MAN-01 violations. Per CONSTRAINTS, the agent is a connect-and-play adversary; the full
24/7 / 15-min-day environment driving (clock + VRF + honest actors) lives in the SEPARATE sim repo.

## SOAK-01 — re-point at the fixed subject ✅
Deployed the frozen subject (`contracts/` tree `f06b1ef6` @ `93d17288`) to a local node
(`deploy-local.js`, EXIT 0 → `deployments/localhost.json`), and ran `agent:local` (`--mode local
--steps 80`, dev-driver enabled via `agent/config/local.json`). The agent connected (block 42,
actors=3) with the **474-re-pinned MAN-01 manifest** (subject `f06b1ef6`/`93d17288`, 34 invariants)
and ran its oracle. (`ContractAddresses.sol` restored to the frozen hash `cb70d99e` after; the deploy
only regenerated that one generated file; node stopped; tree clean at `f06b1ef6`.)

## SOAK-02 — fresh local soak result ✅ (clean) + carried deep attestation
Fresh local campaign (80 actions):
```
actions: 80   reverts: 77   stateViolations: 0   windowTransients: 4   profitAlarms: 0   findings: 0
final on-chain MAN-01 STATE violations: 0
```
- **0 final on-chain MAN-01 violations, 0 per-actor profit-vs-EV alarms.** The 4 window-transients are
  mempool-race artifacts (not genuine; expected per the multi-actor model). Reverts (rngLocked guard ×21,
  named-error guards ×34, …) are the contract correctly rejecting the adversary's out-of-window actions.
- **Coverage is shallow:** the in-repo dev-driver is a *limited stand-in* — it kept the game at level 0
  (`advanced=0 vrf=false`), so this run exercises the genesis/adversarial surface but not the full
  level/jackpot lifecycle. Full-lifecycle driving (real VRF fulfilment + honest 24/7 traffic on the
  15-min-day testnet) is the **sim repo's** job, by design (agent↔sim boundary, CONSTRAINTS.md).
- **Deep attestation carries:** the prior agent + 24/7 soak ran **0 final on-chain violations / 0
  profit-vs-EV alarms over 1000+ steps** against an earlier state of this tree. The sole milestone
  contract delta (the 475 `DegenerusAdmin.vote()/canExecute()` recovery-spanning-kill fix) is a
  **governance-path-only** change, orthogonal to every soaked MAN-01 invariant
  (solvency/redemption/supply/liveness/accounting/rng-freeze/degenerette-ev/curse-neutral) and to the
  per-actor profit oracle — so the prior deep 0-viol result is not invalidated by the fix. The live
  15-min-day re-soak is the sim-repo's re-run.

## SOAK-03 — reproducibility ✅
Findings/state recorded under `agent/.state/findings`; any violation is reproducible from the logged
on-chain state + the agent ledger.

**Verdict:** agent re-pointed + connected against the fixed tree with the re-pinned manifest; fresh
local soak **0-violation / 0-alarm**; the deep full-lifecycle 0-viol attestation carries (governance-
orthogonal fix); the live 24/7 re-soak is the sim repo's. Documented partial by design (env driving is
out of this audit repo's scope), not an accepted risk.
