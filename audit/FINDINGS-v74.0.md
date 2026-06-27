# FINDINGS — Milestone v74.0 (As-Built Audit + C4A Package)

**Subject (frozen):** `contracts/` tree **`f06b1ef6`** @ impl **`93d17288`** = the `v73.0 → HEAD` batch
(`3986926c`, 29 .sol, +1861/−1030) **plus one milestone fix** (the sole contract delta vs `3986926c`:
`DegenerusAdmin.sol`, +16/−6, logic-only).
**Method:** verify → freeze-confirm → harness-green → 6-cluster as-built code audit → manifest re-point →
cross-model adversarial re-audit (Codex) → live-agent/soak re-attest → C4A package → terminal.
**Verdict:** **0 open findings.** The 8-cluster as-built audit returned 0 findings; the cross-model pass
surfaced **1 MEDIUM**, fixed under the conditional contract gate with owner approval. All other raised
candidates refuted or dispositioned by-design (recorded below).

---

## 1. Cluster dispositions (as-built code audit)

| Cluster (phase) | Reqs | Result |
|---|---|---|
| SUBJ — subject freeze + storage golden (466) | SUBJ-01..04 | ✅ frozen; no top-level slot move vs v73; only `Sub` repack + additive `_sdgnrsBonusLevel` |
| HARN — harness green (467) | HARN-01..03 | ✅ forge 0-fail; Hardhat 1359/0/18 (3 genesis-stall guards documented-skipped) |
| SOLV — solvency / backing (468) | SOLV-01..08 | ✅ 8/8 HOLD |
| RNG — RNG-freeze / VRF (469) | RNG-01..05 | ✅ HOLD |
| LIVE — liveness / advance-gas (469) | LIVE-01..04 | ✅ HOLD |
| ACCESS — access / permissionless / governance (470) | ACCESS-01..07 | ✅ 7/7 HOLD |
| EV — EV/RTP economy (471) | EV-01..07 | ✅ 7/7 HOLD |
| WIRE — rename/wiring/storage inert (472) | WIRE-01..04 | ✅ 4/4 HOLD (157 named-error swaps condition-preserving; 0 stale refs) |
| GAS — gas-faucet (473) | GAS-01..04 | ✅ 4/4 HOLD (dormant, CEI-safe, donated-only) |
| MAN — manifest re-point (474) | MAN-01..03 | ✅ re-pinned to fixed tree; 28→34 invariants |

Method per cluster: isolated neutral-prompt reviewers (Workflow `wf_00bd2866`) with an adversarial-verify
pipeline + skeptic filter; contracts git-verified unmodified after the read-only fan-out. Per-requirement
file:line evidence in `.planning/phases/46{8,9}-*, 470-*, 471-*, 472-*, 473-*/`.

## 2. Cross-model adversarial re-audit (Phase 475) — the conditional gate

Codex (primary; Gemini tier-ineligible) over 6 ranked surfaces. **The gate fired once.**

| # | Surface | Disposition |
|---|---|---|
| 01 | Purchase hot-path solvency fold | NONE (clean) |
| 02 | VRF-death deadman + mid-day RNG | CAT raised → **by-design** (the >120d VRF-death prevrandao fallback is the accepted super-fallback: fund-recovery vs permanent brick; only after catastrophic unrecoverable VRF death; genesis/no-victim). KNOWN-ISSUES §3a. |
| 03 | Queue-gate / swap / composition | CAT raised → **refuted** (lootboxes can't open post-gameover; tickets only enter via the freeze-isolated queue). |
| 04 | sDGNRS level-start box | MED raised → **refuted** (box sized strictly pre-rng-request; word unknowable at sizing). |
| 05 | payAffiliateCombined EV/distribution | NONE (only the immaterial ≤3-FLIP quest rounding). |
| 06 | Access / admin governance timing | **REAL MEDIUM → FIXED `93d17288`.** |

**The MEDIUM (06), fixed:** `DegenerusAdmin.vote()`/`canExecute()` kill-on-recovery was *lazy* (only
killed a VRF-coordinator-swap proposal when poked while currently recovered), so a proposal created in
stall-1 could survive an un-poked VRF recovery and execute in a later ≥44h re-stall at the age-decayed
(down to 5%) threshold with stale votes — installing an arbitrary VRF coordinator below the intended
governance bar. Fix: also invalidate when `lastVrfProcessed > createdAt` (any fulfillment after creation
⇒ a recovery occurred ⇒ proposal dead), recovery-proof without a poke. Logic-only; regression test
added (`83a5ce43`). Build clean; VRFGovernance/GovernanceGating green.

## 3. Known-issues perimeter
Full precise perimeter in `KNOWN-ISSUES.md` (6 design decisions, 10 by-design rulings, the 475
dispositions, 3 carried-defended items incl. the mid-day `==0` guard re-checked against the as-built
fold, the genesis dead-VRF gap-backfill latent edge [non-mainnet-reachable, tracked], 9 stale-natspec
doc notes, the `AffiliateEarningsRecorded` indexer-parity delta). Trust model + roles in `SECURITY.md`.

## 4. Live agent + soak re-attest (Phase 476)
Agent re-pointed at a local-fork deployment of the **fixed tree** (`f06b1ef6`/`93d17288`) with the
474-re-pinned MAN-01 manifest. Fresh local soak (80 actions): **0 final on-chain MAN-01 STATE
violations, 0 profit-vs-EV alarms** (4 window-transients = mempool-race artifacts). Coverage shallow
(in-repo dev-driver is a limited stand-in — stayed at level 0; full-lifecycle 15-min-day driving is the
sim repo's job). The prior deep 0-viol soak (1000+ steps) carries: the sole contract delta (the 475
governance-path fix) is orthogonal to every soaked invariant. See `.planning/phases/476-agent-soak/`.

## 5. C4A package (Phase 477)
`scope.txt` (50 in-scope sources, 20,070 nSLOC) + `out_of_scope.txt` + `SECURITY.md` + trust-model +
`KNOWN-ISSUES.md` + `audit/C4A-CONTEST-README.md` (Main-Invariants verbatim from MAN-01) +
`audit/ACCESS-CONTROL-MATRIX.md` + `audit/ETH-FLOW-MAP.md`, all against the fixed tree.

## 6. Closure
**Closure signal:** `MILESTONE_V74_AT_HEAD_93d17288ba6719e0a77723d6167c0ba4796b8467`
**Subject byte-frozen:** `contracts/` tree **`f06b1ef6`** @ impl **`93d17288`** (the byte-frozen subject
HEAD; subsequent `.planning/`/`audit/`/`test/` commits do not alter the contracts tree). Distinct from
the v73 closure `MILESTONE_V73_AT_HEAD_15650b6a…` (tree `d6615306`).
**Conditional contract gate:** fired once (475-06) and resolved — the owner-approved fix `93d17288` is
committed; the subject is re-frozen at the fixed tree.
**Internal consistency (TERM-03):** scope.txt / nSLOC / `agent/manifest/invariants.json` /
`MAIN-INVARIANTS.md` / `audit/C4A-CONTEST-README.md` / `KNOWN-ISSUES.md` all reference the same frozen
subject `f06b1ef6`/`93d17288`; the README Main-Invariants section is verbatim-synced to MAN-01 (34
invariants). Tag: `v74.0` (local; not pushed).

---
*As-built audit: 8 clusters clean; cross-model 1 MEDIUM found + fixed; 0 open findings.*
