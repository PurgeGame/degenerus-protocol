# 392-FINDINGS-BURNIE — ENTROPY-AND-ECON / BURNIE-coinflip-rework adjudication (BURNIE-01..06 + owned + cross-ref leads)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after every task in this plan).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110**; the
emission-conservation anchor is the green **BurnieEmissionSeeds** invariant (5/5); the carry-settle anchor is
**CoinflipCarryClaim.t.sol** (partial / cap / loss-zeroing / compounding). The expected forge-failure
NAME-set is strictly EMPTY at this subject.
**Method:** COUNCIL + CLAUDE both (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice requires BOTH nets
on record). NET 1 = the cross-model council (**gemini on record** with two prime FINDINGS + four SOUND
verdicts; **codex SKIPPED — hard usage-limit cap**), captured in `392-02-COUNCIL-NET.md` +
`council/burnie.gemini.txt`. NET 2 = the deep Claude adversarial net, captured in `392-04-CLAUDE-NET.md` (run
independently, council leads folded after).
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-review
boundary — never fixed, never auto-committed in this phase. The subject stays byte-frozen and re-freezes only
after a gated fix boundary.
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** BURNIE is OFF the ETH/`claimablePool` solvency spine
(BURNIE-06), so a confirmed gap here is an under-credit / strand / lost-emission class, NOT ETH insolvency.
But solvency-ADJACENT backing is the SPINE CONCERN of this phase — a confirmed backing under-credit or a
lost-emission window is VALUE-BEARING; an emission over-mint or a latch double-claim is value-bearing; a
survive-before-mint violation breaks the defining invariant. The BURNIE-"worthless except the whale pass"
rating BOUNDS the magnitude (recorded), it does NOT dismiss the class.
**Design-intent anchor (§5):** survive-before-mint is the DEFINING intent; the stochastic backing-variance
trade (the old fixed 2M reserve → an 8M-stake/~4M-EV seeded flip position) is INTENDED variance — this slice
VERIFIES conservation / completeness / monotonicity / round-trip-losslessness, it does NOT re-litigate the
variance trade. Standing by-design rulings apply ([[intended-game-mechanics-not-findings]],
[[degenerette-wwxrp-rtp-by-design]], [[open-e-operator-approval-trust-boundary]]).

---

## 1. Both-nets-on-record attestation

A no-finding (REFUTED / BY-DESIGN / MONITOR) verdict for any item below cites BOTH nets. A CONFIRMED finding
likewise records both nets' convergence.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? |
|-------|-----------------|----------------|-----------------|
| BURNIE (BURNIE-01..06 + FC-392-16..20 + cross-refs FC-392-11/-12/-13) | `392-02-COUNCIL-NET.md` + `council/burnie.gemini.txt` — **gemini on record**: TWO FINDINGS landing on the exact two prime targets (PRIME-01 carry strand = BURNIE-04/FC-392-16; PRIME-02 VAULT window-aging = BURNIE-05/FC-392-17) + VERIFIED SOUND on BURNIE-01/-02/-03/-06; gemini gave NO explicit verdict on the non-prime leads (FC-392-11/-12/-13/-18/-19/-20). **codex SKIPPED** (hard usage-limit cap, recorded in `burnie.council.json` `skipped[]`). | `392-04-CLAUDE-NET.md` — independent per-item attack: the dedicated exhaustive carry-backing trace (§1), the dedicated VAULT-window determination (§2), the emission-conservation re-verification (§3), the per-source survive-before-mint enumeration (§4), the monotone-latch proof (§5), the packed-lane round-trip (§6), the loss-sequence backing model (§7), the LOW-INFO leads (§8) | ✓ both (codex-skip noted) |

**codex-skip handling (T-392-12):** a slice silently treated as on-record with BOTH CLIs unavailable would be
surfaced for re-run — that condition does NOT apply: gemini is on record with a real, substantive traced
audit (its two FINDINGS land EXACTLY on the two prime targets, not hand-waves), and NET 2 (Claude) is a full
independent net. The codex skip is documented (not silently passed). **A post-reset codex second-source re-run
of the two CONFIRMED prime backing leads (BURNIE-04/FC-392-16, BURNIE-05/FC-392-17) is RECOMMENDED** to
second-source the CONFIRM verdicts before the gated fix boundary; carry to **396 terminal council-on-confirmed**
if codex is still capped at re-run time.

