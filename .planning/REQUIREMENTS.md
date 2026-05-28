# Requirements: Degenerus Protocol — v51.0 claimBingo — Color-Completion Claim

**Milestone:** v51.0 (started 2026-05-28)
**Audit baseline → subject:** v50.0 closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80` (the minimal-close commit; no formal `MILESTONE_V50_AT_HEAD` signal was emitted) → v51.0 closure HEAD. Every cited `file:line` MUST be re-attested vs the v50.0-closure HEAD before any patch.
**Scope source:** the milestone init (2026-05-28) + the v51 forward-seed (`v51-claimbingo-color-completion-seed`) + the locked design doc `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md`. No research (a fully-specced contract feature with game-theory / Monte-Carlo analysis already done in the plan doc).
**Posture:** one coupled contract bundle (BINGO + REBAL + JACK) ships as ONE batched USER-APPROVED `contracts/*.sol` diff; HARD STOP at the commit boundary (`feedback_batch_contract_approval`). Security / RNG-freeze floor over gas (`feedback_security_over_gas`): `claimBingo` is a READ-ONLY consumer of the post-RNG-resolution `traitBurnTicket` map and writes only its own claim/first bitfields → freeze-safe by construction, RE-PROVEN at SPEC, not assumed (`v45-vrf-freeze-invariant`). Pre-launch redeploy-fresh (storage break + constructor-only constant change both fine; no migration).

---

> **🔒 v51.0 AUDIT POSTURE — MINIMAL CLOSE (USER decision 2026-05-28 at milestone start).** v51 ships SPEC → IMPL → TST → TERMINAL with a minimal close. The internal 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) + delta-audit + `audit/FINDINGS-v51.0.md` are **DEFERRED → the v52 consolidated audit**, which MUST cover the cumulative **v50 + v51** contract surface (see the STATE.md audit-debt note). v51 is NOT unaudited: SPEC (339) PROVES freeze-safety + tier-precedence, and TST (341) proves the per-tier rewards / dedup / empty-pool no-op / jackpot-final-day regression — only the adversarial-hunt + formal-findings layer is batched into v52. The Traceability table is the authoritative per-req status.

---

## v51.0 Requirements

### claimBingo Color-Completion Entrypoint (BINGO)
- [ ] **BINGO-01**: A new external `claimBingo(uint256 level, uint8 symbol, uint32[8] slots)` entrypoint exists (likely in a new `DegenerusGameBingoModule.sol` delegatecalled from `DegenerusGame`). It validates `symbol < 32`, `!gameOver`, `level <= currentLevel`; derives `quadrant = symbol >> 3` and `symInQ = symbol & 7`; and for each color `c ∈ [0,7]` verifies the caller owns the entry at `traitBurnTicket[level][traitId][slots[c]]` where `traitId = (quadrant<<6) | (c<<3) | symInQ` (trait byte layout `[QQ][CCC][SSS]`). Duplicate-slot griefing is impossible because each trait byte encodes exactly one (quadrant, color, symbol).
- [ ] **BINGO-02**: Per-player dedup is enforced once per (level, quadrant) via a `bingoClaimed[level][msg.sender]` quadrant-mask bit — a second claim of the same quadrant on the same level reverts. A player may make at most 4 bingo claims per level (one per quadrant A/B/C/D).
- [ ] **BINGO-03**: Three reward tiers are selected with **quadrant-first checked BEFORE symbol-first** precedence: (a) **quadrant-first** (`firstQuadrant[level]` bit unset) → replacement reward (0.5% `Pool.Reward` + 5 000 BURNIE), marks BOTH the `firstQuadrant` AND `firstSymbol` bits and **suppresses** the symbol-first bonus; (b) **symbol-first** (`firstSymbol[level]` bit unset, not quadrant-first) → regular + additive bonus (0.05%+0.05% = 0.1% `Pool.Reward` + 1 000+1 000 = 2 000 BURNIE), marks the `firstSymbol` bit; (c) **regular** (both set) → 0.05% `Pool.Reward` + 1 000 BURNIE. A quadrant-first claim marking the symbol-first bit guarantees no later claim of that symbol can re-collect the symbol-first bonus.
- [ ] **BINGO-04**: The sDGNRS reward draws from `Pool.Reward` via `sdgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, msg.sender, (poolBal * bps) / 10_000)` (using `transferFromPool`'s clamped return as the paid amount); the BURNIE reward is paid via `coinflip.creditFlip(msg.sender, amount)`. Empty-pool behavior is a graceful no-op: if `poolBalance(Pool.Reward) == 0` or the computed amount is 0, the claim still succeeds (claim/first bits set + BURNIE flip credit paid, `dgnrsPaid == 0`) — matching the Degenerette / coinflip-bounty pattern.
- [ ] **BINGO-05**: Leaderboard is event-only — `FirstQuadrantBingo`, `FirstSymbolBingo`, and `BingoClaimed` are emitted; there is no on-chain winner storage beyond the `firstQuadrant` / `firstSymbol` bitfields. Storage additions: `bingoClaimed` (per-player `uint8`, 4 bits used), `firstQuadrant` (systemwide `uint8`, 4 bits), `firstSymbol` (systemwide `uint32`, 32 bits), all keyed by the existing `uint24` level key. `gameOver` is a hard cutoff (`claimBingo` reverts once `gameOver == true`).
- [x] **BINGO-06**: RNG-freeze safety is PROVEN (not assumed): `claimBingo` reads only `traitBurnTicket`, which is fully written at lootbox/jackpot resolution (post-RNG), and writes only its own `bingoClaimed` / `firstQuadrant` / `firstSymbol` bitfields + the two external reward calls — it participates in NO storage slot of any current VRF-influenced output during `rngLock`. The `traitBurnTicket[level][traitId][i]` populated-only-after-level-L-resolution invariant is attested, and the race-start semantics (claimable the moment level-N entry traits are RNG-resolved; whale frontrunning on the trait-resolution batch accepted by design) are locked at SPEC.

### Co-requisite sDGNRS Pool.Reward Rebalance (REBAL)
- [ ] **REBAL-01**: `StakedDegenerusStonk.sol:294-298` constructor constants are rebalanced — `AFFILIATE_POOL_BPS` 3 500 → 3 000 and `REWARD_POOL_BPS` 500 → 1 000 — doubling `Pool.Reward` from 50B to 100B sDGNRS with NO change to total sDGNRS supply (the pool BPS still sum to 10 000; affiliate per-share distribution takes a ~14% haircut). Constructor-only constant change → viable only pre-deploy. SPEC attests the BPS-sum invariant and that no other pool/constant is perturbed.

### Jackpot Final-Day Pool.Reward Deletion (JACK)
- [ ] **JACK-01**: The `isFinalDay` `Pool.Reward` branch in `_paySoloBucket` (`DegenerusGameJackpotModule.sol:1339-1352`) is DELETED, along with the `FINAL_DAY_DGNRS_BPS = 100` constant (`:191`) and the `JackpotDgnrsWin` event if grep confirms it has no other emitter. The one-shot final-day `Pool.Reward` draw (today 1% to the final-day jackpot solo winner) is removed; `Pool.Reward` distribution now flows through `claimBingo` instead.
- [ ] **JACK-02**: The remaining `isFinalDay` plumbing is PRESERVED — the `lvl + 1` ticket-index gate (`:617`) and the `_paySoloBucket` callers passing `isFinalDay` (`:1085 / 1095 / 1135 / 1161 / 1190 / 1312`) are untouched; only the `Pool.Reward` draw is removed. SPEC attests no non-`Pool.Reward` final-day behavior is broken by the deletion.

### Test Proofs (TST)
- [ ] **TST-01**: Per-tier × per-quadrant happy path — a regular claim pays 0.05% `Pool.Reward` + 1 000 BURNIE; a symbol-first claim pays the additive 0.1% + 2 000 (and marks the `firstSymbol` bit); a quadrant-first claim pays the replacement 0.5% + 5 000 (and marks BOTH bits) — each verified across the relevant quadrants, with bits and emitted events asserted.
- [ ] **TST-02**: Tier-precedence suppression — a quadrant-first claim SUPPRESSES the symbol-first bonus AND marks the `firstSymbol` bit, so a subsequent non-quadrant-first claim of the same symbol on the same level collects only the regular reward (not the symbol-first bonus). (Covers "Open before SPEC" item 7.)
- [ ] **TST-03**: Revert + dedup table — `symbol >= 32` reverts; `gameOver == true` reverts; `level > currentLevel` reverts; a slot whose `traitBurnTicket` owner ≠ `msg.sender` reverts; a second claim of an already-claimed (level, quadrant) reverts; a player can make at most 4 distinct-quadrant claims per level.
- [ ] **TST-04**: Empty-pool graceful no-op — a claim against an empty (or 0-amount) `Pool.Reward` still succeeds with the claim/first bits set and the BURNIE flip credit paid (`dgnrsPaid == 0`); and the post-REBAL doubled-pool sizing is reflected (e.g. a level-1 quadrant-first ≈ 0.5% × 100B = 500M sDGNRS).
- [ ] **TST-05**: Jackpot final-day regression — the existing final-day jackpot test suite stays green minus the deleted `Pool.Reward` / `JackpotDgnrsWin` assertion (updated to drop it); no other final-day behavior (the `lvl + 1` ticket-index path, solo-bucket payout) regresses.
- [ ] **TST-06**: Full-suite regression is NON-WIDENING vs the v50.0 closure baseline (net-zero new regression; any pre-existing reds enumerated and guarded BY NAME), absorbing any test renames/oracle migrations from the bundle.

### Cross-Cutting — SPEC Reconciliation + IMPL + TERMINAL (BATCH)
- [ ] **BATCH-01**: SPEC design-lock — settle module placement (new `DegenerusGameBingoModule.sol` recommended), the storage shape (`bingoClaimed` / `firstQuadrant` / `firstSymbol` + the `uint24` key), the slot type width (`uint32` vs the `traitBurnTicket` array indexing), the reward constants, and the `claimBingo` signature; resolve all 7 "Open before SPEC" items from the plan doc (module placement · slot width · view-helper-out-of-scope · `traitBurnTicket` post-resolution invariant · RNG-freeze interaction · jackpot final-day deletion side-effects · tier-precedence test coverage); and grep-attest every cited `file:line` vs the v50.0-closure HEAD before any patch.
- [ ] **BATCH-02**: The ONE batched USER-APPROVED `contracts/*.sol` diff — new `DegenerusGameBingoModule.sol` + storage mappings + `DegenerusGame.claimBingo` entrypoint delegatecall + interface + `StakedDegenerusStonk` constructor rebalance + `JackpotModule` final-day deletion — is applied in producer-before-consumer order; HARD STOP at the commit boundary (locally compiled/tested, never committed without explicit user hand-review of the diff).
- [ ] **BATCH-03**: TERMINAL minimal close — re-attest all v51.0 requirements at closure and apply the atomic 5-doc closure flip (`MILESTONE_V51_AT_HEAD_<sha>` + ROADMAP / STATE / MILESTONES / PROJECT / REQUIREMENTS). The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are DEFERRED → the v52 consolidated audit, and the v51 surface is recorded in the v52 audit-debt charge.

---

## Out of Scope (v51.0)

- **The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md`** — DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface). USER decision 2026-05-28 at milestone start.
- **Bingo progress view helper** — "which (level, symbol) first-prizes are still up for grabs?" / "what bingos are still claimable for me on level L?" — frontend read-only, deferred follow-up.
- **Cross-level / multi-level bingo prizes** — explicit non-goal.
- **2nd/3rd-place ladders within a tier** — user picked binary (first vs not) within each tier.
- **Commit-reveal anti-MEV** — user picked the public-mempool race (MEV dismissed: the race window is the per-VRF trait-resolution batch, not per-block).
- **`Pool.Reward` refill automation** — not in scope; the pool drains toward zero by design (`transferBetweenPools` exists but is not auto-invoked).
- **Any contract surface beyond the three coupled items** (BINGO / REBAL / JACK).
- **Q3 (Dice) special-case naming** — the symbol byte still has 8 values; validation is identical, only a UI string differs.

---

## Future Requirements (deferred, not this milestone)

- The v52 consolidated audit: 3-skill genuine-PARALLEL adversarial sweep + delta-audit over the cumulative v50 + v51 contract surface + `audit/FINDINGS-v50.0.md` + `audit/FINDINGS-v51.0.md`.
- Bingo progress view helper / read-only frontend support module.
- Any claimBingo / Pool.Reward follow-ups surfaced by the deferred v52 sweep.

---

## Traceability

**18/18 v51.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.** Phases continue from 338 → 339..342 (SPEC → IMPL → TST → TERMINAL). Statuses flip to Complete as phases close; all 18 re-attested at the Phase 342 TERMINAL minimal close (BATCH-03).

| Requirement | Phase | Status |
|-------------|-------|--------|
| BINGO-01 | Phase 340 (IMPL) | Pending |
| BINGO-02 | Phase 340 (IMPL) | Pending |
| BINGO-03 | Phase 340 (IMPL) | Pending |
| BINGO-04 | Phase 340 (IMPL) | Pending |
| BINGO-05 | Phase 340 (IMPL) | Pending |
| BINGO-06 | Phase 339 (SPEC) | Complete |
| REBAL-01 | Phase 340 (IMPL) | Pending |
| JACK-01 | Phase 340 (IMPL) | Pending |
| JACK-02 | Phase 340 (IMPL) | Pending |
| TST-01 | Phase 341 (TST) | Pending |
| TST-02 | Phase 341 (TST) | Pending |
| TST-03 | Phase 341 (TST) | Pending |
| TST-04 | Phase 341 (TST) | Pending |
| TST-05 | Phase 341 (TST) | Pending |
| TST-06 | Phase 341 (TST) | Pending |
| BATCH-01 | Phase 339 (SPEC) | Pending |
| BATCH-02 | Phase 340 (IMPL) | Pending |
| BATCH-03 | Phase 342 (TERMINAL) | Pending |

**Per-phase count (verification):**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 339 SPEC | BATCH-01, BINGO-06 | 2 |
| 340 IMPL | BINGO-01, BINGO-02, BINGO-03, BINGO-04, BINGO-05, REBAL-01, JACK-01, JACK-02, BATCH-02 | 9 |
| 341 TST | TST-01, TST-02, TST-03, TST-04, TST-05, TST-06 | 6 |
| 342 TERMINAL | BATCH-03 | 1 |
| **Total** | | **18** |

> **Center-of-gravity notes:** BINGO-06 (the RNG-freeze-safety PROOF) centers at SPEC (339) because it is a design-gating attestation that confirms `claimBingo`'s read-only-of-post-resolution-`traitBurnTicket` shape is freeze-safe before the entrypoint is authored — its empirical coverage is folded into the TST happy-path/regression suite (341). The build of BINGO-01..05 + REBAL-01 + JACK-01/02 lands at IMPL (340) as the single batched diff. The REBAL BPS-sum attestation and the JACK final-day deletion side-effect attestation are SPEC concerns folded into BATCH-01.

> **Note on §13e-style "uncovered" warnings:** as in the v44–v50 milestones, milestone-wide "uncovered" warnings are EXPECTED false alarms — each phase owns only its slice; the TERMINAL minimal close (Phase 342: BATCH-03) re-attests the full 18-requirement set. The TST / TERMINAL phases do not "uncover" the IMPL reqs — they re-prove and re-attest them.

> **Note on the deferred sweep:** v51 plans NO SWEEP category. The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` are out of v51 scope by USER decision (minimal close) and are the v52 consolidated audit's charge over the cumulative v50 + v51 surface. v51's own regression bar is TST-06 (NON-WIDENING vs the v50.0 baseline); its security proof is BINGO-06 (freeze) + TST-01..05 (per-tier / precedence / dedup / empty-pool / jackpot-regression).

*Last updated: 2026-05-28 — v51.0 requirements defined at milestone init. 18 reqs / 5 categories (BINGO 6 · REBAL 1 · JACK 2 · TST 6 · BATCH 3); phases 339-342 (SPEC → IMPL → TST → TERMINAL minimal close). Baseline = v50.0 closure HEAD `812abeee`. Audit posture = minimal close; internal sweep + FINDINGS DEFERRED → v52. Traceability/roadmap mapping finalized by the roadmapper.*
