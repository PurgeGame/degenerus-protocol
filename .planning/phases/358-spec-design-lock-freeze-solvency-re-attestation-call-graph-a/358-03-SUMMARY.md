---
phase: 358-spec-design-lock-freeze-solvency-re-attestation-call-graph-a
plan: 03
subsystem: cross-cutting design-lock SPEC (freeze/solvency re-attestation + UDVT discipline + full call-graph grep-attestation + SPEC lock)
tags: [spec, design-lock, rng-freeze, solvency, udvt, byte-preservation, call-graph-attestation, spec-lock, paper-only]
dependency_graph:
  requires:
    - "358-01 (the 358-SPEC.md header + Frozen-Subject Guard + TDEC-02/03 core)"
    - "358-02 (the WWXRP-02 + BURNIE-03 + SALVAGE-02 + CANCEL-02 small-feature locks + the small-feature re-attestation table)"
  provides:
    - "358-SPEC.md Cross-Cutting RNG-Freeze Re-Attestation (all 8 items freeze-intact; the UDVT abi.encodePacked uint32-cast byte-image flagged LOAD-BEARING)"
    - "358-SPEC.md Cross-Cutting SOLVENCY Re-Attestation (6-of-8 off the ETH path + the 2 flagged exceptions; claimablePool <= balance on every path)"
    - "358-SPEC.md UDVT Width/Byte-Preservation Discipline (D-19 per-site matrix + D-20 test-file handling — the IMPL must follow byte-for-byte)"
    - "358-SPEC.md Full Call-Graph Grep-Attestation (8 blocks; every CONTEXT Source-anchor file:line grep-confirmed vs 1e7a646d; the 3 noted drifts reconciled)"
    - "358-SPEC.md SPEC Lock (LOCKED) — 6 owned req-IDs mapped to IMPL/TST owners; all 8 ROADMAP Phase-358 Success Criteria asserted SATISFIED"
    - "the COMPLETE LOCKED v57.0 design-lock SPEC — Phase 359 authors the batched diff with zero un-checked assumptions"
  affects:
    - "359 IMPL (the batched contract diff authored under every locked shape; the UDVT byte-preservation discipline is fixed here)"
    - "360 GAS (the UDVT GAS-neutrality gate — packed Sub day fields stay uint24)"
    - "361 TST (SEC-01 per-site byte-diff + SEC-02 solvency-invariant + HYG-01/02/03 + SALVAGE-03 + CANCEL-03 — the proof obligations this SPEC hands forward)"
tech_stack:
  added: []
  patterns:
    - "design-lock SPEC, paper-only (ZERO contracts/*.sol)"
    - "frozen-subject grep-attestation (every file:line actually re-grepped vs 1e7a646d; drifts corrected inline; no by-construction)"
    - "SPEC Lock asserting ROADMAP Success Criteria per-criterion with the satisfying section named"
key_files:
  created:
    - ".planning/phases/358-spec-design-lock-freeze-solvency-re-attestation-call-graph-a/358-03-SUMMARY.md"
  modified:
    - ".planning/phases/358-spec-design-lock-freeze-solvency-re-attestation-call-graph-a/358-SPEC.md"
decisions:
  - "RNG-freeze re-attestation: all 8 items freeze-intact; item (5) UDVT is the ONLY one touching the RNG-entropy abi.encodePacked boundary → LOAD-BEARING; the 3 sites (:1405/:1828/:1011) cast Day->uint32 so the keccak preimage byte-image is preserved 4-bytes-not-3; rngWordByDay KEY is mapping(uint32=>uint256) :454 (byte-preserved)"
  - "SOLVENCY re-attestation: 6 of 8 off the ETH/claimablePool path (debit byte-unchanged); BURNIE = posture-widening (restores ticket claims, pro-rata, no unbacked obligation); SALVAGE = solvency-positive (less ETH out + sDGNRS-owned BURNIE transfer, no emission); CANCEL + SALVAGE-BURNIE = sDGNRS-owned/BURNIE-emission no new ETH draw; claimablePool <= balance on every path"
  - "UDVT D-19 per-site matrix locked: 3 encodePacked cast uint32, packed Sub day fields stay uint24 (no cold-slot spill), standalone+indexed stay uint32, rngWordByDay key unchanged, operators <,<=,==,%,+,- + solc 0.8.34 UDVT support; D-20 contract-side in the ONE 359 diff, ~143 test-file updates as separate agent-committable commits"
  - "Full call-graph grep-attestation: every CONTEXT Source-anchor actually re-grepped vs 1e7a646d (8 blocks A-H); 3 NOTED drifts reconciled — HYG-02 :809 (advanceGame/runRewardJackpots comment, fix target _consolidatePoolsAndRewardJackpots :794), GameOverModule :106 inside if(preRefundAvailable!=0) guard (does not weaken the future-day-word lemma), auto-evict :1175/:1240 _removeFromSet-leaves-_subOf-out-of-set (CANCEL-02 D-32 explicit-delete); plan-01/02 line drifts folded; no by-construction survives"
  - "SPEC Lock: status flipped DRAFT -> LOCKED in both the header and the dedicated SPEC Lock section; 6 owned req-IDs (WWXRP-02/TDEC-02/TDEC-03/BURNIE-03/SALVAGE-02/CANCEL-02) mapped to IMPL/TST owners; all 8 ROADMAP Phase-358 SCs asserted SATISFIED with the satisfying section named (SC1->WWXRP-02, SC2->TDEC-02, SC3->TDEC-03, SC4->UDVT discipline, SC5->the 3 cross-cutting/grep sections, SC6->BURNIE-03, SC7->SALVAGE-02, SC8->CANCEL-02)"
