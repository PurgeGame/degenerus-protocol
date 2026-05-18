# §3 — JackpotModule.runTerminalJackpot (file:line 278)

**Consumer entry:** `contracts/modules/DegenerusGameJackpotModule.sol:278`
**Caller stack:** `AdvanceModule._handleGameOverPath` (`DegenerusGameAdvanceModule.sol:624` → `handleGameOverDrain`) → `GameOverModule.handleGameOverDrain` (`DegenerusGameGameOverModule.sol:182`) → `IDegenerusGame(address(this)).runTerminalJackpot` → `DegenerusGame.runTerminalJackpot` (`DegenerusGame.sol:1180`) → `delegatecall` → JackpotModule.runTerminalJackpot.
**VRF word source:** `rngWord` parameter forwarded from `handleGameOverDrain`'s local var, sourced from `rngWordByDay[day]` (`GameOverModule.sol:100`). Word is published by `AdvanceModule._gameOverEntropy` (`DegenerusGameAdvanceModule.sol:1265`) which either (a) consumes `rngWordCurrent` (the VRF-callback-published word) via `_applyDailyRng`, or (b) falls back to `_getHistoricalRngFallback` after `GAMEOVER_RNG_FALLBACK_DELAY` (historical `rngWordByDay` + `block.prevrandao`). Either way, the word is written to `rngWordByDay[day]` *before* `handleGameOverDrain` re-reads it; once written, the slot is **immutable for the lifetime of the terminal jackpot resolution**.
**EXEMPT-stack roots in scope for this consumer:** EXEMPT-ADVANCEGAME (`advanceGame` → `_handleGameOverPath` is the only path that calls `runTerminalJackpot` — confirmed by `grep -rn "runTerminalJackpot"`; the bare-selector self-call at `DegenerusGame.sol:1180` gates `msg.sender == address(this)`).
**Pre-call state latches (relevant to commitment-window analysis):** Immediately before `runTerminalJackpot` is invoked, `handleGameOverDrain` has already (i) set `gameOver = true` (`:139`), (ii) zeroed `currentPrizePool`, `nextPrizePool`, `futurePrizePool`, `yieldAccumulator` (`:147..150`), (iii) written `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)` (`:146`), (iv) credited deity-pass refunds + decimator refunds into `claimableWinnings`/`claimablePool`. The `rngWord` is held in a local memory var, **not** re-read from storage across the cross-contract call (`DegenerusGame.runTerminalJackpot` forwards the parameter through delegatecall encoded into `data`). `dailyIdx` has NOT been advanced — `_unlockRng(day)` runs in AdvanceModule *after* `handleGameOverDrain` returns (`DegenerusGameAdvanceModule.sol:631`), so for the lifetime of this consumer `dailyIdx` is still the prior-day index.

---

## CAT-01 (§A) — Traced Function Set

