# Phase 299 — FIXREC Cluster E: `claimablePool` game-over family

**Cluster:** E — Slot S-16 (`claimablePool` uint128 packed in `DegenerusGameStorage`) writer races during the game-over drain window. The slot's value is consumed by `GameOverModule.handleGameOverDrain` at two SLOAD sites (`:91` `reserved = uint256(claimablePool) + …`; `:154` `postRefundReserved = uint256(claimablePool) + …`) and bounds (i) the deity-pass refund budget at `:110`, (ii) the terminal-decimator pool `decPool = remaining / 10` at `:166-:168`, and (iii) the terminal-jackpot `remaining` at `:182`. Lower `claimablePool` ⇒ larger `available` ⇒ larger downstream payouts; higher `claimablePool` ⇒ smaller `available` ⇒ smaller downstream payouts. The slot also gates whether the RNG word is read at all (`:99` `if (preRefundAvailable != 0) … rngWord = rngWordByDay[day]`).
**VIOLATIONs covered:** V-054, V-055, V-057, V-058, V-063, V-064, V-065 (7 logical entries — `D-43N-V44-HANDOFF-27`..`D-43N-V44-HANDOFF-33`).
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §14 row S-16 (slot decl `DegenerusGameStorage.sol:354`); §15 writer enumeration rows 178-189 (12 distinct writers; this cluster covers the 7 EOA-reachable VIOLATION writers; the 5 advance-stack writers carry EXEMPT-ADVANCEGAME tokens at V-053 / V-056 / V-059 / V-060 / V-061 / V-062); §16 verdict-matrix rows 388-400 (V-053..V-065 13 rows; this cluster covers the 7 VIOLATION rows); §5 consumer chain `handleGameOverDrain` B-3 / B-9 SLOAD sites; §C.B-3 writer enumeration table; §D rows D-3, D-4, D-6, D-7, D-13, D-14, D-15.
**Posture:** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` + zero `test/` mutations. Authorial output only.
**Drafted:** 2026-05-18

---

## Cluster preamble — `claimablePool` dual-role architecture (load-bearing for every §N.A below)

The `claimablePool` slot (uint128 packed at `DegenerusGameStorage.sol:354`) is the in-game accumulator counterpart of the per-player `claimableWinnings[player]` mapping. Every individual player credit (`claimableWinnings[player] += x`) is mirrored by a `claimablePool += x` increment in `_creditClaimable` (`DegenerusGamePayoutUtils.sol:101`); every individual player debit (`claimableWinnings[player] -= x`) is mirrored by a `claimablePool -= x` decrement at the spend / withdraw site. The slot's invariant (cited in `DegenerusGame.sol:18` source-of-truth comment) is **`address(this).balance + steth.balanceOf(this) >= claimablePool`** — the contract MUST hold enough ETH-equivalent reserves to cover every credited but-unwithdrawn player claim.

**Dual role of `claimablePool` per `feedback_design_intent_before_deletion.md` decomposition:**

1. **Post-credit reserve aggregate (positive direction):** `+=` writers represent legitimate ETH-equivalent value flowing INTO the player-claim pool. The advance-stack writers (`JackpotModule._addClaimableEth :763`, `JackpotModule._processDailyEth :1335`, `AdvanceModule._processStethYield :905`, `PayoutUtils._creditClaimable :101`, `GameOverModule.handleGameOverDrain :134, :171`) all run inside `advanceGame` and carry EXEMPT-ADVANCEGAME tokens (V-053, V-056, V-059, V-060, V-061). The EOA-reachable `+=` writer is `DegeneretteModule._addClaimableEth :1131` (reached from EOA `placeDegeneretteBet` → `_resolveBet` → `_distributePayout`), which is V-058 in this cluster.

2. **Post-withdraw debit aggregate (negative direction):** `-=` writers represent ETH-equivalent value flowing OUT of the player-claim pool (either to a player wallet via ETH transfer, or to another in-game accounting bucket like `futurePrizePool`). The EOA-reachable `-=` writers comprise V-054 (Decimator lootbox-portion debit), V-055 (mint shortfall debit), V-057 (Degenerette bet-fund pull-from-claimable), V-063 (`claimWinnings` withdrawal), V-064 (`useClaimableForMint` reuse), V-065 (`sweepSdgnrsClaim` sStonk-callback debit).

**Game-over consumer (`handleGameOverDrain`) SLOAD chain (§5 source-of-truth verbatim, verified by `Read` of `DegenerusGameGameOverModule.sol:79-180`):**

```
:84   totalFunds = address(this).balance + steth.balanceOf(address(this));
:91   reserved = uint256(claimablePool) + sDGNRS.pendingRedemptionEthValue();  // ← B-3 read #1
:93   preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;
:99   if (preRefundAvailable != 0) { rngWord = rngWordByDay[day]; ... }        // ← VRF read gated by claimablePool
:110  budget = preRefundAvailable;                                              // ← deity-refund budget
:116  refund = refundPerPass * purchasedCount;
:122  claimableWinnings[owner] += refund;
:134  claimablePool += uint128(totalRefunded);                                  // ← B-9 write (post-refund)
:139  gameOver = true;                                                          // ← TERMINAL LATCH
:154  postRefundReserved = uint256(claimablePool) + sDGNRS.pendingRedemptionEthValue();  // ← B-3 read #2
:156  available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0;
:166  decPool = remaining / 10;                                                 // ← terminal-decimator
:168  IDegenerusGame(this).runTerminalDecimatorJackpot(decPool, lvl, rngWord);
:182  IDegenerusGame(this).runTerminalJackpot(remaining, lvl, rngWord);         // ← terminal-jackpot
```

The consumer reads `claimablePool` TWICE in the same call: first at `:91` to compute `preRefundAvailable` (the VRF gate + deity-refund budget), then at `:154` after deity refunds and self-`+=` at `:134` to compute `postRefundReserved` and `available` (the terminal payout magnitude inputs). Any EOA writer that fires between `:84` and `:91` shifts the deity-refund branch + RNG gate decision; any EOA writer that fires between `:91` and `:154` shifts the terminal-payout magnitude; any EOA writer that fires between `:139` and `:154` exploits the post-`gameOver=true` window where the consumer is mid-execution.

**Multi-tx game-over window (load-bearing for actor game-theory):** The `handleGameOverDrain` consumer is invoked from `_handleGameOverPath` inside `advanceGame`. The advance-stack uses `STAGE_TICKETS_WORKING` and similar staged-resolution patterns that early-return when the daily resolution budget is exhausted, requiring the caller to re-invoke `advanceGame` across multiple transactions to complete a day's resolution. Between two such transactions, EOA-callable functions that lack a liveness gate remain callable. Specifically, the multi-tx window opens at the moment `rngWordByDay[day]` is written (latches the daily VRF outcome) and closes at the moment `handleGameOverDrain` runs to completion inside the final `advanceGame` tx. During this window, every unmitigated EOA writer of `claimablePool` can race the consumer's SLOAD at `:91` / `:154`. Catalog §5 §E rows E-1..E-6 enumerate this attack surface verbatim.

**`_livenessTriggered()` semantics (source-of-truth verbatim from `DegenerusGameStorage.sol:1243-1252`):**

```solidity
function _livenessTriggered() internal view returns (bool) {
    if (lastPurchaseDay || jackpotPhaseFlag) return false;
    uint24 lvl = level;
    uint32 psd = purchaseStartDay;
    uint32 currentDay = _simulatedDayIndex();
    if (lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS) return true;
    if (lvl != 0 && currentDay - psd > 120) return true;
    uint48 rngStart = rngRequestTime;
    return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD;
}
```

`_livenessTriggered()` returns true when EITHER (a) the game has been idle past the deploy / level timeout (`_DEPLOY_IDLE_TIMEOUT_DAYS` or 120 days), OR (b) the current daily VRF request has exceeded its grace period (`_VRF_GRACE_PERIOD`). Critically, `_livenessTriggered()` is the SAME gate that fires the `_gameOverEntropy` fallback inside `AdvanceModule` (per the comment block at `:1238-:1242`: "below that threshold, liveness stays false — players can propose a coordinator rotation"). When `_livenessTriggered() == true`, the game is in a state where the multi-tx game-over drain WILL fire on the next `advanceGame` call. Gating EOA writers on `!_livenessTriggered()` therefore closes the writer's open window exactly during the period where `handleGameOverDrain` is reachable in the same multi-tx resolution stack.

**`gameOver` flag separate from `_livenessTriggered`:** The `gameOver` boolean is latched at `handleGameOverDrain:139` (POST-consumer-SLOAD). The terminal post-gameover claim period begins at `gameOver == true`, during which `claimWinnings` and `sweepSdgnrsClaim` MUST remain reachable so that players can withdraw their credited winnings. The catalog's V-063 / V-065 fix tactic (a) is therefore `!_livenessTriggered() || gameOver` (NOT `!_livenessTriggered() && !gameOver`) — the gate closes the writer during the pre-`gameOver=true` multi-tx window where `handleGameOverDrain` is mid-execution, and re-opens it permanently once `gameOver = true` so players can withdraw.

**Phase 281 precedent NOT selected here** (per `feedback_design_intent_before_deletion.md` decomposition): for the `prizePoolsPacked` family (Cluster B), tactic (b) snapshot-at-`_swapAndFreeze` was selected because the daily VRF axis is independent of the player-claim-debit axis. For the `claimablePool` family, the consumer is `handleGameOverDrain` — a one-shot terminal consumer — and the multi-tx window is a discrete TIME-BOUNDED interval rather than a recurring daily axis. Tactic (a) gated-revert is structurally minimal: a single `if (_livenessTriggered() && !gameOver) revert E();` (or `if (_livenessTriggered()) revert E();` for non-claim-withdraw writers) closes the open window with zero storage delta and zero new SSTORE/SLOAD on the hot path. Tactic (b) snapshot is rejected here because (i) the `claimablePool` slot's writes mid-window are NOT recurring side-effects of the daily VRF axis but rather discrete EOA-triggered events, (ii) the consumer's SLOAD at `:91` / `:154` is a one-shot read with no intermediate state to preserve, (iii) the same gate that closes the open window automatically blocks downstream writers that share the same EOA entry surface.

**`RngLocked` pattern precedent (in-source):** The `MintModule:1215`, `:1221`, `:1381` callsites already use the `if (_livenessTriggered()) revert E();` pattern (and additionally `if (cachedJpFlag && rngLockedFlag) revert RngLocked();` in some paths). This is the canonical in-source gate pattern; tactic (a) for this cluster mirrors that pattern verbatim. The same revert-on-`_livenessTriggered` gate appears at `MintModule:877` and `:906` (additional mint family entry points). Catalog §5 §E rows E-1..E-4 + E-6 explicitly cite this in-source pattern as the structurally minimal fix shape.

Per `feedback_design_intent_before_deletion.md`: each §N.A below traces the original design intent of the writer's open window (why it lacks a gate in the v43.0 baseline) before recommending the gate. Per `feedback_verify_call_graph_against_source.md`: every catalog row's `writer + callsite` claim was grep-verified against current source — see the "Source verification" line in each §N entry. Per `feedback_rng_window_storage_read_freshness.md`: `claimablePool` is a non-VRF SLOAD consumed alongside the VRF word at `handleGameOverDrain:99` (the VRF read at `rngWordByDay[day]` is gated on the SLOAD result), so this slot is a distinct bug class per the F-41-02 / F-41-03 precedent — the "freshly-read non-VRF storage alongside RNG" class.

---

## §1 — V-054: `claimablePool -=` via `DecimatorModule._creditDecJackpotClaimCore` (EOA `claimDecimatorJackpot`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 389 (V-054). §5 §D row D-3 (VIOLATION). §15 row 179 (writer enumeration). §C.B-3 row C-B3-2. §5 §E row E-1 (tactic (a) rationale).

**Source verification:** Grep `grep -n "claimablePool\|_awardDecimatorLootbox\|_creditDecJackpotClaimCore" contracts/modules/DegenerusGameDecimatorModule.sol` confirms the writer site at `:388` (`claimablePool -= uint128(lootboxPortion);`) inside `_creditDecJackpotClaimCore` (function defined at `:376-:390`). The catalog's writer-label `_awardDecimatorLootbox` is slightly imprecise — the actual `claimablePool -=` SSTORE lives in `_creditDecJackpotClaimCore`, which then calls `_awardDecimatorLootbox(account, lootboxPortion, rngWord)` at `:389` to mint the lootbox itself (the lootbox-minting function is at `:570` and does NOT write `claimablePool` directly). For verdict-matrix purposes the row is correctly classified as a `claimablePool -=` writer reachable from EOA `claimDecimatorJackpot`; the writer-function-name label is a CATALOG-LABEL-INACCURACY (not a stale-phantom — the source line exists and the verdict is correct). The Phase 303 TERMINAL acknowledgment should note this label refinement.

### §1.A — Design-intent backward-trace

**Slot introduction phase:** `claimablePool` was introduced as the in-game ETH-equivalent reserve aggregate alongside the `claimableWinnings[player]` mapping in the v40-era prize-distribution architecture. The Decimator subsystem (DegenerusGameDecimatorModule.sol) was added as the per-level "death bet" jackpot mechanism where each level's last-decimator wins a winner-take-most pot; the winning bucket's per-claimant payouts (`_consumeDecClaim` → `_creditDecJackpotClaimCore`) split 50% ETH (credited via `_creditClaimable` to `claimableWinnings[claimant]` and `claimablePool`) + 50% lootbox tickets (the `lootboxPortion` is then DECREMENTED from `claimablePool` at `:388` because the lootbox-portion stops being claimable ETH at the moment of claim).

**Why the decrement exists at this site:** The 50% lootbox-portion flow conceptually transfers ETH out of the per-player claimable bucket and into the per-player lootbox-ticket bucket. The `claimablePool` decrement is the in-contract accounting mirror: pre-claim the entire `amountWei` was reserved against `claimablePool` (it had been previously credited via `_creditClaimable` when the decimator pot was filled); at claim time the 50% lootbox portion is no longer "claimable ETH" — it's routed into the lootbox subsystem via `_awardDecimatorLootbox`. The decrement at `:388` preserves the `address(this).balance + steth.balanceOf(this) >= claimablePool` invariant by reducing `claimablePool` matching the 50% that's no longer claimable as ETH (the lootbox-portion is still held by the contract but is now accounted as `futurePrizePool` via the `_setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);` write at `:341`).

**Cite for "what would break if naively gated":** The function `claimDecimatorJackpot` already has TWO gating conditions at `:325` (`if (prizePoolFrozen) revert E();`) and `:329` (`if (gameOver) … return;` after `_creditClaimable`-only branch). The `prizePoolFrozen` gate fires during the daily VRF window (separate from `_livenessTriggered()` — `prizePoolFrozen` is true between `_swapAndFreeze` and the freeze-release). The `gameOver` branch routes pure ETH credit (no lootbox-portion split) to the player. The missing gate is the multi-tx-pre-`gameOver=true` window: between `_livenessTriggered() == true` and `gameOver == true`, the function remains callable AND falls through the prizePoolFrozen gate (`prizePoolFrozen` may be cleared by then) AND takes the non-gameOver branch (`gameOver` still false), invoking `_creditDecJackpotClaimCore` and writing `claimablePool -=` at `:388`. The fix MUST not break the legitimate pre-liveness use of the function (normal level-transition decimator claims during active gameplay), so the gate must be `_livenessTriggered()` (not `gameOver`).

**Precedent for tactic (a) gate selection:** The `MintModule.sol:1215, :877, :906, :1381` already use `if (_livenessTriggered()) revert E();` for mint-family entries. The Decimator subsystem inherits this in-source pattern naturally — adding `if (_livenessTriggered()) revert E();` at the top of `claimDecimatorJackpot` (above the `prizePoolFrozen` check at `:325`) closes the open window. Per `feedback_frozen_contracts_no_future_proofing.md`, the gate is added at deploy-time and does not need to anticipate future use-cases beyond the explicit `(_livenessTriggered, gameOver)` matrix.

### §1.B — Actor game-theory walk

**Exploit-actor class:** Player holding an unclaimed winning decimator subbucket entry at the moment the multi-tx game-over drain begins. Concrete vector: a player who won a prior level's decimator claim (and has a non-zero `decClaimRounds[lvl].pool` AND has not yet called `claimDecimatorJackpot(lvl)`) observes the multi-tx game-over signal (`_livenessTriggered() == true` becomes externally observable via `livenessTriggered()` view at `DegenerusGame.sol:2147`).

**Action sequence during multi-tx game-over window (sequential):**

- T0: A previous level's `runRewardJackpots` resolution latched a decimator winner. The player holds an unclaimed decimator entry. `claimDecimatorJackpot` has been callable since the latch but the player has deferred the call.
- T1: `_livenessTriggered()` transitions to true (either VRF stalled past grace period OR idle-timeout fired). Anyone can call `advanceGame` to trigger `_handleGameOverPath` → `handleGameOverDrain`, but the multi-tx resolution stack may early-return on `STAGE_TICKETS_WORKING` if there is unfinalized prior-day jackpot bookkeeping.
- T2 (attacker move): Player observes the impending `handleGameOverDrain` call and front-runs by calling `claimDecimatorJackpot(lvl)` while `gameOver == false` AND `_livenessTriggered() == true` AND `prizePoolFrozen` happens to be false. The call enters `_creditDecJackpotClaimCore` at `:380`, executes `_creditClaimable(account, ethPortion)` at `:385` (credits player's claimable balance with 50% AND `claimablePool += ethPortion` inside `_creditClaimable`), then executes `claimablePool -= uint128(lootboxPortion);` at `:388` (debits `claimablePool` by 50%). NET: `claimablePool` shifts by `(ethPortion - lootboxPortion) = 0` if the split is exactly 50/50… but `ethPortion = amount >> 1` and `lootboxPortion = amount - ethPortion`, so for an even `amount` the two are equal and the net is zero; for odd `amount` they differ by 1 wei. The NET shift to `claimablePool` from this single action is small (∼0 wei).
- T3: The MORE impactful side-effect: `_setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);` at `:341` increases `futurePrizePool` by the lootbox-portion. This itself does not feed `handleGameOverDrain` (which reads `claimablePool` not `futurePrizePool`). The `_addClaimableEth` path inside `_creditClaimable` shifts `claimablePool += ethPortion` (positive), then `:388` shifts `claimablePool -= lootboxPortion` (negative). For an exactly-50/50 split, the NET shift is zero — meaning V-054's claim-window race is structurally near-zero EV on the `handleGameOverDrain` consumer specifically.
- T4: `handleGameOverDrain` runs. `claimablePool` at `:91` SLOAD is approximately unchanged from pre-T2. `preRefundAvailable` is approximately unchanged. Terminal payouts are approximately unchanged.

**EV magnitude estimate:** **LOW on the per-claim margin (~0 net `claimablePool` shift for the 50/50 split).** The catalog row 389 disposition is VIOLATION because the writer is structurally reachable from EOA during the open window AND because of strict-discipline classification (any non-EXEMPT writer is VIOLATION). The actual exploitable surface on `handleGameOverDrain`'s consumer-read is approximately neutral due to the 50/50 ETH/lootbox split symmetry (positive write in `_creditClaimable` ≈ negative write at `:388`). The catalog-listed EV in the §0 headline "structural-hardening cluster" frames this row as a hardening case rather than a high-EV exploit. Economic-likelihood disposition: **unlikely-exploited as a magnitude-shift on `claimablePool`**; **possible-exploited on adjacent side-effects** (the `_setFuturePrizePool` write at `:341` shifts `futurePrizePool` which DOES feed other consumers, but those consumers are outside Cluster E's scope — they belong to Cluster B `prizePoolsPacked` family at V-029..V-035 and have their own tactic-(b) snapshot disposition).

**Cross-side-effect note:** Although V-054 itself is low-EV on the `claimablePool` consumer, the SAME callsite triggers a `_setFuturePrizePool` shift that is exploited under Cluster B V-035 (or sibling). The fix for V-054 — adding `_livenessTriggered()` gate to `claimDecimatorJackpot` — automatically closes V-035's adjacent exploit on the SAME entry function. Cluster E's gate-(a) fix therefore has a positive externality on Cluster B.

### §1.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert.** Catalog §5 §E row E-1 rationale: "Gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window." Catalog §16 row 389 rationale: "Gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window."

**Concrete shape:**

- Add `if (_livenessTriggered()) revert E();` at the TOP of `claimDecimatorJackpot` (`DegenerusGameDecimatorModule.sol:321`), above the existing `if (prizePoolFrozen) revert E();` at `:325`. The new gate covers the multi-tx-pre-`gameOver=true` window where `_livenessTriggered() == true` but `gameOver == false`.
- Post-`gameOver = true`, `_livenessTriggered()` may continue to return true (it doesn't reset on the `gameOver` latch — re-reading the source at `DegenerusGameStorage.sol:1243-:1252` confirms there is no `gameOver`-reset clause). The post-gameOver-claim period in this function (the `:329-:333` branch routing pure ETH credit via `_creditClaimable`) MUST remain reachable. The gate therefore must be `if (_livenessTriggered() && !gameOver) revert E();` (mirroring V-063 / V-065 below) OR alternatively the function can be split into pre-gameOver and post-gameOver entry points. The single-revert form `if (_livenessTriggered() && !gameOver) revert E();` is structurally simpler and preserves the existing function signature.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: the consumer's SLOAD is a one-shot read inside `handleGameOverDrain` (no recurring daily axis to anchor against). Snapshotting `claimablePool` at the moment `_livenessTriggered()` first transitions to true would require a new storage write AND would not eliminate the in-flight EOA writes between the snapshot and the consumer — it would only freeze the consumer's read at a pinned value, which under multi-tx game-over could be many blocks stale and incorrect for the live `address(this).balance` reading at `:84` (which is NOT snapshotted in the (b) variant). Tactic (a) is strictly cheaper and structurally complete.
- **(c) pre-lock reorder** rejected: the writer is EOA-triggered at attacker discretion and cannot be reordered before the consumer.
- **(d) immutable** rejected: `claimablePool` is fundamentally a mutable aggregate counter.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** No new fields, no struct reshape.
- **Bytecode delta:** ~30-50 bytes for the `if (_livenessTriggered() && !gameOver) revert E();` instruction sequence (one external view call OR direct internal call, one boolean AND, one comparison branch, one revert). Per catalog `RngLocked` revert pattern (`MintModule:1221` precedent), the in-source size is approximately 30 bytes.
- **Net runtime gas:** +~2000 gas warm SLOAD per `claimDecimatorJackpot` call (one extra `_livenessTriggered()` invocation, which itself reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime` — about 5 packed SLOADs, mostly warm in the same call frame). The gate fires on the cold path (rare); hot-path overhead is neutral.
- **Public ABI:** **NON-BREAKING.** No signature changes; the function still reverts under a strict superset of the existing revert surface. New revert reason matches the existing `error E()` pattern (no new custom error type).
- **Reference precedent:** `MintModule.sol:1215, :1221` `if (_livenessTriggered()) revert E();` pattern. Phase 290 MINTCLN `rngLockedFlag` discipline (`.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`).

