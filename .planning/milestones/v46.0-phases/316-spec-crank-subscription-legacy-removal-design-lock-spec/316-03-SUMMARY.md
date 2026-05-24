---
phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec
plan: 03
subsystem: spec-design-lock
tags: [spec, subscription, quantity-model, funding-waterfall, skip-kill, sub-09, open-b, open-c, whale-pass-expiry, permanent-deity]
requires:
  - "316-01 (ADD-half: SUB-02 authorization, REW-01 OPEN-B reward-path, OPEN-C disposition)"
  - "316-02 (REMOVE footprint: RM-05 setAfKingMode→self-subscribe, JackpotEthWin ABI break, slot-shift)"
  - "316-05 (JGAS-01 decision gate)"
provides:
  - "316-SPEC.md `## Quantity & Funding Model` (Task 1, prior commit 9a05e2ad)"
  - "316-SPEC.md `## Protocol-Owned Subs (SUB-09)` — sDGNRS + Vault self-subscribe init configs + Task-2 user-ratified permanent-deity free-renew"
  - "316-SPEC.md `## SPEC-Open Resolutions` — OPEN-B / OPEN-C / 1-price-lootbox denomination / claimable-only / JackpotEthWin ABI-break"
affects:
  - "Phase 317 IMPL (SUB-09 self-subscribe wiring; relies on EXISTING DegenerusGame:222/223 Deity grant — no NEW bit-setter; OPEN-C contract-auditor trace)"
  - "Phase 320 AUDIT (economic-analyst no-distortion check on permanent-deity; zero-day-hunter freeze trace)"
tech-stack:
  added: []
  patterns:
    - "permanent-deity free-renew: hasAnyLazyPass(SDGNRS/VAULT) permanently true via the EXISTING constructor Deity-bit grant — zero per-renewal cost, no BURNIE funding stream"
    - "claimable-only = emergent empty-_poolOf property, no new flag"
    - "OPEN-B reward→0 via the guarded _ethToBurnieValue idiom"
key-files:
  created:
    - ".planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-03-SUMMARY.md"
  modified:
    - ".planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md (APPENDED 2 sections; prior sections untouched)"
decisions:
  - "D-316-03-WHALE-EXPIRY-01: protocol-sub whale-pass-expiry free-renew = permanent-deity (USER-RATIFIED 2026-05-23); relies on EXISTING DegenerusGame.sol:222/223 constructor Deity-bit grant — Phase 317 needs NO new bit-setter, only to preserve that grant byte-unmodified through the batched diff"
  - "D-316-03-DEITY-SIDEEFFECT-02: Deity trait/gold side-effect on pinned protocol addresses ACCEPTED (T-316-12, already live behavior — RETAIN not add)"
  - "D-316-03-AUDIT-REFRAME-03: no BURNIE funding stream to close → economic-analyst @AUDIT validates NO economic distortion from the permanent Deity bit (not a funding-closure check)"
  - "D-316-03-OPEN-B-04: reward→0-never-revert via guarded _ethToBurnieValue (MintModule:1416); priceForLevel non-zero secondary backstop"
  - "D-316-03-OPEN-C-05: CEI-proof lean, no new guard; mandatory IMPL mint→lootbox→prize-pool→EV-cap→quest trace routed to contract-auditor @IMPL/TST"
metrics:
  duration: "~10 min (continuation from Task-2 checkpoint ratification)"
  completed: 2026-05-23
  tasks: 3
  files_touched: 1
  lines_added: 74
---

# Phase 316 Plan 03: Open-Item Resolution (Quantity/Funding/Skip-Kill + SUB-09 + SPEC-Open) Summary

**One-liner:** Locked the SUB-09 protocol-owned-sub init configs (sDGNRS claimable-only flat-1 + 2% reinvest + `setCoinflipAutoRebuy(self,true,0)`; Vault claimable-only flat-1 no-reinvest) and recorded the USER-RATIFIED `permanent-deity` whale-pass-expiry free-renew — discovering that the permanent Deity bit is ALREADY set on SDGNRS/VAULT in the live `DegenerusGame` constructor (`:222`/`:223`), so Phase 317 needs no new bit-setter — plus resolved OPEN-B (reward→0 via the guarded `_ethToBurnieValue`), OPEN-C (CEI-proof lean + `contract-auditor` trace), the 1-price-lootbox denomination, claimable-only confirmation, and the `JackpotEthWin` ABI-break delta note.

