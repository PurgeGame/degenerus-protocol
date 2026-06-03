# 357-02 — Adversarial Sweep Log (v56.0 TERMINAL, AUDIT-01 SC1 adversarial-sweep half)

**Audit subject (FROZEN, CURRENT):** `c9b5d20d756f9dfc5f3b0584aae56bdfa215d8bf` (**c9b5d20d** — the FIFTH / FINAL 357 contract gate, the flat-10% pass lootbox + dead-guard refactor). The 3-skill sweep RAN against HEAD'' `61315ecd`; the subject was re-frozen at HEAD'''' `77d8bc88` by two subscribe-hardening gates (RESOLVING the slot-0 churn advisory + the D-11 level-0 gap, §B.3-addendum + §D), then at **c9b5d20d** by the FIFTH gate, which got a FOCUSED single-skill contract-auditor pass (proportionate to a contained economic + dead-code refactor — §F below) rather than a full 3-skill re-sweep.
**Baseline:** v55.0 contract HEAD `453f8073` (`MILESTONE_V55_AT_HEAD_ca3bbd32…`).
**Frozen-subject invariant:** `git diff c9b5d20d HEAD -- contracts/` is EMPTY (zero contract mutation; `DIFF_LINES: 0`). (The 3-skill sweep ran read-only against HEAD'' `61315ecd`; HEAD'''' adds the two revert-only / control-flow-only subscribe gates; c9b5d20d adds the FIFTH-gate pass refactor — §F.)

> **⚠ HEAD'''' RECONCILIATION (357-00d).** This sweep ran against HEAD'' `61315ecd` and recorded ONE armed advisory (ZDH probe 7 — the NEW-run cover-buy slot-0 double-accrue) and marked D-11 NEGATIVE-VERIFIED. Two further USER-approved gates then re-froze the subject at **HEAD'''' `77d8bc88`**: (1) **HEAD''' `7b0b2a0b`** RESOLVES the ZDH-7 slot-0 churn advisory (the `:451` `else if (s.lastAutoBoughtDay == uint24(today))` idempotency guard); (2) **HEAD'''' `77d8bc88`** closes a **D-11 LEVEL-0 PASSLESS GAP the sweep MISSED** — the sweep's D-11 probes (CA e-passforge / ZDH 9) ran only at level ≥ 1 and never exercised level 0, where `validThroughLevel < level` (`0 < 0`) was vacuously false and a funded passless EOA cleared `NoPass()`. The USER's review caught it; HEAD'''' adds the `(s.validThroughLevel == 0 || ...)` arm. **Honest disclosure: the 3-skill sweep was NEGATIVE-VERIFIED on D-11 but had a level-0 coverage gap.** The clean-closure outcome now has **THREE resolved-in-phase items** (F-356-01 + the slot-0 churn advisory + the level-0 D-11 gap), still **0 UNRESOLVED FINDING_CANDIDATE**.

