---
phase: 482-degenerette-dead-mode-repack-gated-contract-diff-4
plan: 01
subsystem: degenerette-packed-bet
tags: [degenerette, packed-bet, dead-mode-strip, repack, FT-to-DEGEN, behavior-preserving, gated-diff, fix-05]

# Dependency graph
requires:
  - phase: 480-01 (bcc47ccc) — degenerette identifier rename (amountPerSpin/spinCount/customTraits/_degenerettePayout)
  - phase: 481-01 (046dd24b) — Degenerette event renames (DegeneretteResolved/DegeneretteResult)
provides:
  - "Degenerette packed bet stripped of the dead Full-Ticket-mode bits (mode/isRandom/hasCustom + dead hero reserved bit) and repacked into one contiguous 220-bit encoding; FT_*_SHIFT → DEGEN_*_SHIFT (new values); _packFullTicketBet → _packDegeneretteBet"
  - "Encoding-only change proven behavior-identical: degenerette EV/resolution distribution byte-identical to pre-482 (65/65 EV numeric lines unchanged); no storage slot move (degeneretteBets stays slot 38)"
affects: [484-verify-close]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dead-bit strip is safe iff the dead bits are write-only AND a different always-set field preserves the packed==0 sentinel. Here spinCount (validated >=1) at DEGEN_COUNT_SHIFT guarantees a live bet is non-zero, replacing the old mode[0]=1 sentinel guarantee."
    - "FIX-05 byte-baseline normalization extended for an encoding change: the Storage byte-identity guard folds the audited 482 layout-comment block (old→new) into the HEAD baseline before cmp; still detects any OTHER drift."

key-files:
  created:
    - .planning/phases/482-degenerette-dead-mode-repack-gated-contract-diff-4/482-01-PLAN.md
    - .planning/phases/482-degenerette-dead-mode-repack-gated-contract-diff-4/482-01-SUMMARY.md
  modified:
    - "contracts/modules/DegenerusGameDegeneretteModule.sol (UNCOMMITTED — gated diff #4; the repack: layout doc, FT_*→DEGEN_* consts, _packDegeneretteBet body, unpack)"
    - "contracts/storage/DegenerusGameStorage.sol (UNCOMMITTED — degeneretteBets layout comment rewrite)"
    - "contracts/DegenerusGame.sol (UNCOMMITTED — degeneretteResolve currency decode >> 42 → >> 40)"
    - test/gas/KeeperResolveBetWorstCaseGas.t.sol
    - test/fuzz/DegeneretteV73SolvencyFuzz.t.sol
    - test/fuzz/DegeneretteHeroScore.t.sol
    - test/mutation/DegeneretteV73MutationKills.t.sol
    - test/unit/LootboxAutoResolveMintBoostRegression.test.js

key-decisions:
  - "Dead hero `reserved` bit (bit[237], always-set, never read) ALSO stripped — heroQuadrant now packs as a plain 2-bit field at DEGEN_HERO_SHIFT (was reserved[0]+quadrant[1..2] at FT_HERO_SHIFT). §2C asked to verify this; maximal-packing → drop it."
  - "index field stays 32-bit (DEGEN_INDEX_SHIFT, MASK_32) — matches the existing pack/unpack behavior exactly (uint32(index) packed, MASK_32 read); the old 48-bit doc reservation collapses to the actual 32-bit field. NOT widened (would change behavior if index ever exceeded 32 bits)."
  - "Cross-file consumer DegenerusGame.degeneretteResolve decodes currency by hardcoded shift (was >> 42) — updated to >> 40 in lockstep. A live reward-gate read; missing it would have mis-gated the resolver consolation flip."

requirements-completed: [DEGEN-REPACK-01]

# Metrics
duration: ~2h
completed: 2026-06-30
---

# Phase 482 / Plan 01: Degenerette Dead-Mode Repack Summary

**The dead fractional "Full Ticket" mode was stripped from the Degenerette packed bet — the
write-only `mode`/`isRandom`/`hasCustom` bits (and the dead hero `reserved` bit) removed, the seven
live fields repacked into one contiguous 220-bit encoding, `FT_*_SHIFT` → `DEGEN_*_SHIFT` (new shift
values), `_packFullTicketBet` → `_packDegeneretteBet` — proven a pure ENCODING change: the
degenerette EV/resolution distribution is byte-identical to pre-482 (65/65 EV numeric lines unchanged)
and no storage slot moved (`degeneretteBets` stays slot 38, layout golden byte-identical).**

## HARD GATE — Dead-mode proof (verdict: PROVABLY DEAD → strip safe)

The packed bet is WRITTEN at exactly one site (`_packDegeneretteBet` ← `_placeDegeneretteBetCore`).
Every reader was traced:
- `_resolveBet` — the full decode (customTraits, spinCount, currency, amountPerSpin, index,
  activityScore, heroQuadrant) → resolution/score/payout/EV.
