# Phase 358: SPEC — Design-Lock + Freeze/Solvency Re-Attestation + Call-Graph Attestation - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Lock the v57.0 **open design decisions** in writing so the IMPL phase (359) authors a fully-reconciled diff with zero "by construction" assumptions, and the load-bearing freeze-safety + byte-preservation are designed BEFORE any code. Phase 358 owns **WWXRP-02** (whale-halfpass design half), **TDEC-02** (terminal-decimator design decisions), **TDEC-03** (terminal-decimator freeze-safety re-proof under the bucket-promotion allowance). Paper-only — **zero `contracts/*.sol`**. The SPEC deliverable also re-attests RNG-freeze-intact + SOLVENCY-01-byte-untouched on paper (SEC design feed) and grep-attests every cited `file:line` against the v56.0 closure HEAD `1e7a646d`.

**Not in scope here (owned downstream):** the contract edits themselves (359 IMPL), gas measurement (360), the empirical SEC/HYG proofs (361), the adversarial close (362). BATCH-01/02 and HYG-01/02 have **no open design decisions** (mechanical, pre-validated) — they appear below only as anchors the SPEC must grep-attest.

</domain>

<decisions>
## Implementation Decisions

All decisions below were verified against the live working tree (HEAD `31bc7720`, contracts identical to baseline `1e7a646d`) via four read-only code scouts during discussion. Anchors are load-bearing — re-grep at SPEC.

### TDEC — Terminal-decimator freeze-safety + gate (TDEC-03)

- **D-01 (freeze gate = `!_livenessTriggered()`, alone):** `boostTerminalDecimator()` gates on `require(!_livenessTriggered())` (+ idempotent `boosted` bit, an existing entry for the current terminal level, a live effective streak). This is SUFFICIENT — the original `!gameOver` framing was the WRONG gate (the gap that matters is between RNG **request** and resolution, not between rngWord-reveal and the gameOver flip).
- **D-02 (the freeze proof — TDEC-03 obligation):** the decimator resolution reads `rngWordByDay[gameOverDay]` (`DegenerusGameGameOverModule.sol:106`), where `gameOverDay` is the day liveness fires (e.g. `purchaseStartDay + 121` for the death-clock path). That key is keyed by the *current day* and physically cannot be written on any earlier day; on `gameOverDay` itself the day-index liveness predicate (`DegenerusGameStorage.sol:1231-1240`) is already `true` from the day's start (it is day-constant), so the first `advanceGame` routes straight into the game-over path and that is what writes the word. Therefore **any boost that passed `!liveness` necessarily occurred on an earlier day, before the resolution word could exist** — the resolution word is always a *future-day* word relative to any admitted boost. The VRF-grace-stall liveness branch is the same (the stalled day's word stays 0; the game is RNG-locked so no new daily words are written during the stall). The decimator path requires a real VRF word (`handleGameOverDrain` reverts if `rngWordByDay[day]==0`) — so there is no predictable-fallback-seed hole either. **SPEC must formally discharge this** ("the resolution word cannot exist before the boost gate closes"), not assert it.
- **D-03 (rejected refinement — recorded):** an earlier "same-day rngWord reuse" concern (gate on `rngWordByDay[currentDay]==0`) was investigated and RETRACTED — the scenario is internally inconsistent (for liveness to be true in the evening it was true that morning, so any "normal advance" that morning would already have routed to game-over; there is no separate pre-set word). **Belt-and-suspenders fallback only:** IF the SPEC's formal pass surfaces a backlog/catch-up edge where game-over processes a day whose word was pre-set, AND-in `rngWordByDay[resolutionDay]==0` cheaply. Default = `!liveness` alone (USER).

### TDEC — Terminal-decimator boost mechanics (TDEC-02 + TDEC-01 design)

