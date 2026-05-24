---
phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec
verified: 2026-05-23T00:00:00Z
status: passed
score: 5/5
overrides_applied: 0
---

# Phase 316: Crank + Subscription + Legacy-Removal Design Lock — Verification Report

**Phase Goal:** Lock the FULL v46.0 add+remove+JGAS design BEFORE any contract change; grep-verify every call-graph claim against contract HEAD; produce `316-SPEC.md` covering all three halves (do-work crank ADD + legacy AFKing/ETH-auto-rebuy REMOVE + JGAS-01 jackpot-split-removal decision gate) so the milestone executes as one batched diff / one test pass / one audit.
**Verified:** 2026-05-23
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ADD design fully locked (crank entry signatures, work-type encoding, reward formula, batchPurchase, cursor sweep, authorization, 5 PROTO sigs on pinned AF_KING) | VERIFIED | `316-SPEC.md` sections `## ADD Design — Do-Work Crank`, `## ADD Design — Subscription Sweep & Authorization`, `## PROTO Additions` all present and substantive |
| 2 | Subscription quantity + funding model locked (flat dailyQuantity min-1 COEXIST reinvestPct via max-semantics, funding waterfall, two-tier skip-kill by pinned identity) | VERIFIED | `## Quantity & Funding Model` section is fully substantive; pins VAULT/:37 + SDGNRS/:47 identity check; max-semantics formula locked |
| 3 | Protocol-owned subs at init specified (SUB-09 sDGNRS + Vault configs, whale-pass-expiry USER-RATIFIED as permanent-deity, denomination resolved) | VERIFIED | `## Protocol-Owned Subs (SUB-09)` and `## SPEC-Open Resolutions` sections; whale-expiry decision recorded as "Task-2 USER-RATIFIED DECISION" verbatim; constructor grant at :222/:223 grep-confirmed |
| 4 | REMOVE design locked (PROTO-01/RM-04 KEEP+EXPOSE, RM-01..06 footprint, slot re-derivation, VRF-freeze retirement) AND JGAS-01 locked (worst-case-first gas, decision string verbatim, footprint grep-verified across BOTH modules, 305 ceiling preserved) | VERIFIED | `## REMOVE Footprint`, `## Storage Slot-Shift Plan`, `## VRF-Freeze Obligation Retirement`, `## JGAS-01 Decision Gate` all present; decision string "REMOVE pending JGAS-04 empirical confirmation, RETAIN-fallback documented" in SPEC |
| 5 | Every cited file:line grep-verified against HEAD; zero unverified "by construction" claims; keeper does NOT depend on anything RM-* deletes; ZERO contracts/ + ZERO test/ mutations | VERIFIED | `## Call-Graph Attestation` section with per-file verdict roll-up; attestation statement explicitly negates "by construction"; keeper grep: 0 RM symbols; `git diff --name-only 62fb514bfcc8ad042a45cef960e5ff0ff6fbb801 HEAD -- contracts/ test/` returns empty |

**Score:** 5/5 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.planning/phases/316-.../316-SPEC.md` | Single deliverable containing all 13 expected section headers | VERIFIED | All 13 headers confirmed present (see section header check below) |

### Section Header Check (13 required)

Actual headers found via `grep -n "^## "` on the SPEC file:

| # | Expected header | Status |
|---|----------------|--------|
| 1 | `## Requirement Design Coverage` | PRESENT (line 21) |
| 2 | `## Success Criteria Coverage` | PRESENT (line 72) |
| 3 | `## ADD Design — Do-Work Crank` | PRESENT (line 88) |
| 4 | `## ADD Design — Subscription Sweep & Authorization` | PRESENT (line 135) |
| 5 | `## PROTO Additions` | PRESENT (line 174) |
| 6 | `## REMOVE Footprint` | PRESENT (line 190) |
| 7 | `## Storage Slot-Shift Plan` | PRESENT (line 265) |
| 8 | `## VRF-Freeze Obligation Retirement` | PRESENT (line 315) |
| 9 | `## JGAS-01 Decision Gate` | PRESENT (line 341) |
| 10 | `## Quantity & Funding Model` | PRESENT (line 423) |
| 11 | `## Protocol-Owned Subs (SUB-09)` | PRESENT (line 467) |
| 12 | `## SPEC-Open Resolutions` | PRESENT (line 511) |
| 13 | `## Call-Graph Attestation` | PRESENT (line 541) |

**All 13 required section headers verified.**

---

## SC#5 Spot-Check — File:Line Citations vs Contract HEAD

The load-bearing gate. Spot-checked a representative cross-section of SPEC citations against live contract source at HEAD.

