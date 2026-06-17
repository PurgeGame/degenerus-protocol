# Council Sweep 394-01 — LEGACY-DEBT / the v50 surface slice (LEGACY-01, LEGACY-02)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top of the
frozen subject). Be concrete and reachable: a finding needs a real ordered call sequence (the multi-tx
claim/subscribe/advance interleaving, or the budget split across `advanceGame` chunks — where the ordering
matters) and a named state variable with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the **long-deferred v50 contract surface** of the protocol — the v50 changes that closed
via a MINIMAL CLOSE WITHOUT the internal adversarial sweep, now folded into v63.0:

- the **whale-pass O(1) deferred-claim path** — the rework that retired the inline ~100-loop pass mint and
  replaced it with a deferred `claimWhalePass` that materializes a deterministic pre-calculated ticket award
  on demand, plus the pass-bundled-deposit box-open record that enqueues the box for the permissionless
  auto-open cursor (`_recordLootboxEntry` + the `LootBoxBuy` event carrying the lootbox RNG index);
- the **AFSUB pass-gating** — the funded-subscriber continuation gates: the `validThroughLevel` refresh /
  eviction, the per-walk inclusive-boundary compare, and the OPEN-E operator-approval consent gate checked
  at subscribe;
- the **MINTDIV index alignment** — the v50 fix that advances the within-player trait write index by the
  ACTUAL tickets taken this iteration (`processed += take`), keeping the trait write cursor and the
  cross-path ticket walk in lockstep across a write-budget split.

We believe the following holds across this surface: the deferred O(1) whale-pass claim is
**value-equivalent** to the retired inline mint and **freeze-safe**; the AFSUB pass-gating refreshes /
evicts at the intended **inclusive boundary** with the OPEN-E operator-approval consent checked at the right
point; and the MINTDIV index alignment keeps every cross-path mint index in **lockstep** with no drift /
double-write / skip. **Your job is to find where one of these beliefs breaks.**

The two requirements this slice charges:
- **LEGACY-01** — the v50 whale-pass O(1) deferred-claim path + the box-open record.
- **LEGACY-02** — the v50 AFSUB pass-gating (`validThroughLevel` eviction/refresh + the OPEN-E re-attest) +
  the MINTDIV index alignment.

## Threat priority (USER-locked for this slice)

DOMINANT = **RNG/freeze** — a break on the whale-pass deferred claim or the box-open record where a VRF
word / lootbox index that became player-controllable or publicly known AFTER the player's commitment point
enters the materialized outcome is the HIGHEST-severity class here; weigh it accordingly. SPINE = **solvency
/ value-non-equivalence** — the O(1) path materializing MORE or LESS box/pass value than the retired inline
mint would have (over- or under-delivery), or the MINTDIV alignment double-writing / skipping a ticket so a
player mints EXTRA traits or LOSES paid-for traits, is the spine concern of this phase. HIGH = gas-DoS only
in the `advanceGame` chain (16,777,216 gas = brick). LOW/confirmatory = access-control / reentrancy / MEV —
an access issue on the consent gate is confirmatory. A pure desirability complaint about the documented
inclusive boundary or the operator-approval funding overload is **NOT a finding**.

## Trust-boundary framing (so you do not waste passes)

- The **whale-pass claim is permissionless-for-beneficiary**: `claimWhalePass(player)` delivers the
  deterministic ticket award to `player` (the box recipient / pass winner), never to `msg.sender`. The
  caller cannot redirect value. The question is value-equivalence + freeze-safety + single-shot, NOT who
  may call it.
- The **AFSUB subscribe consent gate** is the boundary between a self/operator-approved subscribe and an
  unauthorized one. The question is whether the SUBSCRIBE-time check is present at the right point, NOT
  whether an approval can be socially engineered.
