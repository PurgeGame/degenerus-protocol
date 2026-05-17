# Phase 291: MINTCLN Regression Fixture (TST-MINTCLN) - Context

**Gathered:** 2026-05-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Ship the **TST-MINTCLN-01..05** regression fixture under `test/edge/` (or `test/mint/`) covering the contract changes that landed in Phase 290 (audit-subject commit `e5665117` — MINTCLN cleanup batch). The fixture asserts: (1) post-MINTCLN 3-input keccak preserves the v41 Phase 281 cross-call seed-separation invariant on multi-call drains; (2) `TraitsGenerated` decodes to the new 3-field `(player, baseKey, take)` shape with `baseKey` low 32 bits = `owed` at call entry + upper bits = `(lvl, queueIdx, player)`; (3) both B2-symmetric callsites covered (Path A `processFutureTicketBatch` whale-bundle + Path B `_processOneTicketEntry` direct purchase); (4) `ticketsOwedPacked[rk][player]` 40-bit packed-form storage byte-identical to v41 close on a representative drain; (5) breaking `TraitsGenerated` topic-hash documented in test-file header per v40 D-40N-EVT-BREAK-01 precedent. Single USER-APPROVED batched test commit; zero `contracts/` mutations.

</domain>

<decisions>
## Implementation Decisions

### Gas Measurement Scope
- **D-291-GAS-01:** **Skip empirical gas measurement entirely.** The theoretical worst-case attestation in `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md` §3 (~−19,131 gas per drain, ~−893 per emit, ~−18 per `_raritySymbolBatch`) is treated as load-bearing and complete. Phase 290 SUMMARY's "empirical confirmation handed off to Phase 291" wording is non-load-bearing — TST-MINTCLN-01..05 do NOT carry a gas requirement, and adding one would expand scope beyond the locked requirement set. No `console.log` informational gas measurement, no hard regression assertion against the theoretical bound, no TST-MINTCLN-06 expansion. **Why:** REQUIREMENTS.md TST-MINTCLN-01..05 is the locked scope; the theoretical-first attestation under `feedback_gas_worst_case.md` half is sufficient for a cleanup-shape phase with no production capital at risk; preserves the user's preference for tight scope on mechanical test phases per `feedback_skip_research_test_phases.md`. **How to apply:** Plan-phase MUST NOT add a gas requirement, gas assertion, gas helper, or informational gas log to the fixture; Phase 297 §3.A delta-surface table cites 290-MEASUREMENT.md §3 for the gas attestation, NOT Phase 291.

### Claude's Discretion (planner & executor latitude)

The following gray areas were considered but NOT selected for discussion — the planner uses the sister Phase 282 `test/edge/MintBatchDeterminism.test.js` pattern as the default and resolves details at plan-phase without re-asking the user:

- **TST-MINTCLN-01 oracle model.** The roadmap wording "post-MINTCLN trait multiset equals v41 Phase 281 owed-salt multiset at same `(level, queueIdx, player, dailyEntropy)`" cannot be literally bit-identical because the v41 4-input keccak (`baseKey, entropy, groupIdx, ownedSalt`) and v42 3-input keccak (`baseKey, entropy, groupIdx`) hash distinct inputs. Default disposition for the planner: **JS-replay oracle pattern (Phase 282 TST-FIX-01 ALGORITHM_VERIFIED)** — extend `test/helpers/raritySymbolBatchRef.mjs` (currently 183 LOC, v41 4-input form) with a v42 3-input variant; replay against the emitted `(player, baseKey, take)` tuples; assert on-chain credited multiset (via `DegenerusGame.getTickets(trait, lvl, 0, total, player)` reads) equals JS-reference multiset trait-by-trait. The "equals v41" wording reads as "preserves the v41 algorithm invariant of cross-call seed separation," NOT as "produces bit-identical hash outputs." Cross-call seed separation is asserted via a pairwise-distinct-keccak-input check across multi-call emissions (Phase 282 TST-FIX-03 pattern).
- **TST-MINTCLN-04 storage byte-identity technique.** Roadmap says "storage-slot grep proof reads same slot bytes pre + post-MINTCLN." Phase 290 MINTCLN-08 already attested storage layout EMPTY diff via `forge inspect storageLayout` cross-tree compare (290-MEASUREMENT.md §2). Default disposition for the planner: **eth_getStorageAt direct slot reads** at the mapping-derived slot for `ticketsOwedPacked[rk][player]` (mapping key = `keccak256(abi.encode(rk, mappingSlot))` → `keccak256(abi.encode(player, parentSlot))`), executed against the post-patch deployment running the same multi-call drain scenario used by TST-MINTCLN-01. Hard assertion: read slot returns the expected 40-bit packed form (rem low 8 + owed next 24 + processed-via-owed-salt high 8) with `processed` decoded to the expected post-drain value. The "pre + post-MINTCLN" comparison is satisfied structurally by Phase 290 MINTCLN-08's `forge inspect` diff (EMPTY); TST-MINTCLN-04 confirms the packed-form bytes at the runtime slot match the documented layout post-drain.
- **Test file shape & location.** Default disposition for the planner: **new file `test/edge/MintCleanupRegression.test.js`** (mirrors sister Phase 282 `MintBatchDeterminism.test.js` adjacent at `test/edge/`). Single file, all 5 TST-MINTCLN assertions. Do NOT extend Phase 282's `MintBatchDeterminism.test.js` in-place (mixes v41 and v42 assertions in one file; loses the Phase 282 file as a clean v41-closure artifact). Do NOT create `test/mint/` (no existing files there; not a justified directory split for one file).
- **B2 path-coverage strategy.** TST-MINTCLN-03 says TST-MINTCLN-01 + TST-MINTCLN-02 exercise both paths. Default disposition: **reuse the Phase 282 whale-bundle scenario** (2000-ticket purchase at lvl=1 + `_prepareFutureTickets` at lvl=2..5 naturally drives Path B at lvl=1 AND Path A at lvl=2..5 simultaneously in one drain run, with `path-accumulator=A|B` log discrimination per Phase 282 precedent). Scenario setup can be lifted into a shared helper in `test/helpers/` if the planner judges duplication intolerable, but inline duplication of ~50 LOC is acceptable — Phase 282's file is a frozen v41-closure artifact and should not be refactored.
- **TST-MINTCLN-05 indexer-migration note placement.** Roadmap explicitly says "test-file header path-of-investigation comment per v40 Phase 277 D-40N-EVT-BREAK-01 precedent." Default disposition: **JSDoc block at the top of the new test file** mirroring the Phase 282 `MintBatchDeterminism.test.js` header style; documents the v41 → v42 topic-hash transition (`0x5e96bf2d...` → `0x279edf1c...` from 290-MEASUREMENT.md §5), the indexer-rebuild handoff per inherited D-40N-EVT-BREAK-01 posture, and forward-cites Phase 297 §9 "Deferred to Future Milestones" for the migration-tooling handoff per D-42N-EVT-BREAK-01. Documentation-only — no on-chain assertion, no test logic.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Goal & Requirements
- `.planning/ROADMAP.md` — Phase 291 entry (success criteria 1–5; B2 symmetric callsite locks)
- `.planning/REQUIREMENTS.md` — TST-MINTCLN-01..05 detail lines (locked requirement set; do NOT expand scope)
- `.planning/PROJECT.md` — v42.0 milestone goal + audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`

### Phase 290 Audit-Subject Artifacts (load-bearing for this fixture)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md` — §(i) 3-input-hash invariant continuity rationale; §(ii) `TraitsGenerated` field-set rationale + zero-owed disposition; §(iii) breaking-topic-hash justification + indexer-migration steps; decision anchors D-42N-MINTCLN-SCOPE-01 + D-42N-EVT-BREAK-01
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md` — §2 storage byte-identity attestation (`forge inspect storageLayout` EMPTY); §3 theoretical gas worst-case (`~−19,131` per drain, used as gas reference, NOT replayed empirically per D-291-GAS-01); §4 selectors `0x9103766f` + `0x2ff3118b` UNCHANGED; §5 `TraitsGenerated` topic-hash transition v41 `0x5e96bf2d...` → v42 `0x279edf1c...` (test-file header cites this); §6 B2-symmetric callsite structural diff
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-02-SUMMARY.md` — Phase 290 audit-subject commit `e5665117` body (verbatim copy-forward source); 10/10 must-haves verified; key-decisions register

### Sister Test Pattern (extend, don't duplicate)
- `test/edge/MintBatchDeterminism.test.js` (794 LOC) — Phase 282 v41.0 mint-batch determinism regression fixture; reference pattern for whale-bundle B2 path coverage + JS-replay oracle + `path-accumulator=A|B` log discrimination
- `test/helpers/raritySymbolBatchRef.mjs` (183 LOC) — v41 4-input JS reference impl (extend with a v42 3-input variant for TST-MINTCLN-01 oracle; default disposition is in-file branch, NOT a new helper file)

### Audit Methodology Feedback (enforce at plan-phase)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_skip_research_test_phases.md` — skip research; plan directly
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md` — single USER-APPROVED batched test commit at phase close
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_contract_commits.md` — zero `contracts/` mutations in this phase
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md` — theoretical-first attestation (already shipped at Phase 290 §3); empirical confirmation SKIPPED per D-291-GAS-01
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` — TST-MINTCLN-01 cross-call seed separation evidence aligns with the backward-trace methodology (pairwise-distinct keccak inputs across batches)