T-392-12 (a no-finding verdict without both nets, or a prime backing lead waved as "BURNIE worthless" without
the exhaustive trace): does NOT apply — both nets are on record; BURNIE-04/FC-392-16 carries the full §1
exhaustive backing trace; BURNIE-05/FC-392-17 carries the full §2 VAULT-window determination. T-392-11
(subject tampering): mitigated — `git diff a8b702a7 -- contracts/` EMPTY throughout (council ran read-only
`--approval-mode plan` / `--sandbox read-only`; NET 2 read all source via `git show a8b702a7:`; hardhat never
invoked). T-392-13 (a CONFIRMED backing gap under-weighted as "BURNIE worthless," or a HIGH tagged without the
skeptic filter): mitigated — the skeptic gate (§3) is run before any elevation, and both CONFIRMED leads are
weighted value-bearing per §4, the BURNIE-worthless rating recorded as a bound not a dismissal. T-392-14 (a
CONFIRMED finding silently fixed in-phase): does NOT apply — both CONFIRMED leads are DOCUMENTED + ROUTED
(§5), never fixed; the subject stays byte-frozen.

---

## 2. Per-item adjudication table

Verdicts: **CONFIRMED** (a real defect/risk — routed in §5) · **REFUTED** (claim attacked, holds) ·
**BY-DESIGN** (intended, sound) · **MONITOR** (no defect, carried observation). All 6 reqs + 5 owned
coinflip-burnie leads (FC-392-16..20) + 3 cross-ref backing-dynamics leads (FC-392-11/-12/-13) carry one row.
Source cites at `a8b702a7`.

### 2a. BURNIE requirements (BURNIE-01..06)

