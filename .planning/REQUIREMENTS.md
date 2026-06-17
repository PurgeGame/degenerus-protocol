# Requirements: Degenerus Protocol — v67.0 Spinal-Column Brick & State-Corruption Audit (mintFlip / advanceGame chain)

**Defined:** 2026-06-16
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Milestone goal:** Prove no reachable transaction in the game's spinal column — the `mintFlip()` / `purchase` mint chain and the `advanceGame()` core state machine, including every delegatecall into the 13 modules and the VRF / GAMEOVER paths — can revert-wedge the state machine into a permanent brick or leave its packed storage / accounting corrupted.
**Method:** Cross-model council (Gemini + Codex) is the PRIMARY finder; Claude builds the foundation, adjudicates, and synthesizes. Every candidate finding is adversarially verified before it is recorded.
**Subject:** HEAD `fa7932f6`, `contracts/` tree `0dd445a6` (unchanged since the v66 freeze), byte-frozen at FOUNDATION.
**Scope:** Column + synchronous callees (USER-confirmed) — `DegenerusGame.sol` (`mintFlip` L376 · `purchase` L552 · `advanceGame` L279 · `rawFulfillRandomWords` L1856 · `updateVrfCoordinatorAndSub` L1776 · `gameOver` terminal flag + thin delegatecall dispatch stubs) + the 13 `contracts/modules/*` delegatecall modules (Advance · Mint · Lootbox · Jackpot · Decimator · Degenerette · Whale · Afking · Boon[nested] · Bingo · GameOver · MintStreakUtils · PayoutUtils) + the peripheral contracts the column synchronously calls in the critical path (FLIP · Coinflip · Vault · sDGNRS · Affiliate). A revert in a synchronously-called contract bricks the spine just as hard as a revert inside the Game.
**Assumptions:** Honest admin / governance — a legitimate coordinator rotation must not be able to brick or corrupt, but admin malice is out of scope.
**Posture:** Audit-only on a byte-frozen subject. No contract changes expected; any that surface go through the standard contract-commit approval gate. Test-only additions (MECH) commit autonomously.

## v1 Requirements

Requirements for this milestone. Each maps to exactly one roadmap phase.

### FOUND — Foundation: Subject Freeze & Green Baseline

- [ ] **FOUND-01**: The audit subject is byte-frozen at current HEAD, with the commit hash (`fa7932f6`) and `contracts/`-tree hash (`0dd445a6`) recorded as the v67 freeze anchor.
- [ ] **FOUND-02**: A green baseline oracle is captured and documented (forge full-suite pass/skip counts + hardhat parity) as the v67 regression baseline; any pre-existing reds are catalogued as carried, not new.

### COLMAP — Re-Derive the Spinal-Column Call Graph From HEAD

- [ ] **COLMAP-01**: The complete spinal-column call graph is re-derived from current HEAD by mechanical enumeration — every entry point (`mintFlip`, `purchase`, `buyPresaleBox`, `buyLootboxAndPresaleBox`, `purchaseWhaleBundle`, `purchaseLazyPass`, `purchaseDeityPass`, `advanceGame`, `rawFulfillRandomWords`, and the permissionless/keeper entrypoints) → every internal call → every delegatecall (the 13 modules + nested Boon + the raw `delegatecall(msg.data)` afking dispatch) → every synchronous external call into FLIP / Coinflip / Vault / sDGNRS / Affiliate — captured as an authoritative current-HEAD map.
- [ ] **COLMAP-02**: Every revert site reachable in the column (`revert`, `require`, custom errors, checked-arithmetic overflow points, low-level call-failure bubbles) is enumerated and tabulated with its trigger condition.
- [ ] **COLMAP-03**: Every unbounded or input-sized loop in the column is enumerated with its iteration-count bound and the storage / gas it touches per iteration.
- [ ] **COLMAP-04**: Every storage write performed under delegatecall (module → Game storage) is enumerated against the Game's authoritative storage layout (`forge inspect DegenerusGame storageLayout`), establishing the slot each module touches.

### BRICK — Permanent-Brick / Liveness (DOMINANT)