metrics:
  duration: "~1 session"
  completed: 2026-06-04
  tasks: 2
  files: 1
---

# Phase 358 Plan 03: Cross-Cutting Re-Attestation + UDVT Discipline + Full Call-Graph Grep-Attestation + SPEC Lock Summary

**One-liner:** Completed the v57.0 design-lock SPEC — appended the cross-cutting RNG-freeze + SOLVENCY re-attestation (all 8 items, the UDVT `abi.encodePacked` uint32-cast byte-image flagged load-bearing), the UDVT width/byte-preservation discipline (D-19/D-20), the full call-graph grep-attestation of every CONTEXT "Source anchors" `file:line` against `1e7a646d` (8 blocks, the 3 noted drifts reconciled, plan-01/02 drifts folded), and the SPEC Lock flipping DRAFT→LOCKED and asserting all 8 ROADMAP Phase-358 Success Criteria SATISFIED — paper-only, zero contract mutation.

## What Was Built

`358-SPEC.md` grown from 283 lines (post-plan-02) to **523 lines** with five new sections + the header status flip:

- **`## Cross-Cutting RNG-Freeze Re-Attestation (paper) (SEC-01 design feed)`** — one labelled row per the 8 milestone items asserting freeze-intact, each with its source anchor + the TST-361 SEC-01 proof obligation: (1) BATCH BURNIE-accounting-only (`Quests:947-949`→`MintModule:1220/:1355`), (2) WWXRP RNG-insensitive counter/flag gated by the committed `s==9` + pre-liveness `:413`, (3) terminal-decimator weight+bucket+subBucket precede the draw (the future-day-word lemma, cross-ref TDEC-03), (4) HYG comment/test-only, (5) **UDVT LOAD-BEARING** — the 3 `abi.encodePacked(…day…)` sites cast `Day→uint32` to preserve the keccak preimage byte-image (`:1405`/`:1828`/`:1011`), `rngWordByDay` KEY unchanged (`Storage:454`), the per-site byte-diff gate TST 361 enforces empirically, (6) BURNIE `purchaseCoin` reads no `rngWord` (`_livenessTriggered:891`/`gameOverPossible:895`), (7) SALVAGE reads only the SETTLED prior-day word under `rngLockedFlag` (no new VRF), (8) CANCEL reads no `rngWord`, `rngLock`-gated `:300`.
- **`## Cross-Cutting SOLVENCY Re-Attestation (paper) (SEC-02 design feed)`** — SIX clean items (BATCH/WWXRP/HYG/TDEC/UDVT/CANCEL) OFF the ETH/`claimablePool` path with the DEBIT code byte-unchanged, each with its SEC-02 obligation; the TWO functional exceptions flagged: BURNIE (posture-widening — RESTORES ticket claims, pro-rata, no unbacked obligation) + SALVAGE (solvency-POSITIVE — only the ETH part `cashWei − actualBurnie` relabeled out of SDGNRS `:976-977`, BURNIE TRANSFERRED from sDGNRS-owned sources, no emission); CANCEL + the SALVAGE-BURNIE leg noted as sDGNRS-owned/BURNIE-emission with no new ETH-pool draw; **`claimablePool <= balance` asserted on EVERY path**.
- **`## UDVT Width/Byte-Preservation Discipline (design feed — UDVT-01/02/03 built at IMPL 359)`** — the per-site D-19 matrix items 1–6 (3 encodePacked sites cast uint32; packed `Sub`/struct day fields stay uint24-backed, no cold-slot spill; standalone + `indexed` day topics stay raw uint32; `rngWordByDay` KEY `mapping(uint32=>uint256)` unchanged; operator overloads `<,<=,==,%,+,-` + solc 0.8.34 UDVT support confirmed; ~649 lines/27 contracts) + D-20 (contract-side UDVT in the ONE 359 diff held for hand-review; ~143 test-file updates as separate agent-committable commits).
- **`## Full Call-Graph Grep-Attestation (vs 1e7a646d)`** — the frozen-subject guard re-asserted, then a table in **8 blocks** (A Degenerette/WWXRP · B Decimator/TDEC · C Advance/GameOver/RNG · D Quests/streak/BATCH-01 · E BURNIE coin-buy · F SALVAGE · G CANCEL · H HYG-01 test refs), one row per CONTEXT "Source anchors" `file:line` with `Confirmed (Y/N) | Drift note`. Every anchor grep-confirmed Y against `1e7a646d`; the 3 NOTED drifts recorded with reconciliation + the plan-01/02 drifts folded in (consistent with their tables).
- **`## SPEC Lock (LOCKED)`** — status flipped DRAFT→LOCKED; the 6 owned req-IDs mapped to their IMPL/TST owners; the `### ROADMAP Phase-358 Success Criteria` checklist maps all 8 SCs (SC1→WWXRP-02, SC2→TDEC-02, SC3→TDEC-03, SC4→UDVT discipline, SC5→the 3 cross-cutting/grep sections, SC6→BURNIE-03, SC7→SALVAGE-02, SC8→CANCEL-02) each marked SATISFIED with the satisfying section named; the final paper-only attestation (ZERO contracts touched).
- **Header status flip** — the document header's `**Status:** DRAFT` → `LOCKED` with the plan-by-plan provenance and the owned-design-lock list.