- **D-04 (window = last day only):** the boost is admissible only in the final window (USER: "last day only") — a *game-design* lever (separate from freeze) that forces "streak alive to the END": you burn early (`recordTerminalDecBurn` requires `daysRemaining > 7`, `DecimatorModule:701`) then can only boost at the very end while the streak is still live. The exact `daysRemaining` threshold (`== 0` / `<= 1`) is calibrated at IMPL; conceptually it is the deadline day `purchaseStartDay + DEATH_CLOCK_DAYS` (level≠0 ⇒ +120; level 0 ⇒ +365), which is still `!liveness`. Without this the boost could be called early at streak-peak then the player goes dormant — gap-reset can't retroactively undo a past boost.
- **D-05 (bucket PROMOTION is IN — and freeze-safe under D-01/D-02):** the boost re-derives the bucket from the player's LIVE `playerActivityScore(player)` (which now includes the kept-alive quest streak), via `_terminalDecBucket(...)`. If the resulting denom is **strictly lower (= better odds)** than the frozen bucket, PROMOTE; else keep the frozen bucket. (Bucket is a function of activity score, NOT of weight — "boosted weight improves the bucket" resolves to "the live end-game activity/streak re-qualifies a better bucket", matching the original "bucket frozen too early" problem.)
- **D-06 (subBucket re-derive on promotion — forced):** `subBucket = keccak256(player, lvl, bucket) % bucket` (`DecimatorModule:559-570`) is bucket-dependent, so a promotion MUST re-derive `subBucket` (a kept old subBucket could exceed the new denom and never win). "Keep vs re-derive" is therefore settled = re-derive. Safe because it is all committed before the RNG request (D-02).
- **D-07 (re-key the aggregate; solvency conserved):** on promotion, the player's weighted contribution moves from `terminalDecBucketBurnTotal[keccak(lvl, oldBucket, oldSub)]` to `[keccak(lvl, newBucket, newSub)]` — remove from old key, add to new key — so total weight is conserved and `runTerminalDecimatorJackpot`'s shares still sum to the pool (SOLVENCY-neutral; weight-only, BURNIE/ETH path untouched).
- **D-08 (weight scaling):** multiply `weightedBurn` by `boostFactor(effectiveStreak)`, anchors **streak 100→20×, 10→4×**, 1× floor at streak 0. Candidate two-line curve (calibrated at IMPL/GAS): `factorBps = 10000 + 3000·s` for `s ≤ 10`; `40000 + (s−10)·1778` for `10 < s ≤ 100`; cap 20×. Quest streak caps at 100 (`MintStreakUtils:251`).
- **D-09 (effective-streak source = `getPlayerQuestView`):** validate via `getPlayerQuestView(player).baseStreak` (`DegenerusQuests.sol:1088`) — the EFFECTIVE streak with daily gap-reset + shields applied, NOT the raw spoofable `playerQuestStates.streak`. It is a `view` (no mutation).
- **D-10 (double-count = KEEP BOTH levers):** the quest streak ALREADY feeds burn-time weight (`MintStreakUtils:251` adds `questStreak*100` bps into `playerActivityScore`, which drives BOTH the frozen bucket and the `multBps` activity multiplier at `DecimatorModule:709-712`). The final-day boost multiplies a base that already contains streak — this stacking is **intentional** (rewards early-conviction AND sustained-to-the-end). `playerActivityScore` is left UNTOUCHED (it is shared by other systems — stripping streak from it has a large blast radius and was rejected).
- **D-11 (overflow = saturate uint88):** the boost clamps `weightedBurn` to `type(uint88).max`, matching the existing `recordTerminalDecBurn` behavior (`DecimatorModule:750-752`); the aggregate add stays consistent.
- **D-12 (shields = read-only, no consume):** the boost reads the effective streak via the `view` (shields already factored into whether the streak survived gaps); it consumes nothing. Shields are still consumed naturally by the player's normal quest actions / `_questSyncState`.
- **D-13 (idempotence + prerequisite):** one-time per terminal level via a `boosted` bit in the packed `TerminalDecEntry` (24 spare bits confirmed — `uint80 totalBurn / uint88 weightedBurn / uint8 bucket / uint8 subBucket / uint48 burnLevel` = 232/256 bits, `DegenerusGameStorage.sol:1585-1591`). Requires an existing terminal-dec burn (you scale committed weight, not buy an entry).

### WWXRP — Degenerette jackpot whale-halfpass (WWXRP-02)