> **⚠ c9b5d20d RECONCILIATION (357-00e — the FIFTH / FINAL gate).** A FIFTH USER-committed `contracts/*.sol` gate — **c9b5d20d** (the flat-10% pass lootbox on all 3 pass types replacing the presale-20%/post-10% split + 3 unreachable-guard removals + a `hasAnyLazyPass` docstring fix; `DegenerusGame.sol` 8 lines + `DegenerusGameWhaleModule.sol` −46/+25) — re-freezes the subject from HEAD'''' to **c9b5d20d**. It is a contained pass-PURCHASE economic refactor that does NOT touch the afking / advance / subscribe / affiliate surfaces or `_passHorizonOf`, so it got a **FOCUSED single-skill `/contract-auditor` pass** (proportionate to a contained economic + dead-code refactor) rather than a full 3-skill re-sweep — recorded in §F below. **4 probes (guard reachability / flat-10% solvency / dangling refs / `hasAnyLazyPass` doc) all NEGATIVE-VERIFIED, 0 FINDING_CANDIDATE** (full disposition `/tmp/sweep357/c9-auditor.md`). The clean-closure outcome is UNCHANGED — still THREE resolved-in-phase items, **0 UNRESOLVED FINDING_CANDIDATE**; the FIFTH gate adds ZERO findings (a clean refactor, NOT a finding).

---

## §A — CHARGE

### A.1 The fixed 3-skill set
The sweep ran the FIXED set per the carried decision **D-271-ADVERSARIAL-02** (held v44..v55):

| Skill | Role | Lead surface |
|-------|------|--------------|
| `/contract-auditor` | probing skill | (d) TWO-PATH OPEN + (e) the D-11/D-12 hardened gates + the advance-incentive redesign + (f) the drainAffiliateBase stub + the affiliate claim CEI |
| `/economic-analyst` | probing skill | (a) STRATEGIC SUB/UNSUB EDGE (PRIMARY) + (b) SETTLE-TIMING + (c) PRE-CREDIT-EV + the NEW bounty soft-gate keeper economy |
| `/zero-day-hunter` | probing skill | (a) STRATEGIC SUB/UNSUB EDGE (co-lead) + (e) the advance-incentive redesign / RNG-freeze spine + the D-11/D-12/D-13 gates |
| `/degen-skeptic` | **NOT a probing skill** — the dual-gate **FILTER** only | applied to every elevation (§D) |

`/degen-skeptic` is OUT as a 4th hunt; it is used ONLY as the elevation dual-gate (the skeptic FUNCTION: structural-protection lens + 3-condition EV lens). Persona fidelity for all four sourced from the dedicated `$HOME/.claude/skills/<skill>/SKILL.md` files.

### A.2 Execution path — **GENUINE PARALLEL_SUBAGENT**
The plan ran **INLINE in the main orchestrator context** (which holds the Agent/Task tool). The 3 probing skills launched as **3 concurrent background Task spawns** (one general-purpose agent per skill persona, each `model=opus`, each instructed strictly read-only against the frozen subject `61315ecd` via `git show 61315ecd:contracts/...`). This is the genuine **PARALLEL_SUBAGENT** path — NOT the HYBRID / SEQUENTIAL_MAIN_CONTEXT fallback (the executor-nested fallback was avoided exactly because a `gsd-executor` lacks the Task tool → would force the SEQUENTIAL fallback). The orchestrator then ran the best-effort XMODEL close, applied the `/degen-skeptic` dual-gate at integration time (§D), and authored this log. This mirrors the v45/314, v47/324, v48/328, v49/333, v55/352 genuine-parallel precedent.

**Recorded execution path: `PARALLEL_SUBAGENT`.**

### A.3 The v56-weighted charge (NOT a uniform re-sweep) — the 6-surface split
The deepest effort went to the genuinely-NEW v56 surfaces (per ROADMAP Phase 357 SC1 + CONTEXT D-06/D-08b). NOTE: surface (e) is the **advance-incentive REDESIGN** at HEAD'' — the old "`5cb707f2` bypass" framing is **SUPERSEDED** (the gate it bypassed, `_enforceDailyMintGate` + `MustMintToday`, was DELETED ENTIRELY at HEAD''; `advanceGame` is now PURE LIVENESS and the must-mint ladder is the non-reverting SOFT pay-gate `_bountyEligible`). The charged probe is therefore "is the premature-advance INERT / is the soft pay-gate a sound pay-predicate not a security boundary".

- **(a) STRATEGIC SUB/UNSUB EDGE (PRIMARY — `/economic-analyst` + `/zero-day-hunter` lead, the SEC-01 spine).** A churn loop (subscribe → accrue → unsub → re-subscribe) MUST NOT extract more affiliate/quest value than a steady sub. The accrued `affiliateBase` is the uplines' money that PERSISTS on unsub (forfeit-nothing-gain-nothing); the quest `pendingBurnie` is the sub's own per-delivered-day balance; the self-marking running balances make double-settle impossible (re-claim sees `affiliateBase==0`; double quest flush finds `questProgress==0`). Structural defense = the flat-7% deterministic-split PULL (no roll/seed) + the self-marking balances + the D-11/D-12 hardening; PROVEN empirically by V56SecUnmanipulable 11/11 (356-03). Re-attested ADVERSARIALLY at HEAD''.
- **(b) SETTLE-TIMING NON-EXPLOITABILITY (trivial — `/economic-analyst`).** NO seed, NO roll under the flat-7% deterministic-split pull (the C1/C2 free-option finding is MOOT — the roll is REMOVED). Exactly ONE deterministic path. Expected NEGATIVE-VERIFIED.
- **(c) PRE-CREDIT-EV INFLATION (`/economic-analyst` + `/contract-auditor`).** The first-sub-only +0..+9 head-start is USER-ACCEPTED-BY-DESIGN (the bound replaces the escrow); the activity score reads the actual streak; the per-window streak advances only on debit-DELIVERED days. Expected SAFE_BY_DESIGN.
- **(d) TWO-PATH OPEN (`/contract-auditor` lead).** The afking open (`resolveAfkingBox` / `mintBurnie`) vs human `openLootBox` + the LIVE-01 `openBoxes` valve. Probes: shared mutable-state hazard / double-open (`lastOpenedDay` monotone) / EV-cap double-draw on the shared `(player,level)` budget / `openBoxes` valve ordering + `drainAfkingBoxes` selector isolation. Structural defense = OPEN-02 + LIVE-01, PROVEN by V56AfkingGasMarginal LIVE-01 (356-06).
- **(e) THE D-11/D-12/D-13 HARDENED GATES + THE ADVANCE-INCENTIVE REDESIGN (`/contract-auditor` + `/zero-day-hunter`).** Probes: D-11 pass-gate forge/flash-bypass (subscribe reads the live horizon; the `:942` crossing re-reads); D-12 grounding fake (the immediate cover-buy must be real funded delivery); D-13 protocol-sub exemption abuse beyond the two hardcoded addresses (VAULT/SDGNRS, keyed on the un-spoofable resolved subscriber identity). CONFIRM the passless cap-occupancy + unfunded free-rider vectors are CLOSED. THE REDESIGN: is the premature-advance INERT (RNG-freeze spine)? is `_bountyEligible` a sound pay-predicate (not a security boundary)? is the Vault/sDGNRS→`mintBurnie` routing hazard-free? This materially STRENGTHENS the SEC-01 story.
- **(f) THE NEW drainAffiliateBase STUB REACHABILITY + THE AFFILIATE claim CEI (`/contract-auditor` lead, the F-356-01 fix surface).** Probes: is the new Game dispatch stub correctly AFFILIATE-only (the module guard at `:1333` runs under delegatecall, msg.sender = affiliate)? Is the affiliate `claim()` CEI sound (`drainAffiliateBase` zeroes `affiliateBase`, `recordAmount=0` → no reentrancy edge)? Any permissionless-pays-3rd-party hazard (claim mints to A/U1/U2, fine by design)? Expected NEGATIVE-VERIFIED.

### A.4 The best-effort XMODEL close (D-03 — AUGMENTATION, not a hard dependency)
Codex + Gemini were fed crafted prompts on the FULL afking system (buy STAGE / accrual / settle AND open-pass / materialize) + the F-356-01 fix surface + the D-11/D-12/D-13 hardening + the advance-incentive redesign. Their dispositions FOLD into §B/§C as an XMODEL augmentation subsection. The Claude 3-skill sweep is the PRIMARY gate; a CLI being unavailable does NOT block closure.

- **Codex — AVAILABLE, ran read-only** (`-s read-only`), exit 0, NO concrete findings in all 4 probed areas (premature advance / `_bountyEligible` soft-gate / Vault·sDGNRS `mintBurnie` routing / drainAffiliateBase stub + claim CEI). No files edited. **Folds in as augmentation.**
- **Gemini — AVAILABLE but returned an empty/malformed response** (exit 0, no usable output). Recorded **"XMODEL attempted — Gemini partial"** per D-03 (a CLI failure is NOT a blocker; the augmentation is additive assurance, the Claude sweep + Codex carry the gate).

### A.5 Known Non-Issues honored (NOT re-flagged)
The affiliate is a flat-7% deterministic-split PULL with NO roll/seed (the C1/C2 free-option is MOOT — the removed roll is NOT re-raised); affiliate/quest are BURNIE flip-credit OFF the ETH/claimablePool path (SOLVENCY-01 untouched); the first-sub +0..+9 head-start is USER-ACCEPTED-BY-DESIGN (the bound replaces the escrow); the O1/QST-05 lootbox-quest double-credit is RESOLVED (single-credit at 356-05); the operator-approval trust boundary is the consent unit (no "tricked into approving" actor); reentrancy is the USER-locked SAFE_BY_DESIGN stance (trusted contracts, CEI'd, [[threat-model-reentrancy-mev-nonissues]]); MEV is LOW/confirmatory-only (gated, timing-independent); the v44 §9d 135-anchor maximalist register is NOT live vectors. USER-LOCKED weighting: DOMINANT = RNG/freeze + solvency; HIGH = gas-DoS ONLY in the advanceGame chain (16.7M = bricked); LOW/confirmatory = access-control + reentrancy + MEV.

---

## §B — Raw per-skill output (probed against the frozen subject `61315ecd`)

### §B.1 — `/economic-analyst` (lead: STRATEGIC SUB/UNSUB EDGE + SETTLE-TIMING + PRE-CREDIT-EV + the NEW bounty soft-gate economy)

**Probe a1 — affiliate churn re-claim**
- Surface: strategic-sub/unsub.
- Finding @ 61315ecd: `affiliateBase` is the UPLINE's money, never the sub's → zero sub-side churn EV; it accrues only behind a funded debit; the drain (`drainAffiliateBase`) is an atomic read-and-zero; a duplicate sub in a `claim()` batch drains 0.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe a2 — pendingBurnie double-claim**
- Surface: strategic-sub/unsub.
- Finding: `pendingBurnie` = the sub's own per-funded-day balance; `claimAfkingBurnie` zeroes-before-credit (CEI) → a re-claim finds 0; one zeroing entrypoint, no double-settle.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe a3 — quest-streak decay-gap dodge via churn**
- Surface: strategic-sub/unsub.
- Finding: the quest-streak decay is recomputed honestly at every begin/finalize vs `currentDay`; churn cannot bridge a gap; the afking compute-on-read streak self-decays.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe a4 — re-sub cost (D-11/D-12 interaction with churn EV)**
- Surface: strategic-sub/unsub / D-11-D-12-gates.
- Finding: D-11/D-12 make each re-sub cost a held pass + a funded cover-buy → the churn EV is already ≤ steady, now strictly negative. SEC-01 spine HOLDS (churn ⊀ steady).
- Disposition: **NEGATIVE-VERIFIED**.

**Probe b — settle-timing**
- Surface: settle-timing.
- Finding: flat 75/20/5 (or 50/50) deterministic split, no roll/seed, day-invariant — exactly one path. No favorable-seed selection, no two-distribution free option.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe c — pre-credit EV**
- Surface: pre-credit-EV.
- Finding: the streak advances only on funded-delivered days; the +0..+9 head-start once/account is accepted (the bound replaces the escrow); all caps hold.
- Disposition: **SAFE_BY_DESIGN**.

**Probe N1 — bounty soft-gate liveness equilibrium (the fresh redesign surface)**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: removing the revert only INCREASES liveness; the worst case is a first-mover RACE for a time-rising prize (mult 1→2→4→6) with a hard 30-min "anyone earns" backstop — not a volunteer's dilemma.
- Disposition: **SAFE_BY_DESIGN**.

**Probe N2 — bounty monopoly / grief-by-withholding**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: a competitive race among eligibles (by design "first shot"); permissionless + free + backstop → no exclusion, no grief-by-withholding.
- Disposition: **SAFE_BY_DESIGN**.

**Probe N3 — Vault/sDGNRS self-earn bounty**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: intended; pure BURNIE `creditFlip` (`recordAmount=0`), off `claimablePool`; `onlyVaultOwner` gate; no solvency/payout distortion.
- Disposition: **SAFE_BY_DESIGN**.

**Probe N4 — eligibility-captured-before-advance same-tx flip**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: a tier flip requires a REAL paid mint or a D-12-funded subscribe; no cost-free eligibility spoof; the mechanism behaves as specified.
- Disposition: **SAFE_BY_DESIGN**.

**economic-analyst self-summary:** SOLVENCY-01 untouched (all rewards BURNIE flip-credit `recordAmount=0`). RNG-freeze not implicated (advanceGame/mintBurnie read no VRF word into a frozen open-time input; subscribe still hard-blocked under `rngLockedFlag`). 10 probes — 5 NEGATIVE-VERIFIED, 5 SAFE_BY_DESIGN, 0 FINDING_CANDIDATE. Net: ALIGNED — more live, less exploitable.

---

### §B.2 — `/contract-auditor` (lead: TWO-PATH OPEN + the D-11/D-12 gates + the advance-redesign + the drainAffiliateBase stub + the claim CEI)

**Probe d-open — double-open across paths**
- Surface: two-path-open.
- Finding @ 61315ecd: `_openAfkingBox` (`:1118`) sets `lastOpenedDay` BEFORE the resolve delegatecall (effects-first CEI); the re-check `lastOpenedDay < lastAutoBoughtDay` → skip; afking uses a separate `Sub.lastOpenedDay` from the human `boxPlayers` path.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe d-evcap — EV-cap double-draw on the shared budget**
- Surface: two-path-open.
- Finding: the afking open draws the per-level 10-ETH cap ONCE at open via `_applyEvMultiplierWithCap` (`:496`, a monotonic RMW); `_deliverAfkingBuy` never touches `lootboxEvBenefitUsedByLevel`; per-level budgets are independent by design.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe d-valve — openBoxes valve / selector isolation (LIVE-01)**
- Surface: two-path-open.
- Finding: separate cursors (`_subOpenCursor` vs `boxCursor`) + separate storage; `drainAfkingBoxes` is a distinct selector; a direct module call hits empty storage → 0; `maxCount` bounds gas.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe e1 — RNG/freeze timing via early advance (the redesign)**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: the VRF request carries NO caller entropy (fixed keyHash/subId, `numWords=1`); the word is unpredictable regardless of request timestamp; coordinator-only fulfill; `rngLockedFlag` + `_swapAndFreeze` are set ATOMICALLY in the request tx → firing the advance earlier just starts the fence earlier (strictly MORE conservative). NO entropy/freeze edge — premature-advance-inert HOLDS.
- Disposition: **SAFE_BY_DESIGN**.

**Probe e2 — compress/grief jackpot/level/same-day via early advance**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: an earlier request = resolution available earlier (better liveness); ETH ticket buys are NOT blocked (they route to the next slot); frozen actions are frozen by design; a ≤30-min-earlier window cannot change an outcome or extract value.
- Disposition: **SAFE_BY_DESIGN**.

**Probe e3 — soft-gate bypass / pre-advance eligibility capture**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: the bounty pays only when `mult>0 && eligible`; `_bountyEligible` is an anti-freeload PREFERENCE, not a security boundary; a tier-flip requires becoming a REAL paying participant (intended); the pre-advance `dailyIdx` read is the correct semantics.
- Disposition: **SAFE_BY_DESIGN**.

**Probe e4 — Vault/sDGNRS→mintBurnie routing (reentrancy / DoS)**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: the bounty BURNIE is off the ETH path (an intended perk); `creditFlip` (`:859`) is a pure ledger add — no callback/ETH → no reentrancy; only Vault/sDGNRS `gameAdvance` call `mintBurnie` (no re-enter); `NoWork()` is a benign idle (the direct `advanceGame` always exists → no DoS).
- Disposition: **NEGATIVE-VERIFIED**.

**Probe e5 — bountyEligible external view**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: a pure `bool` view for an off-chain pre-check; `isVaultOwner` is a benign DGVE view to a trusted pinned contract, cold-path-last.
- Disposition: **SAFE_BY_DESIGN**.

**Probe e-passforge — D-11/D-12 flash-bypass**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: D-11 reads real pass state (`_passHorizonOf` deity / `frozenUntilLevel` in `mintPacked_`, not flash-creatable); D-12 requires a funded day-0 buy; synchronous-check vs persistent state. The passless cap-occupancy + unfunded free-rider vectors are CLOSED (subscribe reverts both).
- Disposition: **NEGATIVE-VERIFIED**.

**Probe e-d13 — D-13 exemption identity**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: `exemptSub` keys on `subscriber == VAULT/SDGNRS` (pinned constants) on the RESOLVED subscriber (never `src`); subscribing AS that identity needs `msg.sender == VAULT` or an `operatorApproval` — un-spoofable.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe f-stub — drainAffiliateBase stub reachability**
- Surface: drainAffiliateBase-stub+claim-CEI.
- Finding: the Game stub is guard-less BUT delegatecall PRESERVES `msg.sender`; the module enforces `msg.sender == AFFILIATE` → else `NotApproved` (`:1333`); a random caller is rejected; atomic read-and-zero.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe f-cei — Affiliate claim() CEI**
- Surface: drainAffiliateBase-stub+claim-CEI.
- Finding: the drain zeroes `affiliateBase` in-loop BEFORE `creditFlip`; a dup sub drains 0; `creditFlip` is CEI-last with `recordAmount=0` (no callback); it pays the correct resolved upline; permissionless-pays-rightful-affiliate (USER-accepted).
- Disposition: **NEGATIVE-VERIFIED**.

**contract-auditor self-summary:** 12 probes — 7 NEGATIVE-VERIFIED, 5 SAFE_BY_DESIGN, 0 FINDING_CANDIDATE (all Tier 1). Premature-advance-inert HOLDS; the soft-gate is sound; the two-path open is partitioned; the stub + CEI are clean. No real issue in the new surface despite focused stress.

---

### §B.3 — `/zero-day-hunter` (STRATEGIC SUB/UNSUB co-lead + the advance-redesign / RNG-freeze spine + the D-11/D-12/D-13 gates)

**Probe 1 — premature advance freezes the affiliate leaderboard @ second-0**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding @ 61315ecd: an affiliate IS a participant → already had this power pre-redesign; the redesign only adds zero-stake non-participants. No new capability.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe 2 — early daily-RNG request to manipulate same-day jackpot/coinflip**
- Surface: D-11-D-12-gates+advance-redesign (RNG-freeze, DOMINANT).
- Finding: `_requestRng` uses `VRF_REQUEST_CONFIRMATIONS` → the word lands in a SEPARATE callback tx; `rngLockedFlag` blocks all reactive actions (buy/subscribe/sellFF) until unlock; no same-tx request+consume. RNG-freeze intact.
- Disposition: **SAFE_BY_DESIGN**.

**Probe 3 — early GAMEOVER / liveness threshold cross**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: `_livenessTriggered` is pure day-math (`currentDay - psd > 120`); an early advance cannot cross the deterministic threshold.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe 4 — eligibility-before-self-call vs a multi-day gap backfill**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: `_bountyEligible` reads the pre-advance `dailyIdx` (frozen across a stall); a multi-day stall pays multiple bounties but each is REAL keeper work to a genuinely-eligible payee; BURNIE off the ETH path.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe 5 — mintBurnie self-call / creditFlip-to-contract reentrancy**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: `creditFlip` → `_addDailyFlip` with `recordAmount=0` → a pure SSTORE, NO callback/external call; Vault/sDGNRS get a stake increment, not a call → no reentrancy.
- Disposition: **SAFE_BY_DESIGN**.

**Probe 6 — Vault/sDGNRS BURNIE faucet**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: `onlyVaultOwner`; one bounty per advance (`advanceDue` gates); BURNIE off the ETH path; intended; not farmable (`advanceDue` false after the day's advance).
- Disposition: **SAFE_BY_DESIGN**.

**Probe 7 — ADVISORY (NOT a finding): the NEW-run subscribe cover-buy double-accrues the flat 100-BURNIE slot-0 reward per churn cycle**
- Surface: strategic-sub/unsub.
- Finding: the once-per-day STAGE (`:954`) + the active-sub re-sub (`:395`) both guard `lastAutoBoughtDay`, but the NEW-run subscribe cover-buy branch (`:426-485`) guards only on the manual `done[0]` (which an afking buy never sets). A subscribe → fund-buy → cancel → subscribe loop accrues fresh `pendingBurnie` per cycle.
- **SKEPTIC EV GATE FAILS:** 100 BURNIE (= 0.1 ticket ≈ 0.001 ETH, non-extractable) vs a funded ≥0.01-ETH buy + a cancel-tx + a subscribe-tx (~400k+ gas) per cycle → **EV-NEGATIVE**; BURNIE off solvency; the 7% `affiliateBase` routes to the UPLINE, not the churner.
- **OPTIONAL HARDENING:** add `if (s.lastAutoBoughtDay == uint24(today)) { /* skip the cover-buy */ }` to the NEW-run branch (one stored-field compare, mirrors the active-sub guard at `:395`).
- Disposition: **ADVISORY → RESOLVED-AT-357 (HEAD''' `7b0b2a0b`).** Explicitly NOT a finding (EV-negative BURNIE-faucet wart). The optional hardening was SHIPPED at HEAD''' (`GameAfkingModule.sol:451` `else if (s.lastAutoBoughtDay == uint24(today)) { _setStreakBase(s, snap); }` — keep the snapshot, skip a second same-day cover-buy, no slot-0 re-accrual, `lastOpenedDay` untouched). Re-proven GREEN by `V56SubHardening::testChurnSameDayAccruesSlot0Once` (357-00d). The fix is control-flow-only / off the ETH path (SOLVENCY-01 untouched).

**Probe 8 — D-13 exemption abuse**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: keys on the compile-time VAULT/SDGNRS vs the resolved subscriber; subscribing AS them needs `operatorApprovals` which they never grant. Un-spoofable.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe 9 — D-11/D-12 pass-forge / grounding-fake**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: D-11 reads the live `_passHorizonOf` + the per-iter crossing eviction; D-12 requires a real funded buy; an unfunded leg reverts.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe 10 — premature-advance gas-DoS amplifier (HIGH lane)**
- Surface: D-11-D-12-gates+advance-redesign.
- Finding: the advance is idempotent per day (`rngWordByDay` early-return); WHO/WHEN doesn't change the per-tx 16.7M ceiling. No amplification.
- Disposition: **NEGATIVE-VERIFIED**.

**zero-day-hunter self-summary:** DOMINANT (RNG/freeze + solvency) + HIGH (advance gas-DoS) intact; SOLVENCY-01 byte-untouched. 10 probes — 6 NEGATIVE-VERIFIED, 3 SAFE_BY_DESIGN, 1 ADVISORY (EV-negative, off-solvency → RESOLVED at HEAD'''), 0 FINDING_CANDIDATE.

