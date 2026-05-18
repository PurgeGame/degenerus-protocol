# §10 — MintModule trait-generation consumer (Phase 290 MINTCLN audit-subject surface)

**Consumer entry:** `contracts/modules/DegenerusGameMintModule.sol:537` (`_raritySymbolBatch` — the 3-input keccak at :563-:565 `keccak256(abi.encode(baseKey, entropyWord, groupIdx))` is the VRF-derived-entropy consumer; the assembly `sstore` block at :600-:629 is the trait-distribution OUTPUT site writing `traitBurnTicket[lvl][traitId]`'s length + element slots).

**Two outer-loop entry points reach this consumer:**
1. `processFutureTicketBatch(uint24 lvl, uint256 entropy)` at `MintModule.sol:385-526` — entropy passed as parameter (caller-supplied from `rngGate`-returned `rngWord` via `AdvanceModule._processFutureTicketBatch:1438`).
2. `processTicketBatch(uint24 lvl)` at `MintModule.sol:662-720` — entropy SLOADed at `:686` from `lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1]`.

**Caller stack:** Both functions are `external` on the MintModule but the MintModule is delegatecall-only from `DegenerusGame` (no `fallback()` in `DegenerusGame.sol` — confirmed via `grep -nE "fallback" contracts/DegenerusGame.sol` returning only a doc-comment hit). `grep -rn "processFutureTicketBatch\b\|processTicketBatch\b" contracts/ --include="*.sol"` confirms ONLY 4 callsites, ALL inside `DegenerusGameAdvanceModule.sol`: `:322` + `:414` + `:1438` (`_processFutureTicketBatch`); `:589` + `:607` + `:1516` (`processTicketBatch.selector` delegatecall in `_handleGameOverPath` + `_runProcessTicketBatch`); `:221` + `:277` + `:357` reach `_runProcessTicketBatch`. Every callsite lives inside `advanceGame`'s static call graph (entry at `AdvanceModule.sol:158`).

**VRF word source:**
- For `processFutureTicketBatch`: the `entropy` parameter flows from `AdvanceModule.advanceGame:290` `(uint256 rngWord, …) = rngGate(…)` — `rngGate` returns either `rngWordCurrent` (VRF-callback-published, nudge-mixed via `_applyDailyRng:1840` BEFORE `rngLockedFlag` clears) or `rngWordByDay[day]` (cached for the day). The cached parameter is forwarded through `_prepareFutureTickets:1463` / direct `_processFutureTicketBatch` invocations.
- For `processTicketBatch`: the entropy is SLOAD'd at `MintModule:686` from `lootboxRngWordByIndex[lrIndex - 1]` where `lrIndex` is read from `lootboxRngPacked` (the LR_INDEX field). `lootboxRngWordByIndex[i]` is written ONLY by `_finalizeLootboxRng:1256` (advanceGame-stack), `rawFulfillRandomWords:1761` (mid-day VRF-callback branch), and `_backfillOrphanedLootboxIndices:1818` (advanceGame-stack post-gap backfill).

**EXEMPT-stack roots in scope for this consumer:** EXEMPT-ADVANCEGAME (every reachable `_raritySymbolBatch` callsite is downstream of `advanceGame`-rooted outer loops — confirmed by the call-graph enumeration above). EXEMPT-VRFCALLBACK does NOT directly invoke `_raritySymbolBatch` — `rawFulfillRandomWords` only writes `rngWordCurrent` OR `lootboxRngWordByIndex[index]` then returns; the consumer is reached on the NEXT `advanceGame` call. EXEMPT-RETRYLOOTBOXRNG is the lootbox-VRF retry surface (`AdvanceModule.retryLootboxRng:1132`), domain-separated from the daily-VRF that feeds this consumer per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A — does NOT directly invoke `_raritySymbolBatch`.

**Pre-call state latches (relevant to commitment-window analysis):** Immediately before `_raritySymbolBatch` is invoked from either outer loop:
- (i) For `processTicketBatch` (mid-day same-day path at `AdvanceModule:206-238` and `_handleGameOverPath:584-622`): `rngLockedFlag` may be FALSE — the mid-day path checks `_lrRead(LR_MID_DAY_SHIFT)` to detect a pending mid-day VRF, and reverts `RngNotReady` if `lootboxRngWordByIndex[index-1] == 0` (`:213`). But the lock state itself is not asserted at the call boundary. **The entropy is committed: `lootboxRngWordByIndex[index-1]` is monotonic write-once (the `if (lootboxRngWordByIndex[index] != 0) return` guard at `_finalizeLootboxRng:1255` + at `rawFulfillRandomWords:1750` `if (requestId != vrfRequestId || rngWordCurrent != 0) return` ensures one-shot semantics).**
- (ii) For `processTicketBatch` (new-day path at `AdvanceModule:262-285` and `:357-363`): `rngLockedFlag = true` was set at `_requestRng:1634` AND immediately cleared at `_unlockRng:1731`. Inside the daily window, `rngLockedFlag=true` while `processTicketBatch` runs — `_finalizeLootboxRng:1253` is called at `rngGate:1234` BEFORE the outer-loop processing reaches `processTicketBatch`, so the entropy slot is populated before consumption.
- (iii) For `processFutureTicketBatch` (phase-transition FF drain at `:322-329`, near-future drain at `:344-352`, level-transition next-level drain at `:414`): `rngLockedFlag=true` for the entire window from `_requestRng:1634` to `_unlockRng` (called at `:331` after FF drain, `:402` after purchase-daily, `:467` after jackpot-phase, `:631` after game-over). The `entropy` parameter is the just-applied `rngWord` from `rngGate` — same parameter forwarded into every callsite within one `advanceGame` invocation.
- (iv) The `baseKey` carries `(lvl << 224) | (queueIdx << 192) | (player << 32) | owed` per Phase 290 MINTCLN-02 collapse. The `lvl` field is the cached function-parameter `lvl` (constant during the resolution loop). `queueIdx` is the loop-local `idx` (monotonically increasing). `player` is the loop-local `queue[idx]` SLOAD. `owed` is the loop-local `uint32(packed >> 8)` where `packed = ticketsOwedPacked[rk][player]` — DOES SLOAD per outer-loop iteration; per Phase 290 design-intent trace section (ii) the stale `owed==0` in `_processOneTicketEntry` post-`_resolveZeroOwedRemainder` branch is ACCEPTABLE under structural-closure reasoning (single-trait emission only).
- (v) The `traitBurnTicket[lvl][traitId]` length slot is the OUTPUT — its prior length is read (`let len := sload(elem)` at `:614`) and used to compute the destination data slot. The PRE-existing length is therefore a participating SLOAD even though the consumer ALSO writes it.
- (vi) The `_rollRemainder` helper at `:638-:650` re-hashes via `EntropyLib.hash2(entropy, rollSalt|baseKey)` and consumes only stack values + `rem` — no additional SLOADs beyond what the outer loop already enumerates.

---

## CAT-01 (§A) — Traced Function Set

Every internal/external function transitively reached from `processFutureTicketBatch` AND `processTicketBatch` with explicit file:line citation per `feedback_verify_call_graph_against_source.md`. The two outer-loop entries are both traced because both reach the same inner consumer `_raritySymbolBatch` + `_rollRemainder`.

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `processFutureTicketBatch(uint24 lvl, uint256 entropy)` | `MintModule.sol:385` | ENTRY (delegatecall-only from `AdvanceModule._processFutureTicketBatch:1438`) | Outer loop A |
| 2 | `processTicketBatch(uint24 lvl)` | `MintModule.sol:662` | ENTRY (delegatecall-only from `AdvanceModule._runProcessTicketBatch:1507` + `_handleGameOverPath:589/607`) | Outer loop B |
| 3 | `_tqReadKey(uint24 lvl)` | `Storage.sol:723` | 1 → :390 (false branch); 2 → :663 | `[view]` reads `ticketWriteSlot` |
| 4 | `_tqFarFutureKey(uint24 lvl)` | `Storage.sol:731` | 1 → :390 (true branch) + :512; 2 (unreachable) | `[pure]` |
| 5 | `_resolveZeroOwedRemainder(packed, rk, player, entropy, baseKey)` | `MintModule.sol:723` | 2 → :770 (via `_processOneTicketEntry`) | Calls `_rollRemainder`; writes `ticketsOwedPacked[rk][player]` |
| 6 | `_processOneTicketEntry(player, lvl, rk, room, processed, entropy, queueIdx)` | `MintModule.sol:752` | 2 → :690 | Calls `_raritySymbolBatch`, `_rollRemainder`, `_resolveZeroOwedRemainder`; writes `ticketsOwedPacked` |
| 7 | `_raritySymbolBatch(player, baseKey, startIndex, count, entropyWord)` | `MintModule.sol:537` | 1 → :470; 6 → :793 | **The 3-input keccak consumer**: `keccak256(abi.encode(baseKey, entropyWord, groupIdx))` at `:563-:565`. Writes `traitBurnTicket[lvl][traitId]` via assembly `sstore` at `:600-:629`. |
| 8 | `_rollRemainder(entropy, rollSalt, rem)` | `MintModule.sol:638` | 1 → :444, :483; 5 → :738; 6 → :807 | `[pure]` — delegates to `EntropyLib.hash2` |
| 9 | `EntropyLib.hash2(uint256 a, uint256 b)` | `EntropyLib.sol:23` | 8 → :648 | `[pure]` keccak scratch-slot mix; ZERO SLOAD |
| 10 | `DegenerusTraitUtils.traitFromWord(uint64 rnd)` | `DegenerusTraitUtils.sol:143` | 7 → :577 | `[pure]` — weighted-grid trait derivation from low bits of LCG-step word; ZERO SLOAD |
| 11 | `_lrRead(uint256 shift, uint256 mask)` | `Storage.sol:1337` | 2 → :686 | `[view]` reads `lootboxRngPacked` |

> **Stop boundary:** `_raritySymbolBatch` is a `private` function with no further internal sub-calls beyond pure libraries `EntropyLib`/`DegenerusTraitUtils`. The inline assembly block at `:600-:629` is the trait-output SSTORE site — it computes `levelSlot = keccak256(lvl, traitBurnTicket.slot)` (Solidity standard storage layout) and writes `traitBurnTicket[lvl][traitId].length` + array element slots. No further function calls inside the assembly block.

> **Cross-module reach into Storage.sol:** `_queueTicketsScaled` / `_queueTickets` / `_queueTicketRange` are writers of `ticketsOwedPacked` + `ticketQueue` reached from OTHER external entry points (purchase / whale / lootbox / decimator / jackpot stacks). They are NOT reached transitively from this consumer's resolution stack — but they ARE the participating-slot writers enumerated in §C below.

> **`_purchaseFor` is NOT in this trace:** the parent `_purchaseFor` at `MintModule:899-1188` is a SEPARATE entry surface (EOA-purchase path); the `cachedJpFlag && rngLockedFlag` gate at `:1221` (referenced in `D-298-CONSUMER-LIST-01` as a locked-gate convention marker) is INSIDE `_callTicketPurchase` and routes the `targetLevel` of NEW purchases — it does NOT lead to `_raritySymbolBatch` directly. The `_purchaseFor` → `_queueTicketsScaled:1129` path is a WRITER of participating slots (`ticketsOwedPacked` + `ticketQueue` + `prizePoolsPacked`), enumerated below in §C.

---

## CAT-02 (§B) — SLOAD Table

Every storage read reached anywhere in §A's function set is enumerated per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent — NON-PARTICIPATING slots get explicit attestation). Columns: `Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO`.

| Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|------|-----------------------|--------------|----------------|-------------------|
| `lootboxRngPacked` (LR_INDEX field, bits 0..47) | `Storage.sol:1338` reached from `MintModule.sol:686` (`uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1`) | Computes index into `lootboxRngWordByIndex[]` → directly selects which VRF word feeds `entropy` for `_raritySymbolBatch` keccak | **YES** | — |
| `lootboxRngWordByIndex[lrIndex - 1]` | `MintModule.sol:686` | THE VRF word that becomes the `entropy` parameter passed to `_raritySymbolBatch` via `_processOneTicketEntry` for `processTicketBatch` path | **YES** | — (this IS the VRF-derived entropy) |
| `ticketWriteSlot` (bool) | `Storage.sol:719/724` (`_tqWriteKey`/`_tqReadKey`) reached from `MintModule.sol:390, :663` | Selects which `ticketQueue[]` array slot is the READ slot (the slot being drained) → determines `rk = _tqReadKey(lvl)` → determines which `ticketQueue[rk]` array the loop iterates AND which `ticketsOwedPacked[rk][player]` per-player counter is consulted | **YES** | — |
| `ticketLevel` (uint24) | `MintModule.sol:389` (`inFarFuture = (ticketLevel == (lvl \| TICKET_FAR_FUTURE_BIT))`); `:399` (`if (!inFarFuture && ticketLevel != lvl)`); `:667` (`if (ticketLevel != lvl)`) | Control-flow flag: distinguishes far-future drain branch from near-future + signals whether a fresh outer-loop is starting (resets `ticketCursor`). DOES influence `rk` selection at `:390` (via `_tqFarFutureKey` vs `_tqReadKey`) — different `rk` → different `baseKey.queueIdx` packing path AND different `ticketsOwedPacked[rk]` namespace. | **YES** | — |
| `ticketCursor` (uint32) | `MintModule.sol:404` (`idx = ticketCursor`); `:672` (same) | Loop entry point — determines `queueIdx` packed into `baseKey` at `:427`/:764 (`(idx << 192)`). Different cursor → different `baseKey` low bits → different keccak seed at `:563-:565`. | **YES** | — |
| `ticketQueue[rk]` (length + element slots) | `MintModule.sol:391` (`queue = ticketQueue[rk]`); `:393` (`total = queue.length`); `:405` (`idx >= total` check); `:422` (`address player = queue[idx]`); `:513` (`if (ticketQueue[ffk].length > 0)`); `:664-:665` (same in processTicketBatch); `:691` (`queue[idx]` in processTicketBatch via `_processOneTicketEntry`) | Length determines loop bound. Element SLOAD provides `player` — `player` is packed into `baseKey` middle bits at `:428`/`:765` (`(uint256(uint160(player)) << 32)`). Different `player` → different `baseKey` → different keccak seed. **Length AND elements are both participating.** | **YES** | — |
| `ticketsOwedPacked[rk][player]` (uint40) | `MintModule.sol:423` (`packed = ticketsOwedPacked[rk][player]`); `:761` (same in `_processOneTicketEntry`); `:724` (passed by-value to `_resolveZeroOwedRemainder`) | High 32 bits `owed` are packed into `baseKey` low 32 bits at `:429`/`:766` (`uint256(owed)`). Per Phase 290 MINTCLN-02 collapse this is the carrier of the cross-call seed-separation invariant. Low 8 bits `rem` drives `_rollRemainder` outcome. **Direct keccak-input contributor.** | **YES** | — |
| `traitBurnTicket[lvl][traitId].length` (pre-existing length, per traitId touched) | `MintModule.sol:614` (assembly `let len := sload(elem)` where `elem := add(levelSlot, traitId)`) inside `_raritySymbolBatch`'s output loop | Read to determine destination offset for the player-address writes (`dst := add(data, len)`). The new length is `len + occurrences` (`:615`). **Per `feedback_rng_window_storage_read_freshness.md`: the pre-existing length is a SLOAD reached inside the rng-window — it must be classified.** | **NO** | The length value determines the destination slot offset for writing — it does NOT feed back into the keccak seed at `:563-:565` (which is already computed at this point in the loop) and does NOT influence which `traitId` is selected (already determined by `DegenerusTraitUtils.traitFromWord(s)` at `:577`). A mid-window change to `traitBurnTicket[lvl][traitId].length` would change WHERE the player addresses are written, but the writers under enumeration are themselves only this same `_raritySymbolBatch` (no other writer exists — `grep -rn "traitBurnTicket" contracts/` confirms zero other SSTORE sites). The slot is therefore self-coupled within this consumer's stack — no external writer can race it. **F-41-02/03-style attestation: no concurrent writer outside the same delegatecall stack.** |
| `level` (uint24, storage slot) | Indirect: `Storage.sol:571` (`_queueTickets`) — NOT reached transitively from this consumer's resolution stack. (Reachable from external `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` callers — see §C writer enumeration for participating-slot context.) | (not reached inside `_raritySymbolBatch` trace) | **N/A** | The cached `lvl` parameter inside `processFutureTicketBatch`/`processTicketBatch` is a function argument, NOT a storage read. Storage `level` is read by OTHER paths that WRITE participating slots (`ticketsOwedPacked` + `ticketQueue` + `traitBurnTicket` via downstream `_raritySymbolBatch` — though `_raritySymbolBatch` itself doesn't SLOAD `level`, it derives `lvl` from `baseKey >> 224` at `:591`). |
| `traitBurnTicket.slot` reference | `MintModule.sol:602` (`mstore(0x20, traitBurnTicket.slot)`) | Compile-time slot constant for keccak storage-layout computation (`levelSlot := keccak256(0x00, 0x40)` at `:603`). | **NO** | Compile-time constant — Solidity storage-layout slot reference, NOT a runtime SLOAD. Standard mapping-layout: `slot(traitBurnTicket[lvl]) = keccak256(lvl . slot)`. |

