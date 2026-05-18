# Phase 290 MINTCLN — Design-Intent Trace (MINTCLN-10)

> Per `feedback_design_intent_before_deletion.md`: this trace records the original design intent of every code-shape Phase 290 Plan 02 is about to delete or restructure, BEFORE the contract patch lands. The artifact is the AGENT-COMMITTED pre-patch gate. Plan 02 cannot begin its contract-edit task until this file exists alongside `290-01-MEASUREMENT.md` at the paths in Plan 01 `files_modified`.
>
> History is allowed in THIS file because the trace IS a planning artifact whose purpose is to record historical rationale for v41 → v42 changes. The `feedback_no_history_in_comments.md` rule applies to NatSpec / contract source comments only — it does NOT apply to planning docs.

## Audit Baseline + Anchors

**Audit baseline:** `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (v41.0 closure HEAD). All "v41 close" references in this trace, and all "byte-identical to v41 close" assertions in `290-01-MEASUREMENT.md`, resolve against this SHA.

**Phase 290-scope decision anchors (recorded at user disposition 2026-05-17):**

- **D-42N-MINTCLN-SCOPE-01** — narrow scope. The duplicate-logic between `processFutureTicketBatch` inline loop (mint:421-509) and `processTicketBatch` + `_processOneTicketEntry` split (mint:670-834) is FLAG-ONLY at v42; no helper extraction. Cleanup eligible for v43+ maintenance bundle. Trace original design intent before consolidating per `feedback_design_intent_before_deletion.md` at that future milestone.
- **D-42N-EVT-BREAK-01** — breaking `TraitsGenerated` topic-hash change accepted at v42 under pre-launch posture. Inherits v40 D-40N-EVT-BREAK-01 disposition (same posture, same operational handoff form). Indexer rebuild required; no live indexer impact. Indexer-migration tooling is a forward-handoff cited in `audit/FINDINGS-v42.0.md` §9 "Deferred to Future Milestones" register at Phase 297.

**Carry-forward anchors (load-bearing context):**

- **D-40N-EVT-BREAK-01** (v40 Phase 277 precedent for the same breaking-topic-hash posture; v42 D-42N-EVT-BREAK-01 inherits this disposition verbatim).
- **D-40N-MINTBOOST-OUT-01** (mint-boost retention; `_queueTicketsScaled` + `_rollRemainder` + `rem` byte stay at v42; UNCHANGED by Phase 290).
- **D-281-STARTINDEX-SEMANTICS-01** (v41 Phase 281 anchor being cleaned up by MINTCLN-04 + MINTCLN-06; the field-name `startIndex` was repurposed at Phase 281 to carry `owed_at_call_entry` because the ABI shape was held intact under pre-launch indexer-stability constraints; v42 opens the breaking-topic-hash window so the field-name mismatch disappears).
- **D-281-FIX-SHAPE-01** (v41 Phase 281 owed-salt patch shape; the 6th positional `ownedSalt` arg to `_raritySymbolBatch` is being collapsed by MINTCLN-01 + MINTCLN-02 + MINTCLN-03; the algorithmic invariant carries forward via the owed-in-baseKey shape).

## Section (i) — Original 4-Input Hash Rationale

Per MINTCLN-10(i): trace WHY v41 Phase 281 passed `ownedSalt` as a separate 6th positional arg to `_raritySymbolBatch` (`contracts/modules/DegenerusGameMintModule.sol:544-551`) instead of folding `owed` into `baseKey` low 32 bits at queue-time.

At Phase 281 the constraint set was: (a) resolve the F-41-01 finding (within-day determinism break across multi-call drains on the same `(rk, player)` pair when `owed > writesBudget / 2`); (b) zero new storage slot, zero new SSTORE site, zero new SLOAD site; (c) minimal bytecode delta; (d) minimal audit-story surface (the F-41-01 fix had to be a narrow, F-41-01-anchored patch — not a refactor riding the F-41-01 commit window).

The owed-salt approach satisfied all four constraints with a single delta: add one ABI-encoded `uint32` keccak input at the `_raritySymbolBatch` seed-derivation site (mint:571-573 in v41 close form `keccak256(abi.encode(baseKey, entropyWord, groupIdx, ownedSalt))`). The cost was +1 ABI-encoded 32-byte word per `_raritySymbolBatch` invocation (≈ +30 gas/invocation from the additional keccak word + memory load for the dropped parameter slot). Storage delta was zero; the `ticketsOwedPacked[rk][player]` 40-bit packed layout (rem low 8 + owed next 24 + processed-via-owed-salt high 8) stayed at the same slot offset / type / label.

The alternative considered at Phase 281 — folding `owed` into `baseKey` low 32 bits at queue-time — would have required parallel callsite edits at the two `baseKey` construction sites (mint:423-425 in `processFutureTicketBatch` + mint:800-802 in `_processOneTicketEntry`) plus a corresponding `_raritySymbolBatch` signature change to drop the 6th positional parameter, plus an event-shape decision (the v41 `TraitsGenerated` 6-field shape carried `startIndex` as its 4th positional — which the F-41-01 fix repurposed via D-281-STARTINDEX-SEMANTICS-01 to carry `owed_at_call_entry`). At Phase 281 those edits would have looked like a refactor outside the F-41-01 fix scope — a wider audit-story surface than the F-41-01 finding warranted at the time. Phase 281's narrow-scope discipline (the F-41-01 fix is a within-day determinism patch; not the right phase to take a refactor) was the correct call.

The Phase 281 owed-salt patch was therefore NOT a defect; it was a **constraint-satisfying fix at that phase**. The v42 Phase 290 cleanup (`MINTCLN-01` + `MINTCLN-02` + `MINTCLN-03`) is a post-fix refactor enabled by two new conditions: (1) the breaking-topic-hash window deliberately opened at v42 under D-42N-EVT-BREAK-01 (which Phase 281 deliberately did NOT take per D-281-STARTINDEX-SEMANTICS-01's "ABI shape unchanged; semantic meaning shifts" disposition); (2) accumulated audit-story room at v42's audit-subject delta (the v42 milestone scope is wider than the F-41-01-anchored Phase 281 patch was permitted to span).

At v42 Phase 290, the same algorithmic invariant — cross-call seed separation across multi-call drains on the same `(rk, player)` pair — is preserved via the `baseKey`-carrying-owed shape: when the same outer slot is re-entered with a smaller `owed`, `baseKey` itself now changes between successive `_raritySymbolBatch` invocations because the low 32 bits of `baseKey` carry the current `owed` value. The keccak input set reduces from 4 inputs (`baseKey`, `entropyWord`, `groupIdx`, `ownedSalt`) to 3 inputs (`baseKey`, `entropyWord`, `groupIdx`), but the seed-space size remains 256 bits (`uint256(keccak256(...))`), the uniformity property remains intact (keccak is the same), and cross-call distinctness remains intact (the changing low 32 bits of `baseKey` produce pairwise-distinct keccak inputs across multi-call drains, mirroring the role `ownedSalt` previously played). MINTCLN-08 + MINTCLN-09 attestations at Plan 02 lock the byte-identity of the surrounding storage and ABI to ensure no collateral surface changes ride along.

A cleaner-long-term outcome: (a) `baseKey` is already the canonical per-entry identifier in the event emission, so carrying `owed` inside it consolidates one fewer ad-hoc parameter on the API surface; (b) eliminating the 6th positional arg removes function-signature surface area and reduces calldata at the two callsites (mint:469 + mint:803); (c) the 3-input hash is a structurally simpler audit story (no separate "salt" field whose role is opaque without v41 Phase 281 context).

## Section (ii) — Original `TraitsGenerated` Field-Set Rationale + `startIndex` Naming

Per MINTCLN-10(ii): trace WHY v41 Phase 281 left the `TraitsGenerated` ABI shape intact (6 fields: `player`, `level`, `queueIdx`, `startIndex`, `count`, `entropy` per `contracts/storage/DegenerusGameStorage.sol:484-491` v41 close form) and reassigned the 4th positional field's semantic MEANING (from `processed` to `owed_at_call_entry`) per D-281-STARTINDEX-SEMANTICS-01.

At Phase 281 the field-set constraint set was: (a) preserve the event topic hash for off-chain indexer continuity — even pre-launch, the parsing-callsite stability across consecutive milestones was a desirable property to maintain consistency with the v40 D-40N-EVT-BREAK-01 disposition (v40 took the break; subsequent milestones until a new break-window opened were to inherit the v40-stable topic); (b) minimize the patch surface for the F-41-01 fix scope; (c) the 4-byte function selector for `processFutureTicketBatch(uint24,uint256)` had to stay; (d) the v41 fix had to land as one batched commit with the smallest bytecode delta consistent with closing F-41-01.

Restructuring `TraitsGenerated` to carry `baseKey` as a single `uint256` field (collapsing `level` + `queueIdx` + `startIndex` into the packed `baseKey` 256-bit layout) would have been the natural long-term shape — but that would have broken the topic hash. Phase 281 was not the right moment to take that break: the F-41-01 finding was a **within-day determinism defect**, not an event-shape defect; the audit narrative for that phase required the patch surface to track the finding's locus. Forcing an event-shape break alongside the determinism fix would have entangled two unrelated dispositions in one commit and degraded the audit story.

The Phase 281 mitigation was therefore to keep the ABI shape and reassign the 4th positional field's SEMANTIC MEANING under D-281-STARTINDEX-SEMANTICS-01. The emit sites at mint:474 (`processFutureTicketBatch`) + mint:807 (`_processOneTicketEntry`) write the `owed` value into the field declared as `startIndex` in `DegenerusGameStorage.sol:488` — a deliberate decision that the field's name no longer matches its content, in exchange for parsing-callsite stability and the small-patch property required to close F-41-01 narrowly. The mismatch was DOCUMENTED at Phase 281, not silently introduced.

That field-name mismatch is the side-bug MINTCLN-06 fixes incidentally via the MINTCLN-04 rename. The fix is not a "bug fix" in the defect sense — there is no on-chain behavior to correct; the bytecode produces the documented value at the documented position. It is a cleanup of an intentional Phase-281 trade-off that became unnecessary once the breaking-topic-hash window opened at v42.

At v42 Phase 290 the breaking-topic-hash window is opened deliberately under D-42N-EVT-BREAK-01, so the event field-set is right-sized to the post-cleanup shape: `(address indexed player, uint256 baseKey, uint32 take)` — 3 fields. `baseKey` carries `(lvl << 224) | (queueIdx << 192) | (player << 32) | owed` in its 256-bit layout (per the MINTCLN-02 construction at both callsites); the off-chain indexer-replay invariant from Phase 281 (which needed `(player, lvl, queueIdx, owed_at_call_entry, take, entropy)` reconstructible from each emit to replay the trait multiset) stays load-bearing — the same data is reconstructible from `(player, baseKey, take)` because `baseKey` decodes into all four of `(lvl, queueIdx, player, owed)`. Replay completeness is preserved.

A subtle disposition note: `entropy` is dropped from the event. At v42 the day's entropy is available off-chain via the daily entropy-rotation events (`lootboxRngWordByIndex[]` ladder; emitted by upstream VRF settlement callbacks). Each `TraitsGenerated` emit can be linked to its source entropy word by the day's `lootboxRngWordByIndex[dailyIdx]` value rather than by an inline `entropy` field on every emit. The cleanup recovers ~32 bytes of calldata per emit — material at the deity-pass + far-future drain scale where hundreds of emits can fire in a single multi-call drain.

A second subtle disposition: in the `_processOneTicketEntry` zero-owed → rolled-to-1 branch (mint:775-786), `baseKey` is constructed with `owed == 0` at mint:800-802 BEFORE the `_resolveZeroOwedRemainder` helper (mint:731-757) overwrites `owed` to 1 at the local scope. After the MINTCLN-02 + MINTCLN-03 patch lands, the rebuilt `baseKey` will therefore carry stale `owed == 0` in its low 32 bits during the subsequent `_raritySymbolBatch` call. This is ACCEPTABLE behavior under the algorithmic invariant for the following reasons: (a) only a single-trait emission can follow this branch (the zero-owed→rolled-to-1 path produces exactly one trait); (b) no multi-call drain follows this branch (the next outer-loop iteration consumes a fresh `baseKey`); (c) the upper-bit distinctness of `baseKey` (`lvl`, `queueIdx`, `player`) plus the `groupIdx` argument to `_raritySymbolBatch` (mint:565) fully preserves cross-call seed separation independent of the low-32-bit value; (d) keccak's seed uniformity property is satisfied for any low-32-bit value, including zero. The branch is ROUTED TO PHASE 296 SWEEP-02(i) adversarial re-pass as part of the routine adversarial sweep over MINTCLN — the disposition is recorded here pre-emptively so Phase 296 has a baseline to test against; the expected re-pass outcome is SAFE_BY_STRUCTURAL_CLOSURE. Plan 02 is NOT expected to add a separate `_raritySymbolBatch`-callsite rebuild after the helper return in this branch; doing so would expand MINTCLN scope.

## Section (iii) — Breaking-Topic-Hash Justification + Indexer-Migration Handoff

Per MINTCLN-10(iii): trace WHY the breaking `TraitsGenerated` topic-hash change is acceptable at v42 under D-42N-EVT-BREAK-01.

**Pre-launch posture.** No mainnet contract is active. No live indexer has accumulated parsing rules for the v41 `TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)` topic hash. The post-launch off-chain indexer will be built against the v42 close HEAD topic hash directly. There is no indexer-cost-of-migration to weigh against the cleanup benefit, and there is no historical-event-corpus to backfill — pre-v42 `TraitsGenerated` emissions exist only in test fixtures and audit-baseline harnesses, not in any production state.

**Inheritance from v40 D-40N-EVT-BREAK-01.** v40 Phase 277 took an equivalent breaking event-shape change under the same pre-launch posture. The v40 precedent stands as the operational template for the v42 break: same disposition (breaking-topic-hash accepted pre-launch); same handoff form (cite the migration as a forward-handoff in the terminal audit deliverable's "Deferred to Future Milestones" register, NOT as an open finding); same audit-story posture (record the canonical-form signature strings both pre- and post-break in the measurement scaffold so the breaking-change attestation is structural and auditable). The v42 D-42N-EVT-BREAK-01 anchor inherits the v40 D-40N-EVT-BREAK-01 disposition verbatim with one delta: the v42 break affects only `TraitsGenerated`, while v40's break affected the v40-scope event surface. `TicketsCredited` + `TicketsQueued` + all other event topic hashes in the audit surface are UNCHANGED at v42 close HEAD (locked by MINTCLN-09).

**Indexer-migration tooling is OUT OF SCOPE at v42** per the REQUIREMENTS.md `## Out of Scope` register: "the breaking `TraitsGenerated` topic-hash requires off-chain indexer rebuild; v42.0 deliverable cites this as an indexer-migration handoff per D-42N-EVT-BREAK-01 (mirrors v40 D-40N-EVT-BREAK-01 posture) but does NOT produce migration tooling." The handoff is registered in `audit/FINDINGS-v42.0.md` §9 "Deferred to Future Milestones" at Phase 297 (AUDIT-09 — forward-cite zero-emission discipline maintained via descriptive label + anchor ID `D-42N-EVT-BREAK-01`, not a future-milestone numeric reference).

