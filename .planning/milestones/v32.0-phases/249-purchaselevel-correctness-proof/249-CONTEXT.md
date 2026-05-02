# Phase 249: purchaseLevel Correctness Proof — Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove `purchaseLevel` (local stack variable bound at `contracts/modules/DegenerusGameAdvanceModule.sol:185` via `(lastPurchase && rngLockedFlag) ? lvl : lvl + 1`) can never be 0 (or otherwise produce panic 0x11 underflow at `levelPrizePool[uint24(0) - 1]` AdvanceModule:397/L752) at any reachable `(lastPurchaseDay, rngLockedFlag, jackpotPhaseFlag, level)` combination once the WIP `!rngLockedFlag` turbo guard at AdvanceModule:173 is in place; underflow / overflow / out-of-bounds audit at every `purchaseLevel`-arithmetic call site; symbolic reproduction of the testnet panic 0x11 trigger sequence at blocks 10759449 + 10761786; daily-jackpot region (L370-407) no-strand proof.

Six requirements (PLV-01..06 per REQUIREMENTS.md):

- **PLV-01** — Enumerate every read site of `purchaseLevel` (~30+ readsites in AdvanceModule + cross-module re-derivations across MintModule/WhaleModule/LootboxModule/BurnieCoinflip per D-249-01); tag each readsite with the local invariant required (`≥1`, `>level`, `level+1`, `packed`, etc.).
- **PLV-02** — 4-D state-space sweep across `(lastPurchaseDay ∈ {F,T}) × (rngLockedFlag ∈ {F,T}) × (jackpotPhaseFlag ∈ {F,T}) × (level)`; per D-249-04 encoded as 8 octants × 3 level bins (24 cells). Every reachable cell carries a SAFE-with-purchaseLevel ≥ 1 verdict at the bind line (AdvanceModule:185); every UNREACHABLE cell carries an explicit reachability-disproof citation with named invariant.
- **PLV-03** — Prove the ternary `(lastPurchase && rngLockedFlag) ? lvl : lvl + 1` cannot return 0 once the `!rngLockedFlag` turbo guard at L173 is in place; show the unreachable state is `(lastPurchase = T ∧ rngLockedFlag = T ∧ lvl = 0)` and prove turbo no longer fires there.
- **PLV-04** — Underflow / overflow / out-of-bounds audit on every `purchaseLevel`-arithmetic call site (`-1`, `+1`, `+4`, `%10`, `_tqReadKey`, `levelPrizePool[*]` array index). Per D-249-07 single flat per-call-site table with operator column. The `-1` rows cross-cite PLV-02 + PLV-03 + PLV-05 per D-249-08.
- **PLV-05** — Symbolic reproduction of testnet panic 0x11 at blocks 10759449 + 10761786 using BFL-03-style state-transition walk (D-249-11); pre-fix walk shows `purchaseLevel = 0` at L185; post-fix walk shows turbo guard at L173 short-circuits before binding.
- **PLV-06** — Daily-jackpot region L370-407 no-strand proof: per-branch invariant table + strand-disproof attestation that `targetMet ⇒ _unlockRng called same call` (D-249-12); cross-cite Phase 252 POST31-02 productive-pause composition target (D-249-13).