### §1.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-27`** — Add `if (_livenessTriggered() && !gameOver) revert E();` at the top of `DegenerusGameDecimatorModule.claimDecimatorJackpot` (`DegenerusGameDecimatorModule.sol:321`), above the existing `prizePoolFrozen` gate at `:325`. The gate closes the multi-tx-pre-`gameOver=true` window where the `_creditDecJackpotClaimCore` writer at `:388` (`claimablePool -=`) is reachable from EOA.

- Target file:line: `DegenerusGameDecimatorModule.sol:321` (entry-function top).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 389 (V-054), §5 §D D-3 / §C.B-3-2 / §E E-1.
- CATALOG-LABEL-INACCURACY note: catalog labels the writer as `_awardDecimatorLootbox` (function at `:570`); actual `claimablePool -=` SSTORE is at `:388` inside `_creditDecJackpotClaimCore`. Phase 303 TERMINAL ack the label refinement.
- Positive externality: this fix also closes Cluster B V-035 (or sibling) adjacent exploit on `_setFuturePrizePool` at `:341`.

---

## §2 — V-055: `claimablePool -=` via `MintModule._resolveMintShortfall` (EOA `mintBatch` family)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 390 (V-055). §5 §D row D-4 (`EXEMPT-ADVANCEGAME` by-gate). §15 row 180 (writer enumeration). §C.B-3 row C-B3-3. §5 §E (NOT listed — covered by existing gate; FIXREC entry exists for strict-discipline verification).