- The **MINTDIV index walk** runs INSIDE the GAME advance/mint path (a delegatecall target over the shared
  `DegenerusGameStorage` base). The question is whether the within-player write cursor and the cross-path
  ticket walk stay aligned under a write-budget split.

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- **The AFSUB pass-eviction INCLUSIVE boundary is INTENDED.** A funded subscriber is kept while
  `currentLevel <= validThroughLevel` and evicted at `currentLevel > validThroughLevel` (i.e. at +1) —
  deliberately ONE level more lenient than the strict-`>` gates elsewhere. Do NOT flag the leniency.
  **VERIFY the boundary is CODED as the documented inclusive compare** (the per-walk compare matches the
  keep-while-`<=` / evict-at-`+1` shape) — that is the in-scope question, not the desirability of the extra
  level.
- **The OPEN-E operator-approval IS the trust boundary.** The BURNIE-funding operator overload is
  accepted-by-design; do NOT model a "tricked into approving" actor or post-subscribe revocation as a
  finding. The documented intent is: a later revoke does NOT stop an active sub, and re-pointing the funding
  source IS a re-subscribe that re-checks the gate. The in-scope question is whether the SUBSCRIBE-time
  consent gate (subscriber self-consent OR operator-approval; a non-self funding source operator-approved by
  the subscriber) is CHECKED at the right point — NOT whether approval can be engineered.
- **The whale-pass / WWXRP economics are by-design** — the whale pass is rated near-worthless / the WWXRP
  token deliberately near-worthless. **VERIFY the O(1) path's value-equivalence and freeze-safety, NOT the
  pass's worth.** Do not flag "the pass is worthless" or "RTP too high".
- **An admin/protocol-address breaking its OWN game/position at genesis with no engaged community is a
  non-finding.**
- **Lootbox / redemption claim/open TIMING is not a player edge** — the box-open is permissionless and
  economically-incentivized; the seed is frozen at the index advance. Do not flag day/level/wait-to-open
  steering. (A path where the materialized outcome is NOT yet fixed at the player's commitment, or can be
  re-resolved fresh, IS in scope — that is a freeze break, not a timing edge.)

## The thesis to BREAK (mapped to LEGACY-01..02)

We believe ALL of the following hold. Find a concrete counterexample to any one — or VERIFY SOUND with the
specific reason it holds.

1. **(LEGACY-01) The whale-pass O(1) deferred claim is value-equivalent to the retired inline mint and
   freeze-safe**, the box-open record enqueues the pass-bundled box once with the right index, and the claim
   is single-shot (no double-claim / replay).
2. **(LEGACY-02a) The AFSUB pass-gating refreshes / evicts at the correct inclusive boundary**, and the
   OPEN-E operator-approval consent gate is checked at the right point (subscribe-time).
3. **(LEGACY-02b) The MINTDIV index alignment keeps every cross-path mint index in lockstep** — every path
   advances `processed` by exactly `take`, the write-budget split never drops or duplicates a ticket, and
   the per-player boundary reset is off-by-one-clean.

## Authoritative frozen line-cites (read the code via `git show a8b702a7:...`, do not trust the cite blindly)

These cites are verified at `a8b702a7` — supplied so you read the RIGHT code; re-read each via
`git show a8b702a7:contracts/<File>.sol` and confirm the line, do not trust the cite blindly.

- **WHALE-PASS O(1) deferred-claim (LEGACY-01):**
  - `contracts/DegenerusGame.sol`: `claimWhalePass(address player)` @1503 (`_resolvePlayer` then
    `_claimWhalePassFor` @1505) → `_claimWhalePassFor` @1508 → `delegatecall`
    `IDegenerusGameWhaleModule.claimWhalePass.selector` @1513-1514 (thin dispatch stub).
  - `contracts/modules/DegenerusGameWhaleModule.sol`: `claimWhalePass(address player)` @991 — the O(1)
    deferred materialization: `if (_livenessTriggered()) revert` @992; `halfPasses = whalePassClaims[player]`
    @993; early-return if zero @994; **clear-before-award** `whalePassClaims[player] = 0` @997 (double-claim
    guard); `startLevel = level + 1` @1003; `_applyWhalePassStats(player, startLevel)` @1005;
    `_queueTicketRange(player, startLevel, 100, uint32(halfPasses), false)` @1007 (the deterministic award:
    `halfPasses` tickets/level × 100 levels starting at `level+1`).
  - the box-open record on pass-bundled deposits: `_recordLootboxEntry(buyer, lootboxAmount, cachedPacked)`
    @841 — single read `lr = lootboxRngPacked` @850; `index = uint48((lr >> LR_INDEX_SHIFT) & LR_INDEX_MASK)`
    @851; first-deposit branch `existingAmount == 0` @860 snapshots `score` / EV-cap (DIV-2) and
    `boxPlayers[index].push(buyer)` @906 (the producer-only enqueue for the permissionless auto-open cursor;
    consumer gates on `lootboxRngWordByIndex[index] != 0`); subsequent-deposit branch @908 reuses the FROZEN
    first-deposit score/mult; pending-eth rebuild @925-928; `emit LootBoxBuy(buyer, index, lootboxAmount,
    false)` @931 (`presale` always false for a pass box). Callers: whale @371, lazy @514, deity @677.