- [ ] **BRICK-01**: Every revert site enumerated in COLMAP is classified transient (caller can retry / another actor can progress) vs. permanent (wedges the state machine forever); zero permanent-wedge sites survive, or each surviving one is dispositioned.
- [ ] **BRICK-02**: `advanceGame()` is proven to always be able to make progress — there is no reachable (day, level, phase, jackpotPhaseFlag, gameOver) state from which every `advanceGame()` call reverts; the per-tick "one unit of work" invariant holds and pending-work discovery (`hasPendingWork`) cannot diverge from what `advanceGame` will execute.
- [ ] **BRICK-03**: The terminal transition is proven to always finalize — `gameOver`, once set, can always be driven to full settlement (terminal decimator + terminal jackpot + `handleGameOverDrain`) without a reachable revert that strands the terminal state.
- [ ] **BRICK-04**: The worst-case gas composition in the column is derived FIRST (not sampled) and shown to hold under the 16.7M ceiling (target < 10M) — at minimum the subscriber-evict chunk + multi-day gap-backfill + terminal-jackpot composition (the V62-02 class) — with per-item marginal-gas-derived batch sizing.
- [ ] **BRICK-05**: The VRF-word-never-fulfilled and stalled-RNG conditions are proven recoverable — the retry / timeout and (honest) coordinator-rotation paths can always restore liveness; no input or external state can make the daily word permanently unobtainable.

### DELEGATE — Delegatecall Integrity

- [ ] **DELEGATE-01**: The storage layout of `DegenerusGame` and every one of the 13 delegatecall modules is proven compatible — each module's declared storage matches the Game slots it writes; no module can write a slot the Game uses for a different variable (silent corruption).
- [ ] **DELEGATE-02**: The nested-delegatecall paths (Mint / Lootbox → Boon) preserve `msg.value` and `msg.sender` correctly — the in-flight-`msg.value` behavior is verified to neither double-spend nor strand ETH, and `msg.sender`-derived authorization / credit resolves to the intended actor end-to-end.
- [ ] **DELEGATE-03**: The raw `delegatecall(msg.data)` afking dispatch is verified — selector routing, calldata forwarding, return-data handling, and revert-reason bubbling are correct; no selector collision or mis-dispatch is reachable.
- [ ] **DELEGATE-04**: Every thin Game dispatch stub correctly bubbles module reverts (no swallowed failure that leaves partial state committed) and correctly handles return data; a module revert never silently no-ops a state transition the Game assumes succeeded.
- [ ] **DELEGATE-05**: Module addresses / immutables and any init wiring are verified — the column cannot delegatecall a zero / unset / wrong module address, and no module is reachable as a direct external call that would execute against its own (empty) storage.

### CORRUPT — State-Corruption Invariants

- [x] **CORRUPT-01** ✅ HOLDS (420): Packed-slot integrity across the column — every packed storage write (the DEC-ALIAS class: terminal / offset-keyed level writes, packed day-result lanes, packed pool / credit slots) is proven not to alias or overflow into a neighbouring field under any reachable (level, day, offset) combination.
- [x] **CORRUPT-02** ✅ HOLDS (420): Write-after-write ordering across the multi-step advance / mint chain leaves no inconsistent intermediate that a reentrant or follow-on call can observe and exploit; the phase / level / day / pool / queue-index counters are mutually consistent at every external-call boundary.
- [x] **CORRUPT-03** ✅ HOLDS (420): Partial-failure atomicity — if any sub-step of a column transaction reverts, no earlier sub-step's state write survives in a way that corrupts the accounting (CEI / checked-math / revert-bubbling enforces all-or-nothing where required).
- [x] **CORRUPT-04** ✅ HOLDS (420): Reentrancy into the column mid-advance (via the synchronous external calls to FLIP / Coinflip / Vault / sDGNRS / Affiliate and any ETH transfer) cannot corrupt state or double-count — every external-call site in the column is checked for a reentrant re-entry that observes a half-updated invariant.
- [x] **CORRUPT-05** ✅ HOLDS+INFO-01 (420): The solvency / pool identities hold across every column path — `claimablePool == Σ(claimable + afking)` and the sDGNRS-backing identity are preserved by every mint / advance / jackpot / redemption / gameover path in the column.

### MIDRNG — Mid-Day RNG Edge Cases