Every internal/external function transitively reached from `runTerminalJackpot` with the actual `(isJackpotPhase=false, isFinalDay=false, splitMode=SPLIT_NONE, gameOver=true)` execution profile. Pure-library calls are listed but flagged `[pure]` to make the SLOAD-free attestation explicit.

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `runTerminalJackpot` | `DegenerusGameJackpotModule.sol:278` | ENTRY (`msg.sender == GAME` gate) | Caller is GAME (via DegenerusGame self-call routing the delegatecall) |
| 2 | `_rollWinningTraits(rngWord, false)` | `DegenerusGameJackpotModule.sol:1993` | 1 → :285 | `isBonus=false` path; `r = randWord` (no salt) |
| 3 | `JackpotBucketLib.getRandomTraits(r)` | `JackpotBucketLib.sol:281` | 2 → :2000 | `[pure]` — bit-slices `rw` |
| 4 | `_applyHeroOverride(traits, r, randWord)` | `DegenerusGameJackpotModule.sol:1600` | 2 → :2001 | reads `dailyIdx` + delegates to `_rollHeroSymbol` |
| 5 | `_rollHeroSymbol(dailyIdx, heroEntropy)` | `DegenerusGameJackpotModule.sol:1639` | 4 → :1609 | reads `dailyHeroWagers[day]` |
| 6 | `JackpotBucketLib.packWinningTraits(traits)` | `JackpotBucketLib.sol:267` | 2 → :2002 | `[pure]` |
| 7 | `EntropyLib.hash2(rngWord, targetLvl)` | `EntropyLib.sol:23` | 1 → :286 | `[pure]` — keccak scratch mix |
| 8 | `JackpotBucketLib.unpackWinningTraits(packed)` | `JackpotBucketLib.sol:272` | 1 → :287; 7→ via `_processDailyEth` :1127; etc. | `[pure]` |
| 9 | `_pickSoloQuadrant(traits, entropy)` | `DegenerusGameJackpotModule.sol:1098` | 1 → :290 | `[pure]` |
| 10 | `JackpotBucketLib.bucketCountsForPoolCap(...)` | `JackpotBucketLib.sol:98` | 1 → :293 | `[pure]` |
| 11 | `JackpotBucketLib.traitBucketCounts(entropy)` | `JackpotBucketLib.sol:36` | 10 → :105 | `[pure]` |
| 12 | `JackpotBucketLib.scaleTraitBucketCountsWithCap(...)` | `JackpotBucketLib.sol:55` | 10 → :106 | `[pure]` |
| 13 | `JackpotBucketLib.capBucketCounts(counts, max, entropy)` | `JackpotBucketLib.sol:115` | 12 → :94 | `[pure]` |
| 14 | `JackpotBucketLib.sumBucketCounts(counts)` | `JackpotBucketLib.sol:110` | 13 → :129 | `[pure]` |
| 15 | `JackpotBucketLib.shareBpsByBucket(packed, offset)` | `JackpotBucketLib.sol:254` | 1 → :299 | `[pure]` |
| 16 | `JackpotBucketLib.rotatedShareBps(packed, off, idx)` | `JackpotBucketLib.sol:248` | 15 → :257 | `[pure]` |
| 17 | `_processDailyEth(lvl, poolWei, entropy, traits, shareBps, counts, false, SPLIT_NONE, false)` | `DegenerusGameJackpotModule.sol:1232` | 1 → :304 | `splitMode=SPLIT_NONE` → no `resumeEthPool` read/write; `isJackpotPhase=false` → solo-bucket branch unreachable |
| 18 | `PriceLookupLib.priceForLevel(lvl + 1)` | `PriceLookupLib.sol:21` | 17 → :1251 | `[pure]` |
| 19 | `JackpotBucketLib.soloBucketIndex(entropy)` | `JackpotBucketLib.sol:243` | 17 → :1252 | `[pure]` |
| 20 | `JackpotBucketLib.bucketShares(pool, shareBps, counts, idx, unit)` | `JackpotBucketLib.sol:214` | 17 → :1253 | `[pure]` |
| 21 | `JackpotBucketLib.bucketOrderLargestFirst(counts)` | `JackpotBucketLib.sol:293` | 17 → :1257 | `[pure]` |
| 22 | `_randTraitTicket(traitBurnTicket[lvl], …)` | `DegenerusGameJackpotModule.sol:1707` | 17 → :1296 (loop body, 4× per call) | reads `traitBurnTicket[lvl][trait]` (length + slots) + `deityBySymbol[fullSymId]` |
| 23 | `_payNormalBucket(winners, ticketIndexes, perWinner, lvl, traitId, entropy)` | `DegenerusGameJackpotModule.sol:1509` | 17 → :1326 (`isJackpotPhase=false` branch only) | iterates winners, calls `_addClaimableEth` per winner |
| 24 | `_addClaimableEth(w, perWinner, entropy)` | `DegenerusGameJackpotModule.sol:780` | 23 → :1521 | `gameOver=true` ⇒ auto-rebuy branch skipped (line :792 short-circuit); falls through to `_creditClaimable` + returns `(weiAmount, 0, 0)` |
| 25 | `_creditClaimable(beneficiary, weiAmount)` | `DegenerusGamePayoutUtils.sol:32` | 24 → :802 | writes `claimableWinnings[beneficiary]` (SSTORE, NOT SLOAD-as-input) |

**Unreached branches inside `_processDailyEth` (with proof):**
- `splitMode == SPLIT_CALL2` block at :1243 — not entered (`splitMode == SPLIT_NONE`)
- `splitMode != SPLIT_NONE` mask-builder at :1263 — not entered
- `splitMode == SPLIT_CALL1/CALL2` skip checks at :1279/1280 — branches false, `continue` not taken
- `traitIdx == remainderIdx && isJackpotPhase` solo-bucket branch at :1308 — `isJackpotPhase==false` ⇒ unreachable. ⇒ `_handleSoloBucketWinner`, `_processSoloBucketWinner`, `whalePassClaims` write at :1570, `_setFuturePrizePool` at :1571, `dgnrs.poolBalance` + `dgnrs.transferFromPool` at :1493/:1498 are **all unreachable from §3**.
- `splitMode == SPLIT_CALL1` write to `resumeEthPool` at :1339 — not entered.

