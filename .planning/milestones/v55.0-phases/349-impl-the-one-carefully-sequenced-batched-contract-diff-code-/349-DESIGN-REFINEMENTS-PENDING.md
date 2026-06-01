# 349 IMPL — in-review design refinements (HELD diff, uncommitted)

> **⚠ SUPERSEDED 2026-05-31 → `../349.1-afking-box-redesign-*/349.1-DESIGN.md`.** The PENDING
> P1–P5 redesign below was re-derived + corrected in a fresh-context hand-review and now lives in
> **Phase 349.1** (inserted after 349). Key changes vs the P1–P5 sketch below: P3's `dailyIdx-1`
> premise is UNSOUND (`LR_INDEX ≠ dailyIdx`) → instead **`_afkingEpoch` is DROPPED entirely**
> (live-level resolve off the frozen-day word `rngWordByDay[lastAutoBoughtDay]`); the box follows the
> `resolveLootboxDirect` (auto-resolve, live-level) pattern, justified by a structural no-exploit proof
> (permissionless BURNIE auto-open removes player open-timing control). NEW load-bearing rule: the
> **NO-ORPHAN guard** covering all FOUR orphan paths (re-stamp + cancel-reclaim + evict + funding-kill,
> all `_removeFromSet`/`delete`). The held 349 diff's frozen-`_afkingEpoch` model is REPLACED by 349.1.
> Read 349.1-DESIGN.md, not the P1–P5 below.

**Status:** The whole v55 phase-349 batched diff is APPLIED + `forge build` clean (all contracts < 24,576 B; DegenerusGame 23,499 B) and **HELD uncommitted** at HEAD `60a4b5b5` for the USER contract-commit gate. During hand-review the USER directed a series of refinements; some are DONE (below), one larger freeze-critical redesign is PENDING (below) — paused because the orchestrator hit ~65% context and this redesign is too intricate/freeze-critical to start there.

## DONE this review session (applied, build-clean, uncommitted)
1. **Tail-flag parity** — `resolveAfkingBox` now passes `emitLootboxEvent=true` + `payColdBustConsolation=true` (afking boxes emit `LootBoxOpened` + pay the WWXRP bust consolation like a normal box). `distressEth=0,0` left OFF deliberately (USER: niche final-day-before-game-over feature; subs gone by then) — documented inline.
2. **subscribe consolidation** — single create/replace/cancel entrypoint: `subscribe(q>=1)` = upsert (create or replace-in-place), `subscribe(0)` = revert-if-no-active-sub / cancel(tombstone)-if-active; guarded `if (rngLockedFlag) revert RngLocked()`. The 4 per-field setters + their 4 Game dispatch stubs + 4 interface decls REMOVED.
3. **subsFullyProcessed → slot 0** (off 31) — warm with `ticketsFullyProcessed`/`rngLockedFlag`/`level` in the advance path.
4. **1-slot Sub** — uniform-per-cycle fields (`index`,`day`,`baseLevelPlus1`) extracted to a per-day epoch map `_afkingEpoch[day] = pack(index, baseLevelPlus1)` (written once/cycle, cross-cycle freeze-safe via per-day key); `fundingSource` → sparse `_fundingSourceOf` map. `day` dropped (== `lastAutoBoughtDay`). Sub = 1 slot.
5. **FLAG_EXTERNAL_FUNDING** (bit 0) — self-funded subs skip the `_fundingSourceOf` SLOAD (read the already-loaded flag instead).
6. **mp cleanup** — `processSubscriberStage` reuses `_mintPriceInContext()` instead of inlining `PriceLookupLib.priceForLevel(_activeTicketLevel())`.
7. **AfKing.sol + ContractAddresses.sol.bak DELETED** (AfKing was an empty tombstone, no importers).

## PENDING — freeze-critical redesign (do in a FRESH full-context session)
The USER converged on this design for the afking buy/open model. NOT yet implemented.

