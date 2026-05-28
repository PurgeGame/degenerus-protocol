# Roadmap: Degenerus Protocol — Audit Repository

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Milestones

- ✅ **v44.0 sStonk Per-Day Redemption Refactor** — Phases 304-308 (shipped 2026-05-20)
- ✅ **v45.0 VRF-Rotation Liveness Fix** — Phases 309-314 (shipped 2026-05-23, minimal close)
- ✅ **v46.0 Do-Work Crank + AfKing Subscription** — Phases 316-320 (shipped 2026-05-24)
- ✅ **v47.0 Rake-Free Presale + Lootbox-Boon Unification** — Phases 321-324 (shipped 2026-05-25)
- ✅ **v48.0 sDGNRS Salvage Swap + v47 Deferred Fixes + Keeper/Pool/Tombstone/Hero** — Phases 325-328 (shipped 2026-05-26)
- ✅ **v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep** — Phases 329-333 (shipped 2026-05-27)
- ✅ **v50.0 Whale-Pass O(1) Refactor + AfKing Pass-Gated Subs + MintModule Advance-Divergence + External RNG-Audit Protocol** — Phases 334-338 (shipped 2026-05-28, minimal close)
- 🔨 **v51.0 claimBingo — Color-Completion Claim** — Phases 339-342 (started 2026-05-28)

---

## 🔨 v51.0 claimBingo — Color-Completion Claim (Active — started 2026-05-28)

