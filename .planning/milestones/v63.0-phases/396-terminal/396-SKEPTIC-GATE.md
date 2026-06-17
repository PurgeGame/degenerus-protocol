# 396-SKEPTIC-GATE — terminal skeptic-pass over the consolidated severities (v63.0)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Inputs:** `396-CONSOLIDATED-LEDGER.md` (Task 1, the deduped master ledger) + `396-COUNCIL-ON-REFUTED.md`
(Task 2, the council re-run — no new actionable lead, 4 refuted-HIGH confirmed refuted).
**Method (locked process rule [[feedback_skeptic_pass_before_catastrophe]]):** before any severity is locked
into the final FINDINGS document, every MED-or-above entry runs the two-lens skeptic check:
1. **Structural-protection check** — is there an existing code-level guard, cap, or identity that bounds the
   impact?
2. **3-condition EV lens** — does the path actually yield a positive-EV exploit (reachability × profitability
   × repeatability)?
This gate is the explicit clearance that the FINDINGS document (Plan 02) carries no severity above MED.

---

## 1. The MED-or-above population (post-consolidation, post-council)

| Entry | Severity | Origin | Status entering the gate |
|-------|----------|--------|---------------------------|
| **BURNIE-04** / FC-392-16 — sDGNRS auto-rebuy carry stranded from redemption backing | MED (CONFIRMED) | 392 | the sole CONFIRMED contract finding; USER-ruled REAL GAP → gated post-sweep fix |
| **BURNIE-05** / FC-392-17 — VAULT day-1-20 seed window-aging forfeiture | MED (CONFIRMED-as-risk) | 392 | USER-ruled BY-DESIGN / WONTFIX (protocol-owned VAULT) |

No other entry across 389-395 reaches MED. The 3 council HIGH candidates (ECON-04, ECON-06, SOLV-07) and the
RNG-04 INFO/LOW candidate are REFUTED (Task 2 confirms; RNG-04 codex "BREAKS" adjudicated refuted at frozen
source). The mutation net's 7 GENUINE survivors (G-BPL-01, K1-K6) are test-coverage gaps on CORRECT subject
lines, ALL KILLED-by-regression — not contract defects, not severities. R-389-01 is a LOW test-only
oracle-integrity item (contract unaffected). The remaining ~78 leads are REFUTED / BY-DESIGN / MONITOR / INFO.

---

## 2. Skeptic gate — BURNIE-04 (the sole CONFIRMED finding)

**Finding:** the sDGNRS auto-rebuy carry (`autoRebuyCarry`) accrues every post-day-20 sDGNRS coinflip win but
is invisible to `burnieOwed` (`burnieBal + previewClaimCoinflips(sDGNRS)`, StakedDegenerusStonk.sol:1029-1031;
`previewClaimCoinflips` = `_viewClaimableCoin + claimableStored`, neither reads the carry) and has no
sDGNRS-reachable liquidation path ⟹ redeemers are progressively under-credited for carry-resident BURNIE.

| Lens | Result |
|------|--------|
| **Structural-protection check** | (1) the gap is CONSERVATIVE — `base <= burnieBal + claimableBurnie`; the `redeemBurnieShare` waterfall never reverts; no over-credit; **no insolvency**. (2) BURNIE is OFF the ETH/`claimablePool` solvency spine (BURNIE-06, attested 392) — **no ETH-solvency consequence**. (3) BURNIE is rated "worthless except the near-unfarmable whale pass" ([[degenerette-wwxrp-rtp-by-design]]) — the carry-resident value's real-world worth is bounded low. (4) the design comment (BurnieCoinflip:872-879) documents the post-arming carry as "structurally zero return" to redeemers — a KNOWN structural choice. Both council models (Task 2 charge B / AREA A) independently confirm CONSERVATIVE + off the ETH spine. |
| **3-condition EV lens** | (1) reachable? YES — post-day-20, every sDGNRS win rolls to the carry. (2) **profitable for an attacker? NO** — it is an UNDER-credit of redeemers; no third party gains, no extraction; a fairness/backing-completeness defect, not an exploit. (3) value-bearing? YES (bounded) — redeemers under-credited for value the `burnieOwed` premise says is proportionally theirs; magnitude bounded by the BURNIE-worthless rating + the conservative no-insolvency property. |
| **Gate result** | **CONFIRMED-MED, NOT HIGH/CATASTROPHE.** A real backing-completeness gap (under-credit/strand), value-bearing but bounded off the ETH spine, with NO attacker profit and NO insolvency. Below the HIGH bar (no money pump, no supply break, no ETH insolvency); above INFO (real value un-accounted vs the proportional-backing premise). The USER ruled it a REAL GAP → routed to a gated, USER-hand-reviewed contract fix applied AFTER the sweeps (`392-BURNIE-04-FIX-DESIGN.md`); the subject stays byte-frozen through the audit. |

**BURNIE-04 holds at MED. Correctly NOT a HIGH/CATASTROPHE.**

---

## 3. Skeptic gate — BURNIE-05 (CONFIRMED-as-risk → USER WONTFIX)

