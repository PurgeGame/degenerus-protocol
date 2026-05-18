# §5 — GameOverModule rngWordByDay substitution (file:line 100)

**Consumer entry:** `contracts/modules/DegenerusGameGameOverModule.sol:100` (`rngWord = rngWordByDay[day];`)
**Containing function:** `handleGameOverDrain(uint32 day) external` at `:79`.
**Access guard:** None on the module function itself (delegatecall-only target). Reachability gated by `DegenerusGame.sol` dispatcher which only allows the GAME proxy address; the externally reachable path is `AdvanceModule._handleGameOverPath` → `ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(handleGameOverDrain.selector, day)` at `AdvanceModule.sol:624-628`.
**Caller chain:** EOA / contract → `DegenerusGame.advanceGame` (external) → AdvanceModule delegatecall → `_handleGameOverPath` (`AdvanceModule.sol:522`) → `_gameOverEntropy` writes `rngWordByDay[day]` (`AdvanceModule.sol:1271`/`:1841`) → multi-tx ticket drain (`STAGE_TICKETS_WORKING` early returns at `:596`/`:615`) eventually reaches → `delegatecall handleGameOverDrain(day)` (`AdvanceModule.sol:624-628`) → `_unlockRng(day)` (`AdvanceModule.sol:631`).

**VRF word source — the substitution point.** The SLOAD at `:100` is itself a re-read of a value that was written upstream by `_applyDailyRng` (`AdvanceModule.sol:1841`: `rngWordByDay[day] = finalWord;`) OR by `_getHistoricalRngFallback` (`AdvanceModule.sol:1356`, called from `_gameOverEntropy` at `:1304` then re-fed through `_applyDailyRng` at `:1305`). Both writers run BEFORE `handleGameOverDrain` is delegatecall-invoked (the same `_handleGameOverPath` invocation that wrote it then calls the consumer). For the lifetime of this consumer's body (lines 79..184), `rngWordByDay[day]` is **immutable** — there is no path in any external/public function under `contracts/` that writes `rngWordByDay[d]` for the same `d` after `_applyDailyRng` runs (single-shot writer; grep on `rngWordByDay[\w*] *=` returns only `_applyDailyRng:1841`, `_backfillGapDays:1793`, and the gap-day branch never targets the current `day` — see §D-A attestation).

**Downstream-call cross-references (NOT re-enumerated here):**
- Line 168: `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord)` → covered by §4 (`298-04-CATALOG-section.md`). §5 does NOT re-enumerate the SLOADs reached inside `runTerminalDecimatorJackpot`.
- Line 182: `IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord)` → covered by §3 (`298-03-CATALOG-section.md`). §5 does NOT re-enumerate the SLOADs reached inside `runTerminalJackpot`.
- Line 144: `dgnrs.burnAtGameOver()` and line 143: `charityGameOver.burnAtGameOver()` — analyzed in §A as cross-contract calls whose internals are reached but do NOT consume `rngWord`. SLOADs inside those callees are enumerated where they participate in any VRF-influenced output reachable from `handleGameOverDrain` (none of `burnAtGameOver` consumes the word).

**EXEMPT-stack roots in scope for this consumer:**
- **EXEMPT-ADVANCEGAME** — the only externally reachable entry that invokes `handleGameOverDrain` is `AdvanceModule._handleGameOverPath` from `advanceGame()`. Grep verification: `grep -rn "handleGameOverDrain" contracts/ --include="*.sol"` shows exactly two non-comment hits — the function declaration (`GameOverModule.sol:79`), the interface (`IDegenerusGameModules.sol:53`), and the single delegatecall site (`AdvanceModule.sol:624-628`). The delegatecall is `private`, only called from `_handleGameOverPath` (line `:526`), which is `private`, only called from `advanceGame` at `:185`.
- EXEMPT-VRFCALLBACK is not directly in scope — `rawFulfillRandomWords` writes only `rngWordCurrent` / `lootboxRngWordByIndex`, never invokes `handleGameOverDrain`.
- EXEMPT-RETRYLOOTBOXRNG is not in scope (lootbox-only resolve flow).

**Pre-call state latches relevant to commitment-window analysis (per `feedback_rng_commitment_window.md`):**
1. `rngLockedFlag` is TRUE when `_handleGameOverPath` is mid-resolution (set by `_requestRng` at `AdvanceModule.sol:1634`); cleared at `_unlockRng` (`:1731`) which fires AFTER `handleGameOverDrain` returns (`AdvanceModule.sol:631`). Therefore for the entire body of `handleGameOverDrain`, `rngLockedFlag == true`.
2. `dailyIdx` is the PRIOR day's index. `_unlockRng` writes `dailyIdx = day` at `:1730` AFTER `handleGameOverDrain` returns. Inside the consumer body, `dailyIdx` < `day` (lags by ≥1).
3. `level` may have been pre-incremented at `_requestRng:1643` (when `isTicketJackpotDay && !isRetry`). The cached local `lvl` at `:82` is whatever the slot currently holds.
4. `gameOver` is FALSE at entry (the `gameOver` branch in `_handleGameOverPath` at `:539` short-circuits to `handleFinalSweep` before reaching `handleGameOverDrain` if `gameOver` is already true). Line 139 inside `handleGameOverDrain` is the unique writer (`gameOver = true`).
5. `_goRead(GO_JACKPOT_PAID_SHIFT, …)` at `:80` is an idempotency guard — `handleGameOverDrain` early-returns if the GO_JACKPOT_PAID bit was already set by a prior invocation in the same `advanceGame` resolution stack.

---

## CAT-01 (§A) — Traced Function Set

Every internal/external function reached from the `handleGameOverDrain` body, with explicit file:line citation per `feedback_verify_call_graph_against_source.md`. The function body spans lines 79..184. Downstream §3 / §4 functions are listed as cross-call leaves only (their internal SLOAD enumeration lives in the linked sibling catalog sections).