- [x] **MIDRNG-01** ✅ HOLDS+LOW (421): The mid-day lootbox RNG swap / retry path (the stalled-RNG retry + mid-day swap commit) cannot brick or corrupt — a mid-day request that stalls can always be retried / resolved, and the retry cannot bind a box / ticket to the wrong (in-flight) word or strand the index.
- [x] **MIDRNG-02** ✅ FOUND+FIXED `73eb242a` (421): The mid-day partial-drain read slot (a partially-drained queue whose read slot still holds queued tickets) is proven consistent — a mid-day partial advance leaves the queue / index in a state the next advance resumes correctly, with no double-drain or skipped ticket.
- [x] **MIDRNG-03** ✅ HOLDS (421): Mid-day word binding — boxes / tickets / bets placed mid-day after a request bind to the live index / day, not the in-flight word, across gap-backfill and retry interleavings (the `RngIndexDrainBinding` concern, exercised on the column).

### GAMEOVER — Terminal-Branch Liveness

- [x] **GAMEOVER-01** ✅ HOLDS (422): The terminal decimator (`runTerminalDecimatorJackpot`, level keyed at `lvl+1` per the DEC-ALIAS fix) is proven to resolve without aliasing a live regular round and without a reachable revert that strands the terminal payout.
- [x] **GAMEOVER-02** ✅ HOLDS+INFO (422): The terminal jackpot (`runTerminalJackpot`) and `handleGameOverDrain` are proven to finalize for any reachable pre-gameover state (any pending pool, any winner-set size) within the gas ceiling, including the post-gameover claim path that also pays prepaid afking ETH. [worst-case ~7.2M<16.78M; FLIP-tombstone overflow boundary economically unreachable = INFO]
- [x] **GAMEOVER-03** ✅ HOLDS (422):: The gameOver-trigger transition itself cannot wedge — the conditions that set `gameOver` (`lastPurchaseDay` etc.) leave every downstream terminal entrypoint callable; no mid-gameover partial state blocks finalization.

### VRFSWAP — Honest Coordinator Rotation

- [ ] **VRFSWAP-01**: `updateVrfCoordinatorAndSub` under honest governance holds every freeze-relevant variable consistent — no rotation branch strands the lock, de-syncs `vrfRequestId` / `rngWordCurrent`, or leaves the daily word permanently unobtainable; an in-flight request at rotation time is either preserved or cleanly re-requested.
- [ ] **VRFSWAP-02**: A coordinator rotation performed while the game is mid-day / mid-request / stalled cannot brick liveness or corrupt the request↔word binding — the rotation + retry composition always restores a path to a fulfilled word and the correct day binds it.
- [ ] **VRFSWAP-03**: `rawFulfillRandomWords` requestId / coordinator validation is correct across a rotation — a stale (pre-rotation) coordinator or requestId cannot write a word, and the post-rotation coordinator's fulfillment lands on the intended day / index.

### MECH — Close the Mechanical-Net Gaps (test-only)

- [ ] **MECH-01**: A worst-case gas harness asserts every column transaction (advance composition, terminal finalization, max-batch mint) is < 16.7M, derived from the BRICK-04 worst-case branch (not typical seeds), wired so a regression that crosses the ceiling fails it.
- [ ] **MECH-02**: A delegatecall storage-layout regression oracle pins the Game↔module slot alignment (a `forge inspect` layout snapshot + assertion) so any future layout drift that would silently corrupt is caught.
- [ ] **MECH-03**: A state-invariant test (fuzz or targeted) asserts the BRICK liveness + CORRUPT solvency invariants across an advance / mint / gameover sequence — at minimum that `advanceGame` always progresses to settlement and `claimablePool == Σ` holds throughout.
- [ ] **MECH-04**: Any specific brick / corruption mutant surfaced during COLMAP / BRICK / DELEGATE / CORRUPT (a revert made permanent, a slot mis-aligned) is captured as a regression that the current suite is shown blind to, then closed.

### COUNCIL — Cross-Model Adjudication + Synthesis

- [ ] **COUNCIL-01**: The cross-model council (Gemini + Codex) runs as the primary finder over every COLMAP / BRICK / DELEGATE / CORRUPT / MIDRNG / GAMEOVER / VRFSWAP surface, seeded with the column map and the brick / corruption hypotheses.
- [ ] **COUNCIL-02**: Every candidate finding is adversarially verified (independent refutation; majority-refute kills it) before it is recorded as confirmed.
- [ ] **COUNCIL-03**: A canonical `audit/FINDINGS-v67.0.md` (+ HTML report) records confirmed findings, refutations, and by-design dispositions; any contract fix routes through the contract-commit approval gate; the milestone closure signal `MILESTONE_V67_AT_HEAD_<sha>` is recorded.

## v2 Requirements

