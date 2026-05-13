# Phase 275: Auto-Resolve LootboxModule Bernoulli (LBX-AR) - Context

**Gathered:** 2026-05-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend the v39.0 Phase 274 manual-path Bernoulli round-up to the 2 auto-resolve callers (`resolveLootboxDirect` decimator-claim path + `resolveRedemptionLootbox` sDGNRS-redemption path) of `_resolveLootboxCommon` (`contracts/modules/DegenerusGameLootboxModule.sol`). The auto-resolve branch at `:1062–1069` Bernoulli-collapses scaled `futureTickets` to whole tickets at queue time using `bits[152..167]` of the per-resolution seed — the SAME 16-bit slice the v39 manual-path consumes per D-274-BIT-SLICE-01 — and queues via `_queueTickets(player, level, whole, false)` instead of `_queueTicketsScaled(...)`. Auto-resolve cold-bust is SILENT per D-40N-SILENT-01 (no WWXRP consolation, no `LootBoxWwxrpReward` emit, no `LootboxTicketRoll` emit). Mint-boost path at `DegenerusGameMintModule.sol:1142` UNCHANGED per D-40N-MINTBOOST-OUT-01. The `_resolveLootboxCommon` `index != type(uint48).max` sentinel gate stays in place for this phase (Phase 277 EVT-UNI-05 retires it). Event surface (`LootBoxOpened` / `BurnieLootOpen` / `LootboxTicketRoll`) UNCHANGED in this phase (Phase 277 EVT-UNI consolidates events). Storage layout byte-identical at v40 phase-close HEAD vs v39 baseline `MILESTONE_V39_AT_HEAD_6a7455d1`. Net gas-NEUTRAL after factoring eliminated `_rollRemainder` consumption at trait-assignment time.

Wave shape: 1 USER-APPROVED batched contract commit + 1 USER-APPROVED batched test commit (`feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`).

</domain>

<decisions>
## Implementation Decisions

### Bernoulli Code Shape on `_resolveLootboxCommon`

- **D-275-HOIST-01:** Hoist Bernoulli computation OUTSIDE the `if (index != type(uint48).max)` sentinel gate. Compute `scaledPre` / `whole` / `frac` / `roundedUp` once before the gate; manual branch then handles cold-bust consolation + `LootboxTicketRoll` emit using the shared locals; auto-resolve branch calls `_queueTickets(player, targetLevel, whole, false)` unconditionally (the helper early-returns at `DegenerusGameStorage.sol:568` when `quantity == 0`, so silent cold-bust requires no extra guard).
  - **Why:** Pre-stages Phase 277 EVT-UNI-05 sentinel retirement — when the gate retires, the two branches collapse trivially around the already-shared Bernoulli math. Avoids the duplicate-then-consolidate churn of option A2.
  - **Bytecode posture:** Manual path bytecode shape changes vs v39 (Bernoulli moves out of the manual-only block). The math is unchanged; the EV-neutrality identity from v39 §4 (a) `E[whole_post] = scaledPre / 100` holds verbatim. Storage layout byte-identical per LBX-AR-05. v40 deliberately converges manual + auto-resolve, so this restructuring is on-spec.
  - **Reference shape:** See `discuss-phase` preview snapshot recorded in `275-DISCUSSION-LOG.md`.

- **D-275-NATSPEC-01:** Update the bit-allocation NatSpec at `:891–892` — bits[152..167] now consumed on BOTH manual + auto-resolve paths. Replace the v39 wording ("consumed only on manual paths; auto-resolve paths leave the slice unread") with v40 wording covering both branches.

- **D-275-NOOP-01:** No deletions in this phase. `_queueTicketsScaled` lives in `contracts/storage/DegenerusGameStorage.sol:596` (shared across modules) and continues to be called by `DegenerusGameMintModule.sol:1142` for the mint-boost surface. The LootboxModule auto-resolve call site at `:1068` is the only mutation. Sentinel gate stays for this phase (Phase 277 retires it). Manual-branch consolation + `LootboxTicketRoll` emit stay (Phase 277 EVT-UNI-01 retires `LootboxTicketRoll`).