| # | Function | File:line | Reached via | Notes |
|---|----------|-----------|-------------|-------|
| 1 | `handleGameOverDrain(uint32 day)` | `DegenerusGameGameOverModule.sol:79` | ENTRY (delegatecall from `_handleGameOverPath`) | consumer root; body spans :79-:184 |
| 2 | `_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK)` | `DegenerusGameStorage.sol:885` | 1 → :80 | reads `gameOverStatePacked` |
| 3 | `_goRead(GO_TIME_SHIFT, …)` — N/A for `handleGameOverDrain` (only used in `handleFinalSweep`) | — | — | not reached from §5 entry |
| 4 | (implicit) `address(this).balance` | EVM opcode | 1 → :84 | EVM-native `BALANCE` opcode; reads contract ETH balance — NOT an SLOAD, but enumerated as a balance read for `feedback_rng_window_storage_read_freshness.md` completeness |
| 5 | `IStETH(STETH_TOKEN).balanceOf(address(this))` | external Lido stETH | 1 → :84 | external view; reads stETH ledger on Lido contract. Lido is `no source available under contracts/`, classified as trace-stop per `D-298-TRACE-DEPTH-01`. |
| 6 | `IStakedDegenerusStonk(SDGNRS).pendingRedemptionEthValue()` | `StakedDegenerusStonk.sol:224` | 1 → :92 + 1 → :155 | view function reads `pendingRedemptionEthValue` storage on sDGNRS contract (source-available; under `contracts/`) |
| 7 | `charityGameOver.burnAtGameOver()` | `GNRUS.sol` (under `contracts/`) | 1 → :143 | external function on GNRUS contract; trace into its body required per `D-298-TRACE-DEPTH-01` |
| 8 | `dgnrs.burnAtGameOver()` | resolves at runtime to the `IGNRUSGameOver` interface bound to `ContractAddresses.GNRUS` via `dgnrs` storage var (DegenerusGameStorage) | 1 → :144 | `dgnrs` is a storage-cached interface ref; one SLOAD on `dgnrs` slot, then external call. See §B. |
| 9 | `_goWrite(GO_TIME_SHIFT, …, uint48(block.timestamp))` | `DegenerusGameStorage.sol:890` | 1 → :140 | reads-modify-writes `gameOverStatePacked` |
| 10 | `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)` | `DegenerusGameStorage.sol:890` | 1 → :146 | reads-modify-writes `gameOverStatePacked` |
| 11 | `_setNextPrizePool(0)` | `DegenerusGameStorage.sol:791` | 1 → :147 | reads `prizePoolsPacked` via `_getPrizePools()` (`:792`), writes back via `_setPrizePools` |
| 12 | `_setFuturePrizePool(0)` | `DegenerusGameStorage.sol:803` | 1 → :148 | reads `prizePoolsPacked` via `_getPrizePools()`, writes back via `_setPrizePools` |
| 13 | `_setCurrentPrizePool(0)` | `DegenerusGameStorage.sol:821` | 1 → :149 | writes `currentPrizePool` (NO SLOAD — direct assignment) |
| 14 | `_getPrizePools()` | `DegenerusGameStorage.sol:688` | 11 → :792; 12 → :804 | reads `prizePoolsPacked` (one SLOAD per `_set*PrizePool` call, total 2 inside this consumer) |
| 15 | `_setPrizePools(next, future)` | `DegenerusGameStorage.sol:684` | 11/12 (indirect) | writes `prizePoolsPacked` |
| 16 | `IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord)` | `DegenerusGame.sol:1142` | 1 → :168 | external self-call → delegatecall into `DecimatorModule.runTerminalDecimatorJackpot` (`:755`). **Trace stops at this boundary in §5**; covered by §4. |
| 17 | `IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord)` | `DegenerusGame.sol:1180` | 1 → :182 | external self-call → delegatecall into `JackpotModule.runTerminalJackpot` (`:278`). **Trace stops at this boundary in §5**; covered by §3. |
| 18 | `GNRUS.burnAtGameOver()` body (callee) | `contracts/GNRUS.sol` | 7 → external call | Source under `contracts/`. Inspected for SLOADs that flow into VRF-influenced output: none. The function only burns unallocated GNRUS supply held by the game contract; outputs are an `_burn` SSTORE on GNRUS plus an event. NO SLOAD inside `GNRUS.burnAtGameOver` feeds into `rngWord` or any VRF-influenced output (the function doesn't read `rngWord`, and the values it does read — `balanceOf(address(this))` on its own ledger — are independent of any VRF output). |

**Explicit-enumeration discipline** per `feedback_verify_call_graph_against_source.md`: `handleGameOverDrain` body fits in ~110 LoC (lines 79-184). Confirmed by direct file:line read above: 2 `_goRead`/`_goWrite` calls; 2 external view calls (stETH balance, sdgnrs.pendingRedemptionEthValue); 2 `_set*PrizePool` calls (with implicit `_getPrizePools` SLOADs); 2 external write calls (`charityGameOver.burnAtGameOver` / `dgnrs.burnAtGameOver`); 2 `IDegenerusGame` self-calls (lines 168, 182). No internal helper invocations other than the storage-helper accessors enumerated above. No inline assembly (confirmed by `grep -n "assembly" contracts/modules/DegenerusGameGameOverModule.sol` — zero hits).

---

## CAT-02 (§B) — SLOAD Table

Every SLOAD reached during `handleGameOverDrain` execution (excluding the SLOADs already enumerated under §3 / §4 for the downstream `runTerminalJackpot` / `runTerminalDecimatorJackpot` paths — those rows belong to those consumers' catalog sections). Per `feedback_rng_window_storage_read_freshness.md` discipline, ALL SLOADs are listed including non-participating ones with explicit attestation.

| # | Slot (logical) | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|----------------|-----------------------|--------------|----------------|-------------------|
| B-1 | `gameOverStatePacked` (GO_JACKPOT_PAID field) | `DegenerusGameGameOverModule.sol:80` (via `_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK)`) | Idempotency guard: `if (... != 0) return;` short-circuits the entire function | NO | Field is written ONLY by `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)` at `:146` of this same function. Default zero, set once. Guard outcome controls reach (taken = early return, no VRF-influenced output produced); when not taken the value is 0 and contributes no entropy. No external entry mutates this bit. |
| B-2 | `level` | `DegenerusGameGameOverModule.sol:82` (`uint24 lvl = level;`) | Local `lvl` is used at `:107` to gate deity-pass refund branch (`if (lvl < 10)`), at `:168` as arg to `runTerminalDecimatorJackpot(…, lvl, rngWord)`, and at `:182` as `lvl + 1` arg to `runTerminalJackpot(…, lvl + 1, rngWord)`. | **YES** | — (Drives the target-level argument for both downstream consumers' bucket / trait-ticket SLOAD selection in §3 + §4. Also gates the deity-pass refund loop entry per `lvl < 10`.) |
| B-3 | `claimablePool` (uint128 in slot 1) | `DegenerusGameGameOverModule.sol:91` (`uint256 reserved = uint256(claimablePool) + …`); read again at `:154` (`uint256 postRefundReserved = uint256(claimablePool) + …`) | Influences `preRefundAvailable` (line 93) and `available` (line 156). `preRefundAvailable` gates the RNG-required branch at `:99` (`if (preRefundAvailable != 0) … rngWord = rngWordByDay[day]`) AND caps the deity-refund budget at `:110` (`uint256 budget = preRefundAvailable;`). `available` (read at `:156`) bounds the funds passed to `runTerminalDecimatorJackpot` at `:168` (`decPool = remaining / 10`) and `runTerminalJackpot` at `:182` (`remaining`). | **YES** | — (Drives `preRefundAvailable`, which (i) gates whether the RNG word is read at all, and (ii) caps every downstream payout magnitude. Lower `claimablePool` ⇒ larger `available` ⇒ larger `decPool` and `remaining`, which scale every winning payout amount in §3/§4. While the SELECTION of winners inside §3/§4 is independent of `available`, the AMOUNTS paid to winners are linear in `available`, so this SLOAD directly influences the VRF-derived ETH-output magnitude.) |
| B-4 | `pendingRedemptionEthValue` (on sDGNRS contract, slot 224 of `StakedDegenerusStonk.sol`) | `DegenerusGameGameOverModule.sol:92` + `:155` (via `IStakedDegenerusStonk.pendingRedemptionEthValue()` external view) | Reduces `reserved` / `postRefundReserved` → directly impacts `preRefundAvailable` / `available`. Same flow as B-3. | **YES** | — (Cross-contract SLOAD: sDGNRS contract is source-available under `contracts/StakedDegenerusStonk.sol` so per `D-298-TRACE-DEPTH-01` it is in scope. Influences both the RNG-gate at :99 and every downstream payout magnitude.) |
| B-5 | `deityPassOwners.length` | `DegenerusGameGameOverModule.sol:109` (`uint256 ownerCount = deityPassOwners.length;`) | Loop bound; iterates `for (uint256 i; i < ownerCount; ...)`. | **YES** | — (Directly drives the deity-pass refund loop iteration count → drives the per-owner refund credits at `:122` → drives `totalRefunded` → drives `claimablePool += uint128(totalRefunded)` at `:134` → drives `postRefundReserved` at `:154` → drives `available` → drives downstream payout amounts. Adding more owners between `_applyDailyRng` and `handleGameOverDrain` shifts refund vs. terminal-jackpot allocation.) |
| B-6 | `deityPassOwners[i]` (per-index slot) | `DegenerusGameGameOverModule.sol:113` (`address owner = deityPassOwners[i];`) | Selected address becomes the refund recipient at `:122` (`claimableWinnings[owner] += refund;`). | **YES** | — (Determines WHICH addresses receive the deity-pass refund credit. While the AMOUNT each receives is independent of VRF, the recipient list IS the per-index storage slot, and the order matters because the budget is FIFO-consumed at `:118-127`: when `refund > budget` is clamped to `budget` and `budget == 0` breaks the loop. So earlier indexes get full refunds, later indexes get partial or zero. Insertion order is determined by `_purchaseDeityPass`'s `deityPassOwners.push(buyer)` at `WhaleModule:596`.) |
| B-7 | `deityPassPurchasedCount[owner]` | `DegenerusGameGameOverModule.sol:114` (`uint16 purchasedCount = deityPassPurchasedCount[owner];`) | Multiplied by `refundPerPass` at `:116` to compute `refund` for each owner. | **YES** | — (Linearly scales each owner's refund credit. Sums into `totalRefunded` → `claimablePool` → `postRefundReserved` → `available` → terminal-jackpot magnitudes in §3/§4.) |
| B-8 | `claimableWinnings[owner]` (RMW for `+=`) | `DegenerusGameGameOverModule.sol:122` (`claimableWinnings[owner] += refund;`) | Read-modify-write. The prior value of `claimableWinnings[owner]` is loaded, summed with `refund`, written back. | NO | The prior `claimableWinnings[owner]` value is NOT consumed in any subsequent branch, comparison, or hash inside `handleGameOverDrain` — it only flows into the SSTORE at the same line. No flow into VRF-influenced output. (Same NON-PARTICIPATING attestation pattern as §3 entry #11.) |
| B-9 | `claimablePool` (RMW for `+=` at `:134`) | `DegenerusGameGameOverModule.sol:134` (`claimablePool += uint128(totalRefunded);`) | Read-modify-write. | NO | Prior value loaded for the `+=` summation; the new value is read again at `:154` (counted as B-3's second read). The RMW itself does not consume the prior value for any branch / comparison / VRF-derived computation. Pure accumulator update. (Note: the SECOND read at `:154` IS participating — see B-3. The RMW SLOAD here is distinct from that subsequent fresh read.) |
| B-10 | `gameOverStatePacked` (RMW for `_goWrite` at `:140`) | `DegenerusGameStorage.sol:890` (via `_goWrite(GO_TIME_SHIFT, …, uint48(block.timestamp))`) | RMW; prior value loaded to preserve other fields in the packed slot. | NO | The prior packed slot value is loaded only to preserve non-targeted bits during the bit-mask write. Not consumed in any branch / VRF computation. |
| B-11 | `gameOverStatePacked` (RMW for `_goWrite` at `:146`) | `DegenerusGameStorage.sol:890` (via `_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)`) | RMW; same as B-10. | NO | Same attestation as B-10 — prior value loaded only to preserve other packed bits. Not VRF-influencing. |
| B-12 | `prizePoolsPacked` (read inside `_setNextPrizePool(0)` at `:147`) | `DegenerusGameStorage.sol:792` (via `_getPrizePools()` called from `_setNextPrizePool`) | Reads packed `(next, future)`, then writes back `(0, future)` via `_setPrizePools(uint128(val), future)`. | NO | Read only to preserve the `future` half during the `next = 0` write. Value is not consumed by any subsequent branch, comparison, or hash. Pure storage-layout preservation read. |
| B-13 | `prizePoolsPacked` (read inside `_setFuturePrizePool(0)` at `:148`) | `DegenerusGameStorage.sol:804` (via `_getPrizePools()` called from `_setFuturePrizePool`) | Reads packed `(next, future)`, then writes back `(next, 0)`. Note that `next` was just set to 0 at the previous line via B-12 — so this SLOAD observes `(0, future)`. | NO | Same attestation as B-12 — pure storage-layout preservation read. |
| B-14 | `currentPrizePool` (NO read — direct assignment at `:149`) | NOT REACHED (write-only) | `_setCurrentPrizePool(0)` is `currentPrizePool = uint128(0);` direct assignment, no SLOAD. | n/a | Direct SSTORE, no read. Recorded here for completeness. |
| B-15 | `yieldAccumulator` (NO read — direct assignment at `:150`) | NOT REACHED (write-only) | `yieldAccumulator = 0;` direct assignment, no SLOAD. | n/a | Direct SSTORE. |
| B-16 | `dgnrs` (storage-cached `IStakedDegenerusStonk` interface ref) | `DegenerusGameGameOverModule.sol:144` (`dgnrs.burnAtGameOver()`) | SLOAD on the `dgnrs` storage slot to resolve the call target address. | NO | Read returns the immutable bound interface address (set in `DegenerusGameStorage`'s constructor / initializer; not mutable from external entries). Value is the call target; influences which contract receives the `burnAtGameOver` call, but the called function (`GNRUS.burnAtGameOver`) does NOT consume `rngWord` and does NOT write any slot participating in §5's downstream resolution. No flow into VRF-influenced output. |
| B-17 | `address(this).balance` (EVM `BALANCE` opcode) | `:84` + `:212` (the `:212` read is inside `handleFinalSweep`, NOT inside `handleGameOverDrain`; ignored for §5) | Reads ETH balance held by the game contract. | **YES** | — (Although not an SLOAD on the contract's storage, `feedback_rng_window_storage_read_freshness.md` discipline scopes "every storage read consumed alongside RNG" — `balance` is an EVM-native state read that flows into `totalFunds` → `reserved` → `preRefundAvailable` → `available` → downstream payouts. While not addressable via a writer-enumeration in the conventional SLOAD sense, the entry is included for catalog completeness; writer enumeration in §C treats it as a "balance writer" — anyone who can move ETH into / out of the game contract during the window. **Classified as participating** because it directly drives `available` and therefore downstream payout magnitudes.) |
| B-18 | external `stETH.balanceOf(address(this))` | `:84` + `:213` (the `:213` read is inside `handleFinalSweep`; ignored for §5) | Reads game's stETH balance on Lido. | **YES** | — (Same flow as B-17 — drives `totalFunds`. Lido is no-source-under-`contracts/` — trace stop for the SLOAD-inside-balanceOf — but the value-read IS consumed by `handleGameOverDrain` and directly drives `available`. Treated as participating; writer enumeration in §C scopes "anyone who can move stETH balance".) |

**Auxiliary §B-W — SSTOREs inside the consumer body (cross-check, not classified):**

| # | Slot | Write-site (file:line) | Notes |
|---|------|------------------------|-------|
| B-W1 | `claimableWinnings[owner]` | `:122` (`+= refund`) | RMW, post-RNG-read; participating output (recipient identities are read from `deityPassOwners[i]`, participating; amounts depend on `deityPassPurchasedCount[owner]`, participating). |
| B-W2 | `claimablePool` | `:134`, `:171` (`+= uint128(decSpend)`) | RMW post-RNG-read. The `:171` write uses `decSpend = decPool - decRefund` where `decRefund` is the return value from `runTerminalDecimatorJackpot` (§4 covers internals). |
| B-W3 | `gameOver` | `:139` (`= true`) | Single sentinel write. Read by other modules' guards (e.g., MintModule's purchase paths via `_livenessTriggered()` which doesn't read `gameOver` — instead `gameOver` is read directly by `StakedDegenerusStonk` external guards and by `_addClaimableEth` at `JackpotModule.sol:792`). |
| B-W4 | `gameOverStatePacked` (GO_TIME field) | `:140` (`_goWrite(GO_TIME_SHIFT, …, uint48(block.timestamp))`) | RMW. |
| B-W5 | `gameOverStatePacked` (GO_JACKPOT_PAID field) | `:146` (`_goWrite(GO_JACKPOT_PAID_SHIFT, …, 1)`) | RMW. |
| B-W6 | `prizePoolsPacked` (`next` half) | `:147` via `_setNextPrizePool(0)` → `_setPrizePools(0, future)` | RMW. |
| B-W7 | `prizePoolsPacked` (`future` half) | `:148` via `_setFuturePrizePool(0)` → `_setPrizePools(0, 0)` | RMW. |
| B-W8 | `currentPrizePool` | `:149` (`= uint128(0)`) | Direct SSTORE. |
| B-W9 | `yieldAccumulator` | `:150` (`= 0`) | Direct SSTORE. |

**Attestation discipline (per `feedback_rng_window_storage_read_freshness.md`):** ALL SLOADs reachable from `handleGameOverDrain`'s body (lines 79-184) enumerated above — including the RMW SLOADs that exist solely for SSTORE preservation (B-9, B-10, B-11, B-12, B-13) and which are flagged NON-PARTICIPATING. Non-VRF reads that flow into the RNG gate or into payout magnitudes (B-3, B-4, B-5, B-6, B-7, B-17, B-18) are flagged YES with the explicit downstream-influence trace. Inline-assembly raw-`sstore` / `slot:` directives: `grep -n "assembly\|slot:" contracts/modules/DegenerusGameGameOverModule.sol` returns zero hits.

---

## CAT-03 (§C) — Per-Participating-Slot Writer Enumeration

For each `Participating? = YES` row in §B, enumerate every external/public function (in any contract under `contracts/`) that writes the slot, with callsite file:line and the reaching external entry-point chain.

### §C.B-2 — `level` writers

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B2-1 | `_requestRng` writes `level = lvl` | `DegenerusGameAdvanceModule.sol:1643` | `advanceGame` (`AdvanceModule.sol:158`) | Sole writer of `level`. Reached only from `advanceGame` (sole caller of `_requestRng` via `rngGate` / `_handleGameOverPath`'s entropy fetch). |

**Grep verification:** `grep -rn "^\s*level\s*=" contracts/ --include="*.sol"` returns 1 hit on storage (`DegenerusGameAdvanceModule.sol:1643`); the storage declaration at `DegenerusGameStorage.sol:250` (`uint24 public level = 0;`) is a default-initializer (not a runtime writer). The `level` references in `WhaleModule.sol:196`, `WhaleModule.sol:339`, `WhaleModule.sol:640`, `DecimatorModule.sol:919`, `GameOverModule.sol:82`, `GameOverModule.sol:107` are READS; the local variable `level` in `GNRUS.sol:583` is a memory variable shadowing (not storage write).

### §C.B-3 — `claimablePool` writers

Every external/public function reaching a writer of `claimablePool` (uint128 at slot 1, declared `DegenerusGameStorage.sol:354`). Grep: `grep -rn "claimablePool\s*[+\-=]" contracts/ --include="*.sol"` returns the writer set below.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B3-1 | `_creditClaimable` writes `claimablePool += weiAmount` (via `PayoutUtils._creditClaimable` and inline `+= remainder` patterns) | `DegenerusGamePayoutUtils.sol:101` (`claimablePool += uint128(remainder);` inside `_creditClaimable`'s remainder-flow) | Multiple paths: any caller of `_creditClaimable`. Includes `_addClaimableEth` (`JackpotModule.sol:780` — reached from `advanceGame` via `payDailyJackpot` / `runTerminalJackpot` / `runTerminalDecimatorJackpot`); `_creditClaimable` is private but used from internal jackpot flows. | All callsites currently traced back to `advanceGame` resolution stack (EXEMPT-ADVANCEGAME). |
| C-B3-2 | `DecimatorModule._awardDecimatorLootbox` writes `claimablePool -= uint128(lootboxPortion)` | `DegenerusGameDecimatorModule.sol:388` | Reached from decimator-lootbox auto-resolve flow (`resolveRedemptionLootbox` / `_resolveLootboxCommon` — see §6, §7). | These callsites are reached from `advanceGame` (auto-resolve at end of day in `_processLootboxBatch` chain) OR from `requestLootboxRng` (manual user-triggered resolve). The non-`advanceGame` path is the VRF callback (`fulfillRandomWords` writes `lootboxRngWordByIndex` then user calls `resolveLootbox*` — reached from EOA). |
| C-B3-3 | `MintModule._resolveMintShortfall` writes `claimablePool -= uint128(shortfall)` | `DegenerusGameMintModule.sol:949` | Reached from `mintBatch` (EOA-callable purchase entry on `DegenerusGame.sol`). | Mint-time shortfall handling. Reached from EOA `mint*` entry points — NOT EXEMPT. |
| C-B3-4 | `AdvanceModule._processStethYield` writes `claimablePool += uint128(claimableDelta)` | `DegenerusGameAdvanceModule.sol:905` | Reached from `advanceGame` (top-level entry). | EXEMPT-ADVANCEGAME. |
| C-B3-5 | `DegeneretteModule._creditCheckedFromClaimable` writes `claimablePool -= uint128(fromClaimable)` | `DegenerusGameDegeneretteModule.sol:547` | Reached from `playDegenerette` (EOA-callable on `DegenerusGame.sol`). | NOT EXEMPT (player-triggered). |
| C-B3-6 | `DegeneretteModule._resolveLootboxDirect` writes `claimablePool += uint128(weiAmount)` | `DegenerusGameDegeneretteModule.sol:1131` | Reached from VRF callback path (`fulfillRandomWords` → `_resolveLootboxDirect`). | Some callsites are EXEMPT-VRFCALLBACK; others reachable from user-trigger `playDegenerette` / `claimDegeneretteWinnings`. Per-callsite classification required. |
| C-B3-7 | `JackpotModule._addClaimableEth` writes `claimablePool += uint128(claimableDelta)` | `DegenerusGameJackpotModule.sol:763` | Reached from jackpot resolution flows in `advanceGame` (EXEMPT-ADVANCEGAME). | All current callsites are inside `_processDailyEth` / `_payNormalBucket` reached only from `payDailyJackpot` / `runTerminalJackpot` / `runTerminalDecimatorJackpot`'s downstream — i.e., from `advanceGame`. |
| C-B3-8 | `JackpotModule._processDailyEth` writes `claimablePool += uint128(liabilityDelta)` | `DegenerusGameJackpotModule.sol:1335` | Reached from `advanceGame` (same chain as C-B3-7). | EXEMPT-ADVANCEGAME. |
| C-B3-9 | `GameOverModule.handleGameOverDrain` writes `claimablePool += uint128(totalRefunded)` | `DegenerusGameGameOverModule.sol:134` | Reached from `advanceGame` → `_handleGameOverPath` → `handleGameOverDrain`. | EXEMPT-ADVANCEGAME — same stack as the consumer itself. |
| C-B3-10 | `GameOverModule.handleGameOverDrain` writes `claimablePool += uint128(decSpend)` | `DegenerusGameGameOverModule.sol:171` | Reached from `advanceGame` (same as C-B3-9). | EXEMPT-ADVANCEGAME. |
| C-B3-11 | `GameOverModule.handleFinalSweep` writes `claimablePool = 0` | `DegenerusGameGameOverModule.sol:207` | Reached from `advanceGame` (via `_handleGameOverPath` post-`gameOver` short-circuit at `:541`). | EXEMPT-ADVANCEGAME, but ONLY runs after `gameOver == true` AND `block.timestamp >= gameOverTime + 30 days` — long after this consumer (§5) has run. Not a write-during-window concern. |
| C-B3-12 | `DegenerusGame.claimWinnings` writes `claimablePool -= uint128(payout)` | `DegenerusGame.sol:1408` | EOA-callable external function. | NOT EXEMPT (player-triggered). |
| C-B3-13 | `DegenerusGame.useClaimableForMint` / equivalent writes `claimablePool -= uint128(claimableUsed)` | `DegenerusGame.sol:946` | EOA-callable via `mintBatch` family. | NOT EXEMPT. |
| C-B3-14 | `DegenerusGame.sweepSdgnrsClaim` writes `claimablePool -= uint128(amount)` | `DegenerusGame.sol:1739` | External call from sDGNRS (`StakedDegenerusStonk` contract). | sDGNRS contract is source-under-`contracts/`. The sDGNRS function chain: any external entry on sDGNRS that calls back into the game's `sweepSdgnrsClaim`. Reachable from sDGNRS's `claimRedemption` (EOA-callable). NOT EXEMPT. |

**Admin/owner writer check for `claimablePool`:** `grep -n "onlyOwner\|onlyAdmin\|require(msg.sender == owner\|msg.sender == ContractAddresses\.ADMIN" contracts/*/Game*.sol contracts/Degenerus*.sol` reveals admin-gated functions but no direct `claimablePool` writer behind an admin guard.

**Inline-assembly raw `sstore` check:** zero hits in the relevant modules.

### §C.B-4 — `pendingRedemptionEthValue` writers (on sDGNRS contract)

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B4-1 | `StakedDegenerusStonk.beginRedemption` writes `pendingRedemptionEthValue += ethValueOwed` | `StakedDegenerusStonk.sol:789` | EOA-callable (player initiates a gambling burn). | NOT EXEMPT — player-triggered. Player can ADD `pendingRedemptionEthValue` between RNG publication and `handleGameOverDrain` execution. |
| C-B4-2 | `StakedDegenerusStonk.resolveRedemptionPeriod` writes `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` | `StakedDegenerusStonk.sol:593` | Called by the game via `IStakedDegenerusStonk.resolveRedemptionPeriod` (`AdvanceModule.sol:1230`/`:1293`/`:1323`). Game-only on sDGNRS side (gated by `onlyGame`). | EXEMPT-ADVANCEGAME — runs inside `_gameOverEntropy` BEFORE `handleGameOverDrain` is reached. |
| C-B4-3 | `StakedDegenerusStonk.claimRedemption` writes `pendingRedemptionEthValue -= totalRolledEth` | `StakedDegenerusStonk.sol:657` | EOA-callable. | NOT EXEMPT — player-triggered. |

### §C.B-5 / §C.B-6 / §C.B-7 — `deityPassOwners.length`, `deityPassOwners[i]`, `deityPassPurchasedCount` writers

These three slots share the same writer: `_purchaseDeityPass` (`DegenerusGameWhaleModule.sol:542`), which writes `deityPassPurchasedCount[buyer] += 1` (`:595`) and `deityPassOwners.push(buyer)` (`:596`) — appending to the array also writes the new `.length`.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B5-1 | `WhaleModule._purchaseDeityPass` writes `deityPassPurchasedCount[buyer] += 1` and `deityPassOwners.push(buyer)` | `DegenerusGameWhaleModule.sol:595`, `:596` | `WhaleModule.purchaseDeityPass(address buyer, uint8 symbolId)` is `external payable` at `:538`. EOA-callable. Reached via `DegenerusGame.sol`'s dispatcher (selector forwarder). | NOT EXEMPT — player-triggered purchase. **HOWEVER**, `_purchaseDeityPass` has two in-function gates that block the post-RNG window: (1) `if (rngLockedFlag) revert RngLocked();` at `:543`, AND (2) `if (_livenessTriggered()) revert E();` at `:544`. Both gates are evaluated at TX time. |

**Inherited writers (OpenZeppelin / interface):** The mapping `deityPassPurchasedCount` is declared `internal mapping(address => uint16)` at `DegenerusGameStorage.sol:963` — not an OZ-inherited slot. `deityPassOwners` is `address[] internal` at `:969` — not OZ-inherited. No `transferFrom` / `approve` / `_mint` / `_burn` writes either slot.

**Admin/owner writer check:** Zero hits.

**Constructor/initializer writer check:** Mapping / dynamic array default empty; no constructor writes.

**Inline-assembly raw `sstore` / `slot:` check:** Zero hits.

### §C.B-17 — `address(this).balance` "writers" (anyone moving ETH in/out)

Balance changes are not SSTOREs; they are EVM-native value transfers. Any external entry that sends ETH to the game contract or causes the game to send ETH outward is a "writer" of the balance state for the purposes of this catalog.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B17-1 | `DegenerusGame.receive()` accepts ETH transfers | (implicit Solidity receive) | Any EOA / contract sending ETH to the game. | NOT EXEMPT — anyone with the game address can `send(eth)` and inflate `address(this).balance`. |
| C-B17-2 | Every `payable` function (purchase / whale / deity / lootbox / coinflip) inflates balance | e.g., `DegenerusGame.mintBatch` / `purchaseWhaleBundle` (`:599`) / `purchaseDeityPass` / `purchaseLazyPass` / coinflip-burn callbacks | EOA-callable purchase paths. | NOT EXEMPT. Each gated by `_livenessTriggered() || rngLockedFlag` revert (per `WhaleModule:195/385/544/958` and `MintModule:877/906/1215/1381`). |
| C-B17-3 | `claimWinnings` deflates balance (`payable(to).call{value: …}`) | `DegenerusGame.sol:1408` (+ stETH transfers in `_sendStethFirst`) | EOA-callable. | NOT EXEMPT. |
| C-B17-4 | sDGNRS / vault / GNRUS withdrawals | various | Cross-contract callbacks. | NOT EXEMPT in general. |
| C-B17-5 | `_stakeEth` / Lido stETH conversion | `AdvanceModule.sol:1560` neighborhood | Reached from `advanceGame`. | EXEMPT-ADVANCEGAME for those callsites that originate inside `advanceGame`. |
| C-B17-6 | `_handleGameOverPath` itself (writes balance via deity refunds, terminal payouts) | Inside `handleGameOverDrain` (`:122` credits, downstream `runTerminalJackpot` payouts) | Reached from `advanceGame`. | EXEMPT-ADVANCEGAME — same stack. |

### §C.B-18 — `stETH.balanceOf(address(this))` "writers"

stETH balance on Lido is mutated by Lido's internal accrual + by stETH transfers in/out.

| # | Writer chain | Callsite (file:line) | Reaching external entry-point | Notes |
|---|--------------|----------------------|-------------------------------|-------|
| C-B18-1 | Lido rebase (1× daily) | Lido — no source under `contracts/` | n/a | Trace stop per `D-298-TRACE-DEPTH-01`. Rebase is autonomous; not a writer reachable from a `contracts/` entry. NOT classified. |
| C-B18-2 | `steth.transfer(to, amount)` outgoing (game→someone) | `DegenerusGameGameOverModule.sol:243`, `:247` (inside `_sendStethFirst`) | Reached only from `handleFinalSweep` (`:194`) — runs ≥ 30 days after `handleGameOverDrain`. Out of window. | EXEMPT-ADVANCEGAME for the call site, but TEMPORALLY DISJOINT from §5's window. Not a same-window writer. |
| C-B18-3 | `AdvanceModule._stakeEth` (game → Lido via wrap) | `DegenerusGameAdvanceModule.sol:1555..` (neighborhood) | Reached from `advanceGame` (EXEMPT-ADVANCEGAME). | Same EXEMPT stack as §5 itself. |
| C-B18-4 | Lido contract receives `transfer` from the game (e.g., `claimWinnings` paying out stETH via `_sendStethFirst` analog elsewhere) | distinct path | (game-internal). | Wherever the game transfers OUT stETH, balance falls; treated alongside C-B17-3. |
| C-B18-5 | EXTERNAL parties transferring stETH INTO the game | Lido (no source under `contracts/`) | Any external party via `IStETH.transfer(game, amount)`. | NOT EXEMPT — anyone can grief by sending stETH to the game address, inflating B-18 between `_applyDailyRng` and `handleGameOverDrain`. |

---

## CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. **NO `SAFE_BY_DESIGN`** per milestone-goal prohibition.

### §D-A — Pre-flight attestation: `rngWordByDay[day]` itself is not mutated post-write

Before classifying participating-slot writers, attest that the substituted RNG word at line `:100` is itself immutable across the consumer's window:

| Writer of `rngWordByDay[d]` | File:line | Reaching entry | Same-day? | Notes |
|---|---|---|---|---|
| `_applyDailyRng` writes `rngWordByDay[day] = finalWord` | `DegenerusGameAdvanceModule.sol:1841` | `advanceGame` → `rngGate` / `_gameOverEntropy` | YES (single-shot per `day`) | Idempotent guard at `:1187` / `:1271` (`if (rngWordByDay[day] != 0) return …`) prevents overwrite. |
| `_backfillGapDays` writes `rngWordByDay[gapDay] = derivedWord` | `DegenerusGameAdvanceModule.sol:1793` | `advanceGame` → `rngGate` → backfill branch | NO (targets `gapDay` in `[idx + 1, day)`, exclusive of current day) | Backfill only fires for PRIOR days that had no VRF word; never targets `day` itself. |

⇒ `rngWordByDay[day]` is monotonically pinned once written. No external entry under `contracts/` can mutate it. The substituted RNG word is immutable across `handleGameOverDrain`'s body. **The participation analysis below is therefore restricted to the OTHER participating SLOADs (B-2 through B-18).**

### §D-B — Verdict matrix

Per `D-298-EXEMPT-REACH-01`: rows keyed on `(slot, writer-function, callsite-file-line)`.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|------|-----------------|----------------------|---------------------------|----------------|
| D-1 | `level` | `AdvanceModule._requestRng` | `DegenerusGameAdvanceModule.sol:1643` | YES — `_requestRng` only reachable from `advanceGame` (`rngGate` / `_gameOverEntropy`). | **EXEMPT-ADVANCEGAME** |
| D-2 | `claimablePool` | `PayoutUtils._creditClaimable` (`+= uint128(remainder)`) | `DegenerusGamePayoutUtils.sol:101` | YES — reached only from `_addClaimableEth` (jackpot resolution) inside `advanceGame` resolution stack. | **EXEMPT-ADVANCEGAME** |
| D-3 | `claimablePool` | `DecimatorModule._awardDecimatorLootbox` (`-= uint128(lootboxPortion)`) | `DegenerusGameDecimatorModule.sol:388` | NO — auto-resolve lootbox path is reachable from EOA via `requestLootboxRng` / `resolveLootbox*` flows. See §6, §7 for the lootbox consumer chain. | **VIOLATION** |
| D-4 | `claimablePool` | `MintModule._resolveMintShortfall` (`-= uint128(shortfall)`) | `DegenerusGameMintModule.sol:949` | NO — reached from EOA `mintBatch` family. Gated by `_livenessTriggered()` (`MintModule:1215` and similar) which would revert during the multi-tx gameover window (because `_livenessTriggered()` is TRUE once the death-clock fires). **Gate behavior:** during the multi-tx game-over drain, `_livenessTriggered()` is true; `mintBatch` reverts; `_resolveMintShortfall` unreachable. | **EXEMPT-ADVANCEGAME** (by gate; see rationale below — gate is a sufficient structural block, equivalent to direct-EXEMPT classification for this consumer) |
| D-5 | `claimablePool` | `AdvanceModule._processStethYield` (`+= uint128(claimableDelta)`) | `DegenerusGameAdvanceModule.sol:905` | YES — reached only from `advanceGame`. | **EXEMPT-ADVANCEGAME** |
| D-6 | `claimablePool` | `DegeneretteModule._creditCheckedFromClaimable` (`-= uint128(fromClaimable)`) | `DegenerusGameDegeneretteModule.sol:547` | NO — reached from EOA `playDegenerette`. Need to check window gates. `playDegenerette` is gated by `_livenessTriggered()` revert (mirror of MintModule gates). | **EXEMPT-ADVANCEGAME** (by gate, same rationale as D-4) |
| D-7 | `claimablePool` | `DegeneretteModule._resolveLootboxDirect` (`+= uint128(weiAmount)`) | `DegenerusGameDegeneretteModule.sol:1131` | Partial: some callsites reach via VRF callback (EXEMPT-VRFCALLBACK), others via EOA. The lootbox-direct resolve runs after VRF fulfillment delivers a word; the EOA path triggers the resolve. Per `D-298-EXEMPT-CROSSCONTRACT-01`, the per-callsite classification is required. | **EXEMPT-VRFCALLBACK** (when reached via `fulfillRandomWords` → `_resolveLootboxDirect`); **VIOLATION** (when reached via EOA-initiated resolve outside the EXEMPT stacks). See §6/§8 catalog sections for the lootbox/degenerette consumer-stack analysis. For §5's purposes: the same writer-callsite at `:1131` could fire in the EOA branch during the multi-tx game-over window. Classified as VIOLATION here per the conservative discipline. |
| D-8 | `claimablePool` | `JackpotModule._addClaimableEth` (`+= uint128(claimableDelta)`) | `DegenerusGameJackpotModule.sol:763` | YES — reached only from `payDailyJackpot` / `runTerminalJackpot` / `runTerminalDecimatorJackpot` (all inside `advanceGame`). | **EXEMPT-ADVANCEGAME** |
| D-9 | `claimablePool` | `JackpotModule._processDailyEth` (`+= uint128(liabilityDelta)`) | `DegenerusGameJackpotModule.sol:1335` | YES — same stack as D-8. | **EXEMPT-ADVANCEGAME** |
| D-10 | `claimablePool` | `GameOverModule.handleGameOverDrain` (`+= uint128(totalRefunded)`) | `DegenerusGameGameOverModule.sol:134` | YES — same stack as the consumer itself (`advanceGame` → `_handleGameOverPath` → `handleGameOverDrain`). | **EXEMPT-ADVANCEGAME** |
| D-11 | `claimablePool` | `GameOverModule.handleGameOverDrain` (`+= uint128(decSpend)`) | `DegenerusGameGameOverModule.sol:171` | YES — same as D-10. | **EXEMPT-ADVANCEGAME** |
| D-12 | `claimablePool` | `GameOverModule.handleFinalSweep` (`= 0`) | `DegenerusGameGameOverModule.sol:207` | YES — reachable only from `advanceGame` post-`gameOver=true` and ≥30 days later. Temporally disjoint from §5. | **EXEMPT-ADVANCEGAME** |
| D-13 | `claimablePool` | `DegenerusGame.claimWinnings` (`-= uint128(payout)`) | `DegenerusGame.sol:1408` | NO — EOA-callable. Need to check window gates. `claimWinnings` is reachable during the multi-tx game-over drain because it has NO `_livenessTriggered()` / `rngLockedFlag` gate (it's a withdraw path; players are intended to be able to claim throughout the resolution). Confirmed by reading `DegenerusGame.sol` `claimWinnings` body: no liveness gate on the withdrawal of already-credited winnings. | **VIOLATION** |
| D-14 | `claimablePool` | `DegenerusGame.useClaimableForMint` (`-= uint128(claimableUsed)`) | `DegenerusGame.sol:946` | NO — EOA-callable. Gated by `_livenessTriggered()` revert (mint family). | **EXEMPT-ADVANCEGAME** (by gate) |
| D-15 | `claimablePool` | `DegenerusGame.sweepSdgnrsClaim` (`-= uint128(amount)`) | `DegenerusGame.sol:1739` | NO — reached from sDGNRS `claimRedemption` (EOA-callable). | **VIOLATION** |
| D-16 | `pendingRedemptionEthValue` | `StakedDegenerusStonk.beginRedemption` (`+= ethValueOwed`) | `StakedDegenerusStonk.sol:789` | NO — EOA-callable on sDGNRS. Per sDGNRS source review: `beginRedemption` is callable during the multi-tx drain window if not gated by the game's `livenessTriggered()` view. `StakedDegenerusStonk.sol:507` shows `if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();` — `beginRedemption` IS gated by `livenessTriggered() && !gameOver()`. Inside the game-over drain window: `livenessTriggered() == true` AND `gameOver() == false` (until line 139). So `beginRedemption` IS blocked. | **EXEMPT-ADVANCEGAME** (by gate — `BurnsBlockedDuringLiveness` revert blocks the writer during the consumer's resolution window) |
| D-17 | `pendingRedemptionEthValue` | `StakedDegenerusStonk.resolveRedemptionPeriod` (`= … - … + …`) | `StakedDegenerusStonk.sol:593` | YES — reached from `_gameOverEntropy` / `rngGate` inside `advanceGame`. Runs BEFORE `handleGameOverDrain` (at `:1230` / `:1293` / `:1323` — during `_gameOverEntropy`). Temporally upstream of the consumer's first read at `:92`. | **EXEMPT-ADVANCEGAME** |
| D-18 | `pendingRedemptionEthValue` | `StakedDegenerusStonk.claimRedemption` (`-= totalRolledEth`) | `StakedDegenerusStonk.sol:657` | NO — EOA-callable. Per source review (`StakedDegenerusStonk.sol:491` neighborhood): `claimRedemption` has its own gating. Reading the file: `claimRedemption` is gated by `if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();` at `:491`. During the multi-tx drain window, `livenessTriggered() == true` ⇒ `claimRedemption` reverts ⇒ writer blocked. | **EXEMPT-ADVANCEGAME** (by gate) |
| D-19 | `deityPassOwners.length` + `deityPassOwners[i]` + `deityPassPurchasedCount[buyer]` | `WhaleModule._purchaseDeityPass` (writes all three at `:595`, `:596`) | `DegenerusGameWhaleModule.sol:595-596` | NO — EOA-callable via `purchaseDeityPass`. Gated by TWO checks inside `_purchaseDeityPass`: `if (rngLockedFlag) revert RngLocked();` (`:543`) AND `if (_livenessTriggered()) revert E();` (`:544`). Inside the multi-tx game-over drain window: `rngLockedFlag == true` AND `_livenessTriggered() == true`. EITHER gate is sufficient. The writer is blocked. | **EXEMPT-ADVANCEGAME** (by gate — pre-existing structural protection) |
| D-20 | `address(this).balance` (ETH balance) | `receive() payable` fallback | `DegenerusGame.sol` (implicit Solidity receive) | NO — anyone can transfer ETH to the game address at any time, including during the multi-tx drain. No gate. The balance read at `:84` would include any griefer-deposited ETH. | **VIOLATION** |
| D-21 | `address(this).balance` (ETH balance) | every `payable` purchase function | various | NO — `mintBatch`, `purchaseWhaleBundle`, `purchaseDeityPass`, `purchaseLazyPass`, coinflip-burn (`MintModule:877/906/1215/1381`, `WhaleModule:195/385/544/958`). All gated by `_livenessTriggered() && rngLockedFlag` revert. Inside the multi-tx drain window: both gates trip ⇒ purchase reverts ⇒ balance unchanged via this entry. | **EXEMPT-ADVANCEGAME** (by gate) |
| D-22 | `address(this).balance` (ETH balance) | `claimWinnings` outflow (`call{value:…}`) | `DegenerusGame.sol:1408` neighborhood | NO — EOA-callable, NOT gated by `_livenessTriggered()` / `rngLockedFlag`. Players can withdraw mid-window. The withdraw deflates `address(this).balance` and therefore deflates `totalFunds` / `available` in `handleGameOverDrain`. | **VIOLATION** |
| D-23 | `address(this).balance` (ETH balance) | `sweepSdgnrsClaim` outflow | `DegenerusGame.sol:1739` neighborhood | NO — reached from sDGNRS `claimRedemption` (which has its OWN liveness gate per D-18). The game-side `sweepSdgnrsClaim` itself does not gate. However, the sDGNRS caller is blocked during liveness, so this writer is transitively gated. | **EXEMPT-ADVANCEGAME** (by gate at sDGNRS callsite) |
| D-24 | `address(this).balance` (ETH balance) | `_stakeEth` / stETH conversion outflow | `DegenerusGameAdvanceModule.sol:1555..` | YES — reached from `advanceGame`. | **EXEMPT-ADVANCEGAME** |
| D-25 | `address(this).balance` (ETH balance) | `handleGameOverDrain` itself (deity-refund credits at `:122` do not move ETH; they only credit `claimableWinnings`. Terminal jackpot payouts at `:168/:182` via `runTerminalDecimatorJackpot`/`runTerminalJackpot` similarly credit `claimableWinnings` rather than transferring ETH out — confirmed by reading `_addClaimableEth` body) | inside the consumer | YES — same consumer. | **EXEMPT-ADVANCEGAME** (writes occur AFTER the participating SLOAD at :84 / :91 already read the balance; the post-read `:154` re-read picks up the post-refund accounting via `claimablePool` adjustment but the ETH balance itself is unchanged by deity refunds — only the `claimablePool` accumulator changes). |
| D-26 | `stETH balanceOf(game)` | Lido rebase (autonomous) | n/a — Lido, no source under `contracts/` | n/a | Trace-stop per `D-298-TRACE-DEPTH-01`. Not classified. |
| D-27 | `stETH balanceOf(game)` | external party transfers IN via `IStETH.transfer(game, …)` | Lido (no source under `contracts/`) | NO — anyone can `IStETH.transfer(game, amount)` at any time. No game-side gate prevents inbound stETH. Mirror of D-20. | **VIOLATION** |
| D-28 | `stETH balanceOf(game)` | `_sendStethFirst` outflow inside `handleFinalSweep` | `DegenerusGameGameOverModule.sol:243`, `:247` | YES — same EXEMPT-ADVANCEGAME stack. But temporally disjoint (handleFinalSweep runs ≥30 days after the §5 window). Not a within-window writer. | **EXEMPT-ADVANCEGAME** |
| D-29 | `stETH balanceOf(game)` | `_stakeEth` / Lido wrap (inbound stETH from staking) | `DegenerusGameAdvanceModule.sol:1555..` | YES — reached from `advanceGame`. | **EXEMPT-ADVANCEGAME** |

**§D-B summary by participation class:**
- **VIOLATION:** D-3 (`claimablePool` via `_awardDecimatorLootbox`), D-7 (`claimablePool` via `_resolveLootboxDirect` EOA branch), D-13 (`claimablePool` via `claimWinnings`), D-15 (`claimablePool` via `sweepSdgnrsClaim`), D-20 (`address(this).balance` via `receive`), D-22 (`address(this).balance` via `claimWinnings`), D-27 (`stETH balance` via inbound external transfer).
- **EXEMPT-ADVANCEGAME:** D-1, D-2, D-4, D-5, D-6, D-8, D-9, D-10, D-11, D-12, D-14, D-16, D-17, D-18, D-19, D-21, D-23, D-24, D-25, D-28, D-29.
- **EXEMPT-VRFCALLBACK:** none (the VRF callback writes only `rngWordCurrent` / `lootboxRngWordByIndex`, which are not in this consumer's participating-slot set).
- **EXEMPT-RETRYLOOTBOXRNG:** none.

**Total participating-slot tuples classified:** 29. **VIOLATIONs:** 7.

**Note on `level` (B-2) and `deityPass*` (B-5/B-6/B-7):** these slots are EXEMPT for THIS consumer's window because the only writers are either (a) inside `advanceGame` itself (`level` via `_requestRng`) or (b) blocked by `rngLockedFlag` / `_livenessTriggered()` gates during the drain window (`deityPass*` via `_purchaseDeityPass`). This is identical to the structural protection precedent for Phase 287 JPSURF's analogous gating.

---

## CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Recommended tactic | Rationale (≤80 chars) |
|---|-----------|--------------------|-----------------------|
| E-1 | D-3: `_awardDecimatorLootbox` decrements `claimablePool` from EOA-reach during drain | **(a)** | Gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window |
| E-2 | D-7: `_resolveLootboxDirect` `+=` `claimablePool` from EOA branch during drain | **(a)** | Gate the EOA-reached `_resolveLootboxDirect` callsite on `!_livenessTriggered()` |
| E-3 | D-13: `claimWinnings` `-=` `claimablePool` mid-drain shrinks `available` | **(a)** | Gate `claimWinnings` on `!_livenessTriggered() \|\| gameOver` so drain math is stable |
| E-4 | D-15: `sweepSdgnrsClaim` `-=` `claimablePool` mid-drain shrinks `available` | **(a)** | Gate `sweepSdgnrsClaim` on `!_livenessTriggered() \|\| gameOver` to mirror E-3 |
| E-5 | D-20: arbitrary EOA can inflate `address(this).balance` via `receive()` | **(b)** | Snapshot `totalFunds` at `_gameOverEntropy` time; consume snapshot in drain |
| E-6 | D-22: `claimWinnings` outflow deflates `address(this).balance` mid-drain | **(a)** | Same gate as E-3 — single revert closes both `claimablePool` and balance writers |
| E-7 | D-27: external stETH transfer IN inflates `stETH.balanceOf(game)` mid-drain | **(b)** | Same snapshot as E-5 — covers both ETH balance + stETH balance inputs |

**Rationale expansion (out-of-table for traceability; the ≤80-char cells above are the verdict-matrix entries):**

E-1 / E-2 (decimator-lootbox + degenerette-lootbox direct paths): the lootbox auto-resolve / direct-resolve flows can fire from EOA between `_applyDailyRng` and `handleGameOverDrain`. Tactic (a) is the structurally minimal fix — add a `_livenessTriggered()` revert in the EOA-reached entry points (mirroring Phase 290 MINTCLN's `rngLockedFlag` pattern at `DegenerusGameMintModule.sol:1221`). Tactic (b) snapshot is rejected because lootbox flows are independent surfaces with their own RNG word resolution; their `claimablePool` writes happen on their own resolution-window axis, not the daily axis. Tactic (c) reorder is not applicable. Tactic (d) immutable is rejected (these are aggregates).

E-3 / E-4 / E-6 (`claimWinnings` + `sweepSdgnrsClaim`): these are player-withdraw paths that lack a liveness gate. During the multi-tx game-over drain (which can span many TXs because `STAGE_TICKETS_WORKING` early-returns chain), a player can call `claimWinnings` between TX A (where `rngWordByDay[day]` is written) and TX N (where `handleGameOverDrain` runs). This shrinks `address(this).balance` AND `claimablePool`, both of which feed `available` and downstream payout magnitudes. Tactic (a) gated revert: add `if (_livenessTriggered() && !gameOver) revert E();` to `claimWinnings` and `sweepSdgnrsClaim`. Once `gameOver == true` (after `handleGameOverDrain:139`), `claimWinnings` re-opens for the post-gameover claim period.

E-5 / E-7 (external balance griefing): anyone can send ETH or stETH to the game address mid-window. Tactic (b) snapshot is the structurally correct fix because there's no way to BLOCK external balance writes (ETH `receive()` is mandatory for the contract's purchase paths, stETH inbound transfers cannot be rejected by Lido's ERC20 transfer semantics). The snapshot would be taken at `_gameOverEntropy` time (the canonical RNG-commitment moment) and stored alongside `rngWordByDay[day]` (e.g., a new packed `totalFundsAtRngByDay[day]` mapping or a dedicated single-slot snapshot variable for the terminal path). Tactic (a) gated revert is rejected because the entry point that "writes" the balance is the EVM transfer opcode itself, not a function under the game's control. Tactic (d) immutable is rejected (balance is inherently mutable). Tactic (c) reorder is rejected for the same reason as (a).

**Why each rationale is single-tactic per `D-298-RECOMMEND-DEPTH-01`:** Per the lock, no ranked-menu A>B>C>D; the recommendation column emits exactly one tactic per VIOLATION; design-intent backward-cite happens at Phase 299 FIX sub-phase planning per `feedback_design_intent_before_deletion.md`. Phase 298 is the catalog; Phase 299 is the design-intent + remediation choice.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside `handleGameOverDrain`'s body (lines 79-184) enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`.
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point for `rngWordByDay[day]` is the SSTORE at `AdvanceModule.sol:1841` (`_applyDailyRng`); the upstream gating analysis (`_handleGameOverPath` writes `rngWordByDay[day]` BEFORE delegatecalling `handleGameOverDrain`) confirms the substitution at `:100` reads a value that is monotonically pinned for the duration of the consumer's body. Player-controllable state mutability between that SSTORE and the consumer's SLOAD at `:100` (and the auxiliary participating SLOADs at `:84`, `:91`, `:92`, `:109`, `:113`, `:114`, `:154`, `:155`) is the gating analysis recorded in §D.
- **§5-scope boundary discipline:** Per `D-298-TRACE-DEPTH-01`, the trace follows the call graph across `contracts/`. Lines 168 and 182 delegate to §3 (`runTerminalJackpot`) and §4 (`runTerminalDecimatorJackpot`) — their internal SLOAD enumeration lives in those sibling catalog sections, NOT re-duplicated here. §5 captures (i) the upstream-write attestation in §D-A, (ii) the SLOADs INSIDE the `handleGameOverDrain` body in §B, and (iii) the writer enumeration + verdict for those §B slots in §C and §D.
- **Verdicts:** 18 SLOAD rows / 8 participating (B-2, B-3, B-4, B-5, B-6, B-7, B-17, B-18) / 29 writer-callsite tuples classified in §D-B / **7 VIOLATIONs** / 21 EXEMPT-ADVANCEGAME / 0 EXEMPT-VRFCALLBACK / 0 EXEMPT-RETRYLOOTBOXRNG / 0 SAFE_BY_DESIGN (prohibited per milestone goal). 1 trace-stop (Lido — no source under `contracts/`).
- **Scope:** zero `contracts/` + zero `test/` modifications per D-43N-AUDIT-ONLY-01.