## Full Call-Graph Grep-Attestation — drifts reconciled (the actual greps were re-run)

Every CONTEXT "Source anchors" `file:line` was actually re-grepped against the frozen subject (working tree byte-identical to `1e7a646d`). The 3 NOTED drifts + the plan-01/02 drifts:

1. **HYG-02 second site `DegeneretteModule:809`** — re-grepped: `:809` does NOT contain a `_runRewardJackpots` SYMBOL; the exact text @ `1e7a646d` is the comment `// snapshot that advanceGame / runRewardJackpots operates on stays` (inside the poolFrozen ETH-share block `:807-812`). The first site `AdvanceModule:1191` is the comment-table row `JackpotModule (_runRewardJackpots)`. The actual resolution function is `_consolidatePoolsAndRewardJackpots` (`:794`, called `:477`) — the HYG-02 fix target. Both are comment-only, owned at TST 361.
2. **GameOverModule `:106`** — re-grepped: the `rngWord = rngWordByDay[day]` read IS inside `if (preRefundAvailable != 0)` (`:105`) with revert-on-zero `:107`. Recorded + cross-ref the TDEC-03 Step 4 reconciliation (the future-day-word property is a property of the KEY, holds regardless of the read-guard).
3. **Auto-evict explicit-delete** — re-grepped: the tombstone-reclaim path (`:1148`) does `delete _subOf[player]` + `_removeFromSet:1149`, but the pass-expiry (`:1187`) and funding-out (`:1246`) evict paths do `_finalizeAfking` + `sub.dailyQuantity = 0` + `_removeFromSet` ONLY — they do NOT `delete _subOf`, leaving the slot's `pendingBurnie`/`affiliateBase` claimable OUT-OF-SET (the latent inconsistency). Cross-ref CANCEL-02 D-32 (the forfeit intent requires the explicit `delete _subOf`).

