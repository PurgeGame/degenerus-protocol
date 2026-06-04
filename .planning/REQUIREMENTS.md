# Requirements — v57.0 Small-Feature Bundle + Day-Type UDVT Refactor

> **Baseline:** v56.0 HEAD — frozen contract subject `1e7a646d`, closure `MILESTONE_V56_AT_HEAD_1e7a646d44da4ee26375edd0b006274821fef73e`.
> **Design-lock inputs:** `.planning/PLAN-WWXRP-JACKPOT-WHALEPASS.md` · `.planning/PLAN-TERMINAL-DECIMATOR-STREAK-BOOST.md` · the `type-day-udvt-post-v56-seed` + `handlepurchase-burnie-flip-batching-post-v56-seed` memories. All 5 items were PRE-VALIDATED READ-ONLY against the live `1e7a646d` tree on 2026-06-04 (verdicts + corrections folded in below).
> **Scope (USER-locked 2026-06-04):** bundle ALL of — (1) `handlePurchase` BURNIE-flip batching, (2) the WWXRP jackpot whale-halfpass, (3) the terminal-decimator final-day streak boost, (4) test/comment hygiene, (5) the repo-wide `type Day is uint24` UDVT — into ONE milestone, ONE carefully-sequenced batched contract diff. The UDVT is the heavy item and dominates IMPL/TST.
> **Posture:** Hard floor on EVERY item = RNG-freeze intact + SOLVENCY-01 byte-untouched (each change is BURNIE-credit / weight-only / pure-annotation, OFF the ETH/`claimablePool` path). Carefully-sequenced batched USER-APPROVED contract diff (HARD STOP at the contract-commit boundary — only contract commits need approval; docs/tests run hands-off); sequential-on-main (worktrees unsafe: submodule + node_modules); pre-launch redeploy-fresh (storage break fine). FULL close (internal 3-skill genuine-parallel sweep IN-MILESTONE at TERMINAL, like v54/v55/v56). The v52 consolidated cross-model audit stays a SEPARATE future track.

---

## v57.0 Requirements

### BATCH — handlePurchase BURNIE-flip batching (manual path)
- [ ] **BATCH-01**: `DegenerusQuests.handlePurchase` returns `burnieMintReward` in `totalReturned` instead of crediting it inline (`coinflip.creditFlip(player, burnieMintReward)` at `DegenerusQuests.sol:947-949` dropped); the sole caller `DegenerusGameMintModule.sol:1220` already folds the full return into `lootboxFlipCredit` (single credit `:1355`) → same recipient + same amount + additive accumulator = behavior-equivalent, saving one cross-contract `creditFlip` (~5–25k gas) per buy that completes a MINT_BURNIE quest. The afking path is unaffected (it never calls `handlePurchase`).
- [ ] **BATCH-02**: The misleading `ethMintReward` / "ETH mint reward" naming + comments are corrected to reflect quest-TYPE semantics — `MINT_ETH`/`LOOTBOX`/`MINT_BURNIE` are quest TYPE constants and ALL quest rewards pay BURNIE flip stake; no payout is ETH.