> **Pure-helper completeness attestation:** `EntropyLib.hash2`, `DegenerusTraitUtils.traitFromWord`, `_tqFarFutureKey` all perform ZERO SLOADs (`grep -n "sload\|storage" contracts/libraries/EntropyLib.sol contracts/DegenerusTraitUtils.sol` returns only pointer-type declarations). `_rollRemainder` is `pure` (no SLOAD). The LCG iteration at `MintModule.sol:574, :577` is local-variable arithmetic only.

> **Cross-call freshness gate (Phase 290 MINTCLN-02 invariant):** Per Phase 290 `290-01-DESIGN-INTENT-TRACE.md` section (i): the SLOAD of `ticketsOwedPacked[rk][player].owed` per outer-loop iteration produces a SHRINKING low-32-bit value for `baseKey` across cross-call drains on the same `(rk, player)` pair (`remainingOwed = owed - take` at `:480` + `:804`). This SLOAD is the carrier of the cross-call seed-separation invariant that replaces the v41 Phase 281 `ownedSalt` 4th keccak input. **The SLOAD freshness IS the algorithmic invariant** — a stale value would re-introduce F-41-01.

> **Participating-set summary (forwards into §C):** `lootboxRngPacked` (LR_INDEX field), `lootboxRngWordByIndex[lrIndex-1]`, `ticketWriteSlot`, `ticketLevel`, `ticketCursor`, `ticketQueue[rk]` (length + elements), `ticketsOwedPacked[rk][player]`.

