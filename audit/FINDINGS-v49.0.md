---
phase: 333-terminal-delta-audit-3-skill-adversarial-sweep-closure
plan: 03
milestone: v49.0
milestone_name: Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep
audit_baseline: 0cc5d10fbc1232a6d2e7b0464fe21541b9812029
audit_baseline_signal: MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029
source_tree_frozen_ref: 4c9f9d9b
audit_subject_head: "MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9"
closure_signal: MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9
deliverable: audit/FINDINGS-v49.0.md
new_findings: 0
new_findings_disposition: 0 NEW_FINDINGS — the 3-skill genuine-PARALLEL adversarial sweep produced 0 FINDING_CANDIDATEs across 21 charged-probe rows (15 NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN); the OPEN-E 4-protection HARD-BLOCKING re-attestation HOLDS on all 4 without the per-iter :676 check (no GASOPT-05 revert; closure NOT blocked); KNOWN-ISSUES.md byte-unmodified vs v48; the v48 SWAP cash-share advisory carried-forward-unmodified (informational doc-drift, no-arb holds, USER-accepted <=60% canonical, NOT a finding)
---

# v49.0 Findings — Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep (Terminal)

## 1. Audit Subject + Baseline

**Audit Baseline.** v48.0 closure HEAD `0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (signal
`MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029`). v49.0 closure HEAD is
`MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (the signal = the findings-deliverable / pre-flip
HEAD `b0511ca2`, recorded by the closure-flip commit on top per the v44/v46/v47/v48 2-commit sequential-SHA
orchestration; see §9c). SOURCE-TREE FROZEN reference for the terminal: `4c9f9d9b` (contracts/
byte-frozen; `git diff 4c9f9d9b HEAD -- contracts/` empty throughout Phase 333 — EMPTY-CONFIRMED).

**Subject.** The frozen subject HEAD `4c9f9d9b` = the Phase 330 IMPL batched router/advance-redesign diff
`63bc16ca` + the Phase 331 GAS-calibration / re-peg split `4c9f9d9b`. Every v48->v49 `contracts/*.sol` commit
(`git log 0cc5d10f..4c9f9d9b -- 'contracts/*.sol'`):
- `63bc16ca` — the single batched Phase 330 IMPL diff (USER-APPROVED hand-review, BATCH-02): the v49
  keeper-router REDESIGN reconciled across 5 files (`git diff 0cc5d10f 4c9f9d9b -- contracts/` = 5 files,
  +376 / -226) — the **PARAMETERLESS `doWork()`** one-category router (`AfKing.sol`), the **advance-bounty
  re-home** + `(uint8 mult)` return-shape (`DegenerusGameAdvanceModule.sol`), the Game wrapper-decode +
  rngLock-aware O(1) discovery views + autoOpen RD-3/RD-5 rework + the `autoResolve`->`degeneretteResolve`
  rename (`DegenerusGame.sol`), the **GASOPT-01** `owedMap` storage-pointer hoist
  (`DegenerusGameMintModule.sol`), and the `advanceGame() returns (uint8 mult)` interface update
  (`IDegenerusGameModules.sol`).
- `4c9f9d9b` — the USER-APPROVED Phase 331 GAS split: the break-even-@0.5gwei flat-per-tx re-peg constants
  (`BOUNTY_ETH_TARGET` / `BUY_BATCH=50` / `OPEN_BATCH=100` / `ADVANCE_RATIO_NUM=2` / `BUY_RATIO 3/2` /
  `OPEN_KNEE=5`) + the whale-pass-weighted autoOpen budget split, landed into `AfKing.sol` + `DegenerusGame.sol`.
  The `degeneretteResolve` flat `RESOLVE_FLAT_BURNIE = 1e18` re-peg rode the same calibration.

v49.0 is a keeper-subsystem architecture refactor: it unifies the AfKing keeper into a single parameterless
`doWork()` router (one rewarded category per call), re-homes the advance bounty out of the AdvanceModule into
the router, re-pegs every bounty to a flat-per-tx break-even at 0.5 gwei, renames + re-pegs the Degenerette
resolve path, and folds four no-cost gas micro-opts. It ships the full 9-section deliverable, `chmod 444` at
close (applied in 333-04, not here). This is a 5-phase milestone (329 SPEC / 330 IMPL / 331 GAS / 332 TST /
333 TERMINAL) — one phase longer than v48's 4-phase shape, owing to the load-bearing dedicated GAS calibration.

---

## 2. Executive Summary

### Closure Verdict Summary
v49.0 ships the **UNIFIED KEEPER ROUTER**: a parameterless `doWork()` on `AfKing.sol` that routes exactly ONE
keeper category per call (`autoBuy -> advance-leg -> autoOpen`, RD-1) via a structural `else-if` early-return,
pays a single unified `creditFlip` CEI-last after the ladder, and cleanly `revert NoWork()` when no work is
found. It **RE-HOMES the advance bounty** (the 3 in-callee advance `creditFlip` sites removed; `advanceGame()`
now returns `(uint8 mult)` so the router pays the re-homed bounty from the canonical day-epoch home; standalone
`advanceGame()` stays a functional UNREWARDED liveness fallback with the EXISTING free-fallback caller tiers
intact). It **RE-PEGS** every bounty to a flat-per-tx break-even at 0.5 gwei (per-item MARGINAL never a per-call
total — the CR-01 self-crank-faucet rule; the WR-01 round-trip guard proves no positive-EV loop), **RENAMES +
RE-PEGS `autoResolve` -> `degeneretteResolve`** (flat ~1-BURNIE per tx, >=3-NON-WWXRP pay-gate, `NoWork()`-on-zero,
WWXRP excluded, resolution RESULTS byte-identical), and ships **GASOPT-01/03/04/05** (owedMap hoist / batched
`keeperSnapshot` / `AutoBought` event dropped / per-iter `isOperatorApproved` `:676` dropped). The SC2 delta-audit
(5 surfaces NON-WIDENING) + the SC1 3-skill genuine-PARALLEL adversarial sweep + the LEAN regression find the
change set sound with **0 NEW FINDINGS** — the sweep surfaced zero FINDING_CANDIDATE. The **4 structural
invariants** (one-category early-return / frozen advance-consume / free-fallback caller / single day-start epoch
satisfied-by-deletion) are INTACT; the **OPEN-E 4-protections** re-attest HOLD without the per-iter `:676` check
(the GASOPT-05 HARD-BLOCKING condition is SATISFIED — no revert, closure NOT blocked); **RNG-freeze is INTACT**
under the router composition. One informational ADVISORY (the v48 SWAP cash-share doc-drift) is carried-forward-
unmodified — it is OUTSIDE the v49 blast radius, no-arb holds, USER-accepted <=60% canonical, NOT a finding (§4.4
/ §9d). It does NOT amend the verdict.

### Verdict Math
- **Adversarial sweep (Phase 333 SC1, from 333-02):** 21 deduplicated charged-probe rows across the unified
  keeper surface + composition — **15 NEGATIVE-VERIFIED / 6 SAFE_BY_DESIGN / 0 FINDING_CANDIDATE**. 0 skeptic-
  filter self-discards reached FINDING_CANDIDATE (two genuine-hunt self-discards recorded: the line-257
  non-zeroing `totalFlipReversals` read at Gate-1, the v49-novel re-homed advance-leg faucet at Gate-2(a)); 0
  orchestrator integration-time discards became findings. GENUINE PARALLEL_SUBAGENT
  (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per D-271-ADVERSARIAL-02);
  each probed the frozen subject via `git show 4c9f9d9b:contracts/...` (READ-ONLY).