### WWXRP — Degenerette jackpot whale-halfpass
- [ ] **WWXRP-01**: A player who hits the Degenerette jackpot (`s == 9` — the 8-match jackpot is relabeled S=9 in current code) on a `currency == CURRENCY_WWXRP` (=3) bet with `amountPerTicket >= MIN_BET_WWXRP` is awarded a Whale halfpass via `whalePassClaims[player] += 1`, **rationed to one award per 10-level bracket** (a per-bracket award flag keyed by `level/10` — USER override 2026-06-04, REPLACING the old plan's global "first 5 ever" 0→5 lifetime cap). Hook: `DegeneretteModule._resolveFullTicketBet` (~:713, after the existing s≥7 sDGNRS award; `player`/`currency`/`amountPerTicket` in scope). New `wwxrpJackpotWhalePass*` per-bracket state in `DegenerusGameStorage`.
- [ ] **WWXRP-02**: The award is freeze-safe and cheap — it writes only an RNG-insensitive counter/mapping, gated by `s==9` (already deterministically derived from the committed `rngWord`), reuses the existing `claimWhalePass` future-ticket deferral (no ETH/`claimablePool` touch), and short-circuits to zero added cost on non-jackpot spins. The per-bracket rationing key and the operator-placed-bet recipient policy (pass to `player` = bet owner vs operator; whether one player may win multiple brackets) are settled at SPEC.

### TDEC — Terminal-decimator final-day streak boost
- [ ] **TDEC-01**: A new `boostTerminalDecimator()` lets a player on the final day multiply their terminal-decimator `weightedBurn` by their effective quest-streak factor (streak 100→20×, 10→4×), folding the delta into `terminalDecBucketBurnTotal[key]` via the existing `keccak256(abi.encode(lvl, bucket, subBucket))` key. **The boost ALSO updates the player's bucket if the boosted `weightedBurn` qualifies for an IMPROVED (better) bucket** — i.e. the boost can PROMOTE the bucket, not only raise the share within the originally-recorded bucket (USER directive 2026-06-04). The exact "improvement" rule (what makes a bucket better) + whether the `subBucket` is kept or re-derived on a bucket promotion are settled at SPEC. Mechanism reuses the live `DegenerusGameDecimatorModule` machinery (`recordTerminalDecBurn` / `runTerminalDecimatorJackpot` / `_terminalDecMultiplierBps`).
- [ ] **TDEC-02**: The streak is validated via `getPlayerQuestView` (the EFFECTIVE streak with daily gap-reset + shields applied) — NOT the raw stored `playerQuestStates.streak`, which is stale/spoofable; the boost is idempotent via a `boosted` bit added to the packed `TerminalDecEntry` (24 spare bits), overflow-safe under `uint88 weightedBurn` (base × time-mult ≤20× × boost ≤20× ≈ 400× base — saturate or prove headroom), and the double-count policy against the existing burn-time `multBps` streak lever is resolved at SPEC (keep both levers vs strip streak from burn-time); shields consume-vs-read is decided at SPEC.
- [ ] **TDEC-03**: The boost (and any bucket promotion under TDEC-01) is freeze-safe and solvency-neutral — it is weight-only, gated by `require(!gameOver)`, and lands in the SAME tx BEFORE `gameOver` flips and before subbuckets are drawn from `rngWord`. The boosted weight + any improved bucket are DETERMINISTIC from the player's fixed effective-streak factor × their burn, committed before any randomness is revealed → the player cannot use draw knowledge to manipulate placement (the freeze-safety argument is "all weight/bucket mutation precedes the draw", NOT "the bucket is immutable" — since TDEC-01 now allows promotion, the validator's original `subBucket`-fixed simplification no longer holds and SPEC must re-prove freeze-safety under the promotion allowance). The pool is still finalized in the resolution tx and shares still sum to the pool.

