# 396-COUNCIL-ON-REFUTED — council re-run on the refuted-HIGH candidates + pending second-sources

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before AND after the council fan-out; both contracts tree-hashes
== `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Method (the v60 LIFECYCLE lesson):** a Claude-refuted HIGH must survive a FRESH council pass before it is
dismissed in the final document. This is the council-on-refuted re-run for v63.0. Two charge sets were
dispatched via `.planning/audit-v52/cross-model/bin/council.sh` (gemini-3-pro + codex, both read-only):
- **Charge set A** — the 4 Claude-REFUTED candidates, neutrally re-charged ("here is the mechanism we
  believe is safe; find where it breaks"). Raw: `council/refuted.{gemini,codex}.txt`.
- **Charge set B** — the pending second-sources (392/393 codex usage-cap; 394 v51 gemini non-response).
  Raw: `council/secondsource.{gemini,codex}.txt`.
**Adjudication rule:** a resurfaced or new lead is NOT auto-accepted — it is traced against frozen source,
the threat model + by-design rulings applied, and recorded CONFIRMED / REFUTED with evidence.
**Posture:** AUDIT-ONLY. The council ran read-only (`--approval-mode plan` / `--sandbox read-only`); no
contract source was mutated; no stray file remains outside `council/`.

---

## 1. Council availability + byte-freeze attestation

| Model | Charge set A (refuted) | Charge set B (second-source) |
|-------|------------------------|------------------------------|
| gemini-3-pro | ON RECORD (`refuted.gemini.txt`) | ON RECORD (`secondsource.gemini.txt`) |
| codex | ON RECORD (`refuted.codex.txt`) | ON RECORD (`secondsource.codex.txt`) |

**Both models on record for BOTH charge sets** — the 392/393 codex usage-cap and the 394 v51 gemini
non-response are now BOTH RESOLVED (every pending second-source obtained, none left exhausted).

**git-status-verify after the Write-capable fan-out (T-396-01 mitigation):**
- `git diff a8b702a7 -- contracts/` — EMPTY.
- `git rev-parse a8b702a7:contracts` == `git rev-parse HEAD:contracts` == `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
- No stray file written outside `.planning/audit-v52/cross-model/396-terminal/`; the only untracked
  working-tree file is the pre-existing `PLAYER-PURCHASE-REWARDS.html` (unrelated; left untouched).

---

## 2. Charge set A — the 4 refuted-HIGH candidates

| Candidate | gemini-3 | codex | Claude adjudication vs frozen `a8b702a7` | Final |
|-----------|----------|-------|-------------------------------------------|-------|
| **ECON-04** money-pump | HOLDS | HOLDS | both models independently re-derive the refutation (illiquid flip-credit kicker, 10-ETH per-(player,level) EV cap, `allowEthSpin=false` depth-1 recirc, won-claimable value-in). No closed positive-EV liquid loop. | **REFUTED — confirmed** |
| **ECON-06** streak-pump | HOLDS | HOLDS | both re-derive `completionMask` per-slot dedup + afking slot-0 streak-neutral + mutually-exclusive `_effectiveQuestStreak` + fixed downstream ceilings. No same-day double-count; ramp-speed only, no ceiling raise. | **REFUTED — confirmed** |
| **SOLV-07** whalePassCost double-credit | HOLDS | HOLDS | both re-trace `_handleSoloBucketWinner` adding BOTH `paid` and `wpSpent` into `paidDelta` (JackpotModule:1202-1215/1218-1222) ⟹ `paidDailyEth` includes the cost ⟹ `unpaidDailyEth` excludes it; `whalePassCost` credited to futurePrizePool exactly ONCE. Single-counted. | **REFUTED — confirmed** |
| **RNG-04** cross-round seed collision | HOLDS | **BREAKS (ACTIONABLE)** | codex raised a NEW mechanism (`reverseFlip` nudge into the decimator word). Adjudicated in §3 below — **REFUTED at frozen source** (the nudge is committed strictly BEFORE the base word is known; `reverseFlip` reverts once `rngLockedFlag` is set; predictability-WITHOUT-control = by-design, documented). | **REFUTED — adjudicated (§3)** |

3 of 4 candidates: BOTH models CONFIRM the Claude refutation. The 4th (RNG-04) drew a codex "BREAKS" that
required full adjudication — see §3.

---

## 3. Adjudication of the codex RNG-04 "BREAKS" contradiction (skeptic gate, not auto-accepted)