**Indexer-migration steps the post-launch tooling will need to take** (documented here so the Phase 297 §9 handoff register has a self-contained context for the migrator):

1. Re-deploy the event-listener schema with the new 3-field `TraitsGenerated(address,uint256,uint32)` signature. The two indexed fields collapse from `(address indexed player, uint24 indexed level)` to a single `(address indexed player)` indexed field; the post-break event has one indexed topic + `(uint256 baseKey, uint32 take)` in the data payload.
2. Backfill any historical `TraitsGenerated` emissions if pre-v42 emissions need to be parsed. None are expected pre-launch; if any exist (test-harness traces or staging environments), backfill via the v41 topic-hash parser, then mark those records as "v41 schema" in the indexer storage.
3. Recompute the post-break topic hash via `cast keccak "TraitsGenerated(address,uint256,uint32)"` and pin it in the indexer config. The pre-break topic hash `cast keccak "TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)"` should be retained in a "deprecated topics" map for any pre-launch historical-emission reads.

The migration is a routine indexer-schema rebuild — not a state-recovery operation. The pre-launch posture removes all the difficult parts (no live state to preserve; no concurrent event consumers to coordinate with; no historical-corpus integrity requirement).

## Decision Anchors

- **D-42N-MINTCLN-SCOPE-01** — narrow scope; helper-extraction deferred to v43+; duplicate-logic (`processFutureTicketBatch` inline loop mint:421-509 vs `processTicketBatch` + `_processOneTicketEntry` split mint:670-834) flagged-only at v42 with `processed += take` vs `processed += writesUsed >> 1` asymmetry flagged but NOT touched. User disposition 2026-05-17.
- **D-42N-EVT-BREAK-01** — breaking `TraitsGenerated` topic-hash accepted under pre-launch posture; indexer migration inherits v40 D-40N-EVT-BREAK-01 disposition; tooling is a forward-handoff in `audit/FINDINGS-v42.0.md` §9 at Phase 297. User disposition 2026-05-17.

