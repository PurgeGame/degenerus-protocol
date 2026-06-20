---
phase: 445-spec-design-lock-the-implementation-contract
verified: 2026-06-19T22:00:00Z
status: passed
score: 5/5
overrides_applied: 0
---

# Phase 445: SPEC — Design-Lock the Implementation Contract
# Verification Report

**Phase Goal:** Every implementation decision the FINAL-SPEC leaves to engineering is locked into a build-ready contract SPEC so IMPL (446) is mechanical. No `contracts/*.sol` edited (paper-only).
**Verified:** 2026-06-19
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Paper-Only / Contract-Freeze Attestation

`git diff --quiet ffbd7796 HEAD -- contracts/` — **CLEAN** (zero output, exit 0).

The v70 contracts tree `99f2e53f` @ `ffbd7796` is unchanged through HEAD. Every commit in the phase history (`ffeafce8`..`a2ffd137`) carries the `docs(445*)` prefix; `a43a56df` (the PIN-1 resolution commit) touched only `.planning/phases/445-*/*.md`. No `contracts/*.sol` file was modified. **PAPER-ONLY constraint: VERIFIED.**

Baseline anchor cross-check (four corrected anchors verified against actual contract files on disk):

| Anchor | SPEC claim | Actual file | Match? |
|--------|-----------|-------------|--------|
| `boxPlayers` append point | `DegenerusGameStorage.sol:2393`, closing `}` at `:2394` | `:2393` `mapping(uint48 => address[]) internal boxPlayers;` — file is 2394 lines | EXACT |
| `whalePassClaims` already exists | `:1122` `mapping(address => uint256)` | `:1122` confirmed in storage contract | EXACT |
| `TICKET_SCALE = 100` | `:157, :663` | `:157` confirmed; `:663` quantityScaled division confirmed | EXACT |
| `uint24 public level = 0` | `:236` | `:236` confirmed | EXACT |
| `rngWordByDay` | `:462` `mapping(uint24 => uint256)` | `:462` confirmed | EXACT |
| ETH-cap clone source | `DegenerusGameDegeneretteModule.sol:877-915` (`maxEth` `:889`, lootbox-resolve `:915`) | `:889` `maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;` confirmed; `:915` `_resolveLootboxDirect` function start confirmed | EXACT |

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Storage + entrypoints locked (foilRecord packing, foilMatchClaimed, buyFoilPack/claimFoilMatch signatures, append-only, no slot collision, both PINs RESOLVED) | VERIFIED | See SC-1 below |
| 2 | Economics coefficient-exact (5 curve constants, /15360 PMF ladder, 40/40/20 table, 1.9376 calibration) | VERIFIED | See SC-2 below |
| 3 | Match predicate unambiguous (exact positional 6-bit, 2/3 vs LIVE, 4-of-4 vs HERO-FREE, pull/claim, double-claim guard) | VERIFIED | See SC-3 below |
| 4 | Placement fits (new GAME_FOILPACK_MODULE, EIP-170 estimate, v70-frozen producers confirmed untouched) | VERIFIED | See SC-4 below |
| 5 | §6 hard-floor (8 items) mapped to SPEC sections + attest phases; corrected anchors present; no fenced Solidity bodies | VERIFIED | See SC-5 below |

**Score: 5/5 truths verified**

---

## Per-Success-Criterion Verdicts

### SC-1 — Storage + Entrypoints Locked

**Result: MET**

**foilRecord packing — PIN 2 (bit layout):**
`445-SPEC.md §D.1.1` table: `sig0..sig3` at `[0-127]` (4×32-bit), `multBps` at `[128-143]` (16-bit), `rawLevel` stamp at `[144-167]` (24-bit), `[168-255]` reserved `0`. Constants: `_FOIL_STAMP_SHIFT = 144`, `_FOIL_MULT_SHIFT = 128`. Total 168 bits, one slot. PIN 2 explicitly stated **ACCEPTED** by USER sign-off 2026-06-19 in §D.6 and §T Decision 2.

**foilRecord level-keying — PIN 1:**
`445-SPEC.md §D.1` and §D.6: `mapping(uint24 => mapping(address => uint256)) internal foilRecord` — the level=>player surviving-record form. USER sign-off 2026-06-19 confirmed in both §D.6 PIN 1 and §T Decision 1. The single-slot form is documented as the *rejected* alternative. The commit `a43a56df` reconciled all three SPEC files coherently.