- **AFSUB PASS-GATING (LEGACY-02a):**
  - `contracts/modules/GameAfkingModule.sol`: subscribe consent gate — `FREEZE-01` rngLocked block @311;
    `SUB-02` self-consent (`subscriber == msg.sender` OR `operatorApprovals[subscriber][msg.sender]`)
    @314-320; `OPENE-04` non-zero non-self `fundingSource` must be operator-approved by the subscriber
    (`operatorApprovals[fundingSource][subscriber]`) @322-330 (checked HERE only — renewal/per-draw never
    re-check). Refresh: `s.validThroughLevel = _passHorizonOf(subscriber)` @419 (deity sentinel
    `type(uint24).max`); the no-pass / outgrown-pass subscribe-time guard
    `if (!exemptSub && (s.validThroughLevel == 0 || s.validThroughLevel < level)) revert NoPass()` @428-429;
    `exemptSub` = VAULT || SDGNRS @415-416. The per-walk inclusive-boundary crossing:
    `if (currentLevel > sub.validThroughLevel)` @1245 → on crossing re-read `h = _passHorizonOf(player)`
    @1246 → `if (currentLevel <= h)` REFRESH `sub.validThroughLevel = h` @1248-1249 else EVICT
    (tombstone-then-reclaim swap-pop) @1251+ — the INTENDED inclusive boundary (keep while
    `currentLevel <= validThroughLevel`, evict at +1).
- **MINTDIV index alignment (LEGACY-02b):**
  - `contracts/modules/DegenerusGameMintModule.sol`: the per-player trait write loop @587-681 — `processed`
    declared @582 (within-player progress); the budget-overhead reserve `baseOv` @630; `room` after reserve
    @633; `maxT = (room <= 256) ? room/2 : room - 256` @635; `take = owed > maxT ? maxT : owed` @636;
    `_raritySymbolBatch(player, baseKey, processed, take, ...)` @640-648 (the write call seeded at the
    `processed` cursor); the write-budget accounting `writesThis = (take <= 256) ? take*2 : take+256` @652
    (`+= baseOv` @653, `+= 1` if `take == owed` @654 — SEPARATE from the index advance); the v50 alignment
    `processed += take` @668 (advance the within-player index by ACTUAL tickets taken, NOT a writes-derived
    half-count); the per-player completion reset `processed = 0` @676 (also the skip/cleanup resets @608/617);
    the cross-path ticket walk `_processOneTicketEntry(queue[idx], lvl, owedMap, writesBudget - used,
    processed, ...)` @881-893 (passes the SAME `processed` cursor; resets `processed = 0` on advance @897,
    `processed += take` @903) — the cross-path walk that must stay in lockstep with the trait index; the
    `_processOneTicketEntry` definition @951.
- **Green oracle:** `test/REGRESSION-BASELINE-v63.md` = forge 854/0/110 (v50 empirical coverage carried
  from Phase 336: whale-pass equivalence + uniform-O(1) + freeze fuzz; AFSUB sweep/evict/refresh +
  no-pass-SLOAD oracle; MINTDIV cross-path equality).
- **Frozen-source read convention:** `git show a8b702a7:contracts/<File>.sol` (ignore the working tree).

## Concrete break-targets (the three v50 charge items — charge each HARD)

### 1. (LEGACY-01, the whale-pass O(1) value-equivalence + freeze-safety target)

