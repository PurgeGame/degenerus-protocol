# Phase 121: Storage and Gas Fixes - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply 7 audit finding fixes (FIX-01 through FIX-03, FIX-05 through FIX-08) as mechanical contract changes with delta verification. I-12 freeze fix is deferred to Phase 122. No new features — surgical fixes only.

</domain>

<decisions>
## Implementation Decisions

### FIX-01: lastLootboxRngWord removal
- **D-01:** Full deletion: delete the `uint256 internal lastLootboxRngWord;` declaration from DegenerusGameStorage.sol:1231. User explicitly chose delete over deprecate. Must verify via `forge inspect` that no downstream storage slots shift in a way that breaks delegatecall modules — if the variable is the last in its slot group or padding allows safe removal, this is fine.
- **D-02:** Delete 3 write sites in DegenerusGameAdvanceModule.sol:
  - L162: delete `lastLootboxRngWord = word;`
  - L862: delete `lastLootboxRngWord = rngWord;`
  - L1526: delete `lastLootboxRngWord = fallbackWord;`
- **D-03:** Redirect 1 read site in DegenerusGameJackpotModule.sol:1838: replace `uint256 entropy = lastLootboxRngWord;` with `uint256 entropy = lootboxRngWordByIndex[lootboxRngIndex - 1];`
- **D-04:** Safe because consumer always runs after VRF finalization — `lootboxRngWordByIndex[lootboxRngIndex - 1]` is guaranteed non-zero. Mid-day path already checks `word != 0`.

### FIX-02: Double _getFuturePrizePool() SLOAD
- **D-05:** DegenerusGameJackpotModule.sol earlybird path (L774/778): L774 reads `futurePool = _getFuturePrizePool()`, L778 reads it again. Fix: reuse L774 value → `_setFuturePrizePool(futurePool - reserveContribution)`
- **D-06:** Same pattern at early-burn path (L601/604). Fix: same approach, reuse the local.
- **D-07:** No writes between the two reads — both return identical values. Saves 100 gas per call (warm SLOAD).

### FIX-03: RewardJackpotsSettled event
- **D-08:** DegenerusGameEndgameModule.sol L252: event emits `futurePoolLocal` (pre-reconciliation) instead of post-reconciliation value. Fix: emit `futurePoolLocal + rebuyDelta` after the reconciliation block.
- **D-09:** Cosmetic fix — no on-chain state impact, but indexers/frontends see accurate value.

### FIX-05: BitPackingLib NatSpec
- **D-10:** BitPackingLib.sol L59: change comment from "bits 152-154" to "bits 152-153". All callers use mask=3 (0b11) confirming 2-bit field. Zero bytecode change.

### FIX-06: Deity boon downgrade prevention
- **D-11:** In `_applyBoon()` (DegenerusGameLootboxModule.sol L1396-1601), add a tier check: if the player already has a boon of equal or higher tier for that boon type, skip the overwrite.
- **D-12:** This applies to ALL boon types, not just lootbox boons. Check every boon category the deity can issue.

### FIX-07: advanceBounty deferred computation
- **D-13:** Delete L127 — remove early `advanceBounty = (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / price;`
- **D-14:** Replace L189-202 escalation block with a `bountyMultiplier` computation (1x base, 2x at 20min, 4x at 1h, 6x at 2h).
- **D-15:** Replace all 3 `coin.creditFlip(caller, advanceBounty)` calls (L177, L214, L396) with `coin.creditFlip(caller, (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) / price);`
- **D-16:** Bounty always reflects current price at payout time. Saves one eager SLOAD on early-exit paths.

### FIX-08: lastLootboxRngWord delta audit
- **D-17:** Enumerate ALL write sites for both `lastLootboxRngWord` and `lootboxRngWordByIndex` and prove they write the same value in every path (normal VRF, mid-day, stall backfill, coordinator swap, game-over fallback).
- **D-18:** Verify `lootboxRngIndex` is never 0 when the read site executes (underflow check on `index - 1`).

### Claude's Discretion
- Exact ordering of fix application within the phase
- Whether to run `forge test` after each fix or batch them

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Contract files being modified
- `contracts/storage/DegenerusGameStorage.sol` — L1231 lastLootboxRngWord declaration
- `contracts/modules/DegenerusGameAdvanceModule.sol` — L162, L862, L1526 (write sites), L127/L189-202/L177/L214/L396 (advanceBounty)
- `contracts/modules/DegenerusGameJackpotModule.sol` — L1838 (read site), L774/778 and L601/604 (double SLOAD)
- `contracts/modules/DegenerusGameEndgameModule.sol` — L252 (event emission)
- `contracts/libraries/BitPackingLib.sol` — L59 (NatSpec)
- `contracts/modules/DegenerusGameLootboxModule.sol` — L1396-1601 (_applyBoon)

### Audit context
- `audit/FINDINGS.md` — v5.0 master findings (I-01 through I-04)
- `.planning/research/SUMMARY.md` — Research on deprecate-not-delete pattern, BAF risks

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `forge inspect DegenerusGameStorage storage-layout` — verify slot positions unchanged after deprecation
- Existing `// DEPRECATED` comments in codebase (if any) as style reference

### Established Patterns
- Storage variable deprecation: keep declaration, remove reads/writes (v3.9 precedent with _tqWriteKey)
- Local variable caching for SLOAD reduction (v4.2 daily jackpot precedent)
- Event emission after state writes (CEI pattern, v2.1 _executeSwap precedent)

### Integration Points
- All modified files are delegatecall modules inheriting DegenerusGameStorage
- MockVRFCoordinator.sol may need updates if tests reference lastLootboxRngWord
- VRFStallEdgeCases.t.sol tests were just fixed in Phase 120 — may need adjustment after deprecation

</code_context>

<specifics>
## Specific Ideas

- User provided exact line numbers and replacement code for FIX-07 (advanceBounty) — use verbatim
- User emphasized "make sure deities cant downgrade any type of boon" for FIX-06
- FIX-08 delta audit must cover all 5 RNG paths explicitly

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 121-storage-and-gas-fixes*
*Context gathered: 2026-03-26*
