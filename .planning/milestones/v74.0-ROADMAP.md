# Roadmap — Milestone v74.0 — As-Built Milestone Audit + C4A Package (supersedes the v74 "C4A Readiness" plan)

> **Subject (BYTE-FROZEN at HEAD):** the `v73.0 → HEAD` diff — `3986926c` ("sDGNRS level lootbox + pre-deploy hardening batch"), **29 contract files, +1861/−1030**, never milestone-audited. Frozen baseline = local HEAD `3986926c` (on `main`, not pushed). Resets off v73.0 closure `MILESTONE_V73_AT_HEAD_15650b6a…` (`contracts/` tree `d6615306` @ `64ec993e`).
> **Supersedes:** the prior "v74.0 — C4A Readiness" plan (457–465, never tagged) whose no-contract-change premise was overtaken by this batch. Old plan archived → `milestones/v74.0-superseded-plan-{ROADMAP,REQUIREMENTS}.md`. The already-built live agent + 24/7 soak + partial package carry forward in place. **Numbering continues 465 → 466.**
> **Posture:** the subject is already committed; the milestone *verifies* it. The **SOLE possible contract-commit gate** is the conditional squash at 475/478 — fires only if the re-audit surfaces a real defect. Verify/harness/audit/manifest/agent/package/findings work commits autonomously.
> **Method:** verify → freeze-confirm → harness-green → 6-cluster code audit → manifest re-point → cross-model re-audit → live agent/soak re-attest → C4A package → terminal. Cross-model finder = **Codex** (primary); the Gemini CLI is currently unavailable — re-check before leaning on a council.
> **Threat weighting (locked):** DOMINANT RNG/freeze · HIGH gas-DoS in advanceGame (>16.7M = game-over) · SPINE solvency/backing · LOWER access/reentrancy/MEV.
> **Grounding:** `.planning/v74-grounding/v74.0-asbuilt-audit-map.md` (8-cluster change-map + 8 ranked attack surfaces) + `v74.0-asbuilt-map-RAW.json`.

---

## Phase 466 — SUBJECT-FREEZE-CONFIRM

**Goal:** Byte-freeze the audit subject at HEAD `3986926c`, resolve the 2 dirty test files, and capture the storage-layout golden so the whole milestone pins to one immutable tree.

**Requirements:** SUBJ-01, SUBJ-02, SUBJ-03, SUBJ-04

**Success criteria:**
1. `git diff HEAD -- contracts/` is empty; the frozen `contracts/` tree hash + impl commit `3986926c` are recorded as the subject.
2. The 2 dirty liveness `.test.js` files are committed or explicitly quarantined out of the frozen subject.
3. A by-name `forge inspect storageLayout` golden exists and shows no top-level slot move vs v73 — only the within-slot `Sub` repack + the additive `_sdgnrsBonusLevel` (slot 58 offset 25; `boxPlayers` slot 59 unchanged; `WHALE_PASS_TYPE_SHIFT` bit 152).
4. A closure baseline `MILESTONE_V74_AT_HEAD_<sha>` is defined distinct from the stale v73 `d6615306` pin; push posture recorded (local HEAD = subject; push not required).

## Phase 467 — HARNESS-GREEN-GATE (test-only)

**Goal:** Bring the full forge + Hardhat suite to green at frozen HEAD, re-deriving every slot-hardcoded harness broken by the `Sub` repack and de-flaking the deferred liveness tests.

**Requirements:** HARN-01, HARN-02, HARN-03

**Success criteria:**
1. No slot-hardcoded `vm.store`/`vm.load` harness reads a stale `Sub` offset (all re-derived from the 466 golden).
2. Every ABI-breaking selector/signature change is reflected in all JS + Foundry callers/tests; build green.
3. Full `forge` suite green at HEAD (target ≥893/0); Hardhat green incl VRFGovernance 42/42 and the new `DegenerusGasFaucet`/`DegenerusQuests` suites; the 2 deferred liveness edge tests fold back to green.

## Phase 468 — AUDIT-SOLV-FOLD (SPINE)

