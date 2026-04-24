# Requirements: Degenerus Protocol — Post-v30 Delta Audit + Gameover Edge-Case Re-Audit

**Defined:** 2026-04-23
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

**Goal:** Adversarially audit every post-v30.0 contract change (5 commits, 12 files, 4 code-touching) AND re-verify the gameover path's edge cases — with a focused sub-audit on the new liveness gates and sDGNRS redemption protection, with hard guarantees that every redemption path works as intended, never loses funds, and the math closes exactly.

**Audit baseline:** v30.0 HEAD `7ab515fe` → current HEAD `771893d1` at milestone start.

**In-scope commits (chronological):**

1. `ced654df` — fix(jackpot): emit accurate scaled ticketCount on all JackpotTicketWin paths (event correctness; `DegenerusGameJackpotModule.sol` +33/-6)
2. `16597cac` — rngunlock fix (`DegenerusGameAdvanceModule.sol`; `_unlockRng(day)` removal from two-call-split continuation)
3. `6b3f4f3c` — feat(quests): credit recycled ETH toward MINT_ETH quests and earlybird DGNRS (`DegenerusQuests.sol`, `IDegenerusQuests.sol`, `DegenerusGameMintModule.sol`; gas: −142k/−153k/−76k on 3 worst-case paths)
4. `771893d1` — feat(gameover): shift purchase/claim gates to liveness and protect sDGNRS redemptions (`DegenerusGame.sol`, `StakedDegenerusStonk.sol`, `IDegenerusGame.sol`, `IStakedDegenerusStonk.sol`, `AdvanceModule`, `GameOverModule`, `MintModule`, `WhaleModule`, `DegenerusGameStorage.sol`)
5. `ffced9ef` — chore: remove REQUIREMENTS.md for v30.0 milestone (docs-only; enumerated for completeness)

**Write policy:** READ-only — no `contracts/` or `test/` edits (v28/v29/v30 carry-forward).

**Deliverable:** `audit/FINDINGS-v31.0.md` with executive summary, per-phase sections, F-31-NN finding blocks, and a lean regression appendix (only prior findings directly touched by the deltas).

**Accepted RNG exceptions (not re-litigated unless deltas move the surface):**

1. Non-VRF entropy for affiliate winner roll — KNOWN-ISSUES.md
2. Gameover prevrandao fallback (`_getHistoricalRngFallback`) — KNOWN-ISSUES.md
3. Gameover RNG substitution for mid-cycle write-buffer tickets (F-29-04) — KNOWN-ISSUES.md
4. EntropyLib XOR-shift PRNG — KNOWN-ISSUES.md

---

## v31.0 Requirements

### DELTA — Delta Extraction & Classification

