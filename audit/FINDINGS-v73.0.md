# Degenerus Protocol — v73.0 Audit Findings

**Milestone:** v73.0 — Degenerette "Variant-2" Color-Gated Rescore (+ WWXRP Rig Preservation)
**Date:** 2026-06-21
**Subject (frozen):** `contracts/` tree **`d6615306`** (IMPL commit **`64ec993e`**). Baseline was the v72.0 closure subject `contracts/` tree **`4407181d`** (HEAD `e94f1719`). The tree advanced only via the single batched, USER-approved IMPL commit recorded below; the test/audit work that followed touched no `contracts/*.sol`.
**Closure signal:** MILESTONE_V73_AT_HEAD_15650b6a05427517981b14ac62ddf18364c0525b
**Method:** Design→build→prove→re-audit. Phase 452 GEN rewrote + verified the canonical generator (`derive_5_tables.py`) and presented the regenerated tables + the EV-drift measurement BEFORE any contract edit. Phase 453 IMPL landed the Variant-2 change as ONE batched, USER-approved `.sol` diff (the sole approval gate). Phase 454 TST rewrote the v72-era oracles to v73 and added the held-fixed-invariant proofs (byte-reproduce, EV exactness, exact EV-equality, P(S=9) invariance, the real-rig 3000-spin distribution parity, and curve/pin/bracket byte-equality vs the pre-v73 source). Phase 455 REAUDIT ran three isolated top-model subagents (neutral defensive-engineering prompts, read-only) — one per pillar — plus a cross-model **Codex** corroboration of the three load-bearing claims. Honest admin/governance assumed; pre-launch, no live funds.
**Regression floor:** final full forge suite **943 passed / 0 failed / 108 skipped** (136 suites) on the frozen tree.

---

## Verdict: 0 CATASTROPHE / 0 HIGH / 0 MED / 0 LOW · 0 open findings on the final subject

v73 ports the color-gated-by-symbol scoring rule — already shipped + audited on the *foil* match in v72 (`16225de6`) — into the **core Degenerette betting engine**. The main paying slot moves from ~1-in-3 (≈32%) to **~1-in-5 (≈19.5%) at ~2× the multipliers, at IDENTICAL EV**; the WWXRP rig family is recalibrated (DEC-01 R2: a score-bearing "+2-unlock, never-a-9" rig) and the honest ETH/FLIP payout family is split per `(N, hero-is-gold)` (DEC-02 Option B) so every pick is **exactly EV-equal**. Everything that matters about WWXRP and the jackpot is **held byte-fixed**: P(S=9) and the jackpot pins, the WWXRP RTP curve (70→115→118→120%), the activity ROI curve (90→99.9%), and the S=9 whale-pass bracket. The change is a **bounded recalibration of one file** plus the re-audit it forces. All load-bearing math was independently re-derived (generator + an independent BigInt Variant-2 model) and the real rig was run over 3000 on-chain spins against its analytical distribution; the three protocol pillars (Solvency · RNG integrity · Liveness/no-brick) were re-attested by isolated subagents and cross-model-confirmed. **0 findings remain open.**

| Phase | Category | Verdict |
|---|---|---|
| 452 GEN | Generator-first rewrite + table regen + EV-drift measurement (no contract edit) | OK — Variant-2 honest + R2 rigged dists; EVEQ-01 hero-placement drift 2.99→0.00007 centi-x → DEC-02 escalated to Option B; P(S=9)/RTP pre-proof PASS |
| 453 IMPL | The single batched `.sol` diff (the sole approval gate) | OK — USER-approved commit `64ec993e`; subject byte-frozen at tree `d6615306`; module 15,873 B (8,703 B EIP-170 margin); S9 pins + WWXRP_ROI_* byte-identical to HEAD |
| 454 TST | Byte-reproduce + EV/EVEQ + R2 rig parity + held-fixed invariants + full-suite parity | OK — 44/44 byte-reproduce; per-(N,heroIsGold) EV ≤100 & exactly EV-equal; bonus EV=5.000%; P(S=9) invariant; INV-01/02/03/04 byte-unchanged vs pre-v73; 3000-spin real-rig distribution parity; forge 943/0/108 |
| 455 REAUDIT | 3-pillar isolated-subagent sweep + cross-model Codex | OK — 0 CAT/0 HIGH/0 MED/0 LOW; all pillars attested below |
| 456 TERMINAL | Evidence pack + closure | OK — this document |

