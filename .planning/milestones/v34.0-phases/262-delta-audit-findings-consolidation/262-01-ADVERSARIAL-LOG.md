# Phase 262 — Adversarial Validation Log

**Step 2 of D-262-ADVERSARIAL-01:** /contract-auditor + /zero-day-hunter spawn IN PARALLEL after §4 inline draft (Task 5) is finished.

**Subject:** `audit/FINDINGS-v34.0.md` §4a 5-surface row table (commit `693ae0fb`) + §4b closing attestation.

**Spawn invocation:** Single message containing two parallel Skill tool calls (one /contract-auditor, one /zero-day-hunter). Orchestrator-led per "skill-equivalent" provision in the plan; executor agent (gsd-executor) does not have the Skill tool. This produces real skill output rather than the executor-manual SPAWN_FAILED fallback path that v33 Phase 257 used.

**Skills NOT spawned (per D-262-ADVERSARIAL-01):** /economic-analyst (EV-uplift / game-theory angles covered by STAT-04..05 chi² + Phase 261 D-04 per-surface analytical derivation + /contract-auditor adversarial review); /degen-skeptic (practitioner-burned-by-pattern not the failure mode for v34 — no presale / honeypot / drainable-pool surface).

**Source-tree HEAD at spawn time:** `693ae0fb` (Task 5 commit; source-tree HEAD `6b63f6d4` per `git log --oneline 4ce3703d740d3707c88a1af595618120a8168399..HEAD -- contracts/`).

---

## /contract-auditor

**Prompt to skill:** "Red-team the §4 inline 5-surface table at `audit/FINDINGS-v34.0.md` against the v34.0 trait/solo source surface (`contracts/DegenerusTraitUtils.sol` + `contracts/modules/DegenerusGameJackpotModule.sol` at HEAD `6b63f6d4`, baseline `4ce3703d`). Look for: missed attack vectors per surface, weak grep recipes, premature SAFE conclusions, line cites that don't actually prove the verdict. Specifically scrutinize: (a) entropy-bit collision between gold tie-break (`entropy >> 4`) and bucket rotation (`entropy & 3`), (b) `_pickSoloQuadrant` deterministic across L349 ↔ L1147 split-call (live HEAD L454 ↔ L1181), (d) gas-griefing of `_pickSoloQuadrant` 4-iteration loop, (e) overflow / signed-vs-unsigned in entropy XOR mask `~uint256(3)`. Surface (c) gold-trait population manipulation is by design (player cannot bias VRF) — flag only if you find a code-level vector beyond the VRF trust boundary. Output: per-surface verdict {AGREE / DISAGREE-WITH-RATIONALE / NEW-VECTOR}."

**Output:**

**Subject:** `audit/FINDINGS-v34.0.md` §4a (commit `693ae0fb`) + §4b
**HEAD audited:** `6b63f6d4` (source tree) | baseline `4ce3703d`
**Methodology:** Per-surface read of cited code paths + cross-reference against test assertions.

### Per-Surface Verdicts

#### Surface (a) — Entropy-bit collision (gold tie-break vs bucket rotation)
**Verdict: AGREE (with documentation-gap flag)**

The bit-disjointness claim (bits 0-1 rotation, bits 4+ tie-break, bits 2-3 dead-zone) is correct *for the `_pickSoloQuadrant` ↔ `JackpotBucketLib.shareBpsByBucket / soloBucketIndex` interaction*. However, the §4 prose (and the `_pickSoloQuadrant` NatSpec at L1095-1097 it cites) is **incomplete** — it omits a third entropy consumer:

```
contracts/libraries/JackpotBucketLib.sol:169  uint8 trimOff = uint8((entropy >> 24) & 3);
contracts/libraries/JackpotBucketLib.sol:187  uint8 offset  = uint8((entropy >> 24) & 3);
```

`capBucketCounts` consumes `(entropy >> 24) & 3` for cap-trim and cap-fill rotation. Bits 24-25 are **preserved** by the substitution (`~uint256(3)` clears bits 0-1 only), so this is *not* a vulnerability — `effectiveEntropy >> 24` == `entropy >> 24` and the cap-trim/fill behavior is unchanged across the substitution. But the prose's "bits 2-3 unused by either path" framing under-describes the live entropy budget.

