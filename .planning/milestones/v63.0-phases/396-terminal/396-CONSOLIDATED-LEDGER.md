# 396-CONSOLIDATED-LEDGER — v63.0 deduped master finding ledger (phases 389-395)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110**.
**Method (AUDIT-V63-PLAN §2):** COUNCIL + CLAUDE both — every slice carries both nets on record. NET 1 =
the cross-model council (gemini + codex via `council.sh`); NET 2 = the deep Claude adversarial net.
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED + ROUTED to a SEPARATE gated USER-hand-review
boundary, never fixed in the sweep. Standing by-design rulings (intended game mechanics, degenerette/WWXRP
RTP, lootbox-resolution timing, redemption dust-drop, operator-approval trust boundary) are recorded
BY-DESIGN and NOT re-litigated.

This is the single deduped ledger of every lead/finding raised by EITHER net across the seven sweep phases
389-395. Convergent council+Claude leads are collapsed to one "both"-tagged row. Each row carries: ID,
sweep phase, dimension, severity, net-of-origin, one-line description, final verdict, and second-source
status. The four Claude-REFUTED HIGH candidates are flagged **[396-RERUN]** as the council-on-refuted
targets for `396-COUNCIL-ON-REFUTED.md` (Task 2).

Verdict legend: **CONFIRMED** (real gap, routed) · **REFUTED** (claim attacked, holds) · **BY-DESIGN**
(intended, sound) · **WONTFIX** (USER-ruled) · **MONITOR/INFO** (carried observation, no change) ·
**KILLED** (test-gap closed by a Phase 395 regression test, not a contract defect).
Net legend: **council** (gemini/codex only) · **Claude** (NET 2 only) · **both** (convergent) ·
**mutation** (Phase 395 campaign).

---

## 1. Phase 389 — PACKING-IDENTITY (STORAGE-01..07 + GASID-01..05 + FC-389-01..09)

| ID | Dim | Sev | Net | Description | Verdict | 2nd-source |
|----|-----|-----|-----|-------------|---------|-----------|
| STORAGE-01 | storage | — | both | every narrowing width ≥ real-world max (no silent truncation) | REFUTED | gemini+codex |
| STORAGE-02 | storage | — | both | masked RMW helpers preserve co-residents (round-trip) | REFUTED | gemini+codex |
| STORAGE-03 | storage | — | both | cross-module shift/mask conventions agree by construction | REFUTED | gemini+codex |
| STORAGE-04 | storage | — | both | two-window EV-cap never evicts a live key under cursor lag (10 ETH cap not re-earnable) | REFUTED | gemini+codex |
| STORAGE-05 | storage | — | both | ABI getters preserved for privatized/packed fields | REFUTED | gemini+codex |
| STORAGE-06 | storage | LOW | both | no harness hardcodes a moved slot — 2 stale test harnesses found | **CONFIRMED (oracle-integrity, test-only)** → R-389-01 | gemini+codex |
| STORAGE-07 | storage | — | both | capBucketCounts ≤ maxTotal+4 imprecision defended (the "+4" is test-slack, not a contract property) | REFUTED | gemini+codex |
| GASID-01 | gas-id | — | both | `delegatecall(msg.data)` resolves identical selector + ABI (30/30) | REFUTED | gemini+codex |
| GASID-02 | gas-id | — | both | hash1/hash2 keccak preimages byte-identical (RNG image preserved) | REFUTED | gemini+codex |
| GASID-03 | gas-id | — | both | PriceLookup nibble-table output-identical over full domain | REFUTED | gemini+codex |
| GASID-04 | gas-id | — | both | trait-roll consolidation + `_farFutureSeed` extraction equivalent | REFUTED | gemini+codex |
| GASID-05 | gas-id | — | both | no externally-observable behavior change (output/revert/event) | REFUTED | gemini+codex |
| FC-389-01 | storage | — | both | EV-cap two-window eviction under cursor lag → 10 ETH re-earnable (= STORAGE-04) | REFUTED | gemini+codex |
| FC-389-02 | storage | — | both | sDGNRS uint96/uint128 narrowing truncates silently (solvency half → 390) | REFUTED | gemini+codex |
| FC-389-03 | storage | INFO | both | `DecEntry.burn` comment "raw" vs effective imprecision (uint128 bound holds) | MONITOR/INFO | gemini+codex |
| FC-389-04 | storage | LOW | both | test-harness slot recalibration (= STORAGE-06) | **CONFIRMED (folds to R-389-01)** | gemini+codex |
| FC-389-05 | rng | — | both | `DecClaimRound.rngWord` uint32 narrowing (equivalence half here; distribution half → 391) | REFUTED | gemini+codex |
| FC-389-06 | storage | — | Claude | EV-cap level-0 stamp collision if `level==0` (callers pass level+1) | REFUTED | — |
| FC-389-07 | storage | — | Claude | `_addLevelDgnrsClaimed` unclamped high-half (pro-rata bounded upstream) | REFUTED | — |
| FC-389-08 | storage | — | both | StakedStonk uint96/uint128 narrowing (solvency confirm → 390) | REFUTED | gemini+codex |
| FC-389-09 | gas-id | — | both | dynamic-array `msg.data` wrapper decoder-divergence corner | REFUTED | gemini+codex |

