---
phase: 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi
plan: 04
milestone: v46.0
milestone_name: Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal
audit_baseline: 62fb514bfcc8ad042a45cef960e5ff0ff6fbb801
audit_baseline_signal: MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801
v44_baseline_signal: MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349
source_tree_frozen_ref: 30b5c89c
audit_subject_head: "16e9668a6de35cc0c809d81ce960aee137950687"
closure_signal: MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687
deliverable: audit/FINDINGS-v46.0.md
new_findings: 1
new_findings_disposition: H-CANCEL-SWAP-MISS (MEDIUM) DEFERRED→v47.0 [fix locked; SOURCE-TREE FROZEN held]
---

# v46.0 Findings — Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (Terminal; FEATURE-MILESTONE)

## 1. Audit Subject + Baseline

**Audit Baseline.** v45.0 closure HEAD `62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` (closure signal `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`, carry-forward from the v45.0 minimal-close). v44 chain reference: `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`. v46.0 closure HEAD is `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687` (resolved at Phase 320 Commit 1 per the 2-commit sequential-SHA orchestration; see §9c). SOURCE-TREE FROZEN reference for the terminal: `30b5c89c` (contracts/+test/ byte-frozen since; commits after are planning-only).

**Subject.** Every v45→v46 `contracts/` commit (`git log 62fb514b..HEAD -- contracts/`), complete and cross-checked against the STATE.md ledger:
- `df4ef365` — the batched Phase 317 ADD+REMOVE diff: do-work crank + subscription (new `AfKing.sol` keeper) + legacy AFKing/ETH-auto-rebuy removal (RM) + the JGAS jackpot two-call-split removal. The keeper-reconciliation + slot gap-closure (the "317-08 family") landed INSIDE this commit.
- `e4014f91` + `795e679d` — Phase 319 GAS reward-peg calibration + CR-01 box-peg correction (137_944→71_203 per-box marginal).
- `42140ceb` + `e1baa978` — Phase 319.1 OPEN-E shared funding source (`subscribe()` `fundingSource` param + operator-approval routing across AfKing/Vault/sDGNRS) + WR-01 indexed-event.
- `745cd63d` — the 318-01 fixture commit (AfKing deploy + AF_KING pin; test/fixture).

