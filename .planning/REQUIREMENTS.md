# Requirements: Degenerus Protocol — Audit Repository

**Defined:** 2026-05-19
**Milestone:** v44.0 sStonk Per-Day Redemption Refactor + Accounting Invariant Proof
**Posture:** USER-APPROVED contract change per `feedback_batch_contract_approval.md`; AGENT-COMMITTED test/planning per `D-43N-TEST-COMMITS-AUTO-01` lineage
**Audit baseline:** v43.0 closure HEAD `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`
**Load-bearing input:** `audit/FINDINGS-v43.0.md` §9d HANDOFF-111..117 + FIXREC §103 V-184 mechanic
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

---

## v44.0 Goal (precise statement)

The sStonk gambling-burn redemption flow at `contracts/StakedDegenerusStonk.sol` must satisfy **12 formal accounting invariants** under **all** burn/advance/claim/gameOver timing combinations. The V-184 catastrophic cross-day re-roll exploit and its 6 subsumed catalog rows (V-186/V-188/V-190/V-191/V-192/V-193) must be **structurally eliminated** — not patched. The fix replaces the single-pool `redemptionPeriodIndex` design with per-day keyed `pendingByDay[uint32]` storage matching the protocol's existing per-id commitment pattern used in lootbox + coinflip flows. Every accounting invariant must be **provable** via Foundry invariant testing across random action sequences. Every enumerated edge case must be tested with both positive (correct behavior under the case) and negative (any manipulation attempt reverts or produces no exploit) assertions.

**Non-negotiable closure verdict at v44.0 TERMINAL:** `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44; 12 of 12 INVARIANTS PROVEN; 18 of 18 EDGE_CASES TESTED; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`.

---

## v44.0 Requirements

### Invariants (INV) — Formal Accounting Properties

> Each INV-NN becomes a Foundry `invariant_*` function in `test/invariant/RedemptionAccounting.t.sol` asserted across random action sequences drawn from a stateful handler exercising burn/advance/claim/gameOver/transfer.

- [ ] **INV-01**: For every day D with `redemptionPeriods[D].roll != 0`, the value is written exactly once and never mutated by any subsequent state transition (`advanceGame`, `burn`, `claim`, `gameOver`, admin path). Provable via storage-write hook + invariant assertion.
- [ ] **INV-02**: ETH conservation — at every reachable state: `address(this).balance + steth.balanceOf(address(this)) + claimableWinnings(address(this)) == pendingRedemptionEthValue + (ETH paid out via claimRedemption() + non-gambling burns)` modulo dust from `(ethBase * roll) / 100` integer division (per-period dust bounded by 99 wei).
- [ ] **INV-03**: BURNIE conservation — `coin.balanceOf(address(this)) + coinflip.previewClaimCoinflips(address(this)) - pendingRedemptionBurnie == BURNIE available for new burns`. Reservation released at resolve (not claim) per existing semantics.
- [ ] **INV-04**: Per-day base correctness — for every day D where `pendingByDay[D].ethBase != 0` AND `redemptionPeriods[D].roll == 0` (unresolved): `pendingByDay[D].ethBase == sum over all (player, D) of pendingRedemptions[player][D].ethValueOwed`.
- [ ] **INV-05**: Per-day cumulative correctness — `pendingRedemptionEthValue == sum over unresolved days D of pendingByDay[D].ethBase + sum over resolved-but-unclaimed days D of (sum over unclaimed players of pendingRedemptions[player][D].ethValueOwed * redemptionPeriods[D].roll / 100)`.
- [ ] **INV-06**: No cross-player roll manipulation — for any player P and day D where P has a claim, `redemptionPeriods[D].roll` is a deterministic function of day-D+1's VRF word only; no action by any non-EXEMPT actor (other player burn, claim, admin, transfer, approve, etc.) between P's burn and P's claim can alter `redemptionPeriods[D].roll`.
- [ ] **INV-07**: No self-roll manipulation via timing — for any player P with `pendingRedemptions[P][D].ethValueOwed = X` set at time T, the value X is byte-identical at every later time until P calls `claimRedemption(D)`. No P or non-P action can retroactively modify P's locked `ethValueOwed`.
- [ ] **INV-08**: Pre-advance-gap burn safety — for any burn occurring at time T where `currentDayView() == D` AND day-D's advance has not yet fired, the burn lands in `pendingByDay[D]`. Day-D's advance reads `pendingByDay[dayToResolve = D-1]` only and does not read or write `pendingByDay[D]`. The cumulative `pendingRedemptionEthValue` correctly reflects both pools simultaneously.
- [ ] **INV-09**: Skipped-advance recovery — if advances for days D+1, D+2, ..., D+k are skipped and eventually fire in sequence, each advance resolves the next-oldest unresolved day (oldest-first ordering). No pending day's pool is bypassed; no overwrite occurs.
- [ ] **INV-10**: Per-day supply cap — for every day D, total burned in day D never exceeds `pendingByDay[D].supplySnapshot / 2`. Snapshot taken on first burn of day D, immutable for the rest of day D.
- [ ] **INV-11**: Per-(player, day) EV cap — for every (player P, day D), `pendingRedemptions[P][D].ethValueOwed <= MAX_DAILY_REDEMPTION_EV` (160 ETH). Cap resets per new day.
- [ ] **INV-12**: gameOver mid-pending safety — if `gameOver` becomes true while `pendingByDay[D].ethBase != 0` for some D, the eventual resolve+claim flow either completes correctly (claim references stored `redemptionPeriods[D].roll`, payout proceeds via `_payEth` / `_payBurnie`) or reverts cleanly (no partial state, no stuck funds, no double-payment).