- `DegenerusGame.degeneretteResolve` — `betPacked >> 42 & 0x3` (currency, reward-gate) + `== 0` sentinel.
- `DegenerusGame.getDegeneretteBet` — raw getter (off-chain decode only).

Bits NEVER read behaviorally — each proven write-only:
| bit | name | proof |
|---|---|---|
| [0] | `MODE_FULL_TICKET` | written always-1; no reader masks bit 0. The only mode (one bet path). |
| [1] | `isRandom` | never written (always 0) and never read — a pure comment relic. |
| [236] | `hasCustom` | written always-1; no reader masks bit 236. |
| [237] | hero `reserved` | written always-1; unpack reads `>> (FT_HERO_SHIFT + 1)`, skipping it. |

**Sentinel-safety invariant preserved (Rule 2 correctness):** `packed == 0` = "no/resolved bet"
(Game:1501, Degenerette:709; `delete` sets 0). Historically guaranteed non-zero by `mode`[0]=1. After
the strip, non-zero is guaranteed independently by `spinCount` (validated `≥ 1` — `spinCount == 0`
reverts `InvalidBet`) occupying `DEGEN_COUNT_SHIFT = 32`. A live bet stays non-zero. PRESERVED + documented in the pack NatSpec.

No bit being stripped is live → strip is safe. (Had any been live → STOP+FLAG, no strip. It was not.)

## New bit layout (encoding-only; values change, decoded VALUES identical)

| field          | bits      | width | NEW const             | NEW | OLD const            | OLD |
|----------------|-----------|-------|-----------------------|-----|----------------------|-----|
| customTraits   | [0..31]   | 32    | DEGEN_TRAITS_SHIFT    | 0   | FT_TICKET_SHIFT      | 2   |
| spinCount      | [32..39]  | 8     | DEGEN_COUNT_SHIFT     | 32  | FT_COUNT_SHIFT       | 34  |
| currency       | [40..41]  | 2     | DEGEN_CURRENCY_SHIFT  | 40  | FT_CURRENCY_SHIFT    | 42  |
| amountPerSpin  | [42..169] | 128   | DEGEN_AMOUNT_SHIFT    | 42  | FT_AMOUNT_SHIFT      | 44  |
| index          | [170..201]| 32    | DEGEN_INDEX_SHIFT     | 170 | FT_INDEX_SHIFT       | 172 |
| activityScore  | [202..217]| 16    | DEGEN_ACTIVITY_SHIFT  | 202 | FT_ACTIVITY_SHIFT    | 220 |
| heroQuadrant   | [218..219]| 2     | DEGEN_HERO_SHIFT      | 218 | FT_HERO_SHIFT (+1)   | 237 |

Removed: `MODE_FULL_TICKET`, `isRandom` (comment), `FT_HAS_CUSTOM_SHIFT`, hero `reserved`. 220 bits used
(was 240; 4 scattered dead bits removed + 20 freed high bits). Field WIDTHS preserved exactly → every
decoded field VALUE round-trips identically, so resolution/score/payout/EV are unchanged by construction.

## Edits applied

- `DegenerusGameDegeneretteModule.sol`: layout doc block rewritten; `MODE_FULL_TICKET` + `FT_HAS_CUSTOM_SHIFT`
  removed; `FT_*_SHIFT` → `DEGEN_*_SHIFT` (new values); `_packFullTicketBet` → `_packDegeneretteBet` + body
  repacked (no mode/hasCustom/reserved bits; hero packs direct); `_resolveBet` unpack uses new consts +
  `heroQuadrant = (packed >> DEGEN_HERO_SHIFT) & MASK_2` (no `+1`); dead-mode comments reworded
  (BetPlaced "either mode", "(no random)", "Full Ticket bets", pack `isRandom=false/hasCustom=true`).
- `DegenerusGameStorage.sol`: `degeneretteBets` packed-layout doc rewritten (mode/isRandom/hasCustom lines
  gone; new offsets; "spinCount" not "ticketCount"; index uint32).
- `DegenerusGame.sol`: `degeneretteResolve` currency decode `betPacked >> 42` → `>> 40` + comment.
- Test shift-decoders (FIX-05 class, intentional break → new shifts): `KeeperResolveBetWorstCaseGas.t.sol`
  `>> 34` → `>> 32`; the three fuzz/mutation files `FT_ACTIVITY_SHIFT = 220` → `DEGEN_ACTIVITY_SHIFT = 202`.

## Verification (BEHAVIOR_PRESERVATION gate)

| Gate | Result |
|------|--------|
| `npx hardhat compile` | exit 0 |
| `forge build` | exit 0 (harnesses compile with the renamed test consts) |
| Degenerette EV/resolution stat suites (PerNEvExactness, V73Invariants, ProducerChi2, BonusEv, SoloEvUplift) | 50 passing / 1 pending — **byte-identical to the pre-482 baseline (65/65 EV numeric lines diff-clean)** |
| `npm test` (full Hardhat — runtime byte gate) | **1362 passing, 0 failing, 19 pending** ✅ (== 481 floor) |
| Storage-layout oracle — DegenerusGameDegeneretteModule | `degeneretteBets` slot 38 byte-identical to golden — **no slot move (intended-repack-only)** |
| Storage-layout oracle — DegenerusGame / Storage shared-slot consistency | OK (unchanged) |

