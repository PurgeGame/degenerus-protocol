# Phase 274: Lootbox Whole-Ticket Rounding + WWXRP Consolation - Context

**Gathered:** 2026-05-13
**Status:** Ready for planning
**Source:** Direct conversation 2026-05-13 (user-driven scope refinement)

<domain>
## Phase Boundary

**In scope (`contracts/modules/DegenerusGameLootboxModule.sol`):**
- `_resolveLootboxCommon` function — add `uint48 index` parameter and behavioral split between manual lootbox opens (Bernoulli collapse + whole-ticket queue + consolation + `LootboxTicketRoll` event) and auto-resolve paths (status quo)
- 4 callers updated: `openLootBox` (manual), `openBurnieLootBox` (manual), `resolveLootboxDirect` (auto-resolve), `resolveRedemptionLootbox` (auto-resolve)
- New private constant `LOOTBOX_WWXRP_CONSOLATION = 1 ether`
- New event `LootboxTicketRoll(address indexed player, uint48 indexed lootboxIndex, uint32 preRollTickets, bool roundedUp)` declared on `IDegenerusGameLootboxModule` interface AND at the LootboxModule contract event block
- Bit-allocation NatSpec update for `bits[152..159]`

**Out of scope (per user disposition 2026-05-13):**
- Auto-resolve lootbox paths: `resolveLootboxDirect` (decimator-claim) + `resolveRedemptionLootbox` (sDGNRS-redemption) explicitly UNCHANGED — continue `_queueTicketsScaled` queuing, status-quo event emission, `_rollRemainder`-on-activation
- Mint-boost fractional retirement (`DegenerusGameMintModule.sol` line 1142)
- Jackpot ticket-award sites (`DegenerusGameJackpotModule.sol` lines 702 / 835 / 1005 / 2216) — deferred to v40.0+ alongside the deferred v36.0 ENT-05 BAF xorshift refactor
- LBX-02 fixture-coverage gap (RE-DEFERRED-V40+)
- New storage layout / new admin / new upgrade hooks / new public mutation entry points
- KNOWN-ISSUES.md modifications
- `_queueTicketsScaled` + `_rollRemainder` + `rem` byte deletion (mint-boost + auto-resolve still use them)
</domain>

<locked_decisions>
The following decisions are LOCKED — the planner MUST honor them without re-deliberation.

### D-274-MANUAL-ONLY-01 — Scope: manual lootbox opens only

**Decision:** New behavior (Bernoulli collapse + WWXRP consolation + `LootboxTicketRoll` event) applies ONLY to `openLootBox` + `openBurnieLootBox`. Auto-resolve callers (`resolveLootboxDirect` decimator-claim + `resolveRedemptionLootbox` sDGNRS-redemption) explicitly UNCHANGED.

**Rationale:** User disposition 2026-05-13 ("don't worry about anything but the manual lootbox opens for now"). Auto-resolve paths are low-volume and not user-initiated; keeping them on status-quo flow minimizes blast radius and preserves the option to consolidate them in a future milestone.

**Implementation:** Gating discriminator inside `_resolveLootboxCommon` is `index != type(uint48).max`. Manual callers pass real index; auto-resolve callers pass `type(uint48).max`.

### D-274-NO-EVT-BREAK-01 — No breaking event changes

**Decision:** `LootBoxOpened.futureTickets`, `BurnieLootOpen.tickets`, `TicketsQueuedScaled` event field semantics UNCHANGED. The whole-ticket information is exposed purely through the new additive `LootboxTicketRoll` event.

**Rationale:** Supersedes the earlier v39.0 draft "intentional scaled→whole break" position. The narrower manual-only scope makes a breaking change unnecessary; the new event is purely additive and UI/indexer consumers opt in for remainder visibility without rebasing existing reads.

**Implementation:** `LootBoxOpened.futureTickets` emits the scaled post-distress `futureTickets` value on both paths (identical to v38.0 behavior). On manual paths, that value equals `LootboxTicketRoll.preRollTickets` for the same tx.

### D-274-EVT-ROLL-01 — `LootboxTicketRoll` event signature (minimal 4-field schema)

**Decision:** Event signature: `event LootboxTicketRoll(address indexed player, uint48 indexed lootboxIndex, uint32 preRollTickets, bool roundedUp);`