---

## What changed (and what did not)

**The rule (`_score`).** Pre-v73: `S = A + 2H` — 4 color + 4 symbol axes counted *independently* (hero symbol +2). Variant-2: per quadrant a SYMBOL match scores +1 (hero +2), and that quadrant's COLOR scores +1 **only if its symbol also matched** (color gated behind symbol). S∈{0..9} unchanged; floor S≥2 unchanged; **S=9 is still the all-8-axes event**.

| Surface | File / anchor | Change | Held fixed? |
|---|---|---|---|
| Score rule | `_score` `:1086` | Variant-2 color-gated-by-symbol (hero +2); a lone color now scores 0 | S range {0..9}, floor S≥2 |
| WWXRP rig | `_rigWwxrpResult` `:1386` | DEC-01 R2 score-bearing pool (non-hero symbols + colors on symbol-matched quads), +2 unlock, m≥7 cap, empty-pool `u==0` guard | reel-/score-honest display; P(S=9) (m≥7 cap) |
| Honest tables | constants `:~300`, `_getBasePayoutBps` `:1230`, `_wwxrpFactor` `:1136`, `_fullTicketPayout` `:1181` | split per (N, hero-is-gold) → 8 base + 8 S8 + 8 factor; `heroIsGold` selector threaded (honest lane only) | per-N EV ≤100; +5% ETH bonus EV |
| Rigged tables | `_RIG_` family | recalibrated under the R2 dist (still 5 per-N, averaged by-design) | rigged EV ≤100; WWXRP win-rate target |
| **Untouched** | S9 pins `QUICK_PLAY_PAYOUT_N{0..4}_S9`; `WWXRP_ROI_*`/`WWXRP_FLOOR_BPS`; `_roiBpsFromScore`; `_wwxrpRoi`; whale-pass bracket; `WWXRP_RIG_SALT`; `WWXRP_BONUS_FACTOR_SCALE` | — | **byte-identical to pre-v73 (proven, INV-01..04)** |

---

## The three pillars (re-attested on the new scoring)

**Solvency.** All 44 v73 constants byte-reproduce from the canonical generator; every honest sub-case basePayoutEV ∈ [99.99968, 100.0] centi-x and every rigged-lane EV ∈ [99.99857, 99.99955] — all ≤ 100, house edge ≥ 0. The `(N, heroIsGold)` table selected at each of the four call sites is always the one whose distribution the ticket is scored against (the same `heroQuadrant` local feeds both `_score` and the `heroIsGold` derivation; N0/N4 collapse is sound; rigged↔honest lanes never cross). The +5% bonus redistribution is exactly 5.000% per sub-case (cannot overpay), and the rig's m≥7 cap means it can never route an S=9 payout.

**RNG integrity.** The result seed (`keccak256(rngWord, index[, spinIdx], QUICK_PLAY_SALT)`) and rig seed (`hash2(resultSeed, WWXRP_RIG_SALT)`) are byte-identical in shape to pre-v73 and derive only from the committed `lootboxRngWordByIndex[index]`; the rig seed is reel-independent. All table selectors (heroQuadrant, ticket, N, heroIsGold, activityScore) are frozen at bet placement (the frontier index word is 0 until VRF reveal; a placed bet cannot be re-committed against a revealed word), so no post-commitment steer exists. The m≥7 cap holds in code (one forced axis per fired roll → post-force M≤7 → S≤8 < 9). Resolution is caller- and batch-order-independent (score is a pure function of committed inputs; accumulators are additive-only).