**EV byte-identity (the core proof):** baseline (pre-482, on 481 source) vs post-482 EV outputs diff to
zero across all 65 EV-bearing lines — `basePayoutEV` per-(N,heroIsGold) (99.99xx centi-x), EVEQ drifts,
R2 rigged EV, P(S=9) jackpot pins, INV-01..04 (ROI curve / WWXRP RTP / S=9 pins / whale-pass bracket all
unchanged vs HEAD), and the STAT-02 chi² contributions. The repack disturbed nothing player-visible.

**Targeted forge degenerette suites (HeroScore, V73MutationKills, V73SolvencyFuzz, FreezeResolution,
ResolveRepeg, KeeperResolveBetWorstCaseGas):** all fail at `setUp()` with `panic 0x11` at `gas: 0` — the
documented carried foundry-1.6.0-nightly genesis-underflow flake (same Degenerette* suites the 481 summary
flagged). The panic is in deploy/genesis, BEFORE any test body runs, so the repacked resolution path is
never reached — provably not a 482 regression. The Hardhat EV/resolution suite (which DOES place→resolve→
payout through the new pack/unpack) is the authoritative oracle and is byte-identical.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — FIX-05 source-baseline guard] Storage byte-identity guard pinned the pre-482 layout comment**
- **Found during:** `npm test` (the catching signal). 1 failing: `LootboxAutoResolveMintBoostRegression [03b]`
  ("Storage.sol drifted from committed HEAD beyond the audited Phase-481 ABI rename").
- **Root cause:** the guard cmps `DegenerusGameStorage.sol` vs committed HEAD, normalizing only the audited
  480/481 renames into the baseline. The 482 `degeneretteBets` layout-comment rewrite is a new audited drift.
- **Fix:** extended the `[03b]` normalization to fold the audited 482 layout-comment block (old 10-line
  mode/isRandom/hasCustom block → new 7-line repacked block) into the HEAD baseline before cmp (the 480/481
  `normalize*Rename` precedent). The guard STILL detects any OTHER Storage drift; post-commit-safe (the
  normalization becomes a no-op once HEAD includes 482).
- **Files modified:** `test/unit/LootboxAutoResolveMintBoostRegression.test.js`
- **Verify:** `[03a]` + `[03b]` → green; 9 passing in the file; full `npm test` back to the 1362 floor.

**2. [Rule 3 — regen artifact] ContractAddresses.sol restored to HEAD**
- `npx hardhat compile` regenerated `contracts/ContractAddresses.sol` (62-line address churn, unrelated to
  the repack). Restored to HEAD via `git checkout -- contracts/ContractAddresses.sol` so the gated 482 patch
  stays clean (the 481 precedent — ContractAddresses is the compile-regen exempt file).

### Out-of-scope (logged, NOT fixed — SCOPE BOUNDARY)

- The storage-layout oracle flagged `WrappedWrappedXRP` as "CHANGED" — a contract NOT touched by 482 (not in
  the working-tree git status). Root cause: `forge inspect WrappedWrappedXRP` errors "No contract found" — the
  oracle's CONTRACTS list (`storage_layout_oracle.sh:29`) + golden filename reference `WrappedWrappedXRP`, but
  the contract was renamed to `WWXRP` (`contracts/WWXRP.sol`, `contract WWXRP {`). The golden was captured
  under the old name; the oracle entry has been stale since the rename — a PRE-EXISTING oracle-infra mismatch
  that predates 480/481/482 (WWXRP.sol is unmodified). Unrelated to the repack. The Degenerette module + Game +
  Storage layouts (the only files 482 touches) are all byte-identical to golden + shared-slot-consistent.
  Logged to `deferred-items.md` (D-482-ORACLE-01); NOT fixed (SCOPE BOUNDARY — not caused by 482).

### Auth gates
None.

## Threat Flags
None — no new network endpoint, auth path, file access, or trust-boundary schema change. The repack is an
internal storage-encoding change to an existing mapping; the external `placeDegeneretteBet` selector +
signature are unchanged (only the emitted `BetPlaced.packed` value and the `getDegeneretteBet` return
re-encode, which are expected new goldens, not new surface).

## Gated-diff handoff
- **contracts/ left UNCOMMITTED** (3 files carry 482 changes on top of 481: DegenerusGameDegeneretteModule.sol,
  DegenerusGameStorage.sol, DegenerusGame.sol — 482 added NO new files, it deepened the diff in 3 existing-481
  files). The orchestrator captures the incremental 482 patch from snapshots.
- `ContractAddresses.sol` restored to HEAD. Commit-guard + `.git/hooks/pre-commit` untouched; STATE.md /
  ROADMAP.md untouched.
- test/ + plan/summary committed (5 test files, 0 contracts, 0 deletions).