**Grep recipe (additional):** `grep -nE 'entropy >> 24|entropy >> 4|entropy & 3' contracts/libraries/JackpotBucketLib.sol contracts/modules/DegenerusGameJackpotModule.sol`
**Recommended prose amendment to surface (a):** Acknowledge bits 24-25 as a third (cap-trim/fill) consumer; assert preservation across substitution explicitly. No verdict change.

#### Surface (b) — `_pickSoloQuadrant` deterministic across SPLIT_CALL1 ↔ SPLIT_CALL2
**Verdict (initial): DISAGREE-WITH-RATIONALE → revised to AGREE post-disposition**

The `SAFE_BY_STRUCTURAL_CLOSURE` verdict and the SOLO-09 cross-cite are *correct as far as they go*, but they prove **only that `_pickSoloQuadrant` is deterministic in `(randWord, lvl)`**. They do **not** prove that SPLIT_CALL1 (`payDailyJackpot` daily path at L454) and SPLIT_CALL2 (`_resumeDailyEth` at L1181) actually receive the **same** `randWord` on-chain.

Tracing the AdvanceModule wiring:
- Both call sites pass `rngWord` from `rngGate(...)` at `DegenerusGameAdvanceModule.sol:289`.
- `rngGate` returns `rngWordByDay[day]` if cached for *today*; otherwise it processes a fresh VRF word and caches it under `day = _simulatedDayIndexAt(ts)`.
- SPLIT_CALL1 sets `resumeEthPool != 0` and `dailyJackpotCoinTicketsPending = true`, then returns. **No `_unlockRng(day)` is called between SPLIT_CALL1 and SPLIT_CALL2.**
- There is **no `resumeRandWord` storage** — the second-call randWord is recomputed by the caller, not persisted from call 1. (Verified: `grep -n resumeRandWord contracts/` returns zero hits; `contracts/storage/DegenerusGameStorage.sol:1006` shows only `uint128 internal resumeEthPool;`.)

So coherence depends on a one-line invariant the §4 prose never states: **SPLIT_CALL2 must execute on the same `day = _simulatedDayIndexAt(ts)` as SPLIT_CALL1**, so that `rngWordByDay[day]` is hit and returns the same cached word.

**Disposition note (orchestrator + user):** The same-day execution is enforced operationally by the bounty-escalation incentive (2x→4x→6x multipliers at 20m/1h/2h thresholds, per `DegenerusGameAdvanceModule.sol`) — `advanceGame` will be called by bounty-hunters within minutes of SPLIT_CALL1, well before any 24-hour day rollover. Combined with `rngLockedFlag = true` persisting across SPLIT_CALL1, no fresh VRF request fires; `rngGate` returns `rngWordByDay[day]` cache → SPLIT_CALL2 sees identical `randWord`. SOLO-09 (Strategy B) test correctly validates the on-chain coherence under the operational invariant. **Final verdict: AGREE.**

#### Surface (c) — Gold-trait population manipulation via player ticket purchases
**Verdict: AGREE**

VRF-derived `randWord` is the single trait-population input; player ticket purchases buy quadrant ownership not trait outcomes; STAT-01 1M-sample empirical evidence holds. No code-level vector beyond the VRF trust boundary surfaces.

#### Surface (d) — Gas-griefing of `_pickSoloQuadrant` 4-iteration loop
**Verdict: AGREE**

Verified `for (uint8 i; i < 4; ++i)` at `DegenerusGameJackpotModule.sol:1104`. Loop bound is constant, no early-exit on attacker input. `test/gas/Phase261GasRegression.test.js:217-232` tests 4-gold worst-case input ([7,7,7,7]) against `PICK_SOLO_QUADRANT_HARD_BOUND = 1500`. Test asserts `bodyGas <= 1500`. ≤1500 gas constant-cost claim holds.

#### Surface (e) — Overflow / signed-vs-unsigned in entropy XOR mask `~uint256(3)`
**Verdict: AGREE**

