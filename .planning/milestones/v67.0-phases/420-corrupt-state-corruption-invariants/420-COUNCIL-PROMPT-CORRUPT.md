# Adversarial State-Corruption Review — Degenerus Protocol spinal column (v67.0 phase 420 CORRUPT)

You are an independent senior smart-contract auditor reviewing **state-corruption invariants** on a real-money on-chain ETH game. Read-only. The audit subject is the **frozen `contracts/` working tree in this repo at commit `0bb7deca` / contracts-tree `4a67209a`** (the tree is clean — read the files directly under `contracts/` and cite `file:line`). Assume **honest admin/governance** (key-compromise / malicious-owner out of scope).

## The structure under test

`DegenerusGame.sol` (the HUB) dispatches to 13 modules in `contracts/modules/*` via **`delegatecall`** — every module executes IN THE GAME'S STORAGE CONTEXT (shared base `contracts/storage/DegenerusGameStorage.sol`). So a module's storage writes land in the GAME's slots. Many Game-storage slots are **packed** (multiple logical fields in one 256-bit word) and **multi-module** (several modules RMW the same word via `BitPackingLib` shifts/masks). A dropped mask, a mis-keyed packed write, an out-of-order write at an external-call boundary, a non-atomic partial failure, or a reentrant re-entry that observes a half-updated word can silently corrupt the Game's accounting or its packed state.

Phase 419 already proved delegatecall *layout alignment* and *dispatch integrity* (modules write the slot/offset they intend; no hijackable dispatch). **This phase (420) assumes that and goes one level deeper: given correct routing, can any reachable column path leave packed storage or accounting in a corrupted state?**

## CLAIMS (find any reachable counterexample)

### CORRUPT-01 — Packed-slot integrity (the DEC-ALIAS class)
Every packed storage write — terminal/offset-keyed level writes, packed day-result lanes, packed pool/credit slots — writes ONLY its intended field and never aliases or overflows into a neighbouring field, under ANY reachable (level, day, offset, player) combination.

Priority packed/multi-module slots (slot → fields → writers):
- **slot 0** — `level`(uint24 @off12) + ~13 advance flags + 4 module-owned bools (`presaleOver` Mint, `presaleDrained` Lootbox, `ticketRedemptionOpen` Mint+Advance, `gameOver` GameOver-only). Cross-module RMW of one word: does any module's flag write clobber `level` or another module's flag?
- **slot 1** — `currentPrizePool`(uint128 low) | `claimablePool`(uint128 high). Both halves written within single Advance/Jackpot/GameOver calls. Verify a raw-slot or half write preserves the other half.
- **slot 5** — `totalFlipReversals`(uint64 low) | `lastVrfProcessedTimestamp`(uint48 @off8). HUB `reverseFlip` does a masked RMW of `totalFlipReversals`; the VRF-stall clock `lastVrfProcessedTimestamp` (read by `livenessTriggered()`) co-resides. A dropped mask in `reverseFlip` corrupts stall detection → liveness.
- **slot 7** — `balancesPacked[addr]` = `claimable`(low128) | `afking`(high128). 8+ module writers. The solvency invariant rides on consistent half-writes (see CORRUPT-05).
- **slot 9** — `mintPacked_[addr]` multi-field packed (LEVEL_COUNT / CURSE / streak / day / deity bit). 5 modules write co-resident fields. Field isolation is load-bearing for the cached-score read.
- **slot 34** — `lootboxRngPacked` = LR_INDEX | LR_PENDING_ETH | LR_THRESHOLD | LR_PENDING_FLIP | LR_MID_DAY. 5–6 modules field-mask RMW.
- **slot 40** — `lootboxEvCapPacked[player]` = two 88-bit windows {used64 + level24}. **buy-side keys `level+1`; open-side keys `currentLevel`** — both alias the same two-window slot across Mint/Lootbox/Afking/Whale. Verify the two windows can never collide or let one leg's write be read as the other's.
- **slot 44** — `decBucketOffsetPacked[lvl]` (4 bits/denom). **DEC-ALIAS PAIR**: the regular decimator keys `[lvl]` (`runDecimatorJackpot`), the terminal keys `[lvl+1]` (`runTerminalDecimatorJackpot`) — the `+1` is the deliberate isolation introduced by a prior fix. **Verify terminal `[lvl+1]` can never collide with a FUTURE regular round's `[lvl+1]` write** (i.e. no regular round can resolve at `lvl+1` after the gameover that triggers the terminal).
- **slot 51** — `boonPacked[player]` {slot0, slot1}, field-shift masked clears by Boon/Lootbox/Mint/Whale. Multi-module field isolation.
- **slots 2 / 11** — `prizePoolsPacked` / `prizePoolPendingPacked` = `next`(128) | `future`(128). `_setFuturePrizePool` RMWs only `next`; 7–8 modules write these.
- **slot 13** — `ticketsOwedPacked[wk][buyer]` = `owed`(<<8) | `rem`(8), key=(level-derived `wk`, buyer). 6 modules. Verify the `wk` key-derivation cannot alias two distinct levels onto one slot.
- **slot 26** — `levelDgnrsPacked[lvl]` = `alloc`(128) | `claimed`(128). Advance writes `alloc`; Small writes `claimed` — different halves of the same keyed slot.
- **slot 54** — `_subOf[player]` Sub struct: 13 fields packed in ONE word. The **marker sub-slot** (`lastAutoBoughtDay` / `lastOpenedDay` / `afkCoveredThroughDay` / `afkingStartDay`, all uint24) is written by THREE legs (`subscribe`, `_deliverAfkingBuy`, `_openAfkingBox`) keyed by processDay/stampDay; the **accumulator sub-slot** (`affiliateBase` / `pendingFlip` / `subStreakLatch`) is cross-written by `_deliverAfkingBuy` and independently zeroed by `drainAffiliateBase` / `_settlePendingFlip`. Prime aliasing/ordering target.