| ITEM | What it claims | NET 1 (gemini) | NET 2 (Claude) | VERDICT | Settling conservation-identity / monotone-latch / backing-trace / round-trip-bound / design-intent / cite |
|------|----------------|----------------|----------------|---------|--------------------------------------------------------------------------------------------------------|
| **BURNIE-01** | survive-a-coinflip-before-mint holds across EVERY BURNIE source | SOUND | REFUTED (per-source enum) | **REFUTED** | PER-SOURCE SURVIVE-GATE ENUMERATION: seed stakes mint only on a won day (BurnieCoinflip:481-509, loss forfeits principal); per-bet Degenerette survival flip nets `acc.burnieMint` once per bet, flushed via `mintForGame` (DegeneretteModule:771-780, flush :447); box BURNIE spins ×3 under one survival flip, mint-only (DegeneretteModule:1384-1389); normal coinflip win = same win-gated loop; keeper box bounty + afking settlement = `creditFlip` flip STAKES that must survive a LATER flip (StakedStonk:810-813; GameAfkingModule:1096); sDGNRS redemption BURNIE leg = deferred `_addDailyFlip` offset 1:1 by burn+consume (net new BURNIE = 0). FC-392-19 folds in: BURNIE bets have `betLootboxShare==0` ⇒ no box opens ⇒ no shared-seed correlation. No BURNIE mints without a survived flip. (NET 2 §4.) |
| **BURNIE-02** | emission conserved vs the removed 2M+2M; the 200k×20×2 seed sums; no over/under-emission | SOUND | REFUTED (conservation + handoff) | **REFUTED** | CONSERVATION RE-VERIFICATION (anchored on BurnieEmissionSeeds 5/5): constructor seeds days 1-20 inclusive (`d <= SEED_FLIP_DAYS`) to BOTH addresses = 200k×20×2 = **8M stake** (~4M EV) replacing 2M+2M (BurnieCoinflip:178-186); `BurnieCoin._supply` starts ZERO, no constructor mint (BurnieCoin:170-178); one epoch per `processCoinflipPayouts` call, sDGNRS auto-claimed every day so its cursor tracks `flipsClaimableDay` 1:1; seed→arm handoff off-by-one-CLEAN — `if (epoch >= SEED_FLIP_DAYS)` fires when day 20 settles AFTER day-20's win minted to wallet, `autoRebuyStartDay = lastClaim = 20`, days 21+ roll to carry (BurnieCoinflip:880/884-892). (NET 2 §3.) |
| **BURNIE-03** | the `sdgnrsAutoRebuyArmed` latch is monotonic; cannot be entered/exited to double-claim or strand | SOUND | REFUTED (monotone latch) | **REFUTED** | MONOTONE-LATCH PROOF: `sdgnrsAutoRebuyArmed` set exactly once at `epoch >= 20`, never cleared (no code path sets it false; BurnieCoinflip:175/884-889); arming gated behind the `else` of `if (sdgnrsAutoRebuyArmed)` (BurnieCoinflip:877/881); no double-mint — seed-window branch mints via `_claimCoinflipsAmount(...,true)` (:880), armed branch mints nothing (0 take-profit → no `claimableStored` bank); `setCoinflipAutoRebuy(SDGNRS,false,…)` NEVER called for sDGNRS (grep clean; no sDGNRS code, no GAME caller) so the enabled flag can't be toggled off to extract carry. FC-392-18 folds in: the `fromGame` permissive branch (BurnieCoinflip:662-668) is presently UNREACHABLE (grep-clean GAME caller) + matches baseline ([[open-e-operator-approval-trust-boundary]]). (NET 2 §5.) |
| **BURNIE-04** | `claimCoinflipCarry` accounting correct AND the redemption BURNIE backing is COMPLETE — the auto-rebuy carry is reflected in the sDGNRS redemption backing (FA-1) | **FINDING (PRIME-01)** — carry invisible to `previewClaimCoinflips`; redeemers progressively under-credited; "black hole," no liquidation path | **CONFIRMED (under-credit/strand, MED)** | **CONFIRMED (MED — backing-completeness gap; under-credit/strand)** | EXHAUSTIVE BACKING TRACE (the dedicated trace, §1 below + NET 2 §1): `burnieOwed = ((burnieBal + previewClaimCoinflips(sDGNRS)) * amount)/supply` (StakedStonk:1029-1031). (i) NEITHER `previewClaimCoinflips`=`_viewClaimableCoin`+`claimableStored` (BurnieCoinflip:971-975/1013-1064) NOR the `redeemBurnieShare` waterfall (BurnieCoinflip:940-967) reads `autoRebuyCarry`, AND no sDGNRS-reachable liquidation exists (grep-clean `claimCoinflipCarry(sDGNRS)` / `setCoinflipAutoRebuy(sDGNRS)`); (ii) CONSERVATIVE — `base <= burnieBal + claimableBurnie`, waterfall never reverts, no over-credit, no insolvency, OFF the ETH spine; (iii) STEADY STATE — `_viewClaimableCoin(sDGNRS)`=0 between resolutions (lastClaim==latest after daily auto-claim), so `burnieOwed` reflects only the HELD seed-window balance, ongoing post-seed share ≈0. The design comment (BurnieCoinflip:872-879) KNOWS the carry is "structurally zero return" to redeemers — a documented structural choice that nonetheless leaves carry value un-accounted vs the proportional-backing premise. **CONFIRMED backing-completeness gap; routed §5a.** |
| **BURNIE-05** | the VAULT seed-stakes (days 1-20) window-aging forfeiture is confirmed intended OR fixed (FA-2; ~half the seeded emission at risk; "most likely to need a contract change") | **FINDING (PRIME-02)** — VAULT day-1-20 seed silently forfeited if not claimed within 30 days; no auto-claim safety net (unlike sDGNRS) | **CONFIRMED-as-risk (lost-emission window, MED), runbook-contingent** | **CONFIRMED-as-risk (MED — lost-emission window; runbook-contingent)** | VAULT-WINDOW DETERMINATION (the dedicated determination, §2 below + NET 2 §2): for `lastClaim==0` + not-on-rebuy, `windowDays=COIN_CLAIM_FIRST_DAYS=30` and `minClaimableDay=latest-30`, `if (start<minClaimableDay) start=minClaimableDay` silently skips below-window days (BurnieCoinflip:421/433/445-447; view twin :1022-1031). If the VAULT first claims at `flipsClaimableDay>=51` then `minClaimableDay=21>20` ⇒ ALL seed days 1-20 skipped ⇒ ~2M expected emission silently forfeited. (i) NO code guarantee the VAULT claims within 30 days or is armed at deploy (only sDGNRS is auto-claimed/armed; VAULT acts via `onlyVaultOwner coinClaimCoinflips`/`coinSetAutoRebuy`, DegenerusVault:630-646, none at construction); (ii) NO auto-claim/auto-rebuy/keeper safety net for the VAULT (asymmetric vs sDGNRS); (iii) at risk IF the owner does not claim OR arm within 30 days — BUT arming before day 51 sets `minClaimableDay=autoRebuyStartDay` (BurnieCoinflip:441-444), escaping the clamp, and a claim by day≤30 captures all seed days. **CONFIRMED-as-risk: silent, irreversible, no on-chain warning; BY-DESIGN only if the deploy runbook GUARANTEES the within-30-day action (operational, not enforced). Routed §5b.** |
| **BURNIE-06** | the packed stake lanes + the 8-bit 3-state day-result round-trip losslessly; BURNIE off the ETH/`claimablePool` path | SOUND | REFUTED (round-trip + off-spine) | **REFUTED** | ROUND-TRIP BOUND + OFF-SPINE: stake lane = wei in 128-bit halves, masked read/write preserves the sibling day, `weiAmount <= uint128` (supply cap) so no lane overflow (BurnieCoinflip:1072-1085); day-result lane = 8-bit 3-state, win∈[50,156]⊂[0,255] cleanly separated by `b>=50`, NO win in [2,49] (only sub-50 fixed branch is unlucky=50), loss sentinel=1, unresolved=0 (BurnieCoinflip:1092-1106); BURNIE minted/burned only — no `claimableWinnings`/pool credit, box spins mint-only, afking a flip credit, redemption leg net-new-BURNIE=0. No lossy lane / sibling corruption / BURNIE→ETH path. (NET 2 §6.) |