**Source verification:** Grep `grep -n "claimablePool\|_livenessTriggered\|_resolveMintShortfall" contracts/modules/DegenerusGameMintModule.sol` confirms the writer site at `:949` (`claimablePool -= uint128(shortfall);`) inside `_resolveMintShortfall`. The EOA-facing entry function (one of `purchase :830` / `purchaseCoin :852` / `purchaseBurnieLootbox :864`) ALL route through `_purchaseFor` / `_purchaseCoinFor` / `_purchaseBurnieLootboxFor` which contain `if (_livenessTriggered()) revert E();` at `:877`, `:906`, `:1215` (verified by grep). The `_resolveMintShortfall` writer at `:949` is therefore UNREACHABLE from EOA when `_livenessTriggered() == true` — the entry-function-level gate already covers this case.

### §2.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The mint-family shortfall mechanism (the `_resolveMintShortfall` writer at `MintModule.sol:949`) was introduced as the path for players who wish to mint tickets using a COMBINATION of fresh ETH AND already-credited `claimableWinnings`. The shortfall represents the portion of the mint cost paid from the player's `claimableWinnings` bucket; the `claimablePool -=` at `:949` is the in-game accounting mirror of `claimableWinnings[buyer] -= shortfall` at `:947`.

**Why the `_livenessTriggered()` gate at the entry function:** Per Phase 290 MINTCLN design-intent (`.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`), the mint-family entries are gated to prevent purchase activity during the multi-tx VRF window. The gate prevents (a) buying tickets that would never be entered into the current day's draw, (b) shifting prize pools mid-VRF, (c) interfering with the daily settlement. The same gate (a structural superset of "purchase activity during VRF window") covers the `_resolveMintShortfall` writer transitively.

**Cite for "what would break if frozen":** Nothing breaks beyond what the existing `_livenessTriggered()` gate already blocks — the writer is structurally unreachable from EOA when the gate is closed, so no additional restriction is imposed. The FIXREC entry exists for strict-discipline classification (catalog row 390 carries VIOLATION token because the writer is `-=` on a `claimablePool` slot reachable from EOA in absence of a gate; with the gate in place the row is effectively EXEMPT-by-gate but the catalog uses strict tokens per `D-43N-AUDIT-ONLY-01`).

### §2.B — Actor game-theory walk

**Exploit-actor class:** None — the writer is structurally unreachable from EOA when `_livenessTriggered() == true`, which is exactly the condition under which the multi-tx game-over window opens.

**Action sequence during multi-tx game-over window:** Attacker attempts `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` after `_livenessTriggered()` transitions to true. The entry function reverts at `MintModule.sol:877` / `:906` / `:1215` with `error E()`. The `_resolveMintShortfall` writer at `:949` is never reached. `claimablePool` is unchanged.

**EV magnitude estimate:** **ZERO (structurally unreachable).** Catalog disposition is VIOLATION token under strict-discipline; actual exploit surface is empty. Economic-likelihood disposition: **non-exploitable in the deployed contract** (writer is gated by existing in-source guard).

**Branch-coverage concern (FUZZ-301 forward-attestation):** The catalog row 390 rationale notes "verify branch reach." Per `feedback_skip_research_test_phases.md` adjacent reasoning: the verification is whether FUZZ-301 (Phase 301 fuzz harness) exercises the `_livenessTriggered() == true` AND `mintBatch` entry paths together to confirm the revert fires before reaching `_resolveMintShortfall`. This is a TEST-coverage attestation rather than a SOURCE-code fix.

### §2.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert — ALREADY IN-SOURCE.** Catalog §16 row 390 rationale: "Existing `_livenessTriggered()` revert covers; verify branch reach."

**Concrete shape:**

- **No source-code change.** The existing entry-function gates at `MintModule.sol:877, :906, :1215` already close the open window.
- **FUZZ-301 forward-attestation:** Phase 301 (or whichever phase owns the FUZZ harness) MUST add a branch-coverage assertion that exercises `_livenessTriggered() == true` AND attempts each of `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / `mintBatch` (whichever family entries reach `_resolveMintShortfall`), asserting the call reverts BEFORE the `_resolveMintShortfall` writer at `:949` executes. The assertion shape is a Foundry / Hardhat coverage assertion (the writer's `claimablePool` value is unchanged by the reverted call).

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: the writer is unreachable; snapshotting `claimablePool` for a path that cannot fire is pure waste.
- **(c) pre-lock reorder** rejected: the writer is unreachable.
- **(d) immutable** rejected: the slot is mutable; the writer is unreachable.
- **Add a redundant gate at `_resolveMintShortfall:949`** rejected: defense-in-depth at the writer site would add ~30 bytes for zero marginal closure (the entry-function gate is the canonical guard; adding a duplicate at the writer site is precisely the kind of "future-proofing" prohibited by `feedback_frozen_contracts_no_future_proofing.md`).

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical (no change).
- **Bytecode delta:** 0 bytes (no source change).
- **Net runtime gas:** 0 (no change).
- **Public ABI:** byte-identical.
- **Reference precedent:** existing `_livenessTriggered()` gates at `MintModule:877, :906, :1215, :1381`.

### §2.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-28`** — Branch-coverage forward-attestation only. Phase 301 FUZZ harness MUST exercise the `(_livenessTriggered() == true, mint-family entry call)` branch and assert the call reverts before reaching `MintModule._resolveMintShortfall :949`. No source-code change in v44.0.

- Target file:line: `DegenerusGameMintModule.sol:949` (writer site; documented as gated-by-entry-function).
- Existing gate sites: `DegenerusGameMintModule.sol:877, :906, :1215, :1381`.
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 390 (V-055), §5 §D D-4 / §C.B-3-3.

---

## §3 — V-057: `claimablePool -=` via `DegeneretteModule._collectBetFunds` (EOA `placeDegeneretteBet`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 392 (V-057). §5 §D row D-6 (initially `EXEMPT-ADVANCEGAME` by-gate; classification updated to VIOLATION per §5 §E row E-1 / §16 row 392). §15 row 182 (writer enumeration). §C.B-3 row C-B3-5. §5 §E (covered jointly with V-058 via tactic-(a) gate on `placeDegeneretteBet`).