**Phase 389:** 0 CONFIRMED contract findings; 1 CONFIRMED LOW oracle-integrity TEST-harness item (R-389-01,
two stale slots: Composition `MINT_PACKED_SLOT=10` should be 9; HeroOverride JS `LOOTBOX_RNG_PACKED_SLOT=35`
should be 34 — test-only, contract unaffected). R-389-01 is closed by a Phase 395 regression assertion path
(see §7 KILLED note) and re-routed as a test-hardening item, NOT a contract change.

---

## 2. Phase 390 — SOLVENCY-SPINE (SOLV-01..07 + FC-390-01..07 + 5 inherited cross-refs)

| ID | Dim | Sev | Net | Description | Verdict | 2nd-source |
|----|-----|-----|-----|-------------|---------|-----------|
| SOLV-01 | solvency | — | both | `claimablePool == Σ claimable + Σ afking` across every changed touch | REFUTED | gemini+codex |
| SOLV-02 | solvency | — | both | sDGNRS backing identity preserved; balance + stETH ≥ obligations | REFUTED | gemini+codex |
| SOLV-03 | solvency | — | both | submit/claim conservation: ethDirect+lootboxEth+forfeitEth == released | REFUTED | gemini+codex |
| SOLV-04 | solvency | — | both | dust-forfeit self-credit always backed by value leaving sDGNRS; fail-closed | REFUTED | gemini+codex |
| SOLV-05 | solvency | — | both | redemption CLAIM liveness ordering — no strand/double-credit vs drain latch | REFUTED | gemini+codex |
| SOLV-06 | solvency | — | both | CEI / yield-surplus reentrancy closed (stETH-before-ETH; V62-03 class) | REFUTED | gemini+codex |
| **SOLV-07** | solvency | **HIGH-cand** | both (gemini HIGH lead vs codex SOUND) | JackpotModule `whalePassCost` double-credit (delta-fold completeness) | **REFUTED** (gemini premise false at source: `paidDailyEth` INCLUDES `wpSpent`) **[396-RERUN]** | codex SOUND on record; gemini lead refuted |
| FC-390-01 | solvency | — | both | claim path has no liveness gate (= SOLV-05) | REFUTED | gemini+codex |
| FC-390-02 | solvency | — | both | dust-forfeit self-credit phantom-bump risk (= SOLV-04) | REFUTED | gemini+codex |
| FC-390-03 | solvency | — | both | permissionless decimator/redemption claim + gameOver/freeze edge | REFUTED | gemini+codex |
| FC-390-04 | solvency | — | Claude | burnEth `claimValue > combined` dropped `&& claimable != 0` (wasted-call only) | REFUTED | — |
| FC-390-05 | solvency | — | Claude | gameDegeneretteBet overpay guard relocated game-side (identical) | REFUTED | — |
| FC-390-06 | solvency | — | both | keeper-bounty creditFlip issuance bounded (no unbounded BURNIE) | REFUTED | gemini+codex |
| FC-390-07 | solvency | — | both | vault deposit() removal complete; no over-mint | REFUTED | gemini+codex |
| FC-389-02/-08 | solvency | — | both | narrowing-conservation (inherited) | REFUTED (solvency half) | gemini+codex |
| FC-392-08 | solvency | — | both | redemption ETH-spin pool RMW + recirc vs CEI (solvency half) | REFUTED | gemini+codex |
| FC-393-02 | solvency | — | both | forfeit-to-self timing extractable by keeper (per-victim) | BY-DESIGN/REFUTED | gemini+codex |
| FC-393-03 | solvency | — | both | partial-balance redemption-leg solvency under same-block bursts | REFUTED | gemini+codex |