**Goal:** Prove backing/solvency conservation across the deferred/folded purchase-path writes, the combined affiliate credit return, the partial claim, and the new sDGNRS claimable→prize-pool routing.

**Requirements:** SOLV-01, SOLV-02, SOLV-03, SOLV-04, SOLV-05, SOLV-06, SOLV-07, SOLV-08

**Success criteria:**
1. A written conservation proof (or invariant test) that the aggregate `claimablePool` and prize-pool folds equal the prior per-tier sums on all `payKind` branches (±lootbox), and no caller skips the pool decrement; the boon-consume reentrancy window exposes no inconsistent pool.
2. `payAffiliateCombined` `winnerCredit` + buyer credit are fully accounted at the MintModule call site for referrer and noReferrer paths with `winner!=buyer` collision-safety; no unbacked credit minted.
3. The sDGNRS-box backing path is shown solvency-safe (`claimablePool >= Σ claimable`, 1-wei sentinel preserved); partial `claimWinnings` caps exactly and leaves the sentinel pre-gameOver; the GameOver freeze-clear runs before any post-gameOver resolution / `_unfreezePool` on every path.

## Phase 469 — AUDIT-RNG-LIVENESS (DOMINANT + HIGH)

**Goal:** Re-audit the dominant RNG-freeze and high gas-liveness surfaces: VRF-death deadman, mid-day RNG recovery fold, queue-gate removal, fail-open swap, advance same-tx-composition guards, and the foil/mid-day timeout liveness.

**Requirements:** RNG-01, RNG-02, RNG-03, RNG-04, RNG-05, LIVE-01, LIVE-02, LIVE-03, LIVE-04

**Success criteria:**
1. The deadman is shown non-premature, latched, gas-bounded, and driven by a non-steerable historical fallback word; its game-over drain stays under the per-tx ceiling in a worst-case test.
2. Mid-day abandon-and-promote is shown single-resolution with the reserved bucket preserved and the stale `requestId` permanently unmatchable (no entropy-reroll); queue-window tickets are shown never to feed a terminal jackpot; the fail-open swap deferred branch is shown unreachable.
3. The sDGNRS-box pre-RNG live-claimable sizing is shown non-steerable and the once-per-level latch non-re-firing; `didWork`/`drained` never falsely false on a finishing batch; the advance heartbeat cannot be bricked by the decode guards.

## Phase 470 — AUDIT-ACCESS-PERMISSIONLESS

**Goal:** Confirm every newly-permissionless / relaxed-stub / caller-funded-gift path settles value only to the owner and sources spend only from a consenting party, per the locked permissionless-settlement ruling, and that the admin governance timing is safe.

**Requirements:** ACCESS-01, ACCESS-02, ACCESS-03, ACCESS-04, ACCESS-05, ACCESS-06, ACCESS-07