---

## CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` slot in §B, every external/public function across all `contracts/` that writes the slot is enumerated, per-callsite. Each row: `Slot | Writer fn | Writer file:line | Callsite file:line | Reach path`.

### Slot: `lootboxRngPacked` (LR_INDEX field — bits 0..47)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_finalizeRngRequest` increments LR_INDEX | `AdvanceModule.sol:1620-:1624` (`_lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, _lrRead(...) + 1)`) | `:1620` (inside `_finalizeRngRequest` which is called from `_requestRng`, reached from `rngGate` → `advanceGame:290`) | advanceGame → `rngGate` → `_requestRng` → `_finalizeRngRequest` |
| `DegenerusGameStorage.sol:1312` initializer | `Storage.sol:1312` (`lootboxRngPacked = 1 \| (1000 << 112) \| (14 << 176)`) | `:1312` | constructor / static initializer (genesis only) |

**Note:** Other fields of `lootboxRngPacked` (PENDING_ETH, PENDING_BURNIE, THRESHOLD, MIN_LINK, MID_DAY) have their own writers reached from `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / admin paths — but those writes mask only their own bit-ranges (the `_lrWrite` helper at `Storage.sol:1342` preserves other bits via `(packed & ~(mask << shift)) | …`). LR_INDEX-field writes are gated to advanceGame-stack only.

### Slot: `lootboxRngWordByIndex[i]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_finalizeLootboxRng(rngWord)` | `AdvanceModule.sol:1253` (writes `lootboxRngWordByIndex[index] = rngWord` at `:1256`) | `:275, :1234, :1296, :1326` (all inside `advanceGame` / `rngGate` / `_gameOverEntropy` / `_backfillGapDays`) | advanceGame → `_finalizeLootboxRng` (one-shot guard at `:1255` `if (… != 0) return`) |
| `rawFulfillRandomWords` mid-day branch | `AdvanceModule.sol:1745` (writes at `:1761` when `!rngLockedFlag`) | `:1761` (only mid-day path; the daily path writes `rngWordCurrent` instead) | Chainlink VRF coordinator → `rawFulfillRandomWords` (msg.sender gate at `:1749`) — **EXEMPT-VRFCALLBACK stack** |
| `_backfillOrphanedLootboxIndices(vrfWord)` | `AdvanceModule.sol:1806` (writes `lootboxRngWordByIndex[i] = fallbackWord` at `:1818`) | `:1207` (inside `rngGate` gap-day backfill) | advanceGame → `rngGate` → `_backfillOrphanedLootboxIndices` |

### Slot: `ticketWriteSlot` (bool)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_swapTicketSlot(purchaseLevel)` | `Storage.sol:741` (writes `ticketWriteSlot = !ticketWriteSlot` at `:744`) | `:755` (inside `_swapAndFreeze`); `AdvanceModule.sol:601` (inside `_handleGameOverPath` for round-2 drain); `AdvanceModule.sol:1095` (inside `_consolidatePoolsAndRewardJackpots` post-drain swap). All callsites inside `advanceGame`. | advanceGame → `_swapAndFreeze` / `_handleGameOverPath` / `_consolidatePoolsAndRewardJackpots` |

