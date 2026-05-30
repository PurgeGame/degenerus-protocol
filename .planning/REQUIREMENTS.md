# Requirements — v55.0 AfKing-in-Game Redesign

> **Baseline:** v54 de-custody HEAD `20ca1f79` (v54.0 closed-superseded).
> **Design-lock:** `.planning/PLAN-V55-AFKING-IN-GAME-REDESIGN.md` (canonical = §10, which supersedes the §0–§3 stamp framing).
> **Discharged foundations:** REVERT-FREE-CHAIN proof `.planning/PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` (its §5 = the 4 LOCKED obligations below) + SOLVENCY-01 (Phase 343).
> **Posture:** security/freeze/solvency floor over gas; carefully-sequenced batched USER-APPROVED contract diff (HARD STOP at the contract-commit boundary, `feedback_batch_contract_approval` / `feedback_never_preapprove_contracts` / `feedback_no_contract_commits`); `ContractAddresses.sol` freely modifiable; pre-launch redeploy-fresh (storage break fine). FULL close (sweep IN-MILESTONE at TERMINAL).

---

## v55.0 Requirements

### ARCH — Architecture: state game-resident + module split + code-size
- [ ] **ARCH-01**: The subscriber set (`_subOf`/`_subscribers`/`_subscriberIndex`), the process/open cursors, the per-sub box-stamp, and the v54 `afkingFunding` ledger are appended to `DegenerusGameStorage` (layout-safe append; every module already shares the base).
- [ ] **ARCH-02**: A new `GameAfkingModule` (delegatecall, inherits `DegenerusGameStorage`) owns `subscribe`/setters + the process-pass + the open-pass + the router; its bytecode is its own budget, not the Game's.
- [ ] **ARCH-03**: `AfKing.sol` collapses to thin dispatch stubs (`subscribe`/`setDailyQuantity`/`doWork`/…) ≈1–1.5KB; the `AF_KING`-address dissolution vs thin-external-shim question is resolved (incl. the mandatory-mint-gate interaction if any entry routes through `advanceGame`).
- [ ] **ARCH-04**: Game runtime code-size stays < 24,576 bytes at every intermediate step — reclaim FIRST (`claimAffiliateDgnrs`→`BingoModule` ≈1.3KB; read-aggregators drop-`view`/→lens) before adding the afking stubs (sequenced so the Game never breaches the ceiling mid-flight).

### BOX — Box redesign: relocate the freeze into a per-sub stamp
- [ ] **BOX-01**: Boons are OFF for afking boxes → box `amount` = spend (deletes the boosted-amount freeze field).
- [ ] **BOX-02**: The process-pass (pre-RNG) writes a per-sub stamp `(index = current `LR_INDEX`, amount, day)` — one warm-dirty write per process-day, overwritten each cycle (no cold `lootboxEth*`/`lootboxPurchasePacked`/`boxPlayers.push`).
- [ ] **BOX-03**: The process-pass debits `afkingFunding` and sets the `lastAutoBoughtDay == today` success-marker ONLY after a successful debit (a failed buy writes no marker → no free box; a wallet subscribing between process and open has no this-cycle marker → no free box).
- [ ] **BOX-04**: The open-pass (post-RNG) materializes the box from the stamp + the committed `lootboxRngWordByIndex[stamp.index]` with math byte-identical to `openLootBox`; `lastOpenedIndex` is monotonic per sub (open only if `stamp.index > lastOpenedIndex` → no double-open).
- [ ] **BOX-05**: Humans keep the existing `lootboxEth`/`boxPlayers` open route unchanged; the two open routes share no mutable-state hazard.

### FREEZE — RNG / determinism security spine
- [ ] **FREEZE-01**: Freeze-completeness — the stamp captures ALL outcome-determining state at process; the open re-derives nothing manipulable from mutable per-player state (the §10 live score/base-level/EV-cap reads are admitted only because in-window manipulation is −EV; documented + attested).
- [ ] **FREEZE-02**: Index-binding — the stamp binds to the pre-RNG `LR_INDEX` (read once at pass start); the process-pass MUST NOT straddle a mid-day `requestLootboxRng` index advance (`AdvanceModule.sol:1016`).
- [ ] **FREEZE-03**: Determinism — the box seed `keccak256(rngWord, player, day, amount)` uses the STAMPED buy-day (never open-time `_simulatedDayIndex()`), and carries no `block.timestamp/number/prevrandao/coinbase/blockhash` in the draw.