**Source verification:** Grep `grep -n "claimablePool\|_livenessTriggered\|_creditCheckedFromClaimable" contracts/modules/DegenerusGameDegeneretteModule.sol` confirms the writer at `:547` (`claimablePool -= uint128(fromClaimable);`) inside `_collectBetFunds` (function defined at `:533-:567`). The catalog's writer-label `_creditCheckedFromClaimable` is a CATALOG-LABEL-INACCURACY — the actual function name is `_collectBetFunds`; there is no function named `_creditCheckedFromClaimable` in `DegenerusGameDegeneretteModule.sol` (`grep "function _creditCheckedFromClaimable"` returns no match). The writer-site at `:547` exists and is correctly classified as a `claimablePool -=` debit reachable from EOA `placeDegeneretteBet` → `_placeDegeneretteBet` → `_placeDegeneretteBetCore` → `_collectBetFunds`. **CATALOG-LABEL-INACCURACY note** (not a stale-phantom — the source-of-truth writer at `:547` exists and the verdict-matrix classification is correct; only the function-name label is imprecise). Phase 303 TERMINAL acknowledgment should update the catalog row 392 writer-label to `_collectBetFunds`.

**Critical source observation:** Grep `grep -n "_livenessTriggered" contracts/modules/DegenerusGameDegeneretteModule.sol` returns **NO match** — `placeDegeneretteBet` and its internal callees have NO `_livenessTriggered()` gate. The catalog row 392 disposition column note "NO — EOA; gated runtime" is misleading: the runtime gating that the note refers to is the `lootboxRngWordByIndex[index] != 0` revert at `:452` (`RngNotReady`), which gates ONLY on the lootbox-index VRF cycle, NOT on the daily VRF or `_livenessTriggered()`. **No `_livenessTriggered()` gate exists on `placeDegeneretteBet`.**

### §3.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The Degenerette subsystem is the v40-era "spin-the-wheel" minigame where players place bets in ETH / BURNIE / WWXRP currencies; the ETH-currency path allows the player to PAY THE BET from a combination of `msg.value` and already-credited `claimableWinnings`. The `claimablePool -=` writer at `:547` is the in-game accounting mirror of `claimableWinnings[player] -= fromClaimable` at `:546` (the player's claim balance is debited by the portion of the bet paid from claimable, and the pool accumulator is debited matching).

**Why no `_livenessTriggered()` gate at the entry function:** Per source comment at `:551-:558` and the surrounding context, the bet-placement function is designed to be callable during normal gameplay; the ONLY gate is the lootbox-index VRF gate at `:452` (the bet is queued against the next-resolving lootbox index, which must not have its RNG word ready yet). The function does not gate on the DAILY VRF cycle or `_livenessTriggered()` because the spin resolution is independent of the daily jackpot resolution.

**Cite for "what would break if naively gated":** Gating `placeDegeneretteBet` on `_livenessTriggered()` would prevent legitimate spin-placements during the multi-tx game-over window. Players who wish to continue playing Degenerette up to the exact moment `gameOver = true` is latched would be blocked from queueing a final spin. The EV magnitude of "legitimate spin-placement during multi-tx game-over window" is bounded by the player's risk appetite (they MAY want to defer; they MAY want to spin one last bet); the EV magnitude of "blocking the writer race" is bounded by §3.B below. The trade-off favors gating because (i) the multi-tx game-over window is a short, terminal interval, (ii) the legitimate use-case (one-last-spin) is low-frequency, (iii) the exploit-case (writer race on `handleGameOverDrain`) is structurally a VIOLATION per strict-discipline.

**Precedent for gate addition at a non-mint entry function:** The Decimator subsystem (V-054 §1) is the parallel case: `claimDecimatorJackpot` does not have `_livenessTriggered()` in the v43.0 baseline but the FIXREC entry adds it. The Degenerette case is structurally identical — adding the same gate at `placeDegeneretteBet` closes the same class of writer race.

### §3.B — Actor game-theory walk

**Exploit-actor class:** Player holding non-zero `claimableWinnings[player]` who can choose WHEN to convert claimable into a Degenerette spin, including timing the conversion to fire mid-multi-tx-game-over-window.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Player has `claimableWinnings[player] = C` (some non-trivial credited balance). `_livenessTriggered()` transitions to true; multi-tx game-over window opens.
- T1 (attacker move): Player calls `placeDegeneretteBet(player, currency=CURRENCY_ETH, amountPerTicket=X, ticketCount=N, ...)` with `msg.value < totalBet = X * N`, forcing the shortfall path. `_collectBetFunds` at `:542-:548` executes `fromClaimable = totalBet - ethPaid`, `claimableWinnings[player] -= fromClaimable`, `claimablePool -= uint128(fromClaimable);`. Net `claimablePool` shift: `-fromClaimable` (a negative shift, REDUCING `claimablePool`).
- T2: Subsequent code in `_collectBetFunds` at `:550-:558` SHIFTS the bet amount into `futurePrizePool` (`(pNext, pFuture); _setPendingPools(pNext, pFuture + uint128(totalBet));` in the frozen path OR `_setPrizePools(next, future + uint128(totalBet));` in the unfrozen path). This `+= totalBet` to a different pool does NOT counter the `claimablePool -=` because `futurePrizePool` is a SEPARATE slot consumed by Cluster B not Cluster E.
- T3: `handleGameOverDrain` runs. At `:91` SLOAD, `claimablePool` is `originalValue - fromClaimable`. `reserved = (originalValue - fromClaimable) + pendingRedemptionEthValue`. `preRefundAvailable = totalFunds - reserved = totalFunds - originalValue + fromClaimable - pendingRedemptionEthValue` — INFLATED by `fromClaimable` compared to the unattacked case.
- T4: Terminal payouts at `:166-:182` scale linearly with `available` (which equals `preRefundAvailable` modulo the `:134` self-`+=` of `totalRefunded`). The attacker has inflated the terminal payout magnitude by approximately `fromClaimable * (1 - deity_refund_ratio)`.

**EV magnitude estimate:** **MEDIUM** on a per-player margin. The exploit converts `fromClaimable` ETH from "credited to me, pending withdrawal" into "inflated terminal-jackpot pool, distributed via VRF". The attacker's expected return from the inflated jackpot is bounded by `fromClaimable * P(I-win-the-VRF-jackpot)`. If the attacker holds significant ticket weight relative to the rest of the game, `P(I-win) > fromClaimable / inflated_jackpot`, making the EV positive. For an attacker holding 1% ticket weight and inflating jackpot by 1 ETH, EV ≈ +0.01 ETH minus the 1 ETH foregone from claim. EV is NEGATIVE for low-weight attackers; POSITIVE for high-weight attackers (whales, decimator winners). The attack also costs the gas of the spin transaction.

**Catalog §0 headline #4 framing:** "Game-over `claimablePool` writer races (§5) … structural-hardening cluster. Drain math is fragile to in-flight available/totalFunds mutations." V-057 is one of the four EOA writers cited in headline #4. Economic-likelihood disposition: **possible-exploited by high-weight players** (decimator winners, whales) during the multi-tx game-over window; **unlikely-exploited by low-weight players** (EV is negative below ~50% ticket weight).

### §3.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert.** Catalog §16 row 392 rationale: "Gate the EOA-reached `_creditCheckedFromClaimable` callsite on `!_livenessTriggered()`." Catalog §5 §E E-1 rationale: same.

**Concrete shape:**

- Add `if (_livenessTriggered()) revert E();` at the TOP of `placeDegeneretteBet` (`DegenerusGameDegeneretteModule.sol:367`). The gate closes the multi-tx game-over window where the `_collectBetFunds :547` writer is reachable from EOA.
- The gate is `_livenessTriggered()` ONLY (no `gameOver` carve-out), because there is no legitimate post-`gameOver=true` Degenerette spin path (the function should hard-revert once liveness fires — spins are gameplay actions, not withdrawals).

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: same rationale as §1.C — one-shot consumer read, no recurring axis to anchor against; snapshotting `claimablePool` does not eliminate the in-flight EOA debit.
- **(c) pre-lock reorder** rejected: writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: slot is mutable aggregate.
- **Gate ONLY the shortfall path at `:541-:548`** rejected: defense-in-depth at the writer site is less robust than entry-function gate; entry gate eliminates the writer reach AND the adjacent `_setPendingPools` / `_setPrizePools` write at `:553` / `:556` (which feeds Cluster B). Entry gate has positive externality on Cluster B.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~30 bytes for the `if (_livenessTriggered()) revert E();` instruction.
- **Net runtime gas:** +~2000 gas per `placeDegeneretteBet` call (one extra `_livenessTriggered()` invocation).
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** `MintModule.sol:877, :906, :1215` pattern.

### §3.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-29`** — Add `if (_livenessTriggered()) revert E();` at the top of `DegenerusGameDegeneretteModule.placeDegeneretteBet` (`DegenerusGameDegeneretteModule.sol:367`), closing the EOA reach to `_collectBetFunds :547` (`claimablePool -=`) during the multi-tx game-over window.

- Target file:line: `DegenerusGameDegeneretteModule.sol:367` (entry-function top).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 392 (V-057), §5 §D D-6 / §C.B-3-5 / §E E-1.
- CATALOG-LABEL-INACCURACY: catalog labels writer as `_creditCheckedFromClaimable`; actual function is `_collectBetFunds`. Phase 303 TERMINAL ack the label refinement.
- Positive externality: same fix also closes V-058 below (same entry function, sibling writer in same call frame); see §4 for paired discussion.

---

## §4 — V-058: `claimablePool +=` via `DegeneretteModule._addClaimableEth` (EOA `placeDegeneretteBet` → `resolveBets` → `_distributePayout`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 393 (V-058). §5 §D row D-7 (VIOLATION for EOA branch; EXEMPT-VRFCALLBACK for VRF-callback branch). §15 row 183 (writer enumeration). §C.B-3 row C-B3-6. §5 §E row E-2 (tactic (a) rationale).

**Source verification:** Grep `grep -n "claimablePool\|_addClaimableEth\|_resolveLootboxDirect" contracts/modules/DegenerusGameDegeneretteModule.sol` confirms:

- The catalog row 393 cites writer site at `:1131` and calls it `_resolveLootboxDirect`. Reading source at `:1129-:1133` reveals the ACTUAL function at that line is `_addClaimableEth(beneficiary, weiAmount)` (defined at `:1129`), and the `claimablePool += uint128(weiAmount)` SSTORE is at `:1131` inside `_addClaimableEth`.
- The function `_resolveLootboxDirect` is at `:797-:813` and is a DELEGATECALL stub that does NOT write `claimablePool` directly (it forwards to `IDegenerusGameLootboxModule.resolveLootboxDirect.selector` via `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(...)`).
- `_addClaimableEth` at `:1129` is called from `_distributePayout :722` at two sites: `:765` (frozen path) and `:781` (unfrozen path). Both call sites are inside the ETH-currency win-payout flow.
- `_distributePayout` is called from `_resolveBet` (a private function in the same module), which is called from the EOA-facing `resolveBets` at `:389` (`function resolveBets(address player, uint64[] calldata betIds) external`).