The v50 rework replaced the inline ~100-loop pass mint with the O(1) deferred `claimWhalePass`
(`WhaleModule:991`, dispatched via `DegenerusGame:1503-1514`) that records a box-open entry on pass-bundled
deposits (`_recordLootboxEntry` @841 / `LootBoxBuy` @931 carrying the lootbox RNG index). Find:
- **(i) value NON-equivalence** — the deferred O(1) claim materializes a DIFFERENT pass horizon / stat set /
  ticket count / box value than the retired inline mint would have delivered (over- or under-delivery). Trace
  `whalePassClaims[player]` from where it is WRITTEN (the deferred half-pass count) to where it is CONSUMED
  (`_queueTicketRange(player, level+1, 100, halfPasses, false)` @1007 + `_applyWhalePassStats` @1005), and
  confirm the materialized award equals the inline mint's award for the same `halfPasses` — same start level
  (`level+1`, to avoid an already-active level), same tickets/level, same 100-level span, same stats. A
  mismatch (a start-level off-by-one, a halfPasses width truncation `uint32(halfPasses)` @1007, a missing
  stat) is a value-non-equivalence finding.
- **(ii) a FREEZE break** — the deferred claim or the box-open record reads a VRF word / lootbox index that
  became player-controllable or publicly known AFTER the player's commitment point. The box binds to
  `lootboxRngWordByIndex[index]` and the producer-only `boxPlayers[index].push` @906 enqueues at the CURRENT
  `lootboxRngPacked` index @851; confirm the index the box queues at is fixed at the DEPOSIT (the
  commitment), the materialized roll descends from a word committed BEFORE the deposit, and the deferred
  `claimWhalePass` award is a DETERMINISTIC pre-calculated count (no live VRF read at claim time — the
  ticket count is `whalePassClaims[player]`, fixed when the deferred entry was written). The
  WHALE-04 freeze-safety was proven on paper at SPEC 334 — **re-verify in code at the frozen source, do not
  trust the prior paper proof.**
- **(iii) double-claim / replay** — `claimWhalePass` can be re-driven to materialize the pass or the box
  twice. Confirm the **clear-before-award** `whalePassClaims[player] = 0` @997 precedes the
  `_queueTicketRange` award @1007 (so a reentrant or repeated call sees zero and early-returns @994), and
  that `boxPlayers[index].push` @906 fires ONCE per first deposit (`existingAmount == 0` @860, so a second
  deposit at the same index takes the subsequent-deposit branch @908 and does NOT re-enqueue).

VERIFIED SOUND requires the value-equivalence reasoning (the materialized award arithmetic equals the inline
mint's) + the freeze snapshot cite (the index/word committed before the deposit; the claim count
pre-calculated) + the single-shot clear-before-award / first-deposit-only enqueue.

### 2. (LEGACY-02a, the AFSUB refresh/evict boundary + the OPEN-E consent point target)

The `validThroughLevel` refresh (@419) / subscribe-time no-pass guard (@428-429) / per-walk inclusive
crossing compare (@1245-1249) gate a funded subscriber's continuation; the OPEN-E operator-approval
(OPENE-04 @322-330, checked at subscribe ONLY) gates a non-self funding source. Find:
- **(i) an eviction-boundary defect** — a subscriber evicted EARLY (before `currentLevel >
  validThroughLevel`) or retained LATE (a stale `validThroughLevel` kept funded past its horizon). **Confirm
  the inclusive boundary is CODED as documented** — the per-walk compare @1245 is `currentLevel >
  sub.validThroughLevel` (so it keeps while `currentLevel <= validThroughLevel` and evicts at +1), the
  crossing re-read @1246 + `currentLevel <= h` refresh @1248 covers a newly-minted/upgraded pass, and the
  EVICT branch finalizes the streak + deletes the slot. Do NOT flag the intended leniency — flag only if the
  compare does NOT match the documented keep-while-`<=` / evict-at-`+1` shape, or if a stale
  `validThroughLevel` can be kept funded past its real horizon, or if the crossing re-read can refresh to a
  horizon that does NOT actually cover `currentLevel`.