### REVERT — Revert-free-chain (discharged invariant, carried into IMPL)
- [ ] **REVERT-01**: The process-pass slice construction preserves `_resolveBuy`'s validation invariants VERBATIM — `ev = cost − claimableUse` + enum payKind, the 1-wei claimable sentinel, the `LOOTBOX_MIN` transient skip, `quantity ≥ 1` — so the funded buy is revert-free by construction (migration fidelity; the proof's load-bearing obligation).
- [ ] **REVERT-02**: A thin per-sub try/catch skip valve isolates the process AND open legs, absorbing the two residual revert classes (solvency-violation [safe under SOLVENCY-01], liveness-timeout [game-dead]) so no single sub can brick a batch / the day.

### EVCAP — EV-cap accounting at open
- [ ] **EVCAP-01**: The afking open increments `lootboxEvBenefitUsedByLevel[player][level+1]` via `_applyEvMultiplierWithCap` (read+write-at-open, exactly once per open, same map/key as MintModule's buy-time write, hard-clamped ≤10 ETH → no revert); the buy-time EV write is bypassed for afking boxes (no double-draw). Proven equivalent to the v54 per-`(sub,level)` accumulator.

### CONSENT — OPEN-E / AFSUB / set-mutation carry-over
- [ ] **CONSENT-01**: The subscribe-time `isOperatorApproved` (OPEN-E) gate, the pass-gating (`validThroughLevel`), the VAULT/SDGNRS exemption-on-`player`, and the funder=src accounting carry over verbatim; the OPEN-E 4-protection structure is re-attested.
- [ ] **CONSENT-02**: Set-mutation — evictions preserve "no cursor advance after swap-pop" (the H-CANCEL-SWAP-MISS / cancel-tombstone-streak class); tombstone-then-reclaim shape carries over.

### PLACE — Process/open placement + bounty
- [ ] **PLACE-01**: The §4 placement (required-path `advanceGame` phase vs separate permissionless legs) is decided at SPEC on non-revert grounds (guaranteed-every-day vs minimal-surface, the `_enforceDailyMintGate` standing interaction, bounty farm-by-splitting); process-leg pre-RNG cursor-chunked, open-leg post-`_unlockRng` cursor-chunked.
- [ ] **PLACE-02**: Bounty reconciliation — open stays a post-RNG router category (`OPEN_BATCH`/`OPEN_KNEE` pro-rate); the buy/process bounty is work-scaled (not once-per-advance) to close the middle-chunk-unpaid gap and resist farm-by-splitting; payment stays the deferred BURNIE flip-credit mint (`creditFlip`).

### GAS — Behavior-identical relocations
- [ ] **GAS-01**: The afking box-buy's ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` (~120–130k) collapse to one warm-dirty Sub-stamp write (~5k); behavior-identical, proven same-results in TST.
- [ ] **GAS-02**: The per-subscriber `afkingSnapshot`/`afkingFundingOf` cross-contract staticcalls (~3–5k each) become in-context `SLOAD`s.
- [ ] **GAS-03**: Same-slot affiliate/pool aggregate flushes across a process batch (`claimablePool`/`prizePoolsPacked` accumulate-and-flush; bucket affiliate by roll-winner) — SAFE-WITH-CONDITIONS (do NOT batch `quests.handleAffiliate` — non-linear completion logic); each gas-only under the security floor.

### TST — Empirical proofs
- [ ] **TST-01**: Freeze/determinism — the stamp+open produces an identical box outcome independent of open timing/block (seed uses the stamped day); index-binding holds across a mid-day index advance.
- [ ] **TST-02**: Revert-free — a funded process/open never reverts on well-formed slices (the preserved `_resolveBuy` invariants), and the skip valve isolates the solvency/liveness residuals without bricking the batch/day.
- [ ] **TST-03**: EV-cap — the per-`(player, level)` 10-ETH benefit budget is enforced exactly once per open with no double-draw vs the buy-time path; equivalent to v54.
- [ ] **TST-04**: Two-path open coexistence + set-mutation (eviction/tombstone/swap-pop, streak preserved) + OPEN-E 4-protection regression.
- [ ] **TST-05**: NON-WIDENING regression vs the v54 baseline — every pre-existing red enumerated BY NAME (`REGRESSION-BASELINE-v55.md`).
- [ ] **TST-06**: Gas — measured per-buy + per-open marginal under the 16.7M HARD per-tx ceiling; the GAS-01/02/03 wins proven same-results.

### AUDIT — Terminal close
- [ ] **AUDIT-01**: FULL close — delta-audit (every v55 surface vs the v54 baseline; freeze + solvency + OPEN-E re-attested) + 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT) focused on the box-stamp freeze + the liveness isolation + the two-path open + `audit/FINDINGS-v55.0.md` (chmod 444) + the atomic 5-doc closure flip with the `MILESTONE_V55_AT_HEAD_<sha>` signal.