## Out-of-Scope Register (NOT touched by Phase 290 per REQUIREMENTS.md `## Out of Scope`)

(a) **Helper-extraction** (`processFutureTicketBatch` inline loop mint:421-509 vs `processTicketBatch` + `_processOneTicketEntry` split mint:670-834 parallel-emit / parallel-hash duplication) — out-of-scope per D-42N-MINTCLN-SCOPE-01 (user disposition 2026-05-17); not addressed by Plan 02. Cleanup eligible for v43+ maintenance bundle.

(b) **`processed += take` (mint:499) vs `processed += writesUsed >> 1` (mint:714) asymmetry** — out-of-scope per D-42N-MINTCLN-SCOPE-01 (user disposition 2026-05-17, flagged-only); not addressed by Plan 02. The asymmetry reflects the two callsites' different `writesUsed` semantics (inline path tracks `take` directly; split path receives `writesUsed` from `_processOneTicketEntry` and reconstructs progress via `>> 1`). A v43+ helper-extraction would naturally normalize the two; v42 leaves the inconsistency in place.

(c) **Storage-layout changes** — `ticketsOwedPacked[rk][player]` 40-bit packed form (rem low 8 + owed next 24 + processed-via-owed-salt high 8) UNCHANGED; zero new storage slots; zero new mappings; zero new SSTORE / SLOAD sites in MINTCLN scope. Per MINTCLN-08, REQUIREMENTS.md `## Out of Scope`, and the storage-byte-identity proof Plan 02 produces. Not addressed by Plan 02 beyond locking the existing layout.

