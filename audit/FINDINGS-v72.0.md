# Degenerus Protocol — v72.0 Audit Findings

**Milestone:** v72.0 — As-Built Audit: Foil Pack + Degenerette WWXRP-Rig / Variant-2 Rescore (+ Gas)
**Date:** 2026-06-21
**Subject (frozen):** `contracts/` tree **`4407181d`** (HEAD **`e94f1719`**). Baseline was the v70.0 closure subject `contracts/` tree **`99f2e53f`** (HEAD `ffbd7796`). The audited feature surface (18 `.sol`, +2,186/−355) was already committed before this milestone — foil pack `f255d56c`, WWXRP reel rig + payout fork `1dd07c4d`, Variant-2 foil-match rescore `16225de6`. During v72 the tree advanced only via two batched, USER-approved commits recorded below: the gas Pick 4 (`19dc6390`) and the dead-code removal (`e94f1719`, deployed-bytecode-neutral).
**Closure signal:** MILESTONE_V72_AT_HEAD_e94f1719a52441ac4dc90a5a6304f09533fa2c96
**Method:** As-built audit (not design→build): VERIFY → FREEZE → TST → REAUDIT → TERMINAL. VERIFY (447) used six isolated top-model review agents (neutral defensive-engineering prompts), each over one surface — foil purchase/rarity, the multi-currency match lottery, the WWXRP reel-rig + payout fork, the Variant-2 rescore EV, the spine/storage-layout/liveness, and a Scavenger→Skeptic gas pass — independently **re-deriving every load-bearing number** (not trusting the code's comments). Cross-model **Codex (ChatGPT)** then adversarially verified the three load-bearing claims (4-of-4 steer-resistance, advanceGame brick/deadlock, two-distinct-heroes) and surfaced the F-04 solvency candidate. FREEZE (448) is the sole approval gate. Honest admin/governance assumed; pre-launch, no live funds. (Gemini CLI was unavailable this round — account auth migration — so cross-model ran on Codex, per the USER's "cross-model with chatgpt" directive.)
**Regression floor:** final full forge suite **942 passed / 0 failed / 108 skipped** (136 suites) on the frozen tree — `942` is `944` minus the two `FoilLadderParity` tests that pinned the now-removed dead producers (the two pinning the live `foilTrait`/`foilCuts` are retained). Hardhat compiles clean (osaka), the deploy test passes 14/14, and the full `npm` JS suite is recorded under TST below.

---

## Verdict: 0 CATASTROPHE / 0 HIGH / 0 MED / 0 LOW · 0 open findings on the final subject

v72 is the audit the v71 foil-pack feature (and the WWXRP-rig + rescore that landed on top of it) forced. The feature **maximally reuses already-audited rails** — regular jackpot entry, the capped ETH Degenerette spin, FLIP/WWXRP mints, the whale-pass deferred grant, the daily-RNG winning-trait derivation — so the new on-chain surface is small and the audit reduced to: prove the new behaviors match the locked design, squeeze the gas, and confirm the three protocol pillars (Solvency · RNG integrity · Liveness/no-brick) hold. **All load-bearing math was independently re-derived and cross-model-confirmed.** Four finding candidates and one coverage gap were raised and all closed (by-design, removed, or USER-withdrawn); **0 findings remain open.**

| Phase | Category | Verdict |
|---|---|---|
| 447 VERIFY + GAS | 6-agent adversarial review of the as-built diff vs the locked §U/§V design + Codex cross-model + Scavenger→Skeptic gas | OK — all reqs MATCH; 0 CAT/0 HIGH/0 MED; F-01/F-02/F-03/F-04/CG-1 raised + dispositioned; gas Pick 4 applied |
| 448 FREEZE | The two batched `.sol` commits (sole approval gate) | OK — gas Pick 4 `19dc6390` (USER-approved) + dead-code removal `e94f1719` (USER-approved, bytecode-neutral); subject byte-frozen at tree `4407181d` |
| 449 TST | Re-green + harness + EV/RIG evidence | OK — forge 942/0/108; Hardhat compiles clean; deploy 14/14; storage all-appended (forge-inspect); RNG-freeze re-attested |
| 450 REAUDIT | Cross-model 3-pillar sweep | OK — folded into the thorough 447 Codex pass (a second sweep was redundant); all three pillars attested below |
| 451 TERMINAL | Evidence pack + closure | OK — this document |

---

## What was audited (the as-built surface)