- [x] **DELTA-01**: Enumerate every function / state variable / event changed by the 5 post-v30.0 commits with per-commit and aggregate counts — COMPLETE at cc68bfc7 (`audit/v31-243-DELTA-SURFACE.md` Sections 0+1+4+5)
- [x] **DELTA-02**: Classify each changed function as {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED} with evidence (diff hunks + hunk-level annotation) — COMPLETE at cc68bfc7 (`audit/v31-243-DELTA-SURFACE.md` Section 2; 26 rows — 2 NEW / 23 MODIFIED_LOGIC / 1 REFACTOR_ONLY / 0 DELETED / 0 RENAMED)
- [x] **DELTA-03**: Identify every downstream call site of each changed function and interface across `contracts/` (grep-reproducible inventory) — COMPLETE at cc68bfc7 (`audit/v31-243-DELTA-SURFACE.md` Section 3; 60 D-243-X### rows + Section 6 Consumer Index of 41 D-243-I### rows)

### EVT — JackpotTicketWin Event Correctness (`ced654df`)

- [ ] **EVT-01**: Prove every `JackpotTicketWin` emit path now emits a non-zero scaled `ticketCount` (no stub zero values); enumerate all emit sites
- [ ] **EVT-02**: Prove the new `JackpotWhalePassWin` emit covers the previously-silent large-amount odd-index BAF path with correct `amount`/`traitId`
- [ ] **EVT-03**: Prove `ticketCount` is uniformly `TICKET_SCALE`-scaled across BAF and trait-matched paths (UI consumers can divide by 100 without branching on traitId)
- [ ] **EVT-04**: Prove event NatSpec accurately describes the scaling and fractional-remainder resolution (carry vs `_rollRemainder`)

### RNG — rngunlock Fix (`16597cac`)

- [ ] **RNG-01**: Prove `_unlockRng(day)` removal from the two-call split ETH distribution continuation is safe — enumerate every path that reaches that point and verify `rngLocked` clears elsewhere on the same tick
- [ ] **RNG-02**: Re-verify the v30.0 `rngLockedFlag` AIRTIGHT invariant at the new HEAD (no double-set, no set-without-clear, no clear-without-matching-set)
- [ ] **RNG-03**: Verify the reformat-only changes in the same commit (multi-line SLOAD + tuple destructuring) are behaviorally equivalent to the pre-commit source

### QST — Quests Recycled-ETH Credits + Earlybird DGNRS (`6b3f4f3c`)

- [ ] **QST-01**: Prove `MINT_ETH` daily + level quest progress is correctly credited on gross spend (fresh + recycled) via `ethMintSpendWei` path — no path where fresh-only tracking remains
- [ ] **QST-02**: Prove earlybird DGNRS emission counts the same gross spend toward the 1,000 ETH target without double-counting across multiple quest types
- [ ] **QST-03**: Prove affiliate fresh-vs-recycled split (20-25% fresh / 5% recycled) is preserved — the boundary that enforces the real-capital-inflow incentive must not regress
- [ ] **QST-04**: Verify the `freshEth` return drop from `_callTicketPurchase` and `ethFreshWei → ethMintSpendWei` rename are behaviorally equivalent (no call-site drift)
- [ ] **QST-05**: Validate claimed gas savings (−142k WC daily split, −153k WC early-burn, −76k WC terminal jackpot) against repro evidence or mark INFO if unreproducible

### GOX — Gameover Liveness + sDGNRS Redemption Protection (`771893d1`)

- [ ] **GOX-01**: Enumerate all 8 purchase/claim paths moved from `gameOver` → `_livenessTriggered` in MintModule + WhaleModule; prove the one-cycle-earlier cutoff is consistent with existing `_queueTickets` / scaled / range variant ticket-queue guards
- [ ] **GOX-02**: Prove `sDGNRS.burn` + `burnWrapped` block during State 1 (liveness fired, gameOver not yet latched) prevents orphan gambling-burn redemptions whose segregated ETH would be swept by `handleGameOverDrain`
- [ ] **GOX-03**: Prove `handleGameOverDrain` correctly subtracts `pendingRedemptionEthValue` from available funds so pre-gameover-latched redemptions retain reserved ETH for `claimRedemption`
- [ ] **GOX-04**: Prove `_livenessTriggered` VRF-dead handling (14-day `_VRF_GRACE_PERIOD` stall with day math unmet) correctly fires liveness to enable `_gameOverEntropy` prevrandao fallback
- [ ] **GOX-05**: Prove day math is evaluated first in `_livenessTriggered` so mid-drain RNG request/fulfillment gaps cannot transiently suppress liveness
- [ ] **GOX-06**: Prove `_gameOverEntropy` clears `rngRequestTime` on fallback commit and `_handleGameOverPath` checks `gameOver` before liveness (post-gameover final sweep stays reachable when VRF-dead latches gameOver with day math unmet)
- [ ] **GOX-07**: Verify `DegenerusGameStorage.sol` (+27 lines) slot layout changes via `forge inspect` — either backwards-compatible or explicitly intentional

### SDR — sDGNRS Redemption Gameover Safety (deep sub-audit)

- [ ] **SDR-01**: Enumerate every sDGNRS redemption state transition (request → resolve via RNG → claim) across all possible timings vs gameover lifecycle:
  - (a) all three steps pre-liveness
  - (b) request pre-liveness, resolve/claim in State 1 (liveness-fired, !gameOver)
  - (c) request pre-liveness, resolve in State 1, claim post-gameOver
  - (d) resolved pre-gameOver, claim post-gameOver
  - (e) request post-gameOver (expected: blocked)
  - (f) request pre-liveness, VRF-pending at liveness, resolves via `_gameOverEntropy` fallback
- [ ] **SDR-02**: Prove `pendingRedemptionEthValue` accounting is exact across every entry/exit — exact ETH reserved on request-resolve, exact ETH returned to pool on fail-roll, no dust, no overshoot
- [ ] **SDR-03**: Prove `handleGameOverDrain` subtracts the full `pendingRedemptionEthValue` so no reserved ETH is swept into the 33/33/34 claimable split (and the subtraction happens BEFORE the split math)
- [ ] **SDR-04**: Prove `claimRedemption` post-gameOver can always pay out every reserved redemption — no DOS via drain ordering, no starvation, no underflow, no race against the 30-day sweep
- [ ] **SDR-05**: Prove ETH conservation closes: for every wei entering `pendingRedemptionEthValue`, exactly one wei exits (to claimer OR back to pool), never both, never neither — across every gameover timing from SDR-01
- [ ] **SDR-06**: Prove the block on `sDGNRS.burn` + `burnWrapped` during State 1 closes the orphan-redemption window — no reachable path creates a new redemption while liveness is fired but gameOver not latched
- [ ] **SDR-07**: Prove sDGNRS supply conservation across the full redemption lifecycle including gameover interception — no dust mint, no over-burn, no ghost tokens
- [ ] **SDR-08**: Prove `_gameOverEntropy` fallback substitution for VRF-pending redemptions (F-29-04 class interaction) preserves fairness and prevents any redemption hanging in pending limbo post-gameOver

### GOE — Gameover Edge-Case Re-Verification (pre-existing invariants)

- [ ] **GOE-01**: Re-verify F-29-04 RNG-consumer determinism (gameover mid-cycle ticket-buffer swap → `_gameOverEntropy` substitution) still holds at new HEAD
- [ ] **GOE-02**: Re-verify claimablePool 33/33/34 split + 30-day sweep delay (from v24.0) against the new gameover-drain flow that now subtracts `pendingRedemptionEthValue`
- [ ] **GOE-03**: Re-verify purchase blocking covers all entry points at current surface — no ETH injection path after liveness gate fires (updated from v24.0's "10 entry points")
- [ ] **GOE-04**: Re-verify VRF-available vs prevrandao fallback gameover-jackpot branches given the new VRF-dead 14-day grace fallback
- [ ] **GOE-05**: Re-verify the `gameOverPossible` BURNIE endgame gate (v11.0) across all new liveness paths — BURNIE mint/endgame bypass must remain impossible
- [ ] **GOE-06**: Enumerate any NEW edge case introduced by the interaction of liveness-gate + sDGNRS redemption + `pendingRedemptionEthValue` drain subtraction (cross-feature emergent behavior)

### FIND — Findings Consolidation

- [ ] **FIND-01**: Consolidate all v31.0 findings into `audit/FINDINGS-v31.0.md` with executive summary, per-phase sections, and F-31-NN finding blocks (v29/v30 shape)
- [ ] **FIND-02**: Classify each finding using the D-08 5-bucket severity rubric (CRITICAL/HIGH/MEDIUM/LOW/INFO)
- [ ] **FIND-03**: Update `KNOWN-ISSUES.md` with any new accepted-design entries that pass the D-09 3-predicate gating (accepted-design + non-exploitable + sticky)

### REG — Lean Regression Appendix

- [ ] **REG-01**: Spot-check regression — re-verify any v30.0 F-30-NNN finding directly touched by the deltas; re-verify F-29-04 at new HEAD. Skip the full 31-row v30.0 regression sweep per milestone scope decision
- [ ] **REG-02**: Document any prior finding superseded by the new code (e.g., sDGNRS redemption protection may resolve a prior orphan-redemption edge case)

---

## Traceability

_(Filled by roadmapper — maps each REQ-ID to its phase assignment.)_

| REQ-ID | Phase | Status |
|--------|-------|--------|
| DELTA-01 | Phase 243 | COMPLETE (243-01 + 243-01-addendum, at cc68bfc7) |
| DELTA-02 | Phase 243 | COMPLETE (243-02, at cc68bfc7) |
| DELTA-03 | Phase 243 | COMPLETE (243-03, at cc68bfc7) |
| EVT-01 | Phase 244 | Pending |
| EVT-02 | Phase 244 | Pending |
| EVT-03 | Phase 244 | Pending |
| EVT-04 | Phase 244 | Pending |
| RNG-01 | Phase 244 | Pending |
| RNG-02 | Phase 244 | Pending |
| RNG-03 | Phase 244 | Pending |
| QST-01 | Phase 244 | Pending |
| QST-02 | Phase 244 | Pending |
| QST-03 | Phase 244 | Pending |
| QST-04 | Phase 244 | Pending |
| QST-05 | Phase 244 | Pending |
| GOX-01 | Phase 244 | Pending |
| GOX-02 | Phase 244 | Pending |
| GOX-03 | Phase 244 | Pending |
| GOX-04 | Phase 244 | Pending |
| GOX-05 | Phase 244 | Pending |
| GOX-06 | Phase 244 | Pending |
| GOX-07 | Phase 244 | Pending |
| SDR-01 | Phase 245 | Pending |
| SDR-02 | Phase 245 | Pending |
| SDR-03 | Phase 245 | Pending |
| SDR-04 | Phase 245 | Pending |
| SDR-05 | Phase 245 | Pending |
| SDR-06 | Phase 245 | Pending |
| SDR-07 | Phase 245 | Pending |
| SDR-08 | Phase 245 | Pending |
| GOE-01 | Phase 245 | Pending |
| GOE-02 | Phase 245 | Pending |
| GOE-03 | Phase 245 | Pending |
| GOE-04 | Phase 245 | Pending |
| GOE-05 | Phase 245 | Pending |
| GOE-06 | Phase 245 | Pending |
| FIND-01 | Phase 246 | COMPLETE (246-01 closed at cc68bfc7 — audit/FINDINGS-v31.0.md FINAL READ-only published, 403 lines, 9-section v31 shape) |
| FIND-02 | Phase 246 | COMPLETE (246-01 closed at cc68bfc7 — D-08 5-bucket severity rubric reproduced verbatim; severity counts 0/0/0/0/0; total F-31-NN = 0) |
| FIND-03 | Phase 246 | COMPLETE (246-01 closed at cc68bfc7 — zero-row Non-Promotion Ledger; 4-row envelope-non-widening attestation table; KNOWN-ISSUES.md UNMODIFIED per CONTEXT.md D-07 default path) |
| REG-01 | Phase 246 | COMPLETE (246-01 closed at cc68bfc7 — LEAN spot-check 6 PASS / 0 REGRESSED / 0 SUPERSEDED; F-29-04 explicitly NAMED RE_VERIFIED via SDR-08-V01 + GOE-01-V01 dual carriers; 12-row exclusion log) |
| REG-02 | Phase 246 | COMPLETE (246-01 closed at cc68bfc7 — 1-row sweep 0 PASS / 0 REGRESSED / 1 SUPERSEDED; pre-existing orphan-redemption window structurally closed by 771893d1; LEAN explicit candidate list per CONTEXT.md D-10) |

---

## Out of Scope

- Non-delta contract surface — v30.0 HEAD `7ab515fe` already proven VRF-consumer deterministic; not re-audited here
- ETH / BURNIE conservation on non-delta surfaces — covered v29.0 Phase 235 Plans 01-02
- Full v30.0 31-row regression sweep — replaced by REG-01 spot-check (only prior findings touched by deltas)
- Indexer / database / sim / frontend — covered v28.0; not in scope here
- `test/` changes — READ-only pattern
- `contracts/` edits — READ-only pattern (any HIGH/CRITICAL surfacing is documented in FINDINGS-v31.0.md and deferred to a remediation milestone)
- Re-litigating the 4 accepted KNOWN-ISSUES RNG exceptions (affiliate roll / prevrandao fallback / F-29-04 mid-cycle substitution / EntropyLib XOR-shift) — only re-verified that the deltas don't widen them
- Re-proving storage layout for non-delta contracts (v24.1 covered comprehensively; only delta-affected layouts checked here)

## Future Requirements

_(None deferred at milestone start — populated during execution if any REQ rolls forward.)_