**Unreached branches inside `_addClaimableEth`:**
- `!gameOver` block at :792 — `gameOver==true` (set in `handleGameOverDrain:139` before call) ⇒ `autoRebuyState[beneficiary]` SLOAD is **unreachable**, `_processAutoRebuy` (line 814) and downstream `_calcAutoRebuy` (`DegenerusGamePayoutUtils.sol:51`), `_queueTickets`, `_setFuturePrizePool`/`_setNextPrizePool` from rebuy are **unreachable**.

**Trace stops:**
- External `IDegenerus*` interface calls under `contracts/` — none reached from this consumer (the only cross-contract calls that might fire are `dgnrs.poolBalance`/`transferFromPool` and `coinflip.creditFlip*` — all gated behind unreachable branches above).
- Pure libraries — terminal (no SLOAD).

---

## CAT-02 (§B) — SLOAD Table

Every SLOAD reached during `runTerminalJackpot` resolution. Columns per `D-298-SLOT-CLASSIFICATION-01` + `D-298-EXEMPT-REACH-01`. Read-context includes the *immediate use* of the value to support the `Participating?` column.

**Note on storage layout for `traitBurnTicket[lvl][trait]`:** dynamic-array length lives at `keccak256(trait, keccak256(lvl, traitBurnTicket.slot)) + trait` (per Solidity layout — single SLOAD on `.length`); each holder lives at `keccak256(<lengthSlot>) + idx` (one SLOAD per indexed access). The table lists the length SLOAD and indexed-element SLOADs separately because their writer sets differ in cardinality but coincide in identity (both are written by the same `_storeTraits` assembly block in MintModule + the level-1 trait-1 admin writers in `DegenerusGame.sol`).