### 2b. Owned coinflip-burnie leads (FC-392-16..20)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling cite |
|------|----------------|-------|-------|---------|---------------|
| **FC-392-16** | sDGNRS post-seed carry stranded from redemption backing (= BURNIE-04 FA-1) | FINDING (PRIME-01) | CONFIRMED (under-credit/strand) | **CONFIRMED (MED)** | Same as BURNIE-04: exhaustive backing trace (§1) — carry unread by `previewClaimCoinflips` + waterfall, no sDGNRS liquidation, conservative under-credit. StakedStonk:1029-1031; BurnieCoinflip:971-975/940-967. Routed §5a. |
| **FC-392-17** | VAULT seed window-aging forfeiture (= BURNIE-05 FA-2) | FINDING (PRIME-02) | CONFIRMED-as-risk (runbook-contingent) | **CONFIRMED-as-risk (MED)** | Same as BURNIE-05: VAULT-window determination (§2) — no safety net, silent forfeiture at `flipsClaimableDay>=51`, escape via claim/arm within 30 days. BurnieCoinflip:421/433/445-447; DegenerusVault:630-646. Routed §5b. |
| **FC-392-18** | `setCoinflipAutoRebuy` fromGame branch skips operator-approval for a non-zero player | (no explicit gemini verdict) | REFUTED (unreachable, matches baseline) | **REFUTED (latent, unreachable)** | `fromGame = msg.sender == GAME` arm uses the player verbatim (BurnieCoinflip:662-668), but NO in-protocol GAME module calls `setCoinflipAutoRebuy` (grep across `contracts/*.sol` = definition + VAULT/interface decls only). Presently unreachable + matches baseline (not a regression). Operator-approval IS the trust boundary ([[open-e-operator-approval-trust-boundary]]); a GAME-only latent branch is consistent with it. MONITOR-class observation. (NET 2 §5.) |
| **FC-392-19** | survival-flip seed reuses the box seed hash `hash2(rngWord, betId)` on the bet path | (no explicit gemini verdict) | REFUTED (no box on a BURNIE bet) | **REFUTED** | For BURNIE bets `betLootboxShare==0` (lootbox-share is ETH-only) ⇒ NO box opens ⇒ no observable correlation, no path mixes a BURNIE survival outcome with a box draw; `betId=++nonce` (not free), `rngWord` VRF-committed AFTER placement (no player steering). Defence-in-depth only. DegeneretteModule:773. (NET 2 §4.) |
| **FC-392-20** | claim-window widening to 365 (+1460) raises the per-claim resolution-walk gas ceiling | (no explicit gemini verdict) | INFO (bounded, caller-paid); gas → 393 | **INFO/MONITOR; gas worst-case cross-ref → 393** | `COIN_CLAIM_DAYS 90→365`, `AUTO_REBUY_OFF_CLAIM_DAYS_MAX 1095→1460`, counters `uint8→uint16` (BurnieCoinflip:136-138); deep walk `uint32 remaining` (safe for 1460), shallow `uint16` (safe for 365). Per-call + CALLER-PAID, NOT in the advanceGame chain (sDGNRS auto-settle walks ~1 day/advance). No realistic actor can force a many-hundred-day cold-SLOAD walk into a gas-sensitive caller. The fresh-gas worst-case under the new packed masked sub-word reads is owned by 393 (FC-393-04). (NET 2 §8.) |