### Spec (SPEC) — Locked Design Decisions

- [ ] **SPEC-01**: `pendingByDay[uint32]` storage struct shape locked: `struct DayPending { uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }`. Three storage slots per active day. Cumulative scalar globals (`pendingRedemptionEthValue` public, `pendingRedemptionBurnie` internal) unchanged.
- [ ] **SPEC-02**: `claimRedemption(uint32 day)` signature — caller specifies day; no batch helper; immediate-claim UX assumed. `pendingRedemptions[player][day]` composite key. `UnresolvedClaim` revert at `:796-797` removed (per-day keying makes multi-day pending claims safe).
- [ ] **SPEC-03**: `resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve)` — explicit day arg from `AdvanceModule` caller. `dayToResolve = currentDayView() - 1` (or equivalent — locked at SPEC phase). `hasPendingRedemptions(uint32 day)` query takes day, checks only `pendingByDay[day]`.
- [ ] **SPEC-04**: Decisions to lock at SPEC phase: (a) gameOver path interaction (does pendingByDay survive gameOver? does resolve fire post-gameOver if pre-gameOver pending exists?); (b) zero-amount / zero-rounded burn handling (existing `amount == 0` revert preserved; what if `ethValueOwed` rounds to 0?); (c) `pendingByDay[D]` storage refund timing (`delete` at resolve vs at last claim of that day); (d) `pendingRedemptions[player][day]` storage refund at claim (`delete`).
- [ ] **SPEC-05**: 50% supply cap snapshot timing — locked: `pendingByDay[D].supplySnapshot = totalSupply` on first burn of day D (i.e., when `pendingByDay[D].supplySnapshot == 0`); immutable for rest of day D; cap enforced against snapshot, not against `totalSupply` at later burn time within same day.

### Implementation (IMPL) — Contract Changes

> Single batched USER-APPROVED contract diff per `feedback_batch_contract_approval.md`. No partial commits.

