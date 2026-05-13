# Requirements: v39.0 Lootbox Whole-Ticket Rounding + WWXRP Consolation

**Milestone:** v39.0
**Audit baseline:** `MILESTONE_V38_AT_HEAD_06623edb`
**Phase shape:** Single-phase patch (Phase 274 multi-wave) per v36.0 Phase 266 + v38.0 Phase 272 precedent
**Single deliverable:** `audit/FINDINGS-v39.0.md` (terminal phase per D-NN-FCITE-01 carry)

## Out of Scope

- Mint-boost fractional retirement (mint-boost path in `DegenerusGameMintModule._queueTicketsScaled` callsite line 1142 continues to produce fractional `rem` byte writes; lootbox is the only producer being retired in v39.0). Future-milestone consideration.
- `_queueTicketsScaled` / `_rollRemainder` / `rem` byte in `ticketsOwedPacked` deletion — these stay because mint-boost still uses them.
- BAF jackpot `_jackpotTicketRoll` xorshift refactor (v36.0 ENT-05 carry; still out of scope per `272-CONTEXT.md`)
- New storage layout / new admin / new upgrade hooks
- New public/external mutation entry points
- KNOWN-ISSUES.md modifications (default zero-promotion path)
- Game-over thorough hardening
- LBX-02 fixture-coverage gap (RE-DEFERRED-V39+ at v38.0) — explicitly NOT picked up in v39.0; analytical worst-case continues to be load-bearing per Phase 266 GAS-01 + `feedback_gas_worst_case.md`
- Backward-compat shim for `LootBoxOpened.futureTickets` event-semantics change — intentional break per `feedback_no_dead_guards.md` posture

## v39.0 Requirements

### LBX-WT — Whole-Ticket Bernoulli Collapse (Phase 274 Wave 1; contracts/modules/DegenerusGameLootboxModule.sol)

- [ ] **LBX-WT-01**: `_resolveLootboxCommon` keeps the existing scaled-space accumulation across the `amountFirst` and (optional) `amountSecond` branches unchanged. Both branches continue to call `_resolveLootboxRoll` → `_lootboxTicketCount` which still returns `count × TICKET_SCALE`. Distress-mode bonus block (lines ~975-983) continues to compute in scaled space so small bonuses don't truncate to 0. Function `_lootboxTicketCount` UNCHANGED at this milestone (return-value contract preserved).
- [ ] **LBX-WT-02**: At the end of `_resolveLootboxCommon`'s `if (futureTickets != 0)` block, after the distress bonus accumulation, add a single Bernoulli collapse to whole tickets: `uint32 whole = futureTickets / uint32(TICKET_SCALE); uint32 frac = futureTickets % uint32(TICKET_SCALE);` then if `frac != 0 && (uint8(seed >> 152) % uint8(TICKET_SCALE)) < uint8(frac)` increment `whole`. Assign `futureTickets = whole`. EV-neutrality property: `E[whole_post] == futureTickets_pre / 100.00` exactly.
- [ ] **LBX-WT-03**: Replace the `_queueTicketsScaled(player, targetLevel, futureTickets, false)` call inside `if (futureTickets != 0)` with `_queueTickets(player, targetLevel, futureTickets, false)` — the whole-ticket queue helper (storage layer, line 562). The `if (futureTickets != 0)` guard is re-checked AFTER the Bernoulli collapse because the collapse can yield `whole == 0` from a non-zero pre-Bernoulli scaled value (handled by LBX-WX-01).
- [ ] **LBX-WT-04**: Update the bit-allocation NatSpec block in `_resolveLootboxCommon` (lines ~838-847) to add the new sub-roll entry: `bits[152..159] fracRoundUp % 100 (_resolveLootboxCommon ticket whole-collapse)`. Update the total-consumption line: `Total primary-chunk consumption: 160 bits / 256 available.`
- [ ] **LBX-WT-05**: Storage layout byte-identical at v39.0 phase-close HEAD vs v38.0 baseline `06623edb` (storage-slot grep proof). Zero new admin entry points; zero new external mutation entry points; zero new modifiers. `_queueTicketsScaled`, `_rollRemainder`, and the `rem` byte in `ticketsOwedPacked` stay (mint-boost path retains them).

### LBX-WX — WWXRP Consolation for Cold-Bust Ticket-Path Outcomes (Phase 274 Wave 1; contracts/modules/DegenerusGameLootboxModule.sol)