Anchor: HEAD `acd88512` (Phase 247's anchor; both WIP guards already committed inside this SHA — turbo guard L173 + backfill guard L1174). Deliverable: `audit/v32-249-PLV.md` (single file, READ-only after plan-close per D-247-22 / D-248-02 carry-forward).

Phase 249 is a pure-proof phase. Zero `contracts/` writes, zero `test/` writes — all forge / hardhat reproduction lives in Phase 251 TST-01..03 per D-247-02 / D-248-05 carry-forward. Finding-ID emission deferred to Phase 253 (FIND-01..04) per D-247-21 / D-248-03 carry-forward.

</domain>

<decisions>
## Implementation Decisions

### Anchor & Deliverable (Carry-Forward from Phase 247 / 248)

- **D-249-CF-01 (HEAD anchor `acd88512`):** Phase 249 inherits Phase 247/248's anchor at HEAD `acd88512`. Both WIP guards (turbo at L173 + backfill at L1174) already committed inside this SHA. ContractAddresses.sol working-tree changes ignored per D-247-03 carry-forward. Phase 247 Consumer Index D-247-I007..I012 = sole scope input for PLV-01..06; Phase 249 does NOT re-derive the universe from git diffs.
- **D-249-CF-02 (single deliverable `audit/v32-249-PLV.md`):** Per ROADMAP Phase 249 success criteria. READ-only flip on plan-close per D-247-22 / D-248-02 carry-forward. Mirrors v31 / v30 / v29 / Phase 247 / Phase 248 single-deliverable format.
- **D-249-CF-03 (no `F-32-NN` emission — Phase 253 owns):** Carry-forward D-247-21 / D-248-03. Any finding-candidate flagged routes to a `Finding Candidates` subsection with `path:line` + suggested severity for Phase 253 routing. No `F-32-` IDs in this phase.
- **D-249-CF-04 (pure-proof phase; cross-repo READ-only LIFTED at milestone level):** v32.0 lifted READ-only at the milestone but Phase 249, being pure-proof, has zero `contracts/` or `test/` writes. Writes confined to `.planning/phases/249-*/` and `audit/v32-249-*` files. KNOWN-ISSUES.md is NOT touched in Phase 249 (KI promotions are Phase 253 FIND-03 only).
- **D-249-CF-05 (Phase 251 owns all forge / hardhat tests):** Phase 249 produces a test-stub design block at the end of the deliverable (under `## Phase 251 TST-01/02/03 Hand-Off` section) covering `test/edge/LastPurchaseDayRace.test.js` (TST-01 pre-fix panic 0x11 reproduction, TST-02 post-fix pass) + composition with `LivenessProductivePause.test.js` / `LivenessMidJackpot.test.js` (TST-03 regression).
- **D-249-CF-06 (V-row scheme + 3-bucket verdict):** Inherit D-248-12 V-row pattern. Row IDs: `PLV-NN-VMM` (REQ-anchored, monotonic-within-REQ; e.g., `PLV-01-V01`, `PLV-02-V01`, ..., `PLV-06-V01`). Verdicts in 3-bucket {SAFE, EXCEPTION, FINDING_CANDIDATE}. Column shape per CONTEXT.md D-247-10: `Row ID | Site (file:line) | Description | Pre-state | Post-state | Verdict | Evidence Cite` (extended per-section as documented in PLV-specific decisions below).
- **D-249-CF-07 (single-plan multi-task atomic-commit):** Carry-forward D-247-12 / D-248-11. Suggested task ordering (planner final call): one task per cluster of REQs (e.g., Task 1 = PLV-01 + PLV-02, Task 2 = PLV-03 + PLV-04, Task 3 = PLV-05 + PLV-06, Task 4 = Final assembly + READ-only flip). Each task lands its own atomic commit per D-247-14.
- **D-249-CF-08 (scope-guard deferral rule):** Carry-forward D-247-22 / D-248-14. If Phase 249 finds a changed function / state-var / event / interface method / call site NOT in Phase 247's catalog, record a scope-guard deferral in this phase's SUMMARY.md (when the plan closes); Phase 247 output is NOT re-edited. Gaps become Phase 253 finding candidates.
- **D-249-CF-09 (grep-reproducibility for path enumeration):** Carry-forward D-247-19 / D-248-15. Every PLV-01 reachability claim + PLV-04 arithmetic-site claim cites the exact `grep` command used to find every read site / arithmetic call site. Portable POSIX syntax (no GNU `-P` / Perl regex).
- **D-249-CF-10 (testnet block reproduction seed):** Carry-forward D-248-16. PLV-05 worked example uses testnet block numbers 10759449 + 10761786 as the concrete seed (per REQUIREMENTS.md trigger context + Phase 247 §1.6 advanceGame turbo-guard INFO bullet). Walk through pre-fix sequence showing `purchaseLevel = 0` at L185, then walk through post-fix sequence showing the `!rngLockedFlag` short-circuit at L173.

### PLV-01 Enumeration Scope (D-249-01 / D-249-02 / D-249-03)

- **D-249-01 (wider scope — AdvanceModule + cross-module re-derivations):** PLV-01 catalogs (a) the AdvanceModule:185 binding + every read site of that local variable inside `advanceGame`'s call tree (helpers L734, L1097, L1504 take it as a parameter — trace the parameter chain), AND (b) every independent re-derivation of `purchaseLevel` across MintModule:923, WhaleModule:841, LootboxModule:532, BurnieCoinflip:578/1035, plus AdvanceModule helpers L734/L1097/L1504. Rationale: the v32.0 fix targets a `purchaseLevel = 0` panic class and **MintModule:923 has the same ternary shape (`cachedJpFlag ? cachedLevel : cachedLevel + 1`) WITHOUT the new `!rngLockedFlag` guard** — pre-flagging it here gives Phase 250 SIB a live finding-candidate seed instead of a tail-end discovery. Expected ~70+ rows total.
- **D-249-02 (full per-row proof depth — no Phase 250 deferral for cross-module rows):** Each cross-module re-derivation row carries a self-contained reachability proof:
  - **MintModule:923** — enumerate reachability of `(jackpotPhaseFlag = T ∧ cachedLevel = 0)` cell. If reachable → FINDING_CANDIDATE for Phase 250 SIB-01 / Phase 253 FIND-01. If unreachable → reachability-disproof cite.
  - **LootboxModule:532** — packed-slot extraction invariant (`uint24(packed >> 232)` returns the writer's `purchaseLevel` at write-time, which must itself satisfy ≥1; trace to packing site at WhaleModule:876 `lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount` and prove writer's purchaseLevel ≥ 1).
  - **WhaleModule:841 + BurnieCoinflip:578/1035** — parameter pass-through; prove caller's `purchaseLevel` ≥ 1 invariant by tracing call site to upstream binder.
  - **AdvanceModule:1097** — internal `purchaseLevel_ = level + 1` derivation; reachability is `level + 1 ≥ 1` which holds for `level ≥ 0` (always true since `level` is `uint24`). Overflow edge OOS-by-construction per D-249-06.
  - **AdvanceModule:734 / L1504** — parameter pass-through from `advanceGame`'s L185 binding; prove caller passes `purchaseLevel` from the L185 binder.
- **D-249-03 (PLV-01 column shape — standard 7-col + invariant tag):** Inherit D-247-10 / D-248-12 column shape with invariant tag:
  ```
  Row ID | Site (file:line) | Function | Read kind {bind/read/arith-arg/parameter} | Invariant required {≥1, =1, >level, level+1, packed} | Verdict | Evidence cite
  ```
  Verdict in 3-bucket {SAFE, EXCEPTION, FINDING_CANDIDATE}. Evidence cite carries grep recipe and (for cross-module rows) the upstream binder cite.

### PLV-02 4-D State-Space Sweep (D-249-04 / D-249-05 / D-249-06)

- **D-249-04 (8 octants × 3 level bins encoding):** Encode the 4-D Cartesian product as 8 octant tables (one per `(lastPurchase, rngLocked, jackpot)` triple) × level bins {`lvl = 0`, `1 ≤ lvl < levelMax`, `lvl = levelMax`}. 24 cells total. Each cell row column shape:
  ```
  Octant ID | Level bin | purchaseLevel formula at L185 | Reachability {REACHABLE, UNREACHABLE} | Reachability-disproof cite (if UNREACHABLE) | purchaseLevel ≥ 1 verdict | Evidence
  ```
  Octant ID format: `O-PLV-NNN` where N encodes the boolean triple (e.g., `O-PLV-FFF`, `O-PLV-TTF`, etc.). The `(T,T,*,lvl=0)` cells (one per jackpot value) are the load-bearing UNREACHABLE rows whose disproof cites the L173 turbo guard.
- **D-249-05 (inline path:line + named-invariant disproof):** UNREACHABLE cells carry:
  - inline `path:line` cite (e.g., AdvanceModule:173 turbo guard `!rngLockedFlag && !lastPurchaseDay && !inJackpot`)
  - named invariant ID (e.g., `INV-PLV-A-01: lastPurchaseDay = true ⇒ rngLockedFlag = false at write boundary`)
  - grep recipe in Evidence column (e.g., `grep -n 'lastPurchaseDay\\s*=\\s*true' contracts/modules/DegenerusGameAdvanceModule.sol`).
  Named-invariant ID scheme: `INV-PLV-{A=lastPurchase-rngLocked, B=jackpot, C=level}-NN`. Avoids forward-citing PLV-03 (each row stands alone with its proof).
- **D-249-06 (level=uint24.max overflow OOS-by-construction):** The `lvl + 1` branch at L185 overflows iff `lvl = uint24.max`. PLV-02 marks this OOS-by-construction per OUT OF SCOPE clause analog ("`level` cap is a v25/v26-era game-mechanic invariant not part of the v32 delta"). Single one-line cite in the overflow-edge sub-section pointing at the level-cap mechanism (`gameOverPossible` / target-met termination). NOT in the 24-cell main sweep.

### PLV-04 Arithmetic-Site Audit (D-249-07 / D-249-08 / D-249-09)

- **D-249-07 (single flat per-call-site table):** One flat table for all PLV-04 rows, sorted by `file:line`. Column shape:
  ```
  Row ID | Site (file:line) | Function | Operator {-1, +1, +4, %10, _tqReadKey, array-index} | Arithmetic expression | Reachable purchaseLevel range | Underflow/overflow/oob risk | Verdict | Evidence cite
  ```
  Sites enumerated: AdvanceModule `-1` at L397/L752; `+1` at L185/L389/L411; `+4` at L312/L390; `%10==9` at L750; `_tqReadKey()` at L218/L266; `levelPrizePool[purchaseLevel]` at L424. Cross-module sites (per D-249-01 wider scope): BurnieCoinflip `%10==0` at L590/L1041; MintModule:924 `priceForLevel(purchaseLevel)` (function-arg, internal arithmetic — trace into PriceLookupLib); LootboxModule:552 passthrough.
- **D-249-08 (`-1` rows cross-cite PLV-02 + PLV-03 + PLV-05):** Each `purchaseLevel - 1` underflow row (the literal v32.0 panic trigger sites L397/L752) carries verdict SAFE-via-PLV-02 with explicit cross-cites to:
  - PLV-02 sweep table row(s) covering the relevant octant (proves `purchaseLevel ≥ 1`)
  - PLV-03 ternary unreachable-state proof (proves the `(T,T,lvl=0)` cell cannot fire)
  - PLV-05 testnet reproduction (proves the post-fix walk short-circuits before reaching L185)
  Establishes the per-site safety chain explicitly. Mirrors Phase 248 BFL-06's cross-cite pattern to BFL-04 invariant.
- **D-249-09 (array-index oob — both bounds covered):** Each `levelPrizePool[*]` site carries TWO verdict rows:
  - lower-bound: `purchaseLevel ≥ 1` for `[purchaseLevel - 1]` (cross-cite chain per D-249-08)
  - upper-bound: `purchaseLevel ≤ levelPrizePool.length - 1` (cited via the v25/v26 game-mechanic level cap from D-249-06; same underlying invariant)
  Sites: L397, L424, L752. Maintains symmetric oob coverage.

### PLV-05 Testnet Panic Reproduction Shape (D-249-10 / D-249-11)

- **D-249-10 (BFL-03-style state-transition walk):** Mirror Phase 248 BFL-03's worked-numeric-example pattern (D-248-07 carry-forward). Row-per-`advanceGame` invocation across the testnet block sequence (10759449 + 10761786). Column shape:
  ```
  Step | block.timestamp | day | dailyIdx | rngLockedFlag | lastPurchaseDay | jackpotPhaseFlag | level | turbo guard verdict at L173 | binding ternary L185 result | purchaseLevel | next L397/L752 verdict
  ```
  Two tables: §5.1 pre-fix walk (shows `purchaseLevel = 0` at L185 → panic 0x11 at L397/L752); §5.2 post-fix walk (shows the new `!rngLockedFlag` conjunct at L173 fails → turbo block skipped → no `lastPurchaseDay = true` write → L185 binds `lvl + 1` → SAFE).
- **D-249-11 (testnet block seed locked, narrative-context alignment with REQUIREMENTS.md trigger):** Use testnet block numbers 10759449 + 10761786 verbatim as PLV-05 reproduction seed. Pre-fix sequence narrative aligns with REQUIREMENTS.md "purchaseLevel = 0 race" trigger paragraph: turbo block at L173 fires while `rngLockedFlag = true` → `rngGate` fresh-word path runs instead of `_requestRng` → level pre-increment missed → ternary at L185 with `lastPurchase = T ∧ rngLockedFlag = T` returns `lvl = 0`.

### PLV-06 Daily-Jackpot No-Strand Proof Shape (D-249-12 / D-249-13)

- **D-249-12 (per-branch invariant table + strand-disproof attestation):** Single table walking each branch of the L370-407 region. Column shape:
  ```
  Row ID | Branch trigger | State entered | Operations performed | State exited | _unlockRng called same-call? | Verdict
  ```
  Branches enumerated: `purchaseLevel == 1` (L372 — coin-only path), `purchaseLevel ≥ 2` (L384 — daily jackpot path), `targetMet = true` via `gameOverPossible` (L394), `targetMet = true` via `_getNextPrizePool() ≥ levelPrizePool[purchaseLevel - 1]` (L396), `targetMet = false` (no `lastPurchaseDay` write). Followed by a one-paragraph strand-disproof attestation showing zero early-return / revert / break between L398 (`lastPurchaseDay = true`) and L404 (`_unlockRng(day)`) by inspection of the code flow. Matches Phase 248 BFL-04 invariant-table pattern; doesn't duplicate BFL-03 worked-walk format (which is for sequential trigger sequences — PLV-06 is a single-call resolution proof).
- **D-249-13 (Phase 252 POST31-02 cross-cite + composition hand-off row):** PLV-06 emits a one-row hand-off attestation noting the daily-jackpot strand-disproof composes with `8bdeabc2` productive-pause (which clears `lastPurchaseDay || jackpotPhaseFlag` early in `_livenessTriggered`). Phase 252 POST31-02 inherits this row as a confirmed composition target. Mirrors Phase 248 BFL-04's cross-cite of the productive-pause path. Hand-off row column shape:
  ```
  Carrier ID | Compose target | Pre-PLV-06 envelope | Post-PLV-06 envelope | Phase 252 inheritance verdict
  ```

### Plan Topology (D-249-CF-07 carry-forward)

Suggested 4-task split (planner final call):

1. **Task 1 (PLV-01 + PLV-02)** — Cross-module purchaseLevel readsite enumeration (~70+ rows) + 4-D state-space sweep (24 octant cells) with named invariants and grep-cited reachability disproofs.
2. **Task 2 (PLV-03 + PLV-04)** — Ternary unreachable-state proof (the `(T,T,lvl=0)` cell load-bearing on L173 turbo guard) + arithmetic-site flat table with `-1` cross-cite chain + array-index oob both bounds.
3. **Task 3 (PLV-05 + PLV-06)** — Testnet panic 0x11 BFL-03-style state-transition walk (pre-fix + post-fix) + daily-jackpot per-branch invariant table + strand-disproof attestation + Phase 252 POST31-02 composition hand-off row.
4. **Task 4 (Final assembly + Phase 251 hand-off + READ-only flip)** — Assemble `audit/v32-249-PLV.md`, write Phase 251 TST-01/02/03 hand-off appendix (test-stub design + suggested test file alignment with `test/edge/LastPurchaseDayRace.test.js`), mark FINAL READ-only on plan-close commit.

Each task lands its own atomic commit per D-247-14 atomic-task-commit pattern.

### Claude's Discretion

- Final section ordering within `audit/v32-249-PLV.md` (planner picks readable shape — likely 7-section format: §1 PLV-01 enumeration, §2 PLV-02 sweep, §3 PLV-03 ternary unreachable proof, §4 PLV-04 arithmetic audit, §5 PLV-05 testnet reproduction, §6 PLV-06 daily-jackpot no-strand, §7 Finding Candidates + Phase 251 hand-off appendix).
- Whether the PLV-02 octant tables are inlined as 8 separate sub-tables or rendered as one flat 24-row table with octant column.
- Whether named-invariant ID scheme uses `INV-PLV-A-NN / INV-PLV-B-NN / INV-PLV-C-NN` (per-axis) or flat `INV-PLV-NN`.
- Whether finding-candidate severity is suggested in Phase 249's `Finding Candidates` subsection (recommended INFO baseline per D-247-21 spirit) or left blank for Phase 253 D-08 5-bucket rubric.
- Per-REQ section header naming (e.g., `## PLV-01 — ...` vs `## Section 1 — PLV-01`).
- Whether MintModule:924 `priceForLevel(purchaseLevel)` traces into PriceLookupLib internal arithmetic for PLV-04 coverage (recommended yes — internal arithmetic could underflow if PriceLookupLib reads a 0-indexed table and gets `purchaseLevel = 0`) or treats PriceLookupLib as a boundary cite (D-248-10 analog).
- Whether the Phase 251 hand-off appendix sketches an `it()` block or just lists symbolic-spec / suggested-file / Phase 247 row anchors (Phase 248's three-block format is reusable).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` — v32.0 requirements; PLV-01..06 (this phase) + 4 accepted RNG exceptions + OUT OF SCOPE clauses; trigger context for purchaseLevel = 0 race naming testnet blocks 10759449 + 10761786 + the L185 ternary mechanism + the L397/L752 panic 0x11 site.
- `.planning/ROADMAP.md` — Phase 249 success criteria (6 items); deliverable target `audit/v32-249-PLV.md`; per-criterion verdict-row guidance.
- `.planning/PROJECT.md` — Current Milestone section lists the bug context + READ-only-LIFTED write policy.

### Phase 247 scope input (MUST read — sole scope input per Phase 247 success criterion 4)
- `audit/v32-247-DELTA-SURFACE.md` — FINAL READ-only at HEAD `acd88512`. Specifically Section 1.4 acd88512 commit changelog rows D-247-C011 (advanceGame turbo guard hunk) + D-247-C012 (rngGate backfill guard hunk), Section 1.6 finding-candidate bullets for `advanceGame` turbo guard L173, Section 2 classification rows D-247-F010 (advanceGame MODIFIED_LOGIC), Section 3 call-site rows D-247-X027..X029 (3 advanceGame entry paths), Section 6 Consumer Index rows D-247-I007..I012 (PLV-01..06 row scope mapping).
- `.planning/phases/247-delta-extraction-classification/247-CONTEXT.md` — D-247-21 (no F-32-NN emission), D-247-22 (READ-only after plan-close), D-247-02 (test/-out-of-scope routes to Phase 251) — all carried forward into Phase 249.
- `.planning/phases/247-delta-extraction-classification/247-01-PLAN.md` — single-plan multi-task atomic-commit precedent for D-249-CF-07 plan topology.
- `.planning/phases/247-delta-extraction-classification/247-01-SUMMARY.md` — Phase 247 closure verification.

### Phase 248 carry-forward (MUST read for pattern reuse)
- `audit/v32-248-BFL.md` — sibling pure-proof phase. Specifically §3 BFL-03 worked-numeric-example state-transition table format (mirror for PLV-05 D-249-10), §4 BFL-04 invariant-table format (mirror for PLV-06 strand-disproof D-249-12), §5 BFL-05 dual-carrier attestation row format (precedent for PLV-06 hand-off row D-249-13), §6 BFL-06 conservation algebra block (precedent for PLV-04 cross-cite chain D-249-08), and 7-section deliverable format.
- `.planning/phases/248-backfill-idempotency-proof/248-CONTEXT.md` — D-248-02 (single deliverable READ-only flip), D-248-07 (state-transition table for sequential proofs), D-248-12 (V-row scheme + 3-bucket verdict), D-248-15 (grep-reproducibility), D-248-16 (testnet block seed) — all carried forward into Phase 249 as D-249-CF-NN.
- `.planning/phases/248-backfill-idempotency-proof/248-01-*-SUMMARY.md` (and per-task commits) — 5-task split precedent for D-249-CF-07 4-task simplification (PLV has fewer cross-cutting attestations than BFL).

### In-scope code (HEAD acd88512)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — primary audit target. Specifically:
  - `advanceGame` function at L160-488 (the changed function with the new turbo guard hunk).
  - Turbo block at L167-182 with `!rngLockedFlag` guard at L173 (the load-bearing PLV-03 disproof anchor).
  - Binding ternary at L185 `uint24 purchaseLevel = (lastPurchase && rngLockedFlag) ? lvl : lvl + 1;` (PLV-02 / PLV-03 proof target).
  - Daily-jackpot region L370-407 (PLV-06 strand-disproof target). Specifically `_unlockRng(day)` at L404.
  - Underflow site L397 `levelPrizePool[purchaseLevel - 1]` (PLV-04 + the literal v32.0 panic trigger).
  - Underflow site L752 `levelPrizePool[purchaseLevel - 1]` inside `_distributeYieldSurplus` (PLV-04 secondary trigger; same shape).
  - Other arithmetic sites: L312 `+4`, L389 `+1`, L390 `+4`, L411 `+1`, L424 array-index, L750 `%10==9`.
  - Helper functions taking `purchaseLevel` as a parameter: L218/L266 `_tqReadKey`, L223/L280 `_runProcessTicketBatch`, L301 `_swapAndFreeze`, L316 `_processPhaseTransition`, L734 `_distributeYieldSurplus`, L1097 internal `purchaseLevel_ = level + 1` derivation, L1504 `_processFutureTicketBatch`-class.
- `contracts/modules/DegenerusGameMintModule.sol` — cross-module re-derivation site. Specifically L923 `uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;` (the live FINDING_CANDIDATE-or-SAFE row per D-249-02; same ternary shape as L185 WITHOUT the `!rngLockedFlag` guard) + L924 `PriceLookupLib.priceForLevel(purchaseLevel)` (PLV-04 cross-module arithmetic site).
- `contracts/modules/DegenerusGameWhaleModule.sol` — cross-module parameter site. Specifically L841 (parameter receive) + L876 packing site `lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;` (PLV-01 packing-invariant anchor for LootboxModule:532).
- `contracts/modules/DegenerusGameLootboxModule.sol` — cross-module packed-decode site. Specifically L532 `uint24 purchaseLevel = uint24(packed >> 232);` (PLV-01 packed-slot extraction invariant; trace to WhaleModule:876 packer) + L552 `withinGracePeriod ? graceLevel : purchaseLevel` (passthrough).
- `contracts/BurnieCoinflip.sol` — cross-module parameter site. Specifically L578/L1035 (parameter receive), L590/L1041 `purchaseLevel_ % 10 == 0` (PLV-04 modular arithmetic), L596 `bafLevel = purchaseLevel_;` (storage write).
- `contracts/storage/DegenerusGameStorage.sol` — `level` storage variable at L250 `uint24 public level = 0;` (the underlying state `lvl` is read from at AdvanceModule:165 `uint24 lvl = level;`); only writer surfaces feed PLV-02 reachability for the `lvl = 0` boundary case.

### Methodology precedents (carry-forward, not re-litigated)
- `.planning/milestones/v31.0-phases/244-per-commit-adversarial-audit/` — V-row pattern + 3-bucket verdict precedent (D-249-CF-06). Specifically the per-REQ Vnn row format with {SAFE, EXCEPTION, FINDING_CANDIDATE} verdicts.
- `audit/v31-244-EVT.md` / `v31-244-RNG.md` / `v31-244-QST.md` / `v31-244-GOX.md` — direct format precedent for V-row tables in `audit/v32-249-PLV.md`.
- `audit/v31-245-SDR.md` / `v31-245-GOE.md` — dual-carrier attestation precedent for D-249-13 PLV-06 Phase 252 composition hand-off row (specifically SDR-08-V01 / GOE-01-V01 / GOE-04-V02 carrier rows).
- `audit/v31-246-FINDINGS.md` — single-plan multi-task pattern reference; no findings IDs in mid-milestone phases (D-247-21 / D-249-CF-03).
- `.planning/milestones/v30.0-phases/242-findings-consolidation/` — single-plan multi-task pattern reference (D-249-CF-07).

### Prior audit outputs (light cross-cite for PLV-01 + PLV-04)
- `audit/FINDINGS-v31.0.md` — 33 V-rows / 142 verdicts; lean regression appendix. PLV-01 cross-module reads cross-cite any v31 row whose underlying function is `purchaseLevel`-arithmetic-dependent.
- `audit/FINDINGS-v30.0.md` — VRF consumer determinism audit; per-consumer freeze proofs. Light cross-cite for any rngWord-dependent path that PLV-02 reachability touches.
- `audit/FINDINGS-v29.0.md` — F-29-04 gameover RNG substitution finding (the EXC-03 codification source). PLV-06 daily-jackpot path may cross-cite if `gameOverPossible` branch enters EXC-03 envelope.
- `audit/STORAGE-WRITE-MAP.md` — prior storage-write catalog; PLV-02 reachability disproof may cross-cite `lastPurchaseDay` / `rngLockedFlag` / `level` write inventory if the named-invariant proof requires storage-write enumeration.
- `audit/ACCESS-CONTROL-MATRIX.md` — prior access-control context; relevant if PLV-01 wider scope surfaces `purchaseLevel`-dependent access gates.

### Project feedback rules (apply across all plans in Phase 249)
- `memory/feedback_no_contract_commits.md` — explicit per-commit user approval required for any `contracts/` or `test/` write. Phase 249 has zero such writes by D-249-CF-04 / D-249-CF-05 but the rule binds if any agent-level surprise emerges.
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source.
- `memory/feedback_no_history_in_comments.md` — deliverable docs describe what IS, not what CHANGED (PLV deliverable is allowed to describe pre-vs-post-guard state for proof purposes — that's the entire point — but rationale prose must read as descriptive, not as patch-history narration).
- `memory/feedback_rng_backward_trace.md` — every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time. Relevant to PLV-02 reachability disproofs that touch `rngLockedFlag` ← VRF-request boundary.
- `memory/feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment. Relevant to PLV-02 reachability disproofs that depend on the VRF lock window being held continuously.
- `memory/feedback_skip_research_test_phases.md` — skip research for obvious/mechanical phases. Phase 249 is a proof phase grounded in Phase 247's catalog + Phase 248 BFL pattern + REQUIREMENTS.md trigger context — research is unlikely to add value beyond the existing canonical refs.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 247 Section 6 Consumer Index (D-247-I007..I012)** — directly defines PLV-01..06 row scope. Phase 249 plan does NOT re-derive the universe.
- **Phase 248 V-row table format** — direct shape reuse for `audit/v32-249-PLV.md`'s per-REQ sections (PLV-NN-VMM rows with 3-bucket verdicts).
- **Phase 248 BFL-03 worked-numeric-example state-transition walk** — direct shape reuse for D-249-10 PLV-05 testnet panic 0x11 reproduction. Same testnet block seed (10759449 + 10761786) per D-249-CF-10.
- **Phase 248 BFL-04 invariant-table format** — direct shape reuse for D-249-12 PLV-06 daily-jackpot per-branch invariant table.
- **Phase 248 BFL-05 dual-carrier attestation row** — direct shape reuse for D-249-13 PLV-06 Phase 252 composition hand-off row.
- **Phase 248 BFL-06 cross-cite chain to BFL-04** — direct shape reuse for D-249-08 PLV-04 `-1` row cross-cite chain to PLV-02 + PLV-03 + PLV-05.
- **Phase 248 task topology (5-task split)** — adapted to 4-task split per D-249-CF-07 (PLV has fewer cross-cutting attestations than BFL — no envelope re-verify equivalent of BFL-05).
- **Phase 247 single-plan multi-task atomic-commit pattern (D-247-13 / D-247-14)** — direct reuse for D-249-CF-07 plan topology.
- **Existing `audit/v31-243-DELTA-SURFACE.md` / `audit/v32-247-DELTA-SURFACE.md` / `audit/v32-248-BFL.md` 7-section single-file format** — format precedent for `audit/v32-249-PLV.md`.

### Established Patterns
- **State-transition table for sequential proofs** — pattern carry-forward from Phase 248 BFL-03 (per-call pre-state / post-state columns); applied to PLV-05.
- **Per-branch invariant table for single-call resolution proofs** — pattern carry-forward from Phase 248 BFL-04; applied to PLV-06.
- **3-bucket verdict {SAFE, EXCEPTION, FINDING_CANDIDATE}** — Phase 244 / 245 / 248 carry-forward.
- **Cross-cite chain for derivative facts** — pattern from Phase 248 BFL-06 (cross-cites BFL-04 invariant); applied to PLV-04 `-1` rows.
- **Boundary-record + behavioral-cite for external calls** — v25 / v29 / v31 / Phase 248 carry-forward; applied to PLV-04 cross-module arithmetic sites (e.g., `priceForLevel`).
- **No F-NN-NN emission in proof / catalog phases** — v29 / v30 / v31 / Phase 247 / Phase 248 carry-forward.
- **OOS-by-construction with single-line cite** — Phase 248 D-248-10 BurnieCoinflip pattern; applied to PLV-02 / PLV-04 `level = uint24.max` overflow edge.

### Integration Points
- **Phase 247 → Phase 249** — `audit/v32-247-DELTA-SURFACE.md` Section 6 D-247-I007..I012 maps PLV-01..06 to specific Phase 247 row IDs. Phase 249 plan opens by citing these rows and then walks the proof inward.
- **Phase 248 → Phase 249** — `audit/v32-248-BFL.md` BFL-04 invariant table cross-cites the productive-pause path; Phase 249 PLV-06 inherits the same cross-cite for the daily-jackpot strand-disproof composition target.
- **Phase 249 → Phase 250** — PLV-01 wider scope (D-249-01) pre-flags MintModule:923 ternary as a same-shape sibling-pattern candidate; Phase 250 SIB-01/02 sweep inherits this row as a live finding-candidate seed (avoiding tail-end discovery). Per D-249-CF-08 scope-guard deferral, any additional cross-module re-derivation Phase 247 missed routes to Phase 250 SIB sweep scope.
- **Phase 249 → Phase 251** — Phase 249 deliverable's `## Phase 251 TST-01/02/03 Hand-Off` appendix provides test-stub design (symbolic spec + suggested test file alignment with `test/edge/LastPurchaseDayRace.test.js` + Phase 247 row anchors D-247-C011 + D-247-F010 + D-247-X027..X029). Phase 251 plan reads this hand-off as scope input for TST-01 (pre-fix panic 0x11), TST-02 (post-fix pass), TST-03 (regression on `LivenessProductivePause` + `LivenessMidJackpot`).
- **Phase 249 → Phase 252** — D-249-13 emits a one-row composition hand-off attestation; Phase 252 POST31-02 RE_VERIFIES the productive-pause + new turbo guard composition with this row as confirmed input target.
- **Phase 249 → Phase 253** — Any PLV-NN-VNN row classified `FINDING_CANDIDATE` (most likely the MintModule:923 row if `(jackpotPhaseFlag = T ∧ cachedLevel = 0)` cell is reachable) routes into Phase 253 FIND-01 finding-block emission per D-249-CF-03.

### Git Infrastructure (verified 2026-05-01)
- HEAD anchor `acd88512`; current git HEAD `899bd989` (Phase 248 closure docs commits above `acd88512` touch only `.planning/` and `audit/v32-248-*`).
- Working tree at start of Phase 249 execution: `contracts/ContractAddresses.sol` modified (deploy regen, ignored per D-247-03 carry-forward), `test/edge/LastPurchaseDayRace.test.js` untracked (Phase 251 scope per D-247-02).
- No `git diff` runs in Phase 249 plan — Phase 247 catalog is the sole scope input per Phase 247 success criterion 4. Plan opens with a sanity gate `git rev-parse acd88512` to confirm anchor presence, then walks Phase 247's row IDs inward.
- `purchaseLevel` identifier appears in 11 contracts / 104 hits per `grep -rn 'purchaseLevel' contracts/ --include="*.sol"`. Of these, ~30+ are inside AdvanceModule (the L185-binder chain) and ~70+ across cross-module re-derivations — D-249-01 wider scope captures both populations.

</code_context>

<specifics>
## Specific Ideas

- **MintModule:923 ternary is the live FINDING_CANDIDATE seed** — `uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;` mirrors the L185 ternary shape but gates on `jackpotPhaseFlag` instead of `lastPurchaseDay && rngLockedFlag`, AND has no `!rngLockedFlag` guard equivalent. Per D-249-02, walk reachability of `(cachedJpFlag = T ∧ cachedLevel = 0)`. If reachable, this is a same-shape sibling-pattern bug Phase 250 SIB-01 inherits as a live candidate. If unreachable, the disproof must cite the boundary that prevents `cachedLevel = 0` from co-occurring with `cachedJpFlag = T`.
- **PLV-02 octant ID convention suggestion**: `O-PLV-{LR|LRJ|LJ|RJ|L|R|J|0}` where letters encode which booleans are true (L=lastPurchase, R=rngLocked, J=jackpot, 0=all false). Or `O-PLV-FFF / FFT / FTF / FTT / TFF / TFT / TTF / TTT` ordered by triple. Planner final call.
- **Named-invariant ID scheme suggestion**: `INV-PLV-A-NN` for lastPurchaseDay/rngLockedFlag co-occurrence invariants, `INV-PLV-B-NN` for jackpotPhaseFlag invariants, `INV-PLV-C-NN` for level-write invariants. Critical invariants likely needed:
  - `INV-PLV-A-01: lastPurchaseDay = true ⇒ rngLockedFlag = false at write boundary` (load-bearing for `(T,T,*,lvl=0)` UNREACHABLE — anchored at the new L173 turbo guard `!rngLockedFlag && !lastPurchaseDay && !inJackpot`)
  - `INV-PLV-B-01: jackpotPhaseFlag = true ⇒ lastPurchaseDay = false at write boundary` (likely already cited in v25/v29/v30/v31 audits)
  - `INV-PLV-C-01: level only increments inside _consolidatePoolsAndRewardJackpots` or equivalent (PLV-02 reachability for `lvl = 0` boundary case — the bootstrapping case — needs this)
- **PLV-04 site enumeration grep recipes**:
  - All `purchaseLevel` references in AdvanceModule: `grep -n 'purchaseLevel' contracts/modules/DegenerusGameAdvanceModule.sol`
  - All arithmetic on purchaseLevel: `grep -nE 'purchaseLevel\s*[+\-]\s*[0-9]|purchaseLevel\s*%' contracts/`
  - All array-index uses: `grep -nE 'levelPrizePool\[' contracts/`
- **Phase 251 hand-off block format suggestion** — `## Phase 251 TST-01/02/03 Hand-Off` section at the bottom of the deliverable. Three sub-blocks per Phase 248 hand-off precedent:
  1. **Symbolic spec** — pre-state setup (turbo block at L173 fires while `rngLockedFlag = true` pre-fix); call sequence to trigger; expected pre-fix revert kind (panic 0x11 at L397/L752 `levelPrizePool[uint24(0) - 1]`); expected post-fix pass behavior (turbo guard short-circuits → L185 binds `lvl + 1`).
  2. **Suggested test file** — `test/edge/LastPurchaseDayRace.test.js` (untracked, hardhat). Phase 251 final call.
  3. **Phase 247 row anchors** — list the Phase 247 catalog rows the test exercises (D-247-C011 turbo guard hunk + D-247-F010 advanceGame MODIFIED_LOGIC + D-247-X027..X029 advanceGame entry paths).
- **PLV-06 strand-disproof attestation suggestion** — single paragraph by-inspection of L398-L404:
  > Between `lastPurchaseDay = true` (L399) and `_unlockRng(day)` (L404), the only intervening statement is the `compressedJackpotFlag = 1` write (L401, conditional on `day - psd <= 3`). No `revert`, `return`, `break`, or `continue` exists between L398 and L404 within the active branch. Therefore `targetMet ⇒ _unlockRng called same call` holds by code structure.

</specifics>

<deferred>
## Deferred Ideas

- **Forge invariant fuzz test for purchaseLevel ≥ 1** — could augment Phase 251's hardhat reproduction with a forge `invariant_*` test asserting `purchaseLevel ≥ 1` at every `levelPrizePool[purchaseLevel - 1]` site call. Out of Phase 249 scope (pure-proof phase per D-249-CF-04); flag for Phase 251 TST or future-milestone follow-up.
- **MintModule:923 fix candidate (if reachable)** — if D-249-02 surfaces the `(cachedJpFlag = T ∧ cachedLevel = 0)` cell as REACHABLE, the structural fix candidate is to add a `!rngLockedFlag` conjunctive guard (or its MintModule-context analog) to the L923 ternary. Out of Phase 249 scope (pure-proof phase + per D-249-CF-03 no F-32-NN emission); routes to Phase 250 SIB-01/02 verdict + Phase 253 FIND-01/02 severity assignment + per-commit user-approval audit trail per `feedback_no_contract_commits.md`.
- **Cross-milestone delta chain for `purchaseLevel` semantics** — `purchaseLevel` arithmetic shape has been stable since v3.6-era Phase 59-62 (when the level-tier prize pool architecture landed). A retroactive audit chain for the L185 ternary's evolution would be informative but is OUT of v32.0 scope (REQUIREMENTS.md Out of Scope analog: "non-delta surfaces — covered in v25.0/v29.0/v30.0/v31.0; not re-proven globally").
- **PriceLookupLib internal arithmetic deep-walk** — D-249-CF Claude's-Discretion item: whether to trace into `PriceLookupLib.priceForLevel(purchaseLevel)` from MintModule:924 for PLV-04 internal-arithmetic coverage. If PriceLookupLib has a 0-indexed lookup table, a `purchaseLevel = 0` upstream binding could underflow inside the lib. Recommended yes (full per-row proof per D-249-02), but planner final call. If deferred, routes to Phase 250 SIB-03 module-boundary audit.
- **Phase 250 SIB-01 sibling-pattern sweep** — if PLV-01 cross-module rows surface additional same-shape ternaries (beyond MintModule:923) Phase 247 missed, Phase 250 SIB-01 owns the sibling sweep. Phase 249 records the candidate via the `Finding Candidates` subsection and routes via D-249-CF-08 scope-guard deferral.
- **Storage-layout add-row for any new state-var introduced by future purchaseLevel-related hardening** — Phase 247 §5 confirms zero storage-layout delta in v32.0 in-scope SHAs. If planner-added hardening adds a new state-var (none expected in pure-proof Phase 249), it routes to Phase 252 POST31-01 storage-layout re-verify.
- **Octant ordering convention + named-invariant prefix scheme** — left to planner discretion per D-249 Claude's-Discretion. Octants likely best ordered by triple (FFF / FFT / FTF / FTT / TFF / TFT / TTF / TTT) for grep-friendliness; named-invariant prefix can flatten to `INV-PLV-NN` if the per-axis split adds noise.

</deferred>

---

*Phase: 249-purchaselevel-correctness-proof*
*Context gathered: 2026-05-01*
