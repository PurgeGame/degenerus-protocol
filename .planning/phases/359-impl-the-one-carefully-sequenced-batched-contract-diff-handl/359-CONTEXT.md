# Phase 359: IMPL — The ONE Carefully-Sequenced Batched Contract Diff (handlePurchase batching + WWXRP whale-halfpass + terminal-decimator boost + the wide UDVT refactor) - Context

**Gathered:** 2026-06-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Author the SINGLE reconciled `contracts/*.sol` diff for v57.0 — the 11 IMPL-owned REQ-IDs (**BATCH-01/02 · WWXRP-01 · TDEC-01 · UDVT-01/02/03 · BURNIE-01/02 · SALVAGE-01 · CANCEL-01**) — producer-before-consumer, applied to `contracts/` and locally compiling (`forge build` clean), then **HELD at the contract-commit boundary for explicit USER hand-review**. This is THE one contract gate of the milestone (the HARD STOP). The UDVT is the heavy item and dominates effort; BURNIE is the highest-severity item (a Critical loss-of-funds fix).

**ALL design is LOCKED upstream in `358-SPEC.md`** (D-01..D-33 + the UDVT byte-preservation discipline D-19/D-20 + the IMPL/TDEC Handoff Invariants). This phase does NOT re-open any design decision. The discussion below captured only the **execution-strategy** decisions the SPEC left open — how to sequence/author/verify the batched diff for a tractable hand-review.

**Not in scope here (owned downstream):** gas measurement + tuning (360 — the UDVT gas-neutrality gate), the empirical SEC-01/02 + HYG + SALVAGE-03/CANCEL-03 proofs (361 TST), the delta-audit + 3-skill adversarial close (362 TERMINAL). The ~143 Hardhat JS test-file UDVT updates are AGENT-committable (separate commits, per SPEC D-20) — only `contracts/*.sol` commits need explicit approval.

</domain>

<decisions>
## Implementation Decisions

> Scope of THIS discussion = **edit-ordering / execution strategy only** (the single gray area the USER selected). Every WHAT/WHY/freeze/solvency decision is already locked in `358-SPEC.md` and is NOT restated here.

### Edit-Ordering Strategy (discussed + locked this session)