## What this plan delivered

This was a **continuation** from a `checkpoint:decision` (Task 2). The prior executor completed Task 1 (`## Quantity & Funding Model`, commit `9a05e2ad`) and paused at the Task-2 whale-pass-expiry decision. The user ratified `permanent-deity`. This session recorded that decision and authored Task 3.

- **Task 1** — *(prior commit `9a05e2ad`, verified present, NOT redone)*: `## Quantity & Funding Model` — COEXIST max-semantics quantity model (`max(dailyQuantity≥1, floor(claimable×reinvestPct/price))`, one flags byte + `reinvestPct`, no new slot, price-unit denomination via `TICKET_SCALE=400`); the existing `drainGameCreditFirst=true` funding waterfall; the two-tier skip-kill keyed on pinned `ContractAddresses.VAULT`/`SDGNRS` identity (never a settable flag).
- **Task 2** — USER-RATIFIED `permanent-deity` (recorded verbatim, folded into Task 3's SUB-09 section per plan instruction — not a separate commit).
- **Task 3** — appended two sections to `316-SPEC.md`:
  - `## Protocol-Owned Subs (SUB-09)` — sDGNRS + Vault self-subscribe init configs; SUB-02 self-consent path; the verbatim `permanent-deity` decision + the material constructor-grant finding + the T-316-12 ratified side-effect + the re-framed `economic-analyst` AUDIT routing.
  - `## SPEC-Open Resolutions` — OPEN-B, OPEN-C, the 1-price-lootbox denomination (points to Task-1 lock), claimable-only confirmation, and the `JackpotEthWin` ABI-break delta note.

## Key decisions

1. **Whale-pass-expiry free-renew = `permanent-deity` (USER-RATIFIED).** The protocol subs free-renew because `hasAnyLazyPass(SDGNRS/VAULT)` is permanently `true` via the never-expiring Deity bit (`HAS_DEITY_PASS_SHIFT=184`) → the keeper's monthly renewal gate takes the free pass-extend path forever at zero per-renewal cost, no BURNIE funding stream.
2. **Material source finding (grep-verified):** the permanent Deity bit is **ALREADY SET** on both pinned addresses in the live `DegenerusGame` constructor — `DegenerusGame.sol:222` (SDGNRS) + `:223` (VAULT), comment "Vault addresses get deity-equivalent score boost." So Phase 317's obligation is the WEAKER "rely on + preserve the existing grant byte-unmodified through the batched diff," NOT "add a Deity-bit setter" (the planner's Task-2 option-cons had assumed a new write). Recorded so IMPL does not author a redundant write and AUDIT re-verifies survival.
3. **T-316-12 side-effect ACCEPTED (accept-with-condition):** the Deity trait/gold utility on the pinned protocol addresses is already live behavior; `permanent-deity` RETAINS it, introduces no new side-effect. User ratified with eyes open.
4. **AUDIT routing re-framed:** zero per-renewal cost → no funding stream to close → `economic-analyst` @AUDIT validates NO economic distortion from the permanent Deity bit (trait/gold side-effect on non-player addresses + permanently-true `hasAnyLazyPass` not skewing pass-gated EV). Named, not run.
5. **OPEN-B** = reward→0-never-revert via the guarded `_ethToBurnieValue` (`MintModule:1416` `if (amountWei==0||priceWei==0) return 0;`) + the non-zero `priceForLevel` (`PriceLookupLib:21`) secondary backstop.
6. **OPEN-C** = CEI-proof lean, no new guard; mandatory IMPL trace of the mint→lootbox→prize-pool→EV-cap→quest callback chain routed to `contract-auditor` @IMPL/TST.

## Source citations (all grep-verified against HEAD `62fb514b` on 2026-05-23, SC#5)