- **Delta-audit (Phase 333 SC2, from 333-01):** every one of the 5 v49 contract surfaces attests NON-WIDENING
  vs `0cc5d10f` with grep/diff anchors @ `4c9f9d9b`; the +376/-226 delta has ZERO orphan hunks (every hunk maps
  to exactly one of the four work-item families: router / advance-rework / re-peg / micro-opts). Kill-sets are
  grep-ZERO in mainnet code: the 3 advance in-callee keeper `creditFlip` sites (`:189`/`:225`/`:468`), the
  autoBuy stall ladder (`bountyMultiplier`/`stallMultiplier`/`STALL_`), the `AutoBought` event, the per-iter
  `isOperatorApproved(player, AfKing)` `:676`.
- **Regression:** NON-WIDENING **BY NAME** — foundry whole-tree `forge test` **666 pass / 42 fail / 17 skip**
  (708 run) per `test/REGRESSION-BASELINE-v49.md` (the 332-06 ledger). The live failing NAME set **== the 42
  v48.0 §2-union reds BY NAME** (Bucket A 8 VRF/RNG + Bucket B 34 stale-harness/v48-behavioral + Bucket C 0
  HERO-foundry = 42); the **17 premise-retired reward-rehoming tests** were DELETED (v49 invariants re-authored
  fresh at 332-02/03/04, zero coverage lost) and **5 `Crank*` files were `git mv`-renamed to `Keeper*`** — both
  attributed via the ledger, NOT counted as regression. The binding gate is failing-NAME-set equality, not an
  arithmetic count delta.

### Severity Counts
- CATASTROPHE 0 · HIGH 0 · MEDIUM 0 · LOW 0 · informational SAFE_BY_DESIGN 6 · informational ADVISORY 1 (the
  v48 SWAP cash-share doc-drift, carried-forward-unmodified) + 1 coverage observation (advance-leg faucet
  round-trip, §4.3/§C.3a, NOT a finding).

### KI Gating Rubric Reference
KNOWN-ISSUES.md (at the REPO ROOT) byte-unmodified vs v48 (`git diff 0cc5d10f HEAD -- KNOWN-ISSUES.md` empty,
§6). No KI promotion/demotion this milestone; the SC1 sweep surfaced no KI-eligible item (0 FINDING_CANDIDATE).

### Forward-Cite Closure Summary
**0 forward items resolved-this-milestone** (no prior-milestone deferred findings were carried into v49 — v48
closed with 0 NEW findings; F-47-01/F-47-02 were RESOLVED-AT-V48). The prior-milestone v49 descriptive seeds
(the keeper-router redesign + the advance-bounty re-home + the bounty re-peg) are now **SHIPPED** (§8) — no
longer forward-seeds. Two v49.1/v50 forward-seeds are recorded for future milestones (§8): the whale-pass-claim
O(1)-refactor seed and the mintmodule processed/future advance-divergence candidate.

### Attestation Anchor
All `contracts/` file:line anchors herein are sourced from the Phase 333 workstream logs (333-01-DELTA-AUDIT,
333-02-ADVERSARIAL-LOG), each re-grep-verified against the frozen subject `4c9f9d9b`
(`git diff 4c9f9d9b HEAD -- contracts/` empty).

---

## 3. Per-Phase Sections

- **§3a Phase 329 — SPEC (design-lock).** `0eae9c28` (3 plans / 2 waves, VERIFICATION 8/8, paper-only — zero
  contract mutation) — the locked v49.0 design under the keeper-router REDESIGN: the 4 structural invariants
  (one-category structural early-return / frozen advance-consume ADV-04 / guaranteed free-fallback caller D-04a
  / single day-start epoch satisfied-by-deletion GAS-03), the redesigned shared signatures (the
  `advanceGame (uint8 mult, bool rewardable)` return [later collapsed to `(uint8 mult)` at IMPL — §5 note], the
  PARAMETERLESS `doWork()` + `NoWork()` + the standalone UNREWARDED escapes, the rngLock-aware O(1) discovery
  views, the unified single `creditFlip`, the D-07 flat-per-tx model), ROUTER-07 (NO `nonReentrant` guard,
  re-grounded on the unified single `creditFlip`) + GAS-03 (satisfied-by-deletion), the 5 RD changes
  (RD-1..RD-5) + D-08 GASOPT-03/04/05, and every cited `file:line` grep-attested vs the v48.0 HEAD `0cc5d10f`.
- **§3b Phase 330 — IMPL (the ONE batched contract diff).** `63bc16ca` (USER-APPROVED hand-review, BATCH-02;
  9 plans / 8 waves) — all v49 contract work as a single reconciled `contracts/*.sol` diff (5 files,
  +376/-226), forge 616/58 (the v48 baseline +16 reward-rehoming reds deferred to 332). Authored
  producer-before-consumer (AdvanceModule bounty-removal + `(mult)` return -> Game wrapper decode + rngLock-aware
  views + autoOpen RD-3/RD-5 + `degeneretteResolve` rename + GASOPT-03 `keeperSnapshot` -> interfaces -> AfKing
  parameterless `doWork`/`_autoBuy`/RD-2-drop-guard/unified-flat-per-tx-bounty/GASOPT-04/05 -> MintModule
  GASOPT-01 + tests). ROUTER-01..06/08/09/10 · ADV-01/02/03/05 · GASOPT-01/03/04/05. USER deviations folded:
  `rewardable` bool DROPPED (`mult==0` => gameover-no-bounty subsumes it), `bountyMultiplier` collapsed,
  `maxCount==0` default batch retired.
- **§3c Phase 331 — GAS (the break-even peg calibration).** `4c9f9d9b` (USER-APPROVED hand-review, second v49
  contract gate; 5 plans / 3 waves) — the worst-case-first per-category MARGINAL gas derivation + the break-even
  @0.5gwei flat-per-tx re-peg (the CR-01 per-item-marginal rule, the WR-01 round-trip <=0-EV guard, the open KNEE
  killing the small-batch corner) + the `degeneretteResolve` flat `RESOLVE_FLAT_BURNIE=1e18` ~1-BURNIE re-peg.
  Heavy mid-execution USER re-scope (the buy-harness flaw fixed 40k->262k; the gated landing = split
  `DOWORK_BATCH` -> `BUY_BATCH=50`/`OPEN_BATCH=100` + the whale-pass-weighted autoOpen budget; the 16.7M ceiling
  honored). GAS-01/02/04/05/06.
- **§3d Phase 332 — TST.** `95aaf340` (6 plans / 3 waves, sequential-on-main no-worktrees; ZERO contract
  mutation) — the freeze-invariant fuzz (TST-01 `RngLockDeterminism.t.sol` router same-tx perturbation), the
  one-category/no-stacking + reentrancy double-pay regression (TST-02 `KeeperRouterOneCategory.t.sol`), the
  reward-routing + GASOPT same-results (TST-03 `KeeperRewardRoutingSameResults.t.sol`), the `degeneretteResolve`
  re-peg proof (TST-05 `DegeneretteResolveRepeg.t.sol`), and the NON-WIDENING **666/42/17** regression ledger
  (TST-04: the 17 premise-retired reds DELETED + the 5 `Crank*`->`Keeper*` renames + `test/REGRESSION-BASELINE-v49.md`).
- **§3e Phase 333 — TERMINAL.** This deliverable; SOURCE-TREE FROZEN at `4c9f9d9b`; the SC2 delta-audit
  (333-01) + the SC1 3-skill GENUINE PARALLEL_SUBAGENT sweep (333-02) + the regression + the gated closure flip.

### §3.A Delta-Surface Table (folded from 333-01-DELTA-AUDIT.md §2)