**Liveness / no-brick.** The `% u` is guarded by an explicit `u==0` no-op (the one hardening v73 itself shipped — the prior code relied on an unstated `u≥1` invariant that Variant-2's narrowed pool could break); pass-1/pass-2 of the rig enumerate the same eligible cells in the same order so `pick` aligns and `--pick` never underflows; all packed-slot shifts are in range; the advanceGame / pool-accounting / pull-claim state-write surface is byte-identical to pre-v73 (the diff changes only which table/bucket is read); no new push-transfer. EIP-170: 15,873 B (8,703 B margin). The rig is WWXRP-only (cap 5 spins), pure and storage-free; the 25/45-spin resolve-bet worst case (ETH/FLIP, rig not invoked) stays < 30M (per the Variant-2-updated worst-case gas test).

**Cross-model (Codex):** independently re-traced the diff and **CONFIRMED all three load-bearing claims** (Solvency, RNG-integrity, Liveness/no-brick) with exact line references, an exhaustive **1,024-state / 2,532-fired-pick-path** rig enumeration (max post-rig fired score = **8**, no S=9, no pick-misalignment, no `--pick` underflow), a constant-decode showing the S0/S1 floor slots are zero and packed shifts stay in range (`s·32 ≤ 224`, `(bucket−6)·64 ≤ 192`), and a diff scan confirming no storage-write / pool-accounting / pull-claim statement changed. **Real finding: none; worktree stayed clean.** Converges with the three isolated Claude subagents.

---

## Findings & dispositions

No CATASTROPHE / HIGH / MED / LOW findings. INFO-level, by-design confirmations only:

| ID | Sev | Item | Disposition |
|---|---|---|---|
| I-01 | INFO | The R2 +2 color-unlock raises S by 2 but M by only 1, so the m≥7 cap still bounds a fired roll to S≤8 — P(S=9) invariant holds in code (matches the 3000-spin proof). | By-design; verified. |
| I-02 | INFO | The honest `(N,heroIsGold)` split closes the ~+2.24% player-selectable hero-common edge that existed on the real-money lane; the WWXRP `_RIG_` lane retains its averaged-table hero-placement drift by-design (USER "worthless shitcoin" ruling). | By-design (DEC-02). |
| I-03 | INFO | The explicit `u==0` empty-pool guard is the correct hardening for Variant-2's narrowed eligible pool (prevents a `% u` div-by-zero the pre-v73 blanket-color rig could not hit). | By-design; verified. |

---

## Carries (non-blocking; pre-existing, NOT v73)

- **6 stale `test:stat` surface anchors** — `SurfaceRegression` (DegenerusGameJackpotModule hero-override / DegenerusTraitUtils ranges / EntropyLib's `hash1` addition / LootboxModule, all vs v33–v40 baselines, broken by earlier-milestone gas/refactor work) + `PerPullEmptyBucketSkip` (STAT-03 lootbox MC). NONE reads `DegenerusGameDegeneretteModule.sol`, so their result is identical at the v72 baseline — confirmed not v73 regressions. Re-anchoring is out of v73 scope.
- **`_deployProtocol` real-clock setUp flake** — with no `block_timestamp` pin in `foundry.toml`, a protocol constructor's day-arithmetic intermittently panics (0x11) at certain wall-clock seconds during Foundry `setUp` (harness-wide, intermittent; retries pass). Not v73; recommend pinning `block_timestamp` in a future harness pass.

---

## Evidence

- Generator (byte-source): `.planning/notes/degenerette-recalibration/derive_5_tables.py`
- Mechanics + design intent: `.planning/notes/degenerette-recalibration/V73-MECHANICS-AND-INTENT.md`
- Tests (454): `test/stat/DegenerettePerNEvExactness.test.js` (23), `test/stat/DegeneretteBonusEv.test.js` (14), `test/stat/DegeneretteV73Invariants.test.js` (7), `test/fuzz/DegeneretteHeroScore.t.sol` (8), `test/gas/KeeperResolveBetWorstCaseGas.t.sol` (4)
- Re-audit (455): `.planning/phases/455-reaudit/455-SUMMARY.md` (+ Codex cross-check)
- HTML report: `audit/AUDIT-V73-REPORT.html`