Deferred — not in this milestone's roadmap.

### Features (post-audit)

- **SEED-001**: Century quest-streak shield grant — a contract feature; its own approval + re-audit. Explicitly out of this audit-only milestone.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Contract feature changes (incl. SEED-001) | Audit-only milestone on a byte-frozen subject; features are a separate cycle |
| Admin / governance malice | USER assumption = honest admin/governance; rotation liveness IS in scope, key-compromise / malicious-admin is not |
| Gas optimization | Security is the hard floor; no optimization that weakens an invariant; gas passes are their own track. (Gas is in scope here ONLY as the 16.7M brick ceiling, not as efficiency.) |
| Full RNG-freeze / manipulability re-audit | Just closed in v66 (0 findings); only the RNG paths that can BRICK or CORRUPT the column (MIDRNG / VRFSWAP / gameover-RNG) are revisited here |
| Pure economic / game-theory balance | Covered by v60/v63/v64; only solvency-identity preservation across column paths (CORRUPT-05) is in scope |
| Pushing any contract fix without review | Standing rule — manual diff review + approval before any `contracts/*.sol` commit/push |

## Traceability

Each requirement maps to exactly one phase. v67.0 phases continue 415 → 416. The 9-requirement EDGE cluster in the original proposal was split into three dedicated, independently-verifiable phases — 421 MIDRNG, 422 GAMEOVER, 423 VRFSWAP — so MECH shifts to 424 and COUNCIL to 425.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | 416 FOUND | Pending |
| FOUND-02 | 416 FOUND | Pending |
| COLMAP-01 | 417 COLMAP | Pending |
| COLMAP-02 | 417 COLMAP | Pending |
| COLMAP-03 | 417 COLMAP | Pending |
| COLMAP-04 | 417 COLMAP | Pending |
| BRICK-01 | 418 BRICK | Pending |
| BRICK-02 | 418 BRICK | Pending |
| BRICK-03 | 418 BRICK | Pending |
| BRICK-04 | 418 BRICK | Pending |
| BRICK-05 | 418 BRICK | Pending |
| DELEGATE-01 | 419 DELEGATE | Pending |
| DELEGATE-02 | 419 DELEGATE | Pending |
| DELEGATE-03 | 419 DELEGATE | Pending |
| DELEGATE-04 | 419 DELEGATE | Pending |
| DELEGATE-05 | 419 DELEGATE | Pending |
| CORRUPT-01 | 420 CORRUPT | Pending |
| CORRUPT-02 | 420 CORRUPT | Pending |
| CORRUPT-03 | 420 CORRUPT | Pending |
| CORRUPT-04 | 420 CORRUPT | Pending |
| CORRUPT-05 | 420 CORRUPT | Pending |
| MIDRNG-01 | 421 MIDRNG | Pending |
| MIDRNG-02 | 421 MIDRNG | Pending |
| MIDRNG-03 | 421 MIDRNG | Pending |
| GAMEOVER-01 | 422 GAMEOVER | Pending |
| GAMEOVER-02 | 422 GAMEOVER | Pending |
| GAMEOVER-03 | 422 GAMEOVER | Pending |
| VRFSWAP-01 | 423 VRFSWAP | Pending |
| VRFSWAP-02 | 423 VRFSWAP | Pending |
| VRFSWAP-03 | 423 VRFSWAP | Pending |
| MECH-01 | 424 MECH | Pending |
| MECH-02 | 424 MECH | Pending |
| MECH-03 | 424 MECH | Pending |
| MECH-04 | 424 MECH | Pending |
| COUNCIL-01 | 425 COUNCIL | Pending |
| COUNCIL-02 | 425 COUNCIL | Pending |
| COUNCIL-03 | 425 COUNCIL | Pending |

**Coverage:**
- v1 requirements: 37 total
- Mapped to phases: 37 ✓ (1 requirement → exactly 1 phase; no orphans, no duplicates)
- Unmapped: 0 ✓
- Phases: 10 (416 FOUND · 417 COLMAP · 418 BRICK · 419 DELEGATE · 420 CORRUPT · 421 MIDRNG · 422 GAMEOVER · 423 VRFSWAP · 424 MECH · 425 COUNCIL)

---
*Requirements defined: 2026-06-16 — grounded in a HEAD-scan of the spinal column (DegenerusGame + 13 delegatecall modules + synchronous callees). Phases finalized by the roadmapper: 2026-06-16.*