(d) **Indexer-rebuild tooling** — pre-launch handoff per D-42N-EVT-BREAK-01; not produced by Phase 290. v42.0 deliverable cites the migration as a forward-handoff at Phase 297 (AUDIT-09 §9). Not addressed by Plan 02.

(e) **Mint-boost fractional retirement** — `_queueTicketsScaled` + `_rollRemainder` (mint:646-658) + `rem` byte stay at v42 per D-40N-MINTBOOST-OUT-01 v41-carry. Deterministic dust accumulator; not RNG-driven; out of v42.0 scope. The `_rollRemainder` callsites at mint:443 + mint:489 (`processFutureTicketBatch` branches) + mint:746 (`_resolveZeroOwedRemainder`) + mint:824 (`_processOneTicketEntry` post-take branch) continue to read through `EntropyLib.hash2(entropy, rollSalt|baseKey, rem)`; the MINTCLN-05 collapse of `rollSalt` to `baseKey` (where the two locals are constructed identically at mint:771-773 and mint:800-802) is a local-name cleanup with zero distribution impact — `_rollRemainder` continues to hash through `EntropyLib.hash2` with the post-MINTCLN `baseKey`-carrying-owed value.

(f) **`TicketsCredited` + `TicketsQueued` event topic-hash changes** — UNCHANGED at v42 close HEAD; only `TraitsGenerated` topic hash changes per MINTCLN-04. Locked by MINTCLN-09. Not addressed by Plan 02 beyond the byte-identity attestation in `290-01-MEASUREMENT.md` §(5).

