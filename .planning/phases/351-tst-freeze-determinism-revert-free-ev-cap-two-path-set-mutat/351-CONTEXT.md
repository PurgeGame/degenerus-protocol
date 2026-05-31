# Phase 351: TST — Freeze/Determinism + Revert-Free + EV-Cap + Two-Path + Set-Mutation + Non-Widening + Gas - Context

**Gathered:** 2026-05-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Empirically prove the v55 **AfKing-in-Game** redesign behaviorally correct against the **game-resident** model
(the live committed fold + box redesign at HEAD `902f3fbf`, contracts == 349.2 `453f8073`) — **NOT** v54's
soon-replaced de-custody machinery, so no throwaway test work. Owns **6 requirements — TST-01..06**:

1. **TST-01 — Freeze/determinism:** the stamp+open yields a byte-identical box independent of open timing/block
   (seed uses the **STAMPED** day, never open-time `_simulatedDayIndex()`); index-binding holds across a mid-day
   `requestLootboxRng` index advance.
2. **TST-02 — Revert-free + no-valve no-brick:** a funded process/open never reverts on well-formed slices (the
   preserved `_resolveBuy` invariants, REVERT-01); a solvency violation **fails loud** (class B, never masked);
   game-over routing is **never blocked** by the afking STAGE (class C). **D-348-04 — NO try/catch.**
3. **TST-03 — EV-cap:** the per-`(player, level)` 10-ETH benefit budget is enforced **exactly once per open** with
   **no double-draw** vs the buy-time path; equivalent to v54.
4. **TST-04 — Two-path open coexistence + set-mutation** (eviction/tombstone/swap-pop, streak preserved) + the
   **OPEN-E 4-protection** regression.
5. **TST-05 — NON-WIDENING** regression vs the v54 baseline `20ca1f79` — every pre-existing red enumerated **BY
   NAME** (`REGRESSION-BASELINE-v55.md`).
6. **TST-06 — Gas:** per-buy + per-open **marginal** under the 16.7M HARD per-tx ceiling; GAS-01/02/03 wins proven
   same-results.

**Type:** TST. **ZERO `contracts/*.sol` mutation** (the subject is FROZEN at `453f8073`). **Hands-off — no
contract-commit gate** (the ONLY action needing approval is committing `contracts/*.sol`, and this phase produces
none; test/docs commits run autonomously per [[only-contract-commits-need-approval]]). Restores a clean v55.0
regression baseline.

</domain>

<decisions>
## Implementation Decisions

These split into (A) **decisions made in this discussion** and (B) **carried-forward LOCKED posture** (restated
because load-bearing).

### A. Test-corpus disposition (the central decision)

- **D-351-01 — ADAPT EVERYTHING (USER chose over the recommended hybrid).** Rewrite **all** the stale AfKing/keeper
  test files **+ the shared `DeployProtocol.sol` fixture** to the game-resident `GameAfkingModule` path; **preserve
  maximum coverage** (this is an audit repo — every property a C4A warden could probe stays covered). Each property
  **reframes onto its v55 successor mechanism**, it is not deleted:
  - per-day `_afkingEpoch` determinism → **stamped-day determinism** (the 5-field stamp; FREEZE-03)
  - cross-contract `afkingSnapshot`/`afkingFundingOf` **STATICCALL** plumbing → **in-context SLOAD** (GAS-02 no-STATICCALL trace)
  - `doWork` router → **`mintBurnie`** router (rename)
  - cold afking box-ledger (`lootboxEth*`/`boxPlayers.push`/`enqueueBoxForAutoOpen`) → **warm Sub-stamp** (GAS-01)
  - cross-contract `afkingFunding` reads → game-resident `afkingFunding[...]` SLOADs
- **D-351-02 — the ONLY permitted deletion = a fully-removed surface with NO behavioral successor.** A test whose
  *entire subject* is a surface the redesign **removed outright** (the deleted `AF_KING.batchPurchase` / `BatchBuy`
  event / `onlyFlipCreditors` entry — 349.1 P5 dead-code) may be dropped **only** with a BY-NAME entry + the removal
  reason in `REGRESSION-BASELINE-v55.md`. **Bias = adapt/preserve, never silent-delete.** A merely-renamed or
  relocated mechanism is NOT a removed surface — adapt it.