**Finding:** the VAULT day-1-20 coinflip seed (~2M expected BURNIE) is at silent, irreversible forfeiture risk
if the VAULT owner does not claim OR arm within the first 30 resolved days — the claim clamp
`if (start < minClaimableDay) start = minClaimableDay` (minClaimableDay = latest-30) silently skips seed days
1-20 once the first claim lands at flipsClaimableDay ≥ 51. No auto-claim safety net (asymmetric vs sDGNRS).

| Lens | Result |
|------|--------|
| **Structural-protection check** | (1) the VAULT is a PROTOCOL-controlled address (deployer/operator >50.1% DGVE) — the realistic timeline is "the operator who just deployed claims/arms the seed promptly." (2) TWO escape hatches: arming before day 51 sets `minClaimableDay = autoRebuyStartDay` (escapes the clamp); a claim by day ≤ 30 captures all seed days. (3) NO third-party gain — a SELF-INFLICTED operational forfeiture, not a player-exploitable extraction. (4) BURNIE off the ETH spine. Both council models (Task 2 charge B / AREA B) independently confirm "not a player extraction path / protocol-owned VAULT operations failure mode." |
| **3-condition EV lens** | (1) reachable? YES if the VAULT owner does NOT act within 30 resolved days (no code guarantee). (2) **profitable for an attacker? NO** — no third party benefits; the seed forfeits to nobody. (3) value-bearing? YES (bounded) — ~half the seeded principal silently forfeited; bounded by the protocol-owned-address timeline + the two escape hatches. |
| **Gate result** | **CONFIRMED-as-risk MED, NOT HIGH/CATASTROPHE.** A genuine silent unrecoverable lost-emission window, but NOT an attacker exploit (no third-party gain) and off the ETH spine. **USER-ruled BY-DESIGN / WONTFIX:** the VAULT is protocol-owned and the owner will claim/arm within the window; no contract change, no KNOWN-ISSUES disclosure (operational runbook item, not a player-facing defect). Survives the gate as a documented, USER-accepted operational posture. |

**BURNIE-05 BY-DESIGN/WONTFIX survives the gate. NOT a HIGH/CATASTROPHE; not carried as an open finding.**

---

## 4. The refuted HIGH candidates — re-confirmed refuted, no resurrection without adjudication

The council-on-refuted re-run (Task 2) did NOT resurrect any of the 4 candidates as a contract finding. Per
the no-silent-resurrection rule, each is recorded here as remaining REFUTED with the gate result:

| Candidate | Council re-run result | Skeptic-gate posture |
|-----------|----------------------|----------------------|
| **ECON-04** money-pump | both models HOLDS | fails profitability — per-iteration liquid value-out < won-claimable value-in (illiquid flip-credit kicker ≈0.030·V; box sub-unity; 10-ETH/(player,level) EV cap; depth-1 recirc). REMAINS REFUTED. |
| **ECON-06** streak-pump | both models HOLDS | fails reachability — afking slot-0 streak-neutral + `completionMask` dedup + mutually-exclusive compute block the double-channel; fixed ceilings make a transient over-count a ramp-SPEED matter, not a ceiling breach. REMAINS REFUTED. |
| **SOLV-07** whalePassCost double-credit | both models HOLDS | fails reachability — `paidDailyEth` includes `wpSpent` (JackpotModule:1214-1215); `whalePassCost` credited to futurePrizePool once; single-counted. Even hypothetically a conservative pool over-reservation outside the `claimablePool` identity, not an underbacked payout. REMAINS REFUTED. |
| **RNG-04** cross-round seed collision | gemini HOLDS; codex BREAKS → adjudicated REFUTED at source (§3 of Task 2) | fails profitability + grindability — the `reverseFlip` nudge is committed BEFORE the base word is known (gated by `rngLockedFlag`), a blind additive offset with no targeted steer; magnitude set by independent `amount`; off the ETH spine. Benign INFO/LOW, by-design pre-reveal influence. REMAINS REFUTED. |

No refuted candidate is silently resurrected; the one council contradiction (RNG-04 codex BREAKS) was
adjudicated against frozen source with the skeptic gate before being dismissed.

---

## 5. Gate clearance

**Outcome: 0 items assert at CATASTROPHE or HIGH.** The skeptic gate confirms:
- The sole CONFIRMED contract finding (**BURNIE-04**) holds at **MED** — a conservative, off-ETH-spine
  backing-completeness under-credit with no attacker profit and no insolvency; correctly NOT HIGH/CATASTROPHE.
- **BURNIE-05** (CONFIRMED-as-risk) holds at MED and is USER-ruled **BY-DESIGN / WONTFIX** (protocol-owned
  operational posture) — survives the gate, not carried as an open finding.
- The 4 council-flagged refuted candidates (ECON-04 / ECON-06 / SOLV-07 / RNG-04) **remain REFUTED** after the
  fresh council pass — none reaches MED, let alone HIGH.
- The 7 mutation GENUINE survivors are KILLED-by-regression test-gaps (not severities); R-389-01 is a LOW
  test-only oracle item (contract unaffected).

**CLEARANCE: the final FINDINGS document (Plan 02) carries no severity above MED.** The highest severity is
the single CONFIRMED-MED BURNIE-04 (routed to a gated post-sweep fix); BURNIE-05 is CONFIRMED-as-risk MED
WONTFIX. No CATASTROPHE, no HIGH. The byte-frozen subject `a8b702a7` is attested unchanged throughout.