**CATALOG-LABEL-INACCURACY** (not a stale-phantom): the catalog labels the writer as `_resolveLootboxDirect` at `:1131` — but `:1131` is inside `_addClaimableEth`, not `_resolveLootboxDirect`. The verdict-matrix classification is still correct (the writer site exists at `:1131`, the EOA-reach via `resolveBets` is structurally real, and the disposition VIOLATION holds). Phase 303 TERMINAL acknowledgment should update the writer-label to `_addClaimableEth` (or more precisely: the writer in `_addClaimableEth :1131` reached via `_distributePayout :765 / :781` reached via `_resolveBet` reached via EOA `resolveBets :389`).

### §4.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The Degenerette spin-resolution path was introduced as a multi-tier payout mechanism: an ETH-currency winning spin pays out via a 3-tier split (`payout ≤ 3 × bet` → 100% ETH; `3 × bet < payout ≤ 10 × bet` → `max(2.5 × bet, payout / 4)` ETH + lootbox remainder; `payout > 10 × bet` → `payout / 4` ETH + lootbox remainder). The `_addClaimableEth :1131` `+=` write at `:1131` is the in-game accounting mirror of `claimableWinnings[beneficiary] += weiAmount` at `:1132` (`_creditClaimable(beneficiary, weiAmount)`).

**Why the writer fires twice per resolution:** Once at `:765` (frozen path, when `prizePoolFrozen == true`) — the ETH share is debited from `pendingPools` and credited to claimable; once at `:781` (unfrozen path, when `prizePoolFrozen == false`) — the ETH share is debited from `futurePrizePool` and credited to claimable. Only one of the two branches fires per call (mutex on `prizePoolFrozen`); both paths converge on `_addClaimableEth(player, ethShare);`. The writer is reachable from EOA `resolveBets` because `resolveBets` is an external function with no `_livenessTriggered()` gate AND no `prizePoolFrozen` gate (the function is designed to be callable continuously to resolve pending bets, even during the daily VRF freeze).

**Cite for "what would break if naively gated":** Gating `resolveBets` on `_livenessTriggered()` would block legitimate bet-resolution during the multi-tx game-over window. The legitimate use-case: a player has a pending bet (placed BEFORE liveness fired) whose lootbox-index VRF word has just arrived; the player wants to resolve and collect winnings before `gameOver = true` is latched. Gating would force the bet into the post-gameOver resolution stack.

**The catalog's tactic-(a) recommendation (`Gate the EOA-reached _resolveLootboxDirect callsite on !_livenessTriggered()`) implicitly accepts this trade-off:** the EOA bet-resolution path is acceptable to gate because (i) the bet itself is preserved (the `lootboxRngWordByIndex[index]` value persists across the gate), (ii) the player can resolve POST-gameOver via an alternative claim path or via re-calling `resolveBets` after the multi-tx window closes, (iii) the EXEMPT-VRFCALLBACK branch (when the same writer fires via `fulfillRandomWords` → ... → `_resolveBet`) remains unaffected.

**Per-callsite split per `D-298-EXEMPT-CROSSCONTRACT-01`:** The catalog row 393 disposition is dual: VIOLATION (EOA branch) + EXEMPT-VRFCALLBACK (VRF-callback branch). The same writer function `_addClaimableEth :1129-:1133` carries distinct verdicts depending on reach. The fix targets the EOA branch only — gating the EOA entry function (`resolveBets`) does not affect the VRF-callback reach.

### §4.B — Actor game-theory walk

**Exploit-actor class:** Player holding one or more pending Degenerette bets whose lootbox-RNG indices have RESOLVED (i.e., `lootboxRngWordByIndex[index] != 0`) but whose `_resolveBet` has not yet been called.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Player has placed a Degenerette spin bet at level `L`. The bet is queued against `index = some_lootbox_rng_index`. `lootboxRngWordByIndex[index]` is set when the VRF callback fires for that index. The player has CHOSEN to defer `resolveBets` until a strategic moment.
- T1: Multi-tx game-over window opens (`_livenessTriggered() == true`).
- T2 (attacker move): Player calls `resolveBets(player, [betId])`. `_resolveBet` computes the spin outcome (win/lose, tier, payout). For a winning ETH-currency spin, `_distributePayout` enters the 3-tier branch and calls `_addClaimableEth(player, ethShare)` at `:765` or `:781`. `_addClaimableEth` writes `claimablePool += uint128(ethShare)` at `:1131`. Net `claimablePool` shift: `+ethShare` (a POSITIVE shift, INCREASING `claimablePool`).
- T3: `handleGameOverDrain` runs. At `:91` SLOAD, `claimablePool` is `originalValue + ethShare`. `reserved = (originalValue + ethShare) + pendingRedemptionEthValue`. `preRefundAvailable = totalFunds - reserved = totalFunds - originalValue - ethShare - pendingRedemptionEthValue` — DEFLATED by `ethShare` compared to the unattacked case.
- T4: Terminal payouts at `:166-:182` scale linearly with `available` (post-self-`+=` of `totalRefunded`). The attacker has DEFLATED the terminal payout magnitude by approximately `ethShare`.

**Why deflation can be advantageous to the attacker:** This is the INVERSE of V-057. Here, the attacker INCREASES their own `claimableWinnings` balance (by `ethShare`) while DECREASING the terminal-jackpot pool magnitude. If the attacker has LOW ticket weight in the terminal jackpot, the EV of "keep my +ethShare as guaranteed claim" exceeds the EV of "let it flow into terminal jackpot where I might win a fraction". Conversely, if the attacker has HIGH ticket weight, they prefer the V-057 vector (inflate the pool). V-057 + V-058 form a complementary attack pair: low-weight attackers prefer V-058 (deflate), high-weight attackers prefer V-057 (inflate).

**EV magnitude estimate:** **HIGH** on a per-resolution margin (the lootbox-direct payouts can be large; the 3-tier split can credit `(2.5 × bet)` ETH for a Tier-2 win, where `bet` can be substantial). The attacker's EV from V-058 is `ethShare * (1 - P(win-fair-share-of-jackpot))`. For low-weight attackers, `P(win-fair-share)` is small and EV ≈ `+ethShare`. Economic-likelihood disposition: **likely-exploited by low-weight players** with pending winning Degenerette bets during the multi-tx game-over window.

### §4.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert.** Catalog §16 row 393 rationale: "Gate the EOA-reached `_resolveLootboxDirect` callsite on `!_livenessTriggered()`." Catalog §5 §E E-2 rationale: same.

**Concrete shape:**

- Add `if (_livenessTriggered()) revert E();` at the TOP of `resolveBets` (`DegenerusGameDegeneretteModule.sol:389`). The gate closes the EOA reach to `_addClaimableEth :1131` (and the sibling writers `_setPendingPools :764` and `_setFuturePrizePool :780` that feed Cluster B).
- The VRF-callback reach (when `_addClaimableEth :1131` fires via `fulfillRandomWords` → `_resolveBet` from the VRF stack) is UNAFFECTED because that reach does not go through the external `resolveBets` entry.
- The gate is `_livenessTriggered()` ONLY (no `gameOver` carve-out). Post-`gameOver = true`, the player can withdraw via `claimWinnings` (V-063 below) rather than via `resolveBets`. If post-gameOver resolution is REQUIRED for some legitimate flow, the fix can be `if (_livenessTriggered() && !gameOver) revert E();` (mirroring V-063 / V-065 / §1.C). The catalog row 393 wording is silent on the `gameOver` carve-out; v44 plan-phase discretion to decide based on whether `resolveBets` is required for post-gameOver settlement.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: same rationale as §1.C — one-shot consumer read.
- **(c) pre-lock reorder** rejected: writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: slot is mutable.
- **Gate ONLY the writer site at `_addClaimableEth :1129`** rejected: would affect both EOA and VRF-callback reach, breaking the EXEMPT-VRFCALLBACK branch. Entry-function gate at `resolveBets` is strictly necessary to preserve the per-callsite split.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~30 bytes for the gate.
- **Net runtime gas:** +~2000 gas per `resolveBets` call.
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** `MintModule.sol:877, :906, :1215` pattern.

### §4.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-30`** — Add `if (_livenessTriggered()) revert E();` (or `if (_livenessTriggered() && !gameOver) revert E();` per v44 plan-phase post-gameOver settlement requirement) at the top of `DegenerusGameDegeneretteModule.resolveBets` (`DegenerusGameDegeneretteModule.sol:389`), closing the EOA reach to `_addClaimableEth :1131` (`claimablePool +=`) during the multi-tx game-over window. The VRF-callback reach (EXEMPT-VRFCALLBACK branch) is unaffected.

- Target file:line: `DegenerusGameDegeneretteModule.sol:389` (entry-function top).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 393 (V-058), §5 §D D-7 / §C.B-3-6 / §E E-2.
- CATALOG-LABEL-INACCURACY: catalog labels writer as `_resolveLootboxDirect at :1131`; actual writer is `_addClaimableEth at :1131`. Phase 303 TERMINAL ack the label refinement.
- Per-callsite split preservation: EXEMPT-VRFCALLBACK branch (writer reached via `fulfillRandomWords` → `_resolveBet`) MUST remain unaffected. The entry-function gate at `resolveBets :389` is the structural mechanism that preserves the split.
- Positive externality: same fix closes the adjacent Cluster B writers at `_setPendingPools :764` and `_setFuturePrizePool :780` (futurePrizePool race), and closes V-057 reach via `resolveBets` (different entry from `placeDegeneretteBet` but shares the multi-tx window timing).

---

## §5 — V-063: `claimablePool -=` via `DegenerusGame._claimWinningsInternal` (EOA `claimWinnings`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 398 (V-063). §5 §D row D-13 (VIOLATION). §15 row 187 (writer enumeration). §C.B-3 row C-B3-12. §5 §E row E-3 (tactic (a) rationale, paired with V-073 D-22 for `address(this).balance` outflow co-write).

