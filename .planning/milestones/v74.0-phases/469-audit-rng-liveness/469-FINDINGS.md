# Phase 469 — AUDIT-RNG-LIVENESS (DOMINANT RNG-freeze + HIGH gas/liveness)

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-27 (isolated neutral-prompt reviewer, Workflow wf_00bd2866-d0b; adversarial-verify pipeline)
**Subject:** frozen contracts/ tree 280bdb19 @ impl 3986926c (git-verified unmodified after the read-only fan-out)
**Gate:** none

## Verdict

As-built re-audit of the v73.0→HEAD (3986926c) VRF-deadman, mid-day abandon-and-promote, queue-gate removal, sDGNRS level-start box, foil/Degenerette/jackpot word consumption, and the (finished,didWork)/(done,drained) advance-chain composition guards. Every DOMINANT RNG-freeze and HIGH gas-liveness requirement HOLDS against the frozen source. The deadman is a pure monotonic latch (no uint24 underflow possible since dailyIdx<=_simulatedDayIndex always; stays frozen through the multi-tx drain until the terminal _unlockRng) and commits only a sealed-historical + prevrandao fallback with the reverseFlip nudge cancelled-and-consumed (totalFlipReversals subtract); the prevrandao bias is the documented, security-equivalent-to-v73, gameover-only-when-VRF-dead tradeoff (RNG steering on live Chainlink is out of scope). Mid-day promotion preserves the reserved bucket via isRetry (skips _lrAdvanceIndexClearPending) and the stale requestId can never re-match in rawFulfillRandomWords; promotion only fires when the bucket is empty, so no delivered-word reroll. The 3 queue sinks keep the far-future rngLocked revert and rely on the purchase-entry liveness gate (mint module reverts on _livenessTriggered) so no post-word player ticket can reach a terminal jackpot. The sDGNRS box is sized off a LIVE claimable read strictly pre-rngGate and frozen by a once-per-level latch. Foil consumes only sealed rngWordByDay (StaleAdvance day>dailyIdx+1 + rw==0 Invariant guards intact); Degenerette consumes only lootboxRngWordByIndex[index] with zero storage mutation before the packed==0/rngWord==0 gates; BAF is byte-unchanged but the OnlySelf rename. The (finished,didWork) and (done,drained) signals never report a heavy-work batch as no-work (substantial work => SSTOREs => used>0 => didWork=true), so no false negative re-enables same-tx batch+jackpot composition; the decode guards are either fail-open (game-over) or unreachable-on-the-constant-module (normal path); openHumanBoxes is budget-bounded and the combined OPEN_KNEE pro-rate caps per-box extraction at the calibrated rate (no splitting premium); claimWhalePass's empty-claim NothingToClaim revert affects only the two standalone harvest wrappers, no advance-chain crank. candidates[] is empty — clean as-built.

**Result: 9/9 requirements HOLD; 0 candidates raised; 0 confirmed findings.**

## Per-requirement dispositions

### RNG-01 — HOLDS

**Evidence:** contracts/storage/DegenerusGameStorage.sol:1502-1504 (_vrfDeadmanFired = _simulatedDayIndex()-dailyIdx>120); :252 dailyIdx uint24; AdvanceModule.sol:1906 dailyIdx=day set only in _unlockRng; :176,191 day<=_simulatedDayIndexAt(ts) so dailyIdx<=current day → no uint24 underflow; latch stays frozen through drain since _unlockRng runs only at terminal step (DegenerusGameAdvanceModule.sol:761); fallback word non-steerable: _getHistoricalRngFallback uses sealed rngWordByDay + block.prevrandao (:1444-1468) and the reverseFlip nudge is cancelled+consumed via unchecked fallbackWord-=totalFlipReversals (:1395) against the += in _applyDailyRng (:2023-2030)

**Note:** No false-fire on a healthy game: dailyIdx advances every sealed day (purchase, jackpot, last-purchase all reach _unlockRng), so the 120-day gap only opens when no day seals for 120d = VRF-dead/abandoned. prevrandao 1-bit/propose-or-skip bias is the documented gameover-only-when-VRF-dead tradeoff (security-equivalent to the v73 14-day-grace fallback; deadman only removes a delay that would have elapsed anyway); RNG steering on live Chainlink is out of scope per the locked rulings.

### RNG-02 — HOLDS

