# Phase 472 — AUDIT-RENAME-WIRING-STORAGE (mechanical inertness)

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-27 (isolated reviewer re-run; the first cluster agent returned a stub and was discarded)
**Subject:** frozen contracts/ tree 280bdb19 @ impl 3986926c (git-verified unmodified)
**Gate:** none

## Verdict

All four WIRE requirements **HOLD**. The mechanical churn surface is inert: the `Sub.reinvestPct`
removal is a pure within-slot repack (every following member shifts down 8 bits, `_subOf` root stays
slot 54), `_sdgnrsBonusLevel` is purely additive at slot 58 offset 25 with no downstream slot
displaced, and `WHALE_PASS_TYPE_SHIFT` stays bit 152 — all matching the 466 golden. The named-error
migration (186 `revert E()` in v73 → 29 retained in MintModule at HEAD, 157 migrated) is
**condition-preserving**: every migration pair keeps its `if (...)` guard byte-identical. Stale
references = 0; every renamed selector and widened return tuple matches its implementation, interfaces,
and all callers. The new events are pure `emit` (observability-only, no value gating).
**0 contract findings; candidates[] empty.** The only items are documentation-correction
`@custom:reverts`/comment mismatches (§4), routed to the C4A doc polish, not the frozen tree.

**Result: 4/4 requirements HOLD; 0 candidates raised; 0 confirmed findings.**

## Per-requirement dispositions

### WIRE-01 — storage layout — HOLDS
Confirmed against the 466 goldens + live `storage/DegenerusGameStorage.sol`. Top-level v73→HEAD diff
is ONLY astId/recompile churn (same slot/offset) plus the single ADD `_sdgnrsBonusLevel` (slot 58 off
25, uint24). `Sub` repack: no `reinvestPct`; members total 31 bytes (one slot), each at the v73 offset
−8 bits; `_subOf` root unchanged slot 54; cursor-slot 58 packs `_subCursor`/`_subOpenCursor`/
`_afkingResetDay`/`boxCursor`/`boxCursorIndex`/`presaleCloseIndex`/`_sdgnrsBonusLevel`; `boxPlayers`
stays slot 59. `WHALE_PASS_TYPE_SHIFT=152` (`BitPackingLib.sol:70`).

### WIRE-02 — named-error inertness — HOLDS
Every `E()→named` swap preserves the exact revert condition (the `if (...)` predicate is byte-identical
between the removed `revert E()` and the added `revert Named()` across all 157 migrated sites; method:
diffed all 327 changed revert/require lines v73→HEAD). MintModule deliberately retains 29 `E()` sites
(natspec still references `E`). `InvalidReinvestPct` removed cleanly (0 refs). Errors verified
condition-preserving include: OnlyDelegatecall/OnlySelf/OnlyAdmin/OnlyVault/OnlySDGNRS/OnlyCoordinator/
Unauthorized/GameOver/NotStarted/EmptyRevert/EmptyReturn/TransferFailed/Insolvent/Invariant/ZeroAddress/
ZeroValue/NothingToClaim/AlreadySwept/LengthMismatch/SelfBoon/ValueMismatch/MidDayActive/PreResetWindow/
InsufficientLink/NoPendingLootbox/BelowThreshold/RngInFlight/RngNotReady/PrizePoolFrozen/ScoreTooLow/
AlreadyClaimed/MsgValueExceedsAmount/InvalidSlot/RecipientAlreadyBoonedToday/SlotAlreadyUsed/
InvalidDistance/InvalidQuantity/MinQuantityRequired/InvalidLevelForPass/DeityPassConflict/PassNotExpired/
InvalidSymbol/SymbolTaken/AlreadyOwnsDeityPass/FoilAlreadyBought/StaleAdvance/DirectEthInsufficient/
NoClaimableMatch/SmiteeAfkingImmune/SmiteCeilingReached/NotSubscribed/SubscriberCapReached.

**Condition-CHANGING revert sites (NOT migration artifacts — deliberate feature rewrites owned by other
clusters, already audited there):**
| Site | change | owner cluster |
|---|---|---|
| `DegenerusGame` claimWinnings | `amount<=1 && afking==0 E()` → `payout==0 NothingToClaim()` | SOLV-06 |
| AdvanceModule decode | `length==0 E()` → `length<64 EmptyReturn()` | LIVE-01 |
| DegeneretteModule | `!operatorApprovals NotApproved` → `currency==WWXRP NotApproved` | ACCESS-02 |
| DegeneretteModule (×2) | strict/non-strict batch gate on packed==0 / rngWord==0 | EV-02 |
| WhaleModule:1011 | silent no-op → `halfPasses==0 NothingToClaim()` | LIVE-04 |
| GameAfkingModule | `reinvestPct>100 InvalidReinvestPct()` removed | EV-06 |
| storage `_queueTickets*` (×3) | `_livenessTriggered() E()` removed | RNG-03 |
| storage `_swapTicketSlot` | `ticketQueue[rk].length!=0 E()` removed | LIVE-02 |
| DegenerusAdmin `vote()` | `NotStalled()` removed → kill-on-recovery | ACCESS-06 |