### CORRUPT-02 — Write-after-write ordering (no exploitable intermediate)
Across the multi-step advance/mint chain, the phase / level / day / pool / queue-index counters are mutually consistent at every external-call boundary, and no inconsistent intermediate is observable+exploitable by a reentrant or follow-on call. Specific ordering hotspots:
- Mint `mintPacked_` 4-helper sequence within one purchase (`_recordMintData` BEFORE `_recordMintStreakForLevel` / `_clearCurse` / `_recordLootboxMintDay`) — ordering is load-bearing for the cached-score read later in the same purchase.
- Degenerette pool read-once-flush-once vs box-ETH-spin flush-BEFORE-recirc.
- The advance state-machine counters (`level`, `dailyIdx`, `ticketCursor`/`ticketLevel`, `jackpotCounter`, phase flags) across `_finalizeRngRequest` / `_endPhase` / `_consolidate` / ticket-batch processors — is any external/synchronous call made while two counters disagree in a way an attacker can act on?

### CORRUPT-03 — Partial-failure atomicity (all-or-nothing where required)
If any sub-step of a column transaction reverts, no earlier sub-step's state write survives in a way that corrupts the accounting. CEI / checked-math / revert-bubbling must enforce all-or-nothing where required. Note the ONE deliberately-swallowed path (`_handleGameOverPath`) — confirm a swallowed sub-failure there cannot commit partial accounting that a later step assumes succeeded.

### CORRUPT-04 — Reentrancy mid-advance (no half-updated invariant observed / no double-count)
Every synchronous external-call site in the column — into FLIP / Coinflip / Vault / sDGNRS / Affiliate, plus every ETH transfer — is checked for a reentrant re-entry that observes a half-updated invariant or double-counts. Specific sites:
- `claimWinnings` runs payout (CEI) THEN a `maybeCurse` delegatecall — confirm `maybeCurse` has no revert/reentrant side effect that corrupts the just-settled balance.
- `subscribe` → `AFFILIATE.claim` reentrant callback.
- The yield-surplus / stETH-fallback path: re-confirm `_payoutWithStethFallback` leaves NO in-flight stETH that a reentrant `advanceGame`→yield-surplus accounting counts as backing (this is the CEI-ordering class a prior council flagged HIGH and was fixed — verify the fix holds on the current tree).
- Any `transfer`/`call{value:}` to a player-controlled address before the corresponding ledger debit/credit is finalized.

### CORRUPT-05 — Solvency / pool identities preserved across every column path
The two accounting identities hold after every mint / advance / jackpot / redemption / gameover path in the column:
1. `claimablePool == Σ (claimable + afking halves of balancesPacked[*])` — every credit/debit to a player's `balancesPacked` half is matched by an equal `claimablePool` move (DegenerusGameStorage.sol documents this as the invariant); and the reserve `balance + steth >= claimablePool` (no path credits a player without backing).
2. The sDGNRS-backing identity (INV-10 per-day cap / INV-13 single-pool / INV-02 dust tolerance in `sDGNRS.sol`) — every redemption/burn path keeps backing ≥ claims.

Find any reachable path where a credit lands without the matching pool move, a debit is double-applied, or a packed half-write desynchronizes the sum from `claimablePool`.

## Method & output
- Read the frozen source directly; cite `file:line`. Trace the actual write/order/guard — do not assume.
- For EACH of CORRUPT-01..05: verdict (**REAL / REFUTED / UNCERTAIN**), severity (**CATASTROPHE** for silent packed-storage or solvency corruption; else **HIGH / MEDIUM / LOW / INFO**), `reachable` under honest governance, the concrete trigger sequence / PoC sketch if REAL, and reasoning with citations.
- Also report any **newVectors** — a corruption path NOT covered by CORRUPT-01..05.
- Default to **REFUTED** only when you can show the mask/order/guard/identity is real and covers the WHOLE reachable window. If a guard is partial or a window is open, say **REAL** or **UNCERTAIN**. Be concrete and skeptical — a false REFUTED is worse than a false REAL here.