| Citation | SPEC claims | Actual (grep result) | Verdict |
|----------|-------------|----------------------|---------|
| `ContractAddresses.VAULT` | `:37` | `grep -n "VAULT" ContractAddresses.sol` → `37: address internal constant VAULT =` | MATCH |
| `ContractAddresses.SDGNRS` | `:47` | `grep -n "SDGNRS" ContractAddresses.sol` → `47: address internal constant SDGNRS =` | MATCH |
| `DegenerusGame` ctor Deity grant | `:222`/`:223` | `grep -n "mintPacked_.*SDGNRS\|mintPacked_.*VAULT" DegenerusGame.sol` → `:222` / `:223` exactly | MATCH |
| `_hasAnyLazyPass` decl | `:1610` (private view) | `grep -n "_hasAnyLazyPass" DegenerusGame.sol` → `1610: function _hasAnyLazyPass(...)` | MATCH |
| `_hasAnyLazyPass` reader `:1580` | `DegenerusGame.sol:1580` | `grep -n "_hasAnyLazyPass" DegenerusGame.sol` → `1580: if (!_hasAnyLazyPass(player))` | MATCH |
| `_hasAnyLazyPass` reader `:1660` | `DegenerusGame.sol:1660` | `grep -n "_hasAnyLazyPass" DegenerusGame.sol` → `1660: if (_hasAnyLazyPass(player)) return true;` | MATCH |
| `STAGE_JACKPOT_ETH_RESUME = 8` | AdvanceModule `:70` | `grep -n "STAGE_JACKPOT_ETH_RESUME" AdvanceModule.sol` → `70: uint8 private constant STAGE_JACKPOT_ETH_RESUME = 8;` | MATCH |
| AdvanceModule resume-check block | `:453-456` | `sed -n '453,457p' AdvanceModule.sol` → `if (resumeEthPool != 0) { payDailyJackpot(true, lvl, rngWord); stage = STAGE_JACKPOT_ETH_RESUME; break; }` at lines 453-456 | MATCH (2-line comment at :452 is the DRIFT the SPEC records) |
| `_unlockRng` NOT in resume branch | resume branch `:453-456` has no `_unlockRng` | `sed -n '453,460p'` — no `_unlockRng` in that block; `_unlockRng` appears at `:331/:402/:467/:629` elsewhere | VERIFIED |
| `_unlockRng` at coin-tickets stage | `:467` | `grep -n "_unlockRng" AdvanceModule.sol` → `467: _unlockRng(day);` | MATCH |
| `SPLIT_NONE/CALL1/CALL2` | JackpotModule `:197/:199/:201` | `grep -n "SPLIT_NONE\|SPLIT_CALL1\|SPLIT_CALL2" JackpotModule.sol` → `197/199/201` | MATCH |
| `JACKPOT_MAX_WINNERS = 160` | JackpotModule `:219` | `grep -n "JACKPOT_MAX_WINNERS" JackpotModule.sol` → `219: uint16 private constant JACKPOT_MAX_WINNERS = 160;` | MATCH |
| `resumeEthPool` jackpot resume-check | `:349` (SPEC notes DRIFT: req `:348` = comment, live `:349` = if) | `grep -n "resumeEthPool" JackpotModule.sol` → `349: if (resumeEthPool != 0) {` | MATCH (DRIFT correctly recorded) |
| `_resumeDailyEth` | JackpotModule `:1186` | `grep -n "_resumeDailyEth" JackpotModule.sol` → `1186: function _resumeDailyEth(...)` | MATCH |
| `resumeEthPool` storage | `storage/DegenerusGameStorage.sol:994` | `grep -n "resumeEthPool" DegenerusGameStorage.sol` → `994: uint128 internal resumeEthPool;` | MATCH |
| `_ethToBurnieValue` | `DegenerusGameMintModule.sol:1412` | `grep -n "_ethToBurnieValue" DegenerusGameMintModule.sol` → first decl at `1412: function _ethToBurnieValue(` | MATCH |
| `priceForLevel` | `PriceLookupLib.sol:21` | `grep -n "priceForLevel" PriceLookupLib.sol` → `21: function priceForLevel(uint24 targetLevel) internal pure returns (uint256)` | MATCH |
| `HAS_DEITY_PASS_SHIFT = 184` | `BitPackingLib.sol:71` | `grep -n "HAS_DEITY_PASS_SHIFT" BitPackingLib.sol` → `71: uint256 internal constant HAS_DEITY_PASS_SHIFT = 184;` | MATCH |
| Keeper coupling at `:671` (subscribe gate) | `hasAnyLazyPass(player)` at keeper `:671` | `grep -n "hasAnyLazyPass(" StreakKeeperV2.sol` → `671: if (!IGame(...).hasAnyLazyPass(msg.sender)) {` | MATCH |
| Keeper coupling at `:974` (renewal gate) | `hasAnyLazyPass(player)` at keeper `:974` | `grep -n "hasAnyLazyPass(" StreakKeeperV2.sol` → `974: if (IGame(...).hasAnyLazyPass(player)) {` | MATCH |
| Keeper zero RM symbols | 0 matches across full RM-deletion symbol set | `grep -n "syncAfKingLazyPassFromCoin\|...[all RM symbols]..." StreakKeeperV2.sol` → 0 lines | VERIFIED |

**All spot-checked citations MATCH. The two recorded cosmetic +1 DRIFTs (jackpot resume-check :348→349, advance resume-check :452-455→453-456) are correctly documented in the SPEC as cosmetic doc-vs-if offsets, not symbol drifts.**