**Codex's new mechanism:** `reverseFlip()` is a paid +1 nudge to the next RNG word (`DegenerusGame.sol:1811-1827`);
`_applyDailyRng` folds `totalFlipReversals` into the word before storing `rngWordByDay[day]`
(`modules/DegenerusGameAdvanceModule.sol:1878-1893`); that finalized word reaches `runDecimatorJackpot`
(`:958-960`) and is narrowed `uint32(rngWord)` for the claim-time lootbox seed
(`modules/DegenerusGameDecimatorModule.sol:275-277`). Codex's conclusion: "the 'no player-controllable input
into either word' premise is false" — but codex ITSELF immediately records the gating fact: "I do not find
after-reveal steering: `reverseFlip` reverts once `rngLockedFlag` is true."

**Source-anchored trace at `a8b702a7` (the adjudication):**

1. **`reverseFlip` is gated by `rngLockedFlag`** — `if (rngLockedFlag) revert RngLocked();` is the FIRST line
   of `reverseFlip` (`DegenerusGame.sol:1817`). A nudge can only be queued while RNG is UNLOCKED (before the
   VRF request is in-flight).
2. **The lock is set at VRF REQUEST time, before the word lands** — `_finalizeRngRequest` sets
   `rngWordCurrent = 0; rngLockedFlag = true;` (`AdvanceModule:1697-1699`) when the daily VRF request is made.
   From that point until `_unlockRng` (`:1781 rngLockedFlag = false`), `reverseFlip` reverts.
3. **The base word is UNKNOWN when the nudge is committed** — `rngWordCurrent` is the VRF callback output
   (`rawFulfillRandomWords` stores `rngWordCurrent = word`, `:1807`), which only arrives AFTER the request and
   only while the lock is held. `_applyDailyRng` consumes the accumulated `totalFlipReversals`, folds it into
   the freshly-delivered `rawWord`, and then ZEROES `totalFlipReversals` (`:1882-1889`). So every nudge was
   committed strictly before the base word existed on-chain.
4. **Net = predictability-WITHOUT-control over a frozen-after-commitment word.** A player can shift the final
   word by a known additive offset (`+nudges`), but cannot observe or predict the base VRF word at the time
   the nudge is paid — so the player cannot choose a TARGET outcome. This is the contract's own documented
   invariant: "Players cannot predict the base word, only influence it" (`DegenerusGame.sol:1814-1816`,
   `@dev MECHANISM`/`@dev SECURITY` natspec). It is the SAME predictability-without-control structure already
   attested for RNG-01 (every consumer binds its commitment before the word) and RNG-05.

**Skeptic gate (3-condition EV/reachability lens) on the codex mechanism:**
- (1) reachable steer to a chosen decimator outcome? **NO** — the base word is unknown at nudge time; the
  player adds a blind offset, not a targeted value. The nudge influences ALL daily-word consumers uniformly
  (not just the decimator), and the decimator winner set is already drawn from the FULL word before the uint32
  narrowing (DecimatorModule:241-269, attested RNG-02).
- (2) profitable? **NO** — no value extraction; a blind +k offset on an unknown uniform word yields another
  unknown uniform word (the additive shift of a uniform is uniform). Magnitude is still set by the claim's
  independent `amount`; the lootbox tier is off the ETH/claimablePool spine.
- (3) grindable? **NO** — once `rngLockedFlag` is set the nudge is rejected; nudges cost compounding BURNIE
  (`+50%` per nudge); no after-reveal retry exists.

**Verdict: REFUTED at frozen source.** Codex's "BREAKS" rests on the false premise of after-reveal steering,
which codex's own answer then refutes ("`reverseFlip` reverts once `rngLockedFlag` is true"). The
`reverseFlip` nudge is a documented, by-design PRE-reveal influence — not a freshness/freeze break and not a
manipulability break, because the base word is unknown at commitment. The original RNG-04 verdict stands:
the cross-round uint32 collision is benign INFO/LOW (no player control, no value extraction, off the ETH
spine). **No new actionable lead. RNG-04 remains REFUTED.**

> Cross-check: gemini independently ruled RNG-04 HOLDS in the SAME charge set, citing "no player-controllable
> inputs (like timestamp or previous block hash) enter the lootbox seed in `resolveLootboxDirect`" — the
> two council models DIVERGE on RNG-04 exactly as they did at 391 (codex raised it, gemini SOUND), and the
> frozen-source adjudication resolves it the same way: benign, by-design pre-reveal influence.

---

## 4. Charge set B — the pending second-sources (now BOTH models on record)