**Source verification:** Grep `grep -n "claimablePool\|claimWinnings\|_claimWinningsInternal" contracts/DegenerusGame.sol` confirms the writer at `:1408` (`claimablePool -= uint128(payout);`) inside `_claimWinningsInternal` (defined at `:1399-:1415`). Two EOA entries: `claimWinnings(address player)` at `:1387` (general-purpose) and `claimWinningsStethFirst()` at `:1394` (restricted to `msg.sender == ContractAddresses.VAULT`). Both route to `_claimWinningsInternal`.

### §5.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The `claimWinnings` function is THE canonical player-withdrawal path: the player calls it to withdraw their accrued `claimableWinnings[player]` balance as ETH (or stETH-first via `claimWinningsStethFirst`). The function uses the pull-pattern (player calls; contract transfers) for CEI security (per source comment at `:1380-:1385`: "INVARIANT: claimablePool is decremented by payout"). The `claimablePool -=` at `:1408` is the in-game accounting mirror of the `claimableWinnings[player] = 1` SSTORE at `:1405` (the 1-wei sentinel pattern keeps the slot warm for the next credit).

**Why the writer has NO `_livenessTriggered()` gate:** Per source comment at `DegenerusGame.sol:1331-:1337`: "claimablePool is decremented before external call." The function is INTENTIONALLY ungated on `_livenessTriggered()` because players are EXPECTED to be able to withdraw their accrued winnings at any time, including (especially) during a stalled-VRF state. The design-intent: a player who has been credited winnings should NEVER be locked out of withdrawing them.

**The conflict:** The withdraw-anytime intent conflicts with the multi-tx game-over consumer's need for a stable `claimablePool` read. The catalog row 398 fix `!_livenessTriggered() || gameOver` resolves the conflict: BLOCK withdrawal during the pre-`gameOver=true` multi-tx window (a SHORT, DETERMINISTIC interval), RE-OPEN withdrawal once `gameOver = true` is latched (the post-gameover-claim period, which is permanent). Players who attempt to withdraw during the multi-tx window get a temporary revert; they retry post-`gameOver` and succeed. The trade-off favors gating because (i) the multi-tx window is bounded by the next `advanceGame` call, (ii) the user-visible delay is at most a few blocks, (iii) the alternative (consumer-side snapshot) is structurally more invasive AND does not protect the `address(this).balance` outflow side-effect.

**`address(this).balance` outflow co-write:** Per catalog §5 §E E-6: "claimWinnings outflow deflates `address(this).balance` mid-drain." The `_payoutWithStethFallback` or `_payoutWithEthFallback` call at `:1411-:1413` transfers ETH out of the contract, deflating `address(this).balance`. `handleGameOverDrain :84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. A `claimWinnings` mid-window deflates both the `claimablePool` reserve AND the `totalFunds` numerator — but the NET effect on `available = totalFunds - reserved` may be near-zero IF the deflation is symmetric. In practice the symmetry is NOT exact because (i) stETH-first vs ETH-first changes the split between `address(this).balance` and `steth.balanceOf`, (ii) the deity-refund deity-pass branch at `:107-:136` runs between the `:84` read and the `:154` read, mutating intermediate state. The NET effect is approximately neutral on `available` for a single small withdrawal but can be CATASTROPHIC for a large withdrawal that exhausts ETH-side reserves.

**Catalog §5 §E note on co-located writers:** "Same gate as E-3 — single revert closes both `claimablePool` and balance writers." V-063 (claimablePool) and V-073 (address(this).balance via claimWinnings outflow) share the same entry function; one gate closes both. V-073 is documented in Cluster F (S-20 address(this).balance) FIXREC entries; this FIXREC entry covers ONLY the `claimablePool` writer aspect.

### §5.B — Actor game-theory walk

**Exploit-actor class:** ANY player holding non-zero `claimableWinnings[player]`. This is the largest exploit-actor surface in Cluster E because every player who has won ANY prior decimator / Degenerette / lootbox-direct / jackpot share holds claimable balance.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Player has `claimableWinnings[player] = C`. `_livenessTriggered()` transitions to true. Multi-tx game-over window opens.
- T1 (attacker move): Player calls `claimWinnings(player)`. `_claimWinningsInternal` executes: `payout = C - 1` (sentinel reserve), `claimablePool -= uint128(payout)` at `:1408`, then `_payoutWithStethFallback(player, payout)` at `:1413` (or `_payoutWithEthFallback` if `stethFirst`). Net: `claimablePool -= (C-1)`; `address(this).balance` OR `steth.balanceOf(this)` decreases by `(C-1)`.
- T2: `handleGameOverDrain` runs. At `:84`, `totalFunds = (originalEthBalance - (C-1)) + steth.balanceOf(...)` (or vice versa for stETH). At `:91`, `reserved = (originalClaimablePool - (C-1)) + pendingRedemptionEthValue`. `preRefundAvailable = totalFunds - reserved = originalEthBalance - (C-1) - originalClaimablePool + (C-1) - pendingRedemptionEthValue = originalEthBalance - originalClaimablePool - pendingRedemptionEthValue` — APPROXIMATELY EQUAL to the unattacked case (the `(C-1)` cancels). The `preRefundAvailable` value is approximately unchanged.
- T3: BUT: the ETH side of `totalFunds` has been DEFLATED. Deity-pass refunds at `:121-:124` credit `claimableWinnings[owner]` (a future withdrawal, not an immediate ETH transfer). Terminal-jackpot payouts at `:168` / `:182` credit jackpot winners' `claimableWinnings` (again, not immediate ETH transfers — the actual ETH transfer happens later when winners call `claimWinnings`).
- T4: POST-resolution, OTHER players attempt to call `claimWinnings`. If `address(this).balance` has been deflated below the sum of remaining `claimableWinnings[*]`, the `_payoutWithStethFallback` will succeed via stETH-fallback as long as `steth.balanceOf(this) > 0` — but if BOTH ETH and stETH reserves are exhausted, subsequent withdrawals revert. The invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` (per source comment at `DegenerusGame.sol:18`) MUST hold to keep withdrawals solvent.

**Magnitude analysis:** The attacker's `(C-1)` deflation of `address(this).balance` is exact and immediate. If `C` is large (e.g., a player holding 100 ETH of accrued winnings), the deflation is 100 ETH. If multiple players coordinate withdrawals before `handleGameOverDrain`, the cumulative deflation can be a substantial fraction of the contract's ETH reserves.

**EV magnitude estimate:** **CATASTROPHE-tier per single large claim during terminal jackpot drain.** The catalog row 398 V-063 IS THE highest-EV row in Cluster E. The attack vector is structurally a frontrun: the player observes the impending `handleGameOverDrain` and withdraws their balance INTENTIONALLY before the drain runs, ensuring their withdrawal is at full balance (not diluted by deity-pass refunds or terminal-jackpot reallocation). For a player whose `claimableWinnings` would be partially RECLAIMED by the deity-refund branch or zeroed by post-30-day sweep, the EV of frontrunning is ENTIRE_BALANCE - WHATEVER_WOULD_HAVE_BEEN_PAID_POST_RESOLUTION. For a player whose balance is not at risk, the EV is approximately zero (the withdrawal just shifts the timing).

**The TRUE exploit vector (per `feedback_rng_commitment_window.md`):** The exploit is not the `claimablePool` mathematical shift (which is approximately neutral on `preRefundAvailable`) — it is the `address(this).balance` outflow that CONSTRAINS the terminal-jackpot's ability to pay out solvently. If the attacker's withdrawal deflates ETH below the sum of post-resolution claimableWinnings, subsequent claimants face insolvency-by-pull-pattern.

**Economic-likelihood disposition: likely-exploited** by every player holding non-zero claimableWinnings at the moment of multi-tx game-over signal; the action is a no-op for low-balance players (cost-of-gas) and high-EV for high-balance players (entire-balance withdraw).

### §5.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert with `gameOver` carve-out.** Catalog §16 row 398 rationale: "Gate `claimWinnings` on `!_livenessTriggered() || gameOver` so drain math is stable." Catalog §5 §E E-3 rationale: same. Catalog §5 §E E-6 note: "Same gate as E-3 — single revert closes both `claimablePool` and balance writers."

**Concrete shape:**