### 2c. Cross-ref backing-dynamics leads (FC-392-11/-12/-13)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling cite |
|------|----------------|-------|-------|---------|---------------|
| **FC-392-11** | stochastic sDGNRS auto-rebuy backing — a loss sequence drops backing below obligations / a redeemer extracts mid-roll (the BACKING half; the RNG-lock half attested at 391) | (no explicit gemini verdict) | REFUTED (backing half) | **REFUTED (backing half); RNG-lock half attested at 391** | LOSS-SEQUENCE BACKING MODEL: a loss zeroes the carry (`if (rebuyActive) carry = 0`, BurnieCoinflip:512-514), but the carry is ALREADY invisible to `burnieOwed` (FC-392-16), so the loss does NOT reduce any ACCOUNTED backing — the variance couples only to the (already-stranded) carry, never to the held-balance obligations `burnieOwed` tracks. No mid-roll extraction: `redeemBurnieShare` consumes only held + `claimableStored` (BurnieCoinflip:940-967), and the RNG-lock blocks `claimCoinflipCarry` during the roll (391-FINDINGS §2c, airtight). (NET 2 §7.) |
| **FC-392-12** | seed-stake leaderboard/bounty exclusion — no path mis-credits the protocol addresses | (no explicit gemini verdict) | REFUTED (excluded) | **REFUTED** | The constructor writes seeds via direct `_setFlipStake` (BurnieCoinflip:181-182), NOT `_addDailyFlip`; `_updateTopDayBettor` (leaderboard) is reached ONLY from `_addDailyFlip` (BurnieCoinflip:617); bounty/biggest-flip records are touched only by `processCoinflipPayouts` + `_addDailyFlip` arm paths, never `_setFlipStake`. No days-1..20 seed read into a leaderboard/bounty/BAF/biggestFlipEver computation. (NET 2 §8.) |
| **FC-392-13** | `claimCoinflipCarry` settle-ordering — the take-profit `claimableStored` channel + the carry withdrawal can't double-count a single win | (no explicit gemini verdict) | REFUTED (disjoint partition) | **REFUTED** | `claimCoinflipCarry` settles FIRST via `_claimCoinflipsInternal(player,false)` which banks take-profit `reserved` into `claimableStored` and writes the final rolled `carry` (BurnieCoinflip:763/565-574), THEN withdraws ≤`amount` from `autoRebuyCarry` (BurnieCoinflip:770-777). `reserved` and rolled `carry` are DISJOINT partitions of each day's payout (`reserved=(payout/tp)*tp; carry=payout-reserved`, BurnieCoinflip:496-507) — a single win is split, never in both channels. Anchored on CoinflipCarryClaim.t.sol. (NET 2 §7.) |

---

## 3. Skeptic gate (run before any CATASTROPHE/HIGH)

**Outcome: 0 items reach CATASTROPHE/HIGH. Two items reach CONFIRMED-MED (the two prime backing leads), both
bounded off the ETH spine.** Both surface-maps + gemini found 0 HIGH on inspection. The two prime backing
leads (BURNIE-04/FC-392-16, BURNIE-05/FC-392-17) and the loss-sequence backing lead (FC-392-11) are run
through the full dual-gate (structural-protection check + 3-condition EV lens) against the FROZEN source.

### 3a. BURNIE-04 / FC-392-16 carry-backing strand — the PRIORITY dual-gate

| Gate dimension | Result |
|---|---|
| **Source pin** | `burnieOwed = ((burnieBal + previewClaimCoinflips(sDGNRS)) * amount)/supply` (StakedStonk:1029-1031); `previewClaimCoinflips` = `_viewClaimableCoin` + `claimableStored` (BurnieCoinflip:971-975), neither reads `autoRebuyCarry` (:154); the `redeemBurnieShare` waterfall consumes held + `claimableStored` only (:940-967); no caller of `claimCoinflipCarry(sDGNRS)` / `setCoinflipAutoRebuy(sDGNRS,false)` (grep clean). |
| **Structural-protection check** | (1) the gap is CONSERVATIVE — `base <= burnieBal + claimableBurnie`, the waterfall never reverts, no over-credit, no insolvency. (2) BURNIE is OFF the ETH/`claimablePool` spine (BURNIE-06) — no ETH-solvency consequence. (3) BURNIE is rated "worthless except the near-unfarmable whale pass" — the carry-resident value's real-world worth is bounded low. (4) the design comment (BurnieCoinflip:872-879) documents the post-arming carry as "structurally zero return" to redeemers — the structural choice is KNOWN. |
| **3-condition EV/reachability lens** | (1) reachable? YES — post-day-20 every sDGNRS win rolls into the carry (the PRIMARY post-seed accrual sink). (2) profitable for an attacker? NO — it is an UNDER-credit of redeemers (no third party gains; no extraction); it is a fairness/backing-completeness defect, not an exploit. (3) value-bearing? YES (bounded) — redeemers are progressively under-credited for value that the `burnieOwed` formula's own premise says is proportionally theirs; the magnitude is bounded by BURNIE's worthless-except-whale-pass rating + the conservative no-insolvency property. |
| **Gate result** | **CONFIRMED-MED, NOT HIGH.** It is a real backing-completeness gap (under-credit/strand), value-bearing but bounded off the ETH spine, with no attacker profit and no insolvency. Below the HIGH bar (no money pump, no supply break, no ETH insolvency); above INFO (real value un-accounted vs the proportional-backing premise). Routed §5a; codex second-source flagged. |

### 3b. BURNIE-05 / FC-392-17 VAULT seed window-aging — dual-gate