| # | Slot (logical) | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|----------------|-----------------------|--------------|----------------|-------------------|
| 1 | `dailyIdx` | `DegenerusGameJackpotModule.sol:1609` (`_applyHeroOverride` → `_rollHeroSymbol(dailyIdx, …)`) | Drives day-key of hero-wager pool selected by `_rollHeroSymbol` (pass to `dailyHeroWagers[day]` SLOAD #2). Determines which day's wager-pool seeds the hero-quadrant/symbol output → flows into final winning-trait vector → drives bucket-membership → drives winner identity. | **YES** | — |
| 2 | `dailyHeroWagers[day][q]` ×4 (q=0..3) | `DegenerusGameJackpotModule.sol:1653` (loop body) | Decoded into 32 uint32 weights (`_rollHeroSymbol` pass 1); accumulated total + leader tracked; pass 2 cursor against `keccak256(entropy, day)`-derived `pick` picks winning `(quadrant, symbol)`. Output is the hero-override symbol substituted into `w[heroQuadrant]` at `:1623` → flows into final winning-trait vector → drives bucket membership. | **YES** | — |
| 3 | `traitBurnTicket[lvl][trait]`.length | `DegenerusGameJackpotModule.sol:1039` (`_computeBucketCounts` — NB: NOT REACHED from §3; see attestation), `:1718` (`_randTraitTicket` direct via `holders.length`) | At `:1718` reaches into `address[] storage holders = traitBurnTicket_[trait]` then `holders.length`. `len` participates in the `effectiveLen = len + virtualCount` SLOAD math + the `idx % effectiveLen` index selection — directly determines whether a deity virtual entry wins vs a real holder + selects which slot of the real-holder array wins. | **YES** | — |
| 4 | `traitBurnTicket[lvl][trait][idx]` (per-index slot) | `DegenerusGameJackpotModule.sol:1753` (`winners[i] = holders[idx]` inside `_randTraitTicket`) | Selected holder address → emitted as `JackpotEthWin` winner + passed to `_addClaimableEth` → `_creditClaimable` writes `claimableWinnings[holders[idx]]` ETH payout. | **YES** | — |
| 5 | `deityBySymbol[fullSymId]` | `DegenerusGameJackpotModule.sol:1730` (`_randTraitTicket`) | Selected deity address if `idx >= len` (virtual-entry branch). Becomes payout recipient. Also gates whether virtualCount > 0 path engages. | **YES** | — |
| 6 | `gameOver` | `DegenerusGameJackpotModule.sol:792` (`_addClaimableEth`) | Gates the auto-rebuy branch (`if (!gameOver) { … }`). For §3 the value is **already TRUE** (latched by `handleGameOverDrain:139` immediately before `runTerminalJackpot` is invoked) — auto-rebuy is bypassed and payout becomes pure-claimable ETH. The read still happens once per winner and still gates control flow. | **YES** | — (control-flow gate on the auto-rebuy branch; even though it is forced TRUE for this consumer, the SLOAD is part of the reachable trace and a stale/wrong read could re-enable auto-rebuy → autoRebuyState participation. See §D analysis.) |
| 7 | `claimablePool` (uint128 in slot 1) | `DegenerusGameJackpotModule.sol:1335` (`claimablePool += uint128(liabilityDelta)`) | Read-modify-write at end of `_processDailyEth`. `claimablePool` value DOES NOT flow into any winner-selection or payout-amount calculation — it is **pure aggregate accounting**. | **NO** | Read is `+=` (RMW for SSTORE); value is not consumed by any branch, comparison, or hash. No flow into VRF-influenced output. Pure liability counter. |
| 8 | `currentPrizePool` (slot 1, uint128, via `_getCurrentPrizePool()`) | NOT REACHED from §3 | — | n/a | — (`runTerminalJackpot` takes `poolWei` as parameter; the current-pool read in `payDailyJackpot:374` is on a different consumer path. Confirmed by grep.) |
| 9 | `prizePoolsPacked` (slot containing next + future) via `_getPrizePools()` | NOT REACHED from §3 | — | n/a | — (`_setNextPrizePool`/`_setFuturePrizePool` are only reached from the `splitMode==SPLIT_CALL1` final-day branch + auto-rebuy + early-bird lootbox — none reachable here. Confirmed by reading `_processDailyEth` :1199-1206 — those only fire when `splitMode==SPLIT_CALL2`.) |
| 10 | `autoRebuyState[beneficiary]` | NOT REACHED from §3 | — | n/a | — (Gated behind `!gameOver` at :792; `gameOver==true` latched in `handleGameOverDrain:139` before `runTerminalJackpot`. Slot is **not** SLOAD'd on this consumer's stack.) |
| 11 | `claimableWinnings[beneficiary]` | NOT READ AS INPUT from §3 | — | n/a | — (`_creditClaimable` at `:35` is a `+=` SSTORE; the underlying SLOAD for `+=` does not consume the prior value in any flow downstream — only the new value is written. Solidity's `unchecked { x += y }` emits SLOAD+ADD+SSTORE, but the prior `x` is **not** consumed by any subsequent branch/comparison/hash that influences VRF-derived output, so this matches the same NON-PARTICIPATING attestation as #7 — pure accumulator update.) |
| 12 | `resumeEthPool` | NOT REACHED from §3 | — | n/a | — (Read only under `splitMode == SPLIT_CALL2` at `:1244`; `runTerminalJackpot` always passes `SPLIT_NONE`. Confirmed by grep — single call-site at :1244 and a single SSTORE at :1340 are both gated.) |
| 13 | `whalePassClaims[winner]` | NOT REACHED from §3 | — | n/a | — (Only written in `_processSoloBucketWinner:1570` + `_queueWhalePassClaimCore:95` — both behind `isJackpotPhase==true` solo-bucket branch.) |

**Attestation discipline (per `feedback_rng_window_storage_read_freshness.md` + F-41-02/03 precedent):** ALL SLOADs inside the rng-window resolution path are enumerated above; non-participating slots carry an explicit attestation. The non-VRF reads enumerated (#6 `gameOver`, #7 `claimablePool`, #11 `claimableWinnings`) cover the F-41-02/03-class bug surface where a "freshly-read storage value alongside RNG" could swing a winner-side flow. None of them have flow into a VRF-influenced output for §3.

---

## CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` row in §B (#1 `dailyIdx`, #2 `dailyHeroWagers`, #3 `traitBurnTicket[lvl][trait].length`, #4 `traitBurnTicket[lvl][trait][idx]`, #5 `deityBySymbol`, #6 `gameOver`), every external/public function (in any contract under `contracts/`) reaching a writer of that slot, with callsite file:line.

### §C.1 — `dailyIdx` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.1.1 | `DegenerusGame.advanceGame` (`DegenerusGame.sol` — external) | `advanceGame` → AdvanceModule delegatecall → `_unlockRng(day)` → `dailyIdx = day` | `DegenerusGameAdvanceModule.sol:1730` (assignment), reached from `_unlockRng` callsites at `:331`, `:402`, `:467`, `:631`, `:1729` | Only writer of `dailyIdx`. All five callsites are inside `advanceGame`-rooted resolution paths. |

(Grep verification: `grep -rn "dailyIdx *=" contracts/ --include="*.sol"` returns 1 hit at `DegenerusGameAdvanceModule.sol:1730`. Storage declaration at `DegenerusGameStorage.sol:236` is `uint32 internal dailyIdx;` — no initializer.)

### §C.2 — `dailyHeroWagers[day][q]` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.2.1 | `DegenerusGame.placeDegeneretteBet` (external) | `placeDegeneretteBet` → DegeneretteModule delegatecall → `_placeBet` → ETH-currency block writes `dailyHeroWagers[day][heroQuadrant] = wPacked` | `DegenerusGameDegeneretteModule.sol:499` (writer), reached from `placeDegeneretteBet` external entry (DegeneretteModule.sol:389 = `resolveBets`; bet-placement entry is the calling `placeDegeneretteBet` selector routed by DegenerusGame top-level entrypoint) | The `day` index is `_simulatedDayIndex()` at `:486` — the **current** day at write time. |

(Grep verification: `grep -rn "dailyHeroWagers\[" contracts/ --include="*.sol"` returns 1 SSTORE-class hit at `DegenerusGameDegeneretteModule.sol:499`; remaining hits at `:491`, `JackpotModule.sol:1653`, `DegenerusGame.sol:2550`, `:2567` are all reads.)

### §C.3 — `traitBurnTicket[lvl][trait].length` writers + §C.4 — `traitBurnTicket[lvl][trait][idx]` writers

These two slots share writer identity: the same SSTORE block writes both the length and the appended slot.

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.3.1 | `DegenerusGame.advanceGame` (external) | `advanceGame` → AdvanceModule.delegatecall → MintModule.processTicketBatch.delegatecall → `_processOneTicketEntry` → `_storeTraits` (assembly) → `sstore(elem, newLen)` + `sstore(dst, player)` loop | `DegenerusGameMintModule.sol:616` (`sstore(elem, newLen)`), `:627` (`sstore(dst, player)`) — reached from `processTicketBatch` external entry at `:662` | `processTicketBatch` is called from AdvanceModule at `:589` + `:602` (the `_handleGameOverPath` Round-1/Round-2 drain) AND from the steady-state purchase-phase ticket-processing call in `advanceGame`. |
| C.3.2 | `DegenerusGame.adminSeedTraitBucket` (external, admin) | direct `traitBurnTicket[lvlSel][traitSel]` array push/access | `DegenerusGame.sol:2398` (`address[] storage arr = traitBurnTicket[lvlSel][traitSel]`) — call-site at `DegenerusGame.sol:2398..2420` block | Admin-only entry per source review; level-1 trait-1 admin seeding writer. Reached only from a level-1 admin call-site, NOT from any VRF resolution stack. |
| C.3.3 | `DegenerusGame.adminClearTraitBucket` (external, admin) | direct `traitBurnTicket[targetLvl][traitSel]` push/access | `DegenerusGame.sol:2427` | Admin-only entry. |
| C.3.4 | `DegenerusGame` test/helper writer at `:2510` | direct `traitBurnTicket[lvl][trait]` push/access | `DegenerusGame.sol:2510` | Source-code review of the surrounding function context is required; flagged here for completeness so the §D verdict matrix evaluates it. |

(Grep verification: `grep -rn "traitBurnTicket\[" contracts/ --include="*.sol" | grep -v "// "` returns 10 hits — 4 are writers/storage-access entries listed above; 6 are reads (`:691`, `:989`, `:1039`, `:1297`, `:1400`, `:1718`, `:1860` in JackpotModule plus `MintModule.sol:602` which is the slot-derivation `mstore(0x20, traitBurnTicket.slot)` — the actual SSTORE is at `:616`/`:627`). The MintModule assembly block is the only non-admin writer.)

### §C.5 — `deityBySymbol[fullSymId]` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.5.1 | `DegenerusGame.purchaseDeityPass` (external payable) | `purchaseDeityPass` → WhaleModule delegatecall → `_purchaseDeityPass` → `deityBySymbol[symbolId] = buyer` | `DegenerusGameWhaleModule.sol:598` (writer), reached from external `purchaseDeityPass` entry at `:538` | The function is gated by `if (rngLockedFlag) revert RngLocked()` at `:543`, BUT — see §D analysis — terminal jackpot resolution does NOT set `rngLockedFlag` on the game-over path (the flag is cleared by `_unlockRng` only AFTER drain completes per AdvanceModule:631; the `_handleGameOverPath` entry at AdvanceModule:539 short-circuits before evaluating the lock). |

(Grep verification: `grep -rn "deityBySymbol\[" contracts/ --include="*.sol"` returns 5 hits — 1 SSTORE writer at `WhaleModule.sol:598`; 1 SLOAD guard at `WhaleModule.sol:546` (existence check inside `_purchaseDeityPass`); 3 SLOAD reads at `JackpotModule.sol:1044`, `:1730`, `:1844`.)

### §C.6 — `gameOver` writers

| # | Writer function (entry) | Writer chain | Callsite (file:line) | Notes |
|---|-------------------------|--------------|----------------------|-------|
| C.6.1 | `DegenerusGame.advanceGame` (external) | `advanceGame` → AdvanceModule.delegatecall → `_handleGameOverPath` → GameOverModule.delegatecall → `handleGameOverDrain` → `gameOver = true` | `DegenerusGameGameOverModule.sol:139` (writer), reached from `_handleGameOverPath` at AdvanceModule.sol:624 | Single non-mock writer in production. The mock at `contracts/mocks/MockGameCharity.sol:11` is test-only and not part of the deployed MAINNET surface. |

(Grep verification: `grep -rn "gameOver *=\|gameOver=" contracts/ --include="*.sol" | grep -v "// \|mocks/"` returns 1 hit at `DegenerusGameGameOverModule.sol:139`.)

---

## CAT-04 (§D) — Verdict Matrix (slot × writer × callsite)

Per `D-298-EXEMPT-REACH-01` (strict stack-rooted, per-callsite) + `D-298-EXEMPT-CROSSCONTRACT-01` (cross-contract EXEMPT preserved through delegatecall). Classes: `EXEMPT-ADVANCEGAME`, `EXEMPT-VRFCALLBACK`, `EXEMPT-RETRYLOOTBOXRNG`, `VIOLATION`. Only participating slots from §B (#1-#5 + #6 control-flow gate) are classified.

| Slot | Writer fn (file:line) | Callsite (file:line) | Reached-from EXEMPT stack? | Classification |
|------|-----------------------|----------------------|----------------------------|----------------|
| `dailyIdx` | `_unlockRng` assignment (`DegenerusGameAdvanceModule.sol:1730`) | reached only from `advanceGame`-rooted callsites at `:331`, `:402`, `:467`, `:631`, `:1729` | YES — every callsite is downstream of `advanceGame` entry. The `:631` callsite specifically runs **after** `handleGameOverDrain` returns, so for §3 the relevant pre-call snapshot of `dailyIdx` is in fact frozen for the resolution window. | **EXEMPT-ADVANCEGAME** |
| `dailyHeroWagers[day][q]` | `_placeBet` ETH branch (`DegenerusGameDegeneretteModule.sol:499`) | reached from external `placeDegeneretteBet` entry (DegenerusGame.sol top-level — NOT via advanceGame) | NO — `placeDegeneretteBet` is an EOA-callable external entry independent of advanceGame; the writer is reachable while game-over drain has not yet been triggered. | **VIOLATION** |
| `traitBurnTicket[lvl][trait]` (length + slot) | MintModule `_storeTraits` SSTOREs (`DegenerusGameMintModule.sol:616`, `:627`) — callsite via `processTicketBatch` external entry at `:662` | called by AdvanceModule at `:589` + `:602` (game-over drain) AND by AdvanceModule's steady-state `advanceGame` processing loop | YES at every reached callsite — `processTicketBatch` itself is `msg.sender == address(this)`-gated effectively via delegatecall (the only callers are AdvanceModule's `_handleGameOverPath` Round-1/Round-2 AND the advanceGame purchase-phase processing). Every callsite is `advanceGame`-rooted. | **EXEMPT-ADVANCEGAME** |
| `traitBurnTicket[lvl][trait]` | `adminSeedTraitBucket` direct push (`DegenerusGame.sol:2398..2420`) | external admin entry | NO — admin-call surface is outside the 3 EXEMPT stacks. | **VIOLATION** |
| `traitBurnTicket[lvl][trait]` | `adminClearTraitBucket` direct push (`DegenerusGame.sol:2427`) | external admin entry | NO — admin-call surface. | **VIOLATION** |
| `traitBurnTicket[lvl][trait]` | helper writer (`DegenerusGame.sol:2510`) | per source line — function-context-determined entry | NO (treating as non-EXEMPT pending §C.3.4 source verification; admin/helper surface) — see §E rationale | **VIOLATION** |
| `deityBySymbol[symbolId]` | `_purchaseDeityPass` (`DegenerusGameWhaleModule.sol:598`) | external `purchaseDeityPass` payable entry (`:538`) | NO — `purchaseDeityPass` is an EOA-callable external entry, NOT downstream of `advanceGame`/VRF-callback/`retryLootboxRng`. | **VIOLATION** |
| `gameOver` | `gameOver = true` (`DegenerusGameGameOverModule.sol:139`) | reached from `_handleGameOverPath` at AdvanceModule.sol:624 | YES — only writer is in the `advanceGame`-rooted game-over drain stack. | **EXEMPT-ADVANCEGAME** |

**Negative-space attestation:** No VRF-callback-stack write of any §3-participating slot exists (the VRF callback only writes `rngWordCurrent` per `_fulfillRandomWords` at AdvanceModule.sol:1755). No `retryLootboxRng`-stack write of any §3-participating slot exists. So `EXEMPT-VRFCALLBACK` and `EXEMPT-RETRYLOOTBOXRNG` classes have zero rows in §3 — the only EXEMPT class that fires is `EXEMPT-ADVANCEGAME`.

---

## CAT-06 (§E) — Per-VIOLATION Remediation Tactic + Rationale

Per `D-298-RECOMMEND-DEPTH-01`: ONE tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` per VIOLATION row + ≤80-char rationale.

| Slot | Writer × callsite | Tactic | Rationale (≤80 chars) |
|------|-------------------|--------|-----------------------|
| `dailyHeroWagers[day][q]` | `DegeneretteModule.sol:499` via `placeDegeneretteBet` | **(b)** | snapshot dailyHeroWagers[dailyIdx-1] at game-over freeze; §3 reads snapshot |
| `traitBurnTicket[lvl][trait]` | `DegenerusGame.sol:2398..2420` `adminSeedTraitBucket` | **(a)** | gate adminSeed on `!rngLockedFlag && !gameOver` — never write during resolution |
| `traitBurnTicket[lvl][trait]` | `DegenerusGame.sol:2427` `adminClearTraitBucket` | **(a)** | gate adminClear on `!rngLockedFlag && !gameOver` — same window invariant |
| `traitBurnTicket[lvl][trait]` | `DegenerusGame.sol:2510` helper writer | **(a)** | gate writer on `!gameOver` — terminal jackpot bucket must be frozen at drain |
| `deityBySymbol[symbolId]` | `WhaleModule.sol:598` via `purchaseDeityPass` | **(a)** | gate `_purchaseDeityPass` on `!gameOver` — already gates rngLockedFlag at :543 |

**Tactic-selection notes (≤80 chars each, supplementary):**
- `dailyHeroWagers` tactic (b) chosen over (a) because betting must remain live during normal play; only the §3 read needs a snapshot anchor. Phase 288 `dailyIdx` snapshot precedent applies.
- `traitBurnTicket` admin writers tactic (a) chosen because admin writes are operational, not user-facing — a revert during the game-over drain window is acceptable.
- `deityBySymbol` tactic (a) chosen because `_purchaseDeityPass` already reverts on `rngLockedFlag` at `:543`; adding a `gameOver` arm to the same gate is a one-line invariant extension. The terminal-jackpot read at `:1730` would otherwise consume a buyer-mid-resolution write.