**foilMatchClaimed marker:**
`445-SPEC.md §D.3`: `mapping(bytes32 => bool) internal foilMatchClaimed` (unified name — V3 DEFECT E-γ resolved; `foilClaimed` name explicitly rejected). Key = `keccak256(abi.encode(player, uint256(level), uint256(day), uint256(drawKind), uint256(ticketIndex)))` — five distinct positional fields, no concatenation ambiguity.

**buyFoilPack signature:**
`445-SPEC.md §E.1`: `function buyFoilPack() external payable` — no parameters, pinned.

**claimFoilMatch signature:**
`445-SPEC.md §E.2`: `function claimFoilMatch(uint256 day, uint256 ticketIndex, uint8 drawKind) external` — pinned.

**Slot collision / append-only (SEC-03/SEC-04):**
`445-SPEC.md §D.5`: both new mappings append after `boxPlayers` (`:2393`), before `:2394`. Two new DECLARED base mapping slots (`foilRecord` + `foilMatchClaimed`); a nested mapping occupies exactly one declared slot. No existing slot moved/retyped/reordered. `whalePassClaims` at `:1122` — NOT re-declared. Storage lives only in `DegenerusGameStorage` (SEC-03). Verified against actual contract file (`:2393` = `boxPlayers`, file ends at `:2394`).

---

### SC-2 — Economics Coefficient-Exact

**Result: MET**

**foilBoostBps(score) — 5 constants (`445-SPEC.md §A.2.1`):**

| constant | value |
|----------|-------|
| `FOIL_MIN_BPS` | `20_000` |
| `FOIL_K_POINTS` | `300` |
| `FOIL_VA_BPS` | `50_000` |
| `FOIL_VB_BPS` | `55_000` |
| `FOIL_MAX_BPS` | `60_000` |

All five present in `445-SPEC.md:170-174`. Segment closed forms (`§A.2.2`): seg A `20000 + 100·score`, seg B `50000 + 25·(score-300)`, seg C `55000 + (score-500)·5000/29500`, floor/cap guards. Reuses shared knees `ACTIVITY_SEG_B_KNEE_POINTS = 500` and `ACTIVITY_EFFECTIVE_CAP_POINTS = 30_000` (RARE-02 / D-02 confirmed).

**Sibling-producer /15360 PMF ladder (`§A.1.4`):**
`width15360[c] = base[c]·60 · (50000 + (multBps − 10000)·w5[c]) / 50000`; remainder redistributed to three commons (color-0 absorbs `rem mod 3`). Gold exactly `120·M`. V1 exhaustive verification cited (0 mismatches over 40,001-point grid). Per-tier table at `§A.1.6` with four M columns. `p_gold = (2/256)·M` invariant confirmed.

**40/40/20 payout split (`§E.5 C`):**
`uint256 c = currencyLane % 100; c < 40` FLIP; `c < 80` ETH; else WWXRP. All tiers. `FOIL_TO_FUTURE_BPS = 2500` for the 75/25 pool split (`§E.1 step 4`, confirmed distinct from `PURCHASE_TO_FUTURE_BPS = 1000`).

**Calibration (`§E.7`):**
`E[faces/pack/30d] = 240 × 0.0080736 = 1.9376` — exact closed-form (q = 1/64 constant, M-invariant). D-05 policy: 3.1% low, no recalibration flag, table LOCKED. Per-quadrant match `q = 1/64` invariance proven (boost cancels in match channel since winning set is flat uniform 1/8).

---

### SC-3 — Match Predicate Unambiguous

**Result: MET**

**Exact positional quadrant match (`§E.2 step 6`):**
"Quadrant q matches iff `foilQuad_q == winQuad_q` as the full 6-bit `[CCC][SSS]`" — color AND symbol. Color-only explicitly excluded. Wrong-quadrant explicitly excluded. Both sides carry `[QQ]`.

**2/3 vs LIVE, 4-of-4 vs HERO-FREE (`§E.3`, `445-SPEC.md:568-578`):**

| Tier | Condition | Channel |
|------|-----------|---------|
| 2-of-4 | `liveCount == 2` | LIVE |
| 3-of-4 | `liveCount == 3` | LIVE |
| 4-of-4 | `heroFreeCount == 4` ONLY | HERO-FREE pure-VRF |