- **D-275-STATUSQUO-01:** Auto-resolve callers (`resolveLootboxDirect` `:703` + `resolveRedemptionLootbox` `:739`) continue to pass `type(uint48).max` as the `index` arg AND `false` as the `emitLootboxEvent` arg. Phase 277 EVT-UNI-05 retires the sentinel; Phase 277 EVT-UNI-06 decides the auto-resolve `LootBoxOpened` emission shape. This phase touches neither.

### Test Surface (TST-LBX-AR-01..06)

- **D-275-TST-04-01:** TST-LBX-AR-04 seed-uniqueness across 4 upstream callers uses direct-call to `_resolveLootboxCommon` with synthetic seeds matching each caller's keccak shape (`keccak256(abi.encode(rngWord, player, day, amount))`). Per-caller test functions inject distinct rngWord values, assert chi-square independence on `bits[152..167]`. Matches v39 TST-WT precedent. Verifies bit-slice independence, NOT the upstream keccak derivation chain — the per-resolution seed-uniqueness across 4 callers is verified analytically per PROJECT.md v40.0 trace (single-shot per call for callers (a)(b)(c); L1721 redemption-loop evolves rngWord per iteration via `keccak256(abi.encode(rngWord))` at L1769 for caller (d)). Future spike to exercise the full-stack 4-caller flow remains an option if a regression surfaces in adversarial pass at Phase 280.

- **D-275-TST-05-01:** TST-LBX-AR-05 `_rollRemainder` zero-invocation regression uses `ticketsOwedPacked[wk][buyer]` rem-byte snapshot before/after target-queue activation. Open N auto-resolve lootboxes, advance level so target queue activates at trait-assignment, read packed value, assert `uint8(packed) == 0` both pre and post (rem byte stays zero because Bernoulli-collapsed `_queueTickets` never writes the rem field). No test-only contract hook; pure observability via existing storage layout. Strongest signal: directly observes the state change `_rollRemainder` would mutate.

- **D-275-TST-PLACEMENT-01:** Test file placement follows v39 TST-WT precedent — `test/stat/` for TST-LBX-AR-01 (EV-neutrality property) + TST-LBX-AR-04 (chi-square); `test/edge/` for TST-LBX-AR-02 (boundaries 0/1/99/100/101/199/200); `test/unit/` for TST-LBX-AR-03 (silent cold-bust) + TST-LBX-AR-05 (rem-byte snapshot) + TST-LBX-AR-06 (mint-boost regression). Planner finalizes filenames.

### Gas Delta Reporting

- **D-275-GAS-WC-01:** Theoretical worst-case path for the commit-message gas delta is `resolveRedemptionLootbox` single-chunk at peak EV multiplier — single `_resolveLootboxCommon` invocation with maximum scaled `futureTickets` (peak EV multiplier via activity score), far-future target level triggering boon roll + distress bonus + DGNRS path; single Bernoulli sub-roll consumption + single `_queueTickets` whole-ticket write. Per `feedback_gas_worst_case.md`: derive worst case FIRST, then benchmark. Head-to-head comparable with the v39 manual-path `openLootBox` gas number from Phase 274 §3.A. Expected delta: additions (Bernoulli math + branch hoist) offset by removed `_rollRemainder` consumption at trait-assignment time → net-neutral within ±300 gas per resolve. Commit message reports bytecode delta + gas delta against this worst-case path.

### Claude's Discretion

- Exact wording of bit-allocation NatSpec update at `:891–892` (per D-275-NATSPEC-01) — planner finalizes the comment text consistent with v39 style.
- Storage-layout byte-identity proof recipe (`forge inspect storage-layout` diff vs `git show 6a7455d1` artifact) — planner picks the standard mechanic.
- Exact test filenames + function names within the test/unit, test/edge, test/stat placement scheme — planner finalizes consistent with v39 naming conventions.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project + Milestone Anchors
- `.planning/PROJECT.md` — v40.0 milestone definition; D-40N-* decision-anchor IDs (silent-on-cold-bust D-40N-SILENT-01, mint-boost retention D-40N-MINTBOOST-OUT-01, sentinel retirement D-40N-SENTINEL-RETIRE-01, granularity D-40N-GRANULARITY-01); v39.0 closure baseline `MILESTONE_V39_AT_HEAD_6a7455d1`.
- `.planning/ROADMAP.md` §"Phase 275: Auto-Resolve LootboxModule Bernoulli (LBX-AR)" — goal, dependencies, requirements list, success criteria 1–6.
- `.planning/REQUIREMENTS.md` §LBX-AR (LBX-AR-01..06) + §TST-LBX-AR (TST-LBX-AR-01..06) — requirement-level specifications.
- `.planning/MILESTONES.md` §v39.0 — Phase 274 manual-path Bernoulli reference (mirror-the-pattern for auto-resolve).