| Gate dimension | Result |
|---|---|
| **Source pin** | `windowDays = start==0 ? 30 : 365`; `minClaimableDay = latest - windowDays`; `if (start < minClaimableDay) start = minClaimableDay` (BurnieCoinflip:421/433/445-447); VAULT claims only via `onlyVaultOwner coinClaimCoinflips`/`coinSetAutoRebuy` (DegenerusVault:630-646); only sDGNRS auto-claimed/armed (BurnieCoinflip:877-892). |
| **Structural-protection check** | (1) the VAULT is a PROTOCOL-controlled address (deployer/operator >50.1% DGVE) — the realistic timeline is "the operator who just deployed claims the seed promptly." (2) TWO escape hatches: arming before day 51 changes `minClaimableDay=autoRebuyStartDay` (escapes the clamp); a claim by day≤30 captures all seed days. (3) NO third-party gain — this is a SELF-INFLICTED operational forfeiture, not a player-exploitable extraction. (4) BURNIE off the ETH spine. |
| **3-condition EV/reachability lens** | (1) reachable? YES if the VAULT owner does NOT act within 30 resolved days (no code guarantee, no safety net, no on-chain warning). (2) profitable for an attacker? NO — no third party benefits; the seed is forfeited to nobody. (3) value-bearing? YES (bounded) — ~half the seeded principal (~2M expected BURNIE) silently and irreversibly forfeited; a lost-emission window the threat weighting rates value-bearing, bounded by the BURNIE-worthless rating + the operational escape hatches. |
| **Gate result** | **CONFIRMED-as-risk MED, NOT HIGH.** A genuine silent unrecoverable lost-emission window with no safety net and no on-chain signal, contingent on the deploy runbook. NOT an attacker exploit (no third-party gain) and off the ETH spine, so below the HIGH bar. BY-DESIGN only if the deploy runbook GUARANTEES the within-30-day claim/arm (operational, not enforced in code). Routed §5b; codex second-source flagged. This is the lead most likely to warrant a contract change. |

### 3c. FC-392-11 loss-sequence backing — dual-gate

| Gate dimension | Result |
|---|---|
| **Source pin** | a loss zeroes the carry (`carry = 0`, BurnieCoinflip:512-514); `redeemBurnieShare` consumes held + `claimableStored` only (:940-967); `claimCoinflipCarry` RNG-lock-gated at the top (:759). |
| **Structural-protection check** | the volatile carry is ALREADY invisible to `burnieOwed` (FC-392-16), so the loss-sequence variance never touches ACCOUNTED backing; `burnieOwed` reflects the SETTLED held wallet balance, not the in-flight carry; the RNG-lock blocks mid-roll carry extraction (391 airtight). |
| **3-condition EV lens** | (1) reachable backing-below-obligations break? NO — the variance couples only to the un-accounted carry, not to the held-balance obligations. (2) profitable mid-roll extraction? NO — RNG-lock + waterfall-consumes-held-only. (3) grindable? NO. |
| **Gate result** | **NOT a finding — REFUTED.** The backing variance is confined to the already-stranded carry (which is the FC-392-16 finding, not a separate solvency break). No accounted-backing-below-obligations path; no mid-roll extraction. |

No other item reaches the elevated-attention threshold — BURNIE-01/-02/-03/-06 + FC-392-12/-13/-18/-19/-20
are REFUTED / MONITOR / INFO by both nets with source traces (§2), each a conservation / monotone-latch /
round-trip / exclusion property proven by construction, not a borderline call.

---

## 4. The two prime backing leads — settled with the full accounting (the priority adjudication)

### 4a. BURNIE-04 / FC-392-16 — carry strand: the accounting, the verdict, the routed-fix shape

**The accounting (where the value lives):** post-day-20, sDGNRS is on perpetual 0-take-profit auto-rebuy. Each
resolved day `processCoinflipPayouts` calls `_claimCoinflipsInternal(SDGNRS,false)` (BurnieCoinflip:877-878),
which rolls the day's win into `state.autoRebuyCarry` (BurnieCoinflip:496-507/571-574) and advances
`lastClaim` to the latest day (:566-568). The held wallet balance does NOT grow (wins go to carry, not the
wallet); `claimableStored` stays 0 (no take-profit). So sDGNRS's BURNIE backing splits into: (held wallet =
the days-1-20 seed-window wins, FROZEN) + (carry = all post-seed wins, GROWING). `burnieOwed` reads
`burnieBal + previewClaimCoinflips(sDGNRS)` = held + `_viewClaimableCoin` + `claimableStored` = held + 0 + 0 =
**held only** (steady state). The growing carry is accounted NOWHERE in `burnieOwed`, and no sDGNRS-reachable
path liquidates it back into held/claimable.

**Verdict: CONFIRMED (MED — backing-completeness gap; under-credit/strand).** Redeemers are progressively
under-credited for carry-resident BURNIE post-seed. Conservative (no over-credit, no insolvency, off the ETH
spine). Bounded by BURNIE's worthless-except-whale-pass rating. The design comment (BurnieCoinflip:872-879)
documents the structural choice, which is a strong BY-DESIGN signal — but the value IS proportionally owed
under the `burnieOwed` formula's own premise, so it is recorded as a CONFIRMED backing-completeness gap that
the USER may RULE BY-DESIGN at the gated boundary.