**Phase 390:** 0 CONFIRMED contract findings. The single divergent HIGH lead (SOLV-07, gemini) is REFUTED at
frozen source (codex sided SOUND); flagged **[396-RERUN]** for the council-on-refuted pass. One routed
test-hardening note (an EthSolvency redemption-leg action — oracle completeness, not a defect).

---

## 3. Phase 391 — RNG-SPINE (RNG-01..06 + FC-391-01..05 + 2 inherited cross-refs)

| ID | Dim | Sev | Net | Description | Verdict | 2nd-source |
|----|-----|-----|-----|-------------|---------|-----------|
| RNG-01 | rng | — | both | every new/changed consumer backward-traces to a word unknown at input-commitment | REFUTED | gemini+codex |
| RNG-02 | rng | — | both | decimator uint32 claim-seed: entropy floor + non-grindable + unbiased per-bucket distribution | REFUTED | gemini+codex |
| RNG-03 | rng | — | both | box-spin resolvers (WWXRP/BURNIE/ETH) one-shot + replay-safe | REFUTED | gemini+codex |
| **RNG-04** | rng | **INFO/LOW-cand** | both (codex INFO/LOW lead vs gemini SOUND) | cross-round uint32 seed collision (same player, two decimator levels) | **REFUTED as break** (benign INFO/LOW: no player control, no value extraction, off ETH spine) **[396-RERUN]** | codex raised; gemini SOUND |
| RNG-05 | rng | — | both | redemption day+1 pre-draw gate (`BurnsBlockedBeforeDailyRng`); no zero-seed grind | REFUTED | gemini+codex |
| RNG-06 | rng | — | both | every in-window SLOAD over the repacked slots is freeze-invariant | REFUTED | gemini+codex |
| FC-391-01 | rng | INFO/LOW | both | resolveLootboxDirect domain-separation; cross-round collision (= RNG-04) | REFUTED (+INFO) | codex/gemini |
| FC-391-02 | rng | — | both | box-spin replay/one-shot (= RNG-03) | REFUTED | gemini+codex |
| FC-391-03 | rng | — | both | survival-flip cross-bet accumulator can't transiently underflow | REFUTED | gemini+codex |
| FC-391-04 | rng | — | both | decimator 32-bit narrowing can't bias per-bucket reward distribution | REFUTED | gemini+codex |
| FC-391-05 | rng | — | both | redemption day-boundary `currentDayIndex()` can't diverge from `dailyIdx` | REFUTED | gemini+codex |
| FC-389-05 | rng | — | both | decimator uint32 narrowing — RNG-consumption/grind half | REFUTED | gemini+codex |
| FC-392-11 | rng | — | both | coinflip-carry RNG-lock coverage (lock airtight; backing → 392) | REFUTED (RNG-lock half) | gemini+codex |

**Phase 391:** 0 CONFIRMED contract findings — the DOMINANT class clean. The single divergence (RNG-04 codex
INFO/LOW cross-round collision vs gemini SOUND) is REFUTED-as-break, benign INFO/LOW; flagged **[396-RERUN]**.
One routed test-hardening item (a statistical distribution-property oracle — completeness, not a defect).

---

## 4. Phase 392 — ENTROPY-AND-ECON (ECON-01..06 + BURNIE-01..06 + owned + cross-ref leads)

### 4a. ECON slice (reward game-theory)