### v39 Carry Anchors (manual-path baseline)
- `audit/FINDINGS-v39.0.md` §4 (a) — EV-neutrality identity `E[whole_post] = scaledPre / 100` proof carries verbatim to auto-resolve.
- `audit/FINDINGS-v39.0.md` §4 (b) — bit-slice [152..167] pairwise independence via keccak output-entropy carries to auto-resolve seed (per-resolution distinct keccak input).
- v39 decision anchors `D-274-BIT-SLICE-01` (16-bit slice supersession) + `D-274-MANUAL-ONLY-01` (now superseded by this phase) + `D-274-AUTORESOLVE-OUT-01` (now superseded by this phase).

### Contract Files (audit subject)
- `contracts/modules/DegenerusGameLootboxModule.sol:703` — `resolveLootboxDirect` auto-resolve caller (decimator-claim).
- `contracts/modules/DegenerusGameLootboxModule.sol:739` — `resolveRedemptionLootbox` auto-resolve caller (sDGNRS-redemption).
- `contracts/modules/DegenerusGameLootboxModule.sol:905` — `_resolveLootboxCommon` function entry (Bernoulli hoist site per D-275-HOIST-01).
- `contracts/modules/DegenerusGameLootboxModule.sol:1020-1070` — current sentinel-gated branch (manual-path Bernoulli at :1039-1061; auto-resolve `_queueTicketsScaled` at :1068).
- `contracts/modules/DegenerusGameLootboxModule.sol:891-892` — bit-allocation NatSpec (update per D-275-NATSPEC-01).
- `contracts/storage/DegenerusGameStorage.sol:562` — `_queueTickets(quantity)` (auto-resolve branch's new target; early-returns at :568 on `quantity == 0`).
- `contracts/storage/DegenerusGameStorage.sol:596` — `_queueTicketsScaled` (SHARED; stays in place; MintModule still consumes).
- `contracts/modules/DegenerusGameMintModule.sol:1142` — mint-boost `_queueTicketsScaled` consumer; UNCHANGED per D-40N-MINTBOOST-OUT-01 (TST-LBX-AR-06 regression).

### Upstream Auto-Resolve Callers (seed-uniqueness trace)
- `contracts/modules/DecimatorModule.sol:594` — `claimDecimatorJackpot(lvl)` single-shot per call; rngWord from per-level storage.
- `contracts/modules/DegeneretteModule.sol:786` — single-shot per payout call.
- `contracts/modules/StakedDegenerusStonk.sol:672` — single-shot per redemption; entropy = `keccak(rngWord, player)`.
- `contracts/modules/DegenerusGame.sol:1721` — redemption-loop wrapper; `rngWord = keccak256(abi.encode(rngWord))` at L1769 evolves seed per 5-ETH-chunk iteration (caller (d) seed-uniqueness mechanism).

### Feedback / Discipline
- `feedback_no_contract_commits.md` — never commit contracts/ or test/ without explicit user approval.
- `feedback_batch_contract_approval.md` — batch all contract edits, present one diff, one approval at the end.
- `feedback_never_preapprove_contracts.md` — orchestrator must NEVER tell agents contract changes are pre-approved.
- `feedback_manual_review_before_push.md` — final user-review gate on diff before push.
- `feedback_gas_worst_case.md` — derive theoretical worst case FIRST, then benchmark (drives D-275-GAS-WC-01).
- `feedback_design_intent_before_deletion.md` — trace original design intent + actor game-theory BEFORE asking which deletion shape to use (no deletions this phase per D-275-NOOP-01).
- `feedback_test_rnglock.md` — must test rngLocked removal from coinflip claim paths before deploy (not relevant to this phase; ticket queue's `rngLocked` revert path is not touched).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_queueTickets(buyer, targetLevel, quantity, rngBypass)` at `DegenerusGameStorage.sol:562`** — whole-ticket helper with `if (quantity == 0) return;` early-return at `:568` before any event emit or storage write. The silent cold-bust requirement (LBX-AR-03) is satisfied by calling `_queueTickets(player, targetLevel, whole, false)` unconditionally; no extra guard needed.
- **v39 manual-path Bernoulli at `DegenerusGameLootboxModule.sol:1039-1046`** — exact predicate `frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)` carries verbatim to the hoisted form per D-275-HOIST-01.
- **`TICKET_SCALE` constant** — already inlined as `uint32(TICKET_SCALE)` in v39 (compile-time inlined; no storage slot).

### Established Patterns
- **Single-keccak-per-resolution seed-derivation** at `:708` + `:744` — both auto-resolve callers already derive `seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)))` matching the manual-path pattern. Bit allocation per :880-892 NatSpec.
- **Sentinel-gated branching at `:1032`** — `index != type(uint48).max` distinguishes manual vs auto-resolve. Retained this phase; retired Phase 277 EVT-UNI-05.
- **TicketsQueuedScaled emit at `DegenerusGameStorage.sol:605`** — fired by `_queueTicketsScaled`. After this phase, no LootboxModule call site emits it; MintModule:1142 remains the sole emitter.
- **rem-byte at `ticketsOwedPacked` low 8 bits** — `_queueTicketsScaled` writes/accumulates rem; `_queueTickets` never touches it. D-275-TST-05-01 exploits this for the zero-invocation regression.

### Integration Points
- **No new external entry points; no new modifiers; no new admin functions** per LBX-AR-05 (storage layout byte-identical).
- **Only mutation:** `_resolveLootboxCommon` body restructuring (Bernoulli hoist) + auto-resolve branch call-site swap at `:1068` + NatSpec update at `:891-892`.
- **Cross-module byte-identity expected** for JackpotModule + MintModule + Degenerette + TraitUtils + JackpotBucketLib + EntropyLib + DegenerusGameStorage (storage helpers unchanged).

</code_context>

<specifics>
## Specific Ideas

- **A1 hoist preview** (per D-275-HOIST-01) — see `275-DISCUSSION-LOG.md` for the canonical code snapshot of the hoisted shape that planner targets.
- **Worst-case gas benchmark target:** `resolveRedemptionLootbox` single-chunk with peak EV multiplier (activity score = max), far-future target level, scaled `futureTickets` at high boundary (e.g., 9999 from TST-LBX-AR-01 sample span).
- **Chi-square sample size for TST-LBX-AR-04:** ≥10K seeds per caller (matching the ≥10K EV-neutrality sample size from TST-LBX-AR-01 + v39 TST-WT precedent).

</specifics>

<deferred>
## Deferred Ideas

- **Full-stack 4-caller integration test for seed-uniqueness** — option B from the TST-LBX-AR-04 discussion (full-stack exercise through DecimatorModule + DegeneretteModule + sDGNRS + Game:1721 redemption-loop). Deferred per D-275-TST-04-01 in favor of direct-call. Candidate to revisit if adversarial pass at Phase 280 surfaces a redemption-loop-specific concern around L1769 rngWord evolution.
- **`_bernoulliWhole(seed, scaled)` private helper extraction** — option A3 from the code-shape discussion. Deferred in favor of A1 hoist; Phase 277 EVT-UNI-05 will absorb the hoisted shape into a single inlined path anyway, making helper extraction redundant.
- **Sentinel retirement + event surface unification** — Phase 277 EVT-UNI (D-40N-SENTINEL-RETIRE-01 + D-40N-EVT-BREAK-01). Out of scope here.
- **JackpotModule:2216 BAF Bernoulli + `_queueLootboxTickets` wrapper retirement** — Phase 276 JPT-BR + Phase 278 JPT-CLEAN. Independent surface per ROADMAP dependency hints.
- **Mint-boost fractional retirement** — D-40N-MINTBOOST-OUT-01 retains the status quo; mint-boost stays out of v40.0 per user disposition 2026-05-13.

</deferred>

---

*Phase: 275-Auto-Resolve LootboxModule Bernoulli (LBX-AR)*
*Context gathered: 2026-05-13*