| Claim | Anchor | Verified |
|-------|--------|----------|
| sStonk init claim + setAfKingMode | `StakedDegenerusStonk.sol:360` / `:361` (decl `:13`) | ✓ |
| sStonk re-claim | `StakedDegenerusStonk.sol:404` | ✓ |
| Vault claim | `DegenerusVault.sol:581` → `:582` | ✓ |
| setCoinflipAutoRebuy shape | `DegenerusVault.sol:78`; wrapper `:685`→`:686` | ✓ |
| claimWhalePass early-return | `DegenerusGameWhaleModule.sol:1004`, `:1007` `if (halfPasses == 0) return;` | ✓ |
| Deity bit constant | `BitPackingLib.sol:71` `HAS_DEITY_PASS_SHIFT = 184` | ✓ |
| `_hasAnyLazyPass` Deity read | `DegenerusGame.sol:1610` / `:1612` | ✓ |
| **EXISTING Deity-bit constructor grant** | `DegenerusGame.sol:216` (ctor), `:222` (SDGNRS), `:223` (VAULT) | ✓ |
| `_ethToBurnieValue` zero-guard | `DegenerusGameMintModule.sol:1412` decl, `:1416` guard | ✓ |
| `priceForLevel` pure non-zero | `PriceLookupLib.sol:21` | ✓ |
| `JackpotEthWin` fields | `DegenerusGameJackpotModule.sol:69` decl, `:75`/`:76` fields | ✓ |
| Pinned identity constants | `ContractAddresses.sol:37` VAULT / `:47` SDGNRS | ✓ |

## Deviations from Plan

**1. [Rule 1 — corrected stale citation] `JackpotEthWin` field line numbers.** The plan's `<interfaces>` carried `:75`/`:76` for `rebuyLevel`/`rebuyTickets`; an interim grep offset suggested `:74`/`:75`. Re-grep confirmed the canonical `:75`/`:76` (matching the 316-02 section). Authored with the verified `:69` decl + `:75`/`:76` fields. No design impact.

**2. [Rule 2 — material finding strengthening the decision] EXISTING constructor Deity grant.** The plan's Task-2 `permanent-deity` option-cons stated "Requires setting the Deity bit on VAULT/SDGNRS at init (a contract change in the IMPL diff)." Grep-verification against HEAD found the bit is **already set** in the live constructor (`DegenerusGame.sol:222`/`:223`). Recorded as a MATERIAL SOURCE FINDING that weakens the Phase 317 obligation (rely-on + preserve, not add) — this is a correctness refinement of the recorded decision, not a change to the user's selection. Per `feedback_verify_call_graph_against_source` (every "by construction" claim grep-verified pre-IMPL).

## Threat surface scan

No new security-relevant surface introduced (read-only doc authoring). T-316-12 (Deity side-effect Elevation) is the plan's pre-registered accept-with-condition disposition, ratified by the user and recorded; no NEW threat flag. T-316-10 (DoS — under-specified whale-expiry renewal) is MITIGATED by recording the user-ratified `permanent-deity` decision verbatim.

## Known Stubs

None. This is a SPEC design-lock document; the SUB-09 / SPEC-open items are all resolved with HEAD-verified citations, no placeholders. The deferred numeric calibrations (Phase 319 gas-peg constants) and the named-but-not-run AUDIT skills (`economic-analyst`, `contract-auditor`, `zero-day-hunter`) are explicit phase-routing, not stubs.

## Verification

- Task 3 automated verify: `## Protocol-Owned Subs (SUB-09)` + `## SPEC-Open Resolutions` + `setCoinflipAutoRebuy` + `claimWhalePass` + `whale-pass` + `_ethToBurnieValue` all present — **PASS**.
- Prior sections intact: `## Quantity & Funding Model`, `## ADD Design — Do-Work Crank`, `## REMOVE Footprint`, `## JGAS-01 Decision Gate`, `## Storage Slot-Shift Plan`, `## VRF-Freeze Obligation Retirement` all still present (untouched).
- ZERO `contracts/` and ZERO `test/`+`contracts/test/` mutations — `git status --short -- contracts/ test/ contracts/test/` empty; only `316-SPEC.md` modified.
- "settable flag" prohibition present in the two-tier skip-kill (Task-1 lock, intact).
- The whale-pass-expiry decision recorded as a USER-RATIFIED choice (not defaulted).

## Self-Check: PASSED

- `316-03-SUMMARY.md` — FOUND.
- `316-SPEC.md` — FOUND; `## Protocol-Owned Subs (SUB-09)` + `## SPEC-Open Resolutions` present; `DegenerusGame.sol:222` ctor-grant citation present.
- Task 1 commit `9a05e2ad` — FOUND in git log.
- ZERO `contracts/` + `test/` + `contracts/test/` mutations confirmed (git status clean for those paths).