| ID | Dim | Sev | Net | Description | Verdict | 2nd-source |
|----|-----|-----|-----|-------------|---------|-----------|
| ECON-01 | econ | — | both | reward accrual saturates below every hard ceiling; uncapped quest-streak widens no ceiling | REFUTED | gemini; **codex CAPPED** |
| ECON-02 | econ | — | both | EV-neutrality re-verified in code per redistribution | REFUTED | gemini; codex CAPPED |
| ECON-03 | econ | — | both | the two genuine EV changes match documented intent in code | REFUTED | gemini; codex CAPPED |
| **ECON-04** | econ | **HIGH-cand** | both (gemini HIGH candidate) | money-pump: floor 100% + 10% recycle kicker = 110% loop | **REFUTED** (per-leg liquid accounting: kicker illiquid flip-credit ≈0.030·V; box sub-unity; 10-ETH cap) **[396-RERUN]** | gemini HIGH; **codex CAPPED → 396** |
| ECON-05 | econ | — | both | box WWXRP-spin whale-half-pass near-unfarmable (P(S=9)≈6.74e-8 / ~99M boxes/pass) | BY-DESIGN | gemini; codex CAPPED |
| **ECON-06** | econ | **HIGH-cand** | both (gemini HIGH candidate) | streak-pump: afking↔manual same-day double-channel | **REFUTED** (afking slot-0 skip + completionMask dedup + mutually-exclusive compute; ceilings fixed) **[396-RERUN]** | gemini HIGH; **codex CAPPED → 396** |
| FC-392-01 | econ | — | Claude | level-quest +1 streak decay risk (bounded + self-correcting) | REFUTED | codex CAPPED |
| FC-392-02 | econ | — | Claude | afking↔manual same-day toggle harvests both streaks (= ECON-06; double-channel absent) | REFUTED | codex CAPPED |
| FC-392-03 | econ | — | Claude | faster decimator-max ramp matches documented "halve+uncap" intent | BY-DESIGN | codex CAPPED |
| FC-392-04 | econ | INFO | Claude | stale EV-band comment "8000-13500" after band moved to 9000-14500 (comment-only) | MONITOR/INFO | codex CAPPED |
| FC-392-05 | econ | — | Claude | EV-cap reset within a level to re-earn uplift (monotonic per level) | REFUTED | codex CAPPED |
| FC-392-06 | econ | — | Claude | repeatable recycle kicker + presale 25% credit positive loop (= ECON-04) | REFUTED | codex CAPPED |
| FC-392-07 | econ | — | both | box WWXRP-spin lowers whale-pass farm cost (supply capped per bracket) | BY-DESIGN | gemini; codex CAPPED |
| FC-392-08 | econ | — | both | redemption ETH-spin cap-RMW (ECON half; solvency→390, race→393) | BY-DESIGN (ECON half) | gemini; codex CAPPED |
| FC-392-09 | econ | — | Claude | ETH-spin "EV-equal" routed through >100% RTP → realized EV > tickets (10-ETH capped) | REFUTED | codex CAPPED |
| FC-392-10 | econ | — | Claude | `BOX_BETID_SENTINEL = 1<<63` collides with a real bet nonce (unreachable) | REFUTED | codex CAPPED |
| FC-392-14 | econ | — | Claude | self-referral/circular-code captures upline slice (self-referral → VAULT 0%) | REFUTED | codex CAPPED |
| FC-392-15 | econ | INFO | Claude | carried v62 affiliate-score asymmetry (unchanged by v63; no new defect) | MONITOR | codex CAPPED |

### 4b. BURNIE slice (coinflip-seeded-emission / sDGNRS-backing)

