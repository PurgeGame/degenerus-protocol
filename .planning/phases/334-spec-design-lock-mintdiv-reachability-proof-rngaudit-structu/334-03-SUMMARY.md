---
phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu
plan: 03
subsystem: AfKing keeper subscription (pass-gating)
tags: [spec, design-lock, afking, pass-gating, open-e, sub-07, burnForKeeper]
requires:
  - 334-CONTEXT.md (D-08..D-13)
  - 334-RESEARCH.md (Patterns 2 & 3, grep-attestation table)
provides:
  - The settled AFSUB-01..05 signatures (validThroughLevel field, lazyPassHorizon view, refresh-or-evict crossing, burnForKeeper dual-contract removal)
  - The AFSUB preservation criteria (OPEN-E 4-protection, SUB-07 cancel-tombstone + v49 swap-pop, H-CANCEL-SWAP-MISS bar) for IMPL 335 / TST-02 336 / SWEEP-01 338
affects:
  - IMPL 335 (re-authors the AfKing + BurnieCoin batched diff against these signatures)
  - TST 336 (TST-02 empirically re-attests preservation)
  - SWEEP 338 (SWEEP-01 re-attests OPEN-E under pass-gating)
tech-stack:
  added: none (paper-only SPEC, zero contract edits)
  patterns: [level-denominated window mirroring the retired day-window, in-place storage-slot reinterpretation, refresh-or-evict via existing tombstone reuse]
key-files:
  created:
    - .planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-DESIGN-LOCK-AFKING.md
  modified: []
decisions:
  - "validThroughLevel repurposes the existing Sub.paidThroughDay slot (AfKing.sol:89) in-place — D-13 makes any layout break moot regardless"
  - "lazyPassHorizon(address) returns (uint24): deity = type(uint24).max sentinel, lazy/whale = covered-through level; lives alongside hasAnyLazyPass at DegenerusGame:1520, exposed via IGame"
  - "Crossing re-reads the horizon EXACTLY ONCE → refresh-or-evict (not an unconditional kick); the crossing is the ONLY hot-path external pass read (GASOPT-05 preserved)"
  - "burnForKeeper removed from BOTH AfKing (iface :57, calls :437/:641, window accounting, WINDOW_DAYS :220, FLAG_WINDOW_PAID) AND BurnieCoin (:472 impl, KeeperBurn :85, onlyAfKing :549) — IMPL diff touches BurnieCoin.sol (D-09)"
  - "Lazy-only refresh; NO refreshPass() entrypoint (D-10); pass-gating scope = autoBuy window only, autoOpen unchanged (D-08)"
metrics:
  duration: ~6 min
  completed: 2026-05-27
  tasks: 2
  files: 1
---

# Phase 334 Plan 03: AfKing Pass-Gated Subscription Design-Lock Summary

Settled the AfKing pass-gated subscription signatures (AFSUB slice of SC1) — `validThroughLevel` in-place repurposing of `Sub.paidThroughDay`, the new `lazyPassHorizon` level-horizon view with a `type(uint24).max` deity sentinel, the refresh-or-evict crossing control flow, the `burnForKeeper` dual-contract removal, and the OPEN-E / SUB-07 / swap-pop preservation criteria — all citing anchors grep-confirmed against the frozen v49.0 baseline `b0511ca2`.

## What Was Built

One markdown design-lock artifact, `334-DESIGN-LOCK-AFKING.md`, with two sections matching the plan's two tasks:

- **Task 1 (structural signatures, §1-§5 + §7):** pass-gating scope = autoBuy window only (D-08); `validThroughLevel` repurposes the `Sub.paidThroughDay` slot (offset 5, `AfKing.sol:89`) as an in-place reinterpretation, D-13 redeploy-fresh making any break moot; the new `lazyPassHorizon(address) returns (uint24)` view (deity = `type(uint24).max` sentinel, lazy/whale = covered-through `frozenUntilLevel`) alongside `hasAnyLazyPass` at `DegenerusGame.sol:1520` via `IGame`; the refresh-or-evict crossing flow (subscribe sets the horizon; per-iter `currentLevel <= validThroughLevel` with NO off-crossing external read preserving GASOPT-05; crossing re-reads ONCE → refresh-or-evict, not an unconditional kick); `burnForKeeper` full removal from BOTH `AfKing.sol` (iface `:57`, calls `:437`/`:641`, the `paidThroughDay`/`WINDOW_DAYS:220` window accounting, `FLAG_WINDOW_PAID`, the day-31 PAID branch) AND `BurnieCoin.sol` (`:472` impl, `KeeperBurn:85`, `onlyAfKing:549`); lazy-only / no `refreshPass()` (D-10).
- **Task 2 (preservation criteria, §6):** OPEN-E preservation — `fundingSource` stays, pass-gating does NOT moot OPEN-E, the 4 structural protections (consent-gate-at-subscribe `AfKing:393-403` / default-self byte-identical / no-escalation / trust-the-sub temporal bound) re-attest; SUB-07 in-place cancel-tombstone (`setDailyQuantity:458`) + the `_autoBuy:605` swap-pop reclaim + the v49 `membership ⟺ packed != 0` invariant; the H-CANCEL-SWAP-MISS missed-day/streak-reset class named as the regression eviction must NOT reproduce; flagged for TST-02 (336) + SWEEP-01 (338).

## Anchor Attestation (grep-confirmed vs b0511ca2, re-verified 2026-05-27)

All cited `file:line` were confirmed directly against the working tree (`git diff b0511ca2 HEAD -- contracts/` is empty, so the working tree IS the frozen contract baseline):

- `AfKing.sol`: `Sub` struct `:86-93` (paidThroughDay `:89`), subscribe `:374`, SUB-02 self-consent `:385-391`, OPENE-04 gate `:393-403`, pass-OR-pay `:430-443` (hasAnyLazyPass `:432`, burnForKeeper `:437`), setDailyQuantity `:458` (SUB-07 doc `:449-457`), _autoBuy reclaim `:605`, per-iter check `:630`, crossing `:631`, FREE extend `:633`, PAID burnForKeeper `:641`, burnForKeeper iface `:57`, WINDOW_DAYS `:220`, _autoBuyCursor `:214`.
- `BurnieCoin.sol`: burnForKeeper impl `:472` (onlyAfKing gate `:475`), KeeperBurn `:85`, onlyAfKing modifier `:549` — confirmed `burnForKeeper` is its ONLY application (the only `onlyAfKing` modifier use is `:475`).
- `DegenerusGame.sol`: hasAnyLazyPass `:1520` (deity bit `:1522`, frozenUntilLevel `:1524-1527`).
- `grep -rn burnForKeeper contracts/`: only `AfKing.sol` + `BurnieCoin.sol:472` reference it — confirms D-09's dual-contract removal scope and that `onlyAfKing` is orphaned (Assumptions A3/A4 confirmed).

## Deviations from Plan

The plan defines two tasks that both append to the **same single artifact** (`334-DESIGN-LOCK-AFKING.md` — Task 1 = structural signatures §1-§5/§7, Task 2 = preservation criteria §6). The document was authored complete (all sections) and committed in **one atomic commit** rather than two, because splitting a single complete markdown file into two commits would require an artificial intermediate truncated state — contradicting the "no broken intermediate" principle. Both tasks' `<acceptance_criteria>` and both `<verify>` automated grep blocks were run and PASS against the committed file. No functional deviation: every Task 1 AND Task 2 acceptance criterion is satisfied.

This is a documentation-organization choice (single complete artifact, single commit) — not a content change. No Rule 1-4 deviations occurred; no auth gates; no architectural decisions.

## Verification

- Task 1 automated verify: `test -f` + `validThroughLevel` + `type(uint24).max` + `burnForKeeper` + `BurnieCoin` + `refresh-or-evict` → **PASS**.
- Task 2 automated verify: `OPEN-E` + `swap-pop` + `tombstone` + `393-403`/`isOperatorApproved` + `H-CANCEL-SWAP-MISS` → **PASS**.
- `git diff --name-only -- contracts/` → **empty** (zero contract edits — paper-only SPEC honored).
- STATE.md / ROADMAP.md NOT modified (orchestrator owns those writes).

## Known Stubs

None. The artifact is a complete SPEC design-lock; no placeholder values, no unwired data. The `lazyPassHorizon` view name/width is intentionally left as a Claude's-Discretion item for IMPL 335 to finalize (per CONTEXT.md "Claude's Discretion") — this is a settled-semantic-with-IMPL-naming-latitude decision, not a stub.

## Self-Check: PASSED