## SWEEP-02(i) MINTCLN Adversarial-Hypothesis Pre-Emptive Answers

(Pre-emptive answers seed the Phase 296 SWEEP-02(i) baseline. Phase 296 tests these dispositions adversarially; the answers below establish what the adversarial pass should expect to find — and what it should NOT find.)

**Hypothesis 1: Does the 3-input hash re-introduce a different determinism break?**

NO. The cross-call seed separation property at v41 Phase 281 was: under multi-call drains on the same `(rk, player)` pair, the per-batch seed must be pairwise-distinct across batches. At Phase 281 this was achieved by mixing `ownedSalt` into the keccak input — `ownedSalt` carried the at-call-entry `owed` value, which shrinks per emit (`remainingOwed = owed - take` at mint:486 + mint:821), so the 4 keccak inputs were pairwise-distinct across batches. At v42 Phase 290, the same property is achieved by carrying `owed` in `baseKey` low 32 bits (per MINTCLN-02). When the outer loop re-enters the same `(rk, player)` slot with a smaller `owed`, `baseKey` low 32 bits change correspondingly, and the 3 keccak inputs (`baseKey`, `entropyWord`, `groupIdx`) become pairwise-distinct across batches by the same mechanism. Determinism property preserved; algorithmic invariant identical. The expected Phase 296 SWEEP-02(i) finding: SAFE_BY_STRUCTURAL_CLOSURE.