| ID | Dim | Sev | Net | Description | Verdict | 2nd-source |
|----|-----|-----|-----|-------------|---------|-----------|
| BURNIE-01 | burnie | — | both | survive-a-coinflip-before-mint holds across every BURNIE source | REFUTED | gemini; codex CAPPED |
| BURNIE-02 | burnie | — | both | emission conserved vs removed 2M+2M; 200k×20×2 seed sums; off-by-one-clean handoff | REFUTED | gemini; codex CAPPED |
| BURNIE-03 | burnie | — | both | `sdgnrsAutoRebuyArmed` latch monotone; no double-mint / carry-extraction toggle | REFUTED | gemini; codex CAPPED |
| **BURNIE-04** | burnie | **MED** | both (gemini PRIME-01 + Claude) | sDGNRS auto-rebuy carry stranded from redemption backing (under-credit/strand; no liquidation path) | **CONFIRMED (MED)** — USER-ruled REAL GAP → gated fix designed (`392-BURNIE-04-FIX-DESIGN.md`), applied LATER post-sweep | gemini PRIME; **codex CAPPED → 396** |
| BURNIE-05 | burnie | MED | both (gemini PRIME-02 + Claude) | VAULT day-1-20 seed window-aging forfeiture (~2M expected BURNIE; no auto-claim safety net) | **CONFIRMED-as-risk MED → USER-ruled BY-DESIGN / WONTFIX** (VAULT protocol-owned; owner will claim/arm) | gemini PRIME; codex CAPPED |
| BURNIE-06 | burnie | — | both | packed stake lanes + 8-bit 3-state day-result round-trip losslessly; off ETH spine | REFUTED | gemini; codex CAPPED |
| FC-392-16 | burnie | MED | both | sDGNRS post-seed carry stranded (= BURNIE-04) | **CONFIRMED (MED)** → BURNIE-04 routed fix | gemini PRIME; codex CAPPED |
| FC-392-17 | burnie | MED | both | VAULT seed window-aging (= BURNIE-05) | CONFIRMED-as-risk → WONTFIX (USER BY-DESIGN) | gemini PRIME; codex CAPPED |
| FC-392-18 | burnie | INFO | Claude | `setCoinflipAutoRebuy` fromGame branch skips operator-approval (unreachable, matches baseline) | MONITOR (REFUTED, latent) | codex CAPPED |
| FC-392-19 | burnie | — | Claude | survival-flip seed reuses box seed hash on BURNIE bet (no box on BURNIE bet) | REFUTED | codex CAPPED |
| FC-392-20 | burnie | INFO | Claude | claim-window widening to 365 raises per-claim gas (bounded, caller-paid; gas → 393) | INFO/MONITOR | codex CAPPED |
| FC-392-11 | burnie | — | both | stochastic sDGNRS auto-rebuy backing — loss-sequence drops backing (backing half) | REFUTED | gemini; codex CAPPED |
| FC-392-12 | burnie | — | Claude | seed-stake leaderboard/bounty exclusion — no mis-credit of protocol addresses | REFUTED | codex CAPPED |
| FC-392-13 | burnie | — | Claude | `claimCoinflipCarry` settle-ordering double-count (disjoint partition) | REFUTED | codex CAPPED |

**Phase 392:** **2 CONFIRMED MED** (BURNIE-04 carry strand = USER REAL GAP routed to a gated fix; BURNIE-05
VAULT window-aging = USER BY-DESIGN/WONTFIX). 0 CONFIRMED in ECON. The two gemini ECON HIGH candidates
(ECON-04, ECON-06) REFUTED at the gate. **codex was usage-CAPPED across the whole 392 slice** → flagged
**[396-RERUN]** second-source (charge set B) for ECON-04/ECON-06 (refuted HIGH) plus the rest of the slice.

---

## 5. Phase 393 — PERMISSIONLESS-COMPOSITION (ACCESS-01..05 + FC-393-01..04 + 4 inherited cross-refs)

| ID | Dim | Sev | Net | Description | Verdict | 2nd-source |
|----|-----|-----|-----|-------------|---------|-----------|
| ACCESS-01 | access | — | both | every permissionless claim credits ONLY the beneficiary (no third-party push) | REFUTED | gemini; codex CAPPED |
| ACCESS-02 | access | — | both | keeper box-bounty net-NEGATIVE vs REAL gas + flip-credit illiquidity + un-manufacturable | REFUTED | gemini; **codex CAPPED → 396** |
| ACCESS-03 | access | — | both | forced claim-timing cannot reduce a winner's reward / steer an outcome (magnitude frozen) | BY-DESIGN/REFUTED (MONITOR) | gemini; codex CAPPED |
| ACCESS-04 | access | — | both | partial-balance redemption-leg solvency under same-block bursts | REFUTED | gemini; **codex CAPPED → 396** |
| ACCESS-05 | access | — | both | freeze/rngLocked/liveness/gameOver gates intact; reentrancy closed | REFUTED | gemini; codex CAPPED |
| FC-393-01 | access | — | both | forced-timing on the winner — adjacent-level magnitude (= ACCESS-03) | BY-DESIGN/REFUTED (MONITOR) | gemini; codex CAPPED |
| FC-393-02 | access | — | both | forfeit-to-self timing benign (per-victim extractability) | BY-DESIGN/REFUTED | gemini; codex CAPPED |
| FC-393-03 | access | — | both | partial-balance same-block burst solvency (= ACCESS-04) | REFUTED | gemini; codex CAPPED |
| FC-393-04 | access | INFO | both | widened claim-loop gas worst-case (caller-paid; off advanceGame chain) | REFUTED/INFO | gemini; codex CAPPED |
| FC-390-03 | access | — | both | mid-batch gameOver/frozen boundary (ACCESS half) | REFUTED | gemini; codex CAPPED |
| FC-390-06 | access | — | both | keeper-bounty creditFlip issuance bounded (ACCESS half) | REFUTED | gemini; codex CAPPED |
| FC-392-08 | access | — | both | redemption ETH-spin cross-chunk-race half | REFUTED | gemini; codex CAPPED |
| FC-392-20 | access | INFO | both | widened claim-loop gas fresh worst-case (= FC-393-04) | REFUTED/INFO | gemini; codex CAPPED |

