# Roadmap: v47.0 — Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle

**Milestone:** v47.0
**Defined:** 2026-05-24
**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Audit baseline → subject:** v46.0 closure HEAD `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687` → v47.0 closure HEAD. Subject = the single batched USER-APPROVED contract diff reconciling the seven work items (manifest `.planning/PLAN-V47-MILESTONE-SCOPE.md`).
**Scope source:** `.planning/REQUIREMENTS.md` (45 v47.0 REQ-IDs across 8 categories) + the 7 plan docs. All economic numbers + design decisions (D1–D5, manifest §4) LOCKED; **no research, no open decisions.**

> **Posture:** pre-launch redeploy-fresh (storage-layout breaks fine, no migration); security floor over gas. **ONE batched USER-APPROVED `contracts/*.sol` diff** for the whole milestone — plans 1–6 overlap heavily on shared files (manifest §2) and item 7 (`AfKing.sol`) is isolated but joins the same diff, so the milestone has a single contract IMPL phase with a HARD STOP at the contract-commit boundary (the diff is applied + tested but never committed without explicit user hand-review). Tests + planning AGENT-committable. `ContractAddresses.sol` freely modifiable.

> **Phase numbering** continues from the previous milestone — v46.0 ended at Phase 320, so **v47.0 starts at Phase 321.** Not reset to 1.

> **Milestone shape** matches the established v44/v45/v46 audit-milestone pattern: **SPEC design-lock → single batched IMPL contract diff → TST proof → TERMINAL delta-audit + closure flip.**

---

## Phases

- [x] **Phase 321: SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation** - Settle every shared-surface signature (final `resolveRedemptionLootbox` form), grep-attest every cited file:line vs HEAD, and lock the claimable-invariant joint-check + presale-box RNG freeze re-verification before any patch.
- [x] **Phase 322: IMPL — The ONE Batched Contract Diff (all 7 items)** - Apply all seven work items' contract edits as a single reconciled diff per manifest §2; HARD STOP at the contract-commit boundary (applied + tested, never committed without explicit user hand-review).
- [ ] **Phase 323: TST — Repro-First + Same-Results Gas + Behavior/EV + Cancel-Tombstone Proofs** - Prove the redemption fix (REDEEM-08 repro must fail pre-fix), the same-results gas + worst-case absorption (DGAS-05 / DSPIN-02), and the AfKing cancel-tombstone correctness (TOMB-04) + the stale-test baseline repair (TOMB-05).
- [ ] **Phase 324: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure** - Delta-audit vs the v46.0 baseline, run the 3-skill adversarial sweep, author the findings deliverable, and flip the `MILESTONE_V47_AT_HEAD_<sha>` closure signal.

---

## Phase Details

### Phase 321: SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation
**Goal**: Every shared contract surface has a single settled signature, every cited `file:line` is grep-verified against the v47.0 plan-time HEAD, and the cross-plan invariants (claimable balance, presale-box RNG freeze) are re-proven on paper — so the IMPL phase applies a fully reconciled diff with zero "by construction" assumptions.
**Depends on**: Nothing (first v47.0 phase; consumes the v46.0 closure HEAD as the frozen audit baseline)
**Requirements**: BATCH-01, BATCH-02
**Success Criteria** (what must be TRUE):
  1. The FINAL `resolveRedemptionLootbox` signature is settled in writing — it carries BOTH the LOOT-03 boon-flag flip (`allowBoons` false→true) AND the REDEEM-03 changes (`payable` + the unchecked `claimableWinnings[SDGNRS] -= amount` debit removed + `futurePrizePool` credited from the arriving `msg.value`) on one signature, with the apply-order (payable/debit-removal first, then boon-flag) recorded.
  2. The `claimablePool == Σ claimableWinnings` invariant has a documented joint-check spanning PRESALE-06 (80/20 box-ETH ledger move), CPAY-01/02/03 (msg.value+shortfall debits across the whale-module purchases + presale box + the full `external payable` entry sweep), and REDEEM-01/03 (the new `SDGNRS`-gated checked `pullRedemptionReserve` + removal of the unchecked debit) — proving the three plans keep it balanced together.
  3. Every cited `file:line` across all 7 plans is grep-verified against the current `contracts/` HEAD and any drift is corrected in the SPEC (no "by construction" / "single fn reaches all paths" claims survive un-checked; inline-duplicated logic in `DegenerusGame` jackpot/mint paths re-checked per the Phase 294 precedent).
  4. The presale-box RNG model is re-verified freeze-safe — the box payout reuses the committed index/day RNG word with a domain-separated salt (`keccak256(rngWord,"PRESALE_BOX")`), the entropy is unknown at buy-commit and frozen across the request→unlock window, and the combined lootbox+box share-one-index / two-domain-separated-draws design introduces no new manipulation vector.
  5. The earlybird-subsystem removal scope (the `_awardEarlybirdDgnrs` + 4 sites, `_finalizeEarlybird` + `EARLYBIRD_*` triggers/state, and the candidate dead `presaleStatePacked` / level-3 clear / 200-ETH auto-end) is grep-confirmed to have no surviving consumer before deletion, and the `Pool.Earlybird` → `Pool.PresaleBox` enum-slot rename targets are pinned.