**Evidence:** AdvanceModule.sol:316-329 (mid-day stall promotion gated on !rngLockedFlag && rngRequestTime!=0 && elapsed>=MIDDAY_RNG_STALL_TIMEOUT(:147=4h) && bucket empty :301 && rngWordCurrent==0 :303); _finalizeRngRequest isRetry=vrfRequestId!=0 && rngRequestTime!=0 && rngWordCurrent==0 (:1785-1787) skips _lrAdvanceIndexClearPending (:1793-1796) so lootboxRngIndex-1 is preserved; isDailyRetry distinguishes mid-day vs daily (:1792); rawFulfillRandomWords drops the stale id via requestId!=vrfRequestId || rngWordCurrent!=0 (:1941); _finalizeLootboxRng writes the same reserved index-1 once (:1330-1334)

**Note:** No reroll: promotion requires the reserved bucket empty (word never delivered); a delivered mid-day word sets the bucket and zeroes rngRequestTime (rawFulfillRandomWords :1949-1956) so the promotion branch can't fire. The fresh daily word is a new VRF request → unknown at promotion, not steerable. requestLootboxRng MidDayActive/RngInFlight guards (:1145,1154) block re-request.

### RNG-03 — HOLDS

**Evidence:** _queueTickets/_queueTicketsScaled/_queueTicketRange keep the far-future rngLocked revert (DegenerusGameStorage.sol:652,683,744) — only the liveness-timeout gate was removed; the write→read ticketWriteSlot swap freezes at RNG-request time (_swapAndFreeze :437,1762-1765) so tickets queued during the rngLocked window land in the write slot and cannot resolve against the current word; purchase entry points gate liveness and revert (DegenerusGameMintModule.sol:956,1116,1370,1834) so no player ticket can be queued during the game-over/liveness window; the advance-chain's own queueing uses rngBypass (AdvanceModule.sol:1620-1631)

**Note:** v45 freeze invariant preserved: the queue sink must not revert because the advance-chain daily-jackpot distribution flows through it (comment :644-649); protection is at the purchase entry, not the shared sink. In game-over the read slot drains one batch then _swapTicketSlot promotes write→read only after finished (:734-749), and no new player tickets can enter (liveness-gated).

### RNG-04 — HOLDS

**Evidence:** GameAfkingModule.sol:1170-1198 — box block reads LIVE cl=_claimableOf(SDGNRS) (:1172), box=min(cl/20,6 ether) floored at mp (:1179-1181); runs inside processSubscriberStage which is _runSubscriberStage (AdvanceModule.sol:385) executed strictly BEFORE rngGate (:428), so rngWordByDay[processDay] is uncommitted at stamp; once-per-level latch currentLevel>_sdgnrsBonusLevel (:1170) stamped only when the buy fires (:1178); box resolves at open off rngWordByDay[lastAutoBoughtDay] (DegenerusGameStorage.sol:2187,2251) which seals after the stamp day

**Note:** Box amount frozen at the pre-RNG stamp; the latch blocks any re-size within the level after the word becomes knowable. Inflating sDGNRS claimable before the read only enlarges sDGNRS's own self-funded box (positive-EV lootbox is by-design) and cannot steer an unknown word. cl>mp guard + cl/20<cl keeps the 1-wei sentinel.

### RNG-05 — HOLDS

**Evidence:** BAF: DegenerusGameJackpotModule.sol:1956-1964 runBafJackpot gate msg.sender!=address(this) revert OnlySelf() then delegates to jackpots.runBafJackpot(poolWei,lvl,rngWord) unchanged; Foil: DegenerusGameFoilPackModule.sol:184 StaleAdvance day>dailyIdx+1 forward-commit guard, :584-585 rw=rngWordByDay[day] / rw==0 revert Invariant, claim re-derives from rngWordByDay[resolveDay] (:475) with resolveDay bounded (:297-301), drain only sealed buckets (:704-705); Degenerette: DegenerusGameDegeneretteModule.sol:725 rngWord=lootboxRngWordByIndex[index] is the sole word, packed==0 (:709-712) and rngWord==0 (:726-732) gates precede the only mutation delete (:734); placement requires the index word unset (:608)

**Note:** BAF/jackpot winner fan-out is byte-unchanged (only the E()→OnlySelf selector). Degenerette strict/non-strict trailing-skip is a clean no-op (comment :729 'Nothing is mutated above this point'); ResolveAcc flushed once (:517-530), additive/byte-identical.

### LIVE-01 — HOLDS