| Surface | Requirements | Re-grepped anchors @ `4c9f9d9b` | Disposition |
| --- | --- | --- | --- |
| **AfKing.sol** — parameterless router + unified bounty + re-peg + micro-opts | ROUTER-01·02·03·04·05·06·08·09·10 · GASOPT-04·05 · GAS-02·03·04·05 | **PARAMETERLESS `doWork()`** (`:883`, NO `maxCount`) routing one-category `else-if` **autoBuy -> advance -> autoOpen -> `NoWork()`** (`:890`/`:896`/`:902`/`:910`) with the **SINGLE unified `creditFlip` CEI-LAST** after the early-return (`:917`; `NoWork()` decl `:148`). `_autoBuy` is internal (`:561`); the RD-2 rngLock guard `:568` DROPPED (autoBuy fires during rngLock — RD-2 freeze-safe-by-construction). Standalone UNREWARDED escapes: `autoBuy(uint256)` `:923` + `autoOpen(uint256)` `:929`. 331 re-peg constants: `BOUNTY_ETH_TARGET` immutable `:261`, `BUY_BATCH=50` `:850`, `OPEN_BATCH=100` `:856`, `ADVANCE_RATIO_NUM=2` `:860`, `BUY_RATIO 3/2` `:864-865`, `OPEN_KNEE=5` `:869`; per-leg math `:893`/`:899`/`:905-906`. **KILL-SET (grep-ZERO):** the `AutoBought` event (GASOPT-04; oracle migrated to `lastAutoBoughtDay` `:88`/`:744`); the per-iter `isOperatorApproved(player, AfKing)` `:676` (GASOPT-05; strike comment `:667-670`); the autoBuy stall ladder (`bountyMultiplier`/`stallMultiplier`/`STALL_` = 0; GAS-03/D-07). | **NON-WIDENING** |
| **DegenerusGame.sol** — wrapper decode + discovery views + autoOpen RD-3/RD-5 + degeneretteResolve + batchPurchase guard | ADV-02 · GASOPT-03 · ROUTER-04·09 · GAS-06 · ROUTER-08 | **`advanceGame` wrapper** (`:278`) DECODES the delegatecall return (`mult = abi.decode(data, (uint8))` `:288`). **O(1) discovery views:** `advanceDue()` `:1637`, `boxesPending()` `:1655` (rngLock-aware `:1656`, RD-3), `keeperSnapshot(address[])` `:2628` (batches the per-player `claimableWinningsOf` STATICCALLs, GASOPT-03). **autoOpen RD-5** (`:1687`): try/catch DROPPED, pre-loop entry-gate `if (rngLockedFlag || _livenessTriggered()) return 0;` `:1692`; `_autoOpenBox` internal `:1762`. **`degeneretteResolve`** (renamed, `:1595`): flat `RESOLVE_FLAT_BURNIE=1e18` `:1544`; >=3-NON-WWXRP gate + `NoWork()`-at-zero (`:1629`/`:1630`; 1-2 resolved -> committed UNPAID, GAS-06). **batchPurchase** (`:1790`): game-side rngLock pre-check `:1737` DROPPED (RD-2), `gameOver` revert KEPT (`:1796`), AF_KING-gated `:1795`, per-player try/catch isolation INTACT (`:1806`, `catch {}`). | **NON-WIDENING** |
| **modules/DegenerusGameAdvanceModule.sol** — advance bounty-removal + return-shape + free-fallback intact | ADV-01 · ADV-02 · ADV-05 · ADV-03 | **KILL-SET (grep-ZERO keeper credits):** the 3 in-callee advance keeper `creditFlip(caller,…)` sites (`:189`/`:225`/`:468`) REMOVED — module `creditFlip` count = 1, the sole survivor at `:860` credits `ContractAddresses.SDGNRS` (the gameover-RNG U6 settlement, NOT a keeper bounty). **`advanceGame() returns (uint8 mult)`** (`:154`): `mult=1` default `:156`; gameover `mult=0` `:185` (router pays nothing); mid-day partial-drain `mult=1` `:217-218` (no escalation, ADV-05/D-07); new-day stall ladder `6`/`4`/`2` from the KEPT GAME-day epoch `:236`/`:238`/`:240`. Drain/day-advance logic OTHERWISE UNTOUCHED. **Free-fallback callers INTACT (D-04a):** the 30-min universal permissionless bypass `:996`; the ~120-day death-clock `DEPLOY_IDLE_TIMEOUT_DAYS` `:109`. `DegenerusVault.gameAdvance()`/`StakedDegenerusStonk.gameAdvance()` NOT in the v49 delta surface (re-home removed NO structural caller). | **NON-WIDENING** |
| **modules/DegenerusGameMintModule.sol** — GASOPT-01 owedMap hoist | GASOPT-01 | The `mapping(address => uint40) storage owedMap = ticketsOwedPacked[rk]` pointer hoist in BOTH loops: the resolve/future loop (`:399`) and `processTicketBatch` (`:673`), threaded through helpers (`:735`/`:765`). `rk` is loop-invariant within each scope -> a behavior-identical SLOAD-count reduction (byte-equivalent reads/writes at `:432`/`:442`/`:454`/`:464`/`:499`/`:743`/`:750`/`:756`/`:771`/`:824`). | **NON-WIDENING** |
| **interfaces/IDegenerusGameModules.sol** — advanceGame tuple signature | ADV-02 | The 6-line diff changes `advanceGame() external;` -> `advanceGame() external returns (uint8 mult);` (+ NatSpec: `mult` = stall ladder 1/2/4/6 new-day / 1 mid-day / 0 gameover). Matches the AdvanceModule signature (`:154`) + the wrapper decode (`DegenerusGame:288`) verbatim. No other interface row changed. | **NON-WIDENING** |

All 36 v49.0 REQ-IDs are referenced in §3.A + §3.C below: the 5-surface table carries every IMPL/GAS-resident
req (ROUTER-01..10 + ADV-01·02·03·05 + GAS-02·03·04·05·06 + GASOPT-01·03·04·05); ROUTER-07/ADV-04/BATCH-01 are
the SPEC-resident design-locks re-attested in §3a/§3.B; GAS-01 is the GAS derivation; TST-01..05 are the 332
proofs cited in §3d/§5; SWEEP-01 is 333-02, SWEEP-02 is 333-01, SWEEP-03 is this deliverable; BATCH-02 is the
`63bc16ca` diff; BATCH-03 is the 333-04 closure flip.

### §3.B Composition Attestation Matrix (folded from 333-01 §3)

**No orphan hunks across the +376/-226 delta.** Every hunk maps to exactly one v49 work item (333-01 §3.1):
`AfKing.sol` (318 lines, router / `_autoBuy` refactor / unified `creditFlip` / re-peg constants / GASOPT-04/05
/ stall-ladder deletion); `DegenerusGame.sol` (196 lines, wrapper decode / discovery views + `keeperSnapshot` /
autoOpen entry-gate + try/catch-drop / `degeneretteResolve` rename + flat >=3 re-peg / batchPurchase guard);
`DegenerusGameAdvanceModule.sol` (52 lines, the 3 creditFlip-removals + the `(uint8 mult)` return-shape);
`DegenerusGameMintModule.sol` (30 lines, the `owedMap` hoist both loops); `IDegenerusGameModules.sol` (6 lines,
the `advanceGame` return-tuple). **ZERO orphan hunks** — the v49 surface widens NOTHING beyond the four
work-item families.

**The 4 Structural Invariants (329-SPEC §2) re-attested INTACT @ `4c9f9d9b` (333-01 §3.2):**
- **(a) ONE-CATEGORY STRUCTURAL EARLY-RETURN** — `doWork()` (`AfKing:883-919`) is an `if / else if / else if /
  else` ladder (autoBuy `:890` / advance `:896` / autoOpen `:902` / `revert NoWork()` `:910`); exactly one leg
  executes; the single `creditFlip` `:917` fires once CEI-LAST. Bounty-stacking structurally impossible.
  Empirical: TST-02 (`KeeperRouterOneCategory.t.sol`, creditFlip COUNT==1 across buy/advance/open).
- **(b) FROZEN ADVANCE-CONSUME (ADV-04)** — autoBuy (leg 1) runs PRE-ENTROPY at day-open BEFORE the advance leg
  requests the word; autoOpen (leg 3) is rngLock-BLOCKED (`boxesPending()` false during rngLock
  `DegenerusGame:1656`; entry-gate `:1692`) so it never runs in the protected window; the advance leg consumes
  via the return-tuple decode (`:288`) with NO new mutable in-window SLOAD (the AdvanceModule consume logic is
  byte-untouched). Empirical: ADV-04 (SPEC) + TST-01 (`RngLockDeterminism.t.sol`, byte-identical consumed VRF
  output under router same-tx perturbation).
