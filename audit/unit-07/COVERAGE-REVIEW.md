# Unit 7: Decimator System -- Coverage Review

**Taskmaster Identity:** I am a relentless QA lead. My job is to ensure the Mad Genius actually examined every state-changing function, every subordinate call, and every storage write -- no exceptions, no shortcuts.

---

## Function Checklist Verification

| # | Function | In Checklist? | In Attack Report? | Call Tree Complete? | Storage Writes Complete? | Cache Check Done? |
|---|----------|:---:|:---:|:---:|:---:|:---:|
| B1 | `recordDecBurn` | YES | YES | YES (full expansion to _decSubbucketFor, _decRemoveSubbucket, _decUpdateSubbucket, _decEffectiveAmount) | YES (6 write points documented) | YES (SAFE) |
| B2 | `runDecimatorJackpot` | YES | YES | YES (full loop expansion with _decWinningSubbucket, _packDecWinningSubbucket) | YES (4 write points documented) | YES (SAFE) |
| B3 | `consumeDecClaim` | YES | YES | YES (delegates to _consumeDecClaim, full expansion in B4 section) | YES (1 write: claimed flag) | YES (SAFE) |
| B4 | `claimDecimatorJackpot` | YES | YES | YES (full recursive expansion through _consumeDecClaim, _creditDecJackpotClaimCore, _addClaimableEth, _processAutoRebuy, _creditClaimable, _calcAutoRebuy, _queueTickets, _awardDecimatorLootbox, _queueWhalePassClaimCore, delegatecall LootboxModule) | YES (9 write categories documented) | YES (SAFE -- detailed BAF analysis) |
| B5 | `recordTerminalDecBurn` | YES | YES | YES (expansion through _terminalDecDaysRemaining, self-call playerActivityScore, _terminalDecBucket, _decSubbucketFor, _decEffectiveAmount, _terminalDecMultiplierBps) | YES (6 write points documented) | YES (SAFE) |
| B6 | `runTerminalDecimatorJackpot` | YES | YES | YES (full loop expansion) | YES (4 write points documented) | YES (SAFE) |
| B7 | `claimTerminalDecimatorJackpot` | YES | YES | YES (expansion through _consumeTerminalDecClaim, _addClaimableEth, _processAutoRebuy early return, _creditClaimable) | YES (2 write points documented) | YES (SAFE) |
| C1 | `_consumeDecClaim` | YES | YES (in B4 tree) | YES | YES | YES |
| C2 | `_processAutoRebuy` | YES | YES (in B4 tree) | YES (all branches) | YES | YES |
| C3 | `_addClaimableEth` | YES | YES (in B4 + B7 trees) | YES | YES | YES |
| C4 | `_creditDecJackpotClaimCore` | YES | YES (in B4 tree) | YES | YES | YES |
| C5 | `_decUpdateSubbucket` | YES | YES (in B1 tree) | YES | YES | N/A (leaf) |
| C6 | `_decRemoveSubbucket` | YES | YES (in B1 tree) | YES | YES | N/A (leaf) |
| C7 | `_awardDecimatorLootbox` | YES | YES (in B4 tree) | YES (both branches: whale pass + delegatecall) | YES | YES |
| C8 | `_consumeTerminalDecClaim` | YES | YES (in B7 tree) | YES | YES | N/A (leaf) |
| C9 | `_creditClaimable` | YES | YES (in B4 + B7 trees) | YES | YES | N/A (leaf) |
| C10 | `_calcAutoRebuy` | YES | YES (in B4 tree) | YES | YES (pure -- no writes) | N/A (pure) |
| C11 | `_queueWhalePassClaimCore` | YES | YES (in B4 tree) | YES | YES | N/A (leaf) |
| C12 | `_queueTickets` | YES | YES (in B4 tree) | YES | YES | N/A (inherited) |
| C13 | `_revertDelegate` | YES | YES (in B4 tree) | YES | YES (pure -- no writes) | N/A (pure) |
| D1 | `decClaimable` | YES | N/A (view) | N/A | N/A | N/A |
| D2 | `terminalDecClaimable` | YES | N/A (view) | N/A | N/A | N/A |
| D3-D12 | (10 pure/view helpers) | YES | Referenced in call trees | N/A | N/A | N/A |

**Total functions: 32 (7B + 13C + 12D)**

---

## Gaps Found

**NONE.** Every function on the checklist has a corresponding analysis section in the attack report. All call trees are fully expanded to leaf functions. All storage writes are explicitly listed with line numbers. All cached-local-vs-storage checks are present with verdicts.

---

## Interrogation Log

**Q1:** "You listed _setFuturePrizePool at L387 and L336 as writes in B4's tree. Did you verify that L336's read (`_getFuturePrizePool()`) is truly fresh and not cached?"
**A1:** Yes. The Mad Genius explicitly traced that no local variable caches futurePrizePool in claimDecimatorJackpot before the call to _creditDecJackpotClaimCore. The Skeptic independently confirmed this. Verdict: SAFE.

**Q2:** "You said _processAutoRebuy returns false when gameOver is true (B7 analysis). But B7 doesn't check gameOver before calling _addClaimableEth. What if gameOver changes between _consumeTerminalDecClaim and _addClaimableEth?"
**A2:** gameOver is set to true during handleGameOverDrain (GameOverModule L111) and is never set back to false. Once set, it remains true for all subsequent calls. claimTerminalDecimatorJackpot can only execute after GAMEOVER (because _consumeTerminalDecClaim requires lastTerminalDecClaimRound.lvl != 0, which is only set during GAMEOVER). Therefore gameOver is guaranteed true when _addClaimableEth is called from B7. Verdict: SAFE.

**Q3:** "The decBucketOffsetPacked collision finding -- did you verify that _consumeTerminalDecClaim actually reads from decBucketOffsetPacked and not from a separate slot?"
**A3:** Yes. _consumeTerminalDecClaim at L881 reads `decBucketOffsetPacked[lvl]` -- the same mapping used by _consumeDecClaim at L281. The terminal decimator does NOT have its own packed offsets storage. Both claim paths share the same packed offsets. This is confirmed by both the attack report and the Skeptic review.

**Q4:** "B1's bucket migration path -- when _decRemoveSubbucket is called at L148 with prevBurn, and then _decUpdateSubbucket at L153 with prevBurn again, is the aggregate net-zero for the migration (before the new burn is added)?"
**A4:** Yes. _decRemoveSubbucket removes prevBurn from old_aggregate: `old_aggregate -= prevBurn`. _decUpdateSubbucket adds prevBurn to new_aggregate: `new_aggregate += prevBurn`. The carry-over is exact. Then the new burn delta is added at L176 via another _decUpdateSubbucket call. Net accounting is correct.

---

## Verdict: PASS

All 32 functions (7 Category B, 13 Category C, 12 Category D) are accounted for in the attack report. Call trees are fully expanded. Storage writes are mapped. Cached-local-vs-storage checks are present for all Category B and relevant Category C functions. No gaps found. No shortcuts taken.

**Coverage: 100%**

---

*Coverage review completed: 2026-03-25*