- **D-14 (rationing = GLOBAL per bracket):** ONE pass per `level/10` bracket total — awarded to whoever lands the first WWXRP jackpot in that bracket; later jackpots in the same bracket award nothing. New state: `mapping(uint256 => bool) wwxrpJackpotWhalePassBracketAwarded` keyed by `level/10`, appended to `DegenerusGameStorage` (no existing WWXRP state; slot region after `whalePassClaims` @ `:973` / `lootboxEthBase` @ `:977`). NOT a global 0→5 lifetime cap (supersedes the old `PLAN-WWXRP-JACKPOT-WHALEPASS.md`).
- **D-15 (multi-bracket allow):** a single player CAN collect passes across different brackets (naturally rationed by the per-bracket flag).
- **D-16 (recipient = the bettor `player`):** the pass always accrues to the bet owner. `_resolveFullTicketBet`'s `player` is always the owner (`_resolvePlayer` validates `operatorApprovals[player][msg.sender]` then returns the owner; `DegeneretteModule:142-150`); the operator address is not in scope at the award site. Permissionless resolve is fine — `resolveBets` (`:407`, no access modifier) plus the router stubs `resolveDegeneretteBets` (`DegenerusGame.sol:902`) and `degeneretteResolve` (`:1742`) all funnel through the shared `_resolveFullTicketBet`.
- **D-17 (hook + gate):** hook at `DegeneretteModule._resolveFullTicketBet` immediately after the ETH-only `s >= 7` sDGNRS block (`:710-715`). Gate: `s == 9 && currency == CURRENCY_WWXRP (3) && amountPerTicket >= MIN_BET_WWXRP (1 ether) && !wwxrpJackpotWhalePassBracketAwarded[level/10]`. The `s == 9` jackpot check short-circuits first (1-in-10M) → zero added cost on non-jackpot spins. Award `whalePassClaims[player] += 1` directly (the cheap freeze-safe grant — skips the ETH→halfpass conversion in `_queueWhalePassClaimCore`); set the bracket flag; emit an event.
- **D-18 (freeze-safe + pre-liveness):** the award writes only an RNG-insensitive counter/flag, gated by the already-committed `s == 9` (deterministic from the committed daily `rngWord`); reuses the `claimWhalePass` future-ticket deferral → no ETH/`claimablePool` touch (SOLVENCY-neutral). It only fires pre-liveness anyway (`resolveBets` reverts on `_livenessTriggered()`, `:414`) — fully consistent with the freeze model.

### UDVT — `type Day is uint24` discipline (UDVT design feed)

- **D-19 (per-site matrix — confirmed):**
  - (1) The 3 RNG `abi.encodePacked(…day…)` sites cast `Day → uint32` to preserve the exact keccak preimage byte-image: `DegenerusGameAdvanceModule.sol:1405` (`combined, currentDay, block.prevrandao`), `:1828` (`vrfWord, gapDay`), `DegenerusGame.sol:1011` (`day, address(this)`). (All three grep-attested present at exactly these lines.)
  - (2) Packed `Sub`/struct day fields become `Day` (uint24-backed) → same slots, the v56 packed-Sub gas win intact (no cold-slot spill).
  - (3) Standalone day slots + `indexed` day event topics stay raw `uint32` (preserve the existing "uint24 packed / uint32 transient" convention; cast at `Day` boundaries).
  - (4) `rngWordByDay` mapping KEY layout unchanged (uint24/uint32 zero-pad to the same slot).
  - (5) Operator overloads `<, <=, ==, %, +, -` (final set grepped from actual day comparisons at SPEC; solc 0.8.34 supports UDVT + global operator overloads — confirm).
  - (6) Repo-wide ~649 day-bearing lines / 27 contracts (SPEC produces the exact per-site count).
- **D-20 (test-file handling):** the contract-side UDVT is part of the ONE batched USER-approved 359 diff (held for hand-review); the ~143 test-file updates land as separate **agent-committable** commits (only `contracts/*.sol` commits need approval).

### Claude's Discretion
- Exact `daysRemaining` "last day" threshold (D-04), the precise `boostFactor` curve constants (D-08), and the final operator-overload set + per-site UDVT count (D-19) — calibrated/grepped at SPEC/IMPL within the locked shapes above.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### v57.0 scope + requirements
- `.planning/REQUIREMENTS.md` — the 15 v57.0 REQ-IDs (BATCH/WWXRP/TDEC/UDVT/HYG/SEC/AUDIT); 358 owns WWXRP-02, TDEC-02, TDEC-03.
- `.planning/ROADMAP.md` §"Phase 358" — phase goal + 5 success criteria; the v57.0 posture (hard floor = RNG-freeze intact + SOLVENCY-01 byte-untouched).