**Phase 393:** 0 CONFIRMED contract findings — access/reentrancy/MEV (LOW/confirmatory) clean. Two cite-drifts
reconciled at frozen source (redemption bounty is 24e12 not 15e12; carry entry :754/mint :777). **codex
usage-CAPPED** → flagged **[396-RERUN]** second-source (charge set B) for the two substantive primes
(ACCESS-02 keeper-bounty / ACCESS-04 burst-solvency). 3 routed test-hardening items (oracle/gas completeness).

---

## 6. Phase 394 — LEGACY-DEBT (LEGACY-01..06; v50 + v51 slices)

| ID | Dim | Sev | Net | Description | Verdict | 2nd-source |
|----|-----|-----|-----|-------------|---------|-----------|
| LEGACY-01 | v50 | — | both | whale-pass O(1) deferred-claim + box-open record (value-equiv + single-shot + freeze) | REFUTED/BY-DESIGN | gemini+codex on record |
| LEGACY-02 | v50 | — | both | AFSUB validThroughLevel evict/refresh + OPEN-E + MINTDIV index alignment | REFUTED/BY-DESIGN | gemini+codex on record |
| LEGACY-03 | v51 | — | both | claimBingo color-completion / BingoModule (3-tier + dedup + freeze) | REFUTED | codex on record; **gemini SKIPPED → 396** |
| LEGACY-04 | v51 | — | both | sDGNRS Pool.Reward rebalance + jackpot final-day deletion (premise VACUOUS) | REFUTED (+1 INFO doc-hygiene) | codex on record; **gemini SKIPPED → 396** |
| LEGACY-05 | v50 | — | both | `audit/FINDINGS-v50.0.md` authored | DISCHARGED (0 actionable) | gemini+codex |
| LEGACY-06 | v51 | — | both | `audit/FINDINGS-v51.0.md` authored | DISCHARGED (0 actionable) | codex; gemini → 396 |

**Phase 394:** 0 CONFIRMED contract findings across both slices; LEGACY-05/06 deferred FINDINGS discharged.
2 INFO doc-only items (v50 stale test-comment; v51 stale code-comments `JackpotModule:1047`/`:1160`). For v50
both council models were on record (codex reset). For v51 codex on record, **gemini non-responsive** → flagged
**[396-RERUN]** second-source (charge set B).

---

## 7. Phase 395 — MUTATION (bounded campaign; mutation net)

| ID | Target | Class | Net | Description | Verdict |
|----|--------|-------|-----|-------------|---------|
| G-BPL-01 | `BitPackingLib.setPacked` | packing-identity | mutation | masked-RMW round-trip oracle gap | **KILLED-BY-TEST** (`MutationKills.t.sol`) |
| K1 | `StakedStonk` gameOver deterministic burn | solvency-spine | mutation | post-gameOver payout-identity oracle gap | **KILLED-BY-TEST** |
| K2 | `StakedStonk.burnAtGameOver` | solvency-spine | mutation | local-supply drain oracle gap | **KILLED-BY-TEST** |
| K3 | `StakedStonk.transferFromPool` (regular) | solvency | mutation | pool-credit post-condition oracle gap | **KILLED-BY-TEST** |
| K4 | `StakedStonk.transferFromPool` (self-win) | solvency | mutation | self-win-burn oracle gap | **KILLED-BY-TEST** |
| K5 | `StakedStonk.transferBetweenPools` | solvency | mutation | pool-rebalance conservation oracle gap | **KILLED-BY-TEST** |
| K6 | `StakedStonk.wrapperTransferTo` | solvency | mutation | wrapper-transfer post-condition oracle gap | **KILLED-BY-TEST** |

**Phase 395:** 7 GENUINE survivors (1 packing + 6 solvency-spine), ALL test-coverage holes on a CORRECT
subject line, ALL KILLED-BY-TEST. 0 ROUTED, 0 contract defects. 3 RNG/v63-changed modules (BurnieCoinflip,
LootboxModule, DecimatorModule) CI-deferred/resumable (their surface already exhaustively covered by the
389-394 dual-net + BURNIE-04 fix-design). The R-389-01 stale-harness item (Phase 389) is the test-only sibling
class — also a regression-oracle hardening, not a contract defect.