**Plans**: TBD

### Phase 322: IMPL — The ONE Batched Contract Diff (all 7 items)
**Goal**: All seven work items land as a single reconciled `contracts/*.sol` diff — the game is truly rake-free (no presale skim, no BURNIE bonus), BURNIE lootboxes are gone, the 3 ETH lootbox callers are unified, Degenerette resolution is write-batched at the new per-currency spin caps, every ETH-in path accepts claimable-pay, the sDGNRS redemption ETH is hard-segregated + BURNIE settled at submit, and the AfKing cancel-tombstone is restored — applied + locally tested, then HELD at the contract-commit boundary for explicit user hand-review.
**Depends on**: Phase 321 (the SPEC must settle the shared-surface signatures first)
**Requirements**: PRESALE-01, PRESALE-02, PRESALE-03, PRESALE-04, PRESALE-05, PRESALE-06, PRESALE-07, PRESALE-08, PRESALE-09, PRESALE-10, PRESALE-11, PRESALE-12, PRESALE-13, LOOT-01, LOOT-02, LOOT-03, LOOT-04, LOOT-05, LOOT-06, DGAS-01, DGAS-02, DGAS-03, DGAS-04, CPAY-01, CPAY-02, CPAY-03, REDEEM-01, REDEEM-02, REDEEM-03, REDEEM-04, REDEEM-05, REDEEM-06, REDEEM-07, DSPIN-01, TOMB-01, TOMB-02, TOMB-03
**Success Criteria** (what must be TRUE):
  1. The game is rake-free — the 20% presale vault skim is gone (presale lootbox ETH routes 100% to prize pools, split collapsed to normal 90/10) and the +62% presale BURNIE bonus block is removed; presale boxes REPLACE the earlybird subsystem (`Pool.Earlybird`→`Pool.PresaleBox` rename, `_awardEarlybirdDgnrs` + `_finalizeEarlybird` + `EARLYBIRD_*` removed) with credit-gated boon-less boxes (25% credit accrual on non-Degenerette ETH buys, 50/40/10 BURNIE/DGNRS/WWXRP roll, 80/20 ETH routing, 50-ETH clamp-close + last-buyer DGNRS sweep + `presaleOver` slot-0 latch).
  2. The BURNIE lootbox surface is removed entirely (`openBurnieLootBox` / `purchaseBurnieLootbox` / `_purchaseBurnieLootboxFor` / the `purchaseCoin` lootbox branch / `BurnieLootOpen` / the vault wrapper) closing the terminal-paradox hole, while BURNIE→tickets is KEPT; the 3 remaining ETH lootbox callers (`openLootBox` / `resolveLootboxDirect` / `resolveRedemptionLootbox`) all roll full boons+passes with the 10% haircut fixed and the now-dead `allowBoons` / `allowPasses` / `presale` params removed.
  3. The Degenerette resolution is write-batched same-results — ETH/BURNIE/WWXRP payouts accumulate cross-bet and flush once per currency (one `mintForGame`/`mintPrize`, one `claimableWinnings`+`claimablePool` write), the ETH cap stays per-spin against a running-pool local, lootbox-share sums PER `betId` (one box per bet, never across), DGNRS award stays per-spin, RNG seed derivation and the freeze invariant are untouched — at the new per-currency spin caps ETH 25 / BURNIE 15 / WWXRP 5.
  4. Every ETH-in path accepts `msg.value` + `claimableWinnings` shortfall — `purchaseWhaleBundle` / `purchaseLazyPass` / `purchaseDeityPass` use the established overpay-reverts / strict-1-wei-sentinel pattern, the presale box accepts claimable-pay as a pure ledger move, and all `external payable` entries in `DegenerusGame.sol` are swept for uniform application with `claimablePool == Σ claimableWinnings` staying balanced.
  5. The sDGNRS redemption is airtight — ETH is hard-segregated (MAX 175% pulled into sDGNRS at submit via the new `SDGNRS`-gated checked `pullRedemptionReserve`, fail-closed on shortfall; resolve lowers to rolled accounting-only; claim pays ETH-first from segregated balance; `resolveRedemptionLootbox` payable with the unchecked debit removed; gameOver drops the double-counted `+ pendingRedemptionEthValue`), BURNIE is settled at submit via one atomic `redeemBurnieShare` (creditFlip offset by burn+consume, net new BURNIE = 0) with the whole BURNIE reserve apparatus deleted and `onlyFlipCreditors`/burn authority extended to SDGNRS; the AfKing `setDailyQuantity(0)` becomes a true in-place tombstone with the in-sweep tombstone-reclaim branch added (no external cancel ever relocates an entry → no mid-day miss → mint streaks not collaterally broken).
  6. The diff is reconciled per manifest §2 (the single `resolveRedemptionLootbox` signature, the `DegeneretteModule` DGAS+DSPIN single edit, the `presale`-param removal landing with the presale-bonus removal) and is HELD at the contract-commit boundary — applied to `contracts/` and locally compiling/tested, but NOT committed without explicit user hand-review of the batched diff.