### Design-lock inputs (note the corrections below)
- `.planning/PLAN-WWXRP-JACKPOT-WHALEPASS.md` — original WWXRP plan. **SUPERSEDED on rationing:** it specifies a global 0→5 lifetime cap; v57.0 uses GLOBAL-PER-BRACKET keyed `level/10` (D-14). Also note `matches == 8` in the plan = the relabeled `s == 9` in current code.
- `.planning/PLAN-TERMINAL-DECIMATOR-STREAK-BOOST.md` — original terminal-decimator plan (weight-only). Its "Verify before build" list (raw-vs-effective streak, shields, uint88, double-count) is resolved by D-09/D-12/D-11/D-10. Its caveat "a future variant that lets the boost improve the BUCKET/odds would need a hard timing buffer … out of scope here" is now **IN scope and resolved** by D-01/D-02/D-05 (the `!liveness` gate IS the timing buffer).

### Source anchors (re-grep vs `1e7a646d` at SPEC — SC5)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `_resolveFullTicketBet:614`, score `s` @ `:674`, jackpot `s==9`, ETH-only sDGNRS `s>=7` block `:710-715`, `CURRENCY_WWXRP=3` @ `:216`, `MIN_BET_WWXRP=1 ether` @ `:225`, `resolveBets:407` (reverts on liveness `:414`), `_resolvePlayer:142-150`.
- `contracts/modules/DegenerusGameDecimatorModule.sol` — `recordTerminalDecBurn:693` (bucket freeze `:726`), `_decSubbucketFor:559-570`, `_terminalDecBucket:925-936`, `_terminalDecMultiplierBps:916`, `runTerminalDecimatorJackpot:780`, `claimTerminalDecimatorJackpot:836`, deadline `_terminalDecDaysRemaining:939-950`, burn gate `:701`, `terminalDecBucketBurnTotal` key `keccak(lvl,bucket,subBucket)` @ `:755`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `_handleGameOverPath` liveness gate `:591`, `_gameOverEntropy:1289`, `_applyDailyRng` write `rngWordByDay[day]=finalWord:1879`, `handleGameOverDrain` call `:665-670`; UDVT encodePacked sites `:1405`, `:1828`; HYG-02 stale comment `_runRewardJackpots` @ `:1191`.
- `contracts/modules/DegenerusGameGameOverModule.sol` — `handleGameOverDrain:86`, `rngWord = rngWordByDay[day]:106` (reverts if 0), `gameOver = true:145`, `runTerminalDecimatorJackpot(decPool,lvl,rngWord):174-183`.
- `contracts/storage/DegenerusGameStorage.sol` — `_livenessTriggered:1231-1240`, `rngWordByDay:454`, `whalePassClaims:973`, `TerminalDecEntry:1585-1591` (24 spare bits), WWXRP-state insertion neighborhood `~:977`.
- `contracts/DegenerusGame.sol` — UDVT encodePacked site `:1011`; resolve router stubs `resolveDegeneretteBets:902`, `degeneretteResolve:1742`, `_degeneretteResolveBet:1900`; `rngWordForDay:2547`.
- `contracts/DegenerusQuests.sol` — `getPlayerQuestView:1088`, `PlayerQuestState:277-290`, shields `awardQuestStreakShield:409-415` / consume `_questSyncState:1440-1451`; BATCH-01 inline `creditFlip(player, burnieMintReward)` @ `:947-949`.
- `contracts/utils/MintStreakUtils.sol` (a.k.a. `DegenerusGameMintStreakUtils.sol`) — quest-streak → activity score `:251`.
- BATCH-01 caller fold — `contracts/DegenerusGameMintModule.sol:1220` (return-fold) + `:1355` (single `lootboxFlipCredit` credit). **Pre-validated; re-grep at SPEC.**
- HYG-01 stale `gameSetAutoRebuy` refs — `test/unit/GovernanceGating.test.js:247`, `test/unit/DegenerusVault.test.js:385/456` (also `gameSetAutoRebuyTakeProfit` @ `:453/456`), `test/fuzz/CoverageGap222.t.sol:1055/1060/1084/1085` (rename target `coinSetAutoRebuy(true, 0)`).
- HYG-02 — `DegenerusGameAdvanceModule.sol:1191` (`_runRewardJackpots`) confirmed; **DRIFT to re-check:** the second cited site `DegenerusGameDegeneretteModule.sol:809` did NOT match a `_runRewardJackpots` grep — the requirement also names `EndgameModule`, so that comment likely reads `EndgameModule`. SPEC must re-attest the exact text/line.