- **(ii) a consent-gate bypass at subscribe** — a non-self `fundingSource` subscribed WITHOUT
  `operatorApprovals[fundingSource][subscriber]` (OPENE-04 @322-330 skipped or short-circuited wrongly), or
  the subscriber-consent SUB-02 check @314-320 skipped (a `player != msg.sender` subscribe without
  `operatorApprovals[subscriber][msg.sender]`). NOTE: the documented intent is that a later revoke does NOT
  stop an active sub and re-pointing the source IS a re-subscribe that re-checks @419+ — so the question is
  the SUBSCRIBE-time check, NOT post-subscribe revocation. Confirm both gates fire at subscribe (the
  `subscriber != msg.sender` branch and the `fundingSource != address(0) && fundingSource != subscriber`
  branch) and that the `exemptSub` (VAULT/SDGNRS @415-416) carve-out does NOT widen to a non-protocol
  subscriber. Confirm the gate is checked at the right point, or surface a finding.

### 3. (LEGACY-02b, the MINTDIV index alignment — lockstep, no drift / double-write / skip target)

The v50 alignment advances the within-player trait index by `processed += take` (`MintModule:668`), where
`take = min(owed, maxT)` (@636) is the ACTUAL tickets taken this iteration, with the writes-budget
accounting (`writesThis` @652-654) kept SEPARATE from the index advance. Find:
- **(i) a cross-path divergence** — the trait write index (`processed` fed to `_raritySymbolBatch` @642) and
  the ticket walk index (the `_processOneTicketEntry` caller @881-893, passing the SAME `processed`) fall
  OUT of lockstep so a ticket is processed TWICE (double-write / extra mint) or SKIPPED (paid traits lost),
  under a write-budget boundary that splits a player's mint across multiple `advance` chunks. Trace the
  `processed` cursor across a chunk boundary: chunk 1 takes `take_1 < owed` (a partial player), persists
  `remainingOwed = owed - take` to `owedMap[player]` @663-666 WITHOUT resetting `processed` (the player is
  not finished), the call ends with `processed = take_1`; chunk 2 RE-ENTERS the loop for the SAME player —
  confirm `processed` is RE-INITIALIZED correctly at the start of the new call (a fresh call re-declares
  `processed` @582 = 0, but `owed` is now the persisted remainder, so the write must resume at the right
  trait offset). Confirm the trait write offset (`processed` within `_raritySymbolBatch`) and the
  ticket-consumed count (`owed` decremented via `owedMap`) cannot diverge so a ticket's traits are written
  twice or a ticket is consumed from `owedMap` without its traits written.
- **(ii) an off-by-one at the per-player boundary reset** — `processed = 0` @676 (completion) / @608 / @617
  (skip/cleanup) when a player completes mid-budget and the next player starts at `++idx` @674. Confirm the
  reset to 0 fires EXACTLY when `remainingOwed == 0` @672 (the player is done) and NOT while a partial
  remainder is still owed, so the next player starts at `processed = 0` and the just-finished player does not
  carry a stale cursor.

Confirm every path advances `processed` by exactly `take` and the budget split never drops or duplicates a
ticket (the trait write count == the `owed`-consumed count across all chunks), or surface a finding.

## Output (per item)

For each break-target AND each thesis point (LEGACY-01, LEGACY-02a, LEGACY-02b), state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE (the multi-tx claim/subscribe/advance
  interleaving, or the budget split across `advanceGame` chunks — where the ordering matters) · STATE VAR +
  `file:line` at `a8b702a7` · SEVERITY (per the threat priority above — a freeze break is DOMINANT, a
  value-non-equivalence / double-write / skip is SPINE) · WHY the existing guard / freeze-snapshot /
  write-budget / consent-check does NOT stop it.
- **VERIFIED SOUND:** the property and the SPECIFIC reason it holds — cite the freeze snapshot (the
  index/word committed before the deposit; the pre-calculated claim count), the value-equivalence arithmetic
  (the materialized award equals the inline mint's), the index-alignment invariant (`processed += take`; the
  write count == the consumed count across chunks), the clear-before-award / first-deposit-only enqueue, or
  the consent gate (subscribe-time SUB-02 + OPENE-04) — so the adjudicator can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7` via
`git show`. The council finds; the adjudicator (Claude) reconciles at 394-03.
