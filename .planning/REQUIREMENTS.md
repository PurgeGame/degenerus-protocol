# Requirements: Degenerus Protocol — v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep

**Milestone:** v49.0 (started 2026-05-26)
**Audit baseline → subject:** v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` → v49.0 closure HEAD. Every cited `file:line` + the bounty/gas math MUST be re-attested vs the v48.0-closure HEAD before any patch.
**Scope source:** the milestone discussion (2026-05-26) + `.planning/research/SUMMARY.md` + the 4 research dimension docs.
**Posture:** ONE batched USER-APPROVED `contracts/*.sol` diff (router + advance-bounty rework + bounty re-peg + the folded no-cost micro-opts); HARD STOP at the commit boundary. Security/RNG-freeze floor over gas. Bounty stays minted FLIP CREDIT from the finite-pool / self-exclude / ETH-work-gate pattern.

---

## v49.0 Requirements

### Unified Keeper "Do-Work" Router (ROUTER)
- [ ] **ROUTER-01**: A keeper can call a single **PARAMETERLESS `doWork()`** entrypoint on `AfKing.sol` that performs exactly ONE keeper category of work per call and pays one gas-pegged bounty. `doWork()` takes NO `maxCount` — it determines its OWN fixed per-leg default batch internally (D-07 supersedes D-06; the `maxCount == 0` sentinel no longer exists). The standalone parametered **+ UNREWARDED** `autoOpen(uint256 count)` / `autoBuy(uint256 count)` stay as manual/emergency clears (RD-4: direct, non-router calls are unrewarded).
- [ ] **ROUTER-02**: `doWork` routes by priority — **`autoBuy` → advance-leg (new-day advance OR mid-day partial-drain ticket processing) → `autoOpen`** (RD-1: autoBuy runs first so subscriber boxes/tickets queue at day-open before advance requests the day's RNG → same-cycle reveal + same-day quest credit).
- [ ] **ROUTER-03**: The one-rewarded-category-per-call rule is enforced as a STRUCTURAL early-return (advance/open/buy bounties can never stack in one tx).
- [ ] **ROUTER-04**: `doWork` uses O(1) on-chain work-discovery predicates (advance-due incl. mid-day partial-drain / boxes-pending / buys-pending) — no unbounded scans. `boxesPending()` is **rngLock-aware** (RD-3: false during rngLock so the open leg no-ops during the freeze, but covers mid-day-resolved rounds whose word has landed); **buys-pending is TRUE during rngLock** (RD-2: autoBuy no longer aborts on rngLock; buys queue pre-entropy).
- [ ] **ROUTER-05**: `autoBuy` is refactored to an internal `_autoBuy` call (no new cross-contract money edge) **with the rngLock guard dropped (RD-2) and the bounty unified into `doWork` (RD-4)**; the KEEP-04 `bytes32("DGNRS")` affiliate passthrough (GAME-side `_batchPurchaseUnit`) survives the refactor. `autoResolve` is excluded from the router and stays a SEPARATE call — it is RENAMED to `degeneretteResolve` + its bounty RE-PEGGED per GAS-06 (the router-fold itself is architecturally blocked by the caller-supplied `(players[], betIds[])` requirement, which has no O(1) on-chain discovery).
- [ ] **ROUTER-06**: `doWork` signals "no work done" cleanly via a `NoWork()` revert (fires only when all 3 O(1) discovery predicates are empty; consistent with the existing no-buy anti-spam revert idiom), and never pays a bounty for no work.
- [x] **ROUTER-07**: The router's reentrancy disposition is decided at SPEC: **NO `nonReentrant` guard on `doWork`** (D-01), re-grounded on the unified single `creditFlip` — under RD-4 there is exactly ONE `creditFlip` in `doWork`, CEI-last, fed by legs that return raw counts/mult and never self-credit. Formal basis = keeper-never-a-payee + no untrusted ETH send (per-leg + single-`creditFlip` grep D-01a) + one-category structural early-return + single-`creditFlip`-last CEI ordering; the D-01b TST-02 double-pay regression stays as the empirical backstop.
- [ ] **ROUTER-08**: `autoBuy` is a NORMAL buy — DROP both rngLock guards: the AfKing autoBuy-entry guard (`:568`) AND the game-side `batchPurchase` rngLock pre-check (`:1737`); KEEP the `gameOver` check (`:1738`). (RD-2; Q1 RESOLVED SAFE — the guard was v46 batch-hygiene, NOT orphan-index defense; buying is freeze-safe by construction, orphan defended on the resolution side. Q5: `batchPurchase` is AF_KING-gated with sole external caller `AfKing.sol:821` → no other dependent loses freeze protection.)
- [ ] **ROUTER-09**: BLOCK `autoOpen` during rngLock (RD-3: `boxesPending()` rngLock-aware) AND drop the `autoOpen` try/catch + add an entry-gate `if (rngLocked() || _livenessTriggered()) return;` + make `_autoOpenBox` internal (RD-5). Basis: the open path has EXACTLY TWO revert sources — rngLock + the deliberate terminal-jackpot liveness control (`contracts/storage/DegenerusGameStorage.sol:571`); the entry-gate replicates both pre-loop → brick-proof, terminal-jackpot guard intact for direct opens (USER-accepted frozen-contract trade; the entry-gate is MANDATORY if the try/catch goes).
- [ ] **ROUTER-10**: UNIFY the bounty into `doWork` (RD-4) — pull the 3 advance + the autoOpen (`:1676`) + the autoBuy (`:846`) in-callee `creditFlip`s into ONE `creditFlip` in `doWork` (CEI-last); legs return their raw reward basis and NEVER self-credit; direct (non-router) calls become unrewarded. Reverses the original per-leg-bounty model (old R4). Requires signature changes to `autoOpen`/`autoBuy` + `IDegenerusGame`.

### advanceGame Bounty Rework (ADV)
- [ ] **ADV-01**: The 3 advance-bounty `creditFlip(caller,…)` sites in `DegenerusGameAdvanceModule.sol` (`:189`/`:225`/`:468`) are removed; standalone `advanceGame()` pays no bounty.
- [ ] **ADV-02**: `advanceGame` returns `(uint8 mult, bool rewardable)` — the stall multiplier + a rewardable flag — so the router pays the re-homed bounty from the multiplier's canonical day-epoch home (no recompute in a money path). `mult` = the stall ladder (`1/2/4/6`) on the NEW-DAY path ONLY; **the mid-day partial-drain returns `mult = 1`** (no escalation, ADV-05/D-07); the gameover path `mult = 1`. Decoded in the `DegenerusGame.advanceGame` wrapper (`:275`/`:283`, currently discards the delegatecall `data`).
- [ ] **ADV-03**: Standalone `advanceGame()` stays fully functional as an unrewarded liveness fallback; a guaranteed free-fallback caller path is identified so re-homing does not create a single-point liveness risk.
- [x] **ADV-04**: The router's advance-consume reads only FROZEN VRF-window state even when fired in the same tx as `autoOpen`/`autoBuy` — the player-controllable `totalFlipReversals` nudge stays frozen (v45 freeze invariant preserved).
- [ ] **ADV-05**: Mid-day partial-drain ticket processing (`day == dailyIdx` but tickets not fully processed) is router-rewardable advance-leg work.

### Bounty Recalibration + Worst-Case Gas Sweep (GAS)
- [x] **GAS-01**: Worst-case-first marginal gas is derived per keeper category (`autoBuy`/`autoOpen`/`degeneretteResolve`) + the router overhead (theoretical worst case before measurement). This derivation sizes the D-07 flat-per-tx model: the per-category max-laden gas at 0.5 gwei fixes the `1×` base unit + the `1 / 1.5 / 2` per-category ratios + the open `KNEE (~5)`. (`doWork()` is parameterless — D-07 supersedes D-06's `maxCount==0` default-count sizing; the fixed per-leg default batch is intrinsic to `doWork`.)
- [ ] **GAS-02**: All keeper bounties are re-pegged to **flat-per-tx per-category** at break-even 0.5 gwei (BURNIE-denominated): advance `2× × mult`, buy `1.5×`, open `1×` pro-rated below the knee (`1× × min(opened, KNEE)/KNEE`). Pegged to the per-category max-laden MARGINAL, never a per-call total (the CR-01 self-crank-faucet rule); the open knee kills the small-batch corner.
- [x] **GAS-03**: The single day-start stall epoch is **satisfied by DELETION — advance is the sole stall epoch** (D-03 dissolved by D-07: dropping the autoBuy stall multiplier deletes AfKing's autoBuy stall ladder + its absolute-day epoch, leaving the `AdvanceModule` GAME-day epoch as the only escalating path; there are no two epochs to collapse).
- [ ] **GAS-04**: The stall multiplier (1/2/4/6) is kept **ADVANCE-ONLY** (only the advance leg escalates; the autoBuy stall ladder is deleted per D-07); any ceiling extension for extreme stalls is added ABOVE the 2h tier (never lowering existing thresholds) and is capped against the finite faucet pool.
- [ ] **GAS-05**: A WR-01-style round-trip guard proves no positive-EV self-crank loop **under the flat-per-tx model** (esp. the open small-batch + low-gas corner: the per-box reward below the knee `1×/KNEE` ≤ a one-box tx's 0.5-gwei gas → a tiny mid-day open is −EV); the faucet bound holds, self-exclude + ETH-work-gate intact.
- [ ] **GAS-06**: `autoResolve` is RENAMED to `degeneretteResolve` (+ internal `_autoResolveBet`→`_degeneretteResolveBet`, interfaces, tests) and its bounty re-pegged from per-item break-even to a flat literal ~1 BURNIE flip-credit per tx (count-independent), gated at ≥3 successfully-resolved NON-WWXRP bets (revert `NoWork()` on zero work; the 1–2-resolved case → resolved but UNPAID, lean = do-not-revert so a trailing tail is never stranded — SPEC/IMPL confirms). Anti-exploit basis (corrected — NOT the 0.5-gwei peg ref): the keeper pays REAL tx gas (base + ≥3 resolutions + overhead) every call while ~1 BURNIE illiquid flip-credit is worth ≤ `mintPrice/1000` ETH (≤0.00024 ETH even at the 0.24-ETH milestone price) → every qualifying tx is a net loss at any realistic gas price → no positive-EV farm; the ≥3 gate widens the margin. WWXRP stays excluded (AUTO-04 — the ≥3 count is non-WWXRP only); AUTO-02 probe + per-item isolation + self-resolve (REW-04) preserved; kept a SEPARATE call (NOT in the router). GAS sanity check (NOT a blocker): confirm ~1 BURNIE stays below real 3-resolution gas across the low-gas/high-mintPrice corner factoring flip-credit illiquidity; only lower the constant or add a scaled gate if a realistic corner flips positive. (SPEC D-05f: verify losing-bet resolution is not required by any invariant before dropping the break-even incentive.)

### No-Cost Gas Micro-Optimizations (GASOPT)
- [ ] **GASOPT-01**: `DegenerusGameMintModule.sol` hoists `mapping(address=>uint40) storage owedMap = ticketsOwedPacked[rk]` in both `processTicketBatch` (`:671`) and the resolve/future loop (`:398`) — `rk` is loop-invariant; behavior-identical.
- [ ] **GASOPT-02**: **SUBSUMED by GASOPT-03.** (Originally: `AfKing.autoBuy` hoists `IGame.claimableWinningsOf(player)` to one call per iteration. GASOPT-03's batched game-side keeper read is the superset of this per-iteration hoist — the per-player STATICCALL hoist is folded into the batched read. No separate work item.)
- [ ] **GASOPT-03**: NEW game-side `batchPurchaseForKeeper` / `keeperSnapshot` collapsing the two per-player `claimableWinningsOf(player)` STATICCALLs (`AfKing:691` + `:722`) into ONE batched call (~2-3k/player). New function + interface surface. SUBSUMES GASOPT-02. Behavior-identical (same values, fewer cross-contract calls).
- [ ] **GASOPT-04**: DROP the per-player `AutoBought` event (decl `:171`, emit `:785`, ~1.5k/player); the no-double-buy oracle migrates to the existing `lastAutoBoughtDay` storage stamp (`:81`/`:784`). The event-removal AND the test-oracle migration land TOGETHER (the suite's `AutoBought`-keyed assertions break the moment the event is gone). The no-double-buy invariant `_countAutoBoughtFor(sub)==1` is re-expressed in `lastAutoBoughtDay` + pool/balance-delta terms WITHOUT weakening SAFE-03 / H-CANCEL-SWAP. (No off-chain/frontend consumer — the USER owns the keeper.)
- [ ] **GASOPT-05**: REMOVE the per-iteration `isOperatorApproved(player, AfKing)` check (`:676`, ~2.8k/player) — the SUB is the consent unit (revoke = `setDailyQuantity(0)` → tombstone-skip; OPEN-E "consent-gate-at-subscribe + trust-the-sub"); KEEP the subscribe-time `isOperatorApproved(fundingSource, subscriber)` gate (`:401`). **BLOCKING CONDITION:** the Phase 333 SWEEP must re-attest the 4 OPEN-E protections hold WITHOUT `:676` BEFORE closure; if it fails, this removal is REVERTED before the milestone ships.

### Test Proofs (TST)
- [ ] **TST-01**: Freeze-invariant fuzz (extending the v43 `RngLockDeterminism` harness) proves the router advance-consume reads only frozen state mid-tx (the `totalFlipReversals` class). ADDS (the redesign, Q4): autoBuy-during-rngLock SAFE; autoOpen-blocked-during-rngLock + NO marooned boxes (RD-3/RD-5); unified-bounty one-category + no-double-pay (the single `creditFlip` in `doWork`).
- [ ] **TST-02**: A one-rewarded-category-per-tx assertion (no bounty-stacking) + a router→game→`creditFlip` reentrancy double-pay regression (the D-01b backstop proving the ROUTER-07 no-guard disposition — legs structurally cannot credit, only `doWork` credits once after the early-return). Plus the parameterless-`doWork()` default-batch proof (D-07): `doWork()` does its fixed per-leg default batch and does NOT OOG in the common case (a backlog larger than one batch leaves a remainder for the next call), with the standalone parametered + UNREWARDED `autoOpen(count)`/`autoBuy(count)` emergency escapes exercised.
- [ ] **TST-03**: `advanceGame` is unrewarded standalone but rewarded via the router; the GASOPT micro-opts are proven same-results (gas-only).
- [ ] **TST-04**: Full-suite regression is NON-WIDENING vs the v48.0 baseline (net-zero new regression; enumerated-red-set guard). INCLUDES the GASOPT-04 test-oracle migration (`AutoBought` event → `lastAutoBoughtDay` storage / pool-balance-delta) keeping the suite net-zero vs the v48 baseline — the no-double-buy invariant re-expressed in storage terms WITHOUT weakening SAFE-03 / H-CANCEL-SWAP.
- [ ] **TST-05**: The `degeneretteResolve` rename + re-peg (GAS-06) is proven — flat literal ~1 BURNIE per tx (NOT per-item), the ≥3-resolution pay-gate, revert-on-no-work (zero resolved), WWXRP excluded from BOTH the gate count and the reward, and byte-identical resolution RESULTS vs the per-item path (rename + bounty-shape change only, no payout/RNG change).

### Gas + Adversarial Security Sweep (SWEEP)
- [ ] **SWEEP-01**: A 3-skill adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`) is run against the frozen v49 subject, charged with: advance-timing MEV / same-tx bundling of advance-consume + buy/open, composed reentrancy (router→game→creditFlip), faucet-drain re-attestation on the unified surface, bounty-stacking, stall-multiplier abuse, and the unrewarded-advance liveness backstop. Every elevation passes the skeptic dual-gate.
- [ ] **SWEEP-02**: The delta-audit attests NON-WIDENING vs the v48.0 baseline `0cc5d10f` — every `contracts/`+`test/` diff is attributable to a v49 work item.
- [ ] **SWEEP-03**: `audit/FINDINGS-v49.0.md` is authored (9-section, mirroring v44/v46/v47/v48), with any findings adjudicated or deferred per USER direction.

### Cross-Cutting — SPEC Reconciliation + IMPL + TERMINAL (BATCH)
- [x] **BATCH-01**: SPEC design-lock — lock the 4 structural invariants (one-category structural early-return / frozen advance-consume / guaranteed free fallback caller / single day-start epoch), settle the shared signatures (`advanceGame` return shape, `doWork` signature, the discovery views), and grep-attest every cited `file:line` vs the v48.0 HEAD before any patch.
- [ ] **BATCH-02**: The ONE batched USER-APPROVED `contracts/*.sol` diff is applied in producer-before-consumer order (AdvanceModule bounty-removal + `(mult,rewardable)` return → Game wrapper decode + rngLock-aware views + autoOpen RD-3/RD-5 rework + `degeneretteResolve` rename + GASOPT-03 `keeperSnapshot` → interfaces → AfKing parameterless `doWork` router + `_autoBuy` refactor + RD-2 drop-guard + unified flat-per-tx bounty + GASOPT-04/05 → MintModule GASOPT-01 + tests rename-fixes + GASOPT-04 oracle migration); HARD STOP at the commit boundary (locally compiled/tested, never committed without explicit user hand-review).
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

**36/36 v49.0 requirements mapped to exactly one phase across 329–333 — 0 orphaned, 0 duplicated.** Phases: 329 SPEC · 330 IMPL · 331 GAS · 332 TST · 333 TERMINAL. Center-of-gravity assignment (design-at-SPEC / build-at-IMPL / calibrate-at-GAS / prove-at-TST / sweep+attest-at-TERMINAL); the TERMINAL closure (BATCH-03 + SWEEP-01/02/03) re-attests the full set. (29 at roadmap creation + GAS-06/TST-05 added 2026-05-26 for the rename/re-peg → 31; then the keeper-router REDESIGN re-SPEC 2026-05-26 added ROUTER-08/09/10 + GASOPT-03/04/05 (GASOPT-02 SUBSUMED into GASOPT-03, not counted) → 36 active reqs.)

| Requirement | Phase | Status |
|-------------|-------|--------|
| ROUTER-01 | Phase 330 (IMPL) | Pending |
| ROUTER-02 | Phase 330 (IMPL) | Pending |
| ROUTER-03 | Phase 330 (IMPL) | Pending |
| ROUTER-04 | Phase 330 (IMPL) | Pending |
| ROUTER-05 | Phase 330 (IMPL) | Pending |
| ROUTER-06 | Phase 330 (IMPL) | Pending |
| ROUTER-07 | Phase 329 (SPEC) | Complete |
| ROUTER-08 | Phase 330 (IMPL) | Pending |
| ROUTER-09 | Phase 330 (IMPL) | Pending |
| ROUTER-10 | Phase 330 (IMPL) | Pending |
| ADV-01 | Phase 330 (IMPL) | Pending |
| ADV-02 | Phase 330 (IMPL) | Pending |
| ADV-03 | Phase 330 (IMPL) | Pending |
| ADV-04 | Phase 329 (SPEC) | Complete |
| ADV-05 | Phase 330 (IMPL) | Pending |
| GAS-01 | Phase 331 (GAS) | Complete |
| GAS-02 | Phase 331 (GAS) | Pending |
| GAS-03 | Phase 329 (SPEC) | Complete |
| GAS-04 | Phase 331 (GAS) | Pending |
| GAS-05 | Phase 331 (GAS) | Pending |
| GAS-06 | Phase 331 (GAS) | Pending |
| GASOPT-01 | Phase 330 (IMPL) | Pending |
| GASOPT-02 | Phase 330 (IMPL) | SUBSUMED by GASOPT-03 (not counted) |
| GASOPT-03 | Phase 330 (IMPL) | Pending |
| GASOPT-04 | Phase 330 (IMPL) | Pending |
| GASOPT-05 | Phase 330 (IMPL) | Pending |
| TST-01 | Phase 332 (TST) | Pending |
| TST-02 | Phase 332 (TST) | Pending |
| TST-03 | Phase 332 (TST) | Pending |
| TST-04 | Phase 332 (TST) | Pending |
| TST-05 | Phase 332 (TST) | Pending |
| SWEEP-01 | Phase 333 (TERMINAL) | Pending |
| SWEEP-02 | Phase 333 (TERMINAL) | Pending |
| SWEEP-03 | Phase 333 (TERMINAL) | Pending |
| BATCH-01 | Phase 329 (SPEC) | Complete |
| BATCH-02 | Phase 330 (IMPL) | Pending |
| BATCH-03 | Phase 333 (TERMINAL) | Pending |

**Per-phase count:** 329 SPEC: 4 (BATCH-01, ROUTER-07, ADV-04, GAS-03) · 330 IMPL: 18 (ROUTER-01/02/03/04/05/06/08/09/10, ADV-01/02/03/05, GASOPT-01/03/04/05, BATCH-02 — GASOPT-02 SUBSUMED, not counted) · 331 GAS: 5 (GAS-01/02/04/05/06) · 332 TST: 5 (TST-01..05) · 333 TERMINAL: 4 (SWEEP-01/02/03, BATCH-03). **Total = 36** (4 + 18 + 5 + 5 + 4).

**Note:** milestone-wide "uncovered" warnings (§13e-style) are EXPECTED false alarms — each phase owns only its slice; SWEEP-01/02/03 + BATCH-03 re-attest the full 36-requirement set at TERMINAL (same class as the v47/v48 roadmaps).

*Last updated: 2026-05-26 — v49.0 traceability filled at roadmap creation (29 reqs / 7 categories: ROUTER 7 · ADV 5 · GAS 5 · GASOPT 2 · TST 4 · SWEEP 3 · BATCH 3 → phases 329–333), then GAS-06 + TST-05 added (Phase 329 discussion, 2026-05-26) for the `autoResolve`→`degeneretteResolve` rename + flat ~1-BURNIE "lose" bounty re-peg (≥3-gate) → 31 reqs (GAS 6 · TST 5). **Then the keeper-router REDESIGN re-SPEC (2026-05-26, after the 330-07 pivot) reworded ROUTER-01/02/04/05 + ADV-02 + GAS-02/03/04/05 + TST-01/02/04 and REGISTERED ROUTER-08/09/10 (RD-2 drop-guards / RD-3+RD-5 autoOpen-block+entry-gate / RD-4 unify-bounty) + GASOPT-03/04/05 (batched keeper read [SUBSUMES GASOPT-02] / drop AutoBought + oracle migration / drop per-iter isOperatorApproved), all homed to Phase 330 IMPL → 36 active reqs (ROUTER 10 · ADV 5 · GAS 6 · GASOPT 4-active+02-subsumed · TST 5 · SWEEP 3 · BATCH 3). D-06 SUPERSEDED by D-07 parameterless `doWork()` (no `maxCount` sentinel).** Statuses flip to Complete as phases close; all 36 re-attested at the Phase 333 closure.*