- **(c) GUARANTEED FREE-FALLBACK CALLER (D-04a)** — standalone `advanceGame()` stays functional + UNREWARDED;
  the SECONDARY/TERTIARY callers are INTACT (the 30-min permissionless bypass `AdvanceModule:996`, the ~120-day
  death-clock `:109`; `DegenerusVault.gameAdvance()` `:527` + `StakedDegenerusStonk.gameAdvance()` `:421` are
  NOT in the v49 delta surface -> untouched). Re-homing the bounty removed NO structural caller.
- **(d) SINGLE DAY-START EPOCH: SATISFIED-BY-DELETION (GAS-03)** — the AfKing autoBuy stall ladder is DELETED
  (grep-ZERO `bountyMultiplier`/`stallMultiplier`/`STALL_`), leaving the AdvanceModule GAME-day epoch
  (`:236`/`:238`/`:240`, 6/4/2) as the SOLE stall epoch. The 2 remaining `82620` hits (`AfKing:965-969`
  `_currentDay()`) are the keeper-local once/day idempotency epoch, NOT an escalating bounty ladder.

**OPEN-E 4-Protection BLOCKING Re-Attestation (GASOPT-05) — HARD CONDITION (333-01 §3.3):** GASOPT-05 dropped
the per-iteration `isOperatorApproved(player, AfKing)` check (`:676`) and KEPT the subscribe-time
`isOperatorApproved(fundingSource, subscriber)` gate (`:399`, OPENE-04) + the self-consent gate (`:388`). Per
[[open-e-operator-approval-trust-boundary]] + REQUIREMENTS GASOPT-05, the delta-audit re-attests the 4 OPEN-E
structural protections HOLD WITHOUT `:676` as a HARD BLOCKING CONDITION before closure:
1. **consent-gate-at-subscribe — HOLD.** Operator approval is checked ONCE, at subscribe (`:399`); the SUB
   record IS the consent unit. A player who never approved cannot be subscribed by a third party. The per-iter
   re-check was redundant.
2. **default-self byte-identical — HOLD.** `player==address(0)`->`subscriber=msg.sender` (`:386`);
   `fundingSource==address(0)` short-circuits the OPENE-04 read (`:397`) and resolves to the subscriber
   downstream. The self path is untouched by the GASOPT-05 delta.
3. **no-escalation — HOLD.** Dropping the per-iter check grants NO new authority: the consent principal is
   `fundingSource` (fixed + immutable post-subscribe); the autoBuy loop spends only `_poolOf[src]` (CEI-debited)
   into the player's own mint; the keeper is never a payee.
4. **trust-the-sub temporal bound — HOLD.** The window is `paidThroughDay` (`WINDOW_DAYS`), refreshed only by a
   paid `burnForKeeper` or a free active-pass extend; revocation is `setDailyQuantity(0)` -> in-set tombstone,
   skipped on the next autoBuy. The temporal bound + revocation path are intact, independent of the removed check.

**OPEN-E re-attestation outcome: ALL 4 PROTECTIONS HOLD** without the per-iter `:676` check (corroborated
independently by `/contract-auditor` in 333-02 §B.3, per-protection HOLD). The GASOPT-05 removal is
NON-WIDENING — a redundant per-iteration re-check removed while the consent trust boundary is fully preserved.
**The HARD BLOCKING CONDITION is SATISFIED -> no GASOPT-05 revert is required; closure is NOT blocked on this axis.**

**VRF / RNG-Freeze INTACT under the router composition (the v45 north-star, 333-01 §3.4):** the unified same-tx
router path introduces NO in-window SLOAD into the advance-consume ([[v45-vrf-freeze-invariant]]; ADV-04): (i)
autoBuy (leg 1) runs PRE-ENTROPY at day-open (RD-2 freeze-safe-by-construction — boxes queue at the current
`LR_INDEX`, the word lands at `LR_INDEX-1`); (ii) the advance leg (leg 2) consumes via the return-tuple decode
with the AdvanceModule consume logic byte-untouched; (iii) autoOpen (leg 3) is rngLock-BLOCKED (`:1656`/`:1692`)
so the open path NEVER executes inside the protected window. The player-controllable `totalFlipReversals` nudge
stays frozen request->consume (`reverseFlip` is hard-gated `if (rngLockedFlag) revert RngLocked();`
`DegenerusGame:2195`, dead the entire time the word is known). **Composition verdict: RNG-freeze NON-WIDENING.**

### §3.C Requirement Re-Attestation
All 36 v49.0 requirements (ROUTER 10 · ADV 5 · GAS 6 · GASOPT 4-active [01/03/04/05; GASOPT-02 SUBSUMED into
GASOPT-03, a pointer row, not counted] · TST 5 · SWEEP 3 · BATCH 3 = 36) are re-attested at closure. The actual
REQUIREMENTS.md row-flip to Complete is 333-04's closure-gate job; §3.C records the attestation narrative.

- **ROUTER (10):** **ROUTER-01** parameterless `doWork()`, one category/call, one gas-pegged bounty + UNREWARDED
  standalone `autoBuy(count)`/`autoOpen(count)` escapes (`AfKing:883`/`:923`/`:929`); **ROUTER-02** priority
  `autoBuy -> advance -> autoOpen` (`:890`/`:896`/`:902`, RD-1); **ROUTER-03** STRUCTURAL early-return (the
  `else-if` ladder, no stacking); **ROUTER-04** O(1) rngLock-aware discovery views (`advanceDue`/`boxesPending`
  rngLock-aware/buys-pending-true-during-rngLock, `DegenerusGame:1637`/`:1655`); **ROUTER-05** `_autoBuy`
  internal + RD-2 guard-dropped + bounty unified + KEEP-04 `bytes32("DGNRS")` passthrough survives + `autoResolve`
  excluded/renamed; **ROUTER-06** clean `NoWork()` revert (`:910`/`:148`); **ROUTER-07** (SPEC, Complete) NO
  `nonReentrant` guard on `doWork`, re-grounded on the unified single CEI-last `creditFlip` (333-01 §4 / 333-02
  §B.1 P6 SAFE_BY_DESIGN); **ROUTER-08** both rngLock guards dropped (`AfKing:568` + game-side `:1737`), `gameOver`
  KEPT (`:1796`); **ROUTER-09** autoOpen rngLock-blocked + try/catch-dropped + entry-gate + `_autoOpenBox`
  internal (RD-5); **ROUTER-10** bounty UNIFIED into ONE `creditFlip` in `doWork` (`:917`), legs never self-credit.
- **ADV (5):** **ADV-01** the 3 advance keeper `creditFlip` sites removed (grep-ZERO; `:189`/`:225`/`:468`);
  **ADV-02** `advanceGame() returns (uint8 mult)` decoded in the Game wrapper (`AdvanceModule:154` +
  `DegenerusGame:288` + interface) — the `rewardable` bool COLLAPSED into the `mult==0` sentinel (USER
  deviation, NON-WIDENING; §5); **ADV-03** standalone `advanceGame()` functional UNREWARDED liveness fallback
  with the free-fallback caller path intact; **ADV-04** (SPEC, Complete) frozen advance-consume — only frozen
  VRF-window state read even same-tx as autoOpen/autoBuy (TST-01 empirical); **ADV-05** mid-day partial-drain
  router-rewardable advance-leg work (`mult=1`, no escalation, `:217-218`).