Substitution formula `effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` verified safe:
1. `soloQuadrant ∈ [0, 3]` guaranteed by `_pickSoloQuadrant` return-value-bound proof (zero-gold L1111 returns `uint8((3 - (entropy & 3)) & 3) ∈ [0,3]`; multi-gold L1114 returns `uint8((goldQuads >> (idx * 8)) & 0xFF)` where each slot was filled with `i ∈ [0,3]`).
2. `3 - soloQuadrant` evaluated in checked uint8 arithmetic (Solidity 0.8.34 per `pragma solidity 0.8.34;`); no underflow path because `soloQuadrant ≤ 3`.
3. `& 3` mask + `uint256` cast + bitwise OR with `entropy & ~uint256(3)` is bit-correct (verified against `JackpotSoloSplit.test.js` "substitution mask inverts to gold quadrant" and "substitution preserves upper bits of entropy" assertions).

### Summary Table

| Surface | Verdict | Action |
|---|---|---|
| (a) | AGREE (doc-gap, INFO) | Optional §4 prose amendment to acknowledge bits 24-25 cap-trim/fill consumer; preserve verdict SAFE_BY_DESIGN |
| (b) | AGREE (post-disposition) | Same-day operational invariant confirmed by bounty-escalation incentive structure; SOLO-09 Strategy B test validly covers on-chain coherence under that invariant |
| (c) | AGREE | None |
| (d) | AGREE | None |
| (e) | AGREE | None |

**5 of 5 surfaces AGREE; zero F-34-NN-eligible findings.** Recommended disposition: Option B (default path) — 5 SAFE rows preserved, zero F-34-NN blocks. Optional INFO-tier prose tightening on surface (a) is non-load-bearing for the verdict.

---

## /zero-day-hunter

**Prompt to skill:** "The §4 inline 5-surface table at `audit/FINDINGS-v34.0.md` enumerates 5 adversarial surfaces (a..e) for the v34.0 trait/solo source surface. Hunt for a 6th-surface novel-composition attack the plan author did NOT list. Compose: `_pickSoloQuadrant` × `effectiveEntropy` substitution × `JackpotBucketLib.shareBpsByBucket` × `JackpotBucketLib.bucketCountsForPoolCap` × `_processDailyEth` × `_resumeDailyEth` SPLIT_CALL2 × hero override (literal-slice color path) × Degenerette match payouts × bonus jackpot non-injection sites × VRF stall × multi-day backfill (EXC-02/03 envelopes) × XOR-shift entropy quality (EXC-04 envelope). Specifically explore: (1) re-entrance via test-tester wrapper invocation (contracts/test/JackpotSoloTester.sol external-pure passthrough), (2) gold-quadrant population manipulation via player ticket purchases that affect WHICH quadrant a winning trait lives in (does the slot index influence trait color?), (3) cross-call entropy state leakage between SPLIT_CALL1 and SPLIT_CALL2 via storage writes performed BETWEEN the two calls, (4) bonus-jackpot non-injection sites (513/527/598/599/683/1687/1713/1715) — does any subtle interaction with new heavy-tail color distribution affect those equal-split bucket flows, (5) hero override + new color distribution interaction — does the literal-slice color path have any new pathological case under the heavy-tail distribution. Output: NEW_SURFACE candidates with file:line cite + grep recipe + composition path."

**Output:**

**Subject:** `audit/FINDINGS-v34.0.md` §4a (commit `693ae0fb`, lines 297-340) — 5 enumerated surfaces (a..e)
**Mandate:** Find a 6th surface the plan author + /contract-auditor missed
**Methodology:** Composition-hunt across `_pickSoloQuadrant` × `_applyHeroOverride` × `_rollWinningTraits` × MintModule LCG × bonus jackpot × non-injection sites

### NEW_SURFACE (f) — Hero Override × Gold-Priority Composition (Player-Influenced Solo Activation)

**Severity (initial proposal):** MEDIUM (pending user disposition on design intent)
**Severity (post-disposition):** SAFE_BY_DESIGN — intended hero mechanic per user

