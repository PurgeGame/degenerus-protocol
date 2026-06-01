---
phase: 352-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw
plan: 03
milestone: v55.0
milestone_name: AfKing-in-Game Redesign
audit_baseline: 20ca1f79
source_tree_frozen_ref: 453f8073
audit_subject_head: "MILESTONE_V55_AT_HEAD_<sha>"
closure_signal: MILESTONE_V55_AT_HEAD_<sha>
deliverable: audit/FINDINGS-v55.0.md
new_findings: 0
new_findings_disposition: 0 NEW_FINDINGS — the 3-skill genuine-PARALLEL adversarial sweep produced 0 FINDING_CANDIDATEs across 21 charged-probe rows (18 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN); the box-stamp-freeze spine holds adversarially against the AS-BUILT COMMITTED 4-field/DAY-keyed/live-level model (FREEZE-01/02/03), the no-valve STAGE is revert-free-by-construction + fail-loud-on-solvency + gameover-unblocked (REVERT-01/02 + SOLVENCY-01), the two-path open is storage-isolated with an intentionally-shared monotonic EV/boon budget (BOX-04/05 + EVCAP-01), and the OPEN-E 4-protection + CONSENT-02 set-mutation HOLD (the HARD BLOCKING condition SATISFIED — closure NOT blocked); KNOWN-ISSUES.md byte-unmodified vs v54. ONE out-of-scope informational advisory (O1) recorded:  a PRE-EXISTING, SYMMETRIC, immaterial lootbox-quest BURNIE double-credit in the UNCHANGED DegenerusQuests core — NOT a v55 vector (not in the v55 delta; identical across the manual purchaseWith path; a fixed day-idempotent <=300-BURNIE flip-stake OFF the ETH/claimablePool/solvency path) — routed to a future quest-core audit lane + the v52 consolidated cross-model audit. It does NOT amend the 0 NEW_FINDINGS verdict.
---

# v55.0 Findings — AfKing-in-Game Redesign (Terminal)

## 1. Audit Subject + Baseline