### P1 — `amount` → `quantity` (whole tickets)
- Store the QUANTITY (effectiveQty, whole ticket count) in the Sub, NOT wei. Rename `uint96 amount` → e.g. `uint32 quantity` (frees ~64 bits; Sub stays 1 slot with headroom).
- **Reinvest rounds to whole tickets** (USER) — `reinvestQty = (claimable*reinvestPct/100)/mp` already floors to whole tickets; ensure effectiveQty is always a whole ticket count and clamp to the field width.
- At open, derive per mode (see P2): ticket = `quantity` tickets; lootbox eth = `quantity * frozenMp`.

### P2 — separate ticket-sub and lootbox-sub lists (USER: "ticket option should be allowed; maybe a separate list for ticket subs")
- Ticket-mode IS supported (do NOT drop it). The current held diff has a GAP: `_resolveBuy` returns `isTicket` but the open (`resolveAfkingBox`) ALWAYS materializes a lootbox — a `FLAG_USE_TICKETS` sub would open as a mis-sized lootbox. Fix via separate homogeneous sets so the hot loops never branch per-sub on mode:
  - `_lootboxSubs` (+ cursor): STAGE stamps `quantity` → OPEN materializes a lootbox via `resolveAfkingBox` (eth = quantity*frozenMp).
  - `_ticketSubs` (+ cursor): STAGE queues `quantity` tickets at the frozen ticket level (the existing ticket-queue mechanic; no box stamp/seed). Route at `subscribe` by `FLAG_USE_TICKETS`.

### P3 — daily-RNG-as-epoch (USER: "use dailyidx-1 as the epoch for all auto boxes; the daily rng is always the one used; the lootbox index is the same number anyway")
- afking boxes resolve with the DAILY RNG word (keyed by `dailyIdx`, slot 0). The per-box lootbox `index` is REDUNDANT — derive the RNG index from `dailyIdx` (USER says `dailyIdx - 1`) instead of storing it in the epoch. This can drop `index` from `_afkingEpoch` entirely.
- **VERIFY (freeze-critical):** the exact `dailyIdx ↔ processDay ↔ daily-RNG-index` mapping, and that deriving the index at open (post-cycle, `dailyIdx` advanced) from the FROZEN `lastAutoBoughtDay` still yields the SAME daily word the box was stamped against. If `dailyIdx` is not 1:1 with the day, the frozen day must still resolve to the right daily index. Confirm before relying on `dailyIdx-1`.

### P4 — epoch must store the FROZEN price (mp), not derive from baseLevel
- `_activeTicketLevel() = jackpotPhaseFlag ? level : level + 1` — so the price level ≠ the box `baseLevel` in purchase phase. The lootbox-open eth derivation (`quantity * mp`) must use the price `mp` (or the price level) FROZEN at process — store it in the epoch (it's uniform per cycle). Do NOT derive mp from `baseLevelPlus1`.

### P5 — finish the AfKing cleanup (gated on P2)
- Remove the dead `batchPurchase` + `BatchBuy` struct (DegenerusGame ~1886-1955; AF_KING-gated, zero callers) — it was the old ticket+lootbox buy path, superseded by the in-context STAGE.
- Remove the dead `AF_KING` entry from `BurnieCoinflip.onlyFlipCreditors`; the `ContractAddresses.AF_KING` constant is then unused (leave or remove + note deploy impact).

## After the redesign
Re-run `forge build --skip "test/**" --skip "*.t.sol"` + `--sizes` (DegenerusGame < 24,576); confirm freeze invariants (frozen quantity + frozen mp + frozen day → daily RNG; no `block.*`); keep the diff HELD for the USER commit gate. `forge test` is 351 TST's charge (stale `poolOf` + ABI breaks expected).

## Resume
Fresh session: read this file + the 5 SUMMARYs in this phase dir + `git diff` of the held tree. The contract-commit gate (`CONTRACTS_COMMIT_APPROVED=1` + USER "approved") is still OPEN — nothing is committed.