- **GAS (6):** **GAS-01** (GAS, Complete) worst-case-first per-category MARGINAL gas derivation + router overhead
  (the D-07 flat-per-tx sizing); **GAS-02** (GAS, Complete) flat-per-tx break-even @0.5gwei BURNIE re-peg using
  per-item MARGINAL (the CR-01 self-crank-faucet rule; `BUY_BATCH=50`/`OPEN_BATCH=100`/`ADVANCE_RATIO=2`/
  `BUY_RATIO 3/2`/`OPEN_KNEE=5`, landed under the 331 USER gate); **GAS-03** (SPEC, Complete) single day-start
  stall epoch satisfied-by-DELETION (advance is the sole stall epoch); **GAS-04** (GAS, Complete) stall
  multiplier (1/2/4/6) kept ADVANCE-ONLY, faucet-bounded; **GAS-05** (GAS, Complete) WR-01 round-trip guard
  proves no positive-EV self-crank loop under the flat-per-tx model (the open knee kills the small-batch corner);
  **GAS-06** (GAS, Complete) `autoResolve`->`degeneretteResolve` rename + flat ~1-BURNIE re-peg (`RESOLVE_FLAT_BURNIE=1e18`),
  >=3-NON-WWXRP pay-gate, `NoWork()`-on-zero, WWXRP excluded, results byte-identical.
- **GASOPT (4-active):** **GASOPT-01** `owedMap` storage-pointer hoist both loops (`MintModule:399`/`:673`,
  behavior-identical); **GASOPT-02** SUBSUMED into GASOPT-03 (pointer row, not counted — the per-iteration
  `claimableWinningsOf` hoist is folded into the batched game-side read); **GASOPT-03** NEW `keeperSnapshot`
  batching the per-player `claimableWinningsOf` STATICCALLs (`DegenerusGame:2628`, same values, fewer
  cross-contract calls); **GASOPT-04** `AutoBought` event dropped, oracle migrated to `lastAutoBoughtDay`
  (grep-ZERO event, no SAFE-03/H-CANCEL-SWAP weakening); **GASOPT-05** per-iter `isOperatorApproved(player,
  AfKing)` `:676` removed, subscribe-time gate KEPT — the 4 OPEN-E protections re-attested HOLD (§3.B, the HARD
  BLOCKING CONDITION SATISFIED).
- **TST (5):** **TST-01** (TST, Complete) freeze-invariant fuzz — router advance-consume reads only frozen state
  mid-tx + autoBuy-during-rngLock-SAFE + autoOpen-blocked-no-maroon + one-category-no-double-pay; **TST-02** (TST,
  Complete) one-rewarded-category-per-tx + reentrancy double-pay regression (the D-01b ROUTER-07 backstop) +
  parameterless default-batch + UNREWARDED escapes; **TST-03** (TST, Complete) advance UNREWARDED standalone /
  REWARDED via `doWork` + GASOPT-01/03 same-results (gas-only); **TST-04** (TST, Complete) NON-WIDENING full-suite
  regression (666/42/17 BY NAME) incl. the GASOPT-04 oracle migration; **TST-05** (TST, Complete) `degeneretteResolve`
  flat ~1-BURNIE/tx + >=3-gate + revert-on-no-work + WWXRP-excluded + byte-identical RESULTS.
- **SWEEP (3):** **SWEEP-01** the 3-skill genuine-PARALLEL adversarial sweep (333-02; 0 FINDING_CANDIDATE / 21
  rows / dual-gate skeptic filter); **SWEEP-02** the NON-WIDENING delta-audit (333-01; 5 surfaces + zero orphan
  hunks + the 4 invariants + OPEN-E + VRF-freeze + 666/42/17 BY NAME); **SWEEP-03** this `audit/FINDINGS-v49.0.md`.
- **BATCH (3):** **BATCH-01** (SPEC, Complete) the SPEC design-lock (`0eae9c28`, the 4 invariants + the settled
  signatures + the grep-attestation); **BATCH-02** the ONE batched USER-APPROVED IMPL diff (`63bc16ca`,
  producer-before-consumer, HARD STOP at the commit boundary); **BATCH-03** this TERMINAL closure flip (333-04 —
  re-attest all 36 + the atomic 5-doc flip + chmod 444).

---

## 4. Adversarial-Pass Disposition (folded from 333-02-ADVERSARIAL-LOG.md)