**Milestone:** v51.0 (started 2026-05-28)
**Defined:** 2026-05-28
**Audit baseline → subject:** v50.0 closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80` (the minimal-close commit; no formal `MILESTONE_V50_AT_HEAD` signal was emitted) → v51.0 closure HEAD (TBD at TERMINAL). Subject = the single batched USER-APPROVED `contracts/*.sol` diff for the three coupled items (BINGO `claimBingo` color-completion entrypoint · REBAL sDGNRS `Pool.Reward` constructor rebalance · JACK jackpot final-day `Pool.Reward` deletion).
**Scope source:** `.planning/REQUIREMENTS.md` (18 v51.0 REQ-IDs across 5 categories: BINGO 6 · REBAL 1 · JACK 2 · TST 6 · BATCH 3) + the milestone init (2026-05-28) + the v51 forward-seed (`v51-claimbingo-color-completion-seed`) + the locked design doc `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md`. **No research** (a fully-specced contract feature with the game-theory / Monte-Carlo analysis already done in the plan doc) — no phase needs a research sub-phase (attestation + design-proof + established-methodology only).

> **Audit posture — MINIMAL CLOSE (USER decision 2026-05-28 at milestone start).** v51 ships SPEC → IMPL → TST → TERMINAL with a **minimal close**. The internal 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) + delta-audit + `audit/FINDINGS-v51.0.md` are **DEFERRED → the v52 consolidated audit**, which MUST cover the cumulative **v50 + v51** contract surface (per the STATE.md "v50.0 + v51.0 AUDIT DEBT → v52" note). v51 is NOT unaudited: SPEC (339) PROVES freeze-safety (BINGO-06) + tier-precedence, and TST (341) proves the per-tier rewards / dedup / empty-pool no-op / jackpot-final-day regression — only the adversarial-hunt + formal-findings layer is batched into v52. **There is NO SWEEP/AUDIT phase and NO GAS phase in v51.0.** Mirrors the v45.0 + v50.0 minimal-close precedent.

> **Cross-cutting rule (every requirement):** every cited `file:line` MUST be re-attested against the **v50.0-closure HEAD `812abeee`** before any patch (no "by construction" / "single fn reaches all paths" claim survives un-checked — the `DegenerusGame` mint/jackpot inline-duplication precedent; `feedback_verify_call_graph_against_source`). The cited anchors (`DegenerusGameJackpotModule.sol:1339-1352` final-day branch + `:191` constant + `:1350` `JackpotDgnrsWin` emit; `StakedDegenerusStonk.sol:294-298` pool BPS constants; `storage/DegenerusGameStorage.sol:416` `traitBurnTicket`; `DegenerusTraitUtils.sol:17-39` trait byte layout) are confirmed at SPEC. Security / RNG-freeze floor over gas (`feedback_security_over_gas` + `v45-vrf-freeze-invariant`). **`claimBingo` is a READ-ONLY consumer of the post-RNG-resolution `traitBurnTicket` map and writes ONLY its own claim/first bitfields → freeze-safe by construction, RE-PROVEN at SPEC (BINGO-06), not assumed.** Pre-launch redeploy-fresh (storage-layout break + the constructor-only constant change both fine, no migration; `feedback_frozen_contracts_no_future_proofing`).

> **Posture:** the three coupled contract items (BINGO + REBAL + JACK) ship as **ONE batched USER-APPROVED `contracts/*.sol` diff** at IMPL with a **HARD STOP at the contract-commit boundary** (applied + locally compiled/tested, NEVER committed without explicit user hand-review of the single batched diff — `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`; `ContractAddresses.sol` freely modifiable per `feedback_contractaddresses_policy`). The diff is authored producer-before-consumer (new module + storage → `DegenerusGame.claimBingo` delegatecall + interface → `StakedDegenerusStonk` rebalance + `JackpotModule` deletion). Tests + planning + docs AGENT-committable.

> **Shared-surface note:** the BINGO item adds a new `DegenerusGameBingoModule.sol` (delegatecalled from `DegenerusGame.claimBingo`) that is a READ-ONLY consumer of the jackpot-owned `traitBurnTicket` storage the JACK item also touches → SPEC reconciles the storage shape + the `uint24` level key so the read-only bingo consumer and the final-day deletion land in one coherent diff. REBAL (`StakedDegenerusStonk` constructor constants) is isolated but the BPS-sum invariant (pools still sum to 10 000) is attested at SPEC.

> **Phase numbering** continues from the previous milestone — v50.0 ended at Phase 338, so **v51.0 starts at Phase 339.** Not reset to 1. (Prior milestones' phase dirs are archived under `.planning/milestones/vXX.0-phases/`.)

> **Milestone shape** is the established v44–v50 audit pattern, run to a MINIMAL CLOSE: **SPEC design-lock (+ the BINGO-06 RNG-freeze-safety PROOF + the tier-precedence design-lock + call-graph attestation) → single batched IMPL contract diff → TST proof → TERMINAL minimal close (re-attest + atomic 5-doc closure flip; the internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` DEFERRED → v52).** The contract-boundary HARD STOP lives at exactly ONE IMPL phase (340).

### Phases

- [ ] **Phase 339: SPEC — Design-Lock + RNG-Freeze-Safety Proof + Tier-Precedence Lock + Call-Graph Attestation** - Settle the `claimBingo` signature + the storage shape (`bingoClaimed` / `firstQuadrant` / `firstSymbol` + the `uint24` level key) + the slot-width + the reward constants + the module placement, PROVE (not assume) the BINGO-06 RNG-freeze safety of the `traitBurnTicket` read, resolve all 7 "Open before SPEC" items, attest the REBAL BPS-sum invariant + the JACK final-day deletion side-effects, and grep-attest every cited `file:line` vs the v50.0-closure HEAD `812abeee` — paper-only, zero `contracts/*.sol`.
- [ ] **Phase 340: IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK)** - Land the single reconciled `contracts/*.sol` diff in producer-before-consumer order: the new `DegenerusGameBingoModule.sol` 3-tier color-completion entrypoint (regular / additive symbol-first / replacement quadrant-first, quadrant-first-before-symbol-first precedence, per-player (level,quadrant) dedup, `transferFromPool(Pool.Reward,…)` + `coinflip.creditFlip(…)` draws, empty-pool no-op, `gameOver` cutoff, event-only leaderboard) + the storage mappings + the `DegenerusGame.claimBingo` delegatecall + interface + the `StakedDegenerusStonk` constructor rebalance + the `JackpotModule` final-day `Pool.Reward` deletion; applied + locally compiled/tested, then HELD at the contract-commit boundary for explicit user hand-review.
- [ ] **Phase 341: TST — Per-Tier × Per-Quadrant + Tier-Precedence Suppression + Revert/Dedup + Empty-Pool + Jackpot Regression + Non-Widening** - Prove each reward tier pays the correct sDGNRS BPS + BURNIE and marks the correct bits/events; prove a quadrant-first claim SUPPRESSES the symbol-first bonus AND marks the `firstSymbol` bit; prove the full revert/dedup table (`symbol >= 32` / `gameOver` / `level > currentLevel` / non-owner slot / re-claim of a (level,quadrant) / max-4-distinct-quadrants); prove the empty-pool graceful no-op + the post-REBAL doubled-pool sizing; prove the jackpot final-day suite stays green minus the deleted `Pool.Reward` / `JackpotDgnrsWin` assertion; and prove a NON-WIDENING full-suite regression vs the v50.0 baseline.
- [ ] **Phase 342: TERMINAL — Minimal Close: Re-Attest + Atomic 5-Doc Closure Flip (Internal Sweep + FINDINGS DEFERRED → v52)** - Re-attest all 18 v51.0 requirements at closure and apply the atomic 5-doc closure flip with the `MILESTONE_V51_AT_HEAD_<sha>` signal. The internal 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface) and the v51 surface is recorded in the v52 audit-debt charge — there is NO sweep run in this milestone.

---

## Phase Details

### Phase 339: SPEC — Design-Lock + RNG-Freeze-Safety Proof + Tier-Precedence Lock + Call-Graph Attestation

**Goal**: The coupled bundle's shapes are settled in writing so the IMPL phase authors a fully reconciled diff with zero "by construction" assumptions: the `claimBingo` signature + the storage shape + the slot-type width + the reward constants + the module placement are locked, the BINGO-06 RNG-freeze safety of the `traitBurnTicket` read is PROVEN on paper before any code is written, the tier-precedence rule (quadrant-first checked BEFORE symbol-first; quadrant-first marks BOTH bits and suppresses the symbol-first bonus) is design-locked, the REBAL BPS-sum invariant + the JACK final-day deletion side-effects are attested, and every cited `file:line` is grep-verified against the v50.0-closure HEAD `812abeee` — paper-only, zero `contracts/*.sol`.
**Type**: SPEC
**Depends on**: Nothing (first v51.0 phase; consumes the v50.0 closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80` as the frozen audit baseline)
**Requirements**: BATCH-01, BINGO-06
**Success Criteria** (what must be TRUE):

  1. The full bundle design is settled in writing (BATCH-01) — the `claimBingo(uint256 level, uint8 symbol, uint32[8] slots)` signature, the module placement (new `DegenerusGameBingoModule.sol` recommended, delegatecalled from `DegenerusGame.claimBingo`), the storage shape (`bingoClaimed` per-player `uint8` / `firstQuadrant` systemwide `uint8` / `firstSymbol` systemwide `uint32`, all keyed by the existing `uint24` level), the slot-type width (`uint32` vs the `traitBurnTicket` array indexing), and the reward constants (`REGULAR_DGNRS_BPS=5` / `FIRST_SYMBOL_BONUS_DGNRS_BPS=5` / `FIRST_QUADRANT_DGNRS_BPS=50`; `REGULAR_BURNIE=1_000e18` / `FIRST_SYMBOL_BONUS_BURNIE=1_000e18` / `FIRST_QUADRANT_BURNIE=5_000e18`) are reconciled so no downstream file ships an intermediate broken state.
  2. The BINGO-06 RNG-freeze safety is PROVEN, not assumed — `claimBingo` is shown to read ONLY `traitBurnTicket[level][traitId][slots[c]]` (which is fully written at lootbox/jackpot resolution, post-RNG) and to write ONLY its own `bingoClaimed` / `firstQuadrant` / `firstSymbol` bitfields plus the two external reward calls (`transferFromPool` / `creditFlip`) — it participates in NO storage slot of any current VRF-influenced output during `rngLock`; the `traitBurnTicket[level][traitId][i]` populated-only-after-level-L-resolution invariant is attested, and the race-start semantics (claimable the moment level-N entry traits are RNG-resolved; whale frontrunning on the trait-resolution batch accepted by design) are locked — `v45-vrf-freeze-invariant` re-attested for the read on paper.
  3. The tier-precedence rule is design-locked (BATCH-01, the "Open before SPEC" item 7) — `isQuadrantFirst` is checked BEFORE `isSymbolFirst`; a quadrant-first claim is shown to mark BOTH the `firstQuadrant` AND the `firstSymbol` bit (so no later claim of that symbol can re-collect the symbol-first bonus) and to pay the REPLACEMENT reward (0.5% + 5 000) not the additive; a symbol-first claim pays the ADDITIVE reward (0.1% + 2 000) and marks the `firstSymbol` bit; a regular claim pays the baseline (0.05% + 1 000) — the precedence + suppression + bit-marking logic is written out as the IMPL acceptance contract.
  4. The REBAL BPS-sum invariant + the JACK final-day deletion side-effects are attested (BATCH-01) — the `StakedDegenerusStonk.sol:294-298` rebalance (`AFFILIATE_POOL_BPS` 3 500→3 000, `REWARD_POOL_BPS` 500→1 000) is shown to keep the pool BPS summing to 10 000 with NO change to total sDGNRS supply (only the affiliate/reward split shifts, `Pool.Reward` 50B→100B) and no other pool/constant perturbed; and the `_paySoloBucket` final-day `Pool.Reward` deletion (`DegenerusGameJackpotModule.sol:1339-1352` + the `:191` `FINAL_DAY_DGNRS_BPS=100` constant + the `:1350` `JackpotDgnrsWin` emit if grep confirms it is orphaned) is shown to leave the rest of the `isFinalDay` plumbing intact (the `:617` `lvl + 1` ticket-index gate + the `:1085/1095/1135/1161/1190/1312` `_paySoloBucket` callers) — no non-`Pool.Reward` final-day behavior is broken.
  5. Every cited `file:line` across the milestone scope is grep-verified against the v50.0-closure HEAD `812abeee` and any drift is corrected in the SPEC (no "by construction" survives un-checked) — the `traitBurnTicket` storage decl (`storage/DegenerusGameStorage.sol:404-416`), the trait byte layout `[QQ][CCC][SSS]` (`DegenerusTraitUtils.sol:17-39`), the `transferFromPool` / `poolBalance` sDGNRS pool API + the `Pool.Reward` enum, the `coinflip.creditFlip` BURNIE path, the REBAL constants (`StakedDegenerusStonk.sol:294-298`), and the JACK deletion anchors (`DegenerusGameJackpotModule.sol:191 / 617 / 1085 / 1095 / 1135 / 1161 / 1190 / 1312 / 1339-1352 / 1350`) — confirming the producer-before-consumer edit-order map for the IMPL diff.

**Plans**: 4 plans / 2 waves (paper-only, all `autonomous: true`)
- [x] 339-01-PLAN.md — BINGO-06 RNG-freeze-safety proof (structured per-slot enumeration) + `traitBurnTicket` write-site soundness attestation (D-02 IFF) + whale-race ACCEPTED-BY-DESIGN non-finding (D-03) [Wave 1]
- [ ] 339-02-PLAN.md — BINGO design-lock (signature + `uint32` slot-width disposition + storage shape + module placement + reward constants D-05) + the tier-precedence acceptance contract (D-06: quadrant-first-before-symbol-first + suppression) [Wave 1]
- [ ] 339-03-PLAN.md — REBAL BPS-sum attestation (full pool-BPS set → 10000, incl `CREATOR_BPS=2000` at `:291`) + JACK final-day deletion side-effects (D-12) + grep-attestation vs `812abeee` + producer-before-consumer edit-order map (D-13) [Wave 1]
- [ ] 339-04-PLAN.md — SPEC-INDEX + multi-source coverage audit (GOAL/REQ/RESEARCH-N-A/CONTEXT D-01..D-13 → ALL items COVERED) [Wave 2, depends on 01/02/03]
**UI hint**: no

### Phase 340: IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK)

**Goal**: The three coupled contract items land as a single reconciled `contracts/*.sol` diff under the SPEC's settled shapes — the new `DegenerusGameBingoModule.sol` implements the 3-tier `claimBingo` color-completion entrypoint (validates `symbol < 32` / `!gameOver` / `level <= currentLevel`; derives `quadrant = symbol >> 3` / `symInQ = symbol & 7`; verifies the caller owns one `traitBurnTicket[level][traitId][slots[c]]` entry for each color `c ∈ [0,7]`; selects regular / additive symbol-first / replacement quadrant-first with quadrant-first-before-symbol-first precedence; draws `Pool.Reward` via `transferFromPool` with an empty-pool graceful no-op; pays BURNIE via `coinflip.creditFlip`; emits the event-only leaderboard) wired into `DegenerusGame.claimBingo` via delegatecall + interface with the new `bingoClaimed` / `firstQuadrant` / `firstSymbol` storage mappings; the `StakedDegenerusStonk` constructor rebalance doubles `Pool.Reward` (AFFILIATE 3 500→3 000 / REWARD 500→1 000); and the jackpot final-day `Pool.Reward` branch is deleted — applied + locally compiled/tested, then HELD at the contract-commit boundary for explicit user hand-review.
**Type**: IMPL (CONTRACT BOUNDARY — the ONE batched USER-APPROVED `contracts/*.sol` diff; `autonomous: false` at the commit gate; never auto-commit contracts)
**Depends on**: Phase 339 (the SPEC must settle the signature/storage/constants + PROVE the BINGO-06 freeze safety + lock the tier-precedence rule + attest the REBAL/JACK side-effects + grep-attest the edit-order map first)
**Requirements**: BINGO-01, BINGO-02, BINGO-03, BINGO-04, BINGO-05, REBAL-01, JACK-01, JACK-02, BATCH-02
**Success Criteria** (what must be TRUE):

  1. The `claimBingo` entrypoint + ownership validation exists (BINGO-01) — a new external `claimBingo(uint256 level, uint8 symbol, uint32[8] slots)` (in the new `DegenerusGameBingoModule.sol`, delegatecalled from `DegenerusGame`) validates `symbol < 32` / `!gameOver` / `level <= currentLevel`, derives `quadrant = symbol >> 3` and `symInQ = symbol & 7`, and for each color `c ∈ [0,7]` requires `traitBurnTicket[level][traitId][slots[c]] == msg.sender` where `traitId = (quadrant<<6) | (c<<3) | symInQ` (trait byte `[QQ][CCC][SSS]`); duplicate-slot griefing is impossible because each trait byte encodes exactly one (quadrant, color, symbol).
  2. Per-player (level, quadrant) dedup + the 3-tier reward selection with quadrant-first-before-symbol-first precedence are built in (BINGO-02 / BINGO-03) — `bingoClaimed[level][msg.sender]` enforces at most one claim per quadrant (max 4 per level; a repeat reverts), and the tier is selected with `isQuadrantFirst` checked BEFORE `isSymbolFirst`: quadrant-first → replacement (0.5% `Pool.Reward` + 5 000 BURNIE), marks BOTH the `firstQuadrant` AND `firstSymbol` bits and suppresses the symbol-first bonus; symbol-first (not quadrant-first) → additive (0.1% + 2 000), marks the `firstSymbol` bit; regular (both set) → baseline (0.05% + 1 000).
  3. The reward draws + the empty-pool no-op + the event-only leaderboard + the `gameOver` cutoff are wired (BINGO-04 / BINGO-05) — the sDGNRS reward draws from `Pool.Reward` via `sdgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, msg.sender, (poolBal * bps)/10_000)` (using the clamped return as the paid amount) and the BURNIE reward via `coinflip.creditFlip(msg.sender, amount)`; an empty/0-amount `Pool.Reward` is a graceful no-op (claim/first bits set + BURNIE paid, `dgnrsPaid == 0`); `FirstQuadrantBingo` / `FirstSymbolBingo` / `BingoClaimed` are emitted with no on-chain winner storage beyond the bitfields; the storage adds `bingoClaimed` (per-player `uint8`) + `firstQuadrant` (systemwide `uint8`) + `firstSymbol` (systemwide `uint32`) keyed by the `uint24` level; and `claimBingo` reverts once `gameOver == true`.
  4. The REBAL sDGNRS `Pool.Reward` rebalance lands (REBAL-01) — `StakedDegenerusStonk.sol:294-298` constructor constants are `AFFILIATE_POOL_BPS` 3 500→3 000 and `REWARD_POOL_BPS` 500→1 000, doubling `Pool.Reward` 50B→100B sDGNRS with NO change to total sDGNRS supply (the pool BPS still sum to 10 000; affiliate per-share takes a ~14% haircut), and no other pool/constant is perturbed.
  5. The JACK final-day `Pool.Reward` deletion lands with the rest of the `isFinalDay` plumbing preserved, and the diff is HELD at the contract-commit boundary (JACK-01 / JACK-02 / BATCH-02) — the `isFinalDay` `Pool.Reward` branch in `_paySoloBucket` (`DegenerusGameJackpotModule.sol:1339-1352`) + the `FINAL_DAY_DGNRS_BPS = 100` constant (`:191`) + the `JackpotDgnrsWin` event (if grep confirms it has no other emitter) are removed while the `lvl + 1` ticket-index gate (`:617`) and the `_paySoloBucket` callers passing `isFinalDay` (`:1085/1095/1135/1161/1190/1312`) are untouched; the whole diff is authored producer-before-consumer per the SPEC edit-order map, applied to `contracts/` and locally compiling/tested (`ContractAddresses.sol` freely modifiable), but NOT committed without explicit user hand-review of the single batched diff.

**Plans**: TBD
**UI hint**: no

### Phase 341: TST — Per-Tier × Per-Quadrant + Tier-Precedence Suppression + Revert/Dedup + Empty-Pool + Jackpot Regression + Non-Widening

**Goal**: The bundle is proven behaviorally correct empirically — each reward tier (regular / additive symbol-first / replacement quadrant-first) pays the correct sDGNRS BPS + BURNIE and marks the correct bits/events across the relevant quadrants; a quadrant-first claim SUPPRESSES the symbol-first bonus AND marks the `firstSymbol` bit so a subsequent same-symbol non-quadrant-first claim collects only the regular reward; the full revert/dedup table holds; the empty-pool graceful no-op + the post-REBAL doubled-pool sizing are demonstrated; the jackpot final-day suite stays green minus the deleted `Pool.Reward` / `JackpotDgnrsWin` assertion with no other final-day behavior regressed; and the full suite is NON-WIDENING vs the v50.0 baseline — restoring a clean v51.0 regression baseline.
**Type**: TST
**Depends on**: Phase 340 (tests exercise the applied diff — the live `claimBingo` tier selection, the dedup bits, the `Pool.Reward` draws, the JackpotModule deletion — not SPEC placeholders)
**Requirements**: TST-01, TST-02, TST-03, TST-04, TST-05, TST-06
**Success Criteria** (what must be TRUE):

  1. Per-tier × per-quadrant happy path is proven (TST-01) — a regular claim pays 0.05% `Pool.Reward` + 1 000 BURNIE; a symbol-first claim pays the additive 0.1% + 2 000 and marks the `firstSymbol` bit; a quadrant-first claim pays the replacement 0.5% + 5 000 and marks BOTH the `firstQuadrant` AND `firstSymbol` bits — each verified across the relevant quadrants, with the bits and the emitted `FirstQuadrantBingo` / `FirstSymbolBingo` / `BingoClaimed` events asserted.
  2. Tier-precedence suppression is proven (TST-02) — a quadrant-first claim SUPPRESSES the symbol-first bonus AND marks the `firstSymbol` bit, so a subsequent non-quadrant-first claim of the same symbol on the same level collects only the regular reward (0.05% + 1 000), NOT the symbol-first bonus (covers the "Open before SPEC" item 7).
  3. The revert + dedup table is proven (TST-03) — `symbol >= 32` reverts; `gameOver == true` reverts; `level > currentLevel` reverts; a slot whose `traitBurnTicket` owner ≠ `msg.sender` reverts; a second claim of an already-claimed (level, quadrant) reverts; and a player can make at most 4 distinct-quadrant claims per level.
  4. The empty-pool graceful no-op + the post-REBAL sizing are proven (TST-04) — a claim against an empty (or 0-amount) `Pool.Reward` still succeeds with the claim/first bits set and the BURNIE flip credit paid (`dgnrsPaid == 0`), and the post-REBAL doubled-pool sizing is reflected (e.g. a level-1 quadrant-first ≈ 0.5% × 100B = 500M sDGNRS).
  5. The jackpot final-day regression + the NON-WIDENING full-suite regression are proven (TST-05 / TST-06) — the existing final-day jackpot test suite stays green minus the deleted `Pool.Reward` / `JackpotDgnrsWin` assertion (updated to drop it), with no other final-day behavior (the `lvl + 1` ticket-index path, the solo-bucket payout) regressed; and the full suite is NON-WIDENING vs the v50.0 closure baseline `812abeee` (net-zero new regression — every pre-existing red enumerated and guarded BY NAME), absorbing any test renames / oracle migrations from the bundle, with a clean v51.0 regression baseline ledger recorded.

**Plans**: TBD
**UI hint**: no

### Phase 342: TERMINAL — Minimal Close: Re-Attest + Atomic 5-Doc Closure Flip (Internal Sweep + FINDINGS DEFERRED → v52)

**Goal**: The v51.0 audit subject (the single batched diff — the `claimBingo` 3-tier color-completion entrypoint + the sDGNRS `Pool.Reward` rebalance + the jackpot final-day `Pool.Reward` deletion, FROZEN at the IMPL HEAD) is closed via a MINIMAL CLOSE: all 18 v51.0 requirements are re-attested at closure and the milestone is closed with the `MILESTONE_V51_AT_HEAD_<sha>` signal and the atomic 5-doc closure flip. The internal 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface) and the v51 surface is recorded in the v52 audit-debt charge — there is NO sweep run in this milestone. Mitigation already in place: SPEC (339) PROVED freeze-safety (BINGO-06) + the tier-precedence rule, and TST (341) proved the per-tier rewards / dedup / empty-pool no-op / jackpot-final-day regression; pre-launch (no live funds); v51 contract history UNPUSHED.
**Type**: TERMINAL (minimal close — re-attest + closure flip; the internal sweep + FINDINGS DEFERRED → v52)
**Depends on**: Phase 341 (the subject must be implemented + test-proven before the requirements are re-attested at closure)
**Requirements**: BATCH-03
**Success Criteria** (what must be TRUE):

  1. All 18 v51.0 requirements are re-attested at closure (BATCH-03) — BINGO-01..06 + REBAL-01 + JACK-01/02 + TST-01..06 + BATCH-01/02 are confirmed satisfied against the frozen v51.0 closure HEAD (the `claimBingo` 3-tier entrypoint shipped with quadrant-first-before-symbol-first precedence + (level,quadrant) dedup + `transferFromPool`/`creditFlip` draws + empty-pool no-op + `gameOver` cutoff; the `Pool.Reward` rebalance 50B→100B with the BPS-sum invariant intact; the jackpot final-day `Pool.Reward` deletion with the rest of the `isFinalDay` plumbing preserved; freeze-safety PROVEN at SPEC + tested at TST; NON-WIDENING regression).
  2. The closure flip is applied (BATCH-03) — the `MILESTONE_V51_AT_HEAD_<sha>` closure signal is emitted and propagated verbatim, and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) is applied; the closure plan is a single blocking USER closure-verdict + signal-format approval gate (`autonomous: false`) — the auto-advance is HELD at the closure boundary per `feedback_pause_at_contract_phase_boundaries`.
  3. The DEFERRED audit charge is recorded (BATCH-03) — the internal 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) + delta-audit + `audit/FINDINGS-v51.0.md` are explicitly recorded as DEFERRED → the v52 consolidated audit (which MUST cover the cumulative v50 + v51 contract surface per the STATE.md audit-debt note), with the v51 surface (the `claimBingo` / `DegenerusGameBingoModule.sol` tier-selection + dedup + pool draws + freeze read, the `Pool.Reward` rebalance, the jackpot final-day deletion side-effects) enumerated in the v52 charge — NO sweep is run and NO `audit/FINDINGS-v51.0.md` is authored in this milestone.

**Plans**: TBD
**UI hint**: no

---

## Progress

**Execution Order:** Phases execute in numeric order: 339 → 340 → 341 → 342

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 339. SPEC — Design-Lock + Freeze Proof + Tier-Precedence + Attestation | v51.0 | 1/4 | In Progress|  |
| 340. IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK) | v51.0 | 0/TBD | Not started | - |
| 341. TST — Per-Tier + Precedence + Revert/Dedup + Empty-Pool + Jackpot + Non-Widening | v51.0 | 0/TBD | Not started | - |
| 342. TERMINAL — Minimal Close: Re-Attest + Closure Flip (Sweep DEFERRED → v52) | v51.0 | 0/TBD | Not started | - |

> **🔒 v51.0 AUDIT POSTURE — MINIMAL CLOSE (USER decision 2026-05-28 at milestone start).** v51 ships 339 SPEC → 340 IMPL → 341 TST → 342 TERMINAL (minimal close). Phase 342's internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are DEFERRED → the v52 consolidated audit, which MUST cover the cumulative v50 + v51 contract surface. Rationale: pre-launch (no live funds); BINGO-06 freeze-safety PROVEN at SPEC + tested at TST; tier-precedence locked at SPEC + proven at TST. Mirrors the v45.0 + v50.0 minimal-close precedent. There is NO SWEEP/AUDIT phase and NO GAS phase in v51.0.

---

## Coverage (v51.0)

**18/18 v51.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 339 SPEC | BATCH-01, BINGO-06 | 2 |
| 340 IMPL | BINGO-01, BINGO-02, BINGO-03, BINGO-04, BINGO-05, REBAL-01, JACK-01, JACK-02, BATCH-02 | 9 |
| 341 TST | TST-01, TST-02, TST-03, TST-04, TST-05, TST-06 | 6 |
| 342 TERMINAL | BATCH-03 | 1 |
| **Total** | | **18** |

**Per-category split (verification):**

| Category | Total | SPEC | IMPL | TST | TERMINAL |
|----------|-------|------|------|-----|----------|
| BINGO | 6 | 1 (06) | 5 (01,02,03,04,05) | — | — |
| REBAL | 1 | — | 1 (01) | — | — |
| JACK | 2 | — | 2 (01,02) | — | — |
| TST | 6 | — | — | 6 (01–06) | — |
| BATCH | 3 | 1 (01) | 1 (02) | — | 1 (03) |
| **Total** | **18** | **2** | **9** | **6** | **1** |

**Center-of-gravity rationale (where a requirement spans design + impl + test):**

- **BINGO-06** (the RNG-freeze-safety PROOF — `claimBingo` reads only the post-resolution `traitBurnTicket` and writes only its own claim/first bitfields → no current-VRF-window slot during `rngLock`) → SPEC (339), where it is PROVEN on paper as the design-gating attestation that confirms the read-only shape is freeze-safe BEFORE the entrypoint is authored. Its empirical coverage is folded into the TST happy-path / regression suite (341) — it is NOT re-counted there.
- **BINGO-01..05 + REBAL-01 + JACK-01/02** (the build) → IMPL (340) as the single batched diff (the `claimBingo` 3-tier entrypoint + storage + the sDGNRS rebalance + the jackpot final-day deletion). The tier-precedence rule (BINGO-03), the REBAL BPS-sum invariant (REBAL-01), and the JACK final-day deletion side-effects (JACK-01/02) are SPEC concerns folded into BATCH-01 — they are not double-counted at SPEC; only the requirement's HOME (where it must be BUILT) is counted.
- **TST-01..06** (the proofs) → TST (341). TST-01..05 are the per-tier / precedence-suppression / revert-dedup / empty-pool / jackpot-regression proofs; TST-06 is the NON-WIDENING full-suite regression vs the v50.0 baseline. They do not "uncover" the IMPL reqs — they re-prove them empirically.
- **BATCH-01** (the single SPEC design-lock) absorbs the signature/storage/constant reconciliation + the tier-precedence lock + the REBAL/JACK attestations + the grep-attestation; it does not duplicate the BINGO/REBAL/JACK requirements those decisions feed.
- **BATCH-02** (the single batched contract diff + the contract-commit HARD STOP) → IMPL (340); the diff is authored producer-before-consumer per the SPEC edit-order map.
- **BATCH-03** (the TERMINAL minimal close) re-attests all 18 v51.0 requirements at closure + applies the atomic 5-doc closure flip with the `MILESTONE_V51_AT_HEAD_<sha>` signal. The internal sweep + delta-audit + `audit/FINDINGS-v51.0.md` are DEFERRED → the v52 consolidated audit — there is NO SWEEP category and NO sweep run in v51.0.

✓ All 18 v51.0 requirements mapped
✓ No orphaned requirements
✓ No duplicated requirements

**Note on §13e-style "uncovered" warnings:** as in the v44–v50 roadmaps, milestone-wide "uncovered" warnings are EXPECTED false alarms — each phase owns only its slice; BATCH-03 re-attests the full 18-requirement set at the TERMINAL minimal close (342). The TST / TERMINAL phases do not "uncover" the IMPL reqs — they re-prove and re-attest them.

**Note on the deferred sweep:** v51 plans NO SWEEP category and NO GAS phase. The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are out of v51 scope by USER decision (minimal close) and are the v52 consolidated audit's charge over the cumulative v50 + v51 surface. v51's own regression bar is TST-06 (NON-WIDENING vs the v50.0 baseline); its security proof is BINGO-06 (freeze) + TST-01..05 (per-tier / precedence / dedup / empty-pool / jackpot-regression).

---

<details>
<summary>✅ v50.0 Whale-Pass O(1) Refactor + AfKing Pass-Gated Subs + MintModule Advance-Divergence + External RNG-Audit Protocol (Phases 334-338) — CLOSED 2026-05-28 (minimal close)</summary>

**Closure:** MINIMAL CLOSE (USER-approved 2026-05-28) — closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80`; NO formal `MILESTONE_V50_AT_HEAD` signal emitted. Phases 334 SPEC + 335 IMPL + 336 TST + 337 AUDIT-PROTOCOL all Complete (21/25 reqs). **Phase 338's internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v50.0.md` are DEFERRED → the v52 consolidated audit** (SWEEP-01/02/03 + the findings/flip portion of BATCH-03), which MUST cover the cumulative v50 + v51 contract surface. Audit baseline → subject: v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` → v50.0 closure HEAD. Shape: SPEC → IMPL → TST → AUDIT-PROTOCOL → TERMINAL (the established v44–v49 audit shape + a dedicated package-only AUDIT-PROTOCOL phase). Rationale: pre-launch (no live funds); WHALE-04 freeze-safety PROVEN at SPEC + tested at TST. Mirrors the v45.0 minimal-close precedent. v50 contract history UNPUSHED.

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 334. SPEC — Design-Lock + MINTDIV Reachability + RNGAUDIT Structure | 4/4 | Complete | 2026-05-27 |
| 335. IMPL — The ONE Batched Contract Diff (WHALE + AFSUB + MINTDIV-if-real) | 7/7 | Complete | 2026-05-28 |
| 336. TST — Equivalence + Freeze + Divergence + Regression | 6/6 | Complete | 2026-05-28 |
| 337. AUDIT-PROTOCOL — External-LLM RNG-Audit Kit (Package-Only) | 4/4 | Complete | 2026-05-28 |
| 338. TERMINAL — Internal Delta Audit + Sweep + Closure | 0/4 | 🔒 DEFERRED → v52 (minimal close) | 2026-05-28 |

**Coverage:** 25/25 requirements mapped (334: 3 · 335: 10 · 336: 4 · 337: 4 · 338: 4); 0 orphaned, 0 duplicated. Per-category: WHALE 4 · AFSUB 5 · MINTDIV 2 · RNGAUDIT 4 · TST 4 · SWEEP 3 · BATCH 3. Closed verdict: WHALE_O1_CLAIM + AFKING_PASS_GATED_SUBS + MINTDIV_ALIGNED + EXTERNAL_RNG_AUDIT_KIT shipped; KNOWN_ISSUES_UNMODIFIED. SWEEP-01/02/03 + the BATCH-03 findings/flip portion = the v52 charge. Full detail in `.planning/MILESTONES.md`. v51 seed captured at start: `v51-claimbingo-color-completion-seed` (the v51.0 contract bundle).

</details>

<details>
<summary>✅ v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep (Phases 329-333) — SHIPPED 2026-05-27</summary>

**Closure signal:** `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (subject FROZEN `4c9f9d9b`; 0 NEW findings [21 probes: 15 NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN]; OPEN-E 4-protection HOLD without `:676`; RNG-freeze intact; 666/42/17 by NAME). Audit baseline → subject: v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` → v49.0 closure HEAD. ONE batched USER-APPROVED diff `63bc16ca` + the 331 GAS re-peg `4c9f9d9b`. Shape: SPEC → IMPL → GAS → TST → TERMINAL (the dedicated GAS phase because the break-even bounty re-peg was load-bearing). **PUSHED to origin/main 2026-05-27** (`0d9d321f`→`5803da95`, 274 commits — published the prior-unpushed v46/v47/v48/v49 contract history).

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 329. SPEC — Design-Lock + 4 Structural Invariants | 3/3 | Complete | 2026-05-26 |
| 330. IMPL — The ONE Batched Contract Diff (router + advance-rework + micro-opts) | 9/9 | Complete | 2026-05-27 |
| 331. GAS — Worst-Case Marginal + Break-Even @0.5gwei Peg | 6/5 | Complete | 2026-05-27 |
| 332. TST — Freeze Fuzz + One-Category + Regression | 6/6 | Complete | 2026-05-27 |
| 333. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 4/4 | Complete | 2026-05-27 |

**Coverage:** 36/36 requirements mapped (329 SPEC: 4 · 330 IMPL: 18 · 331 GAS: 5 · 332 TST: 5 · 333 TERMINAL: 4, re-attests all 36); 0 orphaned, 0 duplicated. Per-category: ROUTER 10 · ADV 5 · GAS 6 · GASOPT 4 (GASOPT-02 SUBSUMED into GASOPT-03) · TST 5 · SWEEP 3 · BATCH 3. Closure verdict: UNIFIED_KEEPER_ROUTER + ADVANCE_BOUNTY_RE-HOMED + BOUNTY_RE-PEGGED @0.5gwei + DEGENERETTE_RESOLVE RENAMED + GASOPT-01/03/04/05; 5 surfaces NON-WIDENING; OPEN-E 4-protection HOLD without `:676`; RNG_FREEZE_INTACT; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED. Full detail in `.planning/MILESTONES.md` + `audit/FINDINGS-v49.0.md` (chmod 444). v50 seeds captured at closure: `v49-whale-pass-claim-refactor-seed` + `v50-afking-pass-only-sub-simplify-seed` + `mintmodule-processed-advance-divergence-seed` (the three v50.0 contract items).

</details>

<details>
<summary>✅ v48.0 sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle (Phases 325-328) — SHIPPED 2026-05-26</summary>

**Closure signal:** `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (subject frozen `1575f4a9`; 0 NEW findings; F-47-01 + F-47-02 RESOLVED_AT_V48). Audit baseline → subject: v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` → v48.0 closure HEAD. ONE batched USER-APPROVED diff `f50cc634` + the 327 HERO-04 constant-only finals landing `1575f4a9`. Shape: SPEC → IMPL → TST → TERMINAL.

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 325. SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation | 3/3 | Complete | 2026-05-25 |
| 326. IMPL — The ONE Batched Contract Diff (all 7 items) | 8/8 | Complete | 2026-05-25 |
| 327. TST — Repro/Same-Results + No-Arb + EV + Regression Proofs | 6/6 | Complete | 2026-05-26 |
| 328. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 4/4 | Complete | 2026-05-26 |

**Coverage:** 40/40 requirements mapped (325 SPEC: 5 · 326 IMPL: 25 · 327 TST: 9 · 328 TERMINAL: 1, re-attests all 40); 0 orphaned, 0 duplicated. Per-category: PFIX 3 · RFALL 5 · KEEP 5 · POOL 6 · BTOMB 3 · HERO 6 · SWAP 9 · BATCH 3. Closure verdict: all 7 surfaces shipped (presale-drain fix, redemption stETH-fallback, keeper rename + VAULT-code 75/20/5, AfKing pool recovery, gameover BURNIE tombstone, Degenerette hero 2-pt rescale, sDGNRS far-future salvage swap); RNG_FREEZE_INTACT; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED. One informational SWAP cash-share doc-drift advisory (USER-accepted ≤60% as canonical, NOT a finding). Full detail in `.planning/MILESTONES.md` + `audit/FINDINGS-v48.0.md` (chmod 444).

</details>

<details>
<summary>✅ v44.0–v47.0 (Phases 304-324) — SHIPPED</summary>

Full per-phase detail for v44.0 (304-308), v45.0 (309-314), v46.0 (316-320), and v47.0 (321-324) lives in `.planning/MILESTONES.md`. Summary:

- **v47.0** Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle (321-324, shipped 2026-05-25; signal `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`). 4-phase SPEC→IMPL→TST→TERMINAL; 45/45 reqs. 2 MEDIUM findings (F-47-01 + F-47-02) DEFERRED→v48.0 (both RESOLVED_AT_V48). H-CANCEL-SWAP-MISS RESOLVED_AT_V47.
- **v46.0** Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (316-320, shipped 2026-05-24; signal `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`). 6-phase FEATURE milestone with the dedicated GAS phase 319 (the break-even peg precedent v49.0 mirrored); the in-tree `AfKing` keeper shipped here. 1 MEDIUM finding H-CANCEL-SWAP-MISS DEFERRED→v47.0 (RESOLVED_AT_V47).
- **v45.0** VRF-Rotation Liveness Fix + Consolidate-Forward Delta Audit (309-314, shipped 2026-05-23, minimal close; signal `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`). The CATASTROPHE-class VRF-rotation orphan-index liveness fix; the `v45-vrf-freeze-invariant` north-star established here. **The minimal-close precedent v50.0 + v51.0 mirror.**
- **v44.0** sStonk Per-Day Redemption Refactor + Accounting Invariant Proof (304-308, shipped 2026-05-20; signal `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`). V-184 CATASTROPHE structurally closed; 13/13 invariants proven.

</details>

---
*Roadmap created: 2026-05-25 (v48.0)*
*v49.0 milestone added: 2026-05-26 (5 phases 329-333, SPEC→IMPL→GAS→TST→TERMINAL; 36 reqs / 7 categories) — SHIPPED 2026-05-27, archived to the collapsed block above.*
*v50.0 milestone added: 2026-05-27 (5 phases 334-338, SPEC→IMPL→TST→AUDIT-PROTOCOL→TERMINAL; 25 reqs / 7 categories: WHALE 4 · AFSUB 5 · MINTDIV 2 · RNGAUDIT 4 · TST 4 · SWEEP 3 · BATCH 3) — CLOSED 2026-05-28 via minimal close (Phase 338 sweep + FINDINGS DEFERRED → v52); archived to the collapsed block above.*
*v51.0 milestone added: 2026-05-28 (4 phases 339-342, SPEC→IMPL→TST→TERMINAL; 18 reqs / 5 categories: BINGO 6 · REBAL 1 · JACK 2 · TST 6 · BATCH 3). Phase numbering continues from 338 → 339. Established audit-milestone shape run to a MINIMAL CLOSE (USER decision 2026-05-28): NO SWEEP/AUDIT phase + NO GAS phase; the internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface). Contract-boundary HARD STOP at the single IMPL phase (340). Baseline = v50.0 closure HEAD `812abeee` (minimal-close commit, no formal signal). BINGO-06 freeze-safety PROVEN at SPEC + tested at TST; tier-precedence locked at SPEC + proven at TST.*