- [ ] **IMPL-01**: Refactor `contracts/StakedDegenerusStonk.sol` per SPEC: remove `redemptionPeriodIndex`, `redemptionPeriodSupplySnapshot`, `redemptionPeriodBurned`, `pendingRedemptionEthBase`, `pendingRedemptionBurnieBase` (5 slots). Add `mapping(uint32 => DayPending) internal pendingByDay`. Change `pendingRedemptions` to composite key. Drop reset block `:758-762`. Drop `UnresolvedClaim` revert `:796-797`.
- [ ] **IMPL-02**: Update `_submitGamblingClaimFrom` — burn writes to `pendingByDay[game.currentDayView()].ethBase` + `.burnieBase` + `.burned`; cumulative `pendingRedemptionEthValue` += unchanged; `pendingRedemptionBurnie` += unchanged; supply snapshot lazy-initialized on first burn of day; `claim.ethValueOwed` written to composite-keyed mapping at `[beneficiary][day]`.
- [ ] **IMPL-03**: Update `resolveRedemptionPeriod` — accept `uint32 dayToResolve` arg; read `pendingByDay[dayToResolve]` for `ethBase` / `burnieBase`; write `redemptionPeriods[dayToResolve]`; `delete pendingByDay[dayToResolve]` for storage refund. Update `contracts/modules/DegenerusGameAdvanceModule.sol` call site (around `:1230` per FIXREC §103.A.4) to pass `dayToResolve = currentDayView - 1` (or locked equivalent per SPEC).
- [ ] **IMPL-04**: Update `claimRedemption(uint32 day)` — read `pendingRedemptions[msg.sender][day]` + `redemptionPeriods[day]`; existing `NotResolved` revert preserved (`period.roll == 0`); existing `_payEth` / `_payBurnie` flows unchanged; `delete pendingRedemptions[msg.sender][day]` after payout for storage refund. Update `IDegenerusGamePlayer` interface only if `currentDayView` / `dailyIdx` exposure needs change (verify at SPEC phase).

### Test (TST) — Foundry Coverage

> Test-tree AGENT-COMMITTED commits per `D-43N-TEST-COMMITS-AUTO-01` lineage.

- [ ] **TST-01**: Per-function fuzz coverage at `test/fuzz/StakedStonkRedemption.t.sol` — `testFuzz_BurnLandsInCurrentDayPool`, `testFuzz_ResolveWritesCorrectDay`, `testFuzz_ClaimReadsCorrectDay`, `testFuzz_MultipleSameDayBurnsAggregate`, `testFuzz_SupplyCapEnforced`, `testFuzz_EvCapEnforced`. 10k runs per case (FOUNDRY_PROFILE=deep).
- [ ] **TST-02**: Foundry invariant test harness at `test/invariant/RedemptionAccounting.t.sol` — stateful handler emitting random action sequences from {burn, advance, claim, gameOver, transfer, approve, admin-action}; assert INV-01..12 hold after every action.
- [ ] **TST-03**: Edge-case coverage at `test/fuzz/RedemptionEdgeCases.t.sol` — one fuzz function per EDGE-NN scenario. Positive paths assert correct outcome; negative paths assert revert or no-exploit.
- [ ] **TST-04**: V-184 attack reproduction (EDGE-07) — explicit attack vector: player A burns day D, day-D+1 advance resolves with R_{D+1}, attacker burns 1 wei post-resolve, day-D+2 advance fires; ASSERT `redemptionPeriods[D].roll` byte-identical to first resolution (no overwrite).
- [ ] **TST-05**: Phase 301 vm.skip flip — modify `test/fuzz/RngLockDeterminism.t.sol` HANDOFF-111..117 `vm.skip(true)` blocks → remove the skip + assert strict byte-identity. All 7 fuzz cases that were previously skipped MUST pass at v44.0 close.
- [ ] **TST-06**: Gas regression — assert burn-path gas ≤ +5% of v43.0 baseline; claim-path gas ≤ +0% (claim is simpler under per-day keying).
- [ ] **TST-07**: Build + full test suite — `forge build` PASS; `FOUNDRY_PROFILE=deep forge test --match-path "test/{fuzz,invariant}/**"` PASS at 10k runs per fuzz case + sufficient invariant depth.