### §4.1 Outcome
3-skill GENUINE PARALLEL_SUBAGENT sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`;
`/degen-skeptic` OUT per D-271-ADVERSARIAL-02), run as 3 concurrent background Task spawns from the orchestrator
(the v45 P314 / v47 P324 / v48 P328 genuine-parallel path — the orchestrator holds the Task tool, NOT the HYBRID
fallback). **21 deduplicated charged-probe rows across the unified keeper surface + composition: 15
NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN + 0 FINDING_CANDIDATE.** 0 elevations reached FINDING_CANDIDATE through the
dual-gate skeptic filter; the charge was WEIGHTED (CONTEXT D-01 — the unified router is the v49-novel surface):
TIER-A = advance-timing MEV / same-tx bundling (zero-day-hunter Pitfall 3) + bounty economics / stall-multiplier
abuse / faucet self-crank (economic-analyst lead + auditor corroboration); TIER-B = composed reentrancy (Pitfall
6, re-attest only) + unrewarded-advance liveness backstop (auditor). Each subagent probed the actual frozen
subject via `git show 4c9f9d9b:contracts/...` (READ-ONLY; `git diff 4c9f9d9b HEAD -- contracts/` empty
throughout). **Clean closure outcome: ZERO FINDING_CANDIDATEs survive — the `0 NEW_FINDINGS` clause of the
closure verdict HOLDS.**

### §4.2 FINDING_CANDIDATEs
**None.** Zero elevations reached FINDING_CANDIDATE. Per CONTEXT D-04, had any MEDIUM+ survived, it would be
recorded here WITHOUT a contract fix (the subject is FROZEN at `4c9f9d9b`) and routed to the 333-04 closure
gate for USER adjudication (default leaning DEFER->v50 with the fix design locked). No such candidate exists.

### §4.3 SAFE_BY_DESIGN rows (informational)
- **Composed reentrancy router->game->`creditFlip` (TIER-B, zero-day-hunter P6).** SAFE_BY_DESIGN re-attestation
  per the USER-locked 332 stance: under RD-4 there is exactly ONE `creditFlip` in `doWork` (`:917`), CEI-LAST,
  after the one-category early-return, fed by legs that return raw counts/`mult` and never self-credit. Every
  external call targets a pinned `ContractAddresses.*` (GAME / COINFLIP); the bounty is minted FLIP CREDIT
  through the `claimableWinnings` pull ledger, never an ETH push the keeper-contract receives (the only
  `.call{value}` is the player `withdraw` `AfKing:325`, CEI); `AF_KING` is in the `onlyFlipCreditors` set. 0
  untrusted-push legs -> 0 ROUTER-07 blocker. No attacker harness built (the D-01b TST-02 double-pay regression
  is the empirical backstop).
- **autoOpen / boxesPending capturing the in-flight word (zero-day-hunter).** rngLock-aware no-op (RD-3); the box
  outcome derives purely from the already-finalized index word (`DegenerusGame:1655-1724`).
- **Mid-day partial-drain pinned `mult=1` (economic-analyst).** The escalation block is structurally unreachable
  on the mid-day path (`AdvanceModule:193-224`/`:217-218`).
- **Gameover path pinned `mult=0` (economic-analyst).** Explicit zero-return (`AdvanceModule:185`) + the
  `if (mult > 0)` guard (`AfKing:899`); flip-credit is worthless at gameover anyway.
- **Bounty-stacking — invariant (a) re-attested (economic-analyst).** The mutually-exclusive `else-if` => exactly
  one category; exactly ONE `creditFlip` `:917`, CEI-last, gated `bountyEarned>0`; legs never self-credit.
- **Self-exclude / ETH-work-gate present (economic-analyst).** The keeper receives only illiquid flip-credit
  (`:917`); the purchase value is debited from the subscriber's prepaid pool (`fundingSource ?? player`); a
  no-op walk pays nothing (`if(bountyEarned>0)` `:911-912`).

Plus 15 NEGATIVE-VERIFIED probed-no-issue rows (333-02 §C.2 P1/P2/P4/P5/P7/P11/P12/P13/P15/P16/P17/P18/P19/P20
+ the OPEN-E corroboration P21): the same-tx RNG-capture / nudge-interleave (Gate-1 lock-gate + consume-before-
unlock ordering; `reverseFlip` reverts in-window), the discovery-view perturbation (pure reads, no VRF), the
buy-leg-during-rngLock VRF-write (RD-2 freeze-safe), the stall-multiplier-abuse / faucet self-crank buy/open/
advance legs (deeply -EV at every gas price >=0.5 gwei — advance×6 ~ 10.62 gwei covers ~11-21 gas vs >150k real,
~5 orders of magnitude margin; buy ~99.999% loss; open below-knee pro-rated), and the liveness-backstop free-
fallback callers (all intact, NOT in the v49 delta).

**Benign IMPL/SPEC reconciliation note (NOT a finding).** The 329-SPEC R1 text specified `advanceGame` returning
`(uint8 mult, bool rewardable)`; the frozen IMPL @ `4c9f9d9b` returns only `(uint8 mult)` — the `rewardable` bool
was COLLAPSED into the `mult==0` sentinel (the USER deviation: `mult>0` => rewardable, `mult==0` => gameover pays
nothing). Attested NON-WIDENING in 333-01 §5: the rewardable information is fully preserved in the `mult` channel,
the interface matches the contract signature verbatim, and no payout path widened (it SHRINKS the surface). See §5.

### §4.4 Skeptic-Reviewer Filter Attestation
`/degen-skeptic` is OUT as a skill; the skeptic FUNCTION is the dual-gate, applied at two points: (1) per-skill
self-arm — each skill armed both lenses on its own candidates before returning; (2) orchestrator integration-time
re-application — the orchestrator re-applied both lenses to every §B row when assembling §C.
- **Gate 1 — structural-protection lens.** Does a structural mechanism already prevent the elevation? If yes ->
  NEGATIVE-VERIFIED or SAFE_BY_DESIGN.
- **Gate 2 — 3-condition EV lens.** (a) manifests WITHOUT an attacker / is positive-EV; (b) magnitude material;
  (c) severity survives the skeptical re-read. A FINDING_CANDIDATE survives BOTH gates.

All 21 charged-probe rows were filtered. Every TIER-A row failed at least one gate: the same-tx/MEV probes failed
Gate-1 (the lock-gate + consume-before-unlock ordering — invariant (b)) and Gate-2(a) (`reverseFlip` reverts
in-window); the bounty-economics probes failed Gate-1 (the one-category `else-if` + single CEI-last `creditFlip`
— invariant (a); the time-keyed permissionless stall ladder) and Gate-2(a) (every leg deeply -EV at any gas price
>=0.5 gwei — the sub-gwei `BOUNTY_ETH_TARGET` keeps the faucet bound by ~5 orders of magnitude). The TIER-B rows
were re-attestations: reentrancy SAFE_BY_DESIGN per the USER-locked 332 stance (no attacker harness); the liveness
backstop NEGATIVE-VERIFIED (all free-fallback callers intact, D-04a). The OPEN-E corroboration confirmed all 4
protections HOLD without `:676`. Two genuine-hunt self-discards recorded: zero-day-hunter chased the line-257
non-zeroing `totalFlipReversals` read (self-discarded at Gate-1 — inside the lock window; the authoritative zero
is in `_applyDailyRng` same call); economic-analyst chased the v49-novel re-homed advance-leg faucet + the
advance×6 max-escalation ladder (self-discarded at Gate-2(a) — deep -EV; separately recorded an advance-leg
round-trip test-coverage observation as an informational note, §C.3a, explicitly NOT elevated). No "tricked into
approving" actor modeled (per [[open-e-operator-approval-trust-boundary]]).

**Read-only attestation.** `git diff 4c9f9d9b HEAD -- contracts/` is empty throughout the sweep — no
`contracts/*.sol` was opened or mutated; all source was read via `git show 4c9f9d9b:...`. **Attestation: 0
FINDING_CANDIDATEs survived the dual-gate.** SWEEP-01 outcome = `0 NEW_FINDINGS`, KNOWN_ISSUES_UNMODIFIED.

---

## 5. LEAN Regression Appendix (folded from 333-01 §6)

### §5a Suite Baseline — 666 pass / 42 fail / 17 skip of 708, NON-WIDENING BY NAME vs the v48.0 baseline
Per the 332-06 ledger `test/REGRESSION-BASELINE-v49.md` (the full `forge test` tree). The Phase-330 keeper-router
diff `63bc16ca` + the Phase-331 GAS-2 re-peg `4c9f9d9b` flipped a set of **17 premise-retired reward-rehoming
tests** from green-at-v48 to red-at-v49; 332-05 (TST-04 part A) **DELETED all 17** (their v49 invariants
re-authored fresh at 332-02/03/04, zero coverage lost) and `git mv`-**renamed the 5 surviving `Crank*` files to
`Keeper*`**. The passing count stayed flat at **666** across the deletion (the deletions removed only RED tests).

### §5b The BINDING gate: failing-NAME-set EQUALITY, not a count (the Pitfall-3 guard)
**NON-WIDENING = a strict failing-NAME-set equality**, NOT a count match: at the v49 TST HEAD the live `forge
test` failing set **== the 42 v48.0 §2-union reds BY NAME** (`test/REGRESSION-BASELINE-v48.md §2`, carried
forward verbatim — Bucket A 8 VRF/RNG + Bucket B 34 stale-harness/v48-behavioral + Bucket C 0 HERO-foundry = 42).
The ledger §6 verified BOTH directions empirically: `live failing set - v48 union = empty` (no new red outside
baseline) AND `v48 union - live failing set = empty` (no dropped baseline red) -> `live == v48 union BY NAME` is
TRUE. **Net-zero new regression.** Do NOT quote "42 failures, up from 40" — the gate is name-set equality, not an
arithmetic count delta.

### §5c The 17 deletions + 5 renames are ATTRIBUTED via the ledger, NOT counted as regression
- **17 premise-retired deletions** (ledger §3, commit `8041451d`, 4 files / 736 deletions): each enumerated BY
  NAME with per-test re-homing + the v46 provenance commit. Classified reward-shape (RD-4 + GAS-2 per-item-summed
  premise retired) or oracle-migration (RD-2 guard-drop / RD-5 entry-gate / GASOPT-04 `AutoBought`->`lastAutoBoughtDay`).
  The retired premises re-home into the fresh v49 proofs (flat-per-tx one-credit / self-keeper round-trip <=0 /
  `NoWork()`-on-no-work / RD-2 autoBuy-during-rngLock-safe / RD-5 no-marooned-boxes / per-item poison isolation)
  — zero coverage lost.
- **5 `Crank*`->`Keeper*` renames** (ledger §4, commit `52452fe1`, R094-R098 similarity): pure file-path +
  identifier churn, behavior-neutral, PROVEN by the byte-identical post-rename failing NAME set (666/42 both pre-
  and post-rename). The single deliberate `Crank` code residual (`testCrankBoxOpenStaysPostUnlock`, GREEN, in the
  NOT-renamed `RngFreezeAndRemovalProofs.t.sol`) is left unchanged per the explicit plan directive.

The file-path churn is attributed via the ledger, NOT counted as new regression.

### §5d SWEEP-02 NON-WIDENING attestation
Every `git diff 0cc5d10f 4c9f9d9b -- contracts/ test/` hunk is attributable to a known v49-scope commit: the
batched IMPL/redesign diff `63bc16ca` (the 5-file router/advance contract surface), the GAS-split diff `4c9f9d9b`
(the 331-05 re-peg constants in `AfKing.sol` + `DegenerusGame.sol`), and the AGENT-committed 331 GAS + 332 TST
test work (the GAS harnesses, the 332 proofs, `8041451d` the 17 deletions, `52452fe1` the 5 renames, `11d1b1f5`
the regression ledger). `git diff 4c9f9d9b HEAD -- contracts/` is **empty** (zero contract mutation in this
terminal phase; subject byte-frozen). **NON-WIDENING confirmed.**

---

## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification
- **KNOWN-ISSUES.md byte-unmodified** vs v48 (`git diff 0cc5d10f HEAD -- KNOWN-ISSUES.md` empty;
  KNOWN-ISSUES.md lives at the REPO ROOT, not `audit/`). No KI promotion/demotion; the SC1 sweep surfaced no
  KI-eligible item (0 FINDING_CANDIDATE).
- **RNG-freeze intact** under the router composition — the unified same-tx path introduces NO in-window SLOAD
  into the advance-consume (the v45 north-star, ADV-04; §3.B): autoBuy (leg 1) runs PRE-ENTROPY at day-open
  before advance requests the word (RD-2 freeze-safe-by-construction), the advance leg consumes via the
  return-tuple decode with the AdvanceModule consume logic byte-untouched, and autoOpen (leg 3) is rngLock-BLOCKED
  (`boxesPending()` false during rngLock `DegenerusGame:1656` + the entry-gate `:1692`) so the open path never
  executes inside the protected window. The sole `totalFlipReversals` writer `reverseFlip` is hard-gated
  `if (rngLockedFlag) revert RngLocked();` (`DegenerusGame:2195`) — dead the entire time the word is known.
- **Obligations conserved** — the bounty stays minted FLIP CREDIT from the finite-pool / self-exclude /
  ETH-work-gate pattern ([[project_free_burnie_crank_button]]): exactly ONE `creditFlip` in `doWork`, CEI-LAST
  (`AfKing:917`), routed through the `claimableWinnings` pull ledger, never an ETH push the keeper receives; the
  keeper is never a payee of an untrusted send; the autoBuy purchase value is debited from the subscriber's
  prepaid pool (no new ETH-send path introduced). The advance bounty re-home moved the credit's PAYEE (from the
  in-callee advance caller to the `doWork` `msg.sender`) but added NO new emission; the `degeneretteResolve`
  re-peg replaced a per-item break-even with a flat ~1-BURNIE/tx (a count-independent SHRINK, faucet-bounded).
  No accounting axis widened.

---

## 7. Prior-Artifact Cross-Cites
- **v49.0 phase artifacts:** Phase 329 SPEC (`0eae9c28`, 3 plans, VERIFICATION 8/8) + `329-SPEC.md` + the 2
  ATTEST docs (`329-ATTEST-ROUTER-ADVANCE.md` / `329-ATTEST-DEGENERETTE-RESOLVE.md`); Phase 330 IMPL (`63bc16ca`,
  USER-APPROVED batched diff, BATCH-02) + the 9 plan SUMMARYs + `330-VERIFICATION.md`; Phase 331 GAS (`4c9f9d9b`,
  USER-APPROVED second gate) + the calibration record (`331-04`); Phase 332 TST (`95aaf340`, 6 plans) + the 6
  SUMMARYs + the regression ledger `test/REGRESSION-BASELINE-v49.md`; Phase 333 logs (`333-01-DELTA-AUDIT.md`,
  `333-02-ADVERSARIAL-LOG.md` + the 3 per-skill sweep outputs).
- **Prior milestone FINDINGS:** `audit/FINDINGS-v48.0.md` (the 9-section template + the carried-forward SWAP
  cash-share advisory); `audit/FINDINGS-v47.0.md` / `audit/FINDINGS-v46.0.md` / `audit/FINDINGS-v44.0.md` (the
  9-section templates + the v44 §9d maximalist handoff register).
- **Carry-forward anchors:** the v48 closure signal `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029`
  (the v49 audit baseline); the v44 §9d maximalist handoff register (135 anchors — NOT live vectors), carried
  forward unchanged (§9d).

---

## 8. Forward-Cite Closure
- **0 prior-milestone findings carried into v49.0.** v48.0 closed with 0 NEW findings (F-47-01 + F-47-02
  RESOLVED-AT-V48); there was no deferred finding to resolve this milestone.
- **Newly-surfaced 333-02 finding:** NONE. The sweep produced 0 FINDING_CANDIDATE; the advance-leg faucet
  round-trip test-coverage observation (§4.3 / 333-02 §C.3a) is informational only (the EV margin is ~5 orders
  of magnitude — NOT a coverage gap worth a finding; the buy/open round-trip tests already exercise the shared
  `(BOUNTY_ETH_TARGET·PRICE_COIN_UNIT)/mp` unit formula via `testRouterBuyRewardMatchesLiveUnitRatio`).
- **Prior-milestone v49 descriptive seeds now SHIPPED (no longer forward-seeds):** the unified keeper-router
  redesign (ROUTER-01..10), the advance-bounty re-home (ADV-01..05), the break-even flat-per-tx bounty re-peg
  (GAS-01..05), the `degeneretteResolve` rename + flat ~1-BURNIE re-peg (GAS-06), and GASOPT-01/03/04/05.
- **v49.1 / v50 forward-seeds carried forward (deferred, OUT of v49):**
  - **Whale-pass-claim O(1)-refactor seed.** Replace the box-open whale-pass inline 100-loop `_queueTickets`
    mint (`LootboxModule.sol`, the gas monster behind the 331 whale-pass-weighted autoOpen budget) with a cheap
    O(1) pending claim + a player-paid `claimWhalePass()`. Win: uniform O(1) box open -> flat `OPEN_BATCH`.
    MUST-verify: RNG-freeze (queues a future-level -> likely safe, PROVE), the rngLock liveness gate, the
    `_applyWhalePassStats` timing. A contract change, OUT of v49.
  - **Mintmodule processed/future advance-divergence seed (HIGH *candidate*, unconfirmed).** MintModule has two
    near-dup per-ticket loops: `processTicketBatch` advances the within-player startIndex by `writesUsed>>1` vs
    `processFutureTicketBatch`'s correct `+=take` -> divergent trait indices when a player's owed splits across a
    budget slice. Needs reachability + a same-traits test before elevation. Deferred, NOT v49.0 scope.
  - **AfKing pass-gated subscription + cheaper validity seed (USER-raised 2026-05-27).** Remove the
    BURNIE-purchased subscription window (`burnForKeeper` / `paidThroughDay` / `WINDOW_DAYS`) and gate an active
    AfKing sub on PASS-HOLDING only. Since passes cannot be lost, encode the pass's level horizon AT SUBSCRIBE
    (`validThroughLevel`; a deity pass is permanent -> max sentinel) and check `currentLevel <= validThroughLevel`
    per iteration — the SAME cheap packed-field comparison as today's `paidThroughDay`, with NO per-iteration
    external pass read (so it does NOT walk back the GASOPT-05 `:676` per-iter-external-check removal). At a
    level-crossing, re-read for a new/upgraded pass and REFRESH-or-evict (NOT an unconditional kick); the only
    external pass read is the rare crossing. Third-party daily-box funding (`fundingSource` / `depositFor`) STAYS
    (so the OPEN-E operator-approval surface is retained, NOT mooted). A contract change to `AfKing.sol`, OUT of v49.
- **Carry-forward (NOT live vectors):** the v44 §9d maximalist handoff register (135 anchors) carries forward
  unchanged ([[project_rnglock_audit_disposition]]).

---

## 9. Milestone Closure Attestation

### 9a. Closure Verdict

**Locked target (ROADMAP Phase 333 goal + the v49 surface set, for the record):**
`UNIFIED_KEEPER_ROUTER SHIPPED (parameterless doWork() one-category early-return, autoBuy->advance->autoOpen, single creditFlip CEI-last, NoWork() revert); ADVANCE_BOUNTY_RE-HOMED (3 in-callee creditFlip sites removed, advanceGame returns (uint8 mult, bool rewardable), standalone advance UNREWARDED + the free-fallback callers intact); BOUNTY_RE-PEGGED break-even @0.5gwei flat-per-tx (per-item MARGINAL, CR-01 self-crank-faucet rule, WR-01 round-trip guard -EV); DEGENERETTE_RESOLVE RENAMED + RE-PEGGED (flat ~1-BURNIE lose, >=3-NON-WWXRP gate, NoWork()-on-zero, WWXRP excluded, results byte-identical); GASOPT-01/03/04/05 SHIPPED (owedMap hoist / batched keeperSnapshot / AutoBought dropped / per-iter isOperatorApproved :676 dropped); 4_STRUCTURAL_INVARIANTS INTACT (one-category early-return / frozen advance-consume / free-fallback caller / single day-start epoch satisfied-by-deletion); OPEN-E_4-PROTECTIONS RE-ATTESTED (consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub) WITHOUT :676; RNG_FREEZE_INTACT under the router composition; NON-WIDENING 666/42/17 (42-red == v48 §2 union BY NAME); 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`

**Actual verdict (the sweep surfaced 0 FINDING_CANDIDATE -> the `0 NEW_FINDINGS` clause HOLDS UNAMENDED; the
`advanceGame` return shape is recorded with the ACTUAL `(uint8 mult)` IMPL signature per the §5 USER-deviation
reconciliation note — a NON-WIDENING surface SHRINK, NOT a finding):**
`UNIFIED_KEEPER_ROUTER SHIPPED (parameterless doWork() one-category early-return, autoBuy->advance->autoOpen, single creditFlip CEI-last, NoWork() revert); ADVANCE_BOUNTY_RE-HOMED (3 in-callee creditFlip sites removed, advanceGame returns (uint8 mult) [the SPEC's rewardable bool COLLAPSED into the mult==0 gameover sentinel — USER deviation, NON-WIDENING, §5], standalone advance UNREWARDED + the free-fallback callers intact); BOUNTY_RE-PEGGED break-even @0.5gwei flat-per-tx (per-item MARGINAL, CR-01 self-crank-faucet rule, WR-01 round-trip guard -EV — every leg ~99.9%+ negative, advance×6 ~5-orders-of-magnitude margin); DEGENERETTE_RESOLVE RENAMED + RE-PEGGED (flat ~1-BURNIE lose RESOLVE_FLAT_BURNIE=1e18, >=3-NON-WWXRP gate, NoWork()-on-zero, WWXRP excluded, results byte-identical); GASOPT-01/03/04/05 SHIPPED (owedMap hoist / batched keeperSnapshot / AutoBought dropped / per-iter isOperatorApproved :676 dropped); 4_STRUCTURAL_INVARIANTS INTACT (one-category early-return / frozen advance-consume / free-fallback caller / single day-start epoch satisfied-by-deletion); OPEN-E_4-PROTECTIONS RE-ATTESTED HOLD (consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub) WITHOUT :676 [the GASOPT-05 HARD-BLOCKING condition SATISFIED — no revert, closure NOT blocked]; RNG_FREEZE_INTACT under the router composition; NON-WIDENING 666/42/17 (42-red == v48 §2 union BY NAME); 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`

The only deviation from the locked target is the `advanceGame` return clause's `(uint8 mult, bool rewardable)` ->
`(uint8 mult)` correction (the SPEC's `rewardable` bool was collapsed into the `mult==0` gameover sentinel at
IMPL — a USER deviation recorded as a benign NON-WIDENING surface SHRINK, §5). All other clauses hold verbatim;
`0 NEW_FINDINGS` is UNAMENDED.

### 9b. 5-Phase Wave Summary
Phase 329 (SPEC design-lock `0eae9c28`, 3 plans, VERIFICATION 8/8, the 4 structural invariants + the redesigned
shared signatures locked) + 330 (IMPL `63bc16ca`, USER-APPROVED batched router/advance-redesign diff, BATCH-02,
9 plans/8 waves, suite 616/58) + 331 (GAS `4c9f9d9b`, the worst-case-marginal break-even @0.5gwei peg + the
`degeneretteResolve` flat re-peg, 5 plans, USER-approved second gate) + 332 (TST `95aaf340`, 6 plans, freeze-fuzz
+ one-category + reward-routing + the NON-WIDENING 666/42/17 ledger, ZERO contract mutation) + 333 (TERMINAL —
this deliverable; SOURCE-TREE FROZEN at `4c9f9d9b`; SC2 delta-audit + SC1 3-skill genuine-PARALLEL sweep +
regression + gated closure flip). NOTE: **5 phases** (v48 had 4 — the dedicated GAS phase is the difference).
Closure signal: `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`.

### 9c. Closure Signal
**`MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`** (resolved to the Phase 333 audit-deliverable / closure commit in 333-04;
contracts byte-identical to the frozen subject `4c9f9d9b`). Verbatim propagation targets (resolved at the 333-04
closure gate by the single sed-style SHA substitution):
1. Frontmatter `closure_signal:` + `audit_subject_head:`.
2. §1 Audit Subject prose.
3. §9b / §9c references.
4. ROADMAP.md (the v49.0 milestone flip).
5. STATE.md (Last Shipped Milestone) + MILESTONES.md (archive entry) + PROJECT.md.
6. REQUIREMENTS.md (all 36 v49.0 requirement row-flips re-attested at closure).

### 9d. Deferred to v49.1/v50+ — Handoff Register
- **0 NEW findings deferred.** The SC1 sweep produced 0 FINDING_CANDIDATE; there were no prior-milestone
  deferred findings carried into v49 (v48 closed clean). Nothing is carried forward as a finding.
- **Informational ADVISORY (NOT a finding) — the v48 SWAP withdrawable-cash ceiling 60% (code) vs <=40% (design
  memo), carried-forward-UNMODIFIED.** Verbatim from `audit/FINDINGS-v48.0.md` §9d: "Recorded for USER
  reconciliation… reconcile the design memo / verdict text to the implemented `<=60%` cash ceiling, OR confirm
  60% was the intended IMPL calibration. No-arb HOLDS at the 60% ceiling (max withdrawable cash 9.9% of face);
  no positive-EV path; no solvency impact. `0 NEW_FINDINGS` unaffected." The SWAP path is OUTSIDE the v49 blast
  radius (none of the 5 v49 surfaces touched it — 333-01 §7); USER accepted <=60% as canonical (REQUIREMENTS
  Out-of-Scope). It does NOT amend the verdict or stop closure.
- **Advance-leg faucet round-trip — test-coverage observation (informational, NOT a finding).** Recorded in §4.3
  / 333-02 §C.3a: the advance-leg lacks a dedicated round-trip EV test, but the margin is ~5 orders of magnitude
  and the shared unit formula is exercised by the buy/open round-trip tests. Corroborates the SWEEP-02 §3
  attestation; explicitly NOT elevated.
- **v49.1/v50 forward-seeds (§8):** the whale-pass-claim O(1)-refactor seed; the mintmodule processed/future
  advance-divergence candidate (HIGH *candidate*, unconfirmed); the AfKing pass-gated-subscription + cheaper
  level-horizon validity seed (USER-raised 2026-05-27). All are contract changes, OUT of v49.0 scope.
- The v44 §9d maximalist handoff register (135 anchors) carries forward unchanged (NOT live vectors).

---

*v49.0 TERMINAL findings authored 2026-05-27. Source-tree frozen throughout (`git diff 4c9f9d9b HEAD --
contracts/` empty). 0 NEW findings (the 3-skill genuine-PARALLEL sweep surfaced 0 FINDING_CANDIDATE across 21
charged-probe rows; the OPEN-E 4-protection HARD-BLOCKING re-attestation HOLDS without the per-iter :676 check
— no GASOPT-05 revert, closure NOT blocked); the v48 SWAP cash-share advisory carried-forward-unmodified; the
`advanceGame` `(uint8 mult)` IMPL signature recorded per the §5 USER-deviation reconciliation note (NON-WIDENING).
Closure signal `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` resolves at the Phase 333 closure commit (333-04).*