Steer-proof: a steered hero shifts at most one quadrant's symbol on LIVE, reaching at most 3-of-4 LIVE and never `heroFreeCount == 4`. Edge case documented: `liveCount == 4` but `heroFreeCount == 3` pays 3-of-4 (not 4-of-4).

**Pull/claim, double-claim guard, CEI (`§D.3.2`):**
`foilMatchClaimed[mk]` checked and set BEFORE any payout. Reentrant re-call sees set marker, reverts. `§E.2 step 4` documents the order explicitly.

**Re-derivation from `rngWordByDay[day]` (`§E.2 step 3`, `§E.3`):**
`rw = rngWordByDay[uint24(day)]` — retained storage, re-derived at claim, never live-read. `dailyHeroWagers[day-1]` anchor corrected and pinned.

---

### SC-4 — Placement Fits

**Result: MET**

**New GAME_FOILPACK_MODULE (`§F.1`):**
New module recommended (not any existing module). MintModule excluded (SEC-03 + near-full at ~1,116 B free). Estimated body ≈8–11 KB; headroom ≈13.5–16.5 KB vs 24,576 B EIP-170 limit. Facade ≈0.5–0.9 KB against 4,188 B free. Re-measure-at-IMPL caveat documented as HARD-REQ §6.7 (attest phase 446/449). D-04 correctly classified as an engineering call.

**v70-frozen shared producers confirmed untouched (RARE-01):**
`§A.1.1` explicitly: `weightedColorBucket`, `traitFromWord`, `packedTraitsFromSeed` at `DegenerusTraitUtils.sol:115, :143, :169` — NOT edited, retyped, or moved. Foil path is purely additive (new sibling `traitFromWordFoil` / `packedTraitsFoil`, cloned structurally from `packedTraitsDegenerette`).

---

### SC-5 — §6 Hard-Floor Map, Corrected Anchors, No Fenced Solidity

**Result: MET**

**§6 hard-floor map (`445-SPEC.md §H`):**
All 8 items present with SPEC section pointers and attest phases:

| # | Floor item | Locking section | Attest |
|---|-----------|----------------|--------|
| 6.1 | No exploit / steer-proof 4-of-4 | §E.3 | 448 |
| 6.2 | No solvency hole | §E.5 (C) + SEC-02 | 448 |
| 6.3 | Isolated match payout table | §E.5 (A) | 447/448 |
| 6.4 | Frozen shared producers | §A.1.1 (RARE-01) | 448 |
| 6.5 | Buy-time freeze + claim re-derive | §A.2.4 + §E.1 steps 5-6 + §E.2 step 3 | 448 |
| 6.6 | Pull/claim only; advanceGame flat | §D.3.2 + §E.2 | 447/448 |
| 6.7 | EIP-170 fits (re-measure) | §F | 446/449 |
| 6.8 | Full forge suite green; layout goldens | §D.5 + test/re-audit phases | 447/448/449 |

**Corrected anchors (`445-SPEC.md §1`):**
All 4 present in the §1 table with wrong/corrected columns and carry-into-446 directives: (1) `400` not `4` for `_queueTicketsScaled`; (2) `whalePassClaims:1122` already exists; (3) ETH-cap clone source `:877-915` not `:402-446`; (4) `foilMatchClaimed` not `foilClaimed`. All four independently verified against actual contract files.

**No fenced Solidity bodies:**
`grep -n "^\`\`\`sol\|^\`\`\`solidity"` on all three SPEC files — zero matches. Convention honored: all identifiers described in directive prose, not function bodies.

---

## REQ-Coverage Confirmation (20 REQ-IDs)

All 20 phase-445 REQ-IDs are present in `445-SPEC.md` with at minimum one occurrence each:

| REQ-ID | Occurrences in 445-SPEC.md | Status |
|--------|---------------------------|--------|
| FOIL-01 | 8 | PRESENT |
| FOIL-02 | 5 | PRESENT |
| FOIL-03 | 6 | PRESENT |
| FOIL-04 | 4 | PRESENT |
| FOIL-05 | 7 | PRESENT |
| RARE-01 | 10 | PRESENT |
| RARE-02 | 5 | PRESENT |
| RARE-03 | 9 | PRESENT |
| RARE-04 | 4 | PRESENT |
| MATCH-01 | 8 | PRESENT |
| MATCH-02 | 6 | PRESENT |
| MATCH-03 | 6 | PRESENT |
| MATCH-04 | 5 | PRESENT |
| MATCH-05 | 6 | PRESENT |
| MATCH-06 | 4 | PRESENT |
| MATCH-07 | 4 | PRESENT |
| MATCH-08 | 5 | PRESENT |
| MATCH-09 | 6 | PRESENT |
| MATCH-10 | 5 | PRESENT (design basis locked §E.7; empirical proof deferred to 447 TST) |
| SEC-03 | 13 | PRESENT |

SEC-01, SEC-02, SEC-04 are not in the 20-REQ phase-445 set; their design bases are locked here (`§E.3`, `§E.5`, `§D.5`) and explicitly deferred to phase 448 REAUDIT — this is the correct and documented pattern. REQUIREMENTS.md §phase-assignment table confirms this split.

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `445-SPEC.md` | Canonical consolidated design-lock SPEC | PRESENT, SUBSTANTIVE | 827 lines; all §A/§D/§E/§R/§H/§S/§T sections populated; self-contained for an IMPL-446 author |
| `445-SPEC-A-economics.md` | Economics section source | PRESENT | Folded into §A of canonical SPEC |
| `445-SPEC-D-storage.md` | Storage section source | PRESENT, 279 lines | Reconciled to PIN 1 level=>player keying at `a43a56df` |
| `445-SPEC-E-entrypoints.md` | Entrypoints section source | PRESENT, 413 lines | Reconciled at `a43a56df` |
| `445-RESEARCH.md` | Adversarially verified coefficients | PRESENT | On disk; cited as authoritative input |
| `445-04-SUMMARY.md` | Wave-2 plan summary with USER sign-off | PRESENT | Records PIN 1/PIN 2 decisions and reconciliation applied |

---

## Anti-Patterns Found

`grep` for `TBD`, `FIXME`, `XXX`, `TODO`, `PLACEHOLDER` across `445-SPEC.md`, `445-SPEC-D-storage.md`, `445-SPEC-E-entrypoints.md` — **zero matches**. No debt markers, no placeholder bodies, no stubs.

No fenced Solidity in any SPEC file (zero `\`\`\`sol` or `\`\`\`solidity` blocks).

---

## Behavioral Spot-Checks

SKIPPED — paper-only SPEC phase; no runnable entry points produced or expected.

---

## Probe Execution

SKIPPED — no probes defined or expected for a paper-only SPEC phase.

---

## Human Verification Required

None. This phase is a design-lock SPEC with clear, verifiable claims:
- Numeric values (5 constants, PMF ladder, calibration) are closed-form and grep-confirmable.
- Bit layout is machine-readable (specific field names and widths).
- Contract anchor lines verified against actual files on disk.
- Paper-only constraint verified by `git diff`.

There are no UI flows, real-time behaviors, or external service integrations to human-verify.

---

## Notes (non-blocking)

1. **MATCH-10 empirical proof deferred to 447 TST** — the closed-form calibration (1.9376) is present and correct in §E.7, but the REQUIREMENTS.md and REQ-coverage map correctly flag MATCH-10 attestation as phase 447. This is by design and documented. Not a gap.

2. **SEC-01, SEC-02, SEC-04 design bases locked but not attested** — their design rationale is present and correct in §E.3, §E.5, §D.5 respectively. Attestation is downstream at phase 448 per the audit-milestone pattern. Not a gap.

3. **EIP-170 estimate is provisional** — §F.4 explicitly documents this as a HARD-REQ caveat requiring re-measurement at phase 446/449. The SPEC correctly does not assert a final headroom figure, only an engineering estimate. Not a gap.

4. **T-445-D3 disposition upgraded from `accept` to `mitigate`** — the level=>player keying (PIN 1) eliminated the single-slot self-overwrite loss edge structurally. The threat model correctly reflects this.

---

## Gaps Summary

None. All five success criteria are met. All 20 REQ-IDs are present with substantive coverage. The paper-only constraint is verified by `git diff`. The two USER pins are RESOLVED and recorded. The four corrected anchors are verified against actual contract files. No fenced Solidity bodies, no debt markers.

---

_Verified: 2026-06-19T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