**Composition path:**
```
Player wagers via Degenerette to make symbol S the day's top hero in quadrant Q
  → _topHeroSymbol(day) returns (Q, S) (player-controllable via Degenerette wager amount)
  → _rollWinningTraits(randWord, false) calls _applyHeroOverride(traits, randWord)
  → _applyHeroOverride writes traits[Q] = (Q << 6) | (heroColor << 3) | S
  → heroColor = uint8((randWord >> shift) & 7) — UNIFORM 12.5% per color value (NOT weightedColorBucket)
  → 12.5% of jackpots: heroColor == 7 (gold)
  → traits[Q] color == 7
  → _pickSoloQuadrant(traits, entropy) sees gold in quadrant Q
  → soloQuadrant = Q (or random-among-multi-gold via tie-break)
  → effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - Q) & 3)
  → JackpotBucketLib.shareBpsByBucket assigns SOLO bucket (60% on final day, 20% on regular days) to Q
```

**Code citations:**
- Hero override: `contracts/modules/DegenerusGameJackpotModule.sol:1587-1614` (`_applyHeroOverride`)
- Hero color uniform 12.5%: `contracts/modules/DegenerusGameJackpotModule.sol:1599-1607` (`heroColor = uint8((randomWord >> shift) & 7)`)
- Hero override fires for MAIN traits feeding `_pickSoloQuadrant`: `contracts/modules/DegenerusGameJackpotModule.sol:1921` (`_applyHeroOverride(traits, r);` inside `_rollWinningTraits` regardless of `isBonus`)
- 4 v34 solo-priority injection sites: `:287` `:454` `:531` `:1181` (all consume hero-overridden traits via `_pickSoloQuadrant`)
- v34 composition novelty (gold→solo assignment): `:1098-1115` (`_pickSoloQuadrant` body, NEW in v34)
- Hero override is byte-identical pre/post v34 (`git diff 4ce3703d..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol | grep _applyHeroOverride` returns zero matches); only the **gold-color consumer** (`_pickSoloQuadrant`) is new in v34. The composition is novel even though the hero-override mechanism is legacy.

**Why /contract-auditor and the plan author missed it:**

The §4 surface (c) prose ("Gold-trait population manipulation via player ticket purchases") explicitly addresses the *ticket-purchase* channel for player influence over trait outcomes and correctly verdicts `SAFE_BY_DESIGN` on that vector (player ticket purchases buy quadrant ownership, not trait outcomes; VRF derives traits). However, surface (c) does NOT enumerate the **second player-influence channel: hero wagers via Degenerette**. Hero wagers existed pre-v34 but were not load-bearing for any v34-introduced mechanism — until v34 made gold color (in any quadrant) a SOLO-bucket-priority trigger via `_pickSoloQuadrant`. The composition `hero override (legacy) × gold priority (NEW v34)` is a v34-introduced interaction the §4 audit completely omits.

**Design-intent disposition:**

Hero is **symbol-only**, not color: the player wagers via Degenerette to make their chosen symbol S the day's top hero for quadrant Q. The override writes that symbol into traits[Q]; the color slot of the overridden trait is freshly RNG-derived (uniform 12.5% per color). The 12.5% chance that hero-color rolls 7 (gold) triggers solo-priority on Q via `_pickSoloQuadrant`. This is the **intended skill-expression channel** for high-engagement Degenerette wagerers — a player who:
1. Owns a `(Q, color=7, symbol=S)` ticket (acquired at mint via natural 0.781% gold rate or strategic batch-mint)
2. Pays Degenerette wagers to make S the day's top hero in Q

…earns a 12.5% per-jackpot chance of solo-priority activation on Q (vs 0.781% baseline). The advantage is real, paid for via Degenerette wagers, and intentionally rewards forward-planning + engagement.

**Per user disposition (Task 7):**
- Hero override × gold-priority interaction is **DESIGN-INTENTIONAL** under v34 gold-priority mechanism
- No F-34-NN emission required
- Surface (f) added to §4 as a sub-row with verdict `SAFE_BY_DESIGN` to make the intended composition explicit (avoids future audits re-discovering this as a "missed" vector)
- Surface (c) prose tightened to acknowledge the hero-symbol-wagers-via-Degenerette channel as a second player-influence channel (with color uniform-RNG-derived, gold rate 12.5% by design)

### Other hunting paths investigated (all clean)