### Edge Cases (EDGE) — Exhaustive Enumeration

> Each EDGE-NN is a named fuzz function in `test/fuzz/RedemptionEdgeCases.t.sol` (TST-03) with positive + negative assertions.

- [ ] **EDGE-01**: Pre-advance-gap burn on day D — wall flipped to D, day-D advance not yet fired, player burns. Assert: burn lands in `pendingByDay[D]`, NOT `pendingByDay[D-1]`; cumulative correctly includes both days.
- [ ] **EDGE-02**: Two pending days simultaneously — D-1 unresolved (yesterday's burns) + D accumulating (today's gap burns). Assert: day-D advance resolves D-1 only; `pendingByDay[D]` untouched.
- [ ] **EDGE-03**: Single player burns multiple days, never claims — burns on D, D+1, D+2. Assert: each claim independently resolvable; storage grows linearly with day count; player pays own storage cost.
- [ ] **EDGE-04**: Multiple players burn same day, different times relative to advance — A burns pre-advance, B burns post-advance same wall day D. Assert: both in `pendingByDay[D]`; both resolve at day-D+1's advance with R_{D+1}; each gets correct rolled share.
- [ ] **EDGE-05**: Player claims before advance fires — burns day D, calls `claimRedemption(D)` before day-D+1's advance. Assert: reverts `NotResolved`.
- [ ] **EDGE-06**: Skipped advance (long stall) — burns day D, advance for day-D+1 delayed 12h+; eventual advance fires. Assert: resolves day D with day-D+1's eventual VRF word (or retryLootboxRng failsafe word); no stuck claim.
- [ ] **EDGE-07**: V-184 attack reproduction — see TST-04. Negative assertion.
- [ ] **EDGE-08**: Burn → gameOver → claim — burn day D, gameOver triggers before day-D+1 advance (or after resolve but before claim). Assert: claim succeeds with stored roll (if resolved) OR reverts cleanly (if pre-resolve gameOver).
- [ ] **EDGE-09**: Concurrent claims from N players same day — N players all burn day D, all claim after day-D+1 advance. Assert: total payouts sum to `(pendingByDay[D].ethBase * R_{D+1}) / 100` ± dust; no over-payment; `pendingRedemptionEthValue` decrements correctly.
- [ ] **EDGE-10**: Re-entrancy attempt on `_payEth` — malicious recipient contract calls `claimRedemption(D)` re-entrantly. Assert: existing protections hold (refactor doesn't change ordering); state consistent post-revert or post-completion.
- [ ] **EDGE-11**: Burn during `rngLocked` window — assert reverts `BurnsBlockedDuringRng`.
- [ ] **EDGE-12**: Burn during `livenessTriggered` window — assert reverts `BurnsBlockedDuringLiveness`.
- [ ] **EDGE-13**: Zero-rounded `ethValueOwed` from tiny burn (1 wei sDGNRS) — assert either reverts cleanly or proceeds with `ethValueOwed = 0` (no zero-claim corruption).
- [ ] **EDGE-14**: 50% supply cap edge — burn exactly cap (succeeds); one wei over (reverts `Insufficient`).
- [ ] **EDGE-15**: 160 ETH EV cap edge — accumulate exactly 160 ETH (succeeds); one wei over (reverts `ExceedsDailyRedemptionCap`).
- [ ] **EDGE-16**: Cross-day cap reset — burn 160 ETH on D, burn 160 ETH on D+1. Assert: both allowed; per-(player, day) cap resets.
- [ ] **EDGE-17**: Burn after resolve same wall-clock day — day-D advance fires at 22:58, player burns at 23:30 same wall day D. Assert: burn lands in `pendingByDay[D]` (current day still D); resolves at day-D+1's advance.
- [ ] **EDGE-18**: BURNIE pool insufficient at claim — coinflip pool drained; player claims BURNIE owed. Assert: `_payBurnie` falls back correctly per existing logic; no revert, no stuck claim.

### Adversarial Sweep (SWP) — 3-Skill HYBRID Pass

> Per `D-302-INVOKE-01`: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT + `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT. `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02` carry.

- [ ] **SWP-01**: `/contract-auditor` SEQUENTIAL_MAIN_CONTEXT pass. Charge: find any state transition that violates INV-01..12; any (burn, advance, claim, gameOver) interleaving that produces an exploitable outcome; any storage-collision or packing bug in the new layout.
- [ ] **SWP-02**: `/zero-day-hunter` PARALLEL_SUBAGENT pass. Charge: novel attack surfaces on the per-day refactor — composition with lootbox/coinflip flows; ERC20 callback-induced re-entry on transfer paths; cross-module read/write races between sStonk and DegenerusGame storage.
- [ ] **SWP-03**: `/economic-analyst` PARALLEL_SUBAGENT pass. Charge: game-theoretic write-induced effects under the per-day model; coordinated-burn scenarios; timing arbitrage between gap burns vs post-advance burns; MEV surfaces on the new state machine.
- [ ] **SWP-04**: Two-tier consensus per `D-302-CONSENSUS-01`. Tier 1 any-skill FINDING_CANDIDATE → AskUserQuestion PAUSE. Tier 2 3-of-3 consensus → automatic elevation + RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01` against the FIXREC-augment diff.
- [ ] **SWP-05**: Disposition table per skill — every charged hypothesis + beyond-charge entries get NEGATIVE-VERIFIED / FINDING_CANDIDATE / SAFE_BY_DESIGN classification. Skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` (structural-protection check + 3-condition EV lens) applied BEFORE any user-pause.

### Audit (AUDIT) — 9-Section TERMINAL Deliverable

- [ ] **AUDIT-01**: `audit/FINDINGS-v44.0.md` 9-section deliverable. §3.A delta-surface table enumerates the USER-APPROVED contract commit (Phase 305) + every AGENT-COMMITTED test/audit/planning commit.
- [ ] **AUDIT-02**: §3.B per-exempt-entry-point attestation matrix — 3 exempt entry points × per-participating-slot row (sStonk-specific row for `redemptionPeriods[day].roll` exempt writer = `resolveRedemptionPeriod`).
- [ ] **AUDIT-03**: §3.C conservation re-proof — INV-01..12 each attested as proven by a specific TST-NN / EDGE-NN test ID. Formal invariant attestation matrix.
- [ ] **AUDIT-04**: §3.D V-184 disposition — explicit RESOLVED-AT-V44 attestation; HANDOFF-111..117 all closed; cross-reference to TST-04 + TST-05 + EDGE-07.
- [ ] **AUDIT-05**: §3.E remaining v43 backlog reference — 135 anchors deferred to v45.0+ via the v43.0 §9d handoff register; v44.0 does not consume them.
- [ ] **AUDIT-06**: §4 adversarial-pass disposition — every SWP-01..03 hypothesis (charged + beyond-charge) with verdict; skeptic-reviewer filter results.
- [ ] **AUDIT-07**: §3.F formal invariant attestation matrix — NEW section specific to v44.0 — `(INV-NN, test_id, status)` rows × 12 invariants. status = PROVEN / WAIVED (with rationale) / FAILING (blocks closure).
- [ ] **AUDIT-08**: §6 KI walkthrough — EXC-01..04 RE_VERIFIED-NEGATIVE-scope at v44 close (v44 audit subject is sStonk redemption refactor; zero affiliate-roll / AdvanceModule game-over-RNG-substitution interaction beyond sStonk-internal). KNOWN-ISSUES.md UNMODIFIED per `D-44N-KI-01`.
- [ ] **AUDIT-09**: §9 closure attestation — `7 of 7 SSTONK_VIOLATIONS RESOLVED_AT_V44; 12 of 12 INVARIANTS PROVEN; 18 of 18 EDGE_CASES TESTED; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED` verdict format. v45.0+ handoff register (135 remaining v43 anchors).

### Regression (REG) — Cross-Milestone Non-Widening

- [ ] **REG-01**: v43.0 closure non-widening — every v43.0 audit-subject surface (Phase 298 CATALOG + Phase 299 FIXREC + Phase 300 ADMA + Phase 301 FUZZ + Phase 302 SWEEP outputs) byte-identical at v44.0 close EXCEPT the Phase 301 `vm.skip(HANDOFF-111..117)` lines flipped to strict assertions (intended diff, attested in §3.A).

### Closure (CLS) — 2-Commit Sequential SHA Orchestration

- [ ] **CLS-01**: 2-commit sequential SHA orchestration per `D-303-CLOSURE-01` precedent → `D-44N-CLOSURE-01`. Commit 1 ships `audit/FINDINGS-v44.0.md` with `<commit-1-sha>` placeholder + planner-private bundle. Commit 2 resolves placeholder + propagates verbatim to 5 FINDINGS locations + 3 cross-doc targets + `chmod 444 audit/FINDINGS-v44.0.md` + atomic 5-doc closure flip (ROADMAP / STATE / MILESTONES / PROJECT / REQUIREMENTS).
- [ ] **CLS-02**: Closure signal `MILESTONE_V44_AT_HEAD_<commit-1-sha>` propagated atomically. KNOWN-ISSUES.md UNMODIFIED per `D-44N-KI-01`. Pre-authorization per `D-44N-CLOSURE-PREAUTH-01` (user grants closure-flip authorization at SPEC phase signoff; eliminates Tier-1 ping at TERMINAL commit-2).

---

## Future Requirements (deferred to v45.0+)

> Remaining 135 anchors from v43.0 §9d handoff register, plus carry-forward items. v44.0 narrow scope = sStonk only.

- 119 D-43N-V44-HANDOFF-NN anchors (excluding the 7 closed by v44.0): HANDOFF-01..110, HANDOFF-118..119 — Phase 299 FIXREC remaining entries
- 22 D-43N-V44-ADMA-NN anchors: ADMA-01..22 — Phase 300 ADMA recommendations
- 1 D-43N-V44-ADMA-ERRATUM-01 — RNGLOCK-CATALOG.md S-06 phantom-row hygiene
- Mint-boost fractional retirement (`D-40N-MINTBOOST-OUT-01` carry)
- LBX-02 fixture-coverage gap (`D-40N-LBX02-OUT-01` carry)
- `D-42N-MINTCLN-SCOPE-01` MINTCLN helper-extraction handoff
- `D-42N-EVT-BREAK-01` indexer-migration handoff
- Game-over thorough hardening — separate dedicated milestone scope
- `D-42N-RETRY-RNG-LAUNCH-FAQ-01` + `D-42N-RETRY-RNG-SCOPE-DOC-01` (launch-comms / docstring items)
- Phase 302 SWEEP coverage-gap: 3 missing FUZZ edge-case functions (cross-EOA Sybil within rngLock; ERC721 receiver-callback re-entry on deity-pass mint; stETH yield accrual mid-window) — v45.0+ FUZZ-augment phase

## Out of Scope

Explicitly excluded from v44.0; documented to prevent scope creep:

| Feature | Reason |
|---------|--------|
| Any v43 FIXREC entry outside HANDOFF-111..117 | Narrow scope; v45.0+ ships remaining 135 anchors. |
| Any v43 ADMA recommendation | Out of scope; v45.0+ ships ADMA fixes. |
| Re-entrancy hardening of `_payEth` / `_payBurnie` | Existing protections audited at v25+; refactor doesn't change call ordering. |
| BURNIE/coinflip lifecycle redesign | Out of scope; preserve existing semantics. |
| `dailyIdx == currentDayView()` burn gate | Not needed — per-day keying provably closes the gap window (INV-08). |
| Storage migration of pre-v44 state | Pre-launch posture: redeploy-fresh per `feedback_frozen_contracts_no_future_proofing.md`. |
| `claimMultipleRedemptions` batch helper | Drop — immediate-claim UX assumed; multi-day stacking is the rare path, players can call `claimRedemption(day)` N times. |
| `IDegenerusGamePlayer` interface expansion beyond minimum | Add only what `_submitGamblingClaimFrom` + `resolveRedemptionPeriod` require. |

## Traceability

> Every v44.0 requirement maps to exactly one primary delivery phase. INV-01..12 + EDGE-01..18 span multiple phases by design (SPEC documents the property/scenario at Phase 304 → TST proves it at Phase 306 → TERMINAL §3.F attests it at Phase 308); the primary delivery phase is the one that ships the load-bearing artifact for closure verdict math. **Coverage: 63/63** (12 INV + 5 SPEC + 4 IMPL + 7 TST + 18 EDGE + 5 SWP + 9 AUDIT + 1 REG + 2 CLS). Zero orphaned requirements; zero duplicate primary mappings.

| Requirement | Primary Delivery Phase | Status |
|-------------|------------------------|--------|
| INV-01 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-02 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-03 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-04 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-05 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-06 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-07 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-08 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-09 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-10 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-11 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| INV-12 | Phase 306 TST (invariant harness) [doc at 304 SPEC; attest at 308 §3.F] | Pending |
| SPEC-01 | Phase 304 SPEC | Pending |
| SPEC-02 | Phase 304 SPEC | Pending |
| SPEC-03 | Phase 304 SPEC | Pending |
| SPEC-04 | Phase 304 SPEC | Pending |
| SPEC-05 | Phase 304 SPEC | Pending |
| IMPL-01 | Phase 305 IMPL | Pending |
| IMPL-02 | Phase 305 IMPL | Pending |
| IMPL-03 | Phase 305 IMPL | Pending |
| IMPL-04 | Phase 305 IMPL | Pending |
| TST-01 | Phase 306 TST | Pending |
| TST-02 | Phase 306 TST | Pending |
| TST-03 | Phase 306 TST | Pending |
| TST-04 | Phase 306 TST | Pending |
| TST-05 | Phase 306 TST | Pending |
| TST-06 | Phase 306 TST | Pending |
| TST-07 | Phase 306 TST | Pending |
| EDGE-01 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-02 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-03 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-04 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-05 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-06 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-07 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-08 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-09 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-10 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-11 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-12 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-13 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-14 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-15 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-16 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-17 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| EDGE-18 | Phase 306 TST (one fuzz function per EDGE-NN) [enum at 304 SPEC] | Pending |
| SWP-01 | Phase 307 SWEEP | Pending |
| SWP-02 | Phase 307 SWEEP | Pending |
| SWP-03 | Phase 307 SWEEP | Pending |
| SWP-04 | Phase 307 SWEEP | Pending |
| SWP-05 | Phase 307 SWEEP | Pending |
| AUDIT-01 | Phase 308 TERMINAL | Pending |
| AUDIT-02 | Phase 308 TERMINAL | Pending |
| AUDIT-03 | Phase 308 TERMINAL | Pending |
| AUDIT-04 | Phase 308 TERMINAL | Pending |
| AUDIT-05 | Phase 308 TERMINAL | Pending |
| AUDIT-06 | Phase 308 TERMINAL | Pending |
| AUDIT-07 | Phase 308 TERMINAL | Pending |
| AUDIT-08 | Phase 308 TERMINAL | Pending |
| AUDIT-09 | Phase 308 TERMINAL | Pending |
| REG-01 | Phase 308 TERMINAL §5 | Pending |
| CLS-01 | Phase 308 TERMINAL Commit 1 (audit deliverable + planner-private bundle) | Pending |
| CLS-02 | Phase 308 TERMINAL Commit 2 (closure-flip + verbatim propagation + chmod 444) | Pending |