- [ ] **LBX-WX-01**: Add new private constant near line 278 (next to `LOOTBOX_WWXRP_PRIZE`): `uint256 private constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;` — same magnitude as the regular WWXRP-path prize (the booby trigger is much rarer than the 10%-path WWXRP win, so 1:1 magnitude is intentional per user disposition 2026-05-13).
- [ ] **LBX-WX-02**: Inside `_resolveLootboxCommon`'s `if (futureTickets != 0)` block, immediately after the Bernoulli collapse (LBX-WT-02 + LBX-WT-03), add an `else` branch on the post-collapse `if (futureTickets != 0)` check: when `whole == 0` (post-Bernoulli), call `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` and emit `LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)` (reuse existing event signature from regular WWXRP path at line ~1589).
- [ ] **LBX-WX-03**: Consolation trigger predicate verified: fires if-and-only-if `futureTickets > 0` pre-Bernoulli (scaled space) AND `whole == 0` post-Bernoulli. Pre-Bernoulli-zero cases (ticket-path NOT selected; OR ticket-path selected but `_lootboxTicketCount` math truncated to 0 from a degenerate-tiny budget vs high-price target) DO NOT trigger consolation — explicitly excluded per design.
- [ ] **LBX-WX-04**: Event-shape decision: reuse `LootBoxWwxrpReward(player, day, amount, wwxrpAmount)` (same signature as line 1589 regular WWXRP path). UI / indexer distinguishes consolation from regular WWXRP win by absence of `LootBoxOpened.futureTickets > 0` in the same tx. If downstream consumers request a dedicated `LootBoxConsolation` event, easy add post-hoc; not blocking v39.0 close.

### LBX-EVT — Event Semantics Rebase (Phase 274 Wave 1 + Wave 2; backward-incompat break)

- [ ] **LBX-EVT-01**: `LootBoxOpened.futureTickets` semantics shift from scaled (`× TICKET_SCALE`) to whole. No code-site rename needed — variable already named `futureTickets`; only its value-domain shifts post-LBX-WT-02. UI / indexer / test consumers MUST rebase to read whole-tickets. Document the break in commit message + REQUIREMENTS + audit deliverable §3.A.
- [ ] **LBX-EVT-02**: `TicketsQueuedScaled` event NO LONGER emitted from lootbox-path call sites. The `_queueTickets` helper emits `TicketsQueued(buyer, level, qty)` instead. Mint-boost call sites at `DegenerusGameMintModule.sol` line 1142 STILL emit `TicketsQueuedScaled` — split origin tracking by event type.

### TST-WT — Whole-Ticket Unit Tests (Phase 274 Wave 2; test/lootbox/)