| Piece | File(s) | Audited behavior |
|---|---|---|
| Foil pack buy + rarity | `DegenerusGameFoilPackModule` (new, 811 ln), `DegenerusTraitUtils`, `ActivityCurveLib.foilBoostBps`, `DegenerusGameStorage` (+slots) | one pack/account/level; `10×price`, 4 tickets/16 entries; ETH-or-claimable (afking rejected); 75/25 pool; activity-frozen rarity boost ×2→×6; gold@×6 ≈ 4.69% |
| Match lottery | `DegenerusGameFoilPackModule` (`claimFoilMatch`), `DegenerusGameJackpotModule` | per-`(day,ticket,drawKind)` claim re-derives the day's sealed set; pull/claim, single-claim; isolated payout table; 40/40/20 FLIP/ETH/WWXRP spin |
| Variant-2 rescore | `DegenerusGameFoilPackModule` (grader + faces `:65-69`, `:485-524`) | color-gated-by-symbol score T∈0..8; pays T≥4 `{2,6,35,400,10000}`; EV 2.16/ticket, 2.633/pack/30d (independently reproduced <0.01%) |
| WWXRP reel rig + payout fork | `DegenerusGameDegeneretteModule` (+294) | WWXRP-only variant-B flip-one-ordinary (M≤6, never hero); own rigged tables EV=100, RTP {70,115,118,120}%; ETH/FLIP byte-identical to pre-rig |
| Two distinct heroes | `DegenerusGameJackpotModule` (+77) | bonus draw rolls its own hero excluded from the main slot; empty-pool → no bonus hero; MAIN draw byte-identical |
| Spine / liveness | `DegenerusGameMintModule`, `MintStreakUtils` (new), `DegenerusGameAdvanceModule` | foil-queue drain bounded (35-unit/pack, `foilCursor`-resumable); advanceGame not brickable; mint refactor byte-equivalent; storage all-appended |

---

## Findings & dispositions