### WIRE-03 — stale refs / selectors / tuples — HOLDS
0 stale refs for WHALE_BUNDLE_TYPE_SHIFT / WrappedWrappedXRP / purchaseWhaleBundle / `resolveBets(` /
retryLootboxRng / foilStreakBoost. `handleFoilPack` resolves only to `_handleFoilPackQuest`
(`DegenerusQuests.sol:827,1019`) — distinct extant fn, not the removed handler. All renamed selectors +
widened tuples matched to impl + interface + callers: `processTicketBatch→(finished,didWork)`,
`processFoilDrain→(done,drained)`, `_callTicketPurchase` 9-return (both call sites destructure 9),
`subscribe` (−reinvestPct, 5 args), `claimBingo(+address)`, `recordAfkingSecondary(+uint16)`,
`resolveDegeneretteBets`, `payAffiliateCombined→(address,uint256,uint256)`, `purchaseWhalePass`,
`handleFoilPurchase→(…,uint32 streakSnapshot)`. Build green (466/467).

### WIRE-04 — events — HOLDS
New events observability-only (emit alongside, not gating, value): `TicketsBought(buyer,qty,weiIn)`,
`WhalePassPurchased(buyer,qty,weiIn)`, `LazyPassPurchased(buyer,startLevel,weiIn)`,
`AfkingDelivered(player,day,weiIn)` (cover-buy reports weiIn=0 to avoid double-count with `LootBoxBuy`),
`FoilPackBought(buyer,level,multBps,weiIn)`. Affiliate single-emit: `payAffiliateCombined` emits exactly
one `AffiliateEarningsRecorded(...,combined=true)` (`DegenerusAffiliate.sol:648`), early-returns before
any emit when `sumScaled==0` (`:643`), no legacy `Affiliate(...)` in the combined path (the legacy event
persists only for code-creation + the standalone `payAffiliate` foil-pack legs). `claimBingo` retargets
`FirstQuadrantBingo`/`FirstSymbolBingo`/`BingoClaimed` to the resolved `player` (not msg.sender).

**Indexer-parity delta (DOCUMENT for 477):** standard ticket/lootbox buys no longer emit legacy
`Affiliate(amount,code,sender)`; the whole buy logs one `AffiliateEarningsRecorded` (the `combined`
flag distinguishes the folded roll). An indexer deriving buy-path affiliate volume from `Affiliate(...)`
must switch to `AffiliateEarningsRecorded`. The foil-pack path still co-emits both.

## §4 — Stale-natspec / comment doc-correction items (NOT defects → C4A doc polish / KNOWN-ISSUES)
1. `DegenerusGameGameOverModule.sol:72` — `@custom:reverts ZeroValue` but code reverts `Invariant` (rngWord==0, :94) / `TransferFailed` (:258,262,267).
2. `DegenerusGameWhaleModule.sol:182` — `MinQuantityRequired` annotated as value-mismatch; actually fires on `passLevel%100==0 && quantity<2` (:252).
3. `DegenerusGameWhaleModule.sol:401` — names only `OnlyDelegatecall` but also reverts `InvalidLevelForPass`/`DeityPassConflict`/`PassNotExpired` (:439,445,451).
4. `DegenerusGameWhaleModule.sol:553-554` — conflates `InvalidSymbol`(:562) with `SymbolTaken`(:563); `GameOver`(:561) mislabeled as value-mismatch.
5. `DegenerusGame.sol:543` — `newThreshold==0` reverts `ZeroValue`(:546), not `OnlyVault`.
6. `DegenerusGame.sol:1698` — also reverts `Insolvent`/`TransferFailed`(:1712), not only `OnlySDGNRS`.
7. `DegenerusGame.sol:1830/1851` — bundle conditions reverting `ZeroAddress`/`ValueMismatch`(:1837,1838) and `ZeroValue`/`Insolvent`/`TransferFailed`(:1855).
8. `DegenerusGameStorage.sol:2225` — `Sub` comment `// --- config (48 bits) ---` is stale; the config group is 40 bits after the `reinvestPct` removal.

## Candidates
None — clean as-built result. The §4 items are documentation-only corrections; the condition-changing
sites are deliberate, cluster-owned feature changes audited under their owning requirements.