- [ ] **TST-WT-01**: Bernoulli-collapse EV-neutrality property test. ≥10,000 seeded draws across a representative span of pre-Bernoulli scaled values (e.g. 47, 99, 100, 147, 250, 1000, 9999). Property: `mean(whole_post) × TICKET_SCALE` within `±0.5%` of pre-Bernoulli scaled value at sample size N.
- [ ] **TST-WT-02**: Boundary tests — pre-Bernoulli scaled values of 0, 1, 99, 100, 101, 199, 200. Confirm: 0 → 0 deterministically (no Bernoulli roll, no consolation eligible because guard not entered); 100 → 100/100 = 1 whole deterministically (no fractional, no Bernoulli); 199 → 1 whole + 99/100 Bernoulli → expected ~1.99 mean.
- [ ] **TST-WT-03**: Bit-slice independence — assert the `bits[152..159]` Bernoulli slice produces values uncorrelated with the 8 other sub-roll consumers in the primary chunk (rangeRoll, near-offset, far-offset, pathRoll, tierRoll, varianceRoll, ticketVariance, boon roll). Single keccak source means a chi-square test over ≥10K seeds suffices.
- [ ] **TST-WT-04**: Event-shape assertion — open a lootbox that resolves on the ticket-path with a guaranteed-whole pre-Bernoulli value; assert `LootBoxOpened.futureTickets` equals the whole-count, NOT the scaled value. (Will catch any consumer-test that hadn't been rebased.)
- [ ] **TST-WT-05**: `_queueTickets` event-emission assertion — confirm `TicketsQueued(buyer, level, qty)` is emitted (not `TicketsQueuedScaled`) when a lootbox resolves on the ticket-path with `whole > 0`.

### TST-WX — WWXRP Consolation Tests (Phase 274 Wave 2; test/lootbox/)

- [ ] **TST-WX-01**: Cold-bust seed-path test — force a seed where `futureTickets` pre-Bernoulli is `> 0` and `< TICKET_SCALE`, and the Bernoulli `bits[152..159] mod 100 >= frac`. Assert: zero `TicketsQueued` event for the lootbox; one `LootBoxWwxrpReward(player, day, amount, 1 ether)` event; `wwxrp.balanceOf(player)` increased by exactly `1 ether`; `LootBoxOpened.futureTickets == 0` (whole-count semantics).
- [ ] **TST-WX-02**: Non-trigger predicate tests — confirm consolation does NOT fire when: (a) ticket-path not selected (pathRoll lands DGNRS / large-BURNIE / regular-WWXRP); (b) ticket-path selected but `_lootboxTicketCount` math truncated to scaled 0 from start; (c) ticket-path selected with `whole >= 1` post-Bernoulli (success case, no consolation).
- [ ] **TST-WX-03**: Consolation magnitude assertion — `LOOTBOX_WWXRP_CONSOLATION == LOOTBOX_WWXRP_PRIZE == 1 ether`. (Defensive — if either constant drifts, this test catches it.)

### TST-REG — Regression Coverage (Phase 274 Wave 2; test/regression/ + test/lootbox/)

- [ ] **TST-REG-01**: `_rollRemainder` and the `rem` byte branch in `processFutureTicketBatch` are NO LONGER entered from lootbox-only player+level queues. Setup: open N lootboxes only (no mint-boost activity) targeting one future level; advance to that level; assert no `_rollRemainder` invocation occurs (or equivalent observable: no `rem != 0` state in `ticketsOwedPacked[wk][player]` for any lootbox-only player at activation time).
- [ ] **TST-REG-02**: Mint-boost fractional path still works — open a mint with `boostBps != 0` that produces a fractional `adjustedQty`; advance to target level; assert `_rollRemainder` fires correctly on the boost-derived remainder. Confirms v39.0 narrowly retires the lootbox producer without breaking mint-boost.
- [ ] **TST-REG-03**: Multi-lootbox cross-ticket-pooling change observable — open multiple lootboxes targeting the same future level for the same player; confirm the variance distribution matches per-lootbox-Bernoulli (slightly higher variance) NOT cross-lootbox-deterministic-accumulation (the v38.0 behavior). EV is identical; variance is the documented tradeoff.
- [ ] **TST-REG-04**: Existing lootbox test suite (`test/lootbox/*.test.js`) rebases all `LootBoxOpened.futureTickets` reads from scaled to whole. Catalog the diff in commit message.

### AUDIT — Delta Audit Terminal (Phase 274 Wave 3; audit/FINDINGS-v39.0.md)

- [ ] **AUDIT-01**: `audit/FINDINGS-v39.0.md` 9-section deliverable per D-NN-FILES-01 carry. Single FINAL READ-only file at v39.0 closure HEAD (`chmod 444` post-closure-flip). 5-Bucket Severity Rubric carry from v38.0.
- [ ] **AUDIT-02**: §3.A row coverage for the 4 Phase 273 BAF-credit-routing pre-shipped commits (`ff929948` + `e9807891` + `e04d3333` + `1eb1ecb5`) — included-since-baseline mutations, zero F-39-NN finding eligible (surface-coverage attestation only). Plus row coverage for Phase 274 Wave 1 contract commit + Wave 2 test commit.
- [ ] **AUDIT-03**: §4 adversarial surfaces enumerated for v39.0 changes: (a) EV-neutrality of Bernoulli collapse vs cross-lootbox accumulation; (b) Bit-slice `[152..159]` independence from other primary-chunk consumers; (c) Consolation trigger predicate cannot fire from non-ticket-path; (d) Storage layout byte-identical; (e) Event-shape break documented + no consumer reads stale scaled values; (f) Phase 273 BAF-routing surface coverage at included-baseline.
- [ ] **AUDIT-04**: 3-skill PARALLEL adversarial pass on finished §4 draft per D-271-ADVERSARIAL-01 carry: `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` spawn. `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Adversarial-log at `phases/274-.../274-01-ADVERSARIAL-LOG.md`; dispositions: zero residual FINDING_CANDIDATE OR explicit RESOLVED_AT_V39 via Wave 1.5 amendment.
- [ ] **AUDIT-05**: KI walkthrough EXC-01..04 RE_VERIFIED at v39 HEAD. Default zero-promotion path per D-272-KI-01 carry. Closure verdict in §6b: `N of N KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_<UNMODIFIED|MODIFIED>`.
- [ ] **AUDIT-06**: Closure signal `MILESTONE_V39_AT_HEAD_<sha>` emitted in §9c. ROADMAP + STATE + MILESTONES + PROJECT closure-flips land atomically post-§9c attestation per D-272-CLOSURE-01 carry.

### REG — LEAN Regression (Phase 274 Wave 3; audit/FINDINGS-v39.0.md §5)

- [ ] **REG-01**: v38.0 closure signal `MILESTONE_V38_AT_HEAD_06623edb` re-verified non-widening at v39 HEAD. Surface set: Degenerette payout + producer; BURNIE coinflip post-Phase-273 BAF routing; Mint module boost path. Byte-identical for surfaces NOT in v39 scope.
- [ ] **REG-02**: v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4...` re-verified non-widening at v39 HEAD. TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identical.
- [ ] **REG-03**: KI envelope re-verifications at v39 HEAD — EXC-01..03 NEGATIVE-scope; EXC-04 NARROWS retained (BAF-jackpot-only; EntropyLib byte-identical).
- [ ] **REG-04**: Prior-finding spot-check sweep across `audit/FINDINGS-v25.0..v38.0.md` for v39-touched function/surface set. Focus: `_resolveLootboxCommon` + `_lootboxTicketCount` + `_queueTickets` + `_queueTicketsScaled` + `_rollRemainder` + `processFutureTicketBatch`.

## Acceptance Criteria

A requirement is **Complete** when:
- Code change landed in v39.0 audit-subject HEAD
- Test coverage exists (where applicable) and passes
- Audit §3.A row written; §4 surface attested SAFE/SAFE_BY_DESIGN/SAFE_BY_STRUCTURAL_CLOSURE
- Adversarial-pass disposition: zero residual FINDING_CANDIDATE (or RESOLVED_AT_V39 with amendment commit reference)

A requirement is **RE-DEFERRED-V40+** when:
- Explicit user disposition + path-of-investigation prose in `audit/FINDINGS-v39.0.md` §9
- Specific carry conditions documented

## Decision Anchors (v39.0)

- **D-274-CLOSURE-01**: Single-phase patch shape; v36.0 Phase 266 + v38.0 Phase 272 precedent
- **D-274-FILES-01**: Single deliverable `audit/FINDINGS-v39.0.md`; D-NN-FILES-01 carry
- **D-274-FCITE-01**: Forward-cite zero-emission at terminal phase; D-271-FCITE-01 carry
- **D-274-KI-01**: Default zero-promotion path; D-272-KI-01 carry
- **D-274-APPROVAL-01**: Per-commit user approval for `contracts/` + `test/` writes; `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md` carry
- **D-274-ADVERSARIAL-01**: 3-skill PARALLEL adversarial spawn on finished §4 draft; D-271-ADVERSARIAL-01 carry
- **D-274-SEV-01**: 5-Bucket Severity Rubric carry from v38.0 / D-08
- **D-274-EVT-BREAK-01**: `LootBoxOpened.futureTickets` scaled→whole semantic break is INTENTIONAL; no backward-compat shim per `feedback_no_dead_guards.md` posture
- **D-274-WX-AMOUNT-01**: `LOOTBOX_WWXRP_CONSOLATION = 1 ether`, magnitude-equal to `LOOTBOX_WWXRP_PRIZE`; user disposition 2026-05-13 (booby trigger is much rarer than the 10%-path WWXRP win, so 1:1 magnitude is intentional)
- **D-274-MINTBOOST-OUT-01**: Mint-boost fractional retirement explicitly OUT OF SCOPE for v39.0; `_queueTicketsScaled` + `_rollRemainder` + `rem` byte stay
- **D-274-LBX02-OUT-01**: LBX-02 fixture-coverage gap NOT picked up in v39.0; remains RE-DEFERRED-V40+ per v38.0 close disposition
- **D-274-BAF273-INCLUDE-01**: Phase 273 BAF-credit-routing pre-shipped commits fold into v39.0 audit baseline as included-since-baseline; surface-coverage attestation only, no requirements reopen
