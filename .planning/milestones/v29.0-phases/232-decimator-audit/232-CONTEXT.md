# Phase 232: Decimator Audit - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Mode:** auto

<domain>
## Phase Boundary

Adversarial audit of every decimator-related change since the v27.0 baseline (`14cb45e1`, 2026-04-12 21:55). Three owning commits:

- `3ad0f8d3` fix(decimator): key burns by resolution level, consolidate jackpot block — touches `DegenerusGameDecimatorModule.sol`, `DegenerusGameAdvanceModule.sol` (consolidated jackpot block tail), `BurnieCoin.sol` (burn-key plumbing via `degenerusGame.level() + 1`)
- `67031e7d` feat(decimator): emit `DecimatorClaimed` and `TerminalDecimatorClaimed` — touches `DegenerusGameDecimatorModule.sol` (two new events + four new `emit` sites)
- `858d83e4` feat(game): expose `claimTerminalDecimatorJackpot` passthrough — touches `DegenerusGame.sol` (new external wrapper) + `IDegenerusGame.sol` (new interface declaration)

Phase must deliver per-function adversarial verdicts for all three commits covering burn-key correctness (DCM-01), event CEI/argument correctness + indexer-compat observation (DCM-02), and passthrough access-control/reentrancy (DCM-03). All verdicts cite commit SHA + file:line and become finding candidates for Phase 236 consolidation.