---

### §B.3-addendum — the D-11 LEVEL-0 PASSLESS GAP (357-00d, USER-CAUGHT — the 3-skill sweep MISSED it)

**Probe 11 (added post-sweep, 357-00d) — D-11 vacuous at level 0: a funded PASSLESS EOA cleared NoPass at level 0**

- Surface: D-11-D-12-gates (the pass-required gate boundary).
- **HONEST DISCLOSURE — a sweep coverage gap, USER-CAUGHT.** The sweep's D-11 probes (CA `e-passforge`, ZDH `9`) asserted "D-11 reads the live `_passHorizonOf` + the per-iter crossing eviction" and were marked **NEGATIVE-VERIFIED** — but they exercised D-11 only at **level ≥ 1** (the natural test setup pokes the level UP to make `validThroughLevel(0) < level` non-vacuous, e.g. `_setLevel(5)` in `V56SubHardening::testD11PasslessEoaRevertsNoPass`). **Neither the 3-skill sweep nor Codex exercised level 0.** At level 0 the original gate `if (!exemptSub && s.validThroughLevel < level)` is `0 < 0` == FALSE (vacuous), so a funded PASSLESS EOA (horizon 0) cleared `NoPass()` at level 0 and could afk through level 0 — evicted only at L1 (`1 > 0`). The 357-00b `V56SubHardening` D-11 NEGATIVE proof passed precisely because it ran at level ≥ 1; it never exercised the level-0 boundary. **The USER's review caught this on the frozen subject.**
- **Severity / scope:** a single-level (level-0-only) passless cap-occupancy slip — a funded passless EOA could occupy a sub slot for the FIRST level before being evicted at L1. Off the ETH/solvency path (D-12 still requires a funded cover-buy; the slot pays no ETH it isn't funded for); not a value-extraction vector (the affiliate base routes to the upline, the slot-0 reward is the EV-negative BURNIE wart of probe 7, now also fixed). The vector is the passless cap-occupancy the D-11 hardening was MEANT to close — so it is a genuine gap in the gate's coverage, not a new attack surface.
- **Disposition: RESOLVED-AT-357 (HEAD'''' `77d8bc88`).** The gate became `if (!exemptSub && (s.validThroughLevel == 0 || s.validThroughLevel < level)) revert NoPass();` (`GameAfkingModule.sol:372`). A zero horizon (= no pass) is now rejected at EVERY level INCLUDING 0; a real pass has horizon ≥ passLevel+99 (WhaleModule) so `== 0` rejects only the genuinely passless; deity = `type(uint24).max`; the D-13 `exemptSub` short-circuit gates the WHOLE predicate so VAULT/SDGNRS stay exempt + deity-covered. **Revert-only** (SOLVENCY-01 untouched). Re-proven GREEN by `V56SubHardening::testD11PasslessEoaRevertsNoPassAtLevelZero` (the level-0 negative) + `testD11RealPassSubscribesAtLevelZero` / `testD11DeityHolderSubscribesAtLevelZero` / `testD13VaultSdgnrsExemptAtLevelZero` (the level-0 positives), 357-00d.

---

### §B.4 — XMODEL augmentation (D-03 — best-effort cross-model close)

**Codex (read-only, `-s read-only`, exit 0) — NO concrete findings in all 4 areas. No files edited.**

- **A — premature advance:** NO ISSUE — `advanceDue` is true on a wall-clock day != `dailyIdx`; `advanceGame` requests the daily VRF but FREEZES ticket/pool state before consuming the word and uses only the fulfilled-request word; post-freeze purchases route to a pending/next-write-slot → a day-boundary cutoff, NOT a manipulable jackpot-resolution path. Refs `DegenerusGame.sol:1782`, `AdvanceModule:172/330/1274/1666`, `Storage:760/773`.
- **B — `_bountyEligible` soft-gate:** NO ISSUE — the eligibility is intentionally read before the self-call; a same-tx flip is only by making `msg.sender` a real participant first (subscribe needs a pass + a real purchase except the pinned VAULT/sDGNRS); the `dailyIdx` boundary is not bypassable (a post-reset/pre-advance mint still reads today/yesterday for the pre-read). Refs `GameAfkingModule:1228/1233/369/483`, `MintStreakUtils:32`.
- **C — Vault/sDGNRS `mintBurnie` routing:** NO ISSUE — the bounty is credited to the contract address; `creditFlip` is called by GAME (authorized), `recordAmount=0`; `NoWork()` only reverts the user crank when there is no work — it does not brick liveness. Refs `Vault:537`, `sDGNRS:425`, `GameAfkingModule:1247/1255`, `BurnieCoinflip:195/859`.
- **D — drainAffiliateBase stub + claim CEI:** NO ISSUE — the guard-less stub but delegatecall preserves the caller; the module enforces `msg.sender == AFFILIATE` before the read-and-zero; `claim()` drains atomically, dup subs drain 0, a mixed batch reverts tx-wide, the payout follows the accounting via `creditFlip`. Refs `DegenerusGame:428`, `GameAfkingModule:1332`, `Affiliate:629/654/667/693`.

**Gemini — attempted, empty/malformed response (exit 0, no usable output) → recorded PARTIAL per D-03** (a CLI failure is NOT a blocker; the Claude 3-skill sweep + Codex carry the gate).

**XMODEL net:** Codex independently corroborates the 4 redesign / fix-surface areas with NO concrete finding; it surfaces NO disposition that contradicts the Claude sweep (and did NOT independently raise the zero-day-hunter probe-7 advisory, which is consistent with its EV-negative immateriality). The augmentation is additive assurance — it does not change any Claude disposition.

---

## §C — Per-probe disposition table + Outcome summary

| Probe ID | Skill / Model | Surface | Disposition | Skeptic-filter outcome | Tier |
|----------|---------------|---------|-------------|------------------------|------|
| a1 | economic-analyst | strategic-sub/unsub | NEGATIVE-VERIFIED | n-a (not elevated) | 1 |
| a2 | economic-analyst | strategic-sub/unsub | NEGATIVE-VERIFIED | n-a | 1 |
| a3 | economic-analyst | strategic-sub/unsub | NEGATIVE-VERIFIED | n-a | 1 |
| a4 | economic-analyst | strategic-sub/unsub / D-11-D-12-gates | NEGATIVE-VERIFIED | n-a | 2 (corrob. CA e-passforge) |
| b | economic-analyst | settle-timing | NEGATIVE-VERIFIED | n-a | 1 |
| c | economic-analyst | pre-credit-EV | SAFE_BY_DESIGN | n-a (USER-accepted bound) | 1 |
| N1 | economic-analyst | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a (liveness-positive) | 2 (corrob. CA e2) |
| N2 | economic-analyst | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 1 |
| N3 | economic-analyst | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 2 (corrob. CA e4 / ZDH 6) |
| N4 | economic-analyst | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 2 (corrob. CA e3) |
| d-open | contract-auditor | two-path-open | NEGATIVE-VERIFIED | n-a | 1 |
| d-evcap | contract-auditor | two-path-open | NEGATIVE-VERIFIED | n-a | 1 |
| d-valve | contract-auditor | two-path-open (LIVE-01) | NEGATIVE-VERIFIED | n-a | 1 |
| e1 | contract-auditor | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a (premature-advance-inert) | 2 (corrob. ZDH 2 / Codex A) |
| e2 | contract-auditor | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 1 |
| e3 | contract-auditor | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 2 (corrob. Codex B) |
| e4 | contract-auditor | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 2 (corrob. ZDH 5 / Codex C) |
| e5 | contract-auditor | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 1 |
| e-passforge | contract-auditor | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 2 (corrob. ZDH 9) |
| e-d13 | contract-auditor | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 2 (corrob. ZDH 8) |
| f-stub | contract-auditor | drainAffiliateBase-stub+claim-CEI | NEGATIVE-VERIFIED | n-a | 2 (corrob. Codex D) |
| f-cei | contract-auditor | drainAffiliateBase-stub+claim-CEI | NEGATIVE-VERIFIED | n-a | 2 (corrob. Codex D) |
| 1 | zero-day-hunter | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 1 |
| 2 | zero-day-hunter | D-11-D-12-gates+advance-redesign (RNG-freeze) | SAFE_BY_DESIGN | n-a | 2 (corrob. CA e1 / Codex A) |
| 3 | zero-day-hunter | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 1 |
| 4 | zero-day-hunter | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 2 (corrob. Codex B) |
| 5 | zero-day-hunter | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 2 (corrob. CA e4) |
| 6 | zero-day-hunter | D-11-D-12-gates+advance-redesign | SAFE_BY_DESIGN | n-a | 2 (corrob. econ N3) |
| **7** | **zero-day-hunter** | **strategic-sub/unsub** | **ADVISORY** (NOT a finding) | **armed → EV-gate FAILS → ADVISORY** | **1** |
| 8 | zero-day-hunter | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 2 (corrob. CA e-d13) |
| 9 | zero-day-hunter | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED | n-a | 2 (corrob. CA e-passforge) |
| 10 | zero-day-hunter | D-11-D-12-gates+advance-redesign (gas-DoS HIGH) | NEGATIVE-VERIFIED | n-a | 1 |
| **11** | **USER (post-sweep, 357-00d)** | **D-11-D-12-gates (level-0 boundary)** | **GAP — sweep MISSED → RESOLVED-AT-357 (HEAD'''' 77d8bc88)** | **USER-caught; level-0 not exercised by the sweep** | **1** |
| X-A | XMODEL Codex | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED (NO ISSUE) | n-a (augmentation) | 2 (corrob. CA e1 / ZDH 2) |
| X-B | XMODEL Codex | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED (NO ISSUE) | n-a | 2 (corrob. CA e3 / ZDH 4) |
| X-C | XMODEL Codex | D-11-D-12-gates+advance-redesign | NEGATIVE-VERIFIED (NO ISSUE) | n-a | 2 (corrob. CA e4 / ZDH 5) |
| X-D | XMODEL Codex | drainAffiliateBase-stub+claim-CEI | NEGATIVE-VERIFIED (NO ISSUE) | n-a | 2 (corrob. CA f-stub/f-cei) |
| X-G | XMODEL Gemini | (full afking system) | PARTIAL (CLI empty/malformed — D-03) | n-a (attempted, not a block) | n-a |

### §C Outcome summary

**36 charged disposition rows (32 Claude probes + 4 Codex XMODEL rows) + 1 Gemini PARTIAL row:**

- **18 NEGATIVE-VERIFIED** (econ a1/a2/a3/a4/b; CA d-open/d-evcap/d-valve/e4/e-passforge/e-d13/f-stub/f-cei; ZDH 1/3/4/8/9/10 — and the 4 Codex rows are NEGATIVE-VERIFIED corroborations).
- **13 SAFE_BY_DESIGN** (econ c/N1/N2/N3/N4; CA e1/e2/e3/e5; ZDH 2/5/6).
- **1 ADVISORY** (ZDH probe 7 — the NEW-run cover-buy double-accrue; EV-negative; explicitly NOT a finding).
- **0 FINDING_CANDIDATE.**
- **4 Codex XMODEL NEGATIVE-VERIFIED (NO ISSUE) augmentation rows + 1 Gemini PARTIAL** (best-effort, additive).

Counting the Claude-sweep dispositions: **~31 NEGATIVE-VERIFIED + SAFE_BY_DESIGN rows + 1 ADVISORY + 0 FINDING_CANDIDATE** (18 NEGATIVE-VERIFIED + 13 SAFE_BY_DESIGN = 31, plus the advisory); the 4 Codex corroborations push the combined NEGATIVE-VERIFIED + SAFE_BY_DESIGN total to ~35.

Surface roll-up:
- **(a) Strategic sub/unsub edge — PRIMARY** (a1-a4 + ZDH 1·7): the SEC-01 spine HOLDS adversarially at HEAD''. The churn loop is forfeit-nothing-gain-nothing (affiliateBase = uplines' money; pendingBurnie zeroes-before-credit; decay recomputed honestly; D-11/D-12 make re-sub strictly EV-negative; PROVEN by V56SecUnmanipulable 11/11). The ONE asymmetry found — the NEW-run cover-buy slot-0 reward double-accrue — is an **EV-negative ADVISORY**, not a finding.
- **(b) Settle-timing** (1 row): NEGATIVE-VERIFIED — no seed/roll, exactly one deterministic path (the C1/C2 free-option is MOOT).
- **(c) Pre-credit-EV** (1 row): SAFE_BY_DESIGN — the +0..+9 head-start is the USER-ACCEPTED-BY-DESIGN bound.
- **(d) Two-path open** (3 rows): all NEGATIVE-VERIFIED — separate cursors/storage, effects-first `lastOpenedDay`, single monotonic per-level EV-cap draw, LIVE-01 valve + `drainAfkingBoxes` selector isolation (PROVEN by V56AfkingGasMarginal LIVE-01).
- **(e) The D-11/D-12/D-13 gates + the advance-incentive redesign** (the bulk — CA e1-e5/e-passforge/e-d13 + ZDH 1-6·8-10 + econ N1-N4 + Codex A/B/C): premature-advance-INERT HOLDS (VRF timing-independent, separate callback tx, `rngLockedFlag` fences all reactive actions, freeze set atomically with the request → firing early is strictly more conservative); `_bountyEligible` is a sound pay-predicate (NOT a security boundary; tier-flip requires real paid participation; pre-advance `dailyIdx` read correct); Vault/sDGNRS→mintBurnie routing hazard-free (`creditFlip recordAmount=0` no callback → no reentrancy; `NoWork()` benign). The passless cap-occupancy + unfunded free-rider vectors are CONFIRMED CLOSED → SEC-01 STRENGTHENED. **CAVEAT (probe 11, §B.3-addendum): the D-11 probes ran only at level ≥ 1 — they MISSED the level-0 vacuity (`0 < 0` false), where a funded passless EOA slipped through at level 0. USER-CAUGHT; RESOLVED-AT-357 (HEAD'''' `77d8bc88`). The passless cap-occupancy is fully closed only AS OF HEAD''''.**
- **(f) The drainAffiliateBase stub + the affiliate claim CEI** (f-stub/f-cei + Codex D): NEGATIVE-VERIFIED — guard-less-but-correct (delegatecall preserves `msg.sender`; the module enforces AFFILIATE-only at `:1333`) + `claim()` CEI clean (read-and-zero before `creditFlip`; dup subs drain 0; `recordAmount=0` no callback).

**Clean-closure outcome: 0 UNRESOLVED FINDING_CANDIDATE — THREE resolved-in-phase items.** The v56.0 audit closes with three items, ALL RESOLVED at a 357 contract gate, none a live FINDING_CANDIDATE:
1. **F-356-01 (RESOLVED-AT-357, HEAD' `ac5f1e03`)** — the missing `drainAffiliateBase` Game dispatch stub (the v56.0 carried HIGH), re-verified at HEAD'' / HEAD'''' (357-00 / 357-00b / 357-00d).
2. **The slot-0 churn ADVISORY (RESOLVED-AT-357, HEAD''' `7b0b2a0b`)** — the ZDH probe-7 NEW-run cover-buy slot-0 double-accrue (EV-negative, off-solvency), the optional hardening SHIPPED.
3. **The D-11 LEVEL-0 PASSLESS GAP (RESOLVED-AT-357, HEAD'''' `77d8bc88`)** — a USER-caught gap the 3-skill sweep MISSED (D-11 exercised only at level ≥ 1; the level-0 vacuity slipped a funded passless EOA through at level 0). Honestly disclosed (§B.3-addendum) rather than papered over.

This matches the v55-style clean close: every item is RESOLVED in-phase, 0 deferred / 0 unresolved FINDING_CANDIDATE.

---

## §D — Skeptic-Reviewer Filter Attestation (`/degen-skeptic` dual-gate)

`/degen-skeptic` was applied as the elevation FILTER (NOT a probing skill, per D-271-ADVERSARIAL-02). The dual-gate = (1) **structural-protection lens** — does a structural mechanism already prevent the elevation? (2) **3-condition EV lens** — (a) manifests without an attacker-controlled precondition / is positive-EV to execute, (b) magnitude is material, (c) severity survives a skeptic re-read. An elevation becomes a FINDING_CANDIDATE only if it survives BOTH gates. Applied per-skill self-arm AND orchestrator integration-time re-application.

### D.1 — The integration dual-gate result

**ZERO elevation survived both gates across all 3 Claude skills + Codex.** The load-bearing structural attestations:

- **Premature-advance-INERT HOLDS** (the redesign's key claim, CA e1 / ZDH 2 / Codex A): the VRF word is timing-independent (no caller entropy, fixed keyHash/subId, `numWords=1`); it lands in a SEPARATE callback tx; `rngLockedFlag` fences ALL reactive actions (buy/subscribe/sellFF) until unlock; the freeze + the request are set ATOMICALLY in the request tx → firing the advance early is strictly MORE conservative (it starts the fence earlier and resolution becomes available earlier — never extracts value).
- **The `_bountyEligible` soft-gate is a sound pay-predicate, NOT a security boundary** (CA e3 / econ N4 / Codex B): a tier-flip requires becoming a REAL paying participant; the pre-advance `dailyIdx` read is the correct semantics; there is no cost-free eligibility spoof.
- **The Vault/sDGNRS routing is hazard-free** (CA e4 / ZDH 5 / Codex C): `creditFlip recordAmount=0` is a pure SSTORE with no callback → no reentrancy; `NoWork()` is benign (the direct `advanceGame` always exists → no DoS).
- **The two-path open is correctly partitioned** (CA d-open/d-evcap/d-valve): separate cursors + storage, effects-first `lastOpenedDay`, a single monotonic per-level EV-cap draw.
- **The drainAffiliateBase stub is guard-less-but-correct + the claim() CEI is clean** (CA f-stub/f-cei / Codex D): delegatecall preserves `msg.sender`; the module enforces AFFILIATE-only at `:1333`; the claim drains atomically (read-and-zero before `creditFlip`), dup subs drain 0, `recordAmount=0` → no reentrancy edge.

### D.2 — The ONE armed advisory, traced through the dual-gate

**ZDH probe 7 — the NEW-run subscribe cover-buy double-accrues the flat 100-BURNIE slot-0 reward per churn cycle.**

- *Structural-protection lens:* the asymmetry is REAL — the NEW-run cover-buy branch (`GameAfkingModule.sol:426-485`) guards only on the manual `done[0]` (which an afking buy never sets), whereas the daily STAGE (`:954`) and the active-sub re-sub (`:395`) both carry the `lastAutoBoughtDay >= today` idempotency guard. So a subscribe → fund-buy → cancel → subscribe loop re-accrues the flat 100-BURNIE slot-0 reward per cycle. **No structural mechanism fully prevents the re-accrual** — but the economic cost structure structurally dominates the gain (each cycle requires a funded ≥0.01-ETH buy + a cancel-tx + a subscribe-tx).
- *3-condition EV lens:* **FAILS condition (a) positive-EV-without-attacker** — the loop is EV-NEGATIVE: ~100 BURNIE (= 0.1 ticket ≈ 0.001 ETH, and the BURNIE is non-extractable off the solvency path) per cycle vs ~400k+ gas + a funded ≥0.01-ETH buy per cycle. The magnitude is IMMATERIAL (a fixed flat 100-BURNIE flip-stake, off the ETH/claimablePool/solvency path); the 7% `affiliateBase` routes to the UPLINE, not the churner — so there is no self-payable extraction either.
- **VERDICT: ADVISORY (an EV-negative BURNIE-faucet wart), NOT a FINDING_CANDIDATE → RESOLVED-AT-357 (HEAD''' `7b0b2a0b`).** The optional one-line hardening WAS SHIPPED: `else if (s.lastAutoBoughtDay == uint24(today)) { _setStreakBase(s, snap); }` (`GameAfkingModule.sol:451`, mirrors the active-sub guard at `:399`) — keep the snapshot, skip a second same-day cover-buy, no slot-0 re-accrual. Re-proven GREEN by `V56SubHardening::testChurnSameDayAccruesSlot0Once` (357-00d). It does **NOT amend the clean-closure verdict** (it was always EV-negative + off-solvency); it is now RESOLVED rather than carried.

### D.2b — The D-11 LEVEL-0 PASSLESS GAP (probe 11, USER-CAUGHT, the sweep MISSED it) — RESOLVED-AT-357

**The USER's review of the frozen subject found a D-11 boundary the 3-skill sweep + Codex MISSED.**

- *Structural-protection lens:* the gap is REAL — the original D-11 gate `if (!exemptSub && s.validThroughLevel < level)` is VACUOUS at level 0 (`validThroughLevel(0) < level(0)` == `0 < 0` == false), so a funded PASSLESS EOA (horizon 0) cleared `NoPass()` at level 0 and could afk through level 0 (evicted only at L1). **No structural mechanism prevented the level-0 slip** — it was the gap the D-11 hardening was meant to close, with a single-level coverage hole.
- *Why the sweep missed it:* CA `e-passforge` + ZDH `9` (the D-11 probes) and the 357-00b `V56SubHardening` D-11 NEGATIVE proof all ran at **level ≥ 1** (the natural test setup pokes the level UP, e.g. `_setLevel(5)`, to make the `< level` compare non-vacuous). **Neither the 3-skill sweep nor Codex exercised level 0.** This is honestly disclosed (§B.3-addendum probe 11) — the sweep was NEGATIVE-VERIFIED on D-11 but had a level-0 coverage gap.
- *3-condition EV lens:* the gap is a passless cap-occupancy slip for ONE level (level 0), off the ETH/solvency path (D-12 still requires a funded cover-buy). Bounded, single-level, no value extraction (affiliate base → upline; slot-0 reward is the EV-negative wart of probe 7). It is a genuine GATE-COVERAGE gap, not a value-bearing finding.
- **VERDICT: GAP (USER-CAUGHT, sweep-missed) → RESOLVED-AT-357 (HEAD'''' `77d8bc88`).** The gate became `if (!exemptSub && (s.validThroughLevel == 0 || s.validThroughLevel < level)) revert NoPass();` (`GameAfkingModule.sol:372`) — a zero horizon is rejected at every level incl. 0; a real pass (horizon ≥ passLevel+99) / deity (`type(uint24).max`) clear it; D-13 VAULT/SDGNRS stay exempt + deity-covered. **Revert-only** (SOLVENCY-01 untouched). Re-proven GREEN by the new `V56SubHardening` level-0 proofs (§B.3-addendum, 357-00d). It does NOT introduce a deferred finding (resolved in-phase).

### D.3 — The three resolved-in-phase items + the clean-closure outcome

- **F-356-01 — RESOLVED-AT-357 (HEAD' `ac5f1e03`).** The missing `drainAffiliateBase` Game dispatch stub (the v56.0 HIGH carried finding) was FIXED at HEAD' (357-00, USER-approved contract gate) and re-verified at HEAD'' / HEAD'''' (357-00b / 357-00d). It is recorded as **RESOLVED**, NOT a live FINDING_CANDIDATE in this sweep. The fix surface (the stub + the claim CEI) was itself charged (surface (f)) and probed clean (f-stub/f-cei + Codex D = NEGATIVE-VERIFIED).
- **The slot-0 churn ADVISORY — RESOLVED-AT-357 (HEAD''' `7b0b2a0b`).** The ZDH probe-7 NEW-run cover-buy slot-0 double-accrue (EV-negative, off-solvency) was hardened with the `:451` idempotency guard. §D.2.
- **The D-11 LEVEL-0 PASSLESS GAP — RESOLVED-AT-357 (HEAD'''' `77d8bc88`).** The USER-caught level-0 vacuity the sweep missed, closed with the `(validThroughLevel == 0 || ...)` arm. §D.2b.
- **The O1/QST-05 lootbox-quest double-credit is RESOLVED** (single-credit proven at 356-05), NOT re-raised.
- **Clean-closure outcome:** **0 UNRESOLVED FINDING_CANDIDATE.** THREE resolved-in-phase items (F-356-01 + the slot-0 churn advisory + the level-0 D-11 gap), each fixed at a 357 contract gate, each re-proven GREEN. The working target (the v55-style clean close where every item is RESOLVED in-phase) HOLDS. This sweep introduces NO deferred finding.

**No elevation survived both gates → 0 unresolved FINDING_CANDIDATE. The sweep is recorded HONESTLY: the ZDH-7 advisory dual-gate self-discard AND the level-0 D-11 coverage gap (the sweep ran D-11 only at level ≥ 1; the USER caught the level-0 vacuity) are both disclosed, not papered over — a real hunt with a known coverage gap, both items now RESOLVED at a contract gate.**

---

## §E — Read-only invariant

The sweep ran read-only against HEAD'' `61315ecd` (`DIFF_LINES: 0` at sweep time — no `contracts/*.sol` read from anything other than `git show 61315ecd:...`; every cited `file:line` re-grep-verifiable at HEAD''). The subject was then re-frozen at **HEAD'''' `77d8bc88`** by two further revert-only / control-flow-only subscribe gates (HEAD''' `7b0b2a0b` slot-0 idempotency + HEAD'''' `77d8bc88` D-11 level-0 rejection) that RESOLVE the ZDH-7 advisory and the USER-caught level-0 gap, then at **c9b5d20d** by the FIFTH-gate pass refactor (§F). **`git diff c9b5d20d HEAD -- contracts/` is EMPTY** — zero contract mutation in the 357-00e reconciliation; the CURRENT subject is c9b5d20d `c9b5d20d756f9dfc5f3b0584aae56bdfa215d8bf`. The HEAD''→HEAD'''' delta is byte-confined to `GameAfkingModule.subscribe` (the `:451` idempotency guard + the `:372` D-11 level-0 arm); the HEAD''''→c9b5d20d delta is byte-confined to `DegenerusGameWhaleModule.sol` (the lootbox-bps collapse + dead-guard removal) + `DegenerusGame.sol` (the `hasAnyLazyPass` docstring); the SOLVENCY-01 debit two-liner is byte-frozen (relocated `:690-691`→`:702-703` only — `GameAfkingModule.sol` untouched by the FIFTH gate). HEAD == c9b5d20d for `contracts/`.

---

## §F — The FIFTH / FINAL gate `c9b5d20d` — focused single-skill contract-auditor pass (357-00e)

The FIFTH v56.0 contract gate `c9b5d20d` (USER-committed directly) is a **contained pass-PURCHASE economic refactor**: a flat-10% lootbox on all 3 pass types (whale / lazy / deity) replacing the presale-20%/post-10% split (the `*_LOOTBOX_PRESALE_BPS` constants + the `_psRead(PS_ACTIVE)` ternaries dropped, `*_LOOTBOX_POST_BPS → *_LOOTBOX_BPS`; the 25% `presaleBoxCredit` unchanged) + 3 unreachable-guard removals + a `hasAnyLazyPass` docstring fix; it touches `DegenerusGame.sol` (8 lines) + `DegenerusGameWhaleModule.sol` (−46/+25). It does NOT touch the afking / advance / subscribe / affiliate surfaces or `_passHorizonOf` — i.e. NONE of the v56-NEW security spine the 3-skill sweep charged. **Proportionate to a contained economic + dead-code refactor, it got a FOCUSED single-skill `/contract-auditor` pass, NOT a full 3-skill re-sweep** (the genuine-parallel 3-skill sweep §A–§E already discharged the afking/advance/subscribe/affiliate surfaces; this refactor adds no new surface to those). Full disposition: `/tmp/sweep357/c9-auditor.md`.

**4 probes — all NEGATIVE-VERIFIED, 0 FINDING_CANDIDATE:**

**Probe c9-A — the 3 dropped guards reachability**
- Surface: pass-purchase dead-code removal.
- Finding @ c9b5d20d: the lazy `if (baseCost == 0) revert E();` is dead — `priceForLevel` (`PriceLookupLib.sol:21`) has NO zero branch (returns ≥ `0.01 ether` over all `uint24`), so the 10-level `_lazyPassCost` sum is always > 0. The lazy `if (lootboxAmount == 0) return;` + the deity `if (lootboxAmount != 0) { … }` zero-guards are dead — 10% of a positive price ≥ 0.18 ETH (lazy) / ≥ 1.2 ETH (whale) / ≥ 24 ETH (deity) is never 0. `_recordLootboxEntry` is safe even vs a hypothetical 0 (its explicit `!= 0` RMW guard on the sensitive branch). Removing provably-dead branches is byte-irrelevant.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe c9-B — flat-10% solvency / value-conservation**
- Surface: pass-purchase flat-10% lootbox.
- Finding: only the `*_LOOTBOX_BPS` multiplier shifts (2000→1000 presale); OFF the ETH/`claimablePool` path; the ETH pool splits are computed from `totalPrice` INDEPENDENT of the lootbox %; the 25% `presaleBoxCredit` byte-unchanged; reducing an award can't create unbacked value / exceed the EV-cap / underflow. A pure downward tweak (intended). SOLVENCY-01 untouched (`git diff 77d8bc88 c9b5d20d -- contracts/modules/GameAfkingModule.sol` EMPTY).
- Disposition: **NEGATIVE-VERIFIED**.

**Probe c9-C — dangling refs to the dropped constants**
- Surface: pass-purchase constant removal.
- Finding: ZERO remaining refs to the dropped `*_LOOTBOX_PRESALE_BPS` / `*_LOOTBOX_POST_BPS` constants in `contracts/` or `test/` (`git grep` → 0); the `PS_ACTIVE` shift/mask is still used elsewhere (not orphaned). Clean removal.
- Disposition: **NEGATIVE-VERIFIED**.

**Probe c9-D — the `hasAnyLazyPass` docstring**
- Surface: pass-view NatSpec.
- Finding: the docstring is now ACCURATE — `hasAnyLazyPass` is a UI/external VIEW (exclusive `> level`), NOT the AfKing gate (which uses `_passHorizonOf` inclusive through `frozenUntilLevel`); the off-by-one is view-only, referenced only in `IDegenerusGame.sol` + a regression doc, NEVER consumed by any on-chain decision. Benign + the docstring correctly documents the by-design divergence. The function body is byte-unchanged.
- Disposition: **NEGATIVE-VERIFIED**.

**§F outcome:** the FIFTH gate is a clean behavior-preserving simplification + an intended presale-20%→10% lootbox reduction. **4 probes NEGATIVE-VERIFIED, 0 FINDING_CANDIDATE.** SOLVENCY-01 untouched. The clean-closure verdict is UNCHANGED — the FIFTH gate adds ZERO findings (recorded as a clean refactor, NOT a finding); the v56.0 audit still closes with THREE resolved-in-phase items + 0 UNRESOLVED FINDING_CANDIDATE.