**Audit Baseline.** v54 de-custody HEAD `20ca1f79` (the 343 SPEC + 344 IMPL game-side `afkingFunding`
ledger). **v54.0 closed-as-superseded with NO ship signal** — there is intentionally no
`MILESTONE_V54_AT_HEAD` string (345/346/347 were dropped -> folded into v55; the diff was never audited via a
347 TERMINAL), so this report cites the **raw SHA** `20ca1f79` as the baseline. v55.0 closure HEAD is
`MILESTONE_V55_AT_HEAD_<sha>` (the literal placeholder; resolved to the findings-deliverable / closure-flip
HEAD by 352-04 — the self-referential closure commit's own SHA; see §9c). SOURCE-TREE FROZEN reference for the
terminal: `453f8073` (`contracts/` byte-frozen; `git diff 453f8073 HEAD -- contracts/` empty throughout Phase
352 — EMPTY-CONFIRMED).

**Subject.** The frozen subject HEAD `453f8073` = the AfKing-in-Game fold + box redesign. Unlike v49 (whose
v48->v49 delta was 5 files), the v54->v55 step **IS the AfKing dissolution** — `git diff 20ca1f79 453f8073 --
contracts/` is **13 files, +1652 / -1165** — so the source-tree is NOT byte-identical to the baseline (that
"byte-identical to `20ca1f79`" framing held ONLY at 348-SPEC, pre-IMPL). The v54->v55 `contracts/*.sol` landing
is exactly **TWO** commits on top of the baseline (`git log --oneline 20ca1f79..453f8073 -- 'contracts/*.sol'`):
- `77c3d9ef` — the **349.1** AfKing box redesign (USER-APPROVED hand-review): the afking box resolves at the
  LIVE level (`_rollTargetLevel(level+1, seed)`, mirroring `resolveLootboxDirect`) with the RNG word pinned to
  the FROZEN stamp-day's `rngWordByDay[lastAutoBoughtDay]` (**DAY-keyed**, not lootbox-index-keyed) + the seed
  using the FROZEN stamped day; the per-day `_afkingEpoch` epoch (+pack/unpack) + the stamp `index` field
  DROPPED; the process STAGE's NO-ORPHAN guard FIRST in the loop; the ticket/lootbox split (P2); the
  permissionless router renamed `doWork()` -> `mintBurnie()`; the dead `AF_KING` `batchPurchase`/`BatchBuy` +
  `onlyFlipCreditors` entry removed.
- `453f8073` — the **349.2** IMPL FIX (USER-APPROVED hand-review): restore quest-credit + affiliate for afking
  LOOTBOX subs (the box-redesign regression — only LOOTBOX subs lost the side-effects; TICKET subs kept them
  via `purchaseWith`), WITHOUT re-introducing the cold box-ledger — per-buy BURNIE flip-credit OFF the
  ETH/`claimablePool` path (handlers-before-score); the `autoBuy` stub dropped.

**350 GAS was Outcome A = NO net contract change** (`350-OUTCOME.md`: GAS-01/02 CONFIRMED-STRUCTURAL by the
349/349.1 relocation, GAS-03 REJECTED-with-reasoning) — there is **no 350 commit in the delta range**.

v55.0 is an **architecture refactor that dissolves the standalone `AfKing.sol` keeper contract into the
game-resident model**: subscriber state appends to `DegenerusGameStorage` (ARCH-01), a new `GameAfkingModule`
delegatecall owns subscribe/process/open/router (ARCH-02), `AfKing.sol` is DELETED (ARCH-03), and the Game
runtime code-size stays < 24,576 via a `claimAffiliateDgnrs`->`BingoModule` reclaim (ARCH-04). The box freeze
moves from the cold lootbox ledger into a per-sub **4-field stamp** (BOX-01..05); the freeze spine
(FREEZE-01/02/03), the discharged REVERT-FREE-CHAIN (REVERT-01/02), the EV-cap-at-open (EVCAP-01), the OPEN-E
4-protection (CONSENT-01/02), and the Phase-343 SOLVENCY-01 master invariant are all re-proven against the
as-built model. It ships the full 9-section deliverable, `chmod 444` at close (applied in 352-04, not here).

This is a **7-phase milestone** (348 SPEC / 349 + 349.1 + 349.2 IMPL / 350 GAS / 351 TST / 352 TERMINAL —
two inserted IMPL phases) and a **FULL close** — the internal 3-skill genuine-PARALLEL adversarial sweep +
delta-audit + `audit/FINDINGS-v55.0.md` run **IN-MILESTONE** (NOT deferred to the v52 consolidated audit, like
v54.0 and unlike v50.0/v51.0), because the redesign touches the **RNG-freeze + solvency spine** — the freeze
invariants + the discharged REVERT-FREE-CHAIN proof + SOLVENCY-01 are the load-bearing concerns and must be
adversarially probed in-milestone.

> **WARNING — STAMP-SHAPE CORRECTION (LOAD-BEARING — the as-built COMMITTED reality, re-grepped @ `453f8073`).**
> The COMMITTED `Sub` stamp is **4-field** `scorePlus1` (uint16) + `amount` (uint96) + `lastAutoBoughtDay`
> (uint32, the frozen seed day) + `lastOpenedDay` (uint32, the day-keyed no-double-open marker). **`index` was
> DROPPED** — the box word is **DAY-keyed** `rngWordByDay[lastAutoBoughtDay]`, NOT lootbox-index-keyed — and the
> **LEVEL resolves LIVE at open** (`DegenerusGameLootboxModule.sol:767/:800` `currentLevel = level + 1` ->
> `_rollTargetLevel(currentLevel, seed)`). The 349.1 commit `77c3d9ef` **SUPERSEDED** the 348-design-intent
> 5-field stamp `(index, amount, day, scorePlus1, baseLevelPlus1)` (D-348-07). The freeze proof targets the
> **SEED** `keccak256(rngWordByDay[day], player, day, amount)`; the EV-cap clamp
> `lootboxEvBenefitUsedByLevel[player][level+1]` is the **sole** live read at open; the differential oracle
> (afking-open == human-`openLootBox` at the same live level) proves equivalence (351-VERIFICATION.md "Corrected
> Freeze Target Compliance"). This report cites the **4-field** stamp throughout; it does **not** cite a 5-field
> stamp or a `baseLevelPlus1` Sub field anywhere.

---

## 2. Executive Summary

### Closure Verdict Summary
v55.0 ships the **AFKING-IN-GAME FOLD**: `AfKing.sol` is DISSOLVED into a `GameAfkingModule` delegatecall +
a `DegenerusGameStorage` append (ARCH-01..04), strictly removing a whole standalone contract's attack surface
and collapsing the v54 cross-contract de-custody plumbing into in-context SLOADs. It ships the **BOX REDESIGN**:
boons OFF -> `amount == spend`, a per-sub **4-field stamp** `(scorePlus1, amount, lastAutoBoughtDay,
lastOpenedDay)`, a **DAY-keyed** seed `rngWordByDay[lastAutoBoughtDay]`, a **LIVE-level** open byte-identical to
`openLootBox`, and a `lastOpenedDay` no-double-open marker (BOX-01..05). The **FREEZE SPINE is INTACT**
(FREEZE-01/02/03 re-proven against the as-built 4-field/DAY-keyed/live-level model — the 349.1 live-level
collapse NARROWS the frozen set to the SEED, strictly safe because level/score resolve LIVE like the human
path). The **REVERT-FREE-CHAIN is DISCHARGED** (REVERT-01 `_resolveBuy` validation invariants preserved
verbatim -> revert-free-by-construction; REVERT-02 no-valve form: class-B fail-loud-on-solvency + class-C
terminal-routing-unblocked). The **EV-cap is AT-OPEN** (EVCAP-01 RMW exactly-once, the buy-time write bypassed,
the clamp the sole live read, equivalent to v54). The **OPEN-E 4-protection RE-ATTESTS HOLD** (CONSENT-01/02
consent-gate-at-subscribe / default-self / no-escalation / trust-the-sub + the set-mutation no-cursor-advance-
after-swap-pop / cancel-tombstone-streak). **SOLVENCY-01 HELD NET** (the `afkingFunding` ledger rides INSIDE
`claimablePool`, no new aggregate). **GAS is Outcome-A** (GAS-01/02 structural to the relocation, GAS-03
REJECTED-with-reasoning). **RNG-freeze is INTACT** under the game-resident model. The SC1 delta-audit
(13 surfaces NON-WIDENING) + the SC1 3-skill genuine-PARALLEL adversarial sweep + the LEAN regression find the
change set sound with **0 NEW FINDINGS** — the sweep surfaced zero FINDING_CANDIDATE. One **out-of-scope
informational advisory** (O1, the pre-existing symmetric `DegenerusQuests` lootbox-quest double-credit) is
recorded for awareness; it is NOT a v55 vector (not in the v55 delta, identical on the manual path, immaterial
off-ETH) and does NOT amend the verdict (§4.3 / §8 / §9d).

### Verdict Math
- **Adversarial sweep (Phase 352 SC1, from 352-02):** 21 deduplicated charged-probe rows across the box-stamp
  freeze + liveness isolation + two-path open + the OPEN-E/affiliate carry-over — **18 NEGATIVE-VERIFIED /
  3 SAFE_BY_DESIGN / 0 FINDING_CANDIDATE**. 4 elevations were armed and ALL discarded through the dual-gate
  skeptic filter (FREEZE-iii live-level non-monotonic-price parity, C1 shared EV/boon budget, C3 EV-cap
  straddle, O1 quest-core double-credit). GENUINE PARALLEL_SUBAGENT (`/contract-auditor` + `/zero-day-hunter` +
  `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`); each probed the frozen subject via
  `git show 453f8073:contracts/...` (READ-ONLY).
- **Delta-audit (Phase 352 SC1, from 352-01):** every one of the 13 v55 contract surfaces attests NON-WIDENING
  vs `20ca1f79` with grep/diff anchors @ `453f8073`; the +1652/-1165 delta has ZERO orphan hunks (every hunk
  maps to exactly one of the six v55 work-item families: code-size reclaim / GameAfkingModule fold / storage
  append / box stamp+process+open / AfKing dissolution / 349.2 quest+affiliate restore). Kill-sets are grep-ZERO
  in mainnet code: `AfKing.sol` (DELETED — `git show` fails), the `AF_KING` address constant
  (`ContractAddresses.sol` 1->0, zero repo-wide refs), the stamp `index` / `_afkingEpoch`, the `AF_KING`
  `batchPurchase`/`BatchBuy`.
- **Regression:** NON-WIDENING **BY NAME (a strict SUBSET)** — foundry whole-tree `forge test` **603 pass /
  134 fail / 16 skip** (753 run) per `test/REGRESSION-BASELINE-v55.md` (the 351-09 ledger, TST-05). The live
  failing NAME set **subset of the empirically-established 148-name v54.0 `20ca1f79` baseline union BY NAME**
  (`v55 live - v54 union = empty` — the binding gate, 0 names outside baseline; `v54 union - v55 live = 14 names`
  — the §5c NARROWING, v54 reds the v55 adaptation FIXED red->green). The 134 classify into Bucket A (41
  VRF/RNG-window) + Bucket B (92 stale-harness/behavioral) + Bucket F (1 unseeded `DegeneretteBet.inv` flaky).
  The wholesale D-351-01 rewrite map + the D-351-02 removed-surface drops are attributed BY NAME (§5c), NOT
  counted as regression. The binding gate is failing-NAME-set SUBSET membership (`live - union == empty`), not an
  arithmetic count delta.

### Severity Counts
- CATASTROPHE 0 . HIGH 0 . MEDIUM 0 . LOW 0 . informational SAFE_BY_DESIGN 3 (the FREEZE-iii live-level parity,
  the C1 shared EV/boon budget, the C3 EV-cap straddle) . informational ADVISORY 1 (O1, the pre-existing
  out-of-scope `DegenerusQuests` lootbox-quest double-credit, NOT a v55 finding).

### KI Gating Rubric Reference
KNOWN-ISSUES.md (at the REPO ROOT) byte-unmodified vs v54 (`git diff 20ca1f79 HEAD -- KNOWN-ISSUES.md` empty,
§6). No KI promotion/demotion this milestone; the SC1 sweep surfaced no KI-eligible item (0 FINDING_CANDIDATE).

### Forward-Cite Closure Summary
**0 forward items resolved-this-milestone** (no prior-milestone deferred findings were carried into v55 — v54.0
closed-superseded with 0 NEW findings). The prior-milestone v55 descriptive seeds (the AfKing-in-Game fold + the
box redesign + the 349.2 quest/affiliate restore) are now **SHIPPED** (§8) — no longer forward-seeds. Two v56
forward-seeds are recorded for future milestones (§8): the batch-afking-affiliate-quest aggregation seed and the
terminal-decimator final-day streak-boost seed (both contract changes, OUT of v55). The separate **v52
consolidated cross-model audit** still folds the v55 surface into its cumulative sweep as an ADDITIONAL track —
NOT a substitute for this in-milestone close (§8).

### Attestation Anchor
All `contracts/` file:line anchors herein are sourced from the Phase 352 workstream logs (352-01-DELTA-AUDIT,
352-02-ADVERSARIAL-LOG), each re-grep-verified against the frozen subject `453f8073`
(`git diff 453f8073 HEAD -- contracts/` empty).

---

## 3. Per-Phase Sections

- **§3a Phase 348 — SPEC (design-lock).** The D-08 multi-doc SPEC set (6 plans / 4 waves, paper-only — ZERO
  contract mutation) — the locked v55.0 design under the canonical `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` §10:
  the FREEZE spine PROVEN on paper (`348-FREEZE-PROOF.md` FREEZE-01 freeze-completeness / FREEZE-02 pre-RNG
  index-binding / FREEZE-03 stamped-day determinism), the discharged REVERT-FREE-CHAIN + EV-cap invariants
  carried (`348-INVARIANT-CARRY.md` — the 4 LOCKED obligations with **obligation 4, the try/catch valve,
  DROPPED at D-348-04** -> REVERT-02 is the no-valve form), the §4 placement DECIDED = **required-path
  `advanceGame` STAGE** (D-348-01, `348-PLACEMENT-DECISION.md`, superseding SC3's "leans separate-legs"), the
  sequenced code-size reclaim plan (`348-CODE-SIZE-PLAN.md` — `claimAffiliateDgnrs`->`BingoModule` ~1.3 KB FIRST,
  Game MEASURED 24,358 B / 218 B headroom -> ARCH-04 MEASURED Complete), the GAS inventory
  (`348-GAS-INVENTORY.md`), the producer-before-consumer edit-order map (`348-IMPL-EDIT-ORDER-MAP.md`), and the
  OPEN-E/set-mutation carry-over confirmation. Reqs: FREEZE-01/02/03 . PLACE-01 . ARCH-04 (all Complete at SPEC).
  > **NOTE (the D-348-07 supersession):** 348-SPEC locked the stamp as the **5-field** `(index, amount, day,
  > scorePlus1, baseLevelPlus1)` (the SC1 -EV live-read admission overturned by stamping score+baseLevel). The
  > 349.1 IMPL `77c3d9ef` **SUPERSEDED** this — the COMMITTED shape DROPPED `index` (DAY-keyed `rngWordByDay`)
  > and resolves the LEVEL LIVE (so `baseLevelPlus1` is NOT stamped). This report describes the AS-BUILT 4-field
  > model; the FREEZE proofs below carry the supersession note (the live-level collapse NARROWS the frozen set to
  > the SEED — strictly safe).
- **§3b Phase 349 — IMPL (the carefully-sequenced batched fold + box redesign).** The single reconciled
  `contracts/*.sol` diff authored producer-before-consumer (code-size reclaim -> storage append ->
  GameAfkingModule process/open/router -> AdvanceModule STAGE -> interfaces -> AfKing dissolution). **Phase 349.1**
  (`77c3d9ef`, USER-APPROVED, 5 plans / 5 waves) revised the held-349 box machinery into its final form: the
  LIVE-level resolve (`_rollTargetLevel(level+1, seed)`), the DAY-keyed word `rngWordByDay[lastAutoBoughtDay]`,
  the FROZEN stamped-day seed, the `_afkingEpoch` + stamp-`index` DROP, the NO-ORPHAN guard, the P2 ticket/
  lootbox split, the `doWork`->`mintBurnie` rename, and the dead `AF_KING` `batchPurchase`/`BatchBuy` removal —
  the 4-field stamp the milestone ships. **Phase 349.2** (`453f8073`, USER-APPROVED, 1 plan / 1 wave) corrected
  the box-redesign regression: afking LOOTBOX subs again update quest status + pay affiliate (mirroring
  `purchaseWith`'s lootbox leg minus the cold ledger) — `quests.handlePurchase` BEFORE the score stamp
  (handlers-before-score -> `scorePlus1` from the returned post-buy streak) + both `affiliate.payAffiliate`
  branches -> a single `coinflip.creditFlip`; BURNIE flip-credit only -> the ETH/`claimablePool` accounting is
  byte-UNCHANGED (no solvency surface; DegenerusGame 22,855 B). Reqs: ARCH-01/02/03 . BOX-01..05 . REVERT-01/02 .
  EVCAP-01 . CONSENT-01/02 . PLACE-02 (Pending -> flip at 352-04 closure).
- **§3c Phase 350 — GAS (Outcome A — no net contract change).** 3 plans / 3 waves (W3 the contingent
  contract-boundary gate, never triggered). The `/gas-skeptic` adjudication under the security-over-gas floor
  (`350-GAS-SKEPTIC-VERDICTS.md` §7 = Outcome A): **GAS-01 + GAS-02 CONFIRMED-STRUCTURAL** (delivered by the
  349/349.1 relocation — the ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` -> one
  warm-dirty Sub-stamp write; the per-subscriber `afkingSnapshot`/`afkingFundingOf` cross-contract staticcalls ->
  in-context SLOADs; NO apply at 350, MEASURED at 351 TST-06); **GAS-03 REJECTED-with-reasoning** (warm SSTORE
  ~100 gas * (N-1) NOT ~2.9k; the 349.2-restored affiliate/quest/`creditFlip` are BURNIE flip-credit OFF the
  ETH+pool path -> no new batchable shared additive slot; `prizePoolsPacked` grep-absent; the mixed-chunk
  `purchaseWith` interleave hazard breaks the accumulate-and-flush identity; ~0.04%-of-chunk saving vs the audit
  surface on the SOLVENCY-01 spine — the v49 REJECT-with-reasoning precedent). `350-OUTCOME.md` records the
  no-diff close; `git diff` EMPTY throughout. Reqs: GAS-01/02/03 (all Complete at GAS).
- **§3d Phase 351 — TST.** 9 plans / Wave-0 fixture + the wholesale D-351-01 corpus adaptation + the D-351-02
  drops + the 4 new v55 proofs (sequential-on-main no-worktrees; ZERO contract mutation; gsd-verifier PASS 6/6,
  `351-VERIFICATION.md` status passed) — TST-01 freeze/determinism (`V55FreezeDeterminism.t.sol`, 7 tests, the
  D-351-05 differential afking-vs-human box oracle + index-binding + pre-RNG/post-RNG ordering), TST-02 + TST-03
  revert-free + EV-cap (`V55RevertFreeEvCap.t.sol`, 11 tests, class-A revert-free / class-B solvency fail-loud
  `Panic(0x11)` / class-C gameover-unblocked + EV-cap exactly-once / shared budget / clamp), TST-04 two-path +
  set-mutation + OPEN-E (`V55SetMutationOpenE.t.sol`, 10 tests), TST-06 gas (`V55AfkingGasMarginal.t.sol`,
  5 tests, per-buy 206,246 / per-open 74,153 / 16.7M ceiling / GAS-02 no-STATICCALL trace / GAS-03 Outcome-A
  N/A), and the NON-WIDENING **603/134/16** regression ledger (TST-05: the D-351-01 rewrite map + the D-351-02
  drops + `test/REGRESSION-BASELINE-v55.md`). Reqs: TST-01..06 (all Complete at TST).
- **§3e Phase 352 — TERMINAL.** This deliverable; SOURCE-TREE FROZEN at `453f8073`; the SC1 delta-audit (352-01)
  + the SC1 3-skill GENUINE PARALLEL_SUBAGENT sweep (352-02) + the regression + the gated closure flip (352-04).
  Req: AUDIT-01 (Pending -> flip at 352-04).

### §3.A Delta-Surface Table (folded from 352-01-DELTA-AUDIT.md §2)

Grouped by the six v55 work-item families. Columns mirror FINDINGS-v49 §3.A: **Surface (file, change)** |
**Requirements** | **Re-grepped anchors @ `453f8073`** | **Disposition**.

| Surface (file, change) | Requirements | Re-grepped anchors @ `453f8073` | Disposition |
| --- | --- | --- | --- |
| **`AfKing.sol`** (**-952**, DELETED) — *Family 1 (AfKing dissolution)* | ARCH-03 | `git show 453f8073:contracts/AfKing.sol` **fails** (file absent). The standalone keeper contract — `_poolOf` custody, `subscribe`/`doWork`/`_autoBuy`/`_resolveBuy`, `burnForKeeper` — is **gone**; its logic folded into the game-resident model (Families 2-4). **KILL-SET (grep-ZERO):** no tracked `contracts/*.sol` imports `AfKing.sol`; `AF_KING` is removed from `ContractAddresses.sol` (1->0) with ZERO repo-wide references. | **NON-WIDENING** (whole-contract DELETION — strictly removes attack surface; custody + slice math relocate into Families 2-4) |
| **`DegenerusVault.sol`** (33) — *Family 1* | ARCH-03 | The v54 `GAME \|\| AF_KING` receive/credit relaxation **dissolved -> GAME-only**: `onlyGame` (`:434`); the vault self-subscribes (`player == address(this) == msg.sender`); `withdrawAfkingFunding`/`afkingFundingOf` are the GAME-routed accessors (`:72-75`). No `AF_KING` symbol survives. | **NON-WIDENING** — STRICTLY TIGHTER (GAME-only narrows the v54 GAME-or-AF_KING acceptor) |
| **`StakedDegenerusStonk.sol`** (34) — *Family 1* | ARCH-03 | Same GAME-only retarget: `receive()` gated `msg.sender == GAME` (`:429-433`); `burnAtGameOver() onlyGame` (`:526`) is now a **pure local-token burn** (the v54 `afKing.withdraw(afKing.poolOf(this))` prepaid-pool recovery is gone; `withdrawAfkingFunding` recovers a player's OWN funding only). | **NON-WIDENING** — STRICTLY TIGHTER (the de-custody recovery path removed; the receive acceptor narrows) |
| **`BurnieCoinflip.sol`** (6) — *Family 1* | ARCH-03 | The `creditFlip` allow-list retargeted: allowed callers = **GAME** (the delegatecall modules incl. the afking router; `:191`); the `AF_KING` creditor removed. No `AF_KING` symbol survives. | **NON-WIDENING** — STRICTLY TIGHTER (one creditor address removed) |
| **`ContractAddresses.sol`** (4) — *Family 1* | ARCH-03 | `AF_KING` **removed** (1->0); `GAME_AFKING_MODULE` added (`:35`, the new delegatecall module). Freely-modifiable per project policy. | **NON-WIDENING** — an address-constant swap |
| **`modules/GameAfkingModule.sol`** (**+1048**, NEW) — *Family 2 (fold) + 349.2 restore* | ARCH-02 . PLACE-02 . CONSENT-01/02 . BOX-01..05 . REVERT-01/02 . EVCAP-01 . (349.2 quest/affiliate) | **NEW delegatecall module**, `is DegenerusGameMintStreakUtils` (`:74`, inherits `DegenerusGameStorage` -> all subscriber state = in-context SLOADs). Owns: **subscribe/setters** (`subscribe(...)` `:234`, the subscribe-time `isOperatorApproved` consent gate CONSENT-01 `:209`/`:250-265`); the **process-pass** (`processSubscriberStage(...)` `:539`); the **open-pass** (`_openAfkingBox` `:888`); the **router** (`mintBurnie()` `:985`, the SINGLE unified `creditFlip(msg.sender, bountyEarned)` CEI-LAST `:1011-1015`). **349.2 restore** (BURNIE flip-credit only, OFF the ETH/`claimablePool` path): `quests.handlePurchase(...)` `:760`, `affiliate.payAffiliate(_ethToBurnie(...), ...)` `:806`/`:816` -> accumulated `flipCredit` -> one `coinflip.creditFlip(player, flipCredit)` `:831` (handlers-before-score). No index-keyed box ledger — the stamp is the 4-field Sub; `_openAfkingBox` seeds from `rngWordByDay[sub.lastAutoBoughtDay]`. Module bytecode is its own EIP-170 budget (ARCH-02). | **NON-WIDENING** — a NEW module relocating the deleted `AfKing.sol` surface into the game-resident model; the 349.2 restore re-credits afking LOOTBOX subs as BURNIE flip-credit only (ETH/`claimablePool` UNCHANGED -> solvency-neutral) |
| **`interfaces/IDegenerusGameModules.sol`** (80) — *Family 2* | ARCH-02 | The `IGameAfkingModule` signatures match the contract verbatim (incl. `processSubscriberStage` dispatched by the AdvanceModule + the subscribe/`mintBurnie`/`afkingFundingOf`/`withdrawAfkingFunding` surface). The standalone-AfKing interface rows are gone. | **NON-WIDENING** — tracks the new module's ABI |
| **`storage/DegenerusGameStorage.sol`** (**+117**) — *Family 3 (append)* | ARCH-01 . BOX-02/03/04 . FREEZE-01 | The **layout-safe append**: `_subOf` (`:1902`), `_fundingSourceOf` (`:1904`), `_subscribers` (`:1914`), `_subscriberIndex` (`:1918`, swap-pop), `_subCursor` (`:1925`) + `_afkingResetDay` + `subsFullyProcessed` (`:343`, the FREEZE-02 drain gate), `afkingFunding` (`:420`, **rides inside `claimablePool`** — INVARIANT `:358` `claimablePool == sum claimableWinnings[*] + sum afkingFunding[*]`, every mutation moves both `:416`), and `rngWordByDay` (`:454`, the DAY-keyed word). **`struct Sub` `:1867` = 4-field** config + the stamp `uint16 scorePlus1` + `uint96 amount` + `uint32 lastAutoBoughtDay` + `uint32 lastOpenedDay`. **NO `index`, NO `baseLevelPlus1`** in the Sub stamp (the 6 `baseLevelPlus1` hits are the HUMAN `_packLootboxPurchase`/`lootboxPurchasePacked` path `:1372-1430`; the Sub-stamp doc `:1853` disclaims a stored roll floor). | **NON-WIDENING** — a pure append (pre-launch redeploy-fresh; every module shares the base); `afkingFunding` rides inside `claimablePool` (no new aggregate -> inherits the v54-correct solvency wiring) |
| **`modules/DegenerusGameAdvanceModule.sol`** (85) — *Family 4 (box stamp + process-pass)* | PLACE-02 . FREEZE-02 . REVERT-02 | The **required-path STAGE** inserted strictly before `rngGate` (`:294`), dispatched via `IGameAfkingModule.processSubscriberStage.selector` (`:759`). The **FREEZE-02 no-straddle guard**: a forward-looking reset flips `subsFullyProcessed = false` + `_subCursor = 0` ONCE before the day's STAGE (`:300-308`), the STAGE breaks-and-returns `mult` while `!subsFullyProcessed` (`:310-322`), sets `subsFullyProcessed = true` only at cursor-end before falling through to `rngGate` (`:325`) — never straddles the mid-day `requestLootboxRng` index advance. **REVERT-02 no-valve** doc `:749` ("fail loud — D-348-04 no-valve") — the `claimablePool` debit/release is a checked `uint128 -=`, no try/catch. | **NON-WIDENING** — inserts a pre-RNG STAGE; the mid-day same-day path returns earlier (`:287`); the drain/day-advance is otherwise the v54 shape (the guard authored exactly as 348-FREEZE-PROOF FREEZE-02c required) |
| **`modules/DegenerusGameLootboxModule.sol`** (101) — *Family 4 (open-pass)* | BOX-01/04/05 . EVCAP-01 . FREEZE-03 | The afking open materializes from the 4-field stamp + `rngWordByDay[lastAutoBoughtDay]` with math byte-identical to `openLootBox`: `currentLevel = level + 1` (**LIVE** `:767/:800`) -> `_rollTargetLevel(currentLevel, seed)` (`:769/:802`) -> `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)` (`:772`). **EVCAP-01:** `_applyEvMultiplierWithCap` (`:459`) reads `lootboxEvBenefitUsedByLevel[player][lvl]` (`:473`) + writes `usedBenefit + adjustedPortion` (`:488`) — the RMW at open, hard-clamped (no-write 100%-EV short-circuit at cap). **BOX-01:** boons OFF -> `amount == spend`. **BOX-05:** the human path keeps `lootboxPurchasePacked`/`_unpackLootboxPurchase` (`:530`) unchanged -> the two routes share no mutable-state hazard. | **NON-WIDENING** — re-uses the existing draw math (the differential oracle TST-01 proves byte-identical traits at the same live level); the only afking addition is the stamp-sourced seed + the shared EV-cap RMW |
| **`modules/DegenerusGameMintModule.sol`** (14) — *Family 4 (EVCAP bypass) + 349.2 ticket leg* | EVCAP-01 (buy-time bypass) . (349.2 ticket leg) | The afking **ticket-buy** entry doc/path adjustment: the fresh-ETH portion is an explicit `ethValue` parameter (not `msg.value`) so the STAGE drives a no-value self-call (the Game holds the prepaid `afkingFunding`); the v54 `batchPurchase` framing reworded to the ticket-mode `purchaseWith` routed from the STAGE. This is the path that **bypasses the buy-time EV write** for afking boxes (EVCAP-01 double-draw guard — the EV RMW happens once, at open, in the LootboxModule). | **NON-WIDENING** — a comment/parameter-plumbing adjustment on the existing `purchaseWith` path; no new emission, no new mutable read |
| **`modules/DegenerusGameBingoModule.sol`** (**+110**) — *Family 5 (code-size reclaim)* | ARCH-04 | The `claimAffiliateDgnrs` relocation (~1.3 KB reclaimed from the Game) lands here — a behavior-identical MOVE of an existing function to a different delegatecall module (the logic unchanged, only its bytecode home moved). | **NON-WIDENING** — a code-size relocation (ARCH-04 MEASURED Complete at 348-SPEC: Game 24,358 B / 218 B headroom; the reclaim clears the EIP-170 margin) |
| **`DegenerusGame.sol`** (233) — *Family 5 (reclaim + thin wiring)* | ARCH-04 + thin wiring | The reclaim edits (read-aggregators drop-`view`/->lens, the `claimAffiliateDgnrs` move-out, the thin afking-module wiring) + the AfKing-dissolution wiring churn. The afking subscribe/`mintBurnie`/`afkingFunding` surface is now thin delegatecall wiring to `GameAfkingModule`. The Game runtime stayed < 24,576 (`forge build` clean / `npx hardhat compile` EXIT 0 per `REGRESSION-BASELINE-v55.md` §7a). | **NON-WIDENING** — behavior-identical reclaim + thin wiring (the largest single-file line count, but the hunks are the relocation + the dissolution wiring, no new economic surface) |

**Per-file delta accounted: 5 (Family 1) + 2 (Family 2) + 1 (Family 3) + 3 (Family 4) + 2 (Family 5) =
13 files** — exactly the `git diff --stat 20ca1f79 453f8073 -- contracts/` set (+1652 / -1165). **Every file
carries a NON-WIDENING verdict backed by a concrete grep/diff anchor @ `453f8073`, mapped to its owning v55
work item.**

All 29 v55.0 REQ-IDs are referenced in §3.A + §3.C: the 13-surface table carries every IMPL-resident req
(ARCH-01/02/03 + BOX-01..05 + REVERT-01/02 + EVCAP-01 + CONSENT-01/02 + PLACE-02) + the SPEC-resident
FREEZE-01/02 + ARCH-04; FREEZE-03 + PLACE-01 are SPEC design-locks re-attested in §3a/§3.B; GAS-01/02/03 are the
350 Outcome-A reqs (§3c); TST-01..06 are the 351 proofs (§3d/§5); AUDIT-01 is this TERMINAL close.

### §3.B Composition Attestation Matrix (folded from 352-01 §3)

**No orphan hunks across the +1652/-1165 delta.** Every hunk maps to exactly one of the six v55 work-item
families (352-01 §3.1):

| Work item (family) | Surfaces | Net intent |
| --- | --- | --- |
| **code-size reclaim** (ARCH-04) | `DegenerusGameBingoModule.sol` (+110), `DegenerusGame.sol`, `DegenerusGameMintModule.sol` | `claimAffiliateDgnrs`->BingoModule (~1.3 KB); read-aggregators drop-`view`/->lens; keep Game < 24,576 mid-flight |
| **GameAfkingModule fold** (ARCH-02 / PLACE-02 / CONSENT-01/02) | `GameAfkingModule.sol` (NEW +1048), `IDegenerusGameModules.sol` (80) | the delegatecall module owning subscribe/setters + process-pass + open-pass + the `mintBurnie` router |
| **DegenerusGameStorage append** (ARCH-01) | `DegenerusGameStorage.sol` (+117) | `_subOf`/`_subscribers`/`_subscriberIndex` + cursors + the 4-field Sub stamp + the `afkingFunding` ledger |
| **box stamp + process-pass + open-pass** (BOX-01..05 / FREEZE-01/02/03 / REVERT-01/02 / EVCAP-01) | `DegenerusGameLootboxModule.sol` (101), `DegenerusGameAdvanceModule.sol` (85 — the required-path STAGE), `GameAfkingModule.sol` | boons-OFF amount=spend; pre-RNG 4-field stamp; debit `afkingFunding` + `lastAutoBoughtDay` marker; post-RNG open from `rngWordByDay[day]`, byte-identical to `openLootBox`; `lastOpenedDay` no-double-open |
| **AfKing dissolution** (ARCH-03) | `AfKing.sol` (-952), `DegenerusVault.sol` (33), `StakedDegenerusStonk.sol` (34), `BurnieCoinflip.sol` (6), `ContractAddresses.sol` (4) | `AfKing.sol` DELETED; `AF_KING`-address dissolution; receive()/credit gates retargeted GAME-only |
| **349.2 quest/affiliate restore** | `GameAfkingModule.sol` (`:760`/`:806`/`:816`/`:831`), `DegenerusGameLootboxModule.sol` | per-buy BURNIE flip-credit off the ETH/`claimablePool` path; handlers-before-score; freeze-safe (folded into BOX/GAS) |

**The 350 GAS Outcome-A family is EMPTY** — `git log --oneline 20ca1f79..453f8073 -- contracts/` returns
exactly **2** commits (`77c3d9ef` 349.1 + `453f8073` 349.2); there is **no 350 commit in the delta range**
(GAS-01/02 CONFIRMED-STRUCTURAL via the 349/349.1 relocation, GAS-03 REJECTED-with-reasoning). **ZERO orphan
hunks** — the v55 surface widens NOTHING beyond the six work-item families.

**The freeze spine — FREEZE-01/02/03 re-attested INTACT @ `453f8073` against the AS-BUILT COMMITTED
4-field / DAY-keyed / live-level model (352-01 §3.2)**, each cross-ref'd to its paper proof
(`348-FREEZE-PROOF.md`) WITH the 349.1 supersession note + its empirical re-proof (TST-01,
`V55FreezeDeterminism.t.sol`, `351-VERIFICATION.md` truth 1):
- **FREEZE-01 (freeze-completeness) — HELD.** The 4-field stamp captures all **SEED**-determining state at
  process; the open re-derives nothing manipulable from mutable per-player state EXCEPT the documented benign
  EV-cap RMW down-clamp. *349.1 SUPERSESSION:* the committed shape DROPPED `index` (DAY-keyed
  `rngWordByDay[lastAutoBoughtDay]`) and resolves the LEVEL LIVE (`LB:767/:800`), so `scorePlus1` stays stamped
  (the per-sub EV-multiplier input) but `baseLevelPlus1` is **not** stamped — the target-level floor is rolled
  live like the human path. This **NARROWS** the frozen set to the SEED and is **STRICTLY SAFE** (the live read
  of level/score is the same posture as the human `openLootBox`; per D-348-07's own reasoning a one-mint in the
  reveal->open window moves the EV multiplier a few % and costs ~a full box -> -EV, non-manipulable-for-profit).
  *Residual live read:* the EV-cap accumulator `lootboxEvBenefitUsedByLevel[player][level+1]` (RMW at open,
  `LB:459/473/488`) — a benign monotonic <=10-ETH down-clamp, noted not findings-grade. *Empirical:* TST-01
  `testDifferentialAfkingVsHumanOpenSameTuple` + `testFuzzDifferentialAfkingVsHumanOpen`. **VERIFIED.**
- **FREEZE-02 (index-binding, DAY-keyed) — HELD.** The stamp binds to `rngWordByDay[lastAutoBoughtDay]`; the
  STAGE runs strictly pre-`rngGate` (`AdvanceModule:294`) behind the `subsFullyProcessed` drain gate
  (`:300-325`), so no sub stamped after a mid-day advance attaches to a freshly-requested word. *Supersession
  note:* the paper proof reasoned over an `index`-keyed binding; the committed binding is DAY-keyed — the same
  pre-RNG-separation guarantee against the day word; the STAGE-before-`rngGate` + drain gate is the structural
  closure either way. *Empirical:* TST-01 `testIndexBindingMidDayAdvanceDoesNotRebind` +
  `testFuzzIndexBindingAdvanceInvariant`. **VERIFIED.**
- **FREEZE-03 (stamped-day determinism) — HELD.** The seed `keccak256(rngWord, player, day, amount)` uses the
  **STAMPED** buy-day (`sub.lastAutoBoughtDay`, never open-time `_simulatedDayIndex()`), with no
  `block.timestamp/number/prevrandao/coinbase/blockhash` in the draw; `_openAfkingBox` seeds from
  `rngWordByDay[day]` (`GameAfkingModule:888-905`). *Empirical:* TST-01 `testStampedDayDeterminismOpenAtTwoBlocks`
  + `testFuzzNoBlockEntropyInTheDraw`. **VERIFIED.**

**The discharged REVERT-FREE-CHAIN — REVERT-01/02 re-attested (352-01 §3.3)**, cross-ref'd to
`PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` §5 (obligation 4, the thin per-sub try/catch valve, DROPPED at
D-348-04 -> no try/catch) + TST-02 (`V55RevertFreeEvCap.t.sol`):
- **REVERT-01 (revert-free by construction) — HELD.** The process-pass slice preserves `_resolveBuy`'s
  validation invariants VERBATIM: `ev = cost - claimableUse` + enum payKind, the 1-wei claimable sentinel, the
  `LOOTBOX_MIN` transient skip, `quantity >= 1` (the migration-fidelity obligation, the sole no-brick
  guarantor). *Empirical:* TST-02 class A — `testFuzzClassA_FundedSliceNeverReverts` +
  `testClassA_ClaimableSentinelAndMinSkipNeverRevert` + `testClassA_FundedBoxOpenNeverReverts`. **VERIFIED.**
- **REVERT-02 (no valve) — HELD.** The no-brick guarantee rests on the 3 residual revert classes: **(A)**
  revert-free-by-construction (REVERT-01); **(B)** fail-loud-on-solvency — a `claimablePool` underflow MUST
  revert `Panic(0x11)` at the checked `uint128 -=`, **never masked** (no try/catch; AdvanceModule doc `:749`);
  **(C)** terminal-routing-unblocked — the afking STAGE is on the non-gameover new-day path and cannot block
  game-over routing. *Empirical:* TST-02 class B — `testClassB_StageDebitSolvencyFailsLoud` +
  `testClassB_WithdrawSolvencyFailsLoud` + `testFuzzClassB_SolvencyAlwaysFailsLoud` (trace-confirmed the
  underflow originates in `advanceGame -> DegenerusGameAdvanceModule::advanceGame ->
  GameAfkingModule::processSubscriberStage`); class C — `testClassC_GameOverRoutingUnblockedByStage`.
  **VERIFIED.**

**EVCAP-01 — re-attested (352-01 §3.4).** The afking open increments
`lootboxEvBenefitUsedByLevel[player][level+1]` via `_applyEvMultiplierWithCap` (read+write-at-open, EXACTLY ONCE
per open, same map/key as MintModule's buy-time write, hard-clamped <=10 ETH -> no revert); the buy-time EV write
is **bypassed** for afking boxes (the MintModule afking ticket leg routes `purchaseWith` without the lootbox EV
tally -> no double-draw); proven equivalent to the v54 per-(sub,level) accumulator. *As-built:* `LB:459/473/488`
(the RMW), `:772` (the open call site, LIVE `currentLevel`). *Empirical:* TST-03 — `testEvCapExactlyOnceNoDoubleDraw`
+ `testEvCapSharedBudgetAcrossAfkingAndHuman` (afking 3 ETH + human 4 ETH draw the SAME `[player][level+1]` key,
cumulative 7 ETH = the v54 accumulator) + `testEvCapClampsAtTenEthNoRevert` +
`testFuzzEvCapMultiOpenClampedCumulative`. **VERIFIED.**

**The Phase-343 SOLVENCY-01 master invariant — re-attested HELD NET under the game-resident model
(352-01 §3.5).** The master inequality `balance + steth.balanceOf(this) >= claimablePool` (inclusive of the
afking total) was proven at Phase 343 SPEC for v54 and is carried into v55 as a discharged foundation. **NOTE:**
the v54 cross-contract de-custody ledger machinery this proof reasoned over was **largely REPLACED** by the
game-resident model — the `afkingFunding` ledger now rides **INSIDE** `claimablePool`
(`DegenerusGameStorage.sol:358` INVARIANT; every `afkingFunding` mutation moves `claimablePool` in tandem
`:416`), so there is **no new aggregate** — the afking funding is a sub-account of `claimablePool` and the
master inequality is structurally unchanged (it inherits the v54-correct yield-surplus / gameOver-drain /
stETH-stake wiring for free). The empirical guard that an afking debit can never silently breach it is the
**class-B fail-loud** (TST-02 — a forced `claimablePool` underflow reverts `Panic(0x11)`, never masked).
**HELD NET — re-attested.**

**OPEN-E 4-Protection BLOCKING Re-Attestation (CONSENT-01) + the CONSENT-02 set-mutation carry-over
(352-01 §3.6) — HARD CONDITION.** Per [[open-e-operator-approval-trust-boundary]] + REQUIREMENTS CONSENT-01/02,
the 4 OPEN-E structural protections are re-attested as a **HARD BLOCKING CONDITION** before closure (a failure
routes to the 352-04 closure gate as a blocker -> the relevant element is REVERTED before ship). Cross-ref'd to
TST-04 (`V55SetMutationOpenE.t.sol`):
1. **consent-gate-at-subscribe — HOLD.** The subscribe-time `isOperatorApproved` gate carries over
   (`GameAfkingModule:234`/`:250-265`, doc `:209`); a player who never approved cannot be subscribed by a third
   party; process/open never re-check. *Empirical:* TST-04 `testOpenEConsentGateUnapprovedReverts`.
2. **default-self byte-identical — HOLD.** `player == address(0)` -> `subscriber = msg.sender`; the VAULT/SDGNRS
   self-subscribe (`player == address(this) == msg.sender`) rides this path. *Empirical:* TST-04
   `testOpenEDefaultSelfByteIdentical` + `testFuzzOpenEDefaultSelfHoldsUnderOrderings`.
3. **no-escalation — HOLD.** Dropping/holding the consent grants no new authority; the funder=`src` accounting +
   the spend stays bounded to the resolved funding source. *Empirical:* TST-04 `testOpenENoEscalation`.
4. **trust-the-sub temporal bound — HOLD.** The pass-gating `validThroughLevel` (the `Sub.validThroughLevel`
   snapshot at subscribe, refreshed on crossing; deity sentinel `type(uint24).max`) is the temporal bound;
   revocation is `subscribe(_, 0)` -> in-set tombstone. *Empirical:* TST-04 `testOpenETrustTheSubRevokeDoesNotStop`.

**CONSENT-02 set-mutation carry-over — HOLD.** Evictions preserve "**no cursor advance after swap-pop**" (the
H-CANCEL-SWAP-MISS / cancel-tombstone-streak class) + the tombstone-then-reclaim shape: the STAGE's
`_removeFromSet`/`_subscribers.pop()` swap-pop does NOT advance `_subCursor` past the relocated tail, and the
streak (`scorePlus1`) is preserved (re-derived per buy, byte-identical to an undisplaced control). *Empirical:*
TST-04 `testStreakNotCorruptedBySwapPop` + the **NO-ORPHAN guard** trio `testNoOrphanControlInSetSubOpens` /
`testNoOrphanRemovedSubGetsNoBox` / `testNoOrphanGuardLeavesPendingBoxSubUntouchedByStage` (a removed sub gets no
free box — non-vacuous control proves the box would otherwise have materialized).

**OPEN-E re-attestation outcome: ALL 4 PROTECTIONS HOLD** under the fold + the CONSENT-02 set-mutation carry-over
HOLDS. **The HARD BLOCKING CONDITION is SATISFIED** -> no element requires reversion on this axis; closure is
NOT blocked on OPEN-E. (Corroborated independently by `/contract-auditor` in 352-02 §B.2 C4, per-protection HOLD;
the final blocking adjudication is the 352-04 closure gate's.)

**VRF / RNG-Freeze INTACT under the game-resident model (the v45 north-star, 352-01 §3.7):** re-attested INTACT
— **no in-window SLOAD a player can manipulate between rng-request and unlock**. The afking open is **post-RNG**
(`_afkingBoxReady` is false until `rngWordByDay[lastAutoBoughtDay] != 0` lands — `GameAfkingModule:921-934`, so
the open path is blocked in the protected window); the stamp froze the SEED at **process (pre-RNG)** behind the
`subsFullyProcessed` STAGE-before-`rngGate` gate (FREEZE-02). The game-resident fold introduced **NO new in-window
mutable read** — the per-subscriber process/open passes are in-context SLOADs of the appended storage, not new
entropy-window levers; the box draw consumes only frozen/stamped inputs + the benign EV-cap clamp. GAS-02's
no-STATICCALL trace (TST-06, `351-VERIFICATION.md` truth 6) empirically confirmed **0 foreign re-entrant
afking-funding-view StaticCalls** on the STAGE + the open. **Composition verdict: RNG-freeze NON-WIDENING.**

### §3.C Requirement Re-Attestation
All 29 v55.0 requirements (ARCH 4 . BOX 5 . FREEZE 3 . REVERT 2 . EVCAP 1 . CONSENT 2 . PLACE 2 . GAS 3 .
TST 6 . AUDIT 1 = 29) are re-attested at closure. The actual REQUIREMENTS.md row-flip to Complete is 352-04's
closure-gate job; §3.C records the attestation narrative. (FREEZE-01/02/03 + PLACE-01 + ARCH-04 are already
Complete at SPEC; GAS-01/02/03 at GAS; TST-01..06 at TST; the IMPL reqs ARCH-01/02/03 + BOX-01..05 +
REVERT-01/02 + EVCAP-01 + CONSENT-01/02 + PLACE-02 flip at the 352-04 closure; AUDIT-01 is this close.)

- **ARCH (4):** **ARCH-01** the subscriber set + cursors + the 4-field stamp + the `afkingFunding` ledger are
  appended to `DegenerusGameStorage` (layout-safe append; `Storage:1867`/`:1902`/`:1914`/`:1918`/`:420`/`:454`);
  **ARCH-02** the NEW `GameAfkingModule` (delegatecall, inherits `DegenerusGameStorage`) owns
  subscribe/setters + process-pass + open-pass + router (`:74`/`:234`/`:539`/`:888`/`:985`), its bytecode its own
  budget; **ARCH-03** `AfKing.sol` DISSOLVED (DELETED, the `AF_KING` address removed 1->0, all receive()/credit
  gates retargeted GAME-only — `DegenerusVault:434`, `StakedDegenerusStonk:429-433`, `BurnieCoinflip:191`);
  **ARCH-04** (SPEC, Complete) the Game runtime code-size stays < 24,576 at every step — the
  `claimAffiliateDgnrs`->`BingoModule` reclaim FIRST (MEASURED Game 24,358 B / 218 B headroom at SPEC;
  DegenerusGame 22,855 B post-349.2; `forge build` clean / `npx hardhat compile` EXIT 0).
- **BOX (5):** **BOX-01** boons OFF -> `amount == spend` (the boosted-amount freeze field deleted; `LB` afking
  resolve reads the stamp `amount`); **BOX-02** the process-pass (pre-RNG) writes the per-sub 4-field stamp as one
  warm-dirty write per process-day, NO cold `lootboxEth*`/`lootboxPurchasePacked`/`boxPlayers.push`
  (`GameAfkingModule:539`+ the stamp write); **BOX-03** the process-pass debits `afkingFunding` + sets the
  `lastAutoBoughtDay` success-marker ONLY after a successful debit (a failed buy / a between-pass subscribe writes
  no marker -> no free box); **BOX-04** the open-pass (post-RNG) materializes from the stamp +
  `rngWordByDay[lastAutoBoughtDay]` byte-identical to `openLootBox`, with `lastOpenedDay` the day-keyed
  no-double-open gate (`_openAfkingBox` effects-first `:888-892`; `_afkingBoxReady` requires
  `lastOpenedDay < lastAutoBoughtDay`); **BOX-05** humans keep the `lootboxEth`/`boxPlayers` route unchanged
  (`LB:530`); the two open routes share no mutable-state hazard (storage-isolated except the intentionally-shared
  EV/boon budgets, 352-02 §B.2 C1).
  > NOTE: the per-sub stamp is the COMMITTED **4-field** `(scorePlus1, amount, lastAutoBoughtDay, lastOpenedDay)`
  > with LIVE-level open + DAY-keyed seed (349.1 SUPERSEDED the 348 5-field `(index, ..., baseLevelPlus1)` design).
- **FREEZE (3):** **FREEZE-01** (SPEC, Complete) freeze-completeness — the stamp captures all SEED-determining
  state; the only residual live read is the benign monotonic <=10-ETH EV-cap clamp (the live level/score read is
  the human-`openLootBox` posture, NARROWED frozen set, §3.B); **FREEZE-02** (SPEC, Complete) index-binding
  (DAY-keyed) — the STAGE runs strictly pre-`rngGate` behind the `subsFullyProcessed` drain gate, never straddling
  a mid-day advance; **FREEZE-03** (SPEC, Complete) determinism — the seed uses the STAMPED day, zero `block.*`
  entropy. (All three re-proven against the as-built model, TST-01.)
- **REVERT (2):** **REVERT-01** the process-pass preserves `_resolveBuy`'s validation invariants VERBATIM ->
  revert-free-by-construction (the migration-fidelity sole no-brick guarantor; TST-02 class A); **REVERT-02** the
  no-valve form (D-348-04 DROPPED the try/catch) — class-B fail-loud-on-solvency (`Panic(0x11)`, never masked,
  `AdvanceModule:749`) + class-C terminal-routing-unblocked (the STAGE on the non-gameover new-day path); the two
  residual revert classes accepted (solvency-violation [safe under SOLVENCY-01], liveness-timeout [game-dead]);
  TST-02 classes B/C.
- **EVCAP (1):** **EVCAP-01** the afking open increments `lootboxEvBenefitUsedByLevel[player][level+1]` via
  `_applyEvMultiplierWithCap` (RMW exactly-once at open, same map/key as the buy-time write, hard-clamped <=10 ETH
  -> no revert) with the buy-time EV write BYPASSED for afking boxes (no double-draw); proven equivalent to the v54
  per-(sub,level) accumulator (TST-03).
- **CONSENT (2):** **CONSENT-01** the subscribe-time `isOperatorApproved` (OPEN-E) gate + pass-gating
  (`validThroughLevel`) + VAULT/SDGNRS exemption-on-`player` + funder=src accounting carry over verbatim; the
  OPEN-E 4-protection re-attested HOLD (the HARD BLOCKING condition SATISFIED, §3.B; TST-04); **CONSENT-02**
  evictions preserve "no cursor advance after swap-pop" (the H-CANCEL-SWAP-MISS / cancel-tombstone-streak class) +
  the tombstone-then-reclaim shape + the NO-ORPHAN guard (TST-04).
- **PLACE (2):** **PLACE-01** (SPEC, Complete) the §4 placement DECIDED = required-path `advanceGame` STAGE
  (D-348-01, on non-revert grounds — required-path VIABLE since a funded well-formed sub can't revert in a healthy
  game; process-leg pre-RNG cursor-chunked, open-leg post-`_unlockRng` cursor-chunked); **PLACE-02** the bounty
  reconciliation — the open stays a post-RNG router category (`OPEN_BATCH`/`OPEN_KNEE` pro-rate), the buy/process
  bounty is work-scaled (the `mintBurnie` advance/open legs, single CEI-last `creditFlip(msg.sender, ...)`,
  `GameAfkingModule:985-1015`), payment the deferred BURNIE flip-credit mint.
- **GAS (3):** **GAS-01** (GAS, Complete) the ~6 cold box-ledger SSTOREs + `boxPlayers.push` +
  `enqueueBoxForAutoOpen` (~120-130k) collapse to one warm-dirty Sub-stamp write — CONFIRMED-STRUCTURAL (delivered
  by the 349/349.1 relocation; MEASURED at 351 TST-06 NET OF the 349.2-restored BURNIE side-effects); **GAS-02**
  (GAS, Complete) the per-subscriber `afkingSnapshot`/`afkingFundingOf` cross-contract staticcalls -> in-context
  SLOADs — CONFIRMED-STRUCTURAL (the no-STATICCALL trace, 0 foreign re-entrant afking-funding-view StaticCalls,
  TST-06); **GAS-03** (GAS, Complete) the same-slot affiliate/pool aggregate flushes — **REJECTED-with-reasoning**
  (warm SSTORE ~100 gas * (N-1); the 349.2-restored affiliate/quest/`creditFlip` are BURNIE flip-credit OFF the
  ETH+pool path -> no new batchable shared additive slot; the mixed-chunk `purchaseWith` interleave hazard breaks
  the accumulate-and-flush identity; Outcome A — no contract diff).
- **TST (6):** **TST-01** (TST, Complete) freeze/determinism — the stamp+open is identical independent of open
  timing/block (seed uses the stamped day) + index-binding across a mid-day advance + the D-351-05 differential
  afking-vs-human box oracle; **TST-02** (TST, Complete) revert-free — a funded process/open never reverts on
  well-formed slices + class-B solvency fail-loud + class-C gameover-unblocked (the no-valve form); **TST-03**
  (TST, Complete) EV-cap — the per-(player,level) 10-ETH budget enforced exactly once per open, no double-draw,
  equivalent to v54; **TST-04** (TST, Complete) two-path open coexistence + set-mutation (eviction/tombstone/
  swap-pop, streak preserved) + the OPEN-E 4-protection regression; **TST-05** (TST, Complete) NON-WIDENING
  regression vs the v54 baseline (603/134/16, the 134 subset of the 148 BY NAME, `REGRESSION-BASELINE-v55.md`);
  **TST-06** (TST, Complete) gas — per-buy + per-open marginal under the 16.7M HARD ceiling, GAS-01/02/03
  same-results.
- **AUDIT (1):** **AUDIT-01** the FULL TERMINAL close (this `audit/FINDINGS-v55.0.md`) — the delta-audit (352-01;
  13 surfaces NON-WIDENING + zero orphan hunks + the freeze spine + REVERT-FREE-CHAIN + EVCAP-01 + SOLVENCY-01 +
  OPEN-E 4-protection + VRF-freeze re-attested) + the 3-skill genuine-PARALLEL adversarial sweep (352-02; 0
  FINDING_CANDIDATE / 21 rows / dual-gate skeptic filter) + this 9-section deliverable + the atomic 5-doc closure
  flip (352-04).

---

## 4. Adversarial-Pass Disposition (folded from 352-02-ADVERSARIAL-LOG.md)

### §4.1 Outcome
3-skill GENUINE PARALLEL_SUBAGENT sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`;
`/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`), run as 3 concurrent background Task spawns from the orchestrator
(the v45/314 . v47/324 . v48/328 . v49/333 genuine-parallel path — the orchestrator holds the Task tool, NOT the
HYBRID fallback; the executor-nested fallback was avoided exactly because a `gsd-executor` lacks the Task tool).
**21 deduplicated charged-probe rows across the box-stamp freeze + liveness isolation + two-path open + the
OPEN-E/affiliate carry-over: 18 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN + 0 FINDING_CANDIDATE.** 0 elevations
reached FINDING_CANDIDATE through the dual-gate skeptic filter; the charge was WEIGHTED (the genuinely-NEW v55
surfaces got the deepest effort): **(a) BOX-STAMP FREEZE** (`/zero-day-hunter` lead — the RNG-freeze spine touch,
deepest); **(b) LIVENESS ISOLATION** (`/contract-auditor` + `/economic-analyst` — the no-valve required-path
STAGE); **(c) TWO-PATH OPEN** (`/contract-auditor` lead — humans keep `lootboxEth`/`boxPlayers`, afking is the
`mintBurnie` open leg); CARRY-OVER (lighter, corroborate only) the OPEN-E 4-protection + set-mutation. Each
subagent probed the actual frozen subject via `git show 453f8073:contracts/...` (READ-ONLY; `git diff 453f8073
HEAD -- contracts/` empty throughout). **Clean-closure outcome: ZERO FINDING_CANDIDATEs survive — the `0
NEW_FINDINGS` clause of the closure verdict HOLDS.**

The per-skill self-summaries: **`/zero-day-hunter`** 6 probes (FREEZE-i..vi) — 5 NEGATIVE-VERIFIED + 1
SAFE_BY_DESIGN; **`/contract-auditor`** 11 sub-probes (B1-B7 liveness + C1-C4 two-path/OPEN-E) — 9
NEGATIVE-VERIFIED + 2 SAFE_BY_DESIGN; **`/economic-analyst`** 4 charged probes (E1-E4) — 4 NEGATIVE-VERIFIED +
1 out-of-scope advisory (O1). By surface: box-stamp freeze 6 rows (5 NV + 1 SBD), liveness isolation 8 rows
(B1-B7 + E1, all NV — no REVERT-01 hole / class-B swallow / class-C routing-block / gas-DoS brick), two-path
open 4 rows (C1/C2/C3 + E2, 2 NV + 2 SBD), OPEN-E/set-mutation corroboration 1 row (C4, NV) + the
affiliate/bounty incentive 2 rows (E3/E4, NV).

### §4.2 FINDING_CANDIDATEs
**None.** Zero elevations reached FINDING_CANDIDATE. Per the CONTEXT discipline, had any MEDIUM+ survived, it
would be recorded here WITHOUT a contract fix (the subject is FROZEN at `453f8073`) and routed to the 352-04
closure gate for USER adjudication (default leaning DEFER->v56 with the fix design locked). No such candidate
exists.

### §4.3 SAFE_BY_DESIGN rows (informational) + the out-of-scope advisory
**3 SAFE_BY_DESIGN rows** (genuine degrees-of-freedom investigated to ground + structurally neutralized; armed
then discarded through the dual-gate):
- **FREEZE-iii — live-level open, non-monotonic-price degree of freedom (`/zero-day-hunter`).** The outcome
  BUCKET is a pure function of the frozen seed (the live level cannot change WHICH prize is won); the only live
  lever is `targetPrice = priceForLevel((liveLevel+1)+frozenOffset)`, non-monotonic at the 100-level cycle
  boundary. **SAFE_BY_DESIGN** — open timing is NOT player-controlled (`mintBurnie` pays any caller a work-scaled
  bounty to open ready boxes; `autoOpen` sweeps the whole set via a shared cursor -> a rational bounty hunter opens
  promptly at whatever level is live; the owner can neither hold nor single out their box); the "wait for a cheap
  tier" play requires being the sole opener for many days while suppressing all bounty hunters (impossible on a
  public chain); it is deliberate parity with already-shipped `resolveLootboxDirect` (Degenerette/Decimator) +
  post-grace human `openLootBox` via the identical `_rollTargetLevel(currentLevel, seed)` -> `_resolveLootboxCommon`
  shape (the differential oracle holds). The 349.1 design note ("auto-open removes the player's ability to time
  the level") IS this permissionless-open mechanism.
- **C1 — shared EV-cap / boon budget across the two open routes (`/contract-auditor`; corroborated by E2).** The
  ONLY shared maps are `lootboxEvBenefitUsedByLevel[player][level]` (the intentional per-player 10-ETH budget) +
  the BoonModule boon-roll storage (every lootbox shares by design); both monotonic/benign; the routes are
  otherwise storage-isolated. **SAFE_BY_DESIGN** — the sharing is by-design, not positive-EV.
- **C3 — straddle the two paths to double-draw the EV-cap (`/contract-auditor`; corroborated by E2).** The human
  buy-time EV write is UNREACHABLE by the afking lootbox stamp (stamp-only, no `purchaseWith`) + by the afking
  ticket buy (`lootBoxAmount=0`); the afking box draws the cap EXACTLY ONCE at open on the SAME `[player][level+1]`
  key, monotonically. **SAFE_BY_DESIGN** — straddling is EV-NEGATIVE for the attacker (it merely exhausts the
  shared budget faster, to their own detriment).

**Out-of-scope informational advisory (O1) — NOT a v55.0 finding.** **Observation O1
(`/economic-analyst`, out-of-charged-scope):** `DegenerusQuests.handlePurchase`'s lootbox branch credits
`lootboxReward` via `coinflip.creditFlip(player, lootboxReward)` (`:894`) AND includes it in `totalReturned`
(`:896`); both callers (`MintModule:1232`, `GameAfkingModule:770`) re-add the return and credit again
(`MintModule:1367` / `GameAfkingModule:831`), so a completed LOOTBOX quest appears to credit its fixed reward
(100/200/300 BURNIE) twice. **Disposition: OUT-OF-SCOPE INFORMATIONAL ADVISORY** — this is **PRE-EXISTING and
SYMMETRIC across the manual `purchaseWith` path AND the afking path** (it is NOT a 349.2 regression — 349.2
faithfully mirrors the manual path, introducing no NEW vector); `DegenerusQuests.sol` is **NOT in the v55 delta**
(no quest file in `git diff 20ca1f79 453f8073 -- contracts/`) -> **out of the v55 blast radius**; the explicit
comment at `DegenerusQuests:884-891` frames the dual-routing as deliberate; the amount is a fixed, day-idempotent
BURNIE flip-stake (not attacker-scalable), entirely OFF the ETH/`claimablePool`/solvency path. It is recorded for
awareness (the v48 SWAP cash-share doc-drift class) and **routed to a future quest-core (`DegenerusQuests`) audit
lane + the v52 consolidated cross-model audit** (§8 / §9d). It does **NOT** amend the `0 NEW_FINDINGS` verdict.

Plus the 18 NEGATIVE-VERIFIED probed-no-issue rows (352-02 §B/§C): the score/boon/EV-cap reveal->open manipulation
(FREEZE-i — the activity score is a `view`-read FROZEN into `scorePlus1`, never re-read at open), the mid-day
`requestLootboxRng` index-advance straddle (FREEZE-ii — the afking box is purely DAY-keyed; the mid-day path lives
in a disjoint `lootboxRngWordByIndex` keyspace the afking open never reads), the `lastOpenedDay` double-open /
cross-day replay (FREEZE-iv — a strict day-keyed monotone gate, effects-first), the re-subscribe-to-mutate-pending
(FREEZE-v — UPSERT touches no stamp field), the predictable/backfilled-word binding (FREEZE-vi — the stamped day
always equals the same-advance fresh-VRF word), the no-valve STAGE external-call revert holes (B1/B2/B3 — every
callee GAME/QUESTS/AFFILIATE-authorized + revert-free under a funded slice), the class-B silently-swallowed
underflow (B4 — checked `uint128 -=`, no try/catch, `Panic(0x11)` propagates), the class-C game-over-routing block
(B5 — `_handleGameOverPath` returns BEFORE the STAGE; the STAGE/`_livenessTriggered` mutual-exclusion proven), the
gas-DoS past 16.7M (B6 — STAGE chunked `SUB_STAGE_BATCH=50`, `SUBSCRIBER_CAP=500`, O(1) per-sub work, 50x ~ 8-10M
< 16.7M), the out-of-band STAGE double-stamp/debit (B7 — single gated caller, idempotent across chunks), the
same-box double-open across paths (C2 — the two box populations mutually unreachable by construction), the OPEN-E
4-protection + set-mutation (C4 — corroborates 352-01's HARD BLOCKING condition), the no-valve STAGE positive-EV
grief (E1 — boons-OFF afking EV strictly worse than a human's; can't extract more than funded), the EV-cap shared
budget double-draw (E2 — one conserved monotonic accumulator), the 349.2 affiliate/quest gameable incentive
(E3 — off-ETH confirmed, no self-affiliate loop [`code=bytes32("DGNRS")`, self-referral blocked], no streak
farming [`QUEST_STATE_STREAK_CREDITED` day-cap]), and the bounty/funding misalignment (E4 — minted BURNIE
flip-credit to the keeper, never ETH/`claimablePool`, one category per call, `OPEN_KNEE` pro-rate defeats the
farm-by-splitting corner).

### §4.4 Skeptic-Reviewer Filter Attestation
`/degen-skeptic` is OUT as a probing skill (per `D-271-ADVERSARIAL-02`); the skeptic FUNCTION is the dual-gate,
applied at two points: (1) per-skill self-arm — each skill armed both lenses on its own candidates before
returning; (2) orchestrator integration-time re-application — the orchestrator re-applied both lenses to every §B
row when assembling §C.
- **Gate 1 — structural-protection lens.** Does a structural mechanism already prevent the elevation? If yes ->
  NEGATIVE-VERIFIED or SAFE_BY_DESIGN.
- **Gate 2 — 3-condition EV lens.** (a) manifests WITHOUT an attacker-controlled precondition / is positive-EV to
  execute; (b) magnitude material; (c) severity survives the skeptical re-read. A FINDING_CANDIDATE survives BOTH
  gates.

**4 elevations were armed and ALL discarded:** (1) **FREEZE-iii** (live-level non-monotonic-price) — Gate-1
PREVENTED (permissionless bounty-incentivized open removes timing control; deliberate parity with shipped
`resolveLootboxDirect`/`openLootBox`); Gate-2 FAILS (a) (the gain needs the IMPOSSIBLE sole-opener-for-many-days
precondition; mostly ADVERSE — delaying risks a higher tier) -> **SAFE_BY_DESIGN**. (2) **C1** (shared EV/boon
budget) — Gate-1 the shared map is the INTENDED per-player per-level 10-ETH budget, monotonic up-only down-clamp;
Gate-2 FAILS (a) (by-design, not positive-EV) -> **SAFE_BY_DESIGN**. (3) **C3** (EV-cap straddle) — Gate-1 a single
RMW on the shared key, each box debits its own portion once; Gate-2 FAILS (a) (EV-NEGATIVE — merely exhausts the
budget faster) -> **SAFE_BY_DESIGN**. (4) **O1** (quest-core double-credit) — Gate-1 day-idempotent
(`QUEST_STATE_STREAK_CREDITED` + slot masks), fixed reward, explicit deliberate-design comment; Gate-2 (a)
manifests on any completed lootbox quest but NOT attacker-scalable, (b) magnitude IMMATERIAL (fixed <=300-BURNIE
flip-stake, day-capped, off the ETH/solvency path), (c) likely demotes to benign on re-read; the **decisive
v55-scope lens** — `DegenerusQuests.sol` is NOT in the v55 delta, the behavior is PRE-EXISTING + SYMMETRIC across
the manual path -> **not introduced by v55.0** -> **DISCARDED as a v55.0 finding -> recorded as an OUT-OF-SCOPE
INFORMATIONAL ADVISORY** (the v48 SWAP cash-share doc-drift class), routed to a future quest-core audit lane +
the v52 consolidated cross-model audit; does NOT amend the `0 NEW_FINDINGS` verdict.

**No elevation survived both gates. 0 FINDING_CANDIDATE.** The dual-gate self-discards are recorded above for
honesty (the sweep was a real hunt, not a rubber-stamp): the FREEZE-iii / C1 / C3 SAFE_BY_DESIGN rows are genuine
degrees-of-freedom investigated to ground and structurally neutralized; the O1 advisory is surfaced for the
closure gate (352-04) so the USER is aware of a pre-existing, out-of-scope, immaterial observation that a future
quest-core review may wish to confirm. No "tricked into approving" actor modeled (per
[[open-e-operator-approval-trust-boundary]]); reentrancy SAFE_BY_DESIGN / MEV LOW-confirmatory per the USER-locked
weighting ([[threat-model-reentrancy-mev-nonissues]]).

**Read-only attestation.** `git diff 453f8073 HEAD -- contracts/` is empty throughout the sweep — no
`contracts/*.sol` was opened or mutated; all source was read via `git show 453f8073:...`; every cited `file:line`
was re-grep-verified against `453f8073`. **Attestation: 0 FINDING_CANDIDATEs survived the dual-gate.** SWEEP
outcome = `0 NEW_FINDINGS`, KNOWN_ISSUES_UNMODIFIED.

---

## 5. LEAN Regression Appendix (folded from 352-01 §4 / TST-05)

**AUTHORITATIVE SOURCE — cite, do NOT re-run forge or re-derive:** `test/REGRESSION-BASELINE-v55.md` (the 351-09
ledger, TST-05). The whole-tree `forge test` run at the v55 TST HEAD was **603 passed / 134 failed / 16 skipped**
(753 run, default profile, WHOLE tree — NOT `--match-path`).

### §5a Suite Baseline — 603 / 134 / 16, NON-WIDENING BY NAME vs the v54.0 `20ca1f79` baseline

| Quantity | v54 baseline `20ca1f79` (empirical) | v55 corpus delta (351-01..08) | v55 TST HEAD |
| --- | --- | --- | --- |
| `forge test` passed | 461 | +142 (the adapted-green corpus + the 4 new v55 proofs) | **603** |
| `forge test` failed | 148 | -14 v54 reds FIXED by the v55 adaptation (the NARROWING) | **134** |
| `forge test` skipped | 16 | +0 (the 16 `RngLockDeterminism` `vm.skip` blocks carried unchanged) | **16** |

The 134 v55-live reds classify into three named buckets (ledger §2): **Bucket A** VRF/RNG-window baseline reds =
**41** (out of v55 scope — v55 touched no VRF/Advance RNG-window code), **Bucket B** stale-harness/behavioral =
**92** (pre-existing v54 fixtures; `git diff 20ca1f79 453f8073` for these suites' files is empty — they fail
identically at both HEADs), **Bucket F** the unseeded `DegeneretteBet.inv` flaky cluster = **1**.
**41 + 92 + 1 = 134.**

### §5b The BINDING gate — a failing-NAME-set strict SUBSET (134 in 148), NOT a count delta (the Pitfall-3 guard, adapted)
**NON-WIDENING = a strict failing-NAME-set SUBSET**, NOT a count match and NOT a strict equality. The binding,
load-bearing gate is:

> **`v55 live failing set - v54 §2 148-name union == empty`** (0 names outside the baseline) -> **net-zero NEW
> regression.**

The ledger §6 verified BOTH directions empirically: `v55 live - v54 union = empty` (**0 names** — no new red
outside baseline; this is the binding gate, and it HOLDS) AND `v54 union - v55 live = 14 names` (exactly the §5c
NARROWING — v54 reds the v55 adaptation FIXED red->green). So **`v55 live (134) is a SUBSET of v54 union (148)`
BY NAME** (intersection = 134; the 14-name slack is the narrowing). **Do NOT quote "134 failures, down from 148"
as a count delta** — the gate is the NAME-set membership test `live - union == empty`. The v49-precedent
strict-equality gate (`live == union`) is intentionally **RELAXED to the SUBSET gate** here because of the
unseeded `DegeneretteBet.inv` cluster (ledger §4 — the default `[invariant]` block has no `seed`, so its
red-subset is non-deterministic run-to-run) + the v55 NARROWING; the relaxation weakens NOTHING on the
regression-detection side (a new red would still appear in `live - union != empty` and trip the STOP — none did).

> **The empirical v54 baseline (the STRONGEST non-widening position).** The plan's original "byte-identical
> contract tree" premise was WRONG — the v54->v55 step IS the AfKing dissolution (13 contract files differ), so
> the v54 baseline red union could NOT be carried verbatim from a prior doc. It was established **EMPIRICALLY** in
> the same session: checkout `20ca1f79` -> `node scripts/lib/patchForFoundry.js` -> `forge test --json` (WHOLE
> tree, the **11 uncompilable-at-v54 files sidelined**) -> `461 passed / 148 failed / 16 skipped` -> restore ->
> checkout back. The 11 files that did NOT compile at `20ca1f79` (referencing the vanished `afKing.poolOf` /
> de-custody API — `AfKingConcurrency`, `AfKingFundingWaterfall`, `AfKingSubscription`,
> `KeeperBatchAffiliateDeltaAudit`, `KeeperFaucetResistance`, `KeeperNonBrick`, `KeeperRewardRoutingSameResults`,
> `KeeperRouterOneCategory`, `RedemptionStethFallback`, `RouterWorstCaseGas`, `SweepPerPlayerWorstCaseGas`)
> contributed **ZERO compilable v54 reds** to the 148-name union — so **no baseline red could be lost** by the
> wholesale rewrite or the D-351-02 drops (there were none in those files to lose — they were broken at v54).

### §5c The D-351-01 rewrite map + the D-351-02 drops + the 14 NARROWING fixes are ATTRIBUTED via the ledger, NOT counted as regression
- **The D-351-01 wholesale REWRITE MAP** (ledger §3a) — the 11 uncompilable-at-v54 afking/keeper files +
  `DeployProtocol.sol` rewritten to the game-resident `GameAfkingModule` path (the five call-site deltas:
  `afKing.subscribe`->`game.subscribe`, `doWork`->`mintBurnie`, `autoBuy(N)`->the `advanceGame()` STAGE,
  cold-ledger->warm Sub-stamp, cross-contract `afkingFunding` reads->in-context SLOADs, + every pinned slot
  RE-DERIVED via `forge inspect storage DegenerusGame`). A renamed/relocated test is a **rewrite-map entry
  (OUT-old + IN-new)**, never a new red. Each v54 file -> its v55 adapted successor is enumerated BY NAME +
  plan/commit (e.g. `AfKingConcurrency`->game-resident swap-pop/STAGE-reclaim 351-02 `0f78c896`;
  `KeeperNonBrick`->game-resident revert-free 351-05 `49ce1908`; `RouterWorstCaseGas`->STAGE-50 + `mintBurnie`
  under 16.7M 351-07 `e334a91a`).
- **The 4 dedicated v55 proof files authored** (ledger §5, all GREEN, contribute zero red):
  `V55FreezeDeterminism.t.sol` (TST-01, 7 tests), `V55RevertFreeEvCap.t.sol` (TST-02 + TST-03, 11 tests),
  `V55SetMutationOpenE.t.sol` (TST-04, 10 tests), `V55AfkingGasMarginal.t.sol` (TST-06, 5 tests) =
  **33 passing**.
- **The D-351-02 removed-surface DROPS** (ledger §3b, BY NAME + reason — NOT counted as regression; **every drop
  is from the 11 uncompilable-at-v54 files -> zero compilable v54 reds lost**): **D1** WHOLE FILE
  `KeeperBatchAffiliateDeltaAudit.t.sol` (`git rm` 351-06 `c5f600bd` — the removed `batchPurchase` +
  never-landed `batchPurchaseForKeeper`; affiliate-conservation survives non-redundantly in
  `AffiliateDgnrsClaim.t.sol` + the per-buy `payAffiliate`); **D2** `RedemptionStethFallback ::
  test_POOL04_BurnAtGameOverRecoversPool_ZeroPoolTokenSafe` (partial leg, 351-06 `aad3aad8` — the v54 de-custody
  recovery removed, `burnAtGameOver` now a pure local-token burn; the 6 RFALL05 ETH-vs-stETH core + POOL-04
  (a)/(b)/(c) receive() tests KEPT/reframed onto the GAME-only gate); **D3** `KeeperNonBrick.t.sol` the
  `batchPurchase` per-slice try/catch ISOLATION leg (6 tests, 351-05 `49ce1908` — `game.batchPurchase` doesn't
  exist on the v55 game; the reentrancy-rollback + un-brickable-cancel + TOMB-04 + AFSUB-03 properties REFRAME onto
  `withdrawAfkingFunding`/`subscribe(_,0)`/the STAGE); **D4** `RouterWorstCaseGas.t.sol` the 7 AfKing
  cursor/bounty-calibration gas tests (reframed-out 351-07 `e334a91a` onto the STAGE-50 + `mintBurnie` open leg
  under 16.7M); **D5** `KeeperLeversAndPacking.t.sol` the v49 `batchPurchase` source-grep gates (asserted ABSENT
  count==0 351-07 `6c69e627`).
- **The 14 NARROWING fixes** (ledger §3c, `v54 union - v55 live`, v54 red -> v55 green — the opposite of a
  regression): `KeeperLeversAndPacking` (3), `KeeperOpenBoxWorstCaseGas` (3), `KeeperResolveBetWorstCaseGas` (4),
  `RngLockDeterminism` (4) — all in the adapted afking/gas corpus, flipped GREEN by the re-pointing/re-derivation/
  stamped-day adaptation.

### §5d SWEEP NON-WIDENING attestation
Every `git diff 20ca1f79 453f8073 -- contracts/ test/` hunk is attributable to a known v55-scope commit: the
349.1 box-redesign `77c3d9ef` + the 349.2 restore `453f8073` (the contract surface, §3.A) + the AGENT-committed
351 TST test work (the §5c rewrite map, the 4 dedicated proof files, the D-351-02 drops, and
`test/REGRESSION-BASELINE-v55.md` itself). `git diff 453f8073 HEAD -- contracts/` is **EMPTY** (zero contract
mutation in this terminal phase; subject byte-frozen). The ledger's **FC1-FC6** false-confidence guards are all
mitigated (FC1 name-set not count; FC2 every delta attributed BY NAME; FC3 the §6 `## STOP` block returned
empty; FC4 the WHOLE tree was run at BOTH HEADs + `forge build` EXIT 0; FC5 the flaky cluster kept in the
Bucket-F ceiling; FC6 the empirical v54 re-derivation + the 11-file zero-compilable-reds proof + every
rewrite/drop reconciled BY NAME). The Hardhat sanity arm: `npx hardhat compile` EXIT 0 (32 files); the one
afking-referencing Hardhat suite `test/unit/DegenerusGame.test.js` is BYTE-IDENTICAL between `20ca1f79` and HEAD
(the three methods it references were ALREADY ABSENT at v54 — no v55-introduced ABI break). **NON-WIDENING
confirmed.**

---

## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification
- **KNOWN-ISSUES.md byte-unmodified** vs v54 (`git diff 20ca1f79 HEAD -- KNOWN-ISSUES.md` empty;
  KNOWN-ISSUES.md lives at the REPO ROOT, not `audit/`). No KI promotion/demotion this milestone; the SC1 sweep
  surfaced no KI-eligible item (0 FINDING_CANDIDATE). The one out-of-scope informational advisory (O1, the
  pre-existing symmetric `DegenerusQuests` lootbox-quest double-credit) is NOT a v55 KI promotion — it is
  PRE-EXISTING, out of the v55 delta, and routed to a future quest-core audit lane + the v52 consolidated audit
  (§8 / §9d); it does not touch this milestone's KNOWN-ISSUES.md ledger.
- **RNG-freeze intact** under the game-resident model — the per-subscriber process/open passes introduce NO
  in-window SLOAD a player can manipulate (the v45 north-star, [[v45-vrf-freeze-invariant]]; §3.B): the afking
  open is **post-RNG** (`_afkingBoxReady` false until `rngWordByDay[lastAutoBoughtDay] != 0` lands,
  `GameAfkingModule:921-934` — the open path is blocked in the protected window), the stamp froze the SEED at
  **process (pre-RNG)** behind the `subsFullyProcessed` STAGE-before-`rngGate` gate (FREEZE-02,
  `AdvanceModule:294`/`:300-325`), and the box draw consumes only frozen/stamped inputs + the benign EV-cap clamp
  (FREEZE-01b). The 349.1 LIVE-level resolve is the same posture as the human `openLootBox` (the outcome bucket
  is a pure function of the frozen seed; the live level cannot change WHICH prize is won, only `targetPrice`, and
  open timing is not player-controlled — the permissionless bounty-incentivized open, §4.3 FREEZE-iii). The
  mid-day `requestLootboxRng` path lives in a disjoint `lootboxRngWordByIndex` keyspace the DAY-keyed afking open
  never reads (FREEZE-02 / §4.3 FREEZE-ii). GAS-02's no-STATICCALL trace (TST-06) confirmed 0 foreign re-entrant
  afking-funding-view StaticCalls on the STAGE + the open.
- **Obligations conserved** — the SOLVENCY-01 spine (the Phase-343 master inequality `balance +
  steth.balanceOf(this) >= claimablePool`, inclusive of the afking total) is HELD NET under the game-resident
  model: the `afkingFunding` ledger rides **INSIDE** `claimablePool` (`DegenerusGameStorage:358` INVARIANT
  `claimablePool == sum claimableWinnings[*] + sum afkingFunding[*]`; every `afkingFunding` mutation moves
  `claimablePool` in tandem, `:416`), so there is **no new aggregate** — the afking funding is a sub-account of
  `claimablePool` and the master inequality inherits the v54-correct yield-surplus / gameOver-drain / stETH-stake
  wiring for free (§3.B / §3.5). The 349.2-restored affiliate/quest rewards are minted BURNIE flip-credit
  (`coinflip.creditFlip`, `GameAfkingModule:806`/`:816`/`:831`), OFF the ETH/`claimablePool` path — `_ethToBurnie`
  is the valuation basis only, so the existing ETH accounting is byte-UNCHANGED (no new emission, no solvency
  surface; GAS-03 re-confirmed). The empirical guard that an afking debit can never silently breach the invariant
  is the **class-B fail-loud** (TST-02 — a forced `claimablePool` underflow reverts `Panic(0x11)` at the checked
  `uint128 -=`, never masked; no try/catch valve, D-348-04). No accounting axis widened.

---

## 7. Prior-Artifact Cross-Cites
- **v55.0 phase artifacts:** Phase 348 SPEC (the D-08 multi-doc set — `348-FREEZE-PROOF.md` [FREEZE-01/02/03
  proven] + `348-INVARIANT-CARRY.md` [the discharged REVERT-FREE-CHAIN + EV-cap invariants + the D-348-04
  try/catch DROP] + `348-PLACEMENT-DECISION.md` [D-348-01 required-path] + `348-CODE-SIZE-PLAN.md` +
  `348-GAS-INVENTORY.md` + `348-IMPL-EDIT-ORDER-MAP.md` + `348-SPEC-INDEX.md`); Phase 349 IMPL — the 349.1 box
  redesign `77c3d9ef` + the 349.2 quest/affiliate restore `453f8073` (both USER-APPROVED hand-review) +
  `349.1-DESIGN.md` + `349.2-DESIGN.md`; Phase 350 GAS `350-OUTCOME.md` (Outcome-A) + `350-GAS-SKEPTIC-VERDICTS.md`
  + `350-TST06-MEASUREMENT-SPEC.md`; Phase 351 TST `351-VERIFICATION.md` (status passed, gsd-verifier 6/6) + the 4
  dedicated proof files (`V55FreezeDeterminism.t.sol` / `V55RevertFreeEvCap.t.sol` / `V55SetMutationOpenE.t.sol` /
  `V55AfkingGasMarginal.t.sol`) + `test/REGRESSION-BASELINE-v55.md`; Phase 352 logs
  (`352-01-DELTA-AUDIT.md` + `352-02-ADVERSARIAL-LOG.md` + the 3 per-skill sweep outputs).
- **Prior milestone FINDINGS templates:** `audit/FINDINGS-v49.0.md` (the proven 9-section template this report
  mirrors, shipped across v44/v46/v47/v48/v49); `audit/FINDINGS-v48.0.md` / `audit/FINDINGS-v47.0.md` /
  `audit/FINDINGS-v46.0.md` / `audit/FINDINGS-v44.0.md` (the 9-section templates + the v44 §9d maximalist handoff
  register).
- **Carry-forward anchors:** the v54 audit baseline `20ca1f79` (the raw SHA — v54.0 closed-superseded with NO
  `MILESTONE_V54_AT_HEAD` signal); the discharged foundations `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` (§10 canonical)
  + `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` (§5 = the 4 LOCKED obligations, obligation 4 DROPPED at D-348-04) + the
  Phase-343 SOLVENCY-01 master invariant; the v44 §9d maximalist handoff register (135 anchors — NOT live vectors,
  [[project_rnglock_audit_disposition]]), carried forward unchanged (§9d).

---

## 8. Forward-Cite Closure
- **0 prior-milestone findings carried into v55.0.** v54.0 closed-as-superseded with 0 NEW findings (343 SPEC +
  344 IMPL shipped `20ca1f79`; 345/346/347 dropped → folded into v55); there was no deferred finding to resolve
  this milestone.
- **Newly-surfaced 352-02 finding:** NONE. The 3-skill sweep produced 0 FINDING_CANDIDATE across 21 charged-probe
  rows. **One OUT-OF-SCOPE informational advisory (O1) carried forward (NOT a v55.0 finding):** the pre-existing
  symmetric lootbox-quest BURNIE double-credit in the UNCHANGED `DegenerusQuests` core (`handlePurchase` credits
  `lootboxReward` via `creditFlip` AND includes it in `totalReturned`, which both callers re-credit) — it is
  PRE-EXISTING + SYMMETRIC across the manual `purchaseWith` path AND the afking path (NOT a 349.2 regression),
  `DegenerusQuests.sol` is NOT in the v55 delta (out of the v55 blast radius), and it is a fixed day-idempotent
  ≤300-BURNIE flip-stake entirely OFF the ETH/`claimablePool`/solvency path. **Routed to a future quest-core
  (`DegenerusQuests`) audit lane + the v52 consolidated cross-model audit** (§4.3 / §9d). It does NOT amend the
  `0 NEW_FINDINGS` verdict.
- **Prior-milestone v55 descriptive seeds now SHIPPED (no longer forward-seeds):** the AfKing-in-Game fold
  (ARCH-01..04 — `AfKing.sol` dissolved into `GameAfkingModule` + the `DegenerusGameStorage` append), the box
  redesign (BOX-01..05 — boons-OFF amount=spend, the 4-field stamp, the DAY-keyed seed, the live-level open, the
  `lastOpenedDay` no-double-open), and the 349.2 quest/affiliate restore (the afking LOOTBOX-sub per-buy BURNIE
  flip-credit).
- **v56 forward-seeds carried forward (deferred, OUT of v55 — contract changes):**
  - **Batch-afking-affiliate-quest aggregation seed** ([[v56-batch-afking-affiliate-quest-seed]], USER 2026-05-31,
    designed live during 349.2/350). After 349.2 restores the afking lootbox quest+affiliate **per-buy**, the gas
    optimization is to **batch the afking affiliate + quest to ~every 10 days** so the daily STAGE drops back to a
    cheap stamp+debit+accrual (no daily cross-contract `handlePurchase`/`payAffiliate`/`creditFlip` — most of the
    ~262k/sub `SUB_STAGE_BATCH` budget; quest state lives in the separate `DegenerusQuests` contract). USER
    decision: its OWN full-effort phase/milestone (v56-ish), spun after v55, **WITH a mandatory 3-skill
    adversarial economic review** (`/contract-auditor` + `/economic-analyst` + `/zero-day-hunter`) to hunt
    exploits AND determine whether they actually matter. Affiliate (cleanly batchable): accrue daily into a
    per-sub accumulator, settle on a ~10-day flush (a `mintBurnie` router leg) OR any sub mutation (flush at
    locked params first); the scheduled flush KEEPS the per-buy winner-takes-all roll (un-gameable), a
    deterministic EV-equivalent split ONLY on the player-triggered mid-cycle alteration. Quest (harder — the
    SHARED `DegenerusQuests` core): afking = slot-0 + the streak, with the streak-skip guard suppressing only the
    duplicate STREAK credit (never the slot rewards), a confirmed-vs-provisional streak read (bonuses MUST read
    delivered, not pre-credited), and a `lastCompletedDay` double-credit guard — TOUCHES the shared quest core →
    needs freeze/double-credit/solvency proofs. (Note: the historical escalating/milestone streak BURNIE bonus
    USER-DECLINED restoring — the current 1%/activity-score model stays.) A contract change to `GameAfkingModule`/
    `DegenerusQuests`, OUT of v55.
  - **Terminal-decimator final-day streak-boost seed** ([[terminal-decimator-final-day-streak-boost-seed]], USER
    backlog 2026-05-30). A one-time final-day `boostTerminalDecimator()` (callable while `!gameOver`) that
    validates a live, valid quest streak via the canonical `DegenerusQuests` path and multiplies the player's
    `weightedBurn` (NOT bucket/odds) by a streak factor (anchors: streak 100→20x, 10→4x), folding the delta into
    `terminalDecBucketBurnTotal` so the pool still finalizes in the resolution tx. WEIGHT-only → the `require(!gameOver)`
    gate is freeze-safe; must verify lazy day-gap-reset/raw-streak, shields consume-vs-check, uint88 overflow,
    quest-streak double-count. Doc `PLAN-TERMINAL-DECIMATOR-STREAK-BOOST.md`. A contract change, OUT of v55.
- **The v52 consolidated cross-model audit (ADDITIONAL track — NOT a substitute).** The separate v52 consolidated
  cross-model audit STILL folds the v55 surface into its cumulative sweep as an ADDITIONAL track (recorded in the
  v52 charge), NOT a substitute for this in-milestone close. Per STATE.md the v50/v51 internal sweeps were
  deferred → v52, but **v54.0 + v55.0 run their OWN in-milestone close because they touch the solvency/freeze
  spine** (`claimablePool` + the RNG-freeze invariant). The O1 advisory + any cumulative cross-model re-probe of
  the AfKing-in-Game surface fold into the v52 charge alongside the prior-deferred v50/v51 surfaces.
- **Carry-forward (NOT live vectors):** the v44 §9d maximalist handoff register (135 anchors) carries forward
  unchanged ([[project_rnglock_audit_disposition]]).

---

## 9. Milestone Closure Attestation

### 9a. Closure Verdict

**Locked target (ROADMAP Phase 352 goal + the v55 surface set, for the record):**
`AFKING_IN_GAME_FOLD SHIPPED (AfKing.sol dissolved -> GameAfkingModule delegatecall + DegenerusGameStorage append; ARCH-01..04); BOX_REDESIGN SHIPPED (boons-OFF amount=spend, per-sub 4-field stamp scorePlus1+amount+lastAutoBoughtDay+lastOpenedDay, DAY-keyed seed rngWordByDay[day], live-level open byte-identical to openLootBox, lastOpenedDay no-double-open; BOX-01..05); FREEZE_SPINE INTACT (FREEZE-01/02/03 re-proven against the as-built 4-field/DAY-keyed/live-level model — the 349.1 live-level collapse NARROWS the frozen set to the SEED, strictly safe); REVERT_FREE_CHAIN DISCHARGED (REVERT-01 _resolveBuy verbatim revert-free-by-construction + REVERT-02 no-valve: fail-loud-on-solvency class B + terminal-routing-unblocked class C); EVCAP_AT_OPEN (EVCAP-01 RMW exactly-once, buy-time write bypassed, clamp sole live read, equivalent to v54); OPEN-E_4-PROTECTION RE-ATTESTED HOLD (CONSENT-01/02 consent-gate-at-subscribe / default-self / no-escalation / trust-the-sub + set-mutation no-cursor-advance-after-swap-pop / cancel-tombstone-streak); SOLVENCY-01 HELD NET (afkingFunding rides inside claimablePool, no new aggregate); GAS Outcome-A (GAS-01/02 structural to the relocation, GAS-03 REJECTED-with-reasoning); RNG_FREEZE_INTACT under the game-resident model; NON-WIDENING 603/134/16 (134-red SUBSET of the v54 148-name union BY NAME); 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`

**Actual verdict (the sweep surfaced 0 FINDING_CANDIDATE -> the `0 NEW_FINDINGS` clause HOLDS UNAMENDED; one
PRE-EXISTING, out-of-scope, immaterial informational advisory [O1] is recorded — NOT a v55.0 finding, does NOT
amend the verdict):**
`AFKING_IN_GAME_FOLD SHIPPED (AfKing.sol dissolved -> GameAfkingModule delegatecall + DegenerusGameStorage append, AF_KING address removed 1->0, receive()/credit gates retargeted GAME-only; ARCH-01..04); BOX_REDESIGN SHIPPED (boons-OFF amount=spend, the COMMITTED 4-field stamp scorePlus1+amount+lastAutoBoughtDay+lastOpenedDay [349.1 SUPERSEDED the 348 5-field (index,...,baseLevelPlus1) design], DAY-keyed seed rngWordByDay[lastAutoBoughtDay], live-level open byte-identical to openLootBox, lastOpenedDay no-double-open; BOX-01..05); FREEZE_SPINE INTACT (FREEZE-01/02/03 re-proven against the as-built 4-field/DAY-keyed/live-level model — the live-level collapse NARROWS the frozen set to the SEED, strictly safe [the live read of level/score is the human-openLootBox posture, -EV to manipulate]; TST-01); REVERT_FREE_CHAIN DISCHARGED (REVERT-01 _resolveBuy verbatim revert-free-by-construction + REVERT-02 no-valve [D-348-04 dropped the try/catch]: fail-loud-on-solvency class B [Panic(0x11), never masked] + terminal-routing-unblocked class C; TST-02); EVCAP_AT_OPEN (EVCAP-01 RMW exactly-once, buy-time write bypassed, clamp sole live read, equivalent to v54; TST-03); OPEN-E_4-PROTECTION RE-ATTESTED HOLD (CONSENT-01/02 — the HARD BLOCKING condition SATISFIED, no element requires reversion, closure NOT blocked; TST-04); SOLVENCY-01 HELD NET (afkingFunding rides inside claimablePool, no new aggregate; the 349.2 affiliate/quest are BURNIE flip-credit OFF the ETH+pool path); GAS Outcome-A (GAS-01/02 CONFIRMED-STRUCTURAL by the relocation, GAS-03 REJECTED-with-reasoning, no contract diff); RNG_FREEZE_INTACT under the game-resident model (the afking open post-RNG, the SEED frozen pre-RNG, 0 foreign re-entrant StaticCalls); NON-WIDENING 603/134/16 (134-red SUBSET of the v54 148-name union BY NAME, live - union = empty); 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED; + 1 OUT-OF-SCOPE informational advisory O1 [pre-existing symmetric DegenerusQuests lootbox-quest double-credit, NOT in the v55 delta, immaterial off-ETH -> routed to a future quest-core lane + v52, does NOT amend the verdict]`

All clauses of the locked target hold verbatim; the only addition vs the locked target is the explicit O1
out-of-scope advisory carry (recorded for the closure gate's awareness, NOT a finding). `0 NEW_FINDINGS` is
UNAMENDED. (Had any FINDING_CANDIDATE survived the dual-gate, this verdict would be amended + the candidate flagged
for the 352-04 closure gate; none did.)

### 9b. 7-Phase Wave Summary
Phase 348 (SPEC design-lock, the D-08 multi-doc set, 6 plans/4 waves, paper-only — the FREEZE spine proven + the
discharged REVERT-FREE-CHAIN/EV-cap carried + the D-348-01 required-path placement + the D-348-04 try/catch DROP +
the sequenced code-size reclaim plan + ARCH-04 MEASURED Complete) + 349 (IMPL — the carefully-sequenced batched
fold + box redesign, shipped across the inserted **349.1** `77c3d9ef` [box redesign — live-level resolve, DAY-keyed
word, drop `_afkingEpoch`/stamp-`index`, NO-ORPHAN guard, ticket/lootbox split, `doWork`→`mintBurnie`, dead
`AF_KING` removal] + **349.2** `453f8073` [restore quest-credit + affiliate for afking LOOTBOX subs as BURNIE
flip-credit OFF the ETH/pool path]; both USER-APPROVED hand-review) + 350 (GAS — Outcome A, NO net contract change;
GAS-01/02 CONFIRMED-STRUCTURAL by the 349/349.1 relocation, GAS-03 REJECTED-with-reasoning) + 351 (TST, 9 plans,
sequential-on-main no-worktrees, ZERO contract mutation; TST-01..06 + the NON-WIDENING **603/134/16** regression
ledger, gsd-verifier 6/6) + 352 (TERMINAL — this deliverable; SOURCE-TREE FROZEN at `453f8073`; the SC1 delta-audit
+ the SC1 3-skill genuine-PARALLEL sweep + the regression + the gated closure flip). NOTE: **7 phases** (the v49.0/
v54.0 SPEC→IMPL→GAS→TST→TERMINAL shape + the TWO inserted IMPL phases 349.1 + 349.2). Closure signal:
`MILESTONE_V55_AT_HEAD_<sha>` (the literal placeholder; resolved at 352-04).

### 9c. Closure Signal
**`MILESTONE_V55_AT_HEAD_<sha>`** (the literal placeholder — resolved to the Phase 352 audit-deliverable / closure
commit's own SHA in 352-04 [self-referential]; contracts byte-identical to the frozen subject `453f8073`).
Verbatim propagation targets (resolved at the 352-04 closure gate by the single sed-style SHA substitution):
1. Frontmatter `closure_signal:` + `audit_subject_head:`.
2. §1 Audit Subject prose.
3. §9b / §9c references.
4. ROADMAP.md (the v55.0 milestone flip).
5. STATE.md (Last Shipped Milestone) + MILESTONES.md (archive entry) + PROJECT.md (the v55.0 evolution).
6. REQUIREMENTS.md (all 29 v55.0 requirement row-flips re-attested at closure — the SPEC/GAS/TST reqs already
   Complete; the IMPL reqs ARCH-01/02/03 + BOX-01..05 + REVERT-01/02 + EVCAP-01 + CONSENT-01/02 + PLACE-02 + AUDIT-01
   flip at the 352-04 closure).

`chmod 444` is applied to `audit/FINDINGS-v55.0.md` at the 352-04 closure HEAD (the v44/v46/v47/v48/v49 precedent),
NOT here — this deliverable stays writable until the closure flip resolves the SHA + applies the read-only bit.

### 9d. Deferred to v56+ — Handoff Register
- **0 NEW findings deferred.** The SC1 sweep produced 0 FINDING_CANDIDATE; there were no prior-milestone deferred
  findings carried into v55 (v54.0 closed clean). Nothing is carried forward as a finding.
- **OUT-OF-SCOPE informational advisory (NOT a finding) — the pre-existing `DegenerusQuests` lootbox-quest
  double-credit (O1).** `DegenerusQuests.handlePurchase`'s lootbox branch credits `lootboxReward` via `creditFlip`
  AND includes it in `totalReturned` (both callers re-credit) → a completed LOOTBOX quest's fixed reward
  (100/200/300 BURNIE) appears credited twice. It is PRE-EXISTING + SYMMETRIC across the manual `purchaseWith`
  path AND the afking path (NOT a 349.2 regression); `DegenerusQuests.sol` is NOT in the v55 delta (out of the v55
  blast radius); the amount is a fixed, day-idempotent BURNIE flip-stake, entirely OFF the ETH/`claimablePool`/
  solvency path. **Recorded for the USER's awareness; routed to a future quest-core (`DegenerusQuests`) audit lane
  + the v52 consolidated cross-model audit** (the v48 SWAP cash-share doc-drift class — an out-of-scope informational
  carry). It does NOT amend the verdict or stop closure.
- **v56 forward-seeds (§8):** the batch-afking-affiliate-quest aggregation seed
  ([[v56-batch-afking-affiliate-quest-seed]], with the mandatory 3-skill adversarial economic review — touches the
  shared `DegenerusQuests` core); the terminal-decimator final-day streak-boost seed
  ([[terminal-decimator-final-day-streak-boost-seed]]). Both are contract changes, OUT of v55.0 scope.
- **The v52 consolidated cross-model audit (ADDITIONAL track).** The v55 surface (the AfKing-in-Game fold + the box
  redesign) folds into the v52 cumulative sweep as an ADDITIONAL track alongside the prior-deferred v50/v51
  surfaces — NOT a substitute for this in-milestone close (§8).
- The v44 §9d maximalist handoff register (135 anchors) carries forward unchanged (NOT live vectors).

---

*v55.0 TERMINAL findings authored 2026-06-01. Source-tree frozen throughout (`git diff 453f8073 HEAD --
contracts/` empty). 0 NEW findings (the 3-skill genuine-PARALLEL sweep surfaced 0 FINDING_CANDIDATE across 21
charged-probe rows: 18 NEGATIVE-VERIFIED + 3 SAFE_BY_DESIGN; the box-stamp-freeze + liveness-isolation +
two-path-open spine holds adversarially against the as-built 4-field/DAY-keyed/live-level model; the OPEN-E
4-protection HARD BLOCKING condition SATISFIED — closure NOT blocked). One PRE-EXISTING, out-of-scope, immaterial
informational advisory (O1, the symmetric `DegenerusQuests` lootbox-quest double-credit) recorded + routed to a
future quest-core lane + the v52 consolidated audit — NOT a v55.0 finding, does NOT amend the `0 NEW_FINDINGS`
verdict. KNOWN-ISSUES.md byte-unmodified. The COMMITTED 4-field stamp / DAY-keyed seed / live-level open framing
used throughout (349.1 SUPERSEDED the 348 5-field design). Closure signal `MILESTONE_V55_AT_HEAD_<sha>` resolves
at the Phase 352 closure commit (352-04); chmod 444 applied at closure (NOT here).*