**Plans**: 8 plans (waves 1-8, all serialized — plans 1-6 overlap heavily on shared `.sol` files so no parallel writers; item 7 isolated; final wave is the single autonomous:false USER-APPROVAL gate for the ONE batched diff)
- [ ] 322-01-PLAN.md — PRESALE foundation: Pool.Earlybird→PresaleBox rename (concrete+iface), delete earlybird subsystem, new presale storage (presaleOver/box counters/credit/queue mirrors) + `_creditBoxProceeds` 80/20 helper [wave 1]
- [ ] 322-02-PLAN.md — PRESALE rake removal (20% skim→90/10 + 62% BURNIE bonus gone) + credit accrual + credit-gated boon-less box (50/40/10 roll, 80/20 routing, 50-ETH clamp-close+sweep+presaleOver latch, salted-RNG) + entrypoints [wave 2]
- [ ] 322-03-PLAN.md — LOOT: remove the BURNIE lootbox surface (terminal-paradox closed) + `_resolveLootboxCommon` 5→2 bools + 3-caller unification (full boons+passes, 10% haircut fixed) [wave 3]
- [ ] 322-04-PLAN.md — REDEEM: sDGNRS ETH hard-segregation (`pullRedemptionReserve`, fail-closed) + `resolveRedemptionLootbox` payable/debit-removed + gameOver double-count drop + BURNIE flip-credit-at-submit (`redeemBurnieShare`) + SDGNRS authority [wave 4]
- [ ] 322-05-PLAN.md — DGAS+DSPIN (single DegeneretteModule edit, R5): cross-bet write-batching same-results + per-currency spin caps (ETH 25 / BURNIE 15 / WWXRP 5) [wave 5]
- [ ] 322-06-PLAN.md — CPAY: claimable-pay on the 3 whale purchases + the external-payable entry sweep + the 3 WhaleModule credit-accrual sites + final `_awardEarlybirdDgnrs` body deletion [wave 6]
- [ ] 322-07-PLAN.md — TOMB (isolated): AfKing in-place cancel-tombstone + in-sweep reclaim (no-++cursor) — fixes H-CANCEL-SWAP-MISS / restores SUB-07 [wave 7]
- [ ] 322-08-PLAN.md — Verify the full batched diff (forge build + BATCH-01 joint-checks + no-NEW-test-breakage) + the single autonomous:false USER hand-review gate (HELD at the contract-commit boundary) [wave 8]
**UI hint**: no

