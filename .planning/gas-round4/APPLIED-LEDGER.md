# Gas round-4 — applied ledger

50 verified findings applied across 6 packets (advance · cross · decimator · lootbox · mint · whale).
All behavior-preserving: same state transitions, payouts, RNG inputs, and revert conditions on
every reachable path. Verified by 3 independent reviewer passes (one per packet-pair) + full forge
parity + JS name-identity to baseline.

## By module

**DegenerusGameMintModule** — MINT-04/05/08/09/11/16, RT-MINT-04/08/09, RT-IDIOMS-04
- MINT-04: `recordMintData` external entry + `recordMint`'s trailing `_recordMintDataModule`
  delegatecall-back deleted; recording is now a direct internal `_recordMintData` call at the
  self-call's return point (byte-identical execution order — recording touches no claimable/pool
  state). `recordMint` ABI narrowed to `(player, costWei, payKind)` (self-call-only). Drops the
  dispatch from DegenerusGame → −158 bytes (Game 20,651 → 20,493).
- MINT-05: per-batch `counts`/`touchedTraits` scratch hoisted out of `_raritySymbolBatch`,
  threaded by ref, re-zeroed to preserve the all-zero invariant.
- MINT-08/RT-MINT-09: `_mintCost` → `_purchaseCostInputs` (one read of flag/level/price/ticketCost),
  forwarded into `_purchaseForWithCached`; quests `handlePurchase` price + cached comp/cnt gated.
- MINT-09/RT-MINT-08: lootbox-slot RMWs (`lootboxRngPacked`, `presaleStatePacked`) cached to one
  masked SSTORE each; enqueue flattened to a direct `boxPlayers[].push`.
- MINT-11: ticketCursor epilogue writes the packed (cursor,level) slot once per path.
- MINT-16: jackpot flag/counter read + nextStep computed once under the `cachedJpFlag` guard.
- RT-MINT-04/RT-IDIOMS-04: `recordMintQuestStreak` self-call → internal `_recordMintStreakForLevel`.

**DegenerusGameLootboxModule** — LOOTBOX-02/05/06/07/08, VIEWER-02, RT-CLAIMS-02/03/05/12
- LOOTBOX-08: `openHumanBoxes` sweep loads the per-index VRF word and per-entry lootboxEth/
  presaleBoxEth once (the skip-check reads) and threads them into the new
  `_openLootBoxLegWith(player, idx, packed, word)` + presale resolve, instead of re-SLOADing in
  `_openBoxBoth`. Cache-safety: no callee on the lootbox leg hands control to player code, and a
  presaleBoxEth write at a worded index is unreachable from the buy path; presale read-then-zero-
  then-resolve order preserved.
- LOOTBOX-02/VIEWER-02: dead `deityBoonSlots` view + its interface decl deleted.
- LOOTBOX-05/06/RT-CLAIMS-12: dead zero-guards flattened (callers guarantee nonzero).
- LOOTBOX-07/RT-CLAIMS-03: `currentLevel` + `deityPassCount` threaded into boon roll/pool-stats.
- RT-CLAIMS-05: `issueDeityBoon` lazy-mask, no day-rollover zeroing SSTORE.

**DegenerusGameDecimatorModule** — DECIMATOR-02/03/06/08/09/11/13/14, QUESTS-04, RT-QUESTS-AFFILIATE-04
- Loop-invariant hoists, `_consumeDecClaim` inlined, dead zero-guards removed, single struct-literal
  resets, `effectiveBaseStreak` swap, `_consumeTerminalDecClaim` returns (amount,lvl) to drop a
  re-read; weight conservation bit-identical.

**DegenerusGameWhaleModule** — GAME-12, WHALEBOON-01/02/08/09/10/11/13, RT-AFKING-WHALE-11/12
- 100-iteration bonus-ticket loops → closed-form two-range queue; `_playerActivityScore` internal
  call; mintPacked_ caching; dead lazy-default branches deleted.

**DegenerusGameAdvanceModule** — ADVANCE-05/08/09/14, RT-IDIOMS-09 (ADVANCE-12/18, RT-IDIOMS-10 pre-applied)
- dailyIdx/rngLockedFlag hoisted; VRF struct construction → `_requestVrfWord`; pool-balance read
  hoisted; `_emitDailyWinningTraits` wrapper inlined.

**Cross (Quests + AfkingModule)** — QUESTS-13, RT-QUESTS-AFFILIATE-15
- New lean `questCompletionToday(player)` view (delegates to `_questCompleted` per slot —
  day-roll semantics inherited) replaces afking's call to the fat `playerQuestStates`, which
  computed streak/progress only to discard them. Module-local `IQuestCompletionView` interface.

## Not applied
- ADVANCE-12/18, RT-IDIOMS-10: already present in HEAD from a prior round (no-op).