**Rationale:** User disposition 2026-05-13 selected the minimal 4-field schema over a richer "ticketsWhole + consolationPaid" variant. `whole-tickets-awarded` and `consolationPaid` are CONSUMER-DERIVED from `preRollTickets / 100 + (roundedUp ? 1 : 0)` and same-tx `LootBoxWwxrpReward` corroboration.

**Implementation:** Declared on `IDegenerusGameLootboxModule` interface AND at the LootboxModule contract event block. Both `player` and `lootboxIndex` indexed for filter efficiency.

### D-274-EVT-INDEX-SENTINEL-01 — Sentinel value `type(uint48).max`

**Decision:** `type(uint48).max` (= `0xFFFFFFFFFFFF`) is the sentinel value passed by auto-resolve callers into `_resolveLootboxCommon`. Dual-purpose: (a) identifies the path for behavioral gating; (b) auto-resolve paths never emit `LootboxTicketRoll`, so the sentinel never appears as an emitted `lootboxIndex`.

**Rationale:** User disposition 2026-05-13 selected `type(uint48).max` over `0` to remove the "is index 0 ever real?" verification step from the phase plan. Top-of-domain sentinel cannot collide with any realistic real lootbox index (~281 trillion lifetime lootboxes would be required to reach it).

### D-274-WX-AMOUNT-01 — Consolation magnitude `1 ether`

**Decision:** `uint256 private constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;` — magnitude-equal to existing `LOOTBOX_WWXRP_PRIZE`.

**Rationale:** User disposition 2026-05-13. Booby trigger is much rarer than the 10%-path WWXRP win, so 1:1 magnitude is acceptable; no per-magnitude variant ramping needed.

### D-274-BIT-SLICE-01 — Bernoulli entropy bits[152..159]

**Decision:** Round-up Bernoulli reads `uint8(seed >> 152) % TICKET_SCALE` and compares against `uint8(frac)`. Consumes `bits[152..159]` of the per-resolution seed.

**Rationale:** Previously-unallocated slice (primary chunk consumed 152/256 bits across 8 existing sub-roll consumers per the bit-allocation NatSpec). Bit 152-159 is 8 bits = mod 100 with ~0.39% bias (acceptable, matches the near-offset slice precedent).

**Implementation:** Update bit-allocation NatSpec in `_resolveLootboxCommon` (~lines 838-847) to add the new entry; update total-consumption line to 160/256.

### D-274-CLOSURE-01 — Single-phase shape, multi-wave structure

**Decision:** Phase 274 is the SOLE phase of v39.0. Multi-wave structure: Wave 1 contract commit, Wave 2 test commit, Wave 3+ audit deliverable + closure flips.

**Rationale:** Mirrors v36.0 Phase 266 + v38.0 Phase 272 precedent. Single-phase milestone minimizes overhead; multi-wave structure groups changes by approval gate.

### D-274-APPROVAL-01 — Per-commit user approval