### Phase 323: TST — Repro-First + Same-Results Gas + Behavior/EV + Cancel-Tombstone Proofs
**Goal**: The IMPL diff is proven correct empirically — the redemption-accounting defects are reproduced (fail pre-fix, pass post-fix), the gas refactor is shown byte-identical and the raised spin caps' worst case is shown absorbed, and the AfKing cancel-tombstone correctness + the stale-test baseline repair restore a clean v47.0 regression baseline.
**Depends on**: Phase 322 (tests run against the applied contract diff)
**Requirements**: DGAS-05, DSPIN-02, REDEEM-08, TOMB-04, TOMB-05
**Success Criteria** (what must be TRUE):
  1. The REDEEM-08 repro tests are written FIRST and fail against the pre-fix contract, then pass post-fix — two-claimant same-day ETH underflow (`claimableWinnings[SDGNRS]` not wrapped near 2²⁵⁶), BURNIE-can't-block-ETH (the ETH leg still pays when the BURNIE payout exceeds held+stake), and conservation across submit/resolve/claim/gameOver (BURNIE net mint == 0; `address(this).balance ≥ pendingRedemptionEthValue` at all times; no `unchecked` claimable subtraction in the redemption path).
  2. The DGAS-05 same-results gas proof shows the Degenerette write-batching is payout-identical (Tier-1 additive equivalence proven; Tier-2 per-spin cap against the running-pool local proven byte-identical), and the worst case (one bet all-spins-paying per currency + mixed-currency multi-bet up to the 25-spin ETH cap) is derived-then-measured with the measured gas delta reported.
  3. The DSPIN-02 worst-case `resolveBets` (max 25-spin ETH bets in one call, 2.5× the old per-bet roll work) gas regression is derived-then-measured and shown absorbed by the DGAS write-batching.
  4. The TOMB-04 cancel-tombstone tests pass — `testCancelBehindCursorDoesNotStrandPendingTail`, `testCancelTombstoneReclaimedByNextSweep`, `testCancelPreservesPaidWindowThroughDeferredReclaim`, `testReactivateTombstonedSubNoDoubleAdd` — and the existing 318-04 guarantees (exactly-once same-block, `lastSweptDay` backstop, no double-buy, no dead-slot buildup, two-tier skip-kill identity) are re-confirmed.
  5. The TOMB-05 stale gas-test repair lands — `testGas04PackingAndNoNewHotPathStorageSourcePresence` is updated to the post-OPENE-01 `Sub` shape (drop the two standalone-bool checks, add `address fundingSource`, fix the byte-sum 13→31 + field list) — restoring a clean 44-fail v47.0 regression baseline (clearing the 45th stale failure).
**Plans**: 5 plans (2 waves — Wave 1 repair runs both frameworks in parallel; Wave 2 proofs run after the suite compiles)
- [x] 323-01-PLAN.md — FOUNDRY repair: iterate `forge build`→fix→build until exit 0 (REDEEM struct/event arity, removed-identifier cleanup, stale BURNIE-lootbox negative-auth probes) + TOMB-05 `testGas04` repair to the post-OPENE-01 `Sub` shape (byte-sum 13→31, fundingSource) + the v47 foundry regression baseline [wave 1] ✅ 559/51/16, TOMB-05 landed, 12 new-vs-v46 owned by Wave-2
- [x] 323-02-PLAN.md — HARDHAT repair: retarget the removed BURNIE-lootbox surface + `Pool.Earlybird`→`PresaleBox` + per-currency spin-cap literals across the 10 `*.test.js` files + the v47 hardhat regression baseline [wave 1] ✅ 199/3/5 in-scope (+ DegenerettePerNEv 9/0/5); 3 residual fails ALL pre-existing-v46; 0 defects; test-only, zero contracts/ edits
- [x] 323-03-PLAN.md — REDEEM-08 (repro-first): two-claimant same-day ETH underflow (fail pre-fix, pass post-fix) + BURNIE-can't-block-ETH + conservation invariants + the R1/R3/R4 refinement coverage (`burnForCoinflip` net-0 / `_settleClaimableShortfall` / 2-arg `resolveRedemptionPeriod`) [wave 2] ✅ repro FAILS pre-fix (wrap = 2^256−3eth) + PASSES post-fix; StakedStonkRedemption 15/15 + RedemptionAccounting 16/16; contracts frozen at `fb29ed51` (blob 54af4272); commits `5467de69`/`269ce788`/`60254bab`
- [x] 323-04-PLAN.md — DGAS-05 + DSPIN-02: same-results equivalence (Tier-1 additive + Tier-2 running-pool-local cap byte-identical + per-betId lootbox + per-spin DGNRS) + the 25-spin ETH worst case derived-then-measured + absorbed under the block gas limit [wave 2]
- [ ] 323-05-PLAN.md — TOMB-04: the 4 named cancel-tombstone correctness tests + the new `didWork` revert-fix cases (reclaim/renewal-only chunk commits; spam-cancel no-strand) + the 318-04 guarantee re-confirmation [wave 2]
**UI hint**: no