---

## 8. Council-on-refuted re-run targets (Task 2 input)

The four Claude-REFUTED HIGH candidates carried to `396-COUNCIL-ON-REFUTED.md` (charge set A — re-charge the
council neutrally to find where the refutation is wrong):

| Candidate | Phase | Origin net | Claude refutation premise (to be attacked) |
|-----------|-------|-----------|---------------------------------------------|
| **ECON-04** money-pump | 392 | gemini HIGH | per-iteration liquid value-out < won-claimable value-in; kicker illiquid flip-credit (×0.5×0.59), box sub-unity, 10-ETH/(player,level) cap |
| **ECON-06** streak-pump | 392 | gemini HIGH | afking slot-0 streak-skip + completionMask dedup + mutually-exclusive `_effectiveQuestStreak`; ceilings fixed (ramp-speed only) |
| **SOLV-07** whalePassCost double-credit | 390 | gemini HIGH | `paidDailyEth` INCLUDES `wpSpent` (:1214-1215) ⟹ `unpaidDailyEth` excludes it; futurePrizePool credited ONCE; single-counted |
| **RNG-04** cross-round seed collision | 391 | codex INFO/LOW | both words VRF-fixed after address commitment; magnitude set by independent `amount`; off the ETH spine; ~10⁻⁵..10⁻⁴ reachability |

Pending second-sources carried to `396-COUNCIL-ON-REFUTED.md` (charge set B):

| Carry | Phase | Reason |
|-------|-------|--------|
| codex on 392 ECON+BURNIE | 392 | codex usage-CAPPED the whole slice (ECON-04/-06 refuted HIGH + BURNIE-04/-05 CONFIRMED prime leads) |
| codex on 393 ACCESS | 393 | codex usage-CAPPED (ACCESS-02 keeper-bounty / ACCESS-04 burst-solvency primes) |
| gemini on 394 v51 | 394 | gemini non-responsive (LEGACY-03 bingo freeze / LEGACY-04 Pool.Reward) |

---

## 9. Count summary

**Total leads/findings (deduped, one row per ID across 389-395):** 89 rows
(389: 21 · 390: 18 · 391: 13 · 392: 32 · 393: 13 · 395: 7 mutation; 394's 6 LEGACY reqs; inherited cross-refs
appear once at their owning phase and are not double-counted).

**By final verdict:**
- **CONFIRMED contract finding: 1** — **BURNIE-04** (MED, sDGNRS carry strand; USER-ruled REAL GAP; routed to
  a gated post-sweep fix; fix-design `392-BURNIE-04-FIX-DESIGN.md`). **This is the sole CONFIRMED finding.**
- CONFIRMED-as-risk → WONTFIX: 1 — BURNIE-05 (VAULT window-aging; USER-ruled BY-DESIGN/WONTFIX, protocol-owned).
- CONFIRMED oracle-integrity (test-only, contract unaffected): 1 — R-389-01 (two stale test harnesses).
- KILLED-by-regression (Phase 395 mutation test-gaps, NOT contract defects): 7 — G-BPL-01, K1-K6.
- REFUTED / BY-DESIGN / MONITOR / INFO: the remainder (~78), all with both nets on record.

**By severity (contract-bearing):**
- CATASTROPHE: 0 · HIGH: 0 (the 3 council HIGH candidates — ECON-04, ECON-06, SOLV-07 — all REFUTED at the
  gate; RNG-04 INFO/LOW REFUTED-as-break) · MED: 2 (BURNIE-04 routed-fix, BURNIE-05 WONTFIX) · LOW: 1
  (R-389-01 test-only) · INFO/MONITOR: several (doc-hygiene + carried observations).

**By net:** both-nets convergent on the large majority; council-only and Claude-only leads folded once each;
mutation net contributed the 7 KILLED test-gaps. **codex usage-cap (392/393) and gemini non-response (394 v51)
are the open second-source carries** → resolved in Task 2 (`396-COUNCIL-ON-REFUTED.md`).

**CONFIRMED count = 1 (BURNIE-04).** No CATASTROPHE/HIGH asserts pre-skeptic-gate; the skeptic clearance is
recorded in `396-SKEPTIC-GATE.md` (Task 3).