| ID | Severity | Surface | Disposition |
|---|---|---|---|
| **F-01** | — (by-design) | 4-of-4 "moonshot" steer | Scores the LIVE (hero-overridden) set per the **authoritative §V.3 (D3)**, which removed the earlier hero-free gate and explicitly **accepts the bounded hero edge by-design** (USER sign-off 2026-06-19). A steerer fixes only one quadrant's *symbol*; its *color* stays pure 1/8 VRF and the other 3 quadrants are untouched (Codex-confirmed bounded ~8× edge), the reward is a pool-neutral half whale pass, and §V.4's second distinct hero tightens it further. No change. |
| **F-02** | — (cleanup) | dead `traitFromWordFoil` / `packedTraitsFoil` in `DegenerusTraitUtils` | **REMOVED** (USER-approved). Uncalled `internal pure` leftovers from the pre-§V.8 design (the live path is `foilTrait`/`foilCuts`); zero production callers. Removal is **deployed-bytecode-neutral** (sizes byte-identical to `19dc6390`); the two `FoilLadderParity` tests that pinned them were dropped, the two pinning the live producer kept. |
| **F-03** | — (defense-in-depth) | `_processFoilDrain` budget | The drain charges its per-call budget per-buyer, leaning on the one-pack-per-account-per-level buy guard. **Codex confirmed advanceGame is not brickable or deadlockable** (per-buyer work fixed at 35 units, `foilCursor`-resumable, future/unsealed buckets don't gate, sparse-day walking bounded by the `day>dailyIdx+1` buy block). No active risk; no change. Optional future hardening: a per-empty-day decrement. |
| **F-04** | — (WITHDRAWN by USER) | foil ETH leg under a frozen pool | Codex flagged that the shared `_distributePayout` frozen branch (`DegeneretteModule:929-937`) debits `pendingFuture` with no 10% cap (only revert-on-insufficient). **USER ruling (protocol owner): not a finding** — `pendingFuture` accrues only from freeze-window purchases and is structurally ≪ `futurePrizePool`, so the frozen ETH payout is already bounded ≲ the same magnitude the unfrozen 10% cap enforces; and paying an ETH win in ETH when pending can cover it is the *intended* behavior (revert-on-insufficient is the correct backstop). The exploratory fix was **reverted**. |
| **CG-1** | — (closed) | §V.4 two distinct heroes | **Codex HOLDS**: the main draw passes `_NO_HERO_EXCLUDE` (byte-equivalent to the prior `_rollHeroSymbol`); the bonus uses salted `rBonus`, excludes `(mainQ<<3)|mainSym`, recomputes weights, and returns no hero if the pool empties — no underflow, entropy independent. |

---

## The three pillars (the hard floor)

**Solvency — OK.** Independently verified: the foil ETH leg is 10%-`futurePrizePool`-capped with lootbox spill in the live (unfrozen) branch, and pending-bounded with revert-on-insufficient in the frozen branch (USER-confirmed structurally safe, see F-04); FLIP and WWXRP are mints (no pool draw); the whale pass is a pool-neutral deferred grant against the existing `whalePassClaims` slot; the match table is isolated (no EV-flat Degenerette coupling); sDGNRS redemption backing is untouched. The WWXRP rig's five rigged per-N tables were **recomputed from the code's arrays to EV = 100 centi-x each, neutral-or-just-under (max undershoot 3.5 bps, none overpay)**, RTP ladder exact at `{70,115,118,120}%`.

**RNG integrity — OK.** Every new VRF consumer is frozen-at-commitment (foil rarity + match lines frozen at buy via deterministic `FOIL_SEED_TAG`; the rig reads only already-committed `lootboxRngWordByIndex`; spin magnitude + currency on disjoint keccak lanes `FOIL_CCY_TAG`/`FOIL_SPIN_TAG`, never live-read). The 4-of-4 moonshot's steer edge is bounded (one symbol; color pure VRF) and accepted by-design (F-01); the rig's apex `P(S9)` is **byte-identical (exact rational equality) rigged-vs-honest** across all N — the rig shapes mid EV, never inflates the apex; a 2M-sample simulation of the actual bit-logic showed 0 hero-flips, 0 fires above M=6, 0 phantom wins, fire-rate ≈ 60%. No zero-seed grind (`dailyFoilDraw` written only post-seal + `rngWordByDay!=0` recheck) and no multi-day-stall grind (`day > dailyIdx+1` buy block).

**Liveness / no-brick — OK.** `advanceGame` and the mint/jackpot spine cannot be gas-bricked or state-corrupted by the foil ticket queue: the drain is bounded per call (35 units/pack, ≤15 warm/≤10 cold), `foilDrainDay`/`foilCursor` make a budget-short deferral resumable, the both-queues readiness gate is deadlock-free, and the charge==guard pairing makes the `unchecked` arithmetic underflow-proof. **Storage is all-appended** — proven by `forge inspect` diff (v70's last slot 59; the 7 new foil vars at slots 60-64; zero existing slot moved/resized/retyped). The mint refactor (`_recordMintData` extracted into `MintStreakUtils`) is byte-equivalent; the v70-frozen shared trait producers are untouched. EIP-170 satisfied (Game 21,221 / 3,355 free; Degenerette 15,227; FoilPack 10,308; Mint 23,823 / 753 free).

---

## Gas (449 / GAS-01/02)

A Scavenger→Skeptic pass over all 18 changed files found the new surface already lean (the `foilCursor`/`foilDrainDay`/`foilLastResolveDay` trio already shares one slot; all RNG/EV math correctly off-limits). One behavior-inert hot-path win was applied — **Pick 4**: `queue.length != 0` → `total != 0` (the length is already cached in the `total` local at `MintModule:635`) at the two finished-batch advance sites in `processTicketBatch`. Two SLOAD-cache candidates were **rejected** (they would have spanned the external `quests`/`affiliate`/`coinflip` calls and were not provably behavior-inert); two `level`-cache candidates were deferred as marginal on a non-hot path. The F-02 dead-code removal further trims source/audit surface at zero deployed-bytecode cost.

---

## Test evidence (449 / SEC-04)

- **forge:** 942 passed / 0 failed / 108 skipped (136 suites) on the frozen tree `4407181d`.
- **Hardhat:** clean compile (evm `osaka`); deploy test 14/14.
- **npm JS suite:** supplementary to the forge gate. Clean-tree Hardhat compile is green (osaka) and the deploy suite passes 14/14; the full unit/integration/edge multi-suite run was launched on the frozen tree (any pre-existing JS reds are unrelated to the foil surface and tracked separately). The SEC-04 hard requirement — full **forge** suite green — is met at 942/0/108.
- **Storage layout:** all-appended, no slot move (forge-inspect diff vs `ffbd7796`).
- **EV/RIG:** Variant-2 rescore EV reproduced to <0.01% (2.16/ticket, 2.633/pack/30d); WWXRP rigged tables recomputed to EV=100 each; `P(S9)` byte-identical rigged-vs-honest.

---

## Carry items (non-blocking, off-chain or optional)

- Indexer parity: `FoilMatchClaimed.tier` value domain changed `{2,3,4}` → `{4..8}` with the Variant-2 rescore — the indexer must re-vendor (additive, off-chain).
- Doc reconciliation: `REQUIREMENTS.md` MATCH-01 ("signatures frozen at buy") / MATCH-09 ("hero-free pure-VRF") and the `buyFoilPack` references reflect the pre-§V design; the as-built correctly follows §V.3/§V.8/§V.12. Code is correct; the milestone docs carry the older wording.
- Optional: a pure-math forge test pinning `Σ P(T)·face(T)` EV-byte-identity; the F-03 per-empty-day-decrement defense-in-depth.

---

*v72.0 audit — Degenerus Protocol. Subject byte-frozen at `contracts/` tree `4407181d` (HEAD `e94f1719`). 0 open findings.*