### Phase 324: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure
**Goal**: The v47.0 audit subject (the single batched diff) is delta-audited against the v46.0 baseline, swept by the 3-skill adversarial pass for new findings, consolidated into the findings deliverable, and the milestone is closed with the `MILESTONE_V47_AT_HEAD_<sha>` signal and the atomic ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flip.
**Depends on**: Phase 323 (the audit subject must be implemented + test-proven before the terminal delta-audit + sweep)
**Requirements**: BATCH-03
**Success Criteria** (what must be TRUE):
  1. The delta audit covers every contract surface changed vs the v46.0 baseline — rake-removal + presale-box (credit accounting, RNG freeze, close-liveness), lootbox-boon unification (terminal-paradox closure, no BURNIE-funded passes), Degenerette gas (same-results) + per-currency caps, universal claimable-pay (`claimablePool == Σ claimableWinnings` balanced), sDGNRS redemption (two-claimant + BURNIE-can't-block-ETH + conservation), and the AfKing cancel-tombstone (no relocation, no miss) — with each surface attested NON-WIDENING relative to the baseline.
  2. The 3-skill adversarial sweep runs (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per the carried decision) charged with presale snipe / credit double-spend / box-RNG freeze / close-liveness, claimable-invariant breakage, lootbox terminal-paradox closure, redemption two-claimant + BURNIE-blocks-ETH + conservation, and tombstone griefing — with every elevation passed through the skeptic filter (structural-protection + 3-condition EV lens) before being recorded.
  3. The findings deliverable is authored at the v47.0 closure HEAD (mirrors the v44/v46 9-section pattern, chmod 444) with the H-CANCEL-SWAP-MISS finding (deferred from v46.0) recorded as RESOLVED-AT-V47.
  4. The `MILESTONE_V47_AT_HEAD_<sha>` closure signal is emitted and propagated verbatim, and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) is applied with all 45 requirements re-attested at closure.
**Plans**: TBD

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 321. SPEC — Design-Lock + Call-Graph Attestation + Reconciliation | 1/1 | ✅ Complete | 2026-05-25 (`779eacc3`) |
| 322. IMPL — The ONE Batched Contract Diff (all 7 items) | 8/8 | ✅ Complete | 2026-05-25 (`fb29ed51`) |
| 323. TST — Repro + Same-Results Gas + Cancel-Tombstone Proofs | 4/5 | In progress (Wave 1 repair done; 323-03 REDEEM-08 ✅; 323-04 DGAS-05/DSPIN-02 ✅; TOMB-05 ✅; 323-05 TOMB-04 next) | - |
| 324. TERMINAL — Delta Audit + Adversarial Sweep + Closure | 0/TBD | Not started | - |

---

## Coverage

**45/45 v47.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 321 SPEC | BATCH-01, BATCH-02 | 2 |
| 322 IMPL | PRESALE-01..13, LOOT-01..06, DGAS-01..04, CPAY-01..03, REDEEM-01..07, DSPIN-01, TOMB-01..03 | 37 |
| 323 TST | DGAS-05, DSPIN-02, REDEEM-08, TOMB-04, TOMB-05 | 5 |
| 324 TERMINAL | BATCH-03 | 1 |
| **Total** | | **45** |

**Per-category split (verification):**

| Category | Total | SPEC | IMPL | TST | TERMINAL |
|----------|-------|------|------|-----|----------|
| PRESALE | 13 | — | 13 (01–13) | — | — |
| LOOT | 6 | — | 6 (01–06) | — | — |
| DGAS | 5 | — | 4 (01–04) | 1 (05) | — |
| CPAY | 3 | — | 3 (01–03) | — | — |
| REDEEM | 8 | — | 7 (01–07) | 1 (08) | — |
| DSPIN | 2 | — | 1 (01) | 1 (02) | — |
| TOMB | 5 | — | 3 (01–03) | 2 (04–05) | — |
| BATCH | 3 | 2 (01–02) | — | — | 1 (03) |
| **Total** | **45** | **2** | **37** | **5** | **1** |

✓ All 45 v47.0 requirements mapped
✓ No orphaned requirements
✓ No duplicated requirements

---
*Roadmap created: 2026-05-24*