## Future Requirements (deferred)
- Generalized operator-spend of `claimableWinnings` (carried from v54 §10) — larger blast radius, separate optional feature.
- A bingo / afking progress view helper (frontend read-only).

## Out of Scope
- The v52 consolidated cross-model audit (separate track; v55's surface folds into it as an additional track, not a substitute for v55's own close).
- Off-chain indexer / webpage (separate frontend track).
- Any contract surface beyond the AfKing-in-Game fold + the box redesign + the gas pass.

## Traceability

Each REQ-ID maps to exactly ONE phase — the phase that DELIVERS/owns it. 29/29 mapped, 0 orphaned, 0 duplicated. Full rationale (the design+impl+test center-of-gravity split) in `.planning/ROADMAP.md` Coverage section.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ARCH-01 | 349 IMPL | Pending |
| ARCH-02 | 349 IMPL | Pending |
| ARCH-03 | 349 IMPL | Pending |
| ARCH-04 | 348 SPEC | Pending |
| BOX-01 | 349 IMPL | Pending |
| BOX-02 | 349 IMPL | Pending |
| BOX-03 | 349 IMPL | Pending |
| BOX-04 | 349 IMPL | Pending |
| BOX-05 | 349 IMPL | Pending |
| FREEZE-01 | 348 SPEC | Pending |
| FREEZE-02 | 348 SPEC | Pending |
| FREEZE-03 | 348 SPEC | Pending |
| REVERT-01 | 349 IMPL | Pending |
| REVERT-02 | 349 IMPL | Pending |
| EVCAP-01 | 349 IMPL | Pending |
| CONSENT-01 | 349 IMPL | Pending |
| CONSENT-02 | 349 IMPL | Pending |
| PLACE-01 | 348 SPEC | Pending |
| PLACE-02 | 349 IMPL | Pending |
| GAS-01 | 350 GAS | Pending |
| GAS-02 | 350 GAS | Pending |
| GAS-03 | 350 GAS | Pending |
| TST-01 | 351 TST | Pending |
| TST-02 | 351 TST | Pending |
| TST-03 | 351 TST | Pending |
| TST-04 | 351 TST | Pending |
| TST-05 | 351 TST | Pending |
| TST-06 | 351 TST | Pending |
| AUDIT-01 | 352 TERMINAL | Pending |

**Per-phase rollup:**

| Phase | Type | Requirements | Count |
|-------|------|--------------|-------|
| 348 | SPEC | FREEZE-01, FREEZE-02, FREEZE-03, PLACE-01, ARCH-04 | 5 |
| 349 | IMPL (CONTRACT BOUNDARY) | ARCH-01, ARCH-02, ARCH-03, BOX-01, BOX-02, BOX-03, BOX-04, BOX-05, REVERT-01, REVERT-02, EVCAP-01, CONSENT-01, CONSENT-02, PLACE-02 | 14 |
| 350 | GAS (CONTRACT BOUNDARY) | GAS-01, GAS-02, GAS-03 | 3 |
| 351 | TST | TST-01, TST-02, TST-03, TST-04, TST-05, TST-06 | 6 |
| 352 | TERMINAL (FULL close) | AUDIT-01 | 1 |
| **Total** | | | **29** |

✓ All 29 v55.0 requirements mapped · ✓ 0 orphaned · ✓ 0 duplicated