**Evidence:** processTicketBatch returns (finished,didWork): didWorkThisCall=used>0||foilDrained (DegenerusGameMintModule.sol:729), top-empty path returns foil drained flag (:668-670), mid-queue returns used>0 (:744); _runProcessTicketBatch decodes (finished,worked) and returns (worked,finished) (AdvanceModule.sol:1611); daily gate breaks on preWorked||!preFinished (:343-346) and mid-day on ticketWorked||!ticketsFinished (:253-261); processFoilDrain drained=true iff ≥1 buyer resolved (DegenerusGameFoilPackModule.sol:722,740); decode guards: game-over fail-open dData.length>=64 swallow→drain (AdvanceModule.sol:734-751), normal-path data.length<64 revert (:1610) only on the constant module that always returns 64 bytes

**Note:** No false negative with heavy work: substantial work => SSTOREs => used>0 => didWork=true => break (no composition). didWork=false only when used==0 and no foil buyer resolved (negligible gas, safe to compose). The normal-path 64-byte revert cannot trip on a healthy game (constant module, fixed (bool,bool) return).

### LIVE-02 — HOLDS

**Evidence:** _swapTicketSlot fail-open toggle (AdvanceModule.sol:1737-1740); all callers swap only after the read slot is drained: game-over after finished (:734-745), requestLootboxRng under ticketsFullyProcessed (:1192-1193), mid-day promotion _swapAndFreeze only when ticketQueue[preRk].length==0 else _freezePool (:322-326), daily _swapAndFreeze after ticketsFullyProcessed set (:348→437); _freezePool single-seed guarded by if(!prizePoolFrozen) (:1748) and the 1% futurePool seed is rolled back by _unfreezePool at every _unlockRng (:1769-1776,1911)

**Note:** The non-empty read-slot branch is unreachable; even if hit it defers entries one cycle (no loss, no revert) so the heartbeat cannot brick. No double-seed: the freeze flag gates the seed; _unfreezePool folds pending back so no backing leaks or strands.

### LIVE-03 — HOLDS

**Evidence:** Game-over drains ONE ticket batch per tx then breaks STAGE_TICKETS_WORKING (AdvanceModule.sol:725-749), handleGameOverDrain runs in its own tx entered with ticketsFullyProcessed set (:754-761); deadman routes to this same one-batch discipline (:216-224 returns at :222, no do-while composition); mintFlip advance/open legs are mutually exclusive (GameAfkingModule.sol:1620 else 1642), openHumanBoxes budget-bounded by steps<budget=OPEN_BATCH-opened≤80 (DegenerusGameLootboxModule.sol:680-726) with entry-gate return 0 under rngLock/liveness (:665); combined open count one bounty via OPEN_KNEE pro-rate k=min(opened,5), bountyEarned=(unit*k)/OPEN_KNEE (GameAfkingModule.sol:1660-1667)

**Note:** Per-tx work capped at ~80 O(1) box-opens; pro-rate caps per-box extraction at the calibrated unit/5 rate (5 singles == 1 batch-of-5, no splitting premium; a big batch is capped at unit = a discount to the protocol). FLIP-credit illiquidity + real-gas cost per box means no profitable farm (bounty-vs-real-gas ruling). Deadman adds no new advance-chain composition vs v73.

### LIVE-04 — HOLDS

**Evidence:** _foilDrainPending gates the daily draw (AdvanceModule.sol:246-248,294-297) and is true while foilDrainDay<=foilLastResolveDay && rngWordByDay[dd]!=0 (DegenerusGameStorage.sol:2573-2577); _processFoilDrain charges a whole buyer at FOIL_PACK_ENTRIES*2+3=35 units, defers when room<35 (DegenerusGameFoilPackModule.sol:716-720); mid-day 4h fold returns STAGE_RNG_REQUESTED and breaks (AdvanceModule.sol:327-328); claimWhalePass empty-claim halfPasses==0 revert NothingToClaim (DegenerusGameWhaleModule.sol:1010-1011); callers are only the two standalone harvest wrappers DegenerusVault.gameClaimWhalePass (DegenerusVault.sol:582-583) and sDGNRS.gameClaimWhalePass (sDGNRS.sol:483-484), both crediting address(this), never composed into an atomic crank/sweep

**Note:** Readiness gate still blocks the draw until every sealed foil bucket drains; worst-case per-call bounded by the write budget. The NothingToClaim revert only fails a single standalone manual/permissionless harvest call; no on-chain advance-chain crank, Vault sweep, or sDGNRS harvest sequence relied on the prior silent return.

## Candidates

None — clean as-built result (the expected outcome for this already-pre-push-audited batch).