Verified-at-planning anchors marked Y: `_purchaseCoinFor:887-907` discards-returns; BATCH-01 `:947-949` inline + the `:1220`/`:1355` fold; SALVAGE `:976-977` relabel; manual-cancel `:345-362` + the FALSE `:348-351` comment; the 3 encodePacked sites `:1405`/`:1828`/`:1011`; `TerminalDecEntry:1585-1591`; `_livenessTriggered:1231-1240`; `getPlayerQuestView:1088`. The decisive BURNIE `_queueTicketsScaled` 2-caller grep (`MintModule:1251`, `GameAfkingModule:800`; definition `Storage:612`) is re-confirmed (the planning's third "caller" `DegenerusGame:226` is the UN-scaled `_queueTickets`). HYG-01 stale `gameSetAutoRebuy` test refs attested present (with the `:385`-vs-`:456` base-vs-TakeProfit distinction noted; rename target `coinSetAutoRebuy(bool,uint256)` at `CoverageGap222.t.sol:1183`).

## Deviations from Plan

None — the two tasks transcribed the locked shapes exactly: Task 1 authored the three cross-cutting sections (RNG-freeze + SOLVENCY + UDVT discipline) per D-19/D-20 and the CONTEXT freeze/solvency framings; Task 2 built the full grep-attestation table (every anchor actually re-grepped, the 3 noted drifts reconciled, plan-01/02 drifts folded) + flipped the SPEC Lock asserting all 8 SCs. The `min_lines: 420` artifact floor was met with genuine content (523 lines — the 8-block attestation table alone is substantial), no padding needed. Zero `contracts/*.sol` mutation throughout; no fenced implementation code.

## Authentication Gates

None — paper-only SPEC, no external services, no package installs. Per the project's "only contract commits need approval" rule, the docs commits ran hands-off.

## Freeze / Solvency Posture (the locked design floor)

- **RNG-freeze:** intact on all 8 items. The UDVT byte-image (item 5) is the LOAD-BEARING freeze item — the only one touching the RNG-entropy `abi.encodePacked` boundary; the 3 sites cast `Day→uint32` (4-byte preimage preserved, not shortened to 3), `rngWordByDay` KEY byte-preserved. SEC-01 (the per-site byte-diff + determinism harness) is OWNED at TST 361; the bucket-promotion freeze adversarially probed at TERMINAL 362.
- **SOLVENCY:** `claimablePool <= balance` re-attested on every path. 6 of 8 items off the ETH path (debit byte-unchanged); BURNIE = posture-widening (no unbacked obligation); SALVAGE = solvency-positive (less ETH out + no BURNIE emission). SEC-02 (the solvency-invariant harness) is OWNED at TST 361.

## Known Stubs

None — paper-only SPEC; no code, no data wiring, no placeholders. The SPEC is now COMPLETE + LOCKED (all 10 table-of-contents sections filled by plans 01/02/03). The downstream IMPL/GAS/TST/TERMINAL work is owned by phases 359-362 (the milestone shape), NOT stubs.

## Threat Flags

None — no new security-relevant CODE surface was introduced (paper-only SPEC, zero contracts changed). The design-level threat register the SPEC LOCKS (T-358-15..18 from the plan's `<threat_model>`) is addressed: T-358-15 (UDVT preimage shortening) by the UDVT discipline + the Cross-Cutting RNG-Freeze section (the 3 sites cast uint32, the load-bearing item); T-358-16 (packed-day cold-slot spill) by UDVT D-19(2/3); T-358-17 (un-checked anchor) by the Full Call-Graph Grep-Attestation (every anchor re-grepped, the 3 noted drifts reconciled, no "by construction" survives); T-358-18 (flagged solvency exception unbacked) by the Cross-Cutting SOLVENCY section (both exceptions solvency-positive-or-neutral, `claimablePool <= balance` on every path). No HIGH design hole remains open at the SPEC Lock.

## Requirements Completed

- **WWXRP-02** — design-locked (asserted in the SPEC Lock; SC1 SATISFIED).
- **TDEC-02** — design-locked (SPEC Lock; SC2 SATISFIED).
- **TDEC-03** — design-locked (SPEC Lock; SC3 SATISFIED).
- **BURNIE-03** — design-locked (SPEC Lock; SC6 SATISFIED).
- **SALVAGE-02** — design-locked (SPEC Lock; SC7 SATISFIED).
- **CANCEL-02** — design-locked (SPEC Lock; SC8 SATISFIED).

(These 6 are the 358 OWNED req-IDs; their primary authoring landed in plans 01 [TDEC-02/03] + 02 [WWXRP-02/BURNIE-03/SALVAGE-02/CANCEL-02]. Plan 03 LOCKS them in the SPEC Lock + asserts the 8 ROADMAP SCs. UDVT-01/02/03 are design-fed here, built at IMPL 359.)

## Self-Check: PASSED

- `358-SPEC.md` exists at the expected path — FOUND (523 lines, LOCKED).
- `358-03-SUMMARY.md` exists at the expected path — FOUND.
- Commit `ed4a853d` (Task 1: cross-cutting RNG-freeze + SOLVENCY + UDVT discipline) — FOUND in `git log`.
- Commit `fb02931e` (Task 2: full call-graph grep-attestation + SPEC Lock) — FOUND in `git log`.
- `git diff --quiet 1e7a646d HEAD -- contracts/` — clean (ZERO contract mutation) throughout.
- Both task automated verifies — PASS; all 5 sections present; status LOCKED; all 8 SCs (SC1..SC8) asserted SATISFIED; 6 owned req-IDs present; the 3 noted drifts reconciled; `claimablePool <= balance` + `solvency-positive` + `0.8.34` + D-19/D-20 present; min_lines floor (420) met (523); zero fenced code.