### Governing audit memory (background)
- `threat-model-reentrancy-mev-nonissues` — DOMINANT concern = RNG/freeze; SOLVENCY = the spine. Treat the TDEC-03 proof as load-bearing.
- `type-day-udvt-post-v56-seed`, `handlepurchase-burnie-flip-batching-post-v56-seed`, `wwxrp-jackpot-whalepass-seed`, `terminal-decimator-final-day-streak-boost-seed`, `v57-bundle-udvt-milestone`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`whalePassClaims[player] += 1` direct grant** (`DegenerusGameStorage.sol:973`; conversion logic `DegenerusGamePayoutUtils.sol:44-61`) — the cheap freeze-safe whale-pass grant; reused by WWXRP (D-17). Player materializes via the existing `claimWhalePass()` flow — no UI change.
- **`getPlayerQuestView(player).baseStreak`** (`DegenerusQuests.sol:1088`) — the canonical effective-streak accessor (gap-reset + shields), a `view` callable from the decimator boost (D-09).
- **`_terminalDecBucket` / `_decSubbucketFor` / `terminalDecBucketBurnTotal`** (`DecimatorModule:925-936 / 559-570 / :755`) — reused by the boost to recompute+re-key on promotion (D-05/D-06/D-07).
- **`TerminalDecEntry` 24 spare bits** (`DegenerusGameStorage.sol:1585-1591`) — host the `boosted` idempotence bit (D-13).

### Established Patterns
- **Freeze invariant = no player-controlled mutation between VRF REQUEST and resolution** (`threat-model-reentrancy-mev-nonissues`). The decimator resolution requires a real VRF word (`handleGameOverDrain` reverts on `rngWordByDay[day]==0`) — no deterministic-fallback hole. `!liveness` is the boost's correct gate (D-01/D-02).
- **Permissionless resolve, owner-credited** — `resolveBets`/router stubs are callable by anyone; payouts always accrue to `player` (the bettor) via `_resolvePlayer` (D-16).
- **uint88 saturation on weighted burn** — `recordTerminalDecBurn:750-752` clamps; the boost mirrors it (D-11).
- **v56 packed-Sub uint24 gas win** — the UDVT must not spill packed day fields to cold slots (D-19 item 2; proven gas-neutral at 360).

### Integration Points
- WWXRP award injects into the per-spin loop of `_resolveFullTicketBet` (the shared chokepoint for all resolve entrypoints).
- `boostTerminalDecimator()` is a NEW player-initiated entrypoint on `DegenerusGameDecimatorModule` (router stub on `DegenerusGame`), writing only decimator aggregates/entry + reading `getPlayerQuestView` + `playerActivityScore` + `_livenessTriggered`.
- UDVT touches the day-bearing surface repo-wide; the RNG-entropy boundary (3 encodePacked sites) is the only freeze-sensitive integration.

</code_context>

<specifics>
## Specific Ideas

- USER explicitly steered the terminal-decimator gate to liveness ("this boost should be stopped when liveness is dead, so that happens before the rng request that would determine all this") and reframed the freeze question as the general rule ("if the number or bucket was manipulable between rng request and decimator resolution that would violate the rules") — promotion is NOT special, the standard pre-request freeze gate covers both weight and bucket. This is the spine of TDEC-03.
- USER wants resolve to stay permissionless ("anyone should be able to resolve degenerette bets … but the winnings should always accrue to the bettor") — confirmed already true in code.
- USER directive (carried from milestone init): the terminal-decimator boost should also PROMOTE the bucket, not only raise the within-bucket share — now feasible + freeze-safe (D-05).

</specifics>

<deferred>
## Deferred Ideas

- Generalized operator-spend of `claimableWinnings` (carried from v54/v55/v56) — out of scope; separate optional feature (`.planning/REQUIREMENTS.md` Future Requirements).
- The v52 consolidated cross-model audit — a SEPARATE future track; v57's surface folds into it as an addition, not a substitute for v57's own in-milestone close.
- Confirmed NON-ISSUES (NOT work): O1 quest lootbox double-credit (already credited once), the `resolveLootboxRoll` dead branch, the `_runRewardJackpots` module misplacement (only the 2 stale comments remain → HYG-02), and the 4 older balance notes.

None of the above are gray areas for 358 — discussion stayed within the WWXRP-02 / TDEC-02 / TDEC-03 design-lock scope.

</deferred>

---

*Phase: 358-spec-design-lock-freeze-solvency-re-attestation-call-graph-a*
*Context gathered: 2026-06-04*