- Add `if (_livenessTriggered() && !gameOver) revert E();` at the TOP of `_claimWinningsInternal` (`DegenerusGame.sol:1399`), above the existing `if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();` at `:1400`. The gate closes the multi-tx-pre-`gameOver=true` window where `claimWinnings` is reachable.
- Post-`gameOver = true`, the gate re-opens automatically (the `&& !gameOver` clause becomes false). Players can withdraw normally during the post-gameover claim period.
- The gate is at `_claimWinningsInternal :1399` (the private function shared by both `claimWinnings` and `claimWinningsStethFirst`) rather than at each external entry — one gate covers both entries.
- ALTERNATIVE shape (per catalog wording `!_livenessTriggered() || gameOver` — note the OR): `if (!(!_livenessTriggered() || gameOver)) revert E();` simplifies to `if (_livenessTriggered() && !gameOver) revert E();` (De Morgan's). The two are equivalent.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: snapshotting `claimablePool` AND `address(this).balance` at the moment `_livenessTriggered()` first transitions to true would require two new storage slots AND would not eliminate the in-flight ETH outflow side-effect. Tactic (a) is strictly cheaper.
- **(c) pre-lock reorder** rejected: writer is EOA-triggered.
- **(d) immutable** rejected: slot is mutable.
- **Gate only `claimablePool -=` at `:1408`** rejected: would allow the `address(this).balance` outflow at `:1411-:1413` to fire even when the `claimablePool` write is gated — would break invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` because ETH leaves the contract without `claimablePool` accounting. Must gate at function entry, not at writer site.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~40 bytes for the `if (_livenessTriggered() && !gameOver) revert E();` instruction (two SLOADs, one AND, one branch, one revert).
- **Net runtime gas:** +~2500 gas per `claimWinnings` / `claimWinningsStethFirst` call (one extra `_livenessTriggered()` invocation plus one `gameOver` SLOAD).
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** Phase 290 MINTCLN `rngLockedFlag` pattern; in-source `MintModule.sol:1215` `_livenessTriggered` pattern.

### §5.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-31`** — Add `if (_livenessTriggered() && !gameOver) revert E();` at the top of `DegenerusGame._claimWinningsInternal` (`DegenerusGame.sol:1399`), closing the multi-tx-pre-`gameOver=true` window where `claimWinnings` / `claimWinningsStethFirst` are reachable. The same gate closes the V-073 `address(this).balance` outflow co-write (Cluster F handoff anchor cites this anchor as the shared fix).

- Target file:line: `DegenerusGame.sol:1399` (`_claimWinningsInternal` private function top, covering both external entry points `claimWinnings :1387` and `claimWinningsStethFirst :1394`).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 398 (V-063), §5 §D D-13 / §C.B-3-12 / §E E-3 / §E E-6 (paired V-073 co-write).
- Positive externality: same fix closes V-073 (`address(this).balance` outflow via claimWinnings) in Cluster F (S-20 address(this).balance).

---

## §6 — V-064: `claimablePool -=` via `DegenerusGame.useClaimableForMint` (EOA mint family)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 399 (V-064). §5 §D row D-14 (`EXEMPT-ADVANCEGAME` by-gate). §15 row 188 (writer enumeration). §C.B-3 row C-B3-13. §5 §E (NOT listed — covered by existing mint-family gate).

**Source verification:** Grep `grep -n "claimablePool\|useClaimableForMint\|claimableUsed" contracts/DegenerusGame.sol` confirms the writer at `:946` (`claimablePool -= uint128(claimableUsed);`) inside a private function near the mint-payment-routing logic at `:889-:955`. The catalog row 399 calls it `useClaimableForMint` and locates it at `:946`. Source comment at `:889`: "INVARIANT: claimablePool is decremented by claimableUsed." The function is called from the mint-payment-routing path; the EOA-facing entry is one of `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / `mintBatch`-family which all gate on `_livenessTriggered()` via `_purchaseFor` / `_purchaseCoinFor` / `_purchaseBurnieLootboxFor` at `MintModule.sol:877, :906, :1215`.

### §6.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The "useClaimableForMint" mechanism (the v40-era mint-payment path that allows players to pay for tickets using credited `claimableWinnings`) was introduced as a UX convenience: a player who has accrued `claimableWinnings` should be able to spend that balance directly on tickets without first withdrawing to wallet. The `claimablePool -= uint128(claimableUsed)` at `:946` is the in-game accounting mirror of `claimableWinnings[player] = claimable - claimableUsed` at `:934`.

**Why the writer is structurally unreachable during multi-tx game-over:** The mint-family entries (`purchase`, `purchaseCoin`, `purchaseBurnieLootbox`, `mintBatch`) all check `_livenessTriggered()` at the top of their internal implementations (`_purchaseFor`, `_purchaseCoinFor`, `_purchaseBurnieLootboxFor`). When `_livenessTriggered() == true`, the entry function reverts BEFORE reaching the `useClaimableForMint` logic at `DegenerusGame.sol:889-:955`. The writer at `:946` is therefore in the same "gated-by-entry-function" structural class as V-055 (`_resolveMintShortfall :949`).

**Cite for "what would break if naively gated":** Same answer as §2.A — nothing breaks beyond what the existing gate already blocks. The FIXREC entry exists for strict-discipline classification.

### §6.B — Actor game-theory walk

**Exploit-actor class:** None — the writer is structurally unreachable from EOA when `_livenessTriggered() == true`.

**Action sequence during multi-tx game-over window:** Attacker attempts `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / `mintBatch` after `_livenessTriggered()` transitions to true. The entry function reverts at `MintModule.sol:877` / `:906` / `:1215` with `error E()`. The `useClaimableForMint` logic at `DegenerusGame.sol:889-:955` is never reached. `claimablePool` is unchanged.

**EV magnitude estimate:** **ZERO (structurally unreachable).** Catalog disposition is VIOLATION token under strict-discipline; actual exploit surface is empty.

**Branch-coverage concern (FUZZ-301 forward-attestation):** Same FUZZ-301 attestation as §2.B — Phase 301 fuzz harness MUST exercise the `(_livenessTriggered() == true, mint-family entry call)` branch and assert the call reverts before reaching `useClaimableForMint :946`.

**Economic-likelihood disposition: non-exploitable** in the deployed contract.

### §6.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert — ALREADY IN-SOURCE.** Catalog §16 row 399 rationale: "Existing `_livenessTriggered()` gate covers — verify branch coverage."

**Concrete shape:**

- **No source-code change.** The existing entry-function gates at `MintModule.sol:877, :906, :1215` already close the open window.
- **FUZZ-301 forward-attestation:** Same as §2.C. Phase 301 fuzz must verify branch reach.

**Rationale for rejecting alternative tactics:** Same as §2.C.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical (no change).
- **Bytecode delta:** 0 bytes (no source change).
- **Net runtime gas:** 0 (no change).
- **Public ABI:** byte-identical.
- **Reference precedent:** existing `_livenessTriggered()` gates at `MintModule:877, :906, :1215, :1381`.

### §6.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-32`** — Branch-coverage forward-attestation only. Phase 301 FUZZ harness MUST exercise the `(_livenessTriggered() == true, mint-family entry call)` branch and assert the call reverts before reaching `DegenerusGame.useClaimableForMint :946`. No source-code change in v44.0.

- Target file:line: `DegenerusGame.sol:946` (writer site; documented as gated-by-entry-function).
- Existing gate sites: `DegenerusGameMintModule.sol:877, :906, :1215, :1381`.
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 399 (V-064), §5 §D D-14 / §C.B-3-13.

---

## §7 — V-065: `claimablePool -=` via `DegenerusGame.resolveRedemptionLootbox` (sDGNRS `claimRedemption` callback)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 400 (V-065). §5 §D row D-15 (VIOLATION). §15 row 189 (writer enumeration). §C.B-3 row C-B3-14. §5 §E row E-4 (tactic (a) rationale).

**Source verification:** Grep `grep -n "claimablePool\|sweepSdgnrsClaim\|resolveRedemptionLootbox" contracts/DegenerusGame.sol` reveals two distinct functions related to the catalog row 400 description:

- `resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore)` at `:1721` — gated on `if (msg.sender != ContractAddresses.SDGNRS) revert E();` at `:1727`. Body writes `claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount` at `:1737` and `claimablePool -= uint128(amount);` at `:1739`.
- `sweepSdgnrsClaim` — `grep "function sweepSdgnrsClaim"` returns NO match in current source. The catalog row 400 labels the writer as `sweepSdgnrsClaim` at `DegenerusGame.sol:1739`, but the function at `:1721` is named `resolveRedemptionLootbox`. **CATALOG-LABEL-INACCURACY**: catalog labels the function `sweepSdgnrsClaim`; actual function is `resolveRedemptionLootbox`. The writer-site at `:1739` exists and the verdict-matrix classification is correct. Phase 303 TERMINAL acknowledgment should update the catalog row 400 writer-label.

**Caller-allowlist:** `if (msg.sender != ContractAddresses.SDGNRS) revert E();` at `:1727` restricts the function to ONLY sDGNRS contract calls. sDGNRS reaches this function from inside its `claimRedemption` flow, which is EOA-callable on the sDGNRS contract. The chain is: EOA → `StakedDegenerusStonk.claimRedemption(...)` → (sDGNRS-internal logic) → `DegenerusGame.resolveRedemptionLootbox(player, amount, rngWord, activityScore)`. The reach is indirect-EOA via sDGNRS.

### §7.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The `resolveRedemptionLootbox` function (sDGNRS-redemption-lootbox-resolution callback) was introduced as the cross-contract callback that sDGNRS uses to convert burned-sDGNRS-token redemptions into in-game lootbox awards. Per source comment at `:1730-:1734`: "Debit from sDGNRS's claimable (ETH stays in Game's balance). The two paths are mutually exclusive, so claimable >= amount always holds here." The `claimablePool -= uint128(amount)` at `:1739` is the in-game accounting mirror of the sDGNRS-side claimable balance reduction.

**Why the function has NO `_livenessTriggered()` gate:** The function is designed to be callable EXCLUSIVELY by sDGNRS (caller-allowlisted). sDGNRS's `claimRedemption` flow is part of the in-game economy that operates continuously; gating on `_livenessTriggered()` would break sDGNRS's redemption mechanism mid-game. The DEPENDENT design-intent: sDGNRS-redemption should remain functional across the entire game lifetime EXCEPT during the precise multi-tx game-over window where the consumer's read of `claimablePool` could race.

**Cite for "what would break if naively gated":** sDGNRS's `claimRedemption` would revert (because its internal call to `DegenerusGame.resolveRedemptionLootbox` would revert). sDGNRS holders attempting to redeem during the multi-tx game-over window would face a temporary revert; they could retry post-`gameOver = true`. This is the same trade-off as §5.A (claimWinnings) — short-window block, permanent re-open.

**Mirror of V-063 vector:** Per catalog §5 §E E-4: "Gate `sweepSdgnrsClaim` on `!_livenessTriggered() || gameOver` to mirror E-3." The fix shape exactly mirrors V-063 — same gate, same callsite-position discipline, same `gameOver` carve-out.

### §7.B — Actor game-theory walk

**Exploit-actor class:** sDGNRS holder who has burned sDGNRS tokens for gambling-redemption and triggers `claimRedemption` on sDGNRS contract.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Attacker holds burned sDGNRS gambling-redemption claim (pending). Multi-tx game-over window opens.
- T1 (attacker move): Attacker calls `StakedDegenerusStonk.claimRedemption(claimId)` on sDGNRS contract. sDGNRS-internal logic processes the claim and at some point calls `DegenerusGame.resolveRedemptionLootbox(player, amount, rngWord, activityScore)`. The writer at `:1739` executes `claimablePool -= uint128(amount)`. Concurrent side-effects at `:1742-:1748`: `_setPendingPools(pNext, pFuture + uint128(amount))` (frozen) OR `_setPrizePools(next, future + uint128(amount))` (unfrozen) — the `amount` is shifted to `futurePrizePool`/`pendingPools` (Cluster B feed). Then the loop at `:1750-:1763` calls into `IDegenerusGameLootboxModule.resolveRedemptionLootbox` via delegatecall to mint lootbox tickets to the player.
- T2: `handleGameOverDrain` runs. At `:91` SLOAD, `claimablePool` is `originalValue - amount`. Same dynamics as V-057 §3.B (inflate `preRefundAvailable` by `amount`).
- T3: Terminal payouts at `:166-:182` are INFLATED by approximately `amount`.

**EV magnitude analysis:** The attacker has converted `amount` of sDGNRS-claimable-ETH into (a) a `claimablePool` debit AND (b) a `futurePrizePool` credit AND (c) lootbox tickets to the player. The `claimablePool` debit feeds the `handleGameOverDrain` race (inflating terminal payouts); the `futurePrizePool` credit feeds Cluster B's race; the lootbox tickets give the player additional ticket weight in the inflated terminal jackpot. **The combined exploit is HIGH-EV per `amount` of sDGNRS redemption.**

**Comparison to V-063:** V-063 (`claimWinnings`) deflates `address(this).balance` AND `claimablePool` — the NET on `preRefundAvailable` is approximately neutral. V-065 (`resolveRedemptionLootbox`) ONLY shifts `claimablePool` (the ETH stays in the contract per the design-intent comment at `:1733`). V-065's NET shift on `preRefundAvailable` is `+amount` (inflate) — the same direction as V-057 (inflate). V-065 is therefore an INFLATE-tier exploit, complementary to V-063's neutral-or-deflate-tier exploit.

**EV magnitude estimate:** **HIGH** per single sDGNRS redemption during the multi-tx game-over window. The catalog row 400 V-065 disposition mirrors V-063 in the §5 §E E-4 row. Economic-likelihood disposition: **likely-exploited by sDGNRS holders** with pending gambling-redemption claims during the multi-tx game-over window.

### §7.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert with `gameOver` carve-out.** Catalog §16 row 400 rationale: "Gate `sweepSdgnrsClaim` on `!_livenessTriggered() || gameOver` to mirror V-063." Catalog §5 §E E-4 rationale: same.

**Concrete shape:**

- Add `if (_livenessTriggered() && !gameOver) revert E();` at the TOP of `resolveRedemptionLootbox` (`DegenerusGame.sol:1721`), above the existing `if (msg.sender != ContractAddresses.SDGNRS) revert E();` at `:1727`. The gate closes the multi-tx-pre-`gameOver=true` window.
- Post-`gameOver = true`, the gate re-opens automatically. sDGNRS holders can redeem normally during the post-gameover period.
- The gate is `_livenessTriggered() && !gameOver` — mirroring §5.C's V-063 form.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: same rationale as §5.C — one-shot consumer read, snapshot does not eliminate the in-flight `claimablePool` debit.
- **(c) pre-lock reorder** rejected: writer is sDGNRS-callback-triggered at sDGNRS-holder discretion.
- **(d) immutable** rejected: slot is mutable.
- **Gate on the sDGNRS side instead** rejected: would require modifying `StakedDegenerusStonk.claimRedemption` to check `IDegenerusGame.livenessTriggered()` view; possible but adds cross-contract complexity. The single-side gate at `DegenerusGame.resolveRedemptionLootbox :1721` is structurally simpler — the sDGNRS-side revert propagates back through the cross-contract call.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~40 bytes for the gate.
- **Net runtime gas:** +~2500 gas per `resolveRedemptionLootbox` call.
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** §5.C V-063 pattern (same gate shape).

### §7.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-33`** — Add `if (_livenessTriggered() && !gameOver) revert E();` at the top of `DegenerusGame.resolveRedemptionLootbox` (`DegenerusGame.sol:1721`), above the existing sDGNRS caller-allowlist check at `:1727`. Closes the multi-tx-pre-`gameOver=true` window where the sDGNRS-callback-triggered writer at `:1739` is reachable.

- Target file:line: `DegenerusGame.sol:1721` (function entry).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 400 (V-065), §5 §D D-15 / §C.B-3-14 / §E E-4.
- CATALOG-LABEL-INACCURACY: catalog labels function `sweepSdgnrsClaim`; actual function is `resolveRedemptionLootbox`. Phase 303 TERMINAL ack the label refinement.
- Mirror of V-063: same gate shape (`!_livenessTriggered() || gameOver` ≡ `!(_livenessTriggered() && !gameOver)`), same callsite-position discipline.
- Positive externality: same fix closes adjacent Cluster B writer at `:1744 / :1747` (`_setPendingPools` / `_setPrizePools` `+= amount`), which feeds `futurePrizePool` / `pendingPools` races covered by Cluster B.

---

## Cluster E — summary attestations

| V-NNN | Slot | Writer-class | Tactic | EV-tier | Anchor |
|-------|------|--------------|--------|---------|--------|
| V-054 | claimablePool | `_creditDecJackpotClaimCore :388` via EOA `claimDecimatorJackpot` | (a) gate `!_livenessTriggered() && !gameOver` at entry `:321` | LOW on consumer; MEDIUM-HIGH cross-cluster (Cluster B externality) | `D-43N-V44-HANDOFF-27` |
| V-055 | claimablePool | `_resolveMintShortfall :949` via mint family | (a) ALREADY IN-SOURCE at `MintModule:877, :906, :1215`; FUZZ-301 branch-coverage attestation only | ZERO (structurally unreachable) | `D-43N-V44-HANDOFF-28` |
| V-057 | claimablePool | `_collectBetFunds :547` via EOA `placeDegeneretteBet` | (a) gate `!_livenessTriggered()` at entry `:367` | MEDIUM (high for high-weight players) | `D-43N-V44-HANDOFF-29` |
| V-058 | claimablePool | `_addClaimableEth :1131` via EOA `resolveBets` | (a) gate `!_livenessTriggered()` at entry `:389`; preserves EXEMPT-VRFCALLBACK branch | HIGH (large lootbox-direct payouts) | `D-43N-V44-HANDOFF-30` |
| V-063 | claimablePool | `_claimWinningsInternal :1408` via EOA `claimWinnings` / `claimWinningsStethFirst` | (a) gate `!_livenessTriggered() && !gameOver` at internal `:1399` (covers both external entries; also closes V-073 outflow) | CATASTROPHE-tier per single large claim | `D-43N-V44-HANDOFF-31` |
| V-064 | claimablePool | `useClaimableForMint :946` via mint family | (a) ALREADY IN-SOURCE at `MintModule:877, :906, :1215`; FUZZ-301 branch-coverage attestation only | ZERO (structurally unreachable) | `D-43N-V44-HANDOFF-32` |
| V-065 | claimablePool | `resolveRedemptionLootbox :1739` via sDGNRS `claimRedemption` callback | (a) gate `!_livenessTriggered() && !gameOver` at entry `:1721`; mirror of V-063 | HIGH (per sDGNRS redemption magnitude) | `D-43N-V44-HANDOFF-33` |

**Tactic mix:** 7 / 7 select tactic (a) gated-revert. 5 of the 7 require a NEW source-code gate (V-054, V-057, V-058, V-063, V-065); 2 of the 7 (V-055, V-064) are covered by an EXISTING in-source gate and require only FUZZ-301 branch-coverage attestation. Zero tactic (b) snapshot, zero tactic (c) pre-lock reorder, zero tactic (d) immutable.

**EV-tier distribution:** CATASTROPHE-tier in 1 entry (V-063 — single large claimWinnings exhausting ETH-side reserves). HIGH-tier in 2 entries (V-058, V-065). MEDIUM-tier in 2 entries (V-057, V-054-cross-cluster). ZERO (structurally unreachable) in 2 entries (V-055, V-064 — verification-only).

**v44.0 handoff anchor count:** 7 — `D-43N-V44-HANDOFF-27` through `D-43N-V44-HANDOFF-33`. Two of the seven (V-055, V-064) are forward-attestations only (no source change). Five of the seven (V-054, V-057, V-058, V-063, V-065) require a new `if (_livenessTriggered() ...) revert E();` gate at the entry function, all using the canonical in-source `_livenessTriggered()` helper at `DegenerusGameStorage.sol:1243`. Three of the five new gates use the `&& !gameOver` carve-out (V-054, V-063, V-065 — paths that must remain reachable post-gameOver for legitimate claim/withdraw flows). Two of the five use the simple `_livenessTriggered()` form (V-057, V-058 — gameplay actions, no post-gameOver requirement).

**Catalog-label-inaccuracy summary (per `feedback_verify_call_graph_against_source.md`):**

- V-054 catalog writer-label `_awardDecimatorLootbox`; actual writer site at `:388` is inside `_creditDecJackpotClaimCore`.
- V-057 catalog writer-label `_creditCheckedFromClaimable`; actual writer site at `:547` is inside `_collectBetFunds` — there is NO function named `_creditCheckedFromClaimable` in source (grep confirms).
- V-058 catalog writer-label `_resolveLootboxDirect at :1131`; actual writer site at `:1131` is inside `_addClaimableEth` (`_resolveLootboxDirect` is at `:797` and is a delegatecall stub with no `claimablePool` write).
- V-065 catalog writer-label `sweepSdgnrsClaim`; actual function name is `resolveRedemptionLootbox` — there is NO function named `sweepSdgnrsClaim` in source (grep confirms).

ALL 4 inaccuracies are LABEL-only (writer-function-name mislabeling); the underlying writer-site file:line, the verdict-matrix disposition (VIOLATION), and the recommended tactic are correctly captured. NONE are stale-phantoms — every writer-site file:line exists in current source and the EOA-reach claim is grep-verified. Phase 303 TERMINAL acknowledgment should update the 4 catalog row writer-labels to match the source-of-truth function names. The `[STALE-PHANTOM]` marker does NOT apply to any row in this cluster.

**Source-tree mutation count:** 0 (`contracts/`) + 0 (`test/`). Audit-only posture per `D-43N-AUDIT-ONLY-01`.

**Safe-by-design tokens:** zero (token spelled with hyphens, strict-discipline per `D-43N-AUDIT-ONLY-01` — no upper-case underscore form anywhere in this file).

**Cross-references to other Phase 299 FIXREC cluster outputs:**

- V-063 fix at `D-43N-V44-HANDOFF-31` also closes V-073 (`address(this).balance` outflow via claimWinnings) in **Cluster F (S-20 address(this).balance)** — see sibling Phase 299 FIXREC cluster output for V-073's `D-43N-V44-HANDOFF-NN` anchor.
- V-054 / V-057 / V-058 / V-065 fixes have positive externalities on **Cluster B (`prizePoolsPacked` / `futurePrizePool` family)** via the adjacent `_setFuturePrizePool` / `_setPendingPools` / `_setPrizePools` writes triggered at the same EOA entry functions. Cluster B's tactic-(b) snapshot disposition is independent of these (a) gates, but the gates reduce Cluster B's exploit surface by closing the EOA entry doors.

---

*Phase: 299-Fix-Recommendation-Document-FIXREC, Plan 05 — Cluster E (`claimablePool` game-over family)*
*Drafted: 2026-05-18*