### Inherited Anchors (carry-forward; do NOT re-derive)
- v40 Phase 277 D-40N-EVT-BREAK-01 (breaking topic-hash precedent) — cited in TST-MINTCLN-05 test-file header
- v41 Phase 281 owed-salt fix + Phase 282 ALGORITHM_VERIFIED test pattern — TST-MINTCLN-01 invariant continuity reference

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`test/edge/MintBatchDeterminism.test.js`** (Phase 282, 794 LOC): whale-bundle scenario at `purchaseLevel=1` + `_prepareFutureTickets` driving lvl=2..5 — naturally exercises Path B (`_processOneTicketEntry`) at lvl=1 AND Path A (`_processFutureTicketBatch`) at lvl=2..5 in a single drain run. Reuse this scenario shape for TST-MINTCLN-01 + TST-MINTCLN-02 + TST-MINTCLN-03; lift to a helper only if duplication >~50 LOC.
- **`test/helpers/raritySymbolBatchRef.mjs`** (183 LOC): v41 4-input keccak JS reference impl. Extend with a v42 3-input variant (drop `ownedSalt` arg; verify same `keccak256(abi.encode(baseKey, entropyWord, groupIdx))` shape used at `contracts/modules/DegenerusGameMintModule.sol:564`).
- **`test/helpers/deployFixture.js`**: standard deployment fixture used across `test/edge/` — pick this up for the post-MINTCLN deployment.

### Established Patterns
- **JS-replay oracle (ALGORITHM_VERIFIED)**: Phase 282 TST-FIX-01 established this as the multiset-equivalence pattern; replay against emitted event tuples + assert on-chain `getTickets(...)` reads match the replay; trait-by-trait equality check.
- **Path-accumulator log discrimination**: Phase 282's `console.log` per-call output flags `path-accumulator=A|B` to attest which path produced each emission; TST-MINTCLN-03 inherits this pattern as the B2 coverage proof.
- **JSDoc test-file header for path-of-investigation**: Phase 282's header documents reduced-scope decisions + design-intent links; Phase 291's header documents the breaking-topic-hash transition per TST-MINTCLN-05.
- **Single USER-APPROVED batched test commit**: per `feedback_batch_contract_approval.md`, the plan-phase produces ONE batched commit at close (5 tests + helper extension + header note in one diff).

### Integration Points
- New test file plugs into Hardhat test runner via `hardhat test test/edge/MintCleanupRegression.test.js` (planner-chosen filename; default disposition).
- JS helper extension to `test/helpers/raritySymbolBatchRef.mjs` is import-compatible with existing Phase 282 consumers (add a new exported function for v42 3-input; do NOT modify the existing v41 4-input export — Phase 282 fixture must keep passing).
- Storage-slot read for TST-MINTCLN-04 uses `ethers.provider.getStorageAt(contractAddress, slot)` where `slot = keccak256(abi.encode(player, keccak256(abi.encode(rk, baseSlot))))` per Solidity nested-mapping rules; `baseSlot` is the `ticketsOwedPacked` slot index from `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout` (already captured EMPTY-diff at 290-MEASUREMENT.md §2 — index UNCHANGED from v41).

</code_context>

<specifics>
## Specific Ideas

- The "v41 Phase 281 owed-salt multiset" reference in TST-MINTCLN-01 wording is the **algorithmic invariant** (cross-call seed separation), NOT a bit-identical hash output target. Implement the assertion as JS-replay equivalence against the v42 3-input form, augmented by a pairwise-distinct-keccak-input check across multi-call emissions to evidence the invariant continuity.
- Gas measurement is **off the table for Phase 291** — no `console.log`, no hard assertion, no scope expansion. Phase 290 §3 theoretical attestation is the load-bearing reference cited at Phase 297 §3.A.
- Default test filename: `test/edge/MintCleanupRegression.test.js` (planner may choose a different name if a stronger convention emerges; do NOT use `test/mint/` for a single file).
- JSDoc header for TST-MINTCLN-05 should explicitly cite both topic hashes (v41 `0x5e96bf2d...` retired + v42 `0x279edf1c...` new) from 290-MEASUREMENT.md §5 and reference the inherited D-40N-EVT-BREAK-01 posture.

</specifics>

<deferred>
## Deferred Ideas

- **Empirical gas regression bench** — explicitly skipped per D-291-GAS-01; not deferred to a future test phase, not promoted to a v43+ backlog item. Theoretical-first attestation in 290-MEASUREMENT.md §3 is the audit-cite source. If a future indexer regression or migration tooling phase wants empirical gas validation, that is a separate decision under its own anchor.
- **Hard regression assertion against theoretical gas bound (TST-MINTCLN-06 candidate)** — out of scope per D-291-GAS-01.
- **Phase 282 file refactor / helper-extraction** — `test/edge/MintBatchDeterminism.test.js` is a frozen v41-closure artifact; do not refactor in Phase 291. Any duplication of scenario setup (~50 LOC) is acceptable inline; helper-extraction is deferred to a v43+ test-maintenance bundle if it ever becomes load-bearing.

</deferred>

---

*Phase: 291-mintcln-regression-fixture-tst-mintcln*
*Context gathered: 2026-05-17*