### Slot: `ticketLevel` (uint24)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `processFutureTicketBatch` self-writes | `MintModule.sol:395, :400, :408, :514, :519, :523` (multiple branches: reset to 0, set to `lvl`, set to `lvl \| TICKET_FAR_FUTURE_BIT`) | `:395` etc. (self) | advanceGame → `_processFutureTicketBatch` (delegatecall) — **self-stack** |
| `processTicketBatch` self-writes | `MintModule.sol:668, :676, :716` | `:668` etc. (self) | advanceGame → `_runProcessTicketBatch` (delegatecall) — **self-stack** |
| `advanceGame` phase-transition FF-promotion | `AdvanceModule.sol:319` (`ticketLevel = ffLevel \| TICKET_FAR_FUTURE_BIT`) | `:319` | advanceGame self-write |

**No external writer of `ticketLevel` exists outside the advanceGame-stack** — `grep -rn "ticketLevel\s*=" contracts/ --include="*.sol"` confirms all callsites are inside `MintModule.processTicketBatch` / `MintModule.processFutureTicketBatch` / `AdvanceModule.advanceGame`.

### Slot: `ticketCursor` (uint32)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `processFutureTicketBatch` self-writes | `MintModule.sol:394, :401, :407, :507, :515, :518, :522` | (self) | advanceGame stack |
| `processTicketBatch` self-writes | `MintModule.sol:669, :675, :711, :715` | (self) | advanceGame stack |
| `advanceGame` FF-promotion reset | `AdvanceModule.sol:320` (`ticketCursor = 0`) | `:320` | advanceGame self-write |

**Same as `ticketLevel`** — no external writer; all writes are inside advanceGame-stack.