**Hypothesis 2: Does `owed` packed into `baseKey` open any new griefing on shape collision?**

NO. The `baseKey` layout post-MINTCLN-02 is `(lvl << 224) | (queueIdx << 192) | (player << 32) | owed`. The bit ranges are non-overlapping (lvl occupies bits 224-255, queueIdx occupies bits 192-223, player occupies bits 32-191, owed occupies bits 0-31). For two distinct (lvl, queueIdx, player, owed) tuples to collide on `baseKey`, two of the four components would have to differ in a way that produces identical 256-bit packed output — mathematically impossible given the non-overlapping bit-range layout. `queueIdx` is bounded by `uint256` at the callsites (mint:424 + mint:801) but in practice fits in 32 bits (`ticketCursor` is `uint32`); even if `queueIdx` grew beyond 32 bits, the layout reserves bits 192-223 (32 bits) for it and would alias only if `queueIdx >= 2^32`, which is bounded by `ticketQueue[rk].length` and the writes-budget per call — well below `2^32`. No new griefing surface. The expected Phase 296 SWEEP-02(i) finding: SAFE_BY_DESIGN.

**Hypothesis 3: Does the breaking topic-hash on `TraitsGenerated` create a parsing-ambiguity vector for any caller decoding the event?**

NO. The v41 topic-hash and v42 topic-hash are derived from distinct canonical signatures (`TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)` vs `TraitsGenerated(address,uint256,uint32)`); they keccak to different 32-byte topic-0 values. An off-chain decoder that listens for the v41 topic hash will NOT match the v42 emission (different topic-0 → no parse attempt). A decoder that listens for the v42 topic hash will not match v41 emissions either. There is no ambiguity vector — the topic hashes are mutually exclusive. The migration story is "rebuild the indexer schema against the v42 signature", not "handle both signatures simultaneously" — the pre-launch posture removes the dual-listener requirement. The expected Phase 296 SWEEP-02(i) finding: SAFE_BY_DESIGN. Indexer-migration handoff lives in §9 Deferred register, not in the audit findings body.