**Routed-fix shape (NOT applied — gated USER hand-review, §5a):** (a) count `autoRebuyCarry` in sDGNRS's
backing — add a `previewCoinflipCarry(sDGNRS)` read to the `claimableBurnie` term in `burnieOwed`; OR (b) add
an sDGNRS-reachable carry liquidation on the redemption path so the carry materializes before `burnieOwed` is
computed; OR (c) formally rule BY-DESIGN and record a KNOWN-ISSUES note that post-seed BURNIE redemption
backing is the held seed-window balance only (consistent with the design comment + the BURNIE-worthless
rating). The USER chooses; a fix is batched + hand-reviewed, never auto-committed.

### 4b. BURNIE-05 / FC-392-17 — VAULT window-aging: the path, the verdict, the routed-fix shape

**The path (how the seed is lost):** the VAULT seed is written identically to sDGNRS (days 1-20,
BurnieCoinflip:189-197), but ONLY sDGNRS is auto-claimed/armed by `processCoinflipPayouts`
(BurnieCoinflip:877-892). The VAULT must act via `onlyVaultOwner coinClaimCoinflips` (DegenerusVault:630-631)
or `coinSetAutoRebuy` (:645-646), neither at construction. For a first claim at `flipsClaimableDay >= 51`,
`minClaimableDay = 51-30 = 21 > 20`, and the claim clamp `if (start < minClaimableDay) start = minClaimableDay`
(BurnieCoinflip:433) silently skips every seed day 1-20 ⇒ ~2M expected emission never mints, irreversibly.

**Verdict: CONFIRMED-as-risk (MED — lost-emission window; runbook-contingent).** Silent, irreversible, no
on-chain warning, no auto-claim safety net (asymmetric vs sDGNRS). Bounded by: the VAULT is protocol-
controlled (prompt operator claim is the realistic timeline) + two escape hatches (claim by day≤30 OR arm
before day 51, the latter changing `minClaimableDay=autoRebuyStartDay` and escaping the clamp entirely). NOT
an attacker exploit (no third-party gain). BY-DESIGN only if the deploy runbook GUARANTEES the within-30-day
action — which is OPERATIONAL, not enforced in code. This is the surface map's flagged "most likely to need a
contract change."

**Routed-fix shape (NOT applied — gated USER hand-review, §5b):** (a) auto-claim the VAULT alongside sDGNRS in
`processCoinflipPayouts` during the seed window; OR (b) arm the VAULT onto auto-rebuy at deploy (mirroring the
sDGNRS day-20 arming); OR (c) widen `COIN_CLAIM_FIRST_DAYS` to cover the seed window; OR (d) accept BY-DESIGN +
add a deploy-runbook MUST ("claim or arm the VAULT coinflip within 30 days of deploy"). The USER chooses; a
fix is batched + hand-reviewed, never auto-committed.

---

## 5. Routing — CONFIRMED findings + carried INFO/MONITOR

### 5a. CONFIRMED contract finding #1 — BURNIE-04 / FC-392-16 carry strand (CONTRACT-CHANGE-CANDIDATE / ROUTED)

- **Finding:** the sDGNRS auto-rebuy carry is invisible to `burnieOwed` and has no sDGNRS-reachable
  liquidation path ⇒ redeemers are progressively under-credited for carry-resident BURNIE post-seed.
- **Weight:** MED (backing-completeness gap; under-credit/strand; conservative — no over-credit/insolvency;
  off the ETH spine; bounded by the BURNIE-worthless rating). Value-bearing per §4 weighting.
- **Routed to:** a SEPARATE gated USER-hand-review boundary, BATCHED with any other v63 contract findings,
  never pre-approved, never auto-committed. The subject stays byte-frozen until that boundary; it re-freezes
  after. Fix shape options in §4a. **The USER may rule it BY-DESIGN** (the design comment documents the
  structural choice) — in which case the routing becomes a KNOWN-ISSUES/doc decision, not a contract change.
- **Second-source:** codex was capped (skip). A post-reset codex re-run is RECOMMENDED to second-source the
  CONFIRM before any fix; carry to 396.

### 5b. CONFIRMED-as-risk contract finding #2 — BURNIE-05 / FC-392-17 VAULT window-aging (CONTRACT-CHANGE-CANDIDATE / ROUTED)

- **Finding:** the VAULT day-1-20 seed (~2M expected BURNIE) is at silent, irreversible forfeiture risk if the
  VAULT owner does not claim OR arm within the first 30 resolved days; no auto-claim safety net, no on-chain
  warning (asymmetric vs sDGNRS).
