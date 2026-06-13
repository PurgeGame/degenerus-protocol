# Round 7 packet — DegenerusGameMintStreakUtils.sol + DegenerusGameStorage.sol (+ Game view, MintModule callers)

Source verified 2026-06-12 at round-6 HEAD 307d5312.

## MINT-12 (APPROVED) — thread (cl, oneTicketWei, seed) through the salvage quote helpers
- Sites: _quoteFarFutureSwap (MintStreakUtils:153+) and _quoteFarFutureBurnieSplit (:212+)
  each rebuild the per-player daily seed `keccak256(abi.encodePacked(player,
  rngWordByDay[_simulatedDayIndex() - 1]))` and re-evaluate priceForLevel(cl); callers
  previewSellFarFutureTickets (MintModule:1184/1189) and sellFarFutureTickets
  (:1220/:1226/:1240) add a third priceForLevel evaluation.
- Edits: new base helper `_farFutureSeed(address player)` holding the seed expression
  VERBATIM (single computation site → preview/exec parity by construction). Signatures:
  `_quoteFarFutureSwap(levels, quantities, cl, oneTicketWei, seed)` (player param dropped
  — only fed the seed), `_quoteFarFutureBurnieSplit(cashWei, oneTicketWei, seed)` (its
  internal priceWei = the passed oneTicketWei; `priceWei == 0` check value-identical).
  Both entry points compute `cl = _activeTicketLevel(); oneTicketWei =
  PriceLookupLib.priceForLevel(cl); seed = _farFutureSeed(player);` once
  (sellFarFutureTickets' existing oneTicketWei line absorbs into this). Natspec @param
  player lines updated on both helpers.
- Helpers are internal, callers exist only in MintModule (skeptic grep). RngLocked gate
  and prior-day word source untouched — no freeze-invariant interaction.

## MINT-15 (APPROVED) — relocate external curseCountOf out of the shared base
- Site: MintStreakUtils:410-412 — external view in the abstract base, landing in every
  deriving contract's dispatcher (NOT pruned). Post-round-6 derivers: Game, MintModule,
  GameAfkingModule, WhaleModule, DegeneretteModule (5 — Bingo dropped the base in
  SMALLMODS-09 and already shed its copy).
- Edit: move verbatim into DegenerusGame.sol (UI surface preserved, Game ABI identical);
  the 4 modules each drop the body + dispatcher entry.
- No on-chain caller (grep: zero in contracts/ + interfaces/); test fixtures call the
  Game (re-verified round 6: no harness queries a module address).

## RT-AFKING-WHALE-07 (APPROVED) — finish: the hot path is ALREADY APPLIED
- _playerActivityScoreAt already uses _mintStreakEffectiveFromPacked(packed, ...) — the
  audit's hot-path re-SLOAD no longer exists (applied in an earlier round under the
  FromPacked refactor). Residual: the sole remaining caller of the address-taking
  wrapper is DegenerusGame.ethMintStats (:2168), which ALREADY holds `packed` (:2159).
- Edit: ethMintStats → `_mintStreakEffectiveFromPacked(packed, _activeTicketLevel())`;
  delete the orphaned `_mintStreakEffective` wrapper (MintStreakUtils:100-105).
  Cold-view saving + small base shrink; confirm Game bytecode neutral-or-smaller.

## STORAGE-03 + RT-IDIOMS-08 (APPROVED ×2, ONE edit) — hoist loop-invariant flags in _queueTicketRange
- Site: storage _queueTicketRange (:665-697): per-iteration `rngLockedFlag` read (:679)
  and `ticketWriteSlot` read via _tqWriteKey (:680→:737). `level` already cached. Loop
  body = mapping/array SSTOREs only, zero external calls; neither flag has a writer
  reachable from the loop (ticketWriteSlot only in _swapTicketSlot, rngLockedFlag only
  in advance/RNG paths).
- Edit: before the loop `bool rngLockedCached = rngLockedFlag; uint24 writeSlotBit =
  ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0);`; in the loop
  `if (isFarFuture && rngLockedCached && !rngBypass) revert RngLocked();` and
  `uint24 wk = isFarFuture ? _tqFarFutureKey(lvl) : (lvl | writeSlotBit);`
  (algebraic identity: `ticketWriteSlot ? lvl|BIT : lvl` ≡ `lvl | (ticketWriteSlot ?
  BIT : 0)`). Per-level lock-check semantics byte-equivalent (same locked value observed).
- ~100/iteration → ~10k per 100-level whale bundle, ~1k per 10-level lazy-pass activation.
- RT-IDIOMS-08 (same hoist, different ID) subsumed by this edit.

## Test impact
- Whale/ticket-queue suites are the net for the storage hoist; mint-salvage tests for
  MINT-12 (preview/exec parity pins must stay green). curseCountOf relocation: V61 fuzz
  suites call it on the Game — unaffected.