**Success criteria:**
1. An access-control matrix maps each relaxed/permissionless entrypoint to its resolution point and proves value settles only to the owner; no caller acts for an unconsenting player on a spend/gift path.
2. Every gift path sources spend from `msg.sender` (or an approved operator's own player), never a non-consenting party; WWXRP gift-excluded; `claimBingo` operator-approval is non-bypassable and dedup player-keyed; `claimAffiliateDgnrs` moves no value from a non-consenting party.
3. The 44h gate is shown sawtooth-safe; `vote()` kill-on-recovery terminal with no recovered-state vote window; `receive()` unable to revert/strand value; no live selector routes to the removed `GAME_ENDGAME_MODULE`.

## Phase 471 — AUDIT-EV-RTP

**Goal:** Re-verify the economy — foil and Degenerette payouts remain byte-equivalent at frozen-at-buy basis, the affiliate winner-distribution + quests streak changes are intended, and the activity-score skip and reinvest removal are behaviour-preserving.

**Requirements:** EV-01, EV-02, EV-03, EV-04, EV-05, EV-06, EV-07

**Success criteria:**
1. A numeric proof that the foil score basis and the Degenerette `ResolveAcc` fold are byte-equivalent to v73 (EV / RTP / P(match-tier) pins held).
2. The affiliate combined path is shown rounding/leaderboard/score-freeze equivalent to four calls; the single `handleAffiliate` hop confirmed reward-linear (or the divergence documented).
3. The activity-score skip is shown behaviour-preserving (no consumer depends on a real score in the skipped case); `reinvestPct` shown fully removed; the century shield granted exactly once per threshold under the 1→5 jump and the afking-routed path.

## Phase 472 — AUDIT-RENAME-WIRING-STORAGE

**Goal:** Confirm the mechanical surface is truly inert — the named-error migration preserves every revert condition, the whaleBundle/WWXRP renames are value- and layout-neutral, the new events are observability-only, and interface↔module wiring is in lockstep.

**Requirements:** WIRE-01, WIRE-02, WIRE-03, WIRE-04

**Success criteria:**
1. A per-swap table shows each named error replaces an identical condition; all stale-natspec mismatches are catalogued for correction.
2. `grep` confirms 0 stale `WHALE_BUNDLE_TYPE_SHIFT` / `WrappedWrappedXRP` / `purchaseWhaleBundle` / `resolveBets(` / `retryLootboxRng` / `handleFoilPack` / `foilStreakBoost` references in `contracts/`.
3. The `Sub` repack + `_sdgnrsBonusLevel` layout safety is re-confirmed against the 466 golden; every renamed selector + new return tuple is matched to its implementation and all callers/tests; the new events are confirmed value-flow-neutral with the affiliate single-emit indexer-parity documented.

## Phase 473 — AUDIT-GAS-FAUCET (newly in-scope, dormant)

**Goal:** Re-attest the standalone `DegenerusGasFaucet` as structurally clean — it custodies only donated ETH, reads protocol state view-only, and its value-movement + access surfaces are bounded.

**Requirements:** GAS-01, GAS-02, GAS-03, GAS-04

**Success criteria:**
1. The faucet is confirmed unwired/dormant in both deploy scripts; its dormant-in-scope posture is recorded.
2. `distribute()`/`withdraw()` are shown CEI-safe, gating-correct, and bounded to donated funds only.
3. The 26/26-era unit suite is green; structural confirmation it has no mint/burn/ledger path and cannot move protocol value.

## Phase 474 — MANIFEST-REPOINT

**Goal:** Re-point the single machine-readable invariant manifest (MAN-01) from the stale v73 tree to frozen HEAD and add invariants covering the batch's new conservation/freeze surfaces.

**Requirements:** MAN-01, MAN-02, MAN-03

**Success criteria:**
1. `invariants.json` subject is re-pinned to HEAD `3986926c` with all 28 existing entries re-validated against the frozen getters/slots.
2. New invariant entries are added for the SOLV-fold, sDGNRS-box, affiliate-credit, deadman, gift-sourcing, and queue-window surfaces — each on-chain or statistically evaluable.
3. `MAIN-INVARIANTS.md` is regenerated from `invariants.json` and byte-matches the oracle's asserted set (the single MAN-01 source shared by `agent/src/oracle.js` and the README).

## Phase 475 — CROSS-MODEL-REAUDIT (conditional contract gate)

> **The SOLE possible contract-commit gate.** Fires only if a real defect surfaces. An all-refuted result ships gate-free.

**Goal:** Run the established cross-model adversarial re-audit (Codex primary; Gemini if its CLI revives) over the ranked top attack surfaces in isolated neutral-prompt subagents, and adjudicate every candidate.

**Requirements:** CMRA-01, CMRA-02

**Success criteria:**
1. Codex (and Gemini if alive) ran a documented adversarial pass over each ranked surface with neutral prompts in isolated subagents; contracts are git-verified unmodified after each Write-capable subagent.
2. Every raised candidate has a written disposition (fix / refute / known-issue); the skeptic filter was applied before any CATASTROPHE/HIGH label.
3. Any real defect routes to the conditional, owner-approved squash commit (`CONTRACTS_COMMIT_APPROVED=1` + hook move-aside, re-verified after); an all-refuted result records the subject byte-frozen and ships gate-free.

## Phase 476 — AGENT-SOAK-REATTEST

**Goal:** Re-point the already-built live adversarial agent and 24/7 testnet soak at the frozen-HEAD subject and re-attest 0 invariant violations and 0 profit-vs-EV alarms.

**Requirements:** SOAK-01, SOAK-02, SOAK-03

**Success criteria:**
1. The agent + soak are re-pointed at an independently-run testnet of the HEAD subject with the 474-re-pinned MAN-01 manifest (the agent never deploys/forks).
2. A documented campaign + soak run with 0 final on-chain MAN-01 violations and 0 per-actor profit-vs-EV alarms (window-transients explained).
3. Any violation is reproducible from logged state; the attestation cites the soak ledger.

## Phase 477 — C4A-PACKAGE

**Goal:** Assemble the full Code4rena contest package against the as-built tree — scope/out_of_scope + nSLOC, SECURITY + trusted-roles/trust-model, a precise known-issues perimeter, and a C4-section-order contest README.

**Requirements:** PKG-01, PKG-02, PKG-03, KI-01, KI-02

**Success criteria:**
1. `scope.txt` + `out_of_scope.txt` + the in-scope nSLOC table are regenerated against and match the frozen HEAD tree (FLIP/WWXRP renames + EndgameModule removal reflected; faucet placed per its dormant-in-scope posture).
2. `SECURITY.md` + the trust-model enumerates every trusted role + the permissionless-settlement boundary; the known-issues perimeter is mechanism-+-impact specific for every by-design quirk and carried item (the mid-day `==0` guard re-checked against the as-built mid-day-recovery fold).
3. A C4-order contest README is assembled with the Main-Invariants section sharing MAN-01 verbatim; the access-control matrix + ETH-flow map cover the new permissionless/gift/sDGNRS-box/faucet surfaces.

## Phase 478 — TERMINAL

**Goal:** Produce the evidence pack and closure signal, confirming the as-built subject is clean (or all findings dispositioned) and byte-frozen at the freeze tree.

**Requirements:** TERM-01, TERM-02, TERM-03

**Success criteria:**
1. `audit/FINDINGS-v74.0.md` (chmod 444) exists with a complete disposition table across all 8 clusters + the cross-model + soak attestations and the verdict; an HTML report is generated.
2. The closure signal `MILESTONE_V74_AT_HEAD_<sha>` is emitted and the subject confirmed byte-frozen at HEAD (or the updated subject if 475 fired).
3. The package, manifest, and soak attestation all reference the same frozen subject; ROADMAP/REQUIREMENTS archived to `milestones/`; the only commit gate (a conditional contract-fix if 475 surfaced a real defect) is resolved.

---

## Coverage

| Phase | Requirements | Gate |
|-------|--------------|------|
| 466 SUBJECT-FREEZE-CONFIRM | SUBJ-01/02/03/04 | none |
| 467 HARNESS-GREEN-GATE | HARN-01/02/03 | none (test-only) |
| 468 AUDIT-SOLV-FOLD | SOLV-01..08 | none |
| 469 AUDIT-RNG-LIVENESS | RNG-01..05, LIVE-01..04 | none |
| 470 AUDIT-ACCESS-PERMISSIONLESS | ACCESS-01..07 | none |
| 471 AUDIT-EV-RTP | EV-01..07 | none |
| 472 AUDIT-RENAME-WIRING-STORAGE | WIRE-01..04 | none |
| 473 AUDIT-GAS-FAUCET | GAS-01..04 | none |
| 474 MANIFEST-REPOINT | MAN-01/02/03 | none (docs/test-config) |
| 475 CROSS-MODEL-REAUDIT | CMRA-01/02 | **sole contract gate (conditional)** |
| 476 AGENT-SOAK-REATTEST | SOAK-01/02/03 | none |
| 477 C4A-PACKAGE | PKG-01/02/03, KI-01/02 | none (docs) |
| 478 TERMINAL | TERM-01/02/03 | none (docs; conditional fix resolved) |

**62 requirements** mapped across **13 phases**; 0 unmapped ✓. The default path is gate-free; the single possible approval gate (475) is conditional on a real defect surfacing.

---
*Roadmap created: 2026-06-26 (supersedes the v74 "C4A Readiness" plan).*
*Phase numbering continues from the prior v74 allocation (457–465) → 466.*