- **D-351-03 — fixture-repair is Wave 0 (blocking-first).** `test/fuzz/helpers/DeployProtocol.sol` imports the
  now-deleted `contracts/AfKing.sol` → **cascades a compile break to 64 dependent test files**. Repair the shared
  fixture to deploy/wire the game-resident `GameAfkingModule` (and adapt `subscribe`/`mintBurnie`/`setDailyQuantity`
  call paths) **before** any other test work — nothing compiles until it lands. (Precedent: v46 Phase 318
  "fixture-repair un-bricked 533→532 tests".)

### B. New-proof rigor

- **D-351-04 — UNIT + FUZZ where it strengthens.** Targeted unit scenarios pin each named behavior; fuzz campaigns
  layer **specifically** onto the properties where randomness genuinely strengthens the proof:
  - **TST-01 freeze/determinism** — fuzz random open-timing/block + a mid-day `requestLootboxRng` index advance
    (the headline property; fuzz is most valuable here).
  - **TST-02 revert-free** — fuzz random *funded* well-formed slice inputs (amount / claimable-mix) exercising the
    `_resolveBuy` invariants (`ev = cost − claimableUse`, the 1-wei sentinel, the `LOOTBOX_MIN` skip, `quantity ≥ 1`).
  - **TST-04 set-mutation** — fuzz random subscribe/evict/swap-pop orderings (streak-preserved, no cursor advance
    after swap-pop).
  - TST-03 EV-cap exactly-once + the two-path coexistence are unit-shaped (targeted scenarios) but may take a light
    fuzz on multi-open sequences. Not a blanket `FOUNDRY_PROFILE=deep` across the board.

### B. Box same-results oracle

- **D-351-05 — DIFFERENTIAL oracle.** The byte-identical-box core assertion (TST-01 / TST-06 same-results) runs the
  **afking stamp→open path AND a manual `openLootBox`** for the **same** `(amount, level, rngWord, score)` and asserts
  **byte-identical materialized traits**. Robust to any future resolution refactor; the v48 "byte-reproduced" / v49
  same-results precedent. (Not golden-value snapshots.)

### B. Carried-forward LOCKED posture (do NOT re-open)

- **Skip research, plan directly** off the v55 PLAN docs + the 350 TST-06 spec + this CONTEXT
  ([[feedback_skip_research_test_phases]] — fully-specced internal refactor with a discharged proof; the work is
  enumerated with exact file paths + instruments. The planner uses `--skip-research`).
- **TST-06 is FULLY specified by `350-TST06-MEASUREMENT-SPEC.md`** — the planner consumes it as-is: the loop-N-divide
  **MARGINAL rule** (v46 CR-01, never a single-item total), the exact instruments (`processSubscriberStage` per-buy /
  `_openAfkingBox`+`resolveAfkingBox` per-open), the comparison oracles (the v54 cold-ledger ~120–130k for the buy;
  human `openLootBox` for the open), the **no-STATICCALL trace assertion** (GAS-02, §3), the **16.7M ceiling** at
  `SUB_STAGE_BATCH=50` (a landed buy ≈262k → 50 ≈13.1M; the open leg uniform O(1) per box), and the §6 Wave-0 harness
  gaps. The per-buy marginal **INCLUDES** the 349.2-restored BURNIE side-effects (quest/affiliate/creditFlip) — those
  are intended behavior, NOT a GAS-01 regression; report the marginal as-is vs the cold-ledger oracle, do not subtract.
- **GAS-03 → Outcome A (no diff) → NO `claimablePool` byte-identical oracle.** 350 closed Outcome A (GAS-03
  REJECTED-with-reasoning; zero contract change). Record in the TST-06 results: "no Outcome-B diff produced; GAS-03
  measurement not exercised" (350-TST06 §4 under Outcome A). The Outcome-B per-slice-vs-batch oracle + forced-underflow
  test are **N/A**.
- **Freeze target = the 5-field STAMPED stamp** `(index, amount, day, scorePlus1, baseLevelPlus1)` (D-348-07 —
  score+baseLevel are stamped-frozen). The **EV-cap clamp is the SOLE live-read** — that is exactly TST-03's
  exactly-once charge, **not** a freeze target. Do NOT write a freeze test trying to prove score/baseLevel are
  unmanipulable: they're frozen in the stamp (the live-read window from D-348-05 was superseded by the 5-field stamp).