## Plan-02 Pre-Patch Gate

Plan 02 (`290-02-PLAN.md`) cannot begin its contract-edit task (Task 2 contract patch) until BOTH `290-01-DESIGN-INTENT-TRACE.md` (this file) AND `290-01-MEASUREMENT.md` exist at the paths in Plan 01 `files_modified`. This is the design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md`. Plan 02's first task reads both artifacts and copies forward the decision anchors + measurement framework into the batched commit message body. Plan 02 is the user-approval gate for the contract changes; Plan 01 is AGENT-COMMITTED (planning artifacts only; zero contract / test edits per `feedback_no_contract_commits.md`).

## Sister-Plan Coverage Map

| Requirement | Phase 290 Plan | Disposition |
|-------------|----------------|-------------|
| MINTCLN-01 (3-input hash) | Plan 02 | Contract patch (`_raritySymbolBatch` signature + body) |
| MINTCLN-02 (`baseKey` ORs in `owed`) | Plan 02 | Contract patch (B2-symmetric at mint:423-425 + mint:800-802) |
| MINTCLN-03 (`_raritySymbolBatch` callsites drop arg) | Plan 02 | Contract patch (mint:469 + mint:803) |
| MINTCLN-04 (`TraitsGenerated` 3-field shape) | Plan 02 | Contract patch (storage event decl + both emit sites) — BREAKING topic-hash per D-42N-EVT-BREAK-01 |
| MINTCLN-05 (`rollSalt` collapse) | Plan 02 | Contract patch (`_processOneTicketEntry` local cleanup) |
| MINTCLN-06 (side-bug — `startIndex` field-name mismatch) | Plan 02 | Resolved incidentally by MINTCLN-04 rename |
| MINTCLN-07 (`_raritySymbolBatch` docstring rewrite per `feedback_no_history_in_comments.md`) | Plan 02 | Contract patch (mint:534-543 NatSpec) |
| MINTCLN-08 (storage byte-identity attestation) | Plan 02 | Measurement scaffold §(2) populated post-patch |
| MINTCLN-09 (public ABI byte-identity attestation) | Plan 02 | Measurement scaffold §(4) + §(5) populated post-patch |
| MINTCLN-10 (decision anchors + design-intent trace pre-patch gate) | **Plan 01 (this file)** + `290-01-MEASUREMENT.md` | AGENT-COMMITTED |

## Source Citations

All line-number references in this trace resolve against the live v42.0 HEAD at the time of trace authorship (audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`). Per-file anchors:

- `contracts/modules/DegenerusGameMintModule.sol`:
  - L385-L532 — `processFutureTicketBatch` (B2-symmetric callsite A; `baseKey` at L423-L425; `_raritySymbolBatch` callsite at L469; `TraitsGenerated` emit at L470-L477; `_rollRemainder` callsites at L443 + L489)
  - L534-L643 — `_raritySymbolBatch` (NatSpec at L534-L543; signature at L544-L551; seed-derivation at L571-L573)
  - L646-L658 — `_rollRemainder` (UNCHANGED by Phase 290)
  - L670-L728 — `processTicketBatch` (UNCHANGED by Phase 290 modulo MINTCLN-04 emit shape via `_processOneTicketEntry`; `processed += writesUsed >> 1` asymmetry at L714)
  - L731-L757 — `_resolveZeroOwedRemainder` (UNCHANGED by Phase 290; `_rollRemainder` callsite at L746)
  - L760-L834 — `_processOneTicketEntry` (B2-symmetric callsite B; `rollSalt` at L771-L773 → MINTCLN-05 collapse; `baseKey` at L800-L802; `_raritySymbolBatch` callsite at L803; `TraitsGenerated` emit at L804-L811; `_rollRemainder` callsite at L824)
- `contracts/storage/DegenerusGameStorage.sol`:
  - L484-L491 — `TraitsGenerated` event declaration (6-field shape pre-MINTCLN; → 3-field shape post-MINTCLN-04)
  - L494-L498 — `TicketsQueued` event declaration (UNCHANGED by Phase 290)
