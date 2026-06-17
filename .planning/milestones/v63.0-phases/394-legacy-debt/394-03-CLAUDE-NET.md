# 394-03 — NET 2 (Claude Adversarial Net) — the v50 LEGACY-DEBT slice (LEGACY-01, LEGACY-02)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8…`). All source read via
`git show a8b702a7:contracts/<File>.sol` — the working tree is ignored.
**Net:** NET 2 = the independent Claude adversarial net (the second discipline the both-nets-on-record rule
requires; AUDIT-V63-PLAN §2). Run BEFORE folding the council leads — the council outputs were read only at
the END of this analysis (the fold-in section), so each property was attacked independently first.
**Posture:** AUDIT-ONLY. No contract source is modified. A CONFIRMED finding is DOCUMENTED + ROUTED, never
fixed here. `git diff a8b702a7 -- contracts/` is EMPTY at start and at end of this analysis.
**Threat weighting (§4):** RNG-freeze = DOMINANT; value-non-equivalence / solvency / MINTDIV-drift = SPINE;
access / reentrancy / timing = confirmatory. Design-intent anchor (§5): the AFSUB inclusive boundary, the
OPEN-E operator-approval trust boundary, and the whale-pass / WWXRP economics are BY-DESIGN — this net
VERIFIES freeze / value-equivalence / index-correctness / consent-correctness, it does NOT re-litigate the
design.

---

## Frozen line-cites re-pinned (read via `git show a8b702a7:` — corrected against the prompt's blind cites)

| Symbol | Frozen location | Note |
|---|---|---|
| `claimWhalePass(address)` | `WhaleModule:991` | O(1) deferred claim; body 991-1008 |
| `startLevel = level + 1` | `WhaleModule:1003` | recomputed from the LIVE `level` at claim time |
| `_applyWhalePassStats(player, ticketStartLevel)` | **`Storage:1338`** (def) | the 2-arg deferred-claim stat helper (NOT the inline-purchase body @195-300, which is `_purchaseWhaleBundle`) |
| `_queueTicketRange(buyer, startLevel, 100, halfPasses, false)` | `Storage:679` (def) | deterministic ticket queue; NO RNG read |
| `_recordLootboxEntry` index snapshot | `WhaleModule:850-851` | `lr = lootboxRngPacked; index = (lr >> LR_INDEX_SHIFT) & LR_INDEX_MASK` |
| first-deposit-only enqueue | `WhaleModule:888` | `boxPlayers[index].push(buyer)` (only when `existingAmount == 0`) |
| `_activateWhalePass` + **D-04 / D-20 doc** | `LootboxModule:1483-1490` | `whalePassClaims[player] += 1` (count only) |
| type-28 boon caller | `LootboxModule:1900-1901` | `_activateWhalePass(player)` |
| `whalePassClaims` (COUNT, no open-level) | `Storage:1107` | `mapping(address => uint256)`; 5 writers, all `+= count` |
| `level` (live game level) | `Storage:237` | `uint24 public level` |
| AFSUB SUB-02 / OPENE-04 consent | `AfkingModule:314-330` | subscribe-only |
| AFSUB no-pass guard | `AfkingModule:414-428` | rejects `validThroughLevel == 0 || < level` |
| AFSUB `_passHorizonOf` | `AfkingModule:596-606` | deity sentinel `type(uint24).max` / else `frozenUntilLevel` |
| AFSUB inclusive boundary walk | `AfkingModule:1246-1264` | `if (currentLevel > sub.validThroughLevel)` → refresh-or-evict |
| MINTDIV future loop `processed` | `MintModule:582` (decl), `:667` (`processed += take`), `:672-676` (reset on `remainingOwed==0`) | within-call cursor |
| MINTDIV cross-path `_processOneTicketEntry` | `MintModule:951` (def), `:881-905` (caller, `processed += take` @902) | current-level path |
| quadrant offset | `MintModule:761` (`traitId + (uint8(i & 3) << 6)`) | `i` runs `startIndex..startIndex+count`, `startIndex = processed` |

Byte-freeze verified at the start of this analysis: `git diff a8b702a7 -- contracts/` → EMPTY.

---

## LEGACY-01a — Whale-pass O(1) deferred-claim VALUE-EQUIVALENCE (dedicated)

**PROPERTY:** the O(1) deferred `claimWhalePass` materializes the SAME value the retired inline ~100-loop
mint would have — same ticket count, same stat application, same single-shot, no double-claim, no
over-/under-delivery.