1. **Test-tester re-entrance** (`contracts/test/JackpotSoloTester.sol`) — production deploys do NOT include `contracts/test/`; tester instances would have separate storage and `msg.sender != ContractAddresses.GAME` reverts on inherited external functions. No production surface.
2. **Cross-call entropy state leakage SPLIT_CALL1↔SPLIT_CALL2** — no `resumeRandWord` storage exists; the same-day operational invariant (covered by /contract-auditor surface (b) disposition) closes this. Storage writes between calls don't flow into the substituted entropy because both calls re-derive from `(randWord, lvl)`.
3. **Bonus jackpot non-injection sites L513/527/598/599/683/1687/1713/1715** — verified these flow into `_distributeTicketJackpot` / `_awardDailyCoinToTraitWinners` (equal-share distribution, no solo bucket). v34 gold-priority does not interact with these paths. SOLO-06 8-line list correctly identified the non-injection scope.
4. **MintModule LCG trait derivation `MintModule:581 traitFromWord(s)`** — ticket trait outcomes use VRF-derived `entropyWord` mixed with player address. Players cannot grind the LCG without VRF foreknowledge (mempool-VRF question is pre-v34 EXC-03 envelope, not v34-novel).
5. **Degenerette `packedTraitsFromSeed` consumer at `DegenerusGameDegeneretteModule.sol:607`** — Degenerette uses traits for match payouts only, no solo-bucket interaction.

### Summary

**1 NEW_SURFACE candidate found, dispositioned SAFE_BY_DESIGN:**
- (f) Hero override × gold-priority composition — intended hero mechanic per v34 design

**5 of 5 plan-author surfaces (a..e):** AGREE per /contract-auditor

**Zero F-34-NN candidates emitted.** Default-path disposition (Option B) preserved with §4 prose amendments on (a) bits 24-25 cap-trim consumer, (c) hero-wager channel, and new (f) hero × gold composition.

---

## Task 7 — Disposition Summary

**Step 3 of D-262-ADVERSARIAL-01 disposition (per `feedback_wait_for_approval.md`).**

**Skill outputs reviewed:**
- /contract-auditor: 5 of 5 surfaces AGREE post-disposition (surface (b) initial DISAGREE-WITH-RATIONALE resolved by user-confirmed same-day operational invariant under bounty-escalation incentive)
- /zero-day-hunter: 1 NEW_SURFACE (f) hero × gold-priority composition; user-dispositioned SAFE_BY_DESIGN (intended hero mechanic; symbol-only hero, color RNG-uniform, 12.5% gold rate is by-design skill-expression channel for Degenerette wagerers)

**User decisions captured:**
- Surface (b): "safe to assume advancegame isn't going to get stalled out for an entire day in the middle of jackpots" — confirms operational same-day invariant; SOLO-09 Strategy B test correctly validates on-chain coherence under that invariant
- Surface (f): "there is no 'hero color' there is only a hero symbol. it is a decent size advantage to make a symbol that you own a ticket with that symbol in gold win via degenerette, but that is an intended mechanic" — confirms hero × gold composition is design-intentional skill expression

**Final outcome (default path Option B per D-262-FIND-01):**
- Zero F-34-NN finding blocks emitted
- §4 prose amendments to land in Task 8+ continuation work (carried as deferred prose-tightening tasks):
  - Surface (a): acknowledge bits 24-25 of entropy as third (cap-trim/fill) consumer in `JackpotBucketLib.capBucketCounts:169,187`; note bits 24-25 preserved by substitution → no verdict change (INFO-tier doc tightening)
  - Surface (c): tighten prose to acknowledge hero-symbol wagers via Degenerette as second player-influence channel (with color uniform-RNG-derived); not a vulnerability — informational completeness
  - **NEW Surface (f):** Add as sixth row to §4a 5-surface table (renamed §4a 6-surface table) with verdict `SAFE_BY_DESIGN` and full hero × gold composition path documented; cross-cite `_applyHeroOverride` at `:1587-1614` + `_pickSoloQuadrant` at `:1098-1115` + design intent ("hero mechanic rewards Degenerette wagerers; v34 introduces gold-priority as deliberate concentration of solo-bucket reward on heroes who happened to roll color==7")

**Severity counts unchanged:** CRITICAL 0 / HIGH 0 / MEDIUM 0 / LOW 0 / INFO 0 / total F-34-NN 0.

**Resume signal:** `approved — Option B default path` (from user "ok move on")

---