| Area | gemini-3 | codex | Claude adjudication vs frozen `a8b702a7` | Matches prior verdict? |
|------|----------|-------|-------------------------------------------|------------------------|
| **A — BURNIE-04** sDGNRS carry strand | DEFECT (conservative under-credit; carry stranded) | DEFECT (conservative; under-credits redeemers; off ETH/claimablePool) | Both CONFIRM the under-credit, both note it is CONSERVATIVE (no over-credit/insolvency) and OFF the ETH spine — exactly the existing CONFIRMED-MED. The USER already ruled this a REAL GAP → gated post-sweep fix (`392-BURNIE-04-FIX-DESIGN.md`). | YES — CONFIRMED-MED (the sole routed finding) |
| **B — BURNIE-05** VAULT window-aging | DEFECT (self-inflicted operational forfeiture) | DEFECT ("not a player extraction path; protocol-owned VAULT operations failure mode") | Both CONFIRM the silent seed-day-1-20 forfeiture at first-claim ≥ day 51 AND both CONFIRM it is NOT a player exploit (VAULT is protocol-owned). The USER ruled BY-DESIGN/WONTFIX (owner will claim/arm within the window). | YES — CONFIRMED-as-risk → USER WONTFIX |
| **C — ACCESS-02** keeper-bounty vs real gas | SOUND (net-negative 40x-100x; un-manufacturable) | SOUND (net-negative after flip haircut; not freely manufacturable) | Both re-derive net-negative at real gas (5-50 gwei) after the ×0.30 illiquidity AND un-manufacturability (each box requires a real burn). Both bounties (15e12 decimator / 24e12 redemption) confirmed distinct. | YES — REFUTED |
| **D — ACCESS-04** burst solvency | SOUND (Σ legs == Σ rolled == Σ released; MAX reservation covers) | SOUND (conservation holds; ETH-drain shifts the ETH/stETH mix, not the amount; fail-closed) | Both re-derive the conservation identity and the fail-closed stETH-remainder pull under the 175% MAX reservation. | YES — REFUTED |
| **E — LEGACY-03/04** bingo freeze + Pool.Reward | SOUND (bingo) / "ORPHANED" (final-day Reward path vacuous) | SOUND (bingo frozen-population read + CEI; no live jackpot final-day Pool.Reward path) | Both CONFIRM claimBingo reads a frozen population (read/write-opposite-queue + drain-before-swap) with correct tier-precedence + dedup + CEI, AND that the Pool.Reward split conserves to BPS_DENOM. Both confirm there is NO LIVE jackpot final-day Pool.Reward path — gemini's "ORPHANED" framing is the SAME vacuous-premise the LEGACY-04 verdict recorded (the old branch orphaned at v51 D-12; the solo branch credits ETH/whale-pass only). This is the already-routed doc-hygiene INFO (stale comments `JackpotModule:1047`/`:1160`), NOT a new contract defect. | YES — REFUTED (+ INFO doc-hygiene already routed) |

**Charge set B result: every pending second-source obtained; every area CONVERGES with the prior
adjudication.** No new actionable lead. BURNIE-04 second-sourced as CONFIRMED (the routed gated fix);
BURNIE-05 second-sourced as a protocol-owned operational risk (USER WONTFIX); ACCESS-02/04 + LEGACY-03/04
second-sourced as SOUND/REFUTED.

---

## 5. Net result of the council-on-refuted re-run

- **The 4 refuted-HIGH candidates remain REFUTED.** 3 (ECON-04, ECON-06, SOLV-07) confirmed by BOTH council
  models; 1 (RNG-04) drew a codex "BREAKS" that is REFUTED at frozen source (false after-reveal-steering
  premise; the nudge is a documented by-design PRE-reveal blind offset, gated by `rngLockedFlag`). No HIGH
  resurfaces.
- **No new actionable lead survives adjudication.** The only "BREAKS"/"DEFECT" verdicts the council produced
  are (a) RNG-04 — refuted at source, and (b) BURNIE-04/BURNIE-05 — the two ALREADY-known MED findings
  (one routed to a gated fix, one USER-WONTFIX). Nothing new to route to Plan 02.
- **Every pending second-source resolved.** The 392/393 codex usage-cap and the 394 v51 gemini non-response
  are both closed — both council models are now on record for every sweep area, and both converge with the
  prior verdicts.
- **The sole CONFIRMED finding stays BURNIE-04 (MED, routed gated fix).** No CATASTROPHE/HIGH asserts.

**The byte-frozen subject `a8b702a7` is verified unchanged after the fan-out** (`git diff` empty; tree-hash
`2934d3d8987a09c5f073549a0cb499f6c5f28620`). The skeptic-gate clearance is recorded in `396-SKEPTIC-GATE.md`.