- **D-01 (top-level order = FEATURES-FIRST, UDVT LAST):** Author + self-verify all 7 behavior features against the FROZEN audited `1e7a646d` tree FIRST (each feature reasoned against the known-good, already-audited baseline), THEN run ONE mechanical `type Day` UDVT sweep over the whole surface. Rationale (USER): behavior correctness is reasoned against the sacred audited baseline; the UDVT is a single isolated final transformation. Trade-off accepted: the UDVT sweep re-touches the feature hunks, so the 361 per-site byte-diff gate must account for the swept feature code too (the 3 freeze-critical `abi.encodePacked` sites are all in PRE-EXISTING code, so UDVT-02's load-bearing gate is well-defined regardless).

- **D-02 (intra-features order = BY SEVERITY, then BY FILE):** Within the features-first block:
  1. **BATCH-01/02** (the producer — `DegenerusQuests.handlePurchase` returns `burnieMintReward` instead of crediting inline at `:947-949`; the misleading `ethMintReward`/"ETH mint reward" naming corrected to quest-TYPE semantics).
  2. **BURNIE-01/02** (the Critical fix — first and isolated for clean review; `_purchaseCoinFor` queue-on-return + the MINT_BURNIE burn-rebate). This is the **consumer** of BATCH-01's returned reward → producer-before-consumer satisfied.
  3. **SALVAGE-01** (the 2nd functional-solvency item; same `DegenerusGameMintModule.sol` file → opened once with BURNIE).
  4. **WWXRP-01 + TDEC-01 + CANCEL-01** (the clean RNG-insensitive / BURNIE-emission items, any order).
  Highest-risk behavior is reviewed first; `MintModule` is opened once for BURNIE+SALVAGE together.

- **D-03 (compile cadence = TWO CHECKPOINTS):** `forge build` green ONCE after all 7 features are authored, then `forge build` green ONCE after the UDVT sweep. Fewest cycles (USER choice). Worktrees OFF, sequential-on-main (submodule + node_modules make worktrees unsafe — `use_worktrees: false`, `no_worktree_paths: [contracts]`).

- **D-04 (UDVT sweep RETYPES THE NEW FEATURE CODE TOO):** The final UDVT pass converts day-handling in the just-added feature code as well — the whole tree ends consistent `type Day` with NO raw-int islands. The new features' day surface is minimal (WWXRP keys on `level/10`, a LEVEL bracket not a Day; TDEC/SALVAGE read days via existing helpers; CANCEL touches packed `Sub` day fields), so the added churn is small.

- **D-05 (forge-test compile coupling — RECORDED ASSUMPTION):** The "two checkpoints" gate is `forge build`, and Foundry compiles `test/*.t.sol` in the same build. Therefore the forge fuzz-test (`.t.sol`) files that call day-typed contract signatures MUST be updated **as part of reaching the green post-UDVT `forge build`** (they land in/with the UDVT sweep step). The ~143 Hardhat JS test updates do NOT affect `forge build` and lag as **separate agent-committable commits** (SPEC D-20). The USER chose to leave this at planner discretion (declined a dedicated turn) — recorded here so the planner sizes the UDVT step to include the forge-test signature churn needed for the build to pass.

### Design — LOCKED upstream (NOT re-opened; the IMPL author MUST preserve)

All of the following are FIXED in `358-SPEC.md`; the IMPL author implements them verbatim. The load-bearing code-level invariants the author MUST preserve (re-proven at TST 361):

- **TDEC Handoff Invariants 1–5** (SPEC §TDEC-03 Step 8): boost gate is EXACTLY `require(!_livenessTriggered())` (NOT `!gameOver`) + the `boosted`-bit/existing-entry/live-streak preconditions; the bucket-promotion + subBucket re-derive + aggregate re-key are a single atomic in-tx mutation under the gate; the re-key REMOVES the exact pre-boost weighted contribution from the old `terminalDecBucketBurnTotal` key and ADDS the post-boost contribution to the new key (net conservation); the boost reads the effective streak via the `getPlayerQuestView` VIEW only (no mutation/shield-consume); the `boosted` bit makes it one-time per terminal level.
- **Small-feature IMPL Handoff Invariants 1–8** (SPEC §"IMPL Handoff Invariants — small features"): WWXRP recipient = bettor `player` (never `msg.sender`), `s==9` short-circuit FIRST; WWXRP rationing flag keyed by `level/10` (set-on-win, idempotent per bracket); BURNIE queue-on-return + ETH/pool DEBIT byte-unchanged; BURNIE producer-before-consumer + full-cost affordability gate upfront + deferred net burn (rebate ≤ full cost, never a separate `creditFlip`); SALVAGE BURNIE leg TRANSFERRED from sDGNRS-owned BURNIE (never `creditFlip`-minted) with `actualBurnie = min(target, available)` + ETH remainder/fallback + `ethOut ≤ ethCap`; SALVAGE preview parity (reflects source-availability + fallback; randomness source stays the settled prior-day word, no new VRF); CANCEL auto-claim ordering (pay self + drain tree 75/20/5 BEFORE `_finalizeAfking`+clear); CANCEL forfeit explicitness (auto-evict paths MUST `delete _subOf[player]`).
- **UDVT byte-preservation discipline** (SPEC §UDVT, D-19 items 1–6): the 3 `abi.encodePacked(…day…)` entropy sites cast `Day → uint32` (`DegenerusGameAdvanceModule.sol:1405` + `:1828`, `DegenerusGame.sol:1011`); packed `Sub`/struct day fields stay uint24-backed (no cold-slot spill — the v56 gas win); standalone day slots + `indexed` day event topics stay raw `uint32` (cast at boundaries); `rngWordByDay` mapping KEY (`mapping(uint32 => uint256)` @ `DegenerusGameStorage.sol:454`) unchanged; operator overloads from `{<, <=, ==, %, +, -}` (final set grepped from real day comparisons); solc 0.8.34 supports UDVT + global operator overloads.

### Claude's Discretion (explicitly delegated by the SPEC — calibrate at IMPL within the locked shapes; final tuning at 360 GAS)

- The precise `boostFactor` curve constants (SPEC D-08 — anchors streak 100→20×, 10→4×, 1× floor; candidate two-line bps curve given, exact constants discretionary).
- The exact last-day `daysRemaining` threshold (`== 0` vs `<= 1`) within the locked last-day window (SPEC D-04).
- The within-day variability granularity of the SALVAGE offer (SPEC D-27 — may mix a within-day component into the seed AS LONG AS every offer stays previewable + ≤ the no-arb ceiling + the eth-% cap; randomness source stays the settled prior-day word, no new VRF).
- The final operator-overload SET + the exact per-site UDVT count (SPEC D-19 items 5/6 — grepped from the actual day comparisons at IMPL; ~649 lines / 27 contracts is the design estimate).
- Plan/wave decomposition granularity (the USER declined a dedicated turn; left at planner discretion — sequential-on-main, worktrees off).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### LOCKED design (read FIRST — this is the contract for the whole phase)
- `.planning/phases/358-spec-design-lock-freeze-solvency-re-attestation-call-graph-a/358-SPEC.md` — **the v57.0 design-lock SPEC, LOCKED.** Every IMPL decision (D-01..D-33 + the UDVT discipline + the TDEC/small-feature Handoff Invariants + the freeze/solvency re-attestation + the **Full Call-Graph Grep-Attestation table vs `1e7a646d`** with every `file:line` anchor confirmed/reconciled). MUST be read before authoring any code. The IMPL has zero un-checked assumptions because of it.
- `.planning/phases/358-spec-design-lock-freeze-solvency-re-attestation-call-graph-a/358-CONTEXT.md` — the SPEC's own decision record (D-01..D-33 narrative) + the grouped source-anchor lists per feature (Degenerette/WWXRP, Decimator/TDEC, Advance/GameOver/RNG, Quests/BATCH, BURNIE coin-buy, SALVAGE swap, CANCEL afking) — the IMPL target anchors.

### v57.0 scope + requirements
- `.planning/REQUIREMENTS.md` — the 25 v57.0 REQ-IDs; 359 owns BATCH-01/02, WWXRP-01, TDEC-01, UDVT-01/02/03, BURNIE-01/02, SALVAGE-01, CANCEL-01.
- `.planning/ROADMAP.md` §"Phase 359" — phase goal + the contract-boundary HARD STOP posture (hard floor = RNG-freeze intact + SOLVENCY-01 byte-untouched; the one contract gate at 359; `ContractAddresses.sol` freely modifiable; tests/docs agent-committable).

### Source anchors (the IMPL edit targets — full grep-attested table lives in 358-SPEC §"Full Call-Graph Grep-Attestation")
- `contracts/DegenerusQuests.sol` — BATCH-01 inline `creditFlip(player, burnieMintReward):947-949` (→ return), `getPlayerQuestView:1088`.
- `contracts/modules/DegenerusGameMintModule.sol` — BATCH caller fold `:1220`/credit `:1355`; BURNIE `_purchaseCoinFor:887-907` + payInCoin branch `:1545-1555` + `handlePurchase` call `:1210-1217` + `_ethToBurnieValue:1657`; SALVAGE `sellFarFutureTickets:929` + relabel `:976-977` + SDGNRS floor `:958` + ticket leg `:983`.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — WWXRP hook at `_resolveFullTicketBet:614` after the ETH-only `s>=7` block `:713-715`; score `s:674`; `CURRENCY_WWXRP=3:216`; `MIN_BET_WWXRP=1 ether:225`; `resolveBets:407` (liveness revert `:413`); `_resolvePlayer:142-150`.
- `contracts/modules/DegenerusGameDecimatorModule.sol` — TDEC: new `boostTerminalDecimator()`; reuse `recordTerminalDecBurn:693`, `_terminalDecBucket:925-936`, `_decSubbucketFor:559-570`, `terminalDecBucketBurnTotal:755`, `runTerminalDecimatorJackpot:780`, `_terminalDecDaysRemaining:939-950`, uint88 saturate `:750-752`.
- `contracts/modules/GameAfkingModule.sol` — CANCEL: manual cancel `:345-362` (false comment `:348-351`, finalize `:353`, tombstone `:354`), `rngLock` gate `:300`, `_finalizeAfking:1026`, tombstone-reclaim delete `:1148`, pass-expiry evict `:1175-1187`, funding-out evict `:1240-1252`, `claimAfkingBurnie:1560` (CEI `:1574`), `drainAffiliateBase:1605`.
- `contracts/storage/DegenerusGameStorage.sol` — new `wwxrpJackpotWhalePassBracketAwarded` mapping (append after `whalePassClaims:973`/`lootboxEthBase:977`); `TerminalDecEntry:1585-1591` (24 spare bits → `boosted`); `_livenessTriggered:1231-1240`; `rngWordByDay:454` (UDVT key unchanged); `Sub.affiliateBase:1952`/`pendingBurnie:1960`; `_queueTicketsScaled:612`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — UDVT encodePacked sites `:1405`/`:1828`; freeze spine (`_handleGameOverPath:591`, `_gameOverEntropy:1289`, `_applyDailyRng:1879`, `_backfillGapDays:1817`).
- `contracts/DegenerusGame.sol` — UDVT encodePacked site `:1011`; router stubs `purchaseCoin:660`, `sellFarFutureTickets:2074`, `resolveDegeneretteBets:902`/`degeneretteResolve:1742`/`_degeneretteResolveBet:1900`, `claimAfkingBurnie:413`, `mintPrice:2539`; new TDEC `boostTerminalDecimator` router stub.
- `contracts/modules/DegenerusGameGameOverModule.sol` — `handleGameOverDrain:86`, `rngWord:106`, `gameOver=true:145`, decimator draw `:174`.
- `contracts/utils/DegenerusGameMintStreakUtils.sol` — SALVAGE `_quoteFarFutureSwap:145-190` (seed `:160-163`, jitter `:165`, ticketShareBps `:166`, cashWei `:190`), `_farFutureFractionBps:127-130`; quest-streak→activity `:251-252`.
- `contracts/BurnieCoin.sol` (`transfer:315`/`transferFrom:329`), `contracts/BurnieCoinflip.sol` (`creditFlip:859`, `previewClaimCoinflips:927`, `coinflipAmount:934`, `consumeCoinflipsForBurn:366`, stake-consume `:904-912`), `contracts/DegenerusAffiliate.sol` (`claim:629` 75/20/5, `_referrerAddress:809`), `contracts/DegenerusVault.sol` (`gamePurchaseTicketsBurnie:571-574`).

### Design-lock inputs (note the SPEC corrections)
- `.planning/PLAN-WWXRP-JACKPOT-WHALEPASS.md` — **SUPERSEDED on rationing** (global `0→5` lifetime cap → GLOBAL-PER-BRACKET `level/10`, D-14; `matches==8` = the relabeled `s==9`).
- `.planning/PLAN-TERMINAL-DECIMATOR-STREAK-BOOST.md` — original weight-only plan; its "improve the BUCKET would need a hard timing buffer" caveat is now IN scope + resolved (the `!liveness` gate IS the buffer; SPEC D-01/D-02/D-05).

### Governing audit memory (background)
- `threat-model-reentrancy-mev-nonissues` — DOMINANT = RNG/freeze; SOLVENCY = the spine. The TDEC-03 future-day-word lemma + the UDVT byte-image are load-bearing.
- `v57-bundle-udvt-milestone`, `type-day-udvt-post-v56-seed`, `handlepurchase-burnie-flip-batching-post-v56-seed`, `wwxrp-jackpot-whalepass-seed`, `terminal-decimator-final-day-streak-boost-seed`, `lean-code-comments-no-procedural-meta`, `only-contract-commits-need-approval`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`whalePassClaims[player] += 1` direct grant** (`DegenerusGameStorage.sol:973`) — the cheap freeze-safe whale-pass grant reused by WWXRP (materializes via the existing `claimWhalePass()` deferral — no UI change).
- **`getPlayerQuestView(player).baseStreak`** (`DegenerusQuests.sol:1088`) — the canonical effective-streak (gap-reset + shields) VIEW the TDEC boost reads (D-09).
- **`_terminalDecBucket` / `_decSubbucketFor` / `terminalDecBucketBurnTotal`** (`DecimatorModule:925-936 / 559-570 / :755`) — reused by the boost to recompute + re-key on promotion.
- **`TerminalDecEntry` 24 spare bits** (`DegenerusGameStorage.sol:1585-1591`) — host the `boosted` idempotence bit.
- **`claimAfkingBurnie` CEI mirror + `drainAffiliateBase`** (`GameAfkingModule.sol:1560`/`:1605`) — the self-pay + upline-tree-drain parity the CANCEL auto-claim mirrors.
- **`_quoteFarFutureSwap` settled-prior-day-word jitter** (`MintStreakUtils.sol:145-190`) — the existing v48 pattern the SALVAGE ETH/BURNIE split extends with one more derived seed slice (no new VRF).

### Established Patterns
- **Freeze invariant = no player-controlled mutation between VRF REQUEST and resolution.** The boost gate is `!_livenessTriggered()` (closes strictly before the `gameOverDay` word is born — the future-day-word lemma, SPEC TDEC-03).
- **Permissionless resolve, owner-credited** — `resolveBets`/router stubs callable by anyone; WWXRP award always accrues to `player` (the bettor) via `_resolvePlayer`.
- **uint88 saturation on weighted burn** — the boost mirrors `recordTerminalDecBurn:750-752`.
- **Producer-before-consumer** — BATCH-01 makes `handlePurchase` RETURN the reward; the ETH caller folds it into `lootboxFlipCredit` (`:1220`/`:1355`), the BURNIE coin caller nets it against the deferred burn (the new consumer).
- **v56 packed-Sub uint24 gas win** — the UDVT must not spill packed day fields to cold slots (proven gas-neutral at 360).

### Integration Points
- WWXRP award injects into the per-spin loop of `_resolveFullTicketBet` (the shared chokepoint for all resolve entrypoints).
- `boostTerminalDecimator()` is a NEW player-initiated entrypoint on `DecimatorModule` (router stub on `DegenerusGame`), writing only decimator aggregates/entry + reading `getPlayerQuestView` + `playerActivityScore` + `_livenessTriggered`.
- The UDVT touches the day-bearing surface repo-wide; the RNG-entropy boundary (the 3 encodePacked sites) is the only freeze-sensitive integration.
- Frozen-subject guard: `git diff --quiet 1e7a646d HEAD -- contracts/` is CLEAN at phase start — every anchor is read-equivalent to the audited baseline.

</code_context>

<specifics>
## Specific Ideas

- The USER is the hand-reviewer at the contract-commit HARD STOP — the features-first/UDVT-last ordering (D-01) + the by-severity intra-order (D-02) were chosen so the highest-risk behavior (the Critical BURNIE fix + the 2 functional-solvency exceptions) is authored against the sacred audited baseline and reviewed first, before the wide mechanical UDVT churn.
- "Two checkpoints" (D-03) over per-feature compiles — the USER prefers fewer `forge build` cycles; the planner sizes the UDVT step to include the forge `.t.sol` day-signature churn so the post-UDVT build is green (D-05).
- The whole tree ends consistent `type Day` (D-04) — no raw-int islands in the just-added feature code.

</specifics>

<deferred>
## Deferred Ideas

- Hand-review structuring (logical commit grouping / a review map separating mechanical churn from behavior hunks) — the USER chose "ready for context" rather than open this; left at planner/Claude discretion within the locked SPEC. The by-severity/by-file authoring order (D-02) already gives a natural review grouping.
- Generalized operator-spend of `claimableWinnings` (carried from v54/v55/v56) — out of scope; separate optional feature (`.planning/REQUIREMENTS.md` Future Requirements).
- The v52 consolidated cross-model audit — a SEPARATE future track; v57's surface folds into it as an addition, not a substitute for v57's own in-milestone close (362).

None of the above are gray areas for 359 — the discussion stayed within the edit-ordering / execution-strategy scope (all design locked by 358-SPEC).

</deferred>

---

*Phase: 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl*
*Context gathered: 2026-06-04*