### UDVT — `type Day is uint24` repo-wide
- [ ] **UDVT-01**: A `type Day is uint24` user-defined value type with global operator overloads (`<`, `<=`, `==`, `%`, `+`, `-`) replaces the raw day-counter integers across the day-bearing contract surface (~649 lines / 27 contracts — heaviest DegenerusQuests/GameAfkingModule/DegenerusGameStorage/AdvanceModule/BoonModule), improving type-safety with zero behavior change. solc 0.8.34 supports UDVT + operator overloads (confirmed).
- [ ] **UDVT-02**: The RNG byte-image is preserved bit-for-bit — every `abi.encodePacked(…day…)` RNG-entropy site (`DegenerusGameAdvanceModule.sol:1828` + `:1405`, `DegenerusGame.sol:1011`) explicitly casts the day to `uint32` (the seed's "pure annotation" assumption is FALSE here: an unwrapped uint24-backed `Day` would shorten the keccak preimage and change the derived word); the `rngWordByDay` mapping KEY layout is unchanged (uint24/uint32 zero-pad to the same slot). Enforced by a per-site RNG-freeze byte-diff gate.
- [ ] **UDVT-03**: Storage layout + gas are preserved — packed `Sub`/struct day fields stay uint24-backed (no cold-slot spill → the v56 gas win intact), while standalone day slots + `indexed` day event topics widen to `uint32` explicitly; the forge/Hardhat suite is NON-WIDENING vs the `1e7a646d` baseline (every pre-existing red enumerated BY NAME).

### HYG — Test/comment hygiene (no contract logic change)
- [ ] **HYG-01**: The stale `gameSetAutoRebuy` references are fixed to `coinSetAutoRebuy(true, 0)` (renamed, two args, `onlyVaultOwner`) across the suites that error on the missing ABI member — `test/unit/GovernanceGating.test.js:247`, `test/unit/DegenerusVault.test.js:385/456`, `test/fuzz/CoverageGap222.t.sol:1055/1060/1084/1085` — restoring the intended `onlyVaultOwner`-rejects-non-majority assertions.
- [ ] **HYG-02**: The two stale `_runRewardJackpots` / `EndgameModule` comment references are corrected to `_consolidatePoolsAndRewardJackpots` (`DegenerusGameAdvanceModule.sol:1191`, `DegenerusGameDegeneretteModule.sol:809`); the reward-jackpot resolution is already inlined there (validated — no code change, comment-only).

### SEC — Security floor (the hard gate)
- [ ] **SEC-01**: RNG-freeze is intact across all five items — no new player-manipulable read/write of VRF-derived state: the UDVT `abi.encodePacked` sites preserve the exact byte-image (UDVT-02), the WWXRP grant + the terminal-decimator boost touch only RNG-insensitive counters/weights gated by already-committed outcomes, and `handlePurchase` batching is BURNIE-accounting only. Proven empirically (byte-diff + determinism) + adversarially at the in-milestone close.
- [ ] **SEC-02**: SOLVENCY-01 is untouched — every change is BURNIE flip-credit / weight-only / pure-annotation OFF the ETH/`claimablePool` path; the ETH/pool debit is byte-unchanged. Proven empirically (solvency-invariant) + adversarially.

### AUDIT — Terminal close
- [ ] **AUDIT-01**: The in-milestone TERMINAL close — a delta-audit (every changed surface NON-WIDENING vs the v56 baseline `1e7a646d`, with the RNG-freeze byte-diff + SOLVENCY-01 byte-anchor re-attested) + the mandatory 3-skill genuine-PARALLEL adversarial economic review (`/contract-auditor` + `/economic-analyst` + `/zero-day-hunter`; `/degen-skeptic` = the dual-gate filter) + `audit/FINDINGS-v57.0.md` (chmod 444) + the atomic 5-doc closure flip with the `MILESTONE_V57_AT_HEAD_<sha>` signal — re-attests all v57.0 requirements against the frozen closure HEAD.

## Future Requirements (deferred)
- Generalized operator-spend of `claimableWinnings` (carried from v54/v55/v56) — larger blast radius, separate optional feature.

## Out of Scope
- The v52 consolidated cross-model audit (separate track; the v57 surface folds into it as an additional track, not a substitute for v57's own in-milestone close).
- Any ETH/`claimablePool`/solvency-path change (this is a BURNIE-emission / weight / type-annotation change only — SOLVENCY-01 byte-untouched is a hard floor).
- The already-validated NON-ISSUES confirmed already-done at the 2026-06-04 validation (NOT work): O1 quest lootbox double-credit (already credited exactly once by the v56 routing rework), the resolveLootboxRoll dead burnie-conversion branch (refactored away), the runrewardjackpots module misplacement (already inlined — only the 2 stale comments remain → HYG-02), and the 4 older balance notes (degenerette recalibration, burnie near-future per-pull-level, deity-pass gold nerf, hero-override weighted roll — all shipped in commits 267/292/etc).
- Off-chain indexer / webpage (separate frontend track).

## Traceability

_To be filled by the roadmapper (Phase mapping). Each REQ-ID maps to exactly ONE owning phase. Phases continue from 357 → 358. Expected shape: 358 SPEC → 359 IMPL → 360 GAS → 361 TST → 362 TERMINAL (the established v54/v55/v56 audit pattern)._

| Requirement | Phase | Phase Type | Status |
|-------------|-------|------------|--------|
| BATCH-01 | — | — | Not started |
| BATCH-02 | — | — | Not started |
| WWXRP-01 | — | — | Not started |
| WWXRP-02 | — | — | Not started |
| TDEC-01 | — | — | Not started |
| TDEC-02 | — | — | Not started |
| TDEC-03 | — | — | Not started |
| UDVT-01 | — | — | Not started |
| UDVT-02 | — | — | Not started |
| UDVT-03 | — | — | Not started |
| HYG-01 | — | — | Not started |
| HYG-02 | — | — | Not started |
| SEC-01 | — | — | Not started |
| SEC-02 | — | — | Not started |
| AUDIT-01 | — | — | Not started |
