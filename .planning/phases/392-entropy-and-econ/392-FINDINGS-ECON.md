# 392-FINDINGS-ECON — ENTROPY-AND-ECON / reward game-theory adjudication (ECON-01..06 + FC-392 owned ECON leads)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after every task in this plan).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110** (the expected
forge-failure NAME-set is strictly EMPTY at this subject; a regression is any failing name here).
**Method:** COUNCIL + CLAUDE both (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice requires BOTH
nets on record). NET 1 = the cross-model council (gemini on record; **codex skipped — hard usage-limit
cap**), captured in `392-01-COUNCIL-NET.md` + `council/econ.gemini.txt`. NET 2 = the deep Claude
adversarial net, captured in `392-03-CLAUDE-NET.md` (run independently, council leads folded after).
**Posture:** AUDIT-ONLY. A CONFIRMED finding is DOCUMENTED and ROUTED to a SEPARATE gated USER-hand-review
boundary — never fixed, never auto-committed in this phase. The subject stays byte-frozen and re-freezes
only after a gated fix boundary.
**Threat weighting (AUDIT-V63-PLAN §4, USER-locked):** a closed positive-EV **money pump = HIGH**; a
scarce-asset **supply break = value-bearing**; an **unbounded accrual grind = value-bearing**; a
documented-change DESIRABILITY complaint is NOT a finding. RNG/freeze = DOMINANT (391's); solvency = SPINE
(390's); access/reentrancy/MEV = LOW/confirmatory.
**Design-intent anchor (§5):** the reward rebalances are DOCUMENTED (`PAPER-REWARD-CHANGES-BRIEF.md`) —
this sweep VERIFIES the EV-neutrality / two-EV-changes claims hold in CODE, it does NOT re-litigate the
documented intent. Standing by-design rulings apply: EV>100% RTP / positive-EV lootbox+coinflip / WWXRP
worthless except the near-unfarmable whale pass / lootbox open-resolve TIMING
([[intended-game-mechanics-not-findings]], [[degenerette-wwxrp-rtp-by-design]],
[[lootbox-resolution-timing-by-design]]).

---

## 1. Both-nets-on-record attestation

A no-finding (REFUTED / BY-DESIGN / MONITOR) verdict for any item below cites BOTH nets.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? |
|-------|-----------------|----------------|-----------------|
| ECON (ECON-01..06 + FC-392-01..10 + FC-392-14/-15) | `392-01-COUNCIL-NET.md` + `council/econ.gemini.txt` — **gemini on record** (2 HIGH candidates: ECON-04 money pump + ECON-06 streak pump; VERIFIED SOUND on ECON-02/05/01). **codex SKIPPED** (hard usage-limit cap, recorded in `econ.council.json` `skipped[]` + `skip_reasons`). | `392-03-CLAUDE-NET.md` — independent per-surface bounded-accrual sweep (§1), in-code EV-neutrality arithmetic (§2), two-EV-change confirmation (§3), money-pump per-leg liquid accounting + skeptic gate (§4), whale-pass P(S=9) quant + supply-cap proof (§5), streak-machinery trace + skeptic gate (§6), the EV-cap / sentinel / affiliate leads (§7) | ✓ both (codex-skip noted) |

**codex-skip handling (T-392-02):** a slice silently treated as on-record with BOTH CLIs unavailable would
be surfaced for re-run — that condition does NOT apply: gemini is on record with a real audit, and NET 2
(Claude) is a full independent net. The codex skip is documented (not silently passed). **A post-reset
codex second-source re-run of the two HIGH candidates (ECON-04 money pump, ECON-06 streak pump) is
RECOMMENDED** to second-source NET 2's refutation; carry to **396 terminal council-on-refuted** if codex is
still capped at re-run time.

T-392-08 (a no-finding verdict without both nets, or an EV-neutrality claim attested without the in-code
arithmetic, or the money-pump search waved without a composition analysis) does NOT apply: both nets are on
record; ECON-02 carries the full coded arithmetic (§2 of NET 2); ECON-04 carries the per-leg liquid
composition accounting (§4 of NET 2). T-392-07 (subject tampering) mitigation: `git diff a8b702a7 --
contracts/` EMPTY throughout (the council ran read-only `--approval-mode plan` / `--sandbox read-only`; NET
2 read all source via `git show a8b702a7:` — hardhat never invoked). T-392-10 (a CONFIRMED finding silently
fixed in-phase) does NOT apply: 0 CONFIRMED contract findings; all carried items are DOCUMENTED + ROUTED.

---

## 2. Per-item adjudication table

Verdicts: **REFUTED** (claim attacked, holds) · **BY-DESIGN** (intended, sound) · **MONITOR** (no defect,
carried observation) · **CONFIRMED** (a real defect — routed in §4). All 6 reqs + 12 owned reward-economics
leads carry one row. Source cites at `a8b702a7`.

### 2a. ECON requirements (ECON-01..06)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling binding-cap / EV-arithmetic / saturation / supply-flag / cite |
|------|----------------|-------|-------|---------|----------------------------------------------------------------------|
| **ECON-01** | reward accrual saturates below every hard ceiling; no unbounded grind (incl. the now-uncapped quest-streak input) | SOUND (consumers saturate) | REFUTED (per-surface sweep) | **REFUTED** | BOUNDED-ACCRUAL SWEEP: total score clamped to `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` (Storage:143; clamp MintStreakUtils:349-351). Every consumer saturates BELOW it: EV multiplier at `LOOTBOX_EV_ACTIVITY_MAX_BPS = 40_000` ⇒ 14_500 bps (Storage:1629-1630) + 10-ETH/(player,level) benefit cap (Lootbox:489-512); ROI/WWXRP-high-ROI at `ACTIVITY_SCORE_MAX_BPS = 30_500`; terminal-decimator re-clamps streak to 100. The uncapped `questStreak*50` (MintStreakUtils:314) only shortens TIME-TO-CEILING (+150 vs +100 bps/day), never raises a ceiling. No unbounded grind. (NET 2 §1.) |
| **ECON-02** | EV-neutrality re-verified IN CODE per redistribution vs the documented claims | SOUND (split, 19,678, far/near) | REFUTED (full arithmetic) | **REFUTED** | IN-CODE EV ARITHMETIC: (i) split `roll%20` <8/<11/<14/<17/<19/else = **40/15/15/15/10/5** (Lootbox:1980-2049); (ii) `LOOTBOX_TICKET_ROLL_BPS = 19_678` (=16100×11/9, Lootbox:243); aggregate 0.55×16100=**8,855** == 0.45×19678=**8,855**; (iii) far/near `15_000`/`8_750` (1.5×/0.875×, Lootbox:248-249); 0.2×1.5+0.8×0.875=**1.000** exact; (iv) variance chances 1/4/20/45/30% (Lootbox:251-257), ranges symmetric about the old static value (Lootbox:263-272), Σ chance×midpoint = 0.046+0.092+0.220+0.29295+0.135 = **0.78595 == 0.786×**, drawn from the same `varianceRoll` (no extra entropy). No fat-finger / asymmetric range / non-1.0 budget. (NET 2 §2.) |
| **ECON-03** | the two genuine EV changes match documented intent IN CODE | SOUND (implicit) | REFUTED-as-divergence | **REFUTED** | TWO EV-CHANGE NUMBERS IN CODE: (i) band `LOOTBOX_EV_MIN_BPS=9_000` / `LOOTBOX_EV_NEUTRAL_BPS=10_000` @ score 6_000 / `LOOTBOX_EV_MAX_BPS=14_500` @ `LOOTBOX_EV_ACTIVITY_MAX_BPS=40_000` (Storage:1539-1547); `_lootboxEvMultiplierFromScore` linear (Storage:1619-1640). (ii) recycle gate `if (totalClaimableUsed >= priceWei * 3)` with the `spentAllClaimable` drain-detection DELETED (Mint:1740); bonus 10% unchanged (Mint:1741-1744). Both match the brief §1/§7. (NET 2 §3.) |
| **ECON-04** | NO closed positive-EV money pump across recycle/spin/recirc/carry/affiliate | **HIGH candidate** (floor 100% + 10% kicker = 110% loop) | REFUTED (per-leg liquid accounting + skeptic gate) | **REFUTED** | MONEY-PUMP COMPOSITION RESULT: per-iteration liquid accounting (NET 2 §4): the 10% recycle kicker is **illiquid BURNIE flip-credit** (`coinflip.creditFlip` → `_addDailyFlip(...,false,false)`, Mint:1741 / Coinflip:903-908) — must survive a 50/50 flip (×0.5) + the peg-vs-realizable discount (~0.59) ⇒ realized **≈0.030·V**, not 0.10·V; the box at neutral EV returns its OWN sub-unity reward components in liquid ETH (40% non-ETH: BURNIE/WWXRP/finite DGNRS pool), `_applyEvMultiplierWithCap` returns `amount` unscaled at neutral (Lootbox:483-485); the value-in `V` is **real WON claimable** (positive-variance seeded first); the presale 25% box-credit is **box-spend-restricted + presale-windowed** (Mint:1725-1727); ETH-spin recirc is **depth 1** (`allowEthSpin=false`, Degenerette:1463); the EV uplift is **10-ETH/(player,level) capped** (Lootbox:489-512). Value-out < value-in in liquid terms every iteration ⇒ no closed positive loop. Skeptic dual-gate: fails the profitability condition. The "cap doesn't cover the floor" claim is harmless (floor ≤100% is never a profit source). FC-392-06/-09 fold in (illiquid kicker bounded; box EV uplift 10-ETH-capped). (NET 2 §4.) |
| **ECON-05** | scarce-asset invariants hold — box WWXRP-spin (15% opens, S=9) stays near-unfarmable | SOUND (one-per-bracket flag) | BY-DESIGN (quantified + supply proof) | **BY-DESIGN** | WHALE-PASS QUANT + SUPPLY CAP: P(S=9) = (29/225)⁴×(1/8)⁴ ≈ **6.74e-8** per WWXRP spin (S=9 needs all 8 axes match; symbol uniform 1/8, color base-15 gold-1/15/common-2/15; `_score` Degenerette:1001-1029, `_degTrait` TraitUtils:201-224); fires on 15% of opens ⇒ ~**99M box opens per half-pass** (>> near-unfarmable bar). `betAmount >= MIN_BET_WWXRP` holds (box stakes 1 ether == MIN_BET_WWXRP, Lootbox:282/Degenerette:248/1323). Supply: the GLOBAL per-bracket flag `wwxrpJackpotWhalePassBracketAwarded[bracket]` is shared box-route (Degenerette:1325-1327) ∧ bet-route (:751-753) ⇒ **one half-pass per 10-level bracket regardless of route — no supply break** (no race: sequential SSTORE; recirc box hits the same flag). Cost-curve change only, supply intact ([[degenerette-wwxrp-rtp-by-design]]). (NET 2 §5.) |
| **ECON-06** | quest-streak (uncapped, halved) rate-bounded + decay-gated; ceiling reachable only by sustained effort | **HIGH candidate** (afking↔manual same-day double-channel) | REFUTED (machinery trace + skeptic gate) | **REFUTED** | RATE-BOUND + DECAY-GATE: `completionMask` per-day-per-slot dedup blocks a same-slot double-count (Quests:1708-1711; reset on day change :1457-1460); the afking branch makes slot-0 streak-NEUTRAL specifically to prevent the double-channel (`if (!afking)` skipped, Quests:1745-1752); `_effectiveQuestStreak` reads the manual OR the afking compute MUTUALLY-EXCLUSIVELY, never summed (Storage:2284-2293; `_afkingStreak` Storage:2257-2261); rate ≤3/day (slot 0 + slot 1 + level-quest, each once-gated); decay anchor `lastActiveDay` updated ONLY on slot-0 ⇒ miss a daily primary beyond shields ⇒ streak 0 (`_questSyncState` Quests:1428-1461). The same-day toggle is BLOCKED. FC-392-01 (level-quest +1 off the primary gate) folds in: bounded (one/level) + decay-corrected (Quests:2059-2068). Skeptic dual-gate: no double-channel; even a transient over-count is a ramp-SPEED matter (ceilings FIXED) = documented intent, not a ceiling-breach. (NET 2 §6.) |

### 2b. Owned reward-economics leads (FC-392-01..10 + FC-392-14/-15)

| ITEM | What it claims | NET 1 | NET 2 | VERDICT | Settling bound / cite |
|------|----------------|-------|-------|---------|-----------------------|
| **FC-392-01** | level-quest +1 streak not gated by the daily primary off-run; decay risk next day | (within ECON-06 SOUND) | REFUTED | **REFUTED** | `_handleLevelQuestProgress` credits +1 without updating `lastActiveDay` (Quests:2059-2068), so it is at decay risk next day; bounded one-per-level (`1<<136`); `_questSyncState` zeroes it if the daily primary is then skipped (Quests:1428-1461). Bounded + self-correcting. (NET 2 §6.) |
| **FC-392-02** | afking↔manual same-day toggle harvests both the funded-day streak and a manual +1 | (the ECON-06 HIGH) | REFUTED | **REFUTED** | The afking slot-0 streak-skip (Quests:1745) + `completionMask` dedup (Quests:1708) + mutually-exclusive `_effectiveQuestStreak` (Storage:2284) — no path counts both. The double-channel does not exist. (NET 2 §6.) |
| **FC-392-03** | faster decimator-max ramp (20× in ~33 days vs ~100) matches documented intent (VERIFY-claim) | (n/a) | BY-DESIGN | **BY-DESIGN** | The +150 vs +100 bps/day ramp reaches the decimator streak-clamp (100) ~3× faster = the documented "halve + uncap" rebalance; ceiling unchanged. VERIFY-claim confirmed. (NET 2 §7.) |
| **FC-392-04** | stale EV-band comment ("8000-13500") after the band moved to 9000-14500 (comment-only) | (n/a) | MONITOR/INFO | **MONITOR** | `_applyEvMultiplierWithCap` NatSpec still says "8000-13500" (Lootbox:472-473); the live constants (Storage:1543-1547) + `_lootboxEvMultiplierFromScore` NatSpec (Storage:1618) are correct. Comment-only staleness, no logic impact. (NET 2 §3iii.) |
| **FC-392-05** | EV-cap can be reset within a level to re-earn the uplift across composed paths (VERIFY-claim) | (n/a) | REFUTED | **REFUTED** | `lootboxEvCapPacked` keyed per (player,level), 10-ETH cap, two-window evict-smaller-level (never a live key; live set {currentLevel, currentLevel+1}) — Storage:1690-1738; all paths (redemption/direct-open/Degenerette-recirc) RMW the same packed cap via `_applyEvMultiplierWithCap` (Lootbox:474), so `used` for a live level is monotonic and cannot reset within that level. (Cursor-lag eviction edge = FC-389-01, owned by 389.) (NET 2 §7.) |
| **FC-392-06** | repeatable recycle kicker on partial spends stacks with presale 25% box-credit into a positive loop (VERIFY-claim) | (within ECON-04 HIGH) | REFUTED | **REFUTED** | Same illiquid flip-credit gate as ECON-04 (Mint:1741 → `creditFlip`); the presale box-credit is box-spend-restricted + presale-windowed (Mint:1725-1727). No positive loop. (NET 2 §4.) |
| **FC-392-07** | box WWXRP-spin lowers the cost to farm a whale half-pass (new acquisition channel; ECON-05) | SOUND (supply capped) | BY-DESIGN | **BY-DESIGN** | Same as ECON-05: P(S=9)≈6.74e-8, ~99M boxes/pass (cost intact above near-unfarmable); global per-bracket flag caps supply across all routes (Degenerette:1325 == :751). Cost-curve change, supply intact. (NET 2 §5.) |
| **FC-392-08** | redemption ETH-spin pool RMW + recirc vs solvency CEI; cap RMW raced across chunks (cross-ref 390/393) | (no explicit gemini verdict) | ECON half BY-DESIGN; solvency→390, permissionless→393 | **BY-DESIGN (ECON half); cross-ref 390/393** | ECON half: the recirc box's `_applyEvMultiplierWithCap` cap RMW funnels into the SAME packed cap (FC-392-05, monotonic within a level); the ETH-spin recirc is depth 1 (`allowEthSpin=false`, Degenerette:1463). The **solvency-CEI half** (pool RMW + dust-forfeit + `pendingRedemptionEthValue` reconciliation) is owned by **390 SOLVENCY-SPINE** (see FC-390-01/-02); the **permissionless-race half** (cap RMW raced across chunks under an adversarial claim sequence) is owned by **393 PERMISSIONLESS-COMPOSITION** (see FC-393-03). (NET 2 §4/§5.) |
| **FC-392-09** | ETH-spin "EV-equal to the tickets it replaces" routed through >100%-RTP Degenerette → realized EV > tickets (VERIFY-claim) | (within ECON-04 SOUND) | REFUTED | **REFUTED** | The aggregate box EV uplift (ETH-spin + §2 band widening + WWXRP/BURNIE conversions) is bounded by the 10-ETH per-(player,level) benefit cap (Lootbox:489-512); the >100%-RTP Degenerette routing is the documented intent ([[degenerette-wwxrp-rtp-by-design]]). Bounded, intended. (NET 2 §4.) |
| **FC-392-10** | `BOX_BETID_SENTINEL = 1<<63` could collide with a real bet nonce (event-decode correctness) | (n/a) | REFUTED/INFO | **REFUTED** | A real bet nonce reaching bit 63 needs 2^63 ≈ 9.2e18 bets — unreachable over the game lifetime; nonces increment from 1; `_boxBetId` ORs the sentinel (Degenerette:1257/1268). Event-decode stays correct. (NET 2 §7.) |
| **FC-392-14** | self-referral / circular-code routes upline slices back to the sender, or steers the no-referrer path to capture the 75% slice | (no explicit gemini verdict) | REFUTED | **REFUTED** | `payAffiliate` GAME-only (Affiliate:418); self-referral `resolved == sender ⇒ VAULT 0% kickback` (Affiliate:439-444); the 75/20/5 winner-takes-all is intra-upline-chain (buyer never in the distribution); chains terminate at VAULT (Affiliate:350-354); rewards illiquid flip-credit. No self-capture. (NET 2 §7.) |
| **FC-392-15** | carried v62 affiliate-score asymmetry — re-examine vs GAME-only access + 25-ether early-break | (no explicit gemini verdict) | MONITOR/INFO | **MONITOR** | `affiliateBonusPointsBest` monotonic sum, early-break at 25 ether returns the SAME clamped result (no under-count, Affiliate:720-730); GAME-only access removes the prior COIN-caller edge. The carried asymmetry candidate is unchanged by the v63 changes — no new defect. (NET 2 §7.) |

---

## 3. Skeptic gate (run before any CATASTROPHE/HIGH)

**Outcome: 0 items reach CATASTROPHE/HIGH.** Both surface-maps found 0 HIGH on inspection. NET 1 (gemini)
raised TWO HIGH candidates (ECON-04 money pump, ECON-06 streak pump) — both run through the full skeptic
dual-gate (structural-protection check + 3-condition EV/reachability lens) against the FROZEN source. Both
REFUTED at the gate. The MED-attention items (FC-392-07 whale-pass channel, FC-392-08 ECON cap-RMW half)
also get the gate.

### 3a. ECON-04 money pump (gemini HIGH candidate) — the PRIORITY dual-gate

| Gate dimension | Result |
|---|---|
| **Source pin** | recycle kicker `coinflip.creditFlip(buyer, (totalClaimableUsed*PRICE_COIN_UNIT*10)/(priceWei*100))` gated `>= priceWei*3` (Mint:1740-1745) → `_addDailyFlip(player, amount, 0, false, false)` (Coinflip:903-908); box at neutral `_applyEvMultiplierWithCap` returns `amount` unscaled (Lootbox:483-485) → §2 rolls; presale box-credit `(ticketCost+lootBoxAmount)/4` gated `!presaleOver` (Mint:1725-1727); ETH-spin recirc `allowEthSpin=false` (Degenerette:1463); 10-ETH cap (Lootbox:489-512). |
| **Structural-protection check** | (1) the kicker is illiquid BURNIE flip-credit — must survive a 50/50 flip + peg-vs-realizable discount before minting. (2) the box direct EV is sub-unity in liquid ETH (40% of value is non-ETH: BURNIE/WWXRP/finite DGNRS pool; tickets are future-level + variance-discounted). (3) the value-in is REAL WON claimable (a positive-variance event must occur first — not a free seed). (4) the presale box-credit is box-spend-restricted + presale-windowed (a discount on future boxes, not a withdrawable asset). (5) the EV uplift is 10-ETH/(player,level) capped. FIVE independent protections. |
| **3-condition EV/reachability lens** | (1) reachable? yes (recycle is a normal flow). (2) profitable? **NO** — per-iteration realized liquid value-out (< V) < value-in (V); the 0.10·V nominal kicker realizes ≈0.030·V after the flip (×0.5) + illiquidity (×~0.59); the box reshapes V into illiquid/sub-unity assets. (3) repeatable/grindable for net gain? **NO** — each iteration is liquid-value-LOSING, so iterating compounds the loss. |
| **Gate result** | **NOT a money pump — fails the profitability condition.** The gemini claim is a STRUCTURAL assertion ("the 10-ETH cap only bounds the uplift, leaving floor + bonus uncapped") that does not survive the per-leg liquid wei/value accounting: the floor (≤100%) is never a profit source, and the bonus is illiquid/flip-gated/sub-0.10·V realized. **REFUTED — no HIGH.** Routed to a recommended post-reset codex second-source (§1). |

### 3b. ECON-06 streak pump (gemini HIGH candidate) — dual-gate

| Gate dimension | Result |
|---|---|
| **Source pin** | `_questComplete` afking branch (Quests:1716/1745-1754); `completionMask` dedup (Quests:1708); `_effectiveQuestStreak` mutually-exclusive (Storage:2284-2293); `_afkingStreak` (Storage:2257-2261); decay anchor slot-0-only (Quests:1727/1751/1428-1461). |
| **Structural-protection check** | (1) `completionMask` (per-day, per-slot) blocks a same-slot double-count. (2) the afking branch makes slot-0 streak-NEUTRAL specifically to prevent the double-channel. (3) the manual streak and the afking compute are mutually exclusive (never summed). (4) the decay anchor zeroes a streak that misses the daily primary. |
| **3-condition EV/reachability lens** | (1) reachable double-count? **NO** — the mask + the afking slot-0 skip block it; the same-day toggle re-completing slot 0 returns `false` (mask bit set). (2) even a hypothetical transient over-count — profitable? **NO** — every downstream ceiling is FIXED (40,000 EV / 30,500 ROI / streak-clamp-100, all < 65,534, §2a ECON-01); a faster ramp does not raise a ceiling, only time-to-ceiling = documented "halve + uncap" intent. (3) grindable? **NO** — ≤3/day, decay-gated on the daily primary. |
| **Gate result** | **NOT a rate-bound breach — the double-channel does not exist (afking slot-0 skip + mask dedup + mutually-exclusive compute).** Even if a transient over-count existed, the fixed ceilings make it a ramp-SPEED matter (documented intent), not a ceiling-breach. **REFUTED — no HIGH.** Routed to a recommended post-reset codex second-source (§1). |

### 3c. MED-attention items (no HIGH)

- **FC-392-07 whale-pass channel:** a SUPPLY break would be value-bearing — but supply is provably capped
  (the global per-bracket flag, Degenerette:1325 == :751), and the acquisition cost (~99M boxes/pass) stays
  above the near-unfarmable bar. The gate finds no value-bearing break. **BY-DESIGN.**
- **FC-392-08 ECON cap-RMW half:** the recirc cap RMW funnels into the same packed cap (monotonic within a
  level, FC-392-05); the ECON half is bounded. The solvency-CEI half (390) and the permissionless-race half
  (393) are cross-ref'd, not adjudicated here. No ECON HIGH.

No other item reaches the elevated-attention threshold — each is a bounded-accrual / EV-neutral /
supply-cap / decay-gate property proven by construction with a source trace (§2), not a borderline EV call.

---

## 4. Routing — CONFIRMED findings + carried INFO/MONITOR

### 4a. CONFIRMED contract findings

**0 CONFIRMED contract-source findings.** ECON-01..06, FC-392-01..10, and FC-392-14/-15 are all REFUTED /
BY-DESIGN / MONITOR against `a8b702a7` with BOTH nets on record. The two gemini HIGH candidates (ECON-04
money pump, ECON-06 streak pump) are REFUTED at the frozen source through the skeptic dual-gate (§3a/§3b).
The byte-frozen subject is attested document-only at `a8b702a7`. **0 CONFIRMED — document-only; ECON-01..06
attested at a8b702a7.**

### 4b. Carried INFO / MONITOR (no contract change; recorded so a future reader doesn't re-derive)

- **FC-392-04 stale EV-band comment (MONITOR/INFO):** `_applyEvMultiplierWithCap` NatSpec at Lootbox:472-473
  still says "8000-13500" after the band moved to 9000-14500. The live constants + `_lootboxEvMultiplierFromScore`
  NatSpec are correct. A future comment-hygiene pass MAY correct it (comment-only, off the contract-commit
  hard floor per [[feedback_no_full_suite_for_small_changes]] / [[feedback-no-rebuild-for-comment-edits]]);
  it is NOT a logic finding and NOT in KNOWN-ISSUES (intended mechanic visibility).
- **FC-392-03 documented decimator-ramp (BY-DESIGN, carried):** the faster ~33-day decimator-max ramp is the
  documented "halve + uncap" intent; ceiling unchanged. A future reader should NOT re-derive it as an
  accrual finding.
- **FC-392-15 carried v62 affiliate-score asymmetry (MONITOR):** unchanged by the v63 GAME-only-access +
  25-ether early-break changes; no new defect. The carried candidate's disposition is unchanged.
- **FC-392-08 cross-refs:** the **solvency-CEI half → 390 SOLVENCY-SPINE** (FC-390-01/-02: redemption-claim
  liveness gate + dust-forfeit self-credit); the **permissionless-race half → 393 PERMISSIONLESS-COMPOSITION**
  (FC-393-03: partial-balance same-block redemption-leg solvency). The ECON half (cap-RMW / EV-uplift bound)
  is BY-DESIGN here.
- **codex second-source (ROUTED):** codex was capped (hard usage-limit). A post-reset codex re-run of the two
  HIGH candidates (ECON-04, ECON-06) is RECOMMENDED to second-source NET 2's refutation; carry to **396
  terminal council-on-refuted** if still capped. This is a coverage/second-source item, NOT a contract
  finding.

Any test-only (oracle-integrity / missing-property) gap is ROUTED, not a contract finding.

---

## 5. Re-attestation line (each req attested-or-finding)

| Req | Status at `a8b702a7` |
|-----|----------------------|
| ECON-01 | ATTESTED (reward accrual saturates below every hard ceiling; the uncapped quest-streak widens no ceiling; no unbounded grind) |
| ECON-02 | ATTESTED (EV-neutrality re-verified in code: split 40/15/15/15/10/5; ×11/9=19,678 → 8,855==8,855; far/near 1.000; variance 0.78595==0.786×) |
| ECON-03 | ATTESTED (the two EV changes match documented intent in code: band 9000-14500 @ 40,000; recycle ≥3-whole-ticket, drain-detection deleted) |
| ECON-04 | ATTESTED (no closed positive-EV money pump: every composition's liquid value-out < the won-claimable value-in; kicker illiquid/flip-gated, box sub-unity, recursion depth 1, EV uplift 10-ETH-capped) |
| ECON-05 | ATTESTED (the box WWXRP-spin whale-half-pass stays near-unfarmable: P(S=9)≈6.74e-8 / ~99M boxes-per-pass; the per-bracket flag caps supply at one per bracket across all routes) |
| ECON-06 | ATTESTED (the quest-streak is rate-bounded ≤3/day + decay-gated; the same-day afking↔manual double-channel is blocked; the ceiling is reachable only by sustained daily-primary effort) |

**Verdict:** the phase-392 ECON reward-game-theory surface (ECON-01..06 + FC-392-01..10 + FC-392-14/-15) is
adjudicated with BOTH nets on record (gemini + Claude; codex-skip documented + a post-reset re-run flagged),
the skeptic gate applied (the two gemini HIGH candidates — ECON-04 money pump + ECON-06 streak pump —
REFUTED at the frozen source through the dual-gate), and every item carrying an explicit verdict backed by a
binding cap, EV-arithmetic, saturation ceiling, supply-flag, or source-cite. The EV-neutrality is
re-verified in code against the documented claims (§2a ECON-02); the two genuine EV changes match documented
intent in code (§2a ECON-03); the money-pump search is settled by per-leg liquid accounting (§3a); the
whale-pass channel is quantified P(S=9)≈6.74e-8 / ~99M boxes-per-pass with the supply-cap proof (§2a ECON-05);
the bounded-accrual is swept per-surface (§2a ECON-01). **0 CONFIRMED contract findings.** The byte-frozen
subject is attested document-only at `a8b702a7` throughout (`git diff a8b702a7 -- contracts/` EMPTY).