This is a FEATURE milestone (a brand-new in-tree keeper + a new attack surface), so it ships the full 9-section deliverable (D-04, reverting v45's minimal-close precedent), `chmod 444` at close.

---

## 2. Executive Summary

### Closure Verdict Summary

v46.0 ships the do-work crank + the AfKing auto-rebuy subscription + the OPEN-E shared funding source, removes the legacy AFKing mode + free ETH auto-rebuy + the two-call jackpot-ETH split, and keeps the BURNIE flip-autorebuy at a flat 75bps. The 3-skill adversarial sweep (Phase 320, genuine PARALLEL_SUBAGENT) + the add/remove/OPEN-E/JGAS delta-audit + the LEAN regression find the change set sound **with ONE exception**: a single Tier-1 MEDIUM finding (**H-CANCEL-SWAP-MISS**) — a SUB-07 cancel-tombstone IMPL divergence — USER-adjudicated to DEFER-to-v47.0 with the fix locked, keeping v46.0 SOURCE-TREE FROZEN.

### Verdict Math

- **Adversarial sweep:** 34 disposition rows — 29 NEGATIVE-VERIFIED + 4 SAFE_BY_DESIGN + **1 FINDING_CANDIDATE** (H-CANCEL-SWAP-MISS, MEDIUM). 0 skeptic-filter discards. Two-tier consensus: 1 Tier-1 (single skill), 0 Tier-2.
- **Delta-audit:** every surface (PROTO/CRANK/REW/SUB/RM/JGAS/OPENE) matches the 316-SPEC lock EXCEPT SUB-07 (the cancel divergence = H-CANCEL-SWAP-MISS). RM + JGAS kill sets grep-clean (ZERO).
- **Regression:** NON-WIDENING (zero v46 contract regressions); suite 565 pass / 45 fail / 16 skip — 44 byte-identical to the named v45-derived baseline + 1 stale test (testGas04, test-only).

### Severity Counts
- CATASTROPHE 0 · HIGH 0 · **MEDIUM 1** (H-CANCEL-SWAP-MISS, deferred v47.0) · LOW 0 · informational SAFE_BY_DESIGN 4.

### KI Gating Rubric Reference
KNOWN-ISSUES.md byte-unmodified vs v45 (§6). No KI promotion/demotion this milestone.

### Forward-Cite Closure Summary
Two items handed to v47.0: (1) **H-CANCEL-SWAP-MISS** fix (restore SUB-07 in-place tombstone) — `.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md`, v47 manifest item 7; (2) the **testGas04** stale-assertion update (post-OPENE-01 `Sub` shape) — bundled into the same v47 AfKing test work. Both test-and-contract changes land in the v47.0 single batched diff (v46.0 terminal is SOURCE-TREE FROZEN).

### Attestation Anchor
All `contracts/` file:line anchors herein are sourced from the Wave-1 workstream docs (320-01/02/03), each re-grep-verified against HEAD on the OPEN-E-bearing main tree (`grep -c fundingSource contracts/AfKing.sol == 21`).

---

## 3. Per-Phase Sections

- **§3a Phase 316 — SPEC (design-lock).** The locked v46.0 add+remove+JGAS+SUB-09 design (`316-SPEC.md`). The "intended" reference the delta-audit confirms the diff matches. SUB-09 permanent-deity bits ALREADY in the `DegenerusGame` ctor (`:222/:223`); SUB-07 locked "external cancel moves nothing."
- **§3b Phase 317 — IMPL (batched ADD+REMOVE).** `df4ef365` — new `AfKing.sol` keeper + crank entrypoints + RM removal + JGAS split removal + keeper/slot gap-closure.
- **§3c Phase 318 — TST.** Fixture repair (`745cd63d`, 197→532 runnable) + SAFE-01 faucet resistance + SAFE-03 sweep concurrency + 318-05 RngFreezeAndRemovalProofs (13/13) + 318-06 JackpotSingleCallCorrectness.
- **§3d Phase 319 — GAS.** `e4014f91` + `795e679d` — reward-peg calibration + the CR-01 faucet fix (per-box marginal 71_203).
- **§3e Phase 319.1 — OPEN-E IMPL.** `42140ceb` + `e1baa978` — `Sub.fundingSource` (set only via `subscribe()`), ETH `_poolOf` routing, both `burnForKeeper` sites, operator-approval-at-subscribe auth, indexed event. 13/13 VERIFICATION (OPENE-01..04). **The `Sub` repack (collapsing two bools into `flags` + adding `fundingSource`) is the source of the testGas04 staleness (§5).**
- **§3f Phase 320 — TERMINAL.** This deliverable; SOURCE-TREE FROZEN; the 3-skill sweep + delta-audit + regression + gated 2-commit closure.

### §3.A Delta-Surface Table (from 320-02-DELTA-AUDIT.md §1.A)

| Surface | Commit | Re-grepped anchors | Disposition |
| --- | --- | --- | --- |
| PROTO-01..05 | `df4ef365` | `hasAnyLazyPass` `DegenerusGame.sol:1472`; deity bits ctor `:222/:223` | NEGATIVE-VERIFIED |
| CRANK-01..04 | `df4ef365` | `AfKing.sol:569` `sweep`; `:728` funding-skip; `DegenerusGame.sol:1687-1697` keeper-gated `batchPurchase` | NEGATIVE-VERIFIED |
| REW-01..04 | `df4ef365`+`e4014f91`+`795e679d` | `AfKing.sol:801-802` single `creditFlip` bounty; box peg 71_203 (CR-01) | NEGATIVE-VERIFIED |
| SUB-01..06,08,09 | `df4ef365` | `AfKing.sol:375-382` subscribe; `:438`/`:634` burnForKeeper; `:728-729` two-tier skip-kill (un-spoofable `player`); SUB-09 `Vault:474`/`sStonk:380` | NEGATIVE-VERIFIED |
| **SUB-07** (lapsed/cancelled) | `df4ef365` | `AfKing.sol:455-468`→`:459` `_removeFromSet` swap-pop `:825-837`; NO in-sweep tombstone-reclaim branch | **DIVERGES** → H-CANCEL-SWAP-MISS (§4); DEFER-v47.0 |
| RM-01..06 | `df4ef365` | RM kill-set grep ZERO; only afKing survivor = kept `hasAnyLazyPass` | NEGATIVE-VERIFIED |
| JGAS-01/02 | `df4ef365` | JGAS kill-set grep ZERO; single-call `DegenerusGameJackpotModule.sol:286/:457`; 305 ceiling `:229` | NEGATIVE-VERIFIED |
| OPENE-01..04 | `42140ceb`+`e1baa978` | `Sub.fundingSource:85`; set-point `subscribe():426`; gate `:397-403`; default-self `:439`/`:697`; draw `:728`; event `:160` | NEGATIVE-VERIFIED (319.1 13/13) |

### §3.B Composition Attestation Matrix (from 320-02 §2)
- **ADD×REMOVE:** ETH winnings always credit to claimable (`_addClaimableEth`, `claimablePool` balanced); flip-autorebuy flat 75bps unconditional; `_hasAnyLazyPass` the only retained afKing symbol; no orphan/double-credit. NEGATIVE-VERIFIED.
- **JGAS single-call:** daily ETH jackpot ONE advanceGame stage @305 ceiling (159/95/50/1), no resume stage, nothing stranded by the dropped `resumeEthPool` carry; re-attests 318-06 conservation. NEGATIVE-VERIFIED.
- **OPEN-E default-self:** `fundingSource==0` short-circuits to self (`:439`/`:697`), same `_poolOf` slot (`:728`), per-draw gas unchanged; no cross-account spend without `isOperatorApproved` at `subscribe()` only (`:397-403`). NEGATIVE-VERIFIED.

### §3.C Requirement Re-Attestation
All 46 v46.0 requirements (PROTO 5 · CRANK 4 · REW 4 · SUB 9 · RM 6 · SAFE 4 · GAS 6 · JGAS 4 · OPENE 4) are re-attested at closure. 45 NEGATIVE-VERIFIED/Complete; **SUB-07 carries the H-CANCEL-SWAP-MISS divergence** (the cancel-tombstone IMPL diverged from the locked design — deferred to v47.0). OPENE-01..04 attest HERE (319.1 13/13 + 320-01 SWP-OPENE).

---

## 4. Adversarial-Pass Disposition (from 320-01-ADVERSARIAL-LOG.md §6/§8)

### §4.1 Outcome
3-skill genuine PARALLEL_SUBAGENT sweep (`/contract-auditor` anchor + `/zero-day-hunter` ‖ `/economic-analyst`; `/degen-skeptic` OUT). **34 disposition rows: 29 NEGATIVE-VERIFIED + 4 SAFE_BY_DESIGN + 1 FINDING_CANDIDATE.** 0 skeptic-filter self-discards; 0 orchestrator integration-time discards.

### §4.2 The FINDING_CANDIDATE — H-CANCEL-SWAP-MISS (MEDIUM)
External cancel `setDailyQuantity(0)` (`AfKing.sol:459`) calls `_removeFromSet` (swap-pop, `:825-837`) immediately, relocating an unprocessed tail subscriber behind a persisted mid-day `_sweepCursor` → that innocent sub misses one day's auto-buy → the per-consecutive-level mint streak (`DegenerusGameMintStreakUtils._mintStreakEffective`, resets on a missed level) RESETS → up to a **+50% activity-score multiplier permanently lost**. Regresses the LOCKED SUB-07 "external cancel moves nothing" (`316-SPEC.md:152`) + omits the in-sweep `dailyQuantity==0` reclaim branch. Severity revised UP from the hunter's LOW once the streak impact was understood. **Tier-1 (single skill) → USER-adjudicated DEFER-to-v47.0** (fix locked = restore the in-place tombstone + in-sweep reclaim; `.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md`). v46.0 SOURCE-TREE FROZEN held; no RE-PASS triggered.

### §4.3 SAFE_BY_DESIGN rows (informational)
- **SWP-OPENE.D-02 BURNIE-funding overload** (auditor + economist) — the operator-approval authorizes burning the source's general-wallet BURNIE + pending coinflip; consensual under the D-01 trust boundary (grantee = same person or a fixed contract; no "tricked into approving" actor). `allowBurnieFunding` DROPPED (D-02a).
- **SWP-OPENE.4 trust-the-sub temporal bound** (auditor + economist) — a later revoke does not retroactively stop an active sub; the drain is BOUNDED by sub lifetime + S-defunding + M-cancel.

### §4.4 Skeptic-Reviewer Filter Attestation
Dual-gate filter applied (per-skill self-arm + orchestrator integration-time re-application) BEFORE the Tier-1 user-pause. H-CANCEL-SWAP-MISS survived: structural-strict arm fails (reachable, even on legitimate cancels); EV-lens (a) does not hard-discard (the miss manifests without an attacker); (b)/(c) revised severity UP, not down.

---

## 5. LEAN Regression Appendix (from 320-03-REGRESSION.md)

### §5a REG-01 — NON-WIDENING
`git diff 62fb514b..HEAD -- contracts/ test/`: 14 contracts files + 36 test files, EVERY hunk attributable to a v46-scope commit. v44 sStonk-redemption core + v45 VRF-rotation logic byte-unchanged (v46 edits to those files confined to SUB-09 wiring + JGAS single-call). Zero unattributable hunks.

### §5b Suite Baseline — 565 / 45 / 16
The documented named v45-derived baseline was **44 fail** (held at 44 through Phase 319). At HEAD: **565 pass / 45 fail / 16 skip (626 total)** — suite grew 601→626 (+25 tests from 319/319.1). **44 of 45 failures are BYTE-IDENTICAL to the named 318-01 baseline** (TicketRouting/QueueDoubleBuffer/VRF-fuzz/Degenerette/solvency-invariant families). **The 45th = `CrankLeversAndPacking::testGas04PackingAndNoNewHotPathStorageSourcePresence` (panic 0x11) — a STALE v46-internal TEST**, NOT a contract regression: it asserts the pre-OPEN-E `Sub` 7-field/13-byte layout, but OPENE-01 (USER-APPROVED) collapsed the two bools into `flags` + added `address fundingSource` (HEAD `Sub` = 6 fields, `AfKing.sol:79-86`). **ZERO v46 CONTRACT regressions.** Test-only fix deferred to v47.0.

---

## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification (from 320-03 §7/§8)
- **KNOWN-ISSUES.md byte-unmodified** vs v45 (`git diff 62fb514b..HEAD -- KNOWN-ISSUES.md` empty; sha256 `75b3b4bc79a96c7e…`). No KI promotion/demotion.
- **BURNIE win/loss RNG path byte-unmodified** — `processCoinflipPayouts` (`BurnieCoinflip.sol:756`) + `bool win = (rngWord & 1) == 1;` (`:788`) byte-unchanged; the 106-line BurnieCoinflip delta is entirely the RM-scope auto-rebuy/afKing-mode removal.
- **RNG-freeze intact + obligations RETIRED** — RngNotReady guards intact (DegeneretteModule:578/:452, LootboxModule:485/:567); the ETH-auto-rebuy removal retires 1 VRF consumer + 3 player-mutable in-window inputs (318-05 SAFE-04). Crank relaxes WHO resolves, not WHEN.

---

## 7. Prior-Artifact Cross-Cites
- **v46.0 phase artifacts:** `316-SPEC.md`; Phase 317 IMPL (`df4ef365`); Phase 318 TST SUMMARYs (318-01/04/05/06); Phase 319 GAS (`e4014f91`/`795e679d`); Phase 319.1 OPEN-E (319.1-VERIFICATION 13/13, 319.1-REVIEW WR-01/WR-02); Phase 320 workstreams (320-01-ADVERSARIAL-LOG, 320-02-DELTA-AUDIT, 320-03-REGRESSION + the CHARGE + 3 per-skill MDs).
- **Prior milestone FINDINGS:** `audit/FINDINGS-v44.0.md` (9-section template); v45.0 minimal-close (disposition in `314-01-ADVERSARIAL-LOG.md`).
- **Carry-forward anchors:** v45 closure signal `MILESTONE_V45_AT_HEAD_62fb514b…`; the v44 §9d handoff register (135 anchors — maximalist catalog, NOT live vectors).

---

## 8. Forward-Cite Closure
Two v47.0 handoffs (both in the v47.0 single batched diff; v46.0 terminal is SOURCE-TREE FROZEN):
1. **H-CANCEL-SWAP-MISS** (MEDIUM) — restore the SUB-07 in-place tombstone + add the in-sweep `dailyQuantity==0` reclaim branch (`AfKing.sol`) + the cancel-behind-cursor no-miss test. `.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md` (manifest item 7).
2. **testGas04 stale assertion** — update to the post-OPENE-01 `Sub` shape (test-only). Bundled with the same v47 AfKing test work.
No intra-milestone forward-cite residual (all Wave-1 placeholders resolved into this deliverable at §3/§4/§5/§6).

---

## 9. Milestone Closure Attestation

### 9a. Closure Verdict

**Locked target (ROADMAP §Phase-320 success-criterion 4, verbatim — for the record):**
`CRANK_DO_WORK SHIPPED; AFKING_SUBSCRIPTION SHIPPED; LEGACY_AFKING_MODE + FREE_ETH_AUTOREBUY REMOVED; BURNIE_FLIP_AUTOREBUY KEPT@75BPS; FAUCET_BOUNDED; SWEEP NON-BRICK + CONCURRENT-SAFE; FUNDING_WATERFALL + TWO-TIER_SKIP-KILL CORRECT; RNG_FREEZE_INTACT (+ obligations RETIRED by removal); JACKPOT_ETH_SPLIT REMOVED (single-call fits @305-ceiling); WWXRP_ZERO_REWARD; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED`

**Amended actual verdict (the sweep surfaced 1 finding; USER-adjudicated DEFER-to-v47.0 — the `0 NEW_FINDINGS` clause is amended accordingly):**
`CRANK_DO_WORK SHIPPED; AFKING_SUBSCRIPTION SHIPPED; LEGACY_AFKING_MODE + FREE_ETH_AUTOREBUY REMOVED; BURNIE_FLIP_AUTOREBUY KEPT@75BPS; FAUCET_BOUNDED; SWEEP NON-BRICK + CONCURRENT-SAFE [cancel-tombstone miss H-CANCEL-SWAP-MISS → v47.0]; FUNDING_WATERFALL + TWO-TIER_SKIP-KILL CORRECT; RNG_FREEZE_INTACT (+ obligations RETIRED by removal); JACKPOT_ETH_SPLIT REMOVED (single-call fits @305-ceiling); WWXRP_ZERO_REWARD; 1 MEDIUM FINDING (H-CANCEL-SWAP-MISS) DEFERRED→v47.0 [fix locked; SOURCE-TREE FROZEN held]; KNOWN_ISSUES_UNMODIFIED`

The deviation from the locked target is the single `0 NEW_FINDINGS` → `1 MEDIUM FINDING … DEFERRED→v47.0` clause, a direct consequence of the USER adjudication. All other 11 clauses hold verbatim.

### 9b. 6-Phase Wave Summary
Phase 316 (SPEC design-lock) + 317 (IMPL `df4ef365`) + 318 (TST — fixture repair + SAFE/JGAS proofs) + 319 (GAS `e4014f91`/`795e679d`) + 319.1 (OPEN-E IMPL `42140ceb`/`e1baa978`) + 320 (TERMINAL — this deliverable; SOURCE-TREE FROZEN; 2 AGENT-COMMITTED commits). Closure signal: `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`.

### 9c. Closure Signal
**`MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`** (the `16e9668a6de35cc0c809d81ce960aee137950687` placeholder resolves to the Phase 320 Commit 1 SHA at Commit 2). Verbatim propagation targets (resolved at Commit 2):
1. Frontmatter `closure_signal:` + `audit_subject_head:`.
2. §1 Audit Subject prose.
3. §3.A / §9b references.
4. ROADMAP.md (v46.0 milestone flip).
5. STATE.md (Last Shipped Milestone) + MILESTONES.md (archive entry).

### 9d. Deferred to v47.0+ — Handoff Register
- **H-CANCEL-SWAP-MISS** (MEDIUM) — SUB-07 cancel-tombstone restore → `.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md` (v47 manifest item 7, ISOLATED `AfKing.sol` surface).
- **testGas04** stale assertion (test-only) → same v47 AfKing test work.
- **v47.0 milestone scope** (carry, NOT live vectors — descriptive labels): presale-rake-free + lootbox-boon-unification + degenerette-resolution-gas + universal-claimable-pay + sDGNRS-redemption-accounting + degenerette-spins-per-currency + the AfKing cancel-tombstone fix. `.planning/PLAN-V47-MILESTONE-SCOPE.md` (7 items, ONE batched diff).
- The v44 §9d maximalist handoff register (135 anchors) carries forward unchanged (NOT live vectors).

---

*v46.0 TERMINAL findings authored 2026-05-24. Source-tree frozen throughout (`git diff 30b5c89c -- contracts/ test/` empty). 1 MEDIUM finding (H-CANCEL-SWAP-MISS) + 1 stale-test (testGas04) deferred to v47.0; both fixes locked. Closure signal resolves at Commit 2.*