- **Foundry `forge test`, sequential-on-main, NO worktrees** (the repo has a `lib/forge-std` submodule + node_modules
  → worktrees are avoided per v49's TST note).
- **NON-WIDENING discipline + BY-NAME baseline doc** (v49 `666/42/17`, v48 `632/42` precedent): `REGRESSION-BASELINE-v55.md`
  enumerates (a) the carried-over v54 `20ca1f79` baseline reds **BY NAME** that still exist, (b) any removed-surface
  test dropped per D-351-02 (with reason), (c) confirmation that **NO NEW red is introduced by v55 logic**. The v55
  proofs (TST-01..06) are additive green. Because the afking corpus is rewritten (D-351-01), the ledger must reconcile
  the rewrites explicitly (which baseline tests became which adapted test).

### Claude's Discretion (carried on precedent — unpicked gray area)

- **Regression-baseline SCOPE = Foundry-focused.** The redesign is Solidity-internal; the blast radius is the afking
  module + the shared fixture. The BY-NAME NON-WIDENING ledger is **Foundry-centric**; the **Hardhat `.test.js`
  suite** (`test/unit/DegenerusGame.test.js` etc.) is confirmed **still compiling + passing as a sanity check** (if any
  Hardhat test references a changed afking ABI method, adapt it), but it is **not** the primary BY-NAME ledger. (v48 ran
  both runners; v55's narrower blast radius makes Foundry the focus. The planner may confirm.)
- **Gas-harness file placement / naming** — the planner reframes the existing `test/gas/Keeper*WorstCaseGas.t.sol`
  instruments into the afking per-buy/per-open marginal harness per the 350 spec (under `test/gas/`), exact filenames
  the planner's call.
- **Whether `REGRESSION-BASELINE-v55.md` lives in `test/`** (alongside v48/v49/v50 baselines) — yes by precedent, but
  the planner confirms.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The TST charge (read FIRST)
- `.planning/phases/350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam/350-TST06-MEASUREMENT-SPEC.md`
  — **the authoritative TST-06 spec.** Marginal rule, instruments + `file:line` anchors, comparison oracles, the
  no-STATICCALL trace assertion, the 16.7M ceiling, the §6 Wave-0 harness gaps, the Outcome-A GAS-03 N/A note.
- `.planning/REQUIREMENTS.md` — the v55.0 REQ-IDs (351 owns **TST-01..06**, lines 51-56). Plus the SOLVENCY-01
  invariant `claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]` (the class-B fail-loud target).
- `.planning/ROADMAP.md` §"Phase 351" — the goal + 6 success criteria (the depends-on-350 final-surface rule).

### v55 design source-of-truth (the properties under test)
- `.planning/PLAN-V55-AFKING-IN-GAME-REDESIGN.md` — **§10 canonical** (boons OFF → box `amount` = spend; the stamp;
  the 3-rule process-pass; the two open routes). NOTE §4/§9 placement superseded by **D-348-01 (required-path STAGE)**;
  §10 try/catch amended by **D-348-04 (no valve)**.
- `.planning/PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` — **§5 = the 4 LOCKED obligations** (obl 4 try/catch DROPPED by
  D-348-04); §3 = the `_resolveBuy` slice-builder discharge (obligation 1 = the sole no-brick guarantor under
  no-valve, REVERT-01); §4 = the EV-cap-at-open + open-determinism derivation.
- `.planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-CONTEXT.md` +
  `.../348-SPEC-INDEX.md` (+ `348-FREEZE-PROOF.md`, `348-PLACEMENT-DECISION.md`) — the freeze proof (FREEZE-01/02/03),
  the required-path divergence + proof obligations (D-348-01/02), the no-valve correction (D-348-04), the 5-field stamp
  (D-348-07). **The properties TST-01/02 must demonstrate empirically.**

### The IMPL surface under test + the sweep checklists 351 consumes
- `.planning/phases/349.1-*/349.1-DESIGN.md` §7 IMPL checklist + §8 sweep — the box-redesign final form (live-level
  resolve, `_afkingEpoch` DROPPED, ticket/lootbox split, NO-ORPHAN guard, `mintBurnie` rename, `AF_KING` dead-code
  removal). The behaviors TST-01/04 exercise.
- `.planning/phases/349.2-*/349.2-DESIGN.md` §6 IMPL-CHECKLIST + §7 SWEEP — the restored LOOTBOX-sub quest-credit +
  affiliate (BURNIE flip-credit, handlers-before-score → streak-sourced `scorePlus1`). The side-effects TST-06's
  per-buy marginal INCLUDES (and TST-04 may assert present).

### Contract anchors (FROZEN at `453f8073` / HEAD `902f3fbf`; grep-verify before instrumenting)
- `contracts/modules/GameAfkingModule.sol` — `processSubscriberStage` **`:539`** (lootbox branch `:735-833`; stamp
  writes `:793 scorePlus1` / `:794 amount` / `:840 lastAutoBoughtDay`; debit `:709`; `claimablePool -=` `:710`);
  `_openAfkingBox` **`:888`** (marker `:892` effects-first; seed `:901-907` `(amount, day, rngWordByDay[day],
  scorePlus1-1)`); `_afkingBoxReady` **`:918`**; `_autoOpen` **`:938`**; `autoOpen` **`:1023`** (UNREWARDED standalone);
  `mintBurnie` **`:993`** (advance leg `:993-996`, open leg `:1000-1009`). The restored side-effects: `quests.handlePurchase`
  `:760`, `recordMintQuestStreak` `:773`, `affiliate.payAffiliate` `:806`/`:816`, `coinflip.creditFlip` `:831`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — the STAGE block **`:305-312`** via `_runSubscriberStage(day)`
  **`:754`** → delegatecall `processSubscriberStage(SUB_STAGE_BATCH)` **`:759-761`**, strictly PRE-RNG (before `rngGate`);
  partial-drain `:313-317` (`subsFullyProcessed` at cursor end); `SUB_STAGE_BATCH = 50` **`:149`**; `requestLootboxRng`
  **`:1016`** + index advance **`:1089`/`:1629`** (the mid-day advance TST-01 fuzzes).
- `contracts/modules/DegenerusGameLootboxModule.sol` — `resolveAfkingBox` **`:877`** (the open callee); the human
  `openLootBox` **`:503`** (the differential oracle's other arm — reads/zeroes `:505`/`:529`/`:553`/`:555`/`:558`/`:560`);
  `_applyEvMultiplierWithCap` (EV-cap RMW, keyed `lootboxEvBenefitUsedByLevel[player][level+1]`, the TST-03 subject).
- `contracts/storage/DegenerusGameStorage.sol` — the Sub stamp slot (`:1867`); SOLVENCY-01 (`:358`);
  `LOOTBOX_EV_BENEFIT_CAP = 10 ether`. The surviving view-helpers `afkingFundingOf`/`afkingSnapshot`
  (`DegenerusGame.sol:1579`/`:2645`) are called ONLY by `DegenerusVault.sol:518` — **OFF** the hot path (NOT a GAS-02
  STATICCALL violation; do not flag).

### Test surface + regression precedent
- `test/fuzz/helpers/DeployProtocol.sol` — **the shared fixture (imports deleted `AfKing.sol`)**; 64 test files depend
  on it. **Repair FIRST (Wave 0).**
- The AfKing/keeper corpus to ADAPT (D-351-01) — `test/fuzz/AfKingSubscription.t.sol` (direct `AfKing.sol` import +
  `_afkingEpoch` + `doWork`), `test/fuzz/AfKingFundingWaterfall.t.sol`, `test/fuzz/AfKingConcurrency.t.sol`,
  `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol`, `test/fuzz/KeeperFaucetResistance.t.sol`,
  `test/fuzz/KeeperRewardRoutingSameResults.t.sol`, `test/fuzz/KeeperRouterOneCategory.t.sol`,
  `test/fuzz/KeeperNonBrick.t.sol`, `test/fuzz/RngLockDeterminism.t.sol` (epoch ref → stamped-day),
  `test/fuzz/RedemptionStethFallback.t.sol` (`AfKing.sol` import), `test/gas/KeeperOpenBoxWorstCaseGas.t.sol`,
  `test/gas/KeeperLeversAndPacking.t.sol`, `test/gas/KeeperResolveBetWorstCaseGas.t.sol`,
  `test/gas/RouterWorstCaseGas.t.sol`, `test/gas/SweepPerPlayerWorstCaseGas.t.sol`.
- `test/REGRESSION-BASELINE-v49.md` + `test/REGRESSION-BASELINE-v50.md` — the BY-NAME NON-WIDENING ledger format to
  mirror for `test/REGRESSION-BASELINE-v55.md` (TST-05).

### Related memory (audit posture / dispositions)
- [[v55-afking-revert-free-proof]] — the v55 active-state record (proof discharged; 5-field stamp; EV-cap-at-open).
- [[only-contract-commits-need-approval]] — why this TST phase is hands-off (no contract gate).
- [[threat-model-reentrancy-mev-nonissues]] — RNG-freeze dominant; the freeze proof's threat weighting.
- [[afking-cancel-tombstone-streak-finding]] + [[open-e-operator-approval-trust-boundary]] — the set-mutation
  (swap-pop, streak-preserved) + OPEN-E 4-protection TST-04 regresses.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`350-TST06-MEASUREMENT-SPEC.md`** — a turnkey harness blueprint; the planner builds the §6 gaps, no re-derivation.
- **The human `openLootBox` (`LootboxModule.sol:503`)** — the differential oracle's reference arm (run it for the same
  `(amount, level, rngWord, score)` the afking stamp→open uses; assert equal traits).
- **`REGRESSION-BASELINE-v49.md` / `-v50.md`** — the exact BY-NAME ledger template for `-v55.md`.
- **The existing AfKing/keeper fuzz+gas tests** (~8,300 lines) — the property scaffolding to ADAPT (call-site rewrites:
  `AfKing.subscribe`→game path, `doWork`→`mintBurnie`, drop `_afkingEpoch` asserts → stamped-day asserts).

### Established Patterns
- **Fixture-first un-bricking** (v46 Phase 318) — repair the shared deploy helper before chasing per-test reds.
- **NON-WIDENING BY-NAME ledger** (v49 `666/42/17` = "42 v48 reds BY-NAME; 17 deleted + 5 renamed") — the exact
  discipline for TST-05 under a rewritten corpus.
- **Differential same-results oracle** (v48 HERO-04 "byte-reproduced", v49 reward-routing same-results) — D-351-05.
- **Marginal gas peg** (v46 Phase 319 CR-01) — loop-N-divide, never single-item total (350 spec §0).
- **ZERO contract mutation in TST** (v49 Phase 332) — `git diff 453f8073 HEAD -- contracts/` stays EMPTY throughout.

### Integration Points
- **Wave 0 (blocking-first):** repair `test/fuzz/helpers/DeployProtocol.sol` → the 64-dependent compile cascade
  clears → then the per-file adaptation + the new v55 proofs land.
- **The process STAGE is PRE-RNG inside `advanceGame`** (`AdvanceModule:305-312`) — to exercise the per-buy marginal,
  the harness drives a new-day `advanceGame()` (or `mintBurnie()`'s advance leg) with N vs N−1 funded LOOTBOX-mode subs.
- **The open leg is post-RNG** (`autoOpen`/`mintBurnie` open leg) over N vs N−1 ready stamped boxes after
  `rngWordByDay[stampDay]` lands.

</code_context>

<specifics>
## Specific Ideas

- **"Adapt everything" is the USER's emphasis** — they chose maximum coverage retention over the leaner hybrid I
  recommended. For an audit repo, losing battle-tested edge coverage (concurrency orderings, funding-waterfall corners,
  faucet/non-brick) is the worse risk. The planner should treat wholesale deletion as the exception (D-351-02), not the
  default, and reconcile every rewrite in the TST-05 ledger.
- **The per-buy marginal legitimately grew** (349.2 restored BURNIE quest/affiliate). That is the CORRECT same-results
  target for a lootbox sub — it matches a manual lootbox buy MINUS the cold ledger. Do not flag it as a GAS-01 regression.

</specifics>

<deferred>
## Deferred Ideas

- **The Outcome-B `claimablePool` per-slice-vs-batch oracle + forced-underflow test** — N/A under 350's Outcome A
  (GAS-03 REJECTED, no diff). Recorded as not-exercised in the TST-06 results; not deferred work, just inapplicable.
- **The v52 consolidated cross-model audit** (v50+v51 debt) — a separate post-v55 track, NOT this phase.
- **v56 affiliate/quest batching** ([[v56-batch-afking-affiliate-quest-seed]]) — a separate post-ship milestone with
  its own 3-skill economic review; do NOT pull forward into 351.
- **352 TERMINAL** — the delta-audit + 3-skill adversarial sweep + `audit/FINDINGS-v55.0.md` + closure flip is the
  NEXT phase, not 351's charge.

None of the above are scope creep into 351 — the discussion stayed within the test-only boundary.

</deferred>

---

*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Context gathered: 2026-05-31*