### Slot: `ticketQueue[rk]` (length + elements)

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_queueTickets(buyer, targetLevel, quantity, rngBypass)` | `Storage.sol:559` (`.push(buyer)` at `:580`) | Callsites: `DegenerusGame.sol:226, :227` (constructor — SDGNRS + VAULT initial); `AdvanceModule.sol:1535, :1541` (phase-transition vault tickets); `WhaleModule.sol:313, :482, :625` (whale-bundle / lazy-pass / deity-pass tickets); `LootboxModule.sol:1067, :1190` (lootbox resolution tickets); `JackpotModule.sol:703, :837, :1007, :2305` (auto-rebuy / jackpot bonus tickets). | EOA → various external entries (purchaseWhaleBundle, purchaseLazyPass, purchaseDeityPass, openLootBox, openBurnieLootBox, claimWhalePass etc.) → `_queueTickets`; advanceGame → various |
| `_queueTicketsScaled(buyer, targetLevel, quantityScaled, rngBypass)` | `Storage.sol:593` (`.push(buyer)` at `:612`) | `MintModule.sol:1129` (inside `_purchaseFor` after ticket-cost computation) | EOA → `purchase` / `purchaseCoin` → `_purchaseFor` → `_queueTicketsScaled` |
| `_queueTicketRange(buyer, startLevel, numLevels, ticketsPerLevel, rngBypass)` | `Storage.sol:646` (`.push(buyer)` at `:666`) | `DecimatorModule.sol:582` (decimator-tier winner tickets); `WhaleModule.sol:973` (claimWhalePass range claim); `Storage.sol:1135` (whale-pass redemption inside `_redeemWhalePassRange`) | EOA → `recordDecBurn` (via BurnieCoin) / `claimWhalePass` / whale-pass redemption → `_queueTicketRange` |
| `processFutureTicketBatch` self-writes (delete) | `MintModule.sol:406, :510` (`delete ticketQueue[rk]` after full drain) | (self) | advanceGame stack |
| `processTicketBatch` self-writes (delete) | `MintModule.sol:674, :714` | (self) | advanceGame stack |

### Slot: `ticketsOwedPacked[rk][player]`

| Writer fn | Writer file:line | Callsite file:line | Reach path |
|-----------|------------------|--------------------|------------|
| `_queueTickets` | `Storage.sol:585` (`ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) \| uint40(rem)`) | Same callsites as `ticketQueue[rk]` writer above (every `_queueTickets` call writes both slots atomically). | Same |
| `_queueTicketsScaled` | `Storage.sol:636` (`ticketsOwedPacked[wk][buyer] = newPacked`) | `MintModule.sol:1129` | EOA → `purchase` / `purchaseCoin` |
| `_queueTicketRange` | `Storage.sol:671` (`ticketsOwedPacked[wk][buyer] = (uint40(owed) << 8) \| uint40(rem)`) | `DecimatorModule.sol:582`, `WhaleModule.sol:973`, `Storage.sol:1135` | EOA → `recordDecBurn`/`claimWhalePass` |
| `processFutureTicketBatch` self-writes | `MintModule.sol:433, :445, :455, :490` | (self) | advanceGame stack |
| `processTicketBatch` / `_processOneTicketEntry` / `_resolveZeroOwedRemainder` self-writes | `MintModule.sol:733, :740, :746, :814` | (self) | advanceGame stack |

**Note on `rngLockedFlag` gating in writers:** `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` all carry a `rngLockedFlag` gate at `Storage.sol:572`/`:604`/`:660` (`if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`). This gate fires ONLY when `targetLevel > level + 5` (the far-future branch) — for `targetLevel <= level + 5` (near-future + current-level), the write proceeds during the rng-window without revert. Callers from `JackpotModule._queueTickets` (the four jackpot-derived callsites `:703, :837, :1007, :2305`) pass `rngBypass=true` deliberately.

---

## CAT-04 (§D) — Verdict Matrix

Per-(slot × writer × callsite) classification. Tokens: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. Per `D-43N-AUDIT-ONLY-01` — NO SAFE_BY_DESIGN class. Per `D-298-EXEMPT-REACH-01` strict + per-callsite. Per `D-298-EXEMPT-CROSSCONTRACT-01` cross-contract EXEMPT preserved when callsite traces to EXEMPT stack.

| # | Slot | Writer fn | Callsite file:line | Reach analysis | Classification |
|---|------|-----------|--------------------|----------------|---------------|
| 1 | `lootboxRngPacked` (LR_INDEX) | `_finalizeRngRequest` LR_INDEX++ | `AdvanceModule.sol:1620` | EXEMPT-ADVANCEGAME (only reachable via `advanceGame` → `rngGate` → `_requestRng` → `_finalizeRngRequest`) | **EXEMPT-ADVANCEGAME** |
| 2 | `lootboxRngPacked` (LR_INDEX) | static initializer | `Storage.sol:1312` | constructor / static initializer (pre-deploy) | **EXEMPT-ADVANCEGAME** (constructor is structurally EXEMPT — runs once, before any VRF callback can fire) |
| 3 | `lootboxRngWordByIndex[i]` | `_finalizeLootboxRng` daily | `AdvanceModule.sol:1256` | EXEMPT-ADVANCEGAME (one-shot guard at `:1255`; reached only from `rngGate` inside `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 4 | `lootboxRngWordByIndex[i]` | `rawFulfillRandomWords` mid-day branch | `AdvanceModule.sol:1761` | EXEMPT-VRFCALLBACK (caller is Chainlink VRF coordinator; gate at `:1749` `msg.sender != address(vrfCoordinator) revert`); one-shot guard at `:1750` `if (… \|\| rngWordCurrent != 0) return` | **EXEMPT-VRFCALLBACK** |
| 5 | `lootboxRngWordByIndex[i]` | `_backfillOrphanedLootboxIndices` | `AdvanceModule.sol:1818` | EXEMPT-ADVANCEGAME (only reachable via `rngGate` → `_backfillOrphanedLootboxIndices` inside `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 6 | `ticketWriteSlot` | `_swapTicketSlot` via `_swapAndFreeze` | `AdvanceModule.sol:299` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 7 | `ticketWriteSlot` | `_swapTicketSlot` round-2 game-over drain | `AdvanceModule.sol:601` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 8 | `ticketWriteSlot` | `_swapTicketSlot` post-drain swap | `AdvanceModule.sol:1095` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 9 | `ticketLevel` | self-write inside `processFutureTicketBatch` | `MintModule.sol:395/:400/:408/:514/:519/:523` | EXEMPT-ADVANCEGAME (self-stack — only reachable via `_processFutureTicketBatch` delegatecall from advanceGame) | **EXEMPT-ADVANCEGAME** |
| 10 | `ticketLevel` | self-write inside `processTicketBatch` | `MintModule.sol:668/:676/:716` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 11 | `ticketLevel` | `advanceGame` FF-promotion | `AdvanceModule.sol:319` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 12 | `ticketCursor` | self-writes inside `processFutureTicketBatch` | `MintModule.sol:394/:401/:407/:507/:515/:518/:522` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 13 | `ticketCursor` | self-writes inside `processTicketBatch` | `MintModule.sol:669/:675/:711/:715` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 14 | `ticketCursor` | `advanceGame` FF-promotion reset | `AdvanceModule.sol:320` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 15 | `ticketQueue[rk]` | `_queueTickets` — constructor SDGNRS/VAULT init | `DegenerusGame.sol:226/:227` | constructor (pre-deploy) | **EXEMPT-ADVANCEGAME** (constructor) |
| 16 | `ticketQueue[rk]` | `_queueTickets` — phase-transition vault tickets | `AdvanceModule.sol:1535/:1541` | EXEMPT-ADVANCEGAME (inside `_processPhaseTransition` reached from `advanceGame`) | **EXEMPT-ADVANCEGAME** |
| 17 | `ticketQueue[rk]` | `_queueTickets` — `purchaseWhaleBundle` | `WhaleModule.sol:313` (reached via `DegenerusGame.purchaseWhaleBundle` external) | NOT in EXEMPT stack — EOA-initiated. `purchaseWhaleBundle` has `rngLockedFlag` gate at `WhaleModule.sol:543`? Verify: `grep -n "rngLockedFlag" WhaleModule.sol` shows `:543` is inside `purchaseDeityPass`, NOT `purchaseWhaleBundle`. `purchaseWhaleBundle` calls `_queueTickets(buyer, lvl, …, false)` so the `_queueTickets` internal gate at `Storage.sol:572` fires for `isFarFuture` writes only. Near-future + current-level writes PROCEED inside the window. | **VIOLATION** |
| 18 | `ticketQueue[rk]` | `_queueTickets` — `purchaseLazyPass` | `WhaleModule.sol:482` | Same as #17 — `_queueTickets` is called with `rngBypass=false`; far-future revert, near-future proceeds. No top-level rngLockedFlag gate found at `purchaseLazyPass` entry. | **VIOLATION** |
| 19 | `ticketQueue[rk]` | `_queueTickets` — `purchaseDeityPass` | `WhaleModule.sol:625` | `purchaseDeityPass` has `if (rngLockedFlag) revert RngLocked()` at `WhaleModule.sol:543` — full revert inside window. Per `D-298-EXEMPT-REACH-01` (stack-rooted strict): the writer is NOT call-stack-reachable from an EXEMPT root, classification remains VIOLATION; the gate is a correctness-proof artifact. | **VIOLATION** |
| 20 | `ticketQueue[rk]` | `_queueTickets` — `LootboxModule.openLootBox` resolution | `LootboxModule.sol:1067` | NOT in EXEMPT stack — EOA-initiated `openLootBox`. Lootbox VRF is domain-separated per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A, but the writer still races the daily-VRF MintModule consumer (cross-domain write). | **VIOLATION** |
| 21 | `ticketQueue[rk]` | `_queueTickets` — `LootboxModule.openBurnieLootBox` resolution | `LootboxModule.sol:1190` | Same as #20 — separate VRF domain, but the write target (`ticketQueue[rk]`) is shared. | **VIOLATION** |
| 22 | `ticketQueue[rk]` | `_queueTickets` — `JackpotModule` auto-rebuy/jackpot-flow | `JackpotModule.sol:703, :837, :1007, :2305` | EXEMPT-ADVANCEGAME (every JackpotModule.sol `_queueTickets` callsite is reached from `payDailyJackpot` / `payDailyJackpotCoinAndTickets` / terminal-jackpot path, all inside advanceGame). | **EXEMPT-ADVANCEGAME** |
| 23 | `ticketQueue[rk]` | `_queueTicketsScaled` — `MintModule._purchaseFor` | `MintModule.sol:1129` (reached via `DegenerusGame.purchase` / `purchaseCoin` external) | NOT in EXEMPT stack — EOA-initiated. `_purchaseFor` has NO blanket `rngLockedFlag` revert — only the `cachedJpFlag && rngLockedFlag` last-jackpot-day target-level redirect at `MintModule.sol:1221`. Writes to `ticketQueue[rk]` PROCEED during the resolution window. | **VIOLATION** |
| 24 | `ticketQueue[rk]` | `_queueTicketRange` — `DecimatorModule._awardDecimatorLootbox` | `DecimatorModule.sol:582` | NOT in EXEMPT stack — reached from `DegenerusCoin.burnCoin` → `recordDecBurn` external entry, OR from advanceGame's decimator-jackpot path (entry §13). For the EOA-initiated burn path: VIOLATION. For the advanceGame-stack decimator-jackpot path: EXEMPT-ADVANCEGAME. **Per-callsite split required; this single source-line is reached from both stacks.** Following `D-298-EXEMPT-REACH-01` (per-callsite): the EOA-reach is VIOLATION. | **VIOLATION** |
| 25 | `ticketQueue[rk]` | `_queueTicketRange` — `WhaleModule.claimWhalePass` | `WhaleModule.sol:973` (reached via `DegenerusGame.claimWhalePass` external) | NOT in EXEMPT stack — EOA-initiated. No top-level `rngLockedFlag` gate on `claimWhalePass`; downstream `_queueTicketRange` reverts atomically inside the loop when `isFarFuture && rngLockedFlag` for level+6..+100 portion — effective gate but stack-strict classification. | **VIOLATION** |
| 26 | `ticketQueue[rk]` | `_queueTicketRange` — `Storage._redeemWhalePassRange` (whale-pass redemption helper) | `Storage.sol:1135` | Reached from claim/redemption surface — same as #25. | **VIOLATION** |
| 27 | `ticketQueue[rk]` | self-`delete` inside `processFutureTicketBatch` | `MintModule.sol:406/:510` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 28 | `ticketQueue[rk]` | self-`delete` inside `processTicketBatch` | `MintModule.sol:674/:714` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 29 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — phase-transition vault tickets | `AdvanceModule.sol:1535/:1541` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 30 | `ticketsOwedPacked[rk][player]` | `_queueTickets` constructor | `DegenerusGame.sol:226/:227` | constructor (pre-deploy) | **EXEMPT-ADVANCEGAME** (constructor) |
| 31 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `purchaseWhaleBundle` | `WhaleModule.sol:313` | Same as #17 | **VIOLATION** |
| 32 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `purchaseLazyPass` | `WhaleModule.sol:482` | Same as #18 | **VIOLATION** |
| 33 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `purchaseDeityPass` | `WhaleModule.sol:625` | Same as #19 (gate present; stack-strict VIOLATION) | **VIOLATION** |
| 34 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `LootboxModule.openLootBox` | `LootboxModule.sol:1067` | Same as #20 | **VIOLATION** |
| 35 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — `LootboxModule.openBurnieLootBox` | `LootboxModule.sol:1190` | Same as #21 | **VIOLATION** |
| 36 | `ticketsOwedPacked[rk][player]` | `_queueTickets` — JackpotModule self-stack | `JackpotModule.sol:703, :837, :1007, :2305` | EXEMPT-ADVANCEGAME | **EXEMPT-ADVANCEGAME** |
| 37 | `ticketsOwedPacked[rk][player]` | `_queueTicketsScaled` — `MintModule._purchaseFor` | `MintModule.sol:1129` | Same as #23 | **VIOLATION** |
| 38 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` — `DecimatorModule._awardDecimatorLootbox` | `DecimatorModule.sol:582` | Same as #24 (EOA-reach) | **VIOLATION** |
| 39 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` — `WhaleModule.claimWhalePass` | `WhaleModule.sol:973` | Same as #25 | **VIOLATION** |
| 40 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` — `Storage._redeemWhalePassRange` | `Storage.sol:1135` | Same as #26 | **VIOLATION** |
| 41 | `ticketsOwedPacked[rk][player]` | self-writes inside `processFutureTicketBatch` | `MintModule.sol:433/:445/:455/:490` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |
| 42 | `ticketsOwedPacked[rk][player]` | self-writes inside `processTicketBatch`/`_processOneTicketEntry`/`_resolveZeroOwedRemainder` | `MintModule.sol:733/:740/:746/:814` | EXEMPT-ADVANCEGAME (self-stack) | **EXEMPT-ADVANCEGAME** |

> **All rows carry a concrete EXEMPT/VIOLATION token.** Every callsite × slot × writer tuple in §C carries one of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION` per `D-43N-AUDIT-ONLY-01` + `D-298-EXEMPT-REACH-01` strict. NO `SAFE_BY_DESIGN` classifications.

> **Row-class summary:** Rows classified `VIOLATION`: **17, 18, 19, 20, 21, 23, 24, 25, 26, 31, 32, 33, 34, 35, 37, 38, 39, 40** = **18 rows**. Rows classified `EXEMPT-ADVANCEGAME`: 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 22, 27, 28, 29, 30, 36, 41, 42 = **23 rows**. Rows classified `EXEMPT-VRFCALLBACK`: 4 = **1 row**. Rows classified `EXEMPT-RETRYLOOTBOXRNG`: **0 rows** (not in this consumer's reach set — domain-separated VRF). Total = **42 rows**.

> **Commitment-window analysis (per `feedback_rng_commitment_window.md`):** For `processFutureTicketBatch`, the `entropy` parameter is captured at `rngGate:290` inside `advanceGame` and threaded as-cached through the resolution loop — between `rngGate` return and `_raritySymbolBatch` execution, ANY external `_queueTickets` callsite that fires INSIDE the same advanceGame transaction is impossible (Solidity execution is sequential within a transaction). The race is BETWEEN advanceGame transactions: the external writer (e.g., a player calls `purchase` between two `advanceGame` calls) modifies `ticketQueue[rk]` + `ticketsOwedPacked[rk][player]` AFTER the prior `advanceGame` set `rngLockedFlag=true` AT `_requestRng`, and BEFORE the NEXT `advanceGame` that consumes the now-fulfilled VRF word reads them via `processTicketBatch`. The `_queueTickets` near-future gate is INSUFFICIENT to prevent this race because the writer is targeting near-future (level+1..+5) levels, which is the SAME range the consumer drains.

> **Double-buffer mitigation:** `_swapAndFreeze` at `:299` toggles `ticketWriteSlot` BEFORE the daily-RNG consumer fires — new writes during the rng-window land in the NEW write slot, while the consumer drains the OLD read slot. **This is a STRUCTURAL ANTI-RACE pattern but does NOT fully close the window for cross-call drains:** `processFutureTicketBatch` is called for far-future levels (level+6..+100 via `ffLevel`) which use `_tqFarFutureKey(lvl)` — a SEPARATE key space NOT double-buffered. The `rngLockedFlag` gate at `Storage.sol:572` for `isFarFuture` writes IS the far-future race closure. For near-future levels (level+1..+5) drained by `processFutureTicketBatch` at `:344-352` and current-level by `processTicketBatch`, the double-buffer carries the freshness invariant. **The VIOLATIONS above are non-far-future writes that land in the SAME (double-buffered) WRITE slot the next-day consumer will read** — so the double-buffer DOES protect the immediate VRF consumption but does NOT protect freshness ACROSS the lock window (because the writes accumulate in the write slot and will be drained on the NEXT VRF cycle, where they participate in NEXT day's keccak seed via the very mechanism this catalog enumerates).

---

## CAT-06 (§E) — Remediation Tactic per VIOLATION Row

Per `D-298-RECOMMEND-DEPTH-01`: one tactic ∈ `(a)` `rngLockedFlag`-gated revert | `(b)` snapshot/anchor pattern | `(c)` pre-lock reorder | `(d)` immutable. Plus ≤80-char rationale.

| # | Slot | Writer / Callsite | Tactic | Rationale (≤80 chars) |
|---|------|-------------------|--------|------------------------|
| 17 | `ticketQueue[rk]` | `_queueTickets` from `purchaseWhaleBundle` (`WhaleModule.sol:313`) | (a) | Add `if (rngLockedFlag) revert RngLocked()` at WhaleModule:purchaseWhaleBundle entry |
| 18 | `ticketQueue[rk]` | `_queueTickets` from `purchaseLazyPass` (`WhaleModule.sol:482`) | (a) | Add gated-revert at WhaleModule:purchaseLazyPass entry; mirrors purchaseDeityPass:543 |
| 19 | `ticketQueue[rk]` | `_queueTickets` from `purchaseDeityPass` (`WhaleModule.sol:625`) | (a) | Existing gate at :543 satisfies; verdict-matrix is stack-strict, gate verified |
| 20 | `ticketQueue[rk]` | `_queueTickets` from `openLootBox` (`LootboxModule.sol:1067`) | (a) | Gate lootbox-resolution writes via rngLockedFlag; daily-VRF freshness invariant |
| 21 | `ticketQueue[rk]` | `_queueTickets` from `openBurnieLootBox` (`LootboxModule.sol:1190`) | (a) | Same as #20 — domain-separated VRF but write-target shared |
| 23 | `ticketQueue[rk]` | `_queueTicketsScaled` from `_purchaseFor` (`MintModule.sol:1129`) | (a) | Gate purchase() against daily VRF window; level-target redirect at :1221 insufficient |
| 24 | `ticketQueue[rk]` | `_queueTicketRange` from `_awardDecimatorLootbox` (`DecimatorModule.sol:582`) | (a) | Gate EOA-reach (recordDecBurn); advanceGame-stack reach is EXEMPT (per-callsite) |
| 25 | `ticketQueue[rk]` | `_queueTicketRange` from `claimWhalePass` (`WhaleModule.sol:973`) | (a) | Add top-level rngLockedFlag gate; far-future loop revert is partial coverage |
| 26 | `ticketQueue[rk]` | `_queueTicketRange` from `_redeemWhalePassRange` (`Storage.sol:1135`) | (a) | Same as #25 — whale-pass redemption path |
| 31 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `purchaseWhaleBundle` | (a) | Same gate as #17; co-located write — single gate covers both slots |
| 32 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `purchaseLazyPass` | (a) | Same gate as #18 |
| 33 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `purchaseDeityPass` | (a) | Same as #19 — gate-by-revert at :543 already in place |
| 34 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `openLootBox` | (a) | Same gate as #20 |
| 35 | `ticketsOwedPacked[rk][player]` | `_queueTickets` from `openBurnieLootBox` | (a) | Same gate as #21 |
| 37 | `ticketsOwedPacked[rk][player]` | `_queueTicketsScaled` from `_purchaseFor` | (a) | Same gate as #23 |
| 38 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` from `_awardDecimatorLootbox` | (a) | Same gate as #24 (EOA-reach only) |
| 39 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` from `claimWhalePass` | (a) | Same gate as #25 |
| 40 | `ticketsOwedPacked[rk][player]` | `_queueTicketRange` from `_redeemWhalePassRange` | (a) | Same gate as #26 |

> **Tactic-frequency summary:** (a) gated-revert × 18; (b) snapshot/anchor × 0; (c) pre-lock reorder × 0; (d) immutable × 0.

> **Why tactic (a) dominates:** The MintModule consumer's freshness invariant rests on the `ticketQueue[rk]` + `ticketsOwedPacked[rk][player]` snapshot at the start of the resolution window. The double-buffer (`ticketWriteSlot` swap at `_swapAndFreeze:299`) partially protects the read slot, but cross-window race (writes accumulating in write slot, drained on NEXT cycle) is closed only by gated-revert on external writers. Tactic (b) snapshot/anchor would require copying the entire `ticketQueue[rk]` + `ticketsOwedPacked` state at lock-time — prohibitive storage cost given queue lengths can reach hundreds of entries. Tactic (c) pre-lock reorder is not applicable (no writes are scheduled by the consumer itself). Tactic (d) immutable is structurally impossible (the slots are mutable per-player counters). The existing `_queueTickets` near-future + far-future gates partially implement tactic (a) for `targetLevel > level + 5`; the remediation is to extend gating to ALL non-EXEMPT writers regardless of target-level range, OR to add top-level `if (rngLockedFlag) revert` gates at each external entry point (matching the `WhaleModule.purchaseDeityPass:543` pattern).

> **Cross-reference to Phase 290 MINTCLN audit-subject:** Phase 290 MINTCLN-02 collapse (3-input keccak + owed-in-baseKey) preserves CROSS-CALL seed separation INSIDE the resolution stack via the per-iteration `ticketsOwedPacked` SLOAD freshness — Phase 290 design-intent trace section (ii) confirms `baseKey` low 32 bits shrink as `owed` decreases. **The Phase 290 invariant is INSIDE-WINDOW determinism; the Phase 298 catalog identifies CROSS-WINDOW writer races on the SAME slots. Both invariants must hold for the full freshness property: Phase 290 closes intra-call, Phase 298 §10 violations identify inter-call/inter-day writers that erode the snapshot.**

> **Phase 290 `_processOneTicketEntry` zero-owed→rolled-to-1 stale-low-32-baseKey acknowledgment:** Recorded in Phase 290 design-intent trace section (ii) as ACCEPTABLE under structural-closure reasoning (single-trait emission only; no multi-call drain follows; upper-bit + groupIdx distinctness preserved). This catalog does NOT contradict that disposition — the stale-low-32 is INSIDE the self-stack (EXEMPT-ADVANCEGAME) and bounded to a single emission. The VIOLATIONS in §D are CROSS-stack writes that change `ticketsOwedPacked[rk][player]` outside the consumer's self-stack — a different bug class.

---

**§10 catalog complete.** 7 participating slots enumerated. 42 verdict rows. 18 VIOLATION rows, all dispositioned tactic (a) `rngLockedFlag`-gated revert. NO `SAFE_BY_DESIGN` classifications.