**Decision:** Both Wave 1 (contract commit) and Wave 2 (test commit) require explicit USER approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`.

**Implementation:** Single batched contract commit at end of Wave 1 (all contract changes presented together); single batched test commit at end of Wave 2.

### D-274-ADVERSARIAL-01 — 3-skill PARALLEL adversarial pass

**Decision:** Adversarial pass uses `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` spawned PARALLEL on the finished §4 draft. `/degen-skeptic` OUT OF SCOPE.

**Rationale:** Carry from D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-02 (last 3 milestones used this exact composition).

### D-274-JACKPOT-OUT-01 — Jackpot sites deferred

**Decision:** Jackpot ticket-award sites (`DegenerusGameJackpotModule.sol` lines 702 / 835 / 1005 / 2216) OUT OF SCOPE for v39.0. Cosmetic `× TICKET_SCALE` cleanup in `JackpotTicketWin` emissions deferred to v40.0+ alongside the deferred v36.0 ENT-05 BAF xorshift refactor.

**Rationale:** User disposition 2026-05-13 ("don't worry about anything but the manual lootbox opens for now"). Confirmed the inter-milestone separation between manual lootbox surgery and jackpot surgery.
</locked_decisions>

<deferred_items>
- LBX-02 fixture-coverage gap → RE-DEFERRED-V40+ (carry from v38.0 close per `audit/FINDINGS-v38.0.md` §9.NN.iv)
- Jackpot cosmetic + BAF Bernoulli + v36.0 ENT-05 xorshift refactor → v40.0+ bundle
- Mint-boost fractional retirement → future-milestone consideration (mint-boost is the remaining producer of `rem` byte residues after v39.0)
- Auto-resolve lootbox fractional retirement (`resolveLootboxDirect` + `resolveRedemptionLootbox`) → future-milestone consideration (low-volume; would be the second-to-last producer of `rem` byte residues if pursued)
</deferred_items>

<canonical_refs>
- `.planning/REQUIREMENTS.md` — 39 requirements across 7 categories (LBX-WT, LBX-WX, LBX-EVT, TST-WT, TST-WX, TST-REG, AUDIT, REG) + 14 decision anchors
- `.planning/ROADMAP.md` Phase 274 detail section (Success Criteria 1-18)
- `.planning/PROJECT.md` — v39.0 Current Milestone block (target features + constraints)
- `contracts/modules/DegenerusGameLootboxModule.sol` — primary change site (`_resolveLootboxCommon` ~line 860, ticket-path queue ~line 984, bit-allocation NatSpec ~lines 838-847, callers at lines 526 / 606 / 668 / 703)
- `contracts/interfaces/IDegenerusGameLootboxModule.sol` — event declaration for `LootboxTicketRoll`
- `contracts/storage/DegenerusGameStorage.sol` — `_queueTickets` line 562 (whole), `_queueTicketsScaled` line 596 (scaled), `TICKET_SCALE` constant line 165, `TICKET_FAR_FUTURE_BIT` line 195
- `audit/FINDINGS-v38.0.md` (v38.0 closure baseline; READ-only at `06623edb`)
- v37.0 carry: `feedback_no_dead_guards.md`, `feedback_no_history_in_comments.md`, `feedback_design_intent_before_deletion.md`, `feedback_batch_contract_approval.md`, `feedback_no_contract_commits.md`, `feedback_never_preapprove_contracts.md`, `feedback_manual_review_before_push.md`, `feedback_skip_research_test_phases.md`, `feedback_gas_worst_case.md`
- Phase 273 (`273-baf-credit-routing-fix/`) — pre-shipped maintenance; included-since-baseline in v39.0 delta audit; commits `ff929948` + `e9807891` + `e04d3333` + `1eb1ecb5`
</canonical_refs>

<claudes_discretion>
The planner has discretion on:
- Exact ordering of contract-side edits within Wave 1 (the single batched commit groups all of them anyway)
- Test file organization within Wave 2 — single new file vs splitting across existing `test/lootbox/` files vs new `test/edge/` files
- Whether to use HardHat fixtures or Foundry fuzz for the EV-neutrality property test (TST-WT-01); planner picks the better fit for the codebase's existing test infrastructure
- Whether to use a deployed mock or directly-invoked internal-function fixture for forcing specific seed values in the cold-bust test (TST-WX-01)
- Specific assertion granularity (e.g., balanced topic-filter assertions vs full event-match assertions) in `LootboxTicketRoll` tests
- Wave 3 sub-task decomposition for the audit deliverable (§-by-§ atomic writes vs full-file rewrite)
- Whether to spawn `/gas-audit` orchestrator opportunistically during Wave 1 (lootbox path is being touched, so opportunistic cleanup is in-scope IF candidates surface; otherwise skip per `feedback_no_dead_guards.md` "don't waste gas on dead branches" posture)
</claudes_discretion>

<success_definition>
Phase 274 is COMPLETE when all 18 Success Criteria from ROADMAP.md detail section are TRUE at v39.0 closure HEAD. Specifically:
1. `_resolveLootboxCommon` signature + 4 callers updated correctly
2. Manual-branch Bernoulli collapse implemented with EV-neutrality
3. Manual branch routes through `_queueTickets`; auto-resolve through `_queueTicketsScaled`
4. WWXRP consolation predicate fires correctly
5. `LootboxTicketRoll` declared + emitted (manual paths only)
6. No breaking event changes
7. Bit-allocation NatSpec updated
8. Storage layout byte-identical
9-11. Test coverage (TST-WT, TST-WX, TST-REG)
12. USER-approved commits land
13-17. Audit deliverable (FINDINGS-v39.0.md) + adversarial pass + KI walkthrough + closure signal
18. LEAN regression non-widening

**Closure signal:** `MILESTONE_V39_AT_HEAD_<sha>` emitted in §9c of `audit/FINDINGS-v39.0.md`.
</success_definition>