Scope is strictly READ-only per v29.0 milestone rule: NO writes to `contracts/` or `test/`. Phase 230 catalog (`230-01-DELTA-MAP.md`) is also READ-only per D-06 — any catalog gap becomes a scope-guard deferral here, not an in-place edit. No `F-29-NN` finding IDs emitted this phase (finding-ID assignment is Phase 236's job).

</domain>

<decisions>
## Implementation Decisions

### Deliverable Shape
- **D-01:** Three plans, one per DCM requirement: `232-01-PLAN.md` (DCM-01 burn-key refactor), `232-02-PLAN.md` (DCM-02 event emission), `232-03-PLAN.md` (DCM-03 passthrough). Matches v29.0 auto-mode rule #5 (one plan per requirement) and ROADMAP Phase 232 block (expected 2-3 plans). Prevents any single plan from drifting beyond a narrowly scoped audit surface.

### Audit Methodology
- **D-02:** Per-function adversarial verdict table with fixed columns: `Function | File:Line | Attack Vector | Verdict | Evidence | SHA`. Verdict domain: `SAFE | SAFE-INFO | VULNERABLE | DEFERRED`. Mirrors v25.0 Phase 214 adversarial-audit precedent and the ROADMAP Phase 232 Success Criterion 4 citation rule.
- **D-03:** Every audited function row MUST cite its owning commit SHA from `{3ad0f8d3, 67031e7d, 858d83e4}` and a file:line reference to the HEAD source. No un-cited verdicts.

### Scope Anchoring
- **D-04:** Scope source is `230-01-DELTA-MAP.md` exclusively. Plans cite the section anchors already enumerated in §4 Consumer Index:
  - DCM-01 → §1.3 (entire DecimatorModule), §1.1 (`_consolidatePoolsAndRewardJackpots`), §1.8 (`BurnieCoin.decimatorBurn`), §2.2 rows IM-06/IM-07/IM-09, commit `3ad0f8d3`
  - DCM-02 → §1.3 (`claimDecimatorJackpot`, `claimTerminalDecimatorJackpot` event-emission hunks) + event declarations `DecimatorClaimed` / `TerminalDecimatorClaimed`, §2.2 IM-08 callee-side, commit `67031e7d`
  - DCM-03 → §1.6 (`DegenerusGame.claimTerminalDecimatorJackpot` NEW), §1.10 (`IDegenerusGame` interface decl), §3.1 ID-30, §3.3.d ID-93, §2.2 IM-08, commit `858d83e4`
- **D-05:** Any surface discovered outside §4 DCM rows during execution becomes a scope-guard DEFERRED row pointing to Phase 236 (D-227-10 → D-228-09 precedent). The catalog itself is not edited.

### DCM-01 Burn-Key Audit Focus
- **D-06:** Pro-rata share calculation MUST be audited for off-by-one under the new `lvl = degenerusGame.level() + 1` keying. Plan 232-01 enumerates every `decBurns`, `decBurnBuckets`, and `decPool` read site inside `DegenerusGameDecimatorModule.sol` and verifies each reader uses the resolution-level key (not the pre-resolution level). Explicit check that `recordDecBurn` (IM-06 consumer), `runDecimatorJackpot` (IM-07 callee), `consumeDecClaim`, `claimDecimatorJackpot`, and `decClaimable` all read and write the same key space. Satisfies ROADMAP SC1.
- **D-07:** Consolidated jackpot-block ordering in `_consolidatePoolsAndRewardJackpots` (IM-06) MUST be verified: the previously-separate `prevMod100 == 0` (x00) and `prevMod10 == 5 && prevMod100 != 95` (x5) branches now share a single tail — plan verifies branches are mutually exclusive, `decPoolWei` is deterministically zero when neither condition holds, and the `runDecimatorJackpot` self-call still runs with the correct args and CEI position. Satisfies ROADMAP SC1.

### DCM-02 Event Audit Focus
- **D-08:** CEI position of both new events MUST be verified in Plan 232-02:
  - `DecimatorClaimed` — emitted at two sites inside `claimDecimatorJackpot`: (a) the gameOver fast-path post-`_creditClaimable`, (b) the normal ETH/lootbox split post-`_setFuturePrizePool`. Both sites must be AFTER all state mutations (credit + pool write) to satisfy CEI.
  - `TerminalDecimatorClaimed` — emitted immediately after `_creditClaimable(msg.sender, amountWei)`, which itself follows `_consumeTerminalDecClaim` state mutation. Plan verifies emission happens AFTER consume + credit.
- **D-09:** Event argument correctness MUST be verified per §1.3:
  - `DecimatorClaimed(address indexed player, uint24 indexed lvl, uint256 amountWei, uint256 ethPortion, uint256 lootboxPortion)` — plan verifies `ethPortion + lootboxPortion == amountWei` at emission, `lvl` matches the input-level argument to `claimDecimatorJackpot`, `player == msg.sender`.
  - `TerminalDecimatorClaimed(address indexed player, uint24 indexed lvl, uint256 amountWei)` — plan verifies `lvl == lastTerminalDecClaimRound.lvl` (resolved claim round, not caller-controlled), `amountWei` matches consumed claim.
- **D-10:** v28.0 indexer-compat check is a READ-only observation per auto_mode rule #7. Plan 232-02 documents whether the two new event signatures are already registered in the v28.0 indexer event-processor surface (reference: v28.0 Phase 227 event-surface audit). If absent, that becomes an indexer-side gap — recorded as a Phase 236 FIND-02 KNOWN-ISSUES candidate or deferred to a future `database/` milestone. Zero writes to `database/` this phase (out of scope per v29.0 PROJECT.md).

### DCM-03 Passthrough Audit Focus
- **D-11:** Plan 232-03 verifies the new `DegenerusGame.claimTerminalDecimatorJackpot` external wrapper for:
  - **Caller restriction:** No `onlyX` modifier on the wrapper (intentional — post-GAMEOVER player claim per NatSpec on ID-30). Plan verifies the target module `claimTerminalDecimatorJackpot` (ID-93) internally gates on game-state (post-gameover, resolved terminal claim round) so the missing wrapper-level guard is not a privilege escalation.
  - **Reentrancy:** Wrapper uses selector delegatecall via `IDegenerusGameDecimatorModule.claimTerminalDecimatorJackpot.selector` and forwards revert data through `_revertDelegate(data)`. Plan verifies no reentrancy window opens — module body completes all state mutations (consume + credit) before any external interaction, and claim is one-shot per terminal claim round.
  - **Parameter pass-through:** Wrapper takes zero args, delegates with empty calldata. Module function also takes zero args (level is read from storage `lastTerminalDecClaimRound.lvl`, not a caller argument — per NatSpec on ID-30). Plan verifies no caller-controlled parameter injection.
  - **Privilege escalation:** delegatecall preserves `msg.sender`, `msg.value`, and storage context. Plan verifies `_creditClaimable(msg.sender, ...)` credits the original caller, not the module address.
- **D-12:** Delegatecall-site count 43→44 vs v27.0 Phase 220 baseline is the NEW IM-08 wrapper. `make check-delegatecall` PASSED at HEAD per §3.5 (44/44 aligned). Plan 232-03 treats this as corroborating evidence, not a finding — Phase 230 D-04 already documented it as a known non-issue.

### Finding-ID + Artifact Discipline
- **D-13:** No `F-29-NN` ID emission this phase. Per-verdict rows carry a `Finding Candidate: Y/N` column; Phase 236 assigns canonical F-29 IDs during consolidation (REQUIREMENTS.md FIND-01 + v27.0 Phase 223 precedent).
- **D-14:** Conservation impact of the `BurnieCoin.decimatorBurn` change (`3ad0f8d3`) is INTENTIONALLY DEFERRED to Phase 235 CONS-02. Plan 232-01 limits its BurnieCoin scope to burn-key correctness (right key, right level, no stuck state); it does NOT attempt to close the mint/burn accounting loop. The catalog's IM-09 row is cited only for "caller's use of returned value" per Phase 230 Known Non-Issue #3.

### Out-of-Scope Reminders (claude's discretion)
- Plans MAY optionally cite Hardhat / Foundry test file names as evidence but MUST NOT propose or execute test changes.
- Plans MAY optionally note gas implications of the new event emissions as SAFE-INFO; gas-ceiling re-profile is NOT required (no loop-multiplied emissions; events are once-per-claim).
- Plans MAY optionally reason about 4-indexed-topic limit for the new events (both events have 2 indexed topics — well under the 4-topic EVM limit).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 230 catalog (authoritative scope — READ-only)
- `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md`
  - **§1.3** — DegenerusGameDecimatorModule.sol function-level changelog (event declarations + modified `claimDecimatorJackpot`, `claimTerminalDecimatorJackpot`)
  - **§1.6** — DegenerusGame.sol NEW `claimTerminalDecimatorJackpot()` wrapper row
  - **§1.8** — BurnieCoin.sol MODIFIED `decimatorBurn` (burn-key `lvl = degenerusGame.level() + 1`)
  - **§1.1** — DegenerusGameAdvanceModule.sol `_consolidatePoolsAndRewardJackpots` MODIFIED (consolidated jackpot block)
  - **§1.10** — IDegenerusGame.sol NEW `claimTerminalDecimatorJackpot()` interface declaration
  - **§2.2** — Decimator-related chains IM-06 (consolidated block → `runDecimatorJackpot` self-call), IM-07 (Game wrapper → module delegatecall), IM-08 (new terminal passthrough chain), IM-09 (BurnieCoin → Game.level getter)
  - **§3.1 ID-30** — IDegenerusGame `claimTerminalDecimatorJackpot() external` interface drift PASS
  - **§3.3.d ID-93** — IDegenerusGameModules `claimTerminalDecimatorJackpot() external` module-interface drift PASS
  - **§3.5** — automated gate rollup: check-delegatecall 44/44 PASS (the +1 site is IM-08)
  - **§4** — Consumer Index DCM-01, DCM-02, DCM-03 anchor rows
- `.planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md` — Known Non-Issues #3 (IM-09 call-unchanged-but-caller-arithmetic-changed) and #4 (43→44 delegatecall-site bump attribution)

### Milestone artifacts
- `.planning/REQUIREMENTS.md` — DCM-01, DCM-02, DCM-03 definitions + commit attribution
- `.planning/ROADMAP.md` — Phase 232 block (Goal, Depends on: Phase 230, Success Criteria 1-4)
- `.planning/PROJECT.md` — Current Milestone section lists all 10 in-scope commits
- `.planning/STATE.md` — Phase 230 complete; Phase 232 is one of four parallelizable post-230 audit phases

### Methodology precedent
- `.planning/milestones/v25.0-phases/214-adversarial-audit/` — per-function adversarial verdict table pattern (Function | File:Line | Attack Vector | Verdict | Evidence | SHA)
- `.planning/phases/230-delta-extraction-scope-map/230-CONTEXT.md` — CONTEXT.md shape being mirrored here
- v28.0 Phase 227 event-surface audit (`.planning/milestones/v28.0-phases/227-indexer-event-processing-correctness/`) — indexer-event-shape reasoning reused for DCM-02 indexer-compat observation

### Source files under audit (READ-only)
- `contracts/modules/DegenerusGameDecimatorModule.sol`
- `contracts/modules/DegenerusGameAdvanceModule.sol`
- `contracts/BurnieCoin.sol`
- `contracts/DegenerusGame.sol`
- `contracts/interfaces/IDegenerusGame.sol`
- `contracts/interfaces/IDegenerusGameModules.sol` (IDegenerusGameDecimatorModule sub-interface)

### Out-of-scope sibling artifacts (consulted read-only, not modified)
- `audit/FINDINGS-v28.0.md` — v28.0 indexer findings baseline for DCM-02 indexer-compat observation
- `audit/KNOWN-ISSUES.md` — READ-only; Phase 236 owns any KNOWN-ISSUES updates

</canonical_refs>

<code_context>
## Existing Code Insights

Bulleted observations from §1.3 / §1.6 / §1.8 / §2.2 / §3 DCM rows and §4 Consumer Index of `230-01-DELTA-MAP.md`:

### DCM-01 surface (commit `3ad0f8d3`)
- `BurnieCoin.decimatorBurn` has a 3-insertion / 1-deletion diff; the semantic change is one line: `uint24 lvl = degenerusGame.level() + 1;` (§1.8 verification note). The `+ 1` is the heart of DCM-01 — all downstream decimator read sites must match this key.
- `_consolidatePoolsAndRewardJackpots` in `DegenerusGameAdvanceModule.sol` (§1.1 + §2.2 IM-06) collapsed two separate branches (x00 and x5) into a single tail calling `runDecimatorJackpot`; IM-06 note states "Selector, args, and ordering unchanged" but the new branch-merge structure is where off-by-one or mutual-exclusivity bugs could hide.
- `DegenerusGameDecimatorModule.sol` surface in §1.3: all 9 module-level decimator functions (ID-86..ID-94) have PASS drift verdicts — signatures stable. The change is in function bodies, not selectors.
- IM-09 note in §2.2: "Call site itself unchanged (`degenerusGame.level()`). Caller body MODIFIED to compute `lvl = degenerusGame.level() + 1` post-call" — Phase 230 Known Non-Issue #3 explicitly scopes this as "inspect the caller's use of the returned value, not the call itself."

### DCM-02 surface (commit `67031e7d`)
- Two NEW event declarations on `DegenerusGameDecimatorModule.sol` (§1.3):
  - `DecimatorClaimed(address indexed player, uint24 indexed lvl, uint256 amountWei, uint256 ethPortion, uint256 lootboxPortion)`
  - `TerminalDecimatorClaimed(address indexed player, uint24 indexed lvl, uint256 amountWei)`
- Both events use 2 indexed topics — within the 4-topic EVM limit.
- `claimDecimatorJackpot` body (§1.3 row, ID-89 drift row): signature unchanged, body MODIFIED to emit `DecimatorClaimed` at two sites (gameOver fast path + normal split tail). No CEI reordering noted in §1.3.
- `claimTerminalDecimatorJackpot` body (§1.3 row, ID-93 drift row): signature unchanged, body MODIFIED to emit `TerminalDecimatorClaimed` immediately after `_creditClaimable`. §1.3 explicitly notes "state mutation in `_consumeTerminalDecClaim` already complete, credit applied, event emitted last" — CEI claim is prima facie correct per the catalog, but Plan 232-02 still verifies against HEAD source.
- v28.0 Phase 227 audited the v28.0-baseline event-processor surface; new events added post-v27 (i.e. this commit) were NOT in that audit's scope. Indexer-side registration is therefore an OBSERVATION in DCM-02 (not a contract-side finding).

### DCM-03 surface (commit `858d83e4`)
- `DegenerusGame.claimTerminalDecimatorJackpot()` is NEW (§1.6) — external wrapper that delegatecalls `IDegenerusGameDecimatorModule.claimTerminalDecimatorJackpot.selector` and forwards revert data through `_revertDelegate(data)`. Sibling-positioned after the existing `claimDecimatorJackpot(uint24 lvl)` wrapper.
- Interface drift: `IDegenerusGame.claimTerminalDecimatorJackpot()` is NEW (§1.10, ID-30) introduced in lockstep with the wrapper. Module-side `IDegenerusGameDecimatorModule.claimTerminalDecimatorJackpot()` (ID-93) is PASS — pre-existing selector.
- IM-08 (§2.2) is the only cross-module chain introduced by this commit: `DegenerusGame.claimTerminalDecimatorJackpot` → `DegenerusGameDecimatorModule.claimTerminalDecimatorJackpot` via delegatecall. Also doubles as the callee-side anchor for DCM-02 since `67031e7d` modifies the module body.
- `make check-delegatecall` registers this as site #44 (§3.5 + Known Non-Issue #4) — 44/44 aligned at HEAD. Alignment is corroborating evidence for DCM-03, not a finding.

### Automated-gate corroboration at HEAD
- `make check-interfaces` PASS (§3.4) — no interface drift anywhere, including the new wrapper pair.
- `make check-delegatecall` PASS 44/44 (§3.5) — IM-08 site aligned.
- `forge build` PASS (warnings only, pre-existing lints).

</code_context>

<specifics>
## Specific Ideas

### Plan count: 3
One plan per DCM requirement, each a single-file per-function adversarial audit:

1. **`232-01-PLAN.md` — DCM-01 Burn-Key Refactor Audit**
   - Cites: §1.3 (DecimatorModule surface), §1.1 (`_consolidatePoolsAndRewardJackpots`), §1.8 (`BurnieCoin.decimatorBurn`), §2.2 IM-06 / IM-07 / IM-09, commit `3ad0f8d3`
   - Deliverable: per-function verdict table (Function | File:Line | Attack Vector | Verdict | Evidence | SHA) covering every read/write site of decimator state (`decBurns`, `decBurnBuckets`, `decPool`) + consolidated jackpot-block tail
   - Satisfies ROADMAP SC1

2. **`232-02-PLAN.md` — DCM-02 Event Emission Audit**
   - Cites: §1.3 (`claimDecimatorJackpot`, `claimTerminalDecimatorJackpot` body hunks + event declarations), §2.2 IM-08 callee-side, commit `67031e7d`
   - Deliverable: per-function verdict table + dedicated CEI-position analysis for each of the 3 `emit` sites + 1-paragraph indexer-compat observation citing v28.0 Phase 227 (OBSERVATION only, not a finding)
   - Satisfies ROADMAP SC2

3. **`232-03-PLAN.md` — DCM-03 Terminal Claim Passthrough Audit**
   - Cites: §1.6, §1.10, §3.1 ID-30, §3.3.d ID-93, §2.2 IM-08, commit `858d83e4`
   - Deliverable: per-function verdict table covering wrapper (`DegenerusGame.claimTerminalDecimatorJackpot`) + interface declaration + delegatecall alignment corroboration from §3.5; attack-vector columns cover caller restriction, reentrancy, parameter pass-through, privilege escalation (ROADMAP SC3 literal items)
   - Satisfies ROADMAP SC3

All three plans share the D-02 column schema and the D-03 SHA-citation rule. ROADMAP SC4 ("every verdict cites commit SHA + file:line and is added to the Phase 236 finding candidate pool") is satisfied uniformly by D-02 + D-13.

</specifics>

<deferred>
## Deferred Ideas

### Deferred to Phase 235 CONS-02
- **BurnieCoin conservation end-to-end.** The `3ad0f8d3` change to `decimatorBurn` touches BURNIE accounting by changing the burn-key, but sum-in / sum-out over the full mint/burn surface is explicitly a Phase 235 CONS-02 deliverable per REQUIREMENTS.md + ROADMAP Phase 235. Plan 232-01 limits its BurnieCoin scope to burn-key correctness only (right level, right bucket, no stuck burns); it does NOT close the BURNIE accounting loop.

### Deferred to Phase 236 FIND-01 / FIND-02 / FIND-03
- **Finding-ID assignment.** No `F-29-NN` IDs emitted in Phase 232 artifacts. Every per-function verdict row carries a `Finding Candidate: Y/N` column; Phase 236 FIND-01 assigns canonical IDs during consolidation. ROADMAP SC4 "added to the Phase 236 finding candidate pool" is satisfied by the Y/N column plus the Phase 232 SUMMARY's finding-candidate-count metric.
- **KNOWN-ISSUES entries.** If the DCM-02 indexer-compat observation or the DCM-03 missing-caller-restriction reasoning surfaces a design-decision candidate, Phase 236 FIND-02 owns the KNOWN-ISSUES.md write.

### Deferred to `database/` repo out-of-scope
- **Actual indexer-side event-processor registration for `DecimatorClaimed` / `TerminalDecimatorClaimed`.** v29.0 PROJECT.md scopes this milestone to `contracts/` only; the `database/` repo is explicitly out of scope. Plan 232-02 documents the observation; no `database/` writes are planned or permitted.

### Scope-guard deferrals (if any emerge)
- If any of the three plans encounter a surface outside §4 DCM rows during execution, that surface becomes a DEFERRED verdict row with target Phase 236 (D-05 + D-227-10 precedent). Phase 230 catalog remains READ-only.

</deferred>

---

*Phase: 232-decimator-audit*
*Context gathered: 2026-04-17*