---

## JGAS-01 Ordering Verification

The SPEC is required to honor the ordering: design-intent BEFORE worst-case-first gas BEFORE locked decision.

| Section | SPEC line number | Order |
|---------|-----------------|-------|
| `### (1) Design intent of the two-call split — traced BEFORE locking the deletion` | 345 | 1st |
| `### (2) Theoretical worst-case single-call gas — derived FIRST, before any reliance` | 357 | 2nd |
| `### (3) The decision gate — resolved and LOCKED` | 368 | 3rd |
| `### (4) Deletion footprint — enumerated and grep-verified across BOTH modules` | 377 | 4th |
| `### (5) VRF / freeze-invariant SAFE verdict — STATED, not assumed` | 405 | 5th |

JGAS-01 ordering: design-intent (345) < gas (357) < decision (368) < footprint (377) < verdict (405). **HONORED.**

---

## SUB-09 Whale-Pass-Expiry USER-RATIFIED Check

The SPEC must record the whale-pass-expiry decision as a USER-RATIFIED choice (permanent-deity), not a defaulted fact.

The SPEC at line 491 reads: "Whale-pass-expiry free-renew — Task-2 USER-RATIFIED DECISION (recorded VERBATIM)" with the explicit heading "USER-SELECTED OPTION: `permanent-deity` (Permanent Deity bit), with NO additional caveats." The REQUIREMENTS.md traceability table at line 54 records: "post-expiry renewal funding USER-RATIFIED = `permanent-deity`". **USER-RATIFIED label confirmed.**

---

## Zero Source-Mutation Invariant

```
git diff --name-only 62fb514bfcc8ad042a45cef960e5ff0ff6fbb801 HEAD -- contracts/ test/
```

**Result: empty output.** Zero `contracts/` and zero `test/` mutations since the v45.0 milestone baseline. **VERIFIED.**

---

## Requirement Design Coverage (42/42)

The SPEC's `## Requirement Design Coverage` table maps all 42 v46.0 requirement IDs to their SPEC section and primary verification owner phase, with the explicit statement "Coverage: 42/42 mapped, 0 unmapped, 0 duplicated."

The four SPEC-primary-owned requirements are marked Complete in `REQUIREMENTS.md` Traceability:

| Req | REQUIREMENTS.md status |
|-----|------------------------|
| PROTO-01 | `Complete` (line 118) |
| SUB-09 | `Complete (316-03 — design locked; permanent-deity free-renew ratified)` (line 119) |
| RM-04 | `Complete` (line 120) |
| JGAS-01 | `Complete` (line 121) |

**All four SPEC-owned primaries marked Complete.**

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----| ----|--------|---------|
| SPEC PROTO-01 design | `DegenerusGame.sol:1610` `_hasAnyLazyPass` | reader-set 3-match grep | VERIFIED | Decl :1610 + readers :1580/:1660 all confirmed at HEAD |
| SPEC PROTO-05 pattern | `ContractAddresses.sol:37/:47` | VAULT/SDGNRS precedent | VERIFIED | Lines :37/:47 confirmed; AF_KING addition is IMPL obligation |
| SPEC JGAS-01 VRF verdict | `DegenerusGameAdvanceModule.sol:467` `_unlockRng` | "not in resume branch" | VERIFIED | Resume branch :453-456 has no `_unlockRng`; `_unlockRng` at :467 confirmed |
| SPEC SUB-09 free-renew | `DegenerusGame.sol:222/:223` constructor Deity grant | `mintPacked_[SDGNRS/VAULT]` already set | VERIFIED | Grep confirms lines :222/:223 exactly as cited |
| Keeper dependency | RM-deletion symbol set | zero-match grep | VERIFIED | 0 RM symbols in StreakKeeperV2.sol; only `hasAnyLazyPass` at :671/:974 |

---

## Anti-Patterns Found

No source `.sol` or test files were modified by this phase. The deliverable is a markdown planning document only. No anti-pattern scan of source is applicable (zero-mutation phase by design).

Scanned `316-SPEC.md` for any unverified "by construction" claims:

- The SPEC contains only TWO occurrences of "by construction" — both inside the Call-Graph Attestation's explicit negation sentence: "the SPEC asserts no unverified 'by construction' / 'single fn reaches all paths' claim — the only such phrasing in this document is inside this explicit negation sentence." **No unverified by-construction claims.**
- No TBD/FIXME/XXX/TODO debt markers found in the SPEC that are unreferenced.

**No blockers. No warnings.**

---

## Human Verification Required

None. This is a SPEC/design-lock phase — the deliverable is a markdown document. All verifiable claims are programmatically confirmed via grep against HEAD source. No UI, real-time, or external service behavior to test.

---

## Gaps Summary

No gaps. All 5 success criteria are verified with direct source evidence. The phase goal — locking the FULL v46.0 design before any contract change, with every citation grep-verified — is achieved.

---

_Verified: 2026-05-23_
_Verifier: Claude (gsd-verifier)_