- **Weight:** MED (lost-emission window; value-bearing; runbook-contingent; not an attacker exploit; off the
  ETH spine; bounded by the protocol-owned-address timeline + the two escape hatches). The lead "most likely
  to need a contract change."
- **Routed to:** a SEPARATE gated USER-hand-review boundary, BATCHED, never pre-approved, never auto-committed.
  Fix shape options in §4b (auto-claim/arm-at-deploy/widen-window/accept-BY-DESIGN-with-runbook-MUST). **The
  USER may rule it BY-DESIGN with a deploy-runbook MUST** rather than a contract change.
- **Second-source:** post-reset codex re-run RECOMMENDED; carry to 396.

### 5c. Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive)

- **FC-392-18 latent `fromGame` permissive branch (MONITOR):** unreachable (grep-clean GAME caller) + matches
  baseline; operator-approval IS the trust boundary. A future reader should NOT re-derive it as an
  access-control finding while no GAME module calls `setCoinflipAutoRebuy`.
- **FC-392-20 claim-window gas (INFO; cross-ref → 393):** bounded, caller-paid, off the advanceGame chain; the
  fresh-gas worst-case under the new packed reads is owned by 393 (FC-393-04).
- **FC-392-11 backing-dynamics (REFUTED; the RNG-lock half attested at 391):** the loss-sequence variance
  couples only to the stranded carry (which IS FC-392-16, §5a), not to accounted obligations. The RNG-lock
  half is attested at 391-FINDINGS §2c. Recorded so 392 owns the backing half.
- **codex second-source (ROUTED):** codex capped. A post-reset re-run of the two CONFIRMED prime leads is
  RECOMMENDED before the gated fix boundary; carry to 396. A coverage/second-source item, not itself a finding.

Any test-only (oracle-integrity / missing-property) gap is ROUTED, not a contract finding.

---

## 6. Re-attestation line (each req attested-or-finding)

| Req | Status at `a8b702a7` |
|-----|----------------------|
| BURNIE-01 | ATTESTED (survive-before-mint complete across every source: seeds, per-bet flip, box spins, normal mint, keeper bounty, afking, redemption leg; FC-392-19 no-box-on-BURNIE-bet) |
| BURNIE-02 | ATTESTED (emission conserved: 200k×20×2 = 8M stake / ~4M EV replaces 2M+2M; zero-start supply; seed→arm handoff off-by-one-clean; BurnieEmissionSeeds 5/5) |
| BURNIE-03 | ATTESTED (the `sdgnrsAutoRebuyArmed` latch is monotone — set once at epoch≥20, never cleared, no double-mint, no carry-extraction toggle; FC-392-18 unreachable) |
| BURNIE-04 | **FINDING (CONFIRMED MED — under-credit/strand)** — the auto-rebuy carry is NOT reflected in the sDGNRS redemption backing and has no liquidation path; conservative (no over-credit/insolvency, off the ETH spine); routed §5a (USER may rule BY-DESIGN) |
| BURNIE-05 | **FINDING (CONFIRMED-as-risk MED — lost-emission window)** — the VAULT day-1-20 seed is at silent irreversible forfeiture risk with no auto-claim safety net; runbook-contingent; routed §5b (USER may rule BY-DESIGN with a deploy-runbook MUST) |
| BURNIE-06 | ATTESTED (packed stake lane + 8-bit 3-state day-result round-trip losslessly; BURNIE off the ETH/`claimablePool` spine) |

**Verdict:** the phase-392 BURNIE/coinflip-rework surface (BURNIE-01..06 + FC-392-16..20 + cross-refs
FC-392-11/-12/-13) is adjudicated with BOTH nets on record (gemini + Claude; codex-skip documented + a
post-reset re-run flagged), the skeptic gate applied (0 HIGH; the two prime backing leads CONFIRMED-MED at the
frozen source through the dual-gate), and every item carrying an explicit verdict backed by a conservation
identity, monotone-latch proof, backing trace, round-trip bound, or design-intent cite. The two prime backing
leads are settled by dedicated rigorous treatment: BURNIE-04/FC-392-16 carry strand = CONFIRMED-MED with the
exhaustive backing trace + the conservative bound + the routed-fix shape (§4a); BURNIE-05/FC-392-17 VAULT
window-aging = CONFIRMED-as-risk-MED with the VAULT-window determination + the escape-hatch bound + the
routed-fix shape (§4b). **2 CONFIRMED contract-change-candidates (both MED, both off the ETH spine, both
runbook-/design-intent-contingent), DOCUMENTED + ROUTED to a gated USER-hand-review boundary — NOT fixed
here.** The byte-frozen subject is attested at `a8b702a7` throughout (`git diff a8b702a7 -- contracts/` EMPTY).
