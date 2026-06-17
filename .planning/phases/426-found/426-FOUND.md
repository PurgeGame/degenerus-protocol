# Phase 426: FOUND — Subject Freeze, Green Baseline & Tooling Starting State

**Milestone:** v68.0 Pre-C4A Coverage Completion + AI-Verifiable RNG-Freeze Proof
**Completed:** 2026-06-17
**Requirements:** FOUND-01, FOUND-02

---

## FOUND-01 — Subject byte-freeze anchor

| Anchor | Value |
|--------|-------|
| HEAD commit | `d0af2984389b853dc58b86bc0216596eed566ddc` (`d0af2984`) |
| `contracts/` tree | `4970ba5b7d22bdce9aedfbb6c3725c81f4e07803` (`4970ba5b`) |
| origin/main | `d0af2984` (== HEAD; already pushed) |

The contracts tree `4970ba5b` is **unchanged since the v67 MIDRNG-02 re-freeze** (v67 closure subject). `git diff` against this anchor is empty. v68.0 is a logic-frozen milestone: the ONLY `contracts/*.sol` edit planned is the logic-inert comment trim (Phase 433), behind the contract-commit approval gate. Every other track (MUT/INV/RNGPROOF/LAYOUT/CI/COUNCIL) is test/tooling/proof/CI work and must not change the contracts tree.

**Freeze invariant for the milestone:** `git rev-parse HEAD:contracts == 4970ba5b` holds through Phase 432; it may change exactly once, at Phase 433, and only by comment-only edits (verified logic-inert).

---

## FOUND-02 — Green baseline + detection-asset inventory

### Forge full-suite baseline (primary regression oracle)

```
Ran 127 test suites: 903 tests passed, 0 failed, 108 skipped (1011 total)
```

- **Status: GREEN** (0 failures). Captured at HEAD `d0af2984` / tree `4970ba5b`, default profile (optimizer_runs=1000, via_ir). Raw log: `.planning/phases/426-found/forge-baseline.txt`.
- Matches the v67.0 close (903/0/108) exactly — expected, since the contracts tree is byte-identical. The 108 skips are the carried/known skip set, not new.

### Hardhat parity

The contracts tree is **byte-identical to the v67.0 close** (`4970ba5b`), so the hardhat baseline carries by construction from v67 (1239/129/14 carried floor). No contract change in v68 until Phase 433 (comment-only), so hardhat parity holds; a full hardhat re-run is optional and deferred (slow; no logic delta to validate).

### Detection-asset starting state (what each v68 track extends)

| Asset | Current state | v68 track / gap |
|-------|---------------|-----------------|
| **Invariant net** | 17 suites under `test/fuzz/invariant/` (BoxEnqueue, CoinSupply, Composition, DegeneretteBet, EthSolvency, GameFSM, MultiLevel, PoolConservation, RedemptionInvariants, RngIndexDrainOrdering, RngWindowFreeze, TicketQueue, V61SolvencyAfpay, VaultShare, VaultShareMath, VRFPathInvariants, WhaleSybil); **68 `invariant_` properties** | **INV** — runs shallow in CI (runs=256/depth=128) and `[invariant] fail_on_revert = false` in **both** the default and `[profile.deep.invariant]` profiles → the should-not-have-reverted class is silently discarded. Deep profile already exists (`[profile.deep.invariant]` runs=1000/depth=256). |
| **Halmos proofs** | 5 files under `test/halmos/` (Arithmetic, GameFSM, NewProperties, RedemptionRoll, SolvencyArithmetic); **31 `check_` proofs** | **CI** — run manually only; a proof-breaking edit ships green today. |
| **Mutation harness** | `audit/mutation/` — `run-campaign.sh` + `run-campaign-v63.sh` + `run-campaign-v64.sh`, `oracle-comprehensive.sh` + 7 per-target oracles. `.DONE` for the 7 v63-spine targets (BitPackingLib, JackpotBucketLib, JackpotModule, Storage, Vault, GameTimeLib, StakedDegenerusStonk). **No `.DONE` for Coinflip / LootboxModule / DecimatorModule.** The aborted `BurnieCoinflip-v64.log` ends on `for (uint24 d=1; revert(); )` → `COMPILATION FAILURE` (the invalid-RR-mutant class that aborts the run). Oracle-hole regressions land in `test/mutation/MutationKills.t.sol`. | **MUT** — harness needs the non-compiling-mutant pre-filter (MUT-01) before the 3 RNG modules can be scored (MUT-02/03). |
| **Foundry profiles** | `[profile.default]` (runs=1000 fuzz), `[profile.lite]`, `[profile.deep.fuzz]` (runs=10000), `[profile.deep.invariant]` (runs=1000/depth=256, fail_on_revert=false) | **INV** uses `[profile.deep.invariant]`; **CI** schedules it. |
| **CI** (`.github/workflows/ci.yml`) | `foundry` job = `forge build --sizes` + **EIP-170 ceiling guard** (fails if any deployed > 24,576) + `forge test -vvv`, on push/PR. Plus non-blocking `slither` + `aderyn` jobs. | **CI/LAYOUT** — NO Halmos, NO deep-invariant, NO mutation, NO storage-layout-diff gate today. The EIP-170 ceiling check already exists and is reused by CI-02; LAYOUT-02 adds the slot-diff oracle. |

### Carried v67 items folded into v68 (baseline note)

- codex-423 backfill + frozen-commit council pass → Phase 432 (COUNCIL).
- full forge-inspect storage-layout snapshot oracle (MECH-02, shipped PARTIAL in v67) → Phase 430 (LAYOUT).
- INFO-02 slot-46 `yieldAccumulator` creditFlip no-callback regression → Phase 427 (MUT-04).
- optional `:1843`/`:1850` `==0` guard + 423 rotation-timer hardening → v2 (deferred, LOW defense-in-depth contract changes).
- `capBucketCounts` exactness → CLOSED (USER: never >1 solo bucket; out of scope).

---

## Verdict

FOUND-01 ✅ and FOUND-02 ✅. Subject frozen at `d0af2984` / `4970ba5b`; forge baseline GREEN 903/0/108; every v68 detection track's starting state is inventoried with its measurable gap. Ready for Phase 427 (MUT).