**Attack call-sequence tried (value-extraction lens):**
1. Open a box → roll boon type 28 → `_activateWhalePass(player)` records `whalePassClaims[player] += 1`
   (`LootboxModule:1489`). The box-open emits `LootBoxWhalePassJackpot(player, …, level + 1, …)` as
   HISTORICAL CONTEXT only (`LootboxModule:1908`) — it does NOT queue tickets.
2. Do NOT claim. Let the game advance many levels (the live `level` rises L → L'>L).
3. Call `claimWhalePass(player)` at level L'. It reads the COUNT (`WhaleModule:993`), zeroes it FIRST
   (`:997`), recomputes `startLevel = level + 1 = L'+1` (`:1003`), applies stats (`:1005`), queues
   `100 levels × halfPasses` tickets from `L'+1` (`:1007`).

**Break attempts + result:**
- **Double-claim / replay:** REFUTED. `whalePassClaims[player] = 0` (`:997`) executes BEFORE the external
  ticket-queue/stat effect (`:1005-1007`); a re-call reads 0 and `return`s (`:994`). Clear-before-award is a
  strict single-shot. No re-driveable double-mint of tickets or stats. The box enqueue is independently
  single-shot: `boxPlayers[index].push` fires only on `existingAmount == 0` (`WhaleModule:888`).
- **Ticket-COUNT non-equivalence:** REFUTED. `_queueTicketRange(player, startLevel, 100, halfPasses, false)`
  always queues `100 × halfPasses` tickets regardless of `startLevel` — the count arithmetic is
  TIMING-INDEPENDENT. A late claim queues the SAME number of tickets (the same 100-level span), only shifted
  to higher level keys. There is no count over-/under-delivery.
- **Stat (freeze) over-delivery:** ANALYZED → BOUNDED, NOT a value-extraction edge. `_applyWhalePassStats`
  (`Storage:1338`) is DELTA-BASED: `targetFrozenLevel = ticketStartLevel + 99`,
  `newFrozenLevel = max(frozenUntilLevel, targetFrozenLevel)`, `deltaFreeze = newFrozenLevel −
  frozenUntilLevel`, `levelsToAdd = min(100, deltaFreeze)`, `newLevelCount = levelCount + levelsToAdd`,
  `LAST_LEVEL = newFrozenLevel`. A LATER claim raises `targetFrozenLevel`, which can raise `levelsToAdd` UP
  TO the 100 cap — BUT only when the player's existing `frozenUntilLevel` is BELOW the new target. The cap
  `levelsToAdd ≤ 100` and the delta-based no-double-dip (overlapping passes only credit NEW covered levels)
  bound the stat award to exactly one 100-level pass worth of freeze — the player can NEVER extract MORE than
  one pass's stat span from one count. The "shift" moves the freeze WINDOW forward; it does not multiply it.

**VERDICT (provisional):** REFUTED as a value-non-equivalence finding — the deferred path is
value-equivalent to the inline mint up to a DOCUMENTED claim-time horizon shift (see LEGACY-01 horizon, the
council-divergent item below). Count + single-shot + delta-stat-cap all hold at the frozen source.

---

## LEGACY-01 — the claim-time HORIZON SHIFT (the council-divergent SPINE candidate)

**The divergence (folded from NET 1 at the end, but attacked independently here):** codex flagged a SPINE
"value non-equivalence in deferred whale-pass claim horizon" — `whalePassClaims` stores only a COUNT, so a
DELAYED claim queues from claim-time `level+1` instead of open-time `level+1`, giving "100 FUTURE levels
instead of the originally-opened 100-level window." gemini cleared the same path as value-equivalent.

**Independent skeptic dual-gate vs the frozen source:**

1. **Structural-protection / DOCUMENTED-INTENT check (the load-bearing tie-breaker).** The
   `_activateWhalePass` doc at `LootboxModule:1483-1485` states verbatim:
   *"Materialization (stats + 100 levels × tickets) is deferred to the player-paid `claimWhalePass`
   endpoint … (D-04 — timing shifts from open-time to claim-time …)."* The type-28 caller comment at
   `LootboxModule:1903-1907` reinforces it: *"the queued tickets start at the level when the player calls
   `claimWhalePass` — not necessarily `level + 1` here."* The claim-time horizon is therefore **DOCUMENTED
   v50 DESIGN (D-04 / D-20)**, not an accidental drift. codex's mechanical trace is ACCURATE; its SPINE
   severity label is the disputed part.

2. **3-condition EV / value-harm lens.** Is the shift a VALUE-EXTRACTION edge, or inert claim-timing the
   by-design ruling already covers?
   - **Ticket count:** identical at any claim level (timing-independent, proven in LEGACY-01a). No tickets
     gained or lost.
   - **Direction of the shift:** a LATER claim moves the 100-level span to HIGHER levels — i.e. into levels
     the player has NOT yet reached and whose tickets are not yet drawable. This is NEUTRAL-to-the-player at
     best and a SELF-INFLICTED DELAY at worst (the player forgoes coverage of the levels between open-time
     and claim-time). It is NOT an over-delivery: the player does not receive MORE tickets, only the SAME
     100-level span placed later. There is no path where the protocol pays out value it did not commit.
   - **Adversarial-extraction:** there is no money-pump. The claim is permissionless (anyone can call it for
     a player), the count is fixed at open, and the award is illiquid trait tickets on a near-worthless pass
     ([[degenerette-wwxrp-rtp-by-design]] — the pass is rated near-worthless; the whale-half-pass channel
     caps supply globally). A player cannot manufacture extra value by timing the claim — the worst they do
     is delay their own coverage. The lootbox/claim TIMING-is-not-a-player-edge ruling
     ([[lootbox-resolution-timing-by-design]]) directly covers this inert claim-timing.
   - **Freeze:** the claim reads NO RNG word (see LEGACY-01b) — the horizon shift cannot steer any draw.

   The skeptic gate does NOT pass for a HIGH/CATASTROPHE: the shift is documented intent, count-equivalent,
   neutral-or-self-harming in direction, non-extractable, and freeze-independent.

**VERDICT (provisional):** **BY-DESIGN (D-04 / D-20 documented claim-time horizon).** codex's mechanical
observation is correct and is recorded; its SPINE label does NOT survive the skeptic gate. There is no
value-extraction edge — a late claim is neutral-or-self-harming, never an over-delivery. Settled by the
`LootboxModule:1483-1485` D-04 doc + the `WhaleModule:1003` claim-time `startLevel` + the
`Storage:1338` delta-cap. gemini's "value-equivalent" verdict is correct in OUTCOME (no value harm); codex's
"horizon shifts" is correct in MECHANISM — both reconcile under "documented intent, no extraction."

> **Possible MONITOR sub-note (not a finding):** the LEGACY-01a delta-stat interaction means a player who
> opens early but claims LATE, AFTER independently buying a pass that raised `frozenUntilLevel`, gets
> `deltaFreeze` reduced (no double-dip) — so a late claim can also UNDER-deliver stats relative to an
> early claim. This is the SAME no-double-dip cap working as designed; it strictly bounds the award DOWNWARD,
> never upward. Recorded as a non-finding (favors the protocol).

---

## LEGACY-01b — deferred-claim FREEZE-safety (re-verify WHALE-04 IN CODE, not from the paper proof)

**PROPERTY:** the box-open record carries the lootbox RNG index, and the deferred resolution cannot steer
which VRF word/index it reads — the index is anchored at deposit BEFORE the word lands.

**Backward trace from the deferred resolution to the commitment point:**
- The box value resolves against `lootboxRngWordByIndex[index]`. `index` is snapshotted ONCE at DEPOSIT:
  `_recordLootboxEntry` reads `lr = lootboxRngPacked` and derives
  `index = (lr >> LR_INDEX_SHIFT) & LR_INDEX_MASK` (`WhaleModule:850-851`) — the COMMITMENT POINT. The
  first deposit pushes `boxPlayers[index]` (`:888`); later deposits reuse the FROZEN packed record
  (`existingAmount != 0`). The word for that index is populated by a VRF request made AFTER the index is
  active but BEFORE the result is revealed; the consumer gates on `lootboxRngWordByIndex[index] != 0`.
- The **`claimWhalePass` path itself reads NO RNG** — grep of `WhaleModule:991-1008` shows zero
  `lootboxRng` / `entropy` / `word` reads. It queues DETERMINISTIC tickets (`_queueTicketRange`, no RNG
  arg) and applies DETERMINISTIC stats (`_applyWhalePassStats`, pure packed-math). The only live read is
  `level` (`:1003`), which is the horizon input (LEGACY-01), NOT an RNG seed. The trait RESOLUTION of those
  queued tickets happens LATER in the mint loop against the daily VRF word, snapshotted pre-RNG via the
  standard `_swapAndFreeze` slot-swap (the same freeze spine the v62 net re-attested; the queued tickets
  are far-future-keyed and rng-locked while a word is in flight — `_queueTicketRange` enforces
  `rngLockedFlag` on far-future keys @`Storage:699`).

**COMMITMENT POINT that settles it:** the lootbox index is committed at DEPOSIT (`WhaleModule:850-851`),
strictly before the word for that index is revealed; the deferred claim is RNG-independent and cannot
re-select the index. WHALE-04 freeze RE-VERIFIED in code (not trusted from the SPEC-334 paper proof).

**VERDICT (provisional):** REFUTED (no freeze break). Convergent with both council models on the box-record
half. Green-baseline anchor: `RngFreezeAndRemovalProofs.t.sol` + `RngWindowFreeze.inv.t.sol` (exercised,
non-vacuous per `REGRESSION-BASELINE-v63 §2`).

---

## LEGACY-02a — AFSUB pass-gating boundary + OPEN-E consent (re-attest)

**PROPERTY:** the inclusive-boundary refresh/evict is CODED as documented (keep while
`currentLevel <= validThroughLevel`, evict at `+1`), and the OPEN-E consent gate is checked at the SUBSCRIBE
point.

**Re-verification vs the frozen source:**
- **Inclusive boundary (as-coded, do NOT flag the leniency):** the per-walk compare is
  `if (currentLevel > sub.validThroughLevel)` (`AfkingModule:1246`) — it crosses ONLY when `currentLevel`
  strictly EXCEEDS the horizon, i.e. keeps the sub while `currentLevel <= validThroughLevel`, evicts at
  `+1`. This MATCHES the documented intended leniency ([[afking-pass-eviction-inclusive-boundary-intended]]).
  On crossing it re-reads `h = _passHorizonOf(player)` (`:1247`) and REFRESHES if `currentLevel <= h`
  (`:1248-1250`) else FINALIZES → `delete _subOf` → `_removeFromSet` swap-pop (`:1252-1264`).
- **No early eviction / no late retention:** a funded sub is kept until `currentLevel` strictly exceeds its
  horizon (no early drop); a stale `validThroughLevel` is re-read against the CANONICAL `_passHorizonOf`
  at the crossing (no late retention past the true horizon — a refresh only happens if the player genuinely
  re-extended the pass). `_passHorizonOf` (`:596-606`) is the SAME canonical source at both the subscribe
  write (`:419`) and the crossing re-read (deity sentinel `type(uint24).max` / else `frozenUntilLevel`) —
  no two-source skew.
- **No-pass guard:** `subscribe` rejects a non-exempt subscriber with `validThroughLevel == 0` or
  `< level` (`:414-428`) — a zero horizon (no pass) is rejected at EVERY level including level 0.
- **OPEN-E consent (subscribe-only):** SUB-02 self/operator gate `operatorApprovals[subscriber][msg.sender]`
  (`:314-320`); OPENE-04 non-self `fundingSource` gate `operatorApprovals[fundingSource][subscriber]`
  (`:322-330`). Both checked AT SUBSCRIBE; the comment + the ruling
  ([[open-e-operator-approval-trust-boundary]]) document that a later revoke does not stop an active sub and
  a re-point = re-subscribe re-checks — INTENDED. The `exemptSub` carve-out is strictly VAULT/SDGNRS
  (`:414-416`). No bypass at subscribe; not modelling a tricked-into-approving actor (operator-approval IS
  the trust boundary).

**VERDICT (provisional):** REFUTED / BY-DESIGN-CONFIRMED-AS-CODED. Convergent with both council models.
Green-baseline anchor: the Phase-336 AFSUB sweep/evict/refresh + no-pass-SLOAD oracle, carried in
`REGRESSION-BASELINE-v63` (854/0).

---

## LEGACY-02b — MINTDIV index alignment / quadrant LOCKSTEP (dedicated — the council-divergent SPINE candidate)

**The divergence:** gemini flagged a SPINE quadrant bias — `processed` re-declares 0 each call
(`MintModule:582/880`) and is NOT persisted across a write-budget split, so the quadrant offset
`(uint8(i & 3) << 6)` (`:761`), keyed on the within-call `i = processed…`, resets mid-player → a
budget-split-dependent / gas-dependent quadrant distribution a player could force. codex cleared it
(reset only at `remainingOwed == 0`).

**Independent lockstep + dual-gate analysis vs the frozen source:**

1. **`processed` is a WITHIN-CALL cursor — gemini's mechanical observation is CORRECT.** Confirmed at the
   frozen source: `processed` is a function-local declared `uint32 processed;` at `MintModule:582` (future
   loop) and `:874` (current-level caller), reset to 0 at the start of every `advanceGame` call. Within a
   call it advances `processed += take` (`:667` / `:902`) and resets to 0 ONLY when a player finishes
   (`remainingOwed == 0` → `++idx; processed = 0` at `:672-676` / `:896-897`) or on a skip/cleanup
   next-player move (`:597-618`). On a budget-split mid-player stop, the `while` breaks WITHOUT resetting
   `processed`, but the NEXT `advanceGame` call re-enters with `processed = 0` (fresh local). So across a
   split, call 1 writes `_raritySymbolBatch(startIndex=0, count=take_1)` and call 2 writes
   `_raritySymbolBatch(startIndex=0, count=take_2)` — the quadrant index `i & 3` DOES restart from 0 in
   call 2, NOT continue from `take_1 & 3`. **gemini's "the quadrant does not continue across the split" is
   structurally accurate.**

2. **But the quadrant is NOT a positional/ordering property that must be preserved — it is a RANDOM
   DISTRIBUTION mechanism. This is where gemini's SEVERITY claim fails the skeptic gate.** The decisive
   semantic fact (read from `DegenerusTraitUtils:143` + `Storage:425-441`): a trait ID is
   `traitFromWord(s) = (color << 3) | symbol` — a 6-bit value (0-63) — and the quadrant
   `(i & 3) << 6` adds the TOP 2 bits to form the full 8-bit trait ID (0-255). The
   `traitBurnTicket[level]` array is `address[][256]`: 256 BUCKETS, one per full trait ID, used for jackpot
   winner selection (random index into the trait's array — "more burns = more tickets = higher win
   probability"). The quadrant is the SAME role as `packedTraitsFromSeed`'s 4-way split
   (`TraitUtils:165-175`): it spreads a player's tickets across 4 quadrant-copies of each base trait so the
   tickets distribute over the bucket space. **There is NO contract that interprets the quadrant as ticket
   N's "position" — there is no per-player ordering invariant on quadrants.** A player's tickets are an
   unordered MULTISET deposited into the 256 buckets; the jackpot draws by random index. Restarting `i`
   from 0 on call 2 changes WHICH buckets a player's later tickets land in, but does NOT change HOW MANY
   tickets the player gets, does NOT drop or duplicate a ticket, and does NOT advantage the player.

3. **Lockstep proof (no drift / no double-write / no skip across a budget boundary).** The COUNT accounting
   is exact and independent of the quadrant: `take = min(owed, maxT)` is the actual tickets taken
   (`:634` / `_processOneTicketEntry:986-988`); the persisted debt drops by EXACTLY `take`
   (`owedMap[player] = remainingOwed = owed − take`, `:660-666` / `:1018-1020`); the index advances
   `processed += take` (`:667` / `:902`), NOT by a writes-derived count (the MINTDIV-02 fix that replaced
   `writesUsed >> 1` — confirmed in the `MintModule:898-901` comment + the `processed += take` at `:902`).
   Across a split: call 1 takes `take_1`, persists `owed − take_1`; call 2 reads `owed_2 = owed − take_1`,
   takes `take_2`, persists `owed − take_1 − take_2`; the player advances ONLY when the cumulative persisted
   debt reaches 0. **No ticket is written twice (each `take` consumes distinct owed units) and none is
   skipped (the persisted `owedMap` remainder is the resume anchor).** The two paths (future loop +
   `_processOneTicketEntry`) share the identical `_raritySymbolBatch` body and the identical
   `processed += take` accountancy → cross-path lockstep.

4. **Skeptic 3-condition lens on the residual quadrant-distribution variance:** (a) no value gained/lost
   (count exact); (b) the variance is over WHICH 4-way bucket a tail ticket lands in — the jackpot draw is
   over the full 256-bucket multiset and is itself RNG-driven, so a different quadrant placement does not
   change the player's expected win probability (the player's total ticket count in level L is unchanged;
   the buckets are all equally drawn from the daily VRF word); (c) NOT player-steerable to an EV edge — to
   "force a split at a specific offset" the player would need to control the global queue position, the
   per-call `WRITES_BUDGET`, the cold/warm 65% scaling, and the set of co-queued players, AND the resulting
   quadrant change would have to map to a jackpot-selection advantage that does not exist (the draw is over
   the level-wide trait buckets, not a player's quadrant ordering). The gate does NOT pass for HIGH.

5. **Green-oracle corroboration.** `test/edge/MintBatchDeterminism.test.js` (GREEN at `a8b702a7`,
   854/0) is the cross-path-equality oracle: its W2 indexer-replay (TST-FIX-01) reconstructs the trait
   MULTISET by replaying `raritySymbolBatchRef.mjs` with a PER-CALL `cumProcessed = 0` accumulator
   (`MintBatchDeterminism:175-178`) and asserts it equals the on-chain credited multiset trait-by-trait via
   `getTickets(trait, lvl, …)` over EVERY trait id 0..255 (i.e. INCLUDING the quadrant bits 6-7). The
   reference model RESETS `processed` per call exactly as the contract does, and the on-chain credit MATCHES
   — so the per-call reset is the TESTED, intended behavior and the credited 256-bucket multiset is the one
   the oracle pins. (The test's header comment line 36-37 mentioning `processed += writesUsed >> 1` for
   Path B is STALE prose describing the pre-MINTDIV-02 code; the live caller is `processed += take` at
   `:902`, and the reference replay uses the emitted values, so the test asserts the live behavior — a
   comment-only staleness, not a code divergence. Flag for a future comment trim, not a finding.)

**VERDICT (provisional):** **REFUTED as a SPINE/value finding; the quadrant is a distribution mechanism,
not an ordering invariant.** gemini's mechanical observation (the quadrant `i` restarts per call) is correct
but does NOT break value-equivalence: the COUNT is exact and lockstep across budget splits (no
drift/double-write/skip), and the residual quadrant placement variance carries no EV edge and is the tested
behavior of the green oracle. codex's "lockstep holds for the charged property" is the correct verdict on
the count accounting. The single substantive nuance the council MISSED on BOTH sides: neither model named
WHY the quadrant restart is harmless (the `address[][256]` bucket semantics + the jackpot draw being over
the level-wide multiset) — NET 2 supplies that as the settling reason.

---

## Fold-in of the NET 1 council leads (read AFTER the independent pass)

| Council lead (394-01) | NET 1 split | NET 2 independent result | Reconciliation |
|---|---|---|---|
| LEGACY-01 horizon drift | codex FINDING (SPINE) vs gemini SOUND | BY-DESIGN (D-04/D-20 documented, no extraction) | codex mechanism correct + gemini outcome correct; the `LootboxModule:1483-1485` D-04 doc is the tie-breaker — documented intent, count-equivalent, non-extractable |
| LEGACY-01b box-open record freeze | convergent SOUND | REFUTED (index committed at deposit; claim RNG-independent) | convergent across both nets |
| LEGACY-02a AFSUB boundary + OPEN-E | convergent SOUND | REFUTED / as-coded-by-design | convergent across both nets |
| LEGACY-02b MINTDIV quadrant | gemini FINDING (SPINE) vs codex SOUND | REFUTED (count lockstep exact; quadrant = distribution, not ordering) | codex count-lockstep correct; gemini's mechanical restart correct but non-harmful — NET 2 supplies the bucket-semantics reason both models missed |
| Cite-drifts (lead 5) | bookkeeping | re-pinned in the table above | `_applyWhalePassStats` @Storage:1338 (not 195-300); `processed += take` @902 (not writesUsed>>1) |

**No council-only lead remains un-adjudicated.** Both divergent SPINE candidates are settled at the frozen
source with the skeptic dual-gate: neither survives to a HIGH.

---

## Byte-freeze attestation (end of NET 2)

- `git diff a8b702a7 -- contracts/` → **EMPTY** (subject byte-frozen; NET 2 wrote only this `.planning/`
  doc).
- No `hardhat compile --force` was run (only `git show` reads). T-394-07 (tampering) mitigation satisfied.
- Full-tree `git status` shows only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html` (not produced
  by this analysis) and this new `.planning/` deliverable.

**NET 2 (the Claude adversarial net) is ON RECORD for the v50 slice** — independent per-item attack +
provisional verdict, the whale-pass O(1) value-equivalence + freeze re-verified in code, the AFSUB
boundary/consent confirmed as-coded, the MINTDIV lockstep proven with the settling bucket-semantics reason,
and the council leads folded in. Provisional verdicts: **0 CONFIRMED findings** (LEGACY-01 BY-DESIGN,
LEGACY-01b/02a/02b REFUTED). Synthesis + the deferred `audit/FINDINGS-v50.0.md` follow in Task 2.
