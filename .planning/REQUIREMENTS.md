# Requirements: Degenerus Protocol — v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep

**Milestone:** v49.0 (started 2026-05-26)
**Audit baseline → subject:** v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` → v49.0 closure HEAD. Every cited `file:line` + the bounty/gas math MUST be re-attested vs the v48.0-closure HEAD before any patch.
**Scope source:** the milestone discussion (2026-05-26) + `.planning/research/SUMMARY.md` + the 4 research dimension docs.
**Posture:** ONE batched USER-APPROVED `contracts/*.sol` diff (router + advance-bounty rework + bounty re-peg + the folded no-cost micro-opts); HARD STOP at the commit boundary. Security/RNG-freeze floor over gas. Bounty stays minted FLIP CREDIT from the finite-pool / self-exclude / ETH-work-gate pattern.

---

## v49.0 Requirements

### Unified Keeper "Do-Work" Router (ROUTER)
- [ ] **ROUTER-01**: A keeper can call a single `doWork(maxCount)` entrypoint on `AfKing.sol` that performs exactly ONE keeper category of work per call and pays one gas-pegged bounty. `maxCount == 0` is a sentinel resolving to a FIXED per-leg default count (≈ a ~10M-gas budget ÷ avg-marginal-per-item; the count-bounded `autoOpen`/`_autoBuy` legs only — advance is self-bounded), so a naive keeper can call `doWork(0)` for a sensible budget of work without computing pending counts; worst-case OOG is a clean state-reverting revert + manual smaller-`maxCount` retry (SPEC decision D-06).
- [ ] **ROUTER-02**: `doWork` routes by priority — advance-leg (new-day advance OR mid-day partial-drain ticket processing) → `autoOpen` → `autoBuy`.
- [ ] **ROUTER-03**: The one-rewarded-category-per-call rule is enforced as a STRUCTURAL early-return (advance/open/buy bounties can never stack in one tx).
- [ ] **ROUTER-04**: `doWork` uses O(1) on-chain work-discovery predicates (advance-due incl. mid-day partial-drain / boxes-pending / buys-pending) — no unbounded scans.
- [ ] **ROUTER-05**: `autoBuy` is refactored to an internal `_autoBuy` call (no new cross-contract money edge); `autoResolve` is excluded from the router and stays a SEPARATE call — it is RENAMED to `degeneretteResolve` + its bounty RE-PEGGED per GAS-06 (the router-fold itself is architecturally blocked by the caller-supplied `(players[], betIds[])` requirement, which has no O(1) on-chain discovery).
- [ ] **ROUTER-06**: `doWork` signals "no work done" cleanly (consistent with the existing no-buy anti-spam revert; exact form decided at SPEC), and never pays a bounty for no work.
- [ ] **ROUTER-07**: The router's reentrancy disposition is decided at SPEC (guard vs proven composed-CEI), defaulting to a guard per the security floor.

### advanceGame Bounty Rework (ADV)
- [ ] **ADV-01**: The 3 advance-bounty `creditFlip(caller,…)` sites in `DegenerusGameAdvanceModule.sol` (`:189`/`:225`/`:468`) are removed; standalone `advanceGame()` pays no bounty.
- [ ] **ADV-02**: `advanceGame` returns the stall multiplier + a rewardable flag so the router pays the re-homed bounty from the multiplier's canonical day-epoch home (no recompute in a money path).
- [ ] **ADV-03**: Standalone `advanceGame()` stays fully functional as an unrewarded liveness fallback; a guaranteed free-fallback caller path is identified so re-homing does not create a single-point liveness risk.
- [ ] **ADV-04**: The router's advance-consume reads only FROZEN VRF-window state even when fired in the same tx as `autoOpen`/`autoBuy` — the player-controllable `totalFlipReversals` nudge stays frozen (v45 freeze invariant preserved).
- [ ] **ADV-05**: Mid-day partial-drain ticket processing (`day == dailyIdx` but tickets not fully processed) is router-rewardable advance-leg work.

### Bounty Recalibration + Worst-Case Gas Sweep (GAS)
- [ ] **GAS-01**: Worst-case-first marginal gas is derived per keeper category (`autoBuy`/`autoOpen`/`autoResolve`) + the router overhead (theoretical worst case before measurement). This derivation ALSO sizes the D-06 `maxCount==0` default: the AVG marginal-per-item fixes each per-leg `DEFAULT_*_COUNT = floor(~10M ÷ avg)`, and the worst-case marginal fixes the headroom margin (≈3× vs the ~30M block limit).
- [ ] **GAS-02**: All keeper bounties are re-pegged to break-even at 0.5 gwei (BURNIE-denominated) using the per-item MARGINAL, never a per-call total (the CR-01 self-crank-faucet rule).
- [ ] **GAS-03**: The stall multiplier uses a single unified day-start epoch (collapsing the differing `AfKing` `today*1days+82620` vs `AdvanceModule` `(day-1+DEPLOY_DAY_BOUNDARY)*1days+82620` epochs).
- [ ] **GAS-04**: The stall multiplier (1/2/4/6) is kept; any ceiling extension for extreme stalls is added ABOVE the 2h tier (never lowering existing thresholds) and is capped against the finite faucet pool.
- [ ] **GAS-05**: A WR-01-style round-trip guard proves no positive-EV self-crank loop under the unified router (faucet bound holds; self-exclude + ETH-work-gate intact).
- [ ] **GAS-06**: `autoResolve` is RENAMED to `degeneretteResolve` (+ internal `_autoResolveBet`→`_degeneretteResolveBet`, interfaces, tests) and its bounty re-pegged from per-item break-even to a flat literal ~1 BURNIE flip-credit per tx (count-independent), gated at ≥3 successfully-resolved NON-WWXRP bets (revert `NoWork()` on zero work; the 1–2-resolved case → resolved but UNPAID, lean = do-not-revert so a trailing tail is never stranded — SPEC/IMPL confirms). Anti-exploit basis (corrected — NOT the 0.5-gwei peg ref): the keeper pays REAL tx gas (base + ≥3 resolutions + overhead) every call while ~1 BURNIE illiquid flip-credit is worth ≤ `mintPrice/1000` ETH (≤0.00024 ETH even at the 0.24-ETH milestone price) → every qualifying tx is a net loss at any realistic gas price → no positive-EV farm; the ≥3 gate widens the margin. WWXRP stays excluded (AUTO-04 — the ≥3 count is non-WWXRP only); AUTO-02 probe + per-item isolation + self-resolve (REW-04) preserved; kept a SEPARATE call (NOT in the router). GAS sanity check (NOT a blocker): confirm ~1 BURNIE stays below real 3-resolution gas across the low-gas/high-mintPrice corner factoring flip-credit illiquidity; only lower the constant or add a scaled gate if a realistic corner flips positive. (SPEC D-05f: verify losing-bet resolution is not required by any invariant before dropping the break-even incentive.)

### No-Cost Gas Micro-Optimizations (GASOPT)
- [ ] **GASOPT-01**: `DegenerusGameMintModule.sol` hoists `mapping(address=>uint40) storage owedMap = ticketsOwedPacked[rk]` in both `processTicketBatch` (`:671`) and the resolve/future loop (`:398`) — `rk` is loop-invariant; behavior-identical.
- [ ] **GASOPT-02**: `AfKing.autoBuy` hoists `IGame.claimableWinningsOf(player)` to one call per iteration (today `:691` + `:722`), preserving the existing laziness (only when `reinvestPct>0 || FLAG_DRAIN_FIRST`); behavior-identical.

### Test Proofs (TST)
- [ ] **TST-01**: Freeze-invariant fuzz (extending the v43 `RngLockDeterminism` harness) proves the router advance-consume reads only frozen state mid-tx (the `totalFlipReversals` class).
- [ ] **TST-02**: A one-rewarded-category-per-tx assertion (no bounty-stacking) + a router→game→`creditFlip` reentrancy double-pay regression. Plus the D-06 `doWork(0)` default-count proof: the fixed default does a budget of work and does NOT OOG in the common case (a backlog larger than one budget leaves a remainder for the next call; `autoBuy(0)`/`autoOpen(0)` no longer revert/no-op under the default path), with the manual smaller-`maxCount` fallback exercised.
- [ ] **TST-03**: `advanceGame` is unrewarded standalone but rewarded via the router; the GASOPT micro-opts are proven same-results (gas-only).
- [ ] **TST-04**: Full-suite regression is NON-WIDENING vs the v48.0 baseline (net-zero new regression; enumerated-red-set guard).
- [ ] **TST-05**: The `degeneretteResolve` rename + re-peg (GAS-06) is proven — flat literal ~1 BURNIE per tx (NOT per-item), the ≥3-resolution pay-gate, revert-on-no-work (zero resolved), WWXRP excluded from BOTH the gate count and the reward, and byte-identical resolution RESULTS vs the per-item path (rename + bounty-shape change only, no payout/RNG change).

### Gas + Adversarial Security Sweep (SWEEP)
- [ ] **SWEEP-01**: A 3-skill adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) is run against the frozen v49 subject, charged with: advance-timing MEV / same-tx bundling of advance-consume + buy/open, composed reentrancy (router→game→creditFlip), faucet-drain re-attestation on the unified surface, bounty-stacking, stall-multiplier abuse, and the unrewarded-advance liveness backstop. Every elevation passes the skeptic dual-gate.
- [ ] **SWEEP-02**: The delta-audit attests NON-WIDENING vs the v48.0 baseline `0cc5d10f` — every `contracts/`+`test/` diff is attributable to a v49 work item.
- [ ] **SWEEP-03**: `audit/FINDINGS-v49.0.md` is authored (9-section, mirroring v44/v46/v47/v48), with any findings adjudicated or deferred per USER direction.

### Cross-Cutting — SPEC Reconciliation + IMPL + TERMINAL (BATCH)
- [ ] **BATCH-01**: SPEC design-lock — lock the 4 structural invariants (one-category structural early-return / frozen advance-consume / guaranteed free fallback caller / single day-start epoch), settle the shared signatures (`advanceGame` return shape, `doWork` signature, the discovery views), and grep-attest every cited `file:line` vs the v48.0 HEAD before any patch.
- [ ] **BATCH-02**: The ONE batched USER-APPROVED `contracts/*.sol` diff is applied in producer-before-consumer order (AdvanceModule bounty-removal + return → Game wrapper/views → interfaces → AfKing router/`_autoBuy`/re-peg/micro-opts); HARD STOP at the commit boundary (locally compiled/tested, never committed without explicit user hand-review).
- [ ] **BATCH-03**: TERMINAL closure — re-attest all v49.0 requirements at closure and apply the closure flip (`MILESTONE_V49_AT_HEAD_<sha>` + the atomic ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flip + chmod 444 the findings).

---

## Out of Scope (v49.0)

- **`autoResolve`/`degeneretteResolve` FOLDED INTO the on-chain router** — the router-fold is out (architecturally blocked: it needs caller-supplied `(players[], betIds[])`, no O(1) discovery; router = buy/open/advance only; the unified "one button" is a frontend concern). NOTE: the rename `autoResolve`→`degeneretteResolve` + the flat ~1-BURNIE "lose" re-peg (≥3-gate) ARE in scope (GAS-06 + TST-05) — only the router-fold is excluded.
- **Gas opts that trade an invariant** — the `Sub` memory-snapshot/write-back-at-end pattern (breaks the guard-less CEI + loses early-`continue` writes + collides with swap-pop), and the `batchPurchase` "trusted-batch" try/catch bypass (the per-slice try/catch IS the keeper isolation invariant). REJECTED in the 2026-05-26 scavenger review.
- **`1 ether - decayN` unchecked** — DEFERRED pending a `_wadPow ≤ WAD including rounding` proof (catastrophic underflow if it can round above WAD); revisit only if proven free.
- **SWAP cash-share ≤40% tighten** — the v48 advisory; USER accepted ≤60% as canonical. Revisit only if explicitly requested.
- **Standing profit-margin bounty** — break-even + stall escalation is the chosen liveness lever (research: a minted-BURNIE premium gets bid to ~zero in gas under competition and is pure dilution).
- **External keeper network** (Chainlink Automation / Gelato / Keep3r) — off-chain-network + funded-registry models contradict the permissionless self-serve, in-protocol-BURNIE-funded design.
- **Off-chain indexer / webpage** — separate frontend track.
- **Any non-keeper contract surface** — the sweep is scoped to the AfKing keeper subsystem + the router + advance.

---

## Future Requirements (deferred, not this milestone)

- Extended stall-multiplier tiers beyond the GAS-sized ceiling, if deep-stall analysis warrants more than the v49 extension.
- The `1 ether - decayN` unchecked hardening (pending the `_wadPow` rounding proof).

---

## Traceability

**31/31 v49.0 requirements mapped to exactly one phase across 329–333 — 0 orphaned, 0 duplicated.** Phases: 329 SPEC · 330 IMPL · 331 GAS · 332 TST · 333 TERMINAL. Center-of-gravity assignment (design-at-SPEC / build-at-IMPL / calibrate-at-GAS / prove-at-TST / sweep+attest-at-TERMINAL); the TERMINAL closure (BATCH-03 + SWEEP-01/02/03) re-attests the full set. (29 at roadmap creation + GAS-06/TST-05 added 2026-05-26 for the `autoResolve`→`degeneretteResolve` rename + flat ~1-BURNIE re-peg.)

| Requirement | Phase | Status |
|-------------|-------|--------|
| ROUTER-01 | Phase 330 (IMPL) | Pending |
| ROUTER-02 | Phase 330 (IMPL) | Pending |
| ROUTER-03 | Phase 330 (IMPL) | Pending |
| ROUTER-04 | Phase 330 (IMPL) | Pending |
| ROUTER-05 | Phase 330 (IMPL) | Pending |
| ROUTER-06 | Phase 330 (IMPL) | Pending |
| ROUTER-07 | Phase 329 (SPEC) | Pending |
| ADV-01 | Phase 330 (IMPL) | Pending |
| ADV-02 | Phase 330 (IMPL) | Pending |
| ADV-03 | Phase 330 (IMPL) | Pending |
| ADV-04 | Phase 329 (SPEC) | Pending |
| ADV-05 | Phase 330 (IMPL) | Pending |
| GAS-01 | Phase 331 (GAS) | Pending |
| GAS-02 | Phase 331 (GAS) | Pending |
| GAS-03 | Phase 329 (SPEC) | Pending |
| GAS-04 | Phase 331 (GAS) | Pending |
| GAS-05 | Phase 331 (GAS) | Pending |
| GAS-06 | Phase 331 (GAS) | Pending |
| GASOPT-01 | Phase 330 (IMPL) | Pending |
| GASOPT-02 | Phase 330 (IMPL) | Pending |
| TST-01 | Phase 332 (TST) | Pending |
| TST-02 | Phase 332 (TST) | Pending |
| TST-03 | Phase 332 (TST) | Pending |
| TST-04 | Phase 332 (TST) | Pending |
| TST-05 | Phase 332 (TST) | Pending |
| SWEEP-01 | Phase 333 (TERMINAL) | Pending |
| SWEEP-02 | Phase 333 (TERMINAL) | Pending |
| SWEEP-03 | Phase 333 (TERMINAL) | Pending |
| BATCH-01 | Phase 329 (SPEC) | Pending |
| BATCH-02 | Phase 330 (IMPL) | Pending |
| BATCH-03 | Phase 333 (TERMINAL) | Pending |

**Per-phase count:** 329 SPEC: 4 (BATCH-01, ROUTER-07, ADV-04, GAS-03) · 330 IMPL: 13 (ROUTER-01..06, ADV-01/02/03/05, GASOPT-01/02, BATCH-02) · 331 GAS: 5 (GAS-01/02/04/05/06) · 332 TST: 5 (TST-01..05) · 333 TERMINAL: 4 (SWEEP-01/02/03, BATCH-03). **Total = 31.**

**Note:** milestone-wide "uncovered" warnings (§13e-style) are EXPECTED false alarms — each phase owns only its slice; SWEEP-01/02/03 + BATCH-03 re-attest the full 31-requirement set at TERMINAL (same class as the v47/v48 roadmaps).

*Last updated: 2026-05-26 — v49.0 traceability filled at roadmap creation (29 reqs / 7 categories: ROUTER 7 · ADV 5 · GAS 5 · GASOPT 2 · TST 4 · SWEEP 3 · BATCH 3 → phases 329–333), then GAS-06 + TST-05 added (Phase 329 discussion, 2026-05-26) for the `autoResolve`→`degeneretteResolve` rename + flat ~1-BURNIE "lose" bounty re-peg (≥3-gate) → 31 reqs (GAS 6 · TST 5). Statuses flip to Complete as phases close; all 31 re-attested at the Phase 333 closure. Then SPEC decision D-06 (the `doWork(maxCount==0)` fixed gas-budget-sized default count; user 2026-05-26) was folded as a REFINEMENT of the existing ROUTER-01 (IMPL) + GAS-01 (calibration) + TST-02 (proof) — NO new REQ-IDs minted (count stays 31), since it refines the already-in-scope `doWork(maxCount)` signature rather than adding a separate function.*
