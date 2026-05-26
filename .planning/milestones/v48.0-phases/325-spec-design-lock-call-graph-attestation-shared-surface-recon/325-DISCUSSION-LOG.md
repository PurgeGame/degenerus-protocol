# Phase 325: SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-25
**Phase:** 325-spec-design-lock-call-graph-attestation-shared-surface-recon
**Areas discussed:** Hero payout shape (HERO-04), Pool re-stranding (POOL-06)

---

## Gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Hero payout shape (HERO-04) | EV-budget shape over S∈{0..9}; bonus thresholds on the new scale | ✓ |
| Salvage-swap margin (SWAP-08) | Accept ~4.5pp ceiling no-arb margin vs tighten fractionBps | (skipped → lean) |
| Redemption acct shape (RFALL-04) | Single pendingRedemptionEthValue vs split ETH/stETH tracking | (skipped → lean) |
| Pool re-stranding (POOL-06) | Second sweep at +30d vs accept-as-minor | ✓ |

**User's choice:** Hero payout shape + Pool re-stranding. The two skipped items were locked to
their plan-doc leans (SWAP-08 → accept the margin; RFALL-04 → single tracked value).

---

## Hero payout shape (HERO-04) — Q1: curve shape over S∈{0..9}

| Option | Description | Selected |
|--------|-------------|----------|
| Continuity (recommended) | S=3..9 track today's M=2..8; S=9≡M=8 jackpot; S=2 = small consolation | ✓ |
| Frequent-reward (flatter) | S=2 a felt win (~20% hit); top tiers trimmed to fund it | |
| Lottery (steeper) | Budget concentrated in S≥5; S=2 a token | |

**User's choice:** Continuity. Minimal player surprise, lowest calibration risk; jackpot relabel.
**Notes:** EV held at 100 centi-x per pick; derive script solves the exact constants at TST.

## Hero payout shape (HERO-04) — Q2: S=2 hero-alone magnitude

| Option | Description | Selected |
|--------|-------------|----------|
| Token (~10-20% wager) | Symbolic; ~3% of EV budget; max continuity, barely pays | |
| Partial refund (~40-60%) | Felt consolation; ~9% of budget; S=3..9 drift modestly below today | ✓ |
| Near break-even (~0.8-1x) | Most literal to vision; ~16% of budget; weakest continuity | |

**User's choice:** Partial refund (~40-60% of wager).
**Notes:** Honors "just getting the hero symbol right is a win" without gutting the continuity of
the real-match tiers.

## Hero payout shape (HERO-04) — Q3: bonus-currency thresholds on the 0-9 scale

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve rarity (S≥7) | Old M≥6 → new S≥7 (shift-by-one); same physical rarity | ✓ |
| Hold the label (S≥6) | Keep at S≥6; slightly more reachable | |
| You decide | Default to preserve-rarity unless math favors otherwise | |

**User's choice:** Preserve rarity (S≥7).
**Notes:** Applies to WWXRP bonus buckets + sDGNRS _awardDegeneretteDgnrs; recompute factors so
ETH +5% / WWXRP high-roi / sDGNRS award EV stays exact per N.

---

## Pool re-stranding (POOL-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Accept-as-minor | No second sweep; document donor-only residual (plan lean) | ✓ |
| Second sweep at +30d | Also pull in handleFinalSweep; catches the 30-day settlement tail | |

**User's choice:** Accept-as-minor.
**Notes:** burnAtGameOver auto-recovers all pre-gameOver pool ETH; a post-gameOver depositFor(SDGNRS)
harms only the donor. sDGNRS standalone-withdraw stays off the table (locked). VAULT unaffected.

---

## Claude's Discretion

Pure attestations the SPEC author resolves by reading source (intentionally not put to the user —
grep/derive work, not design choices): KEEP-04 (VAULT registered-code check + conditional setup),
KEEP-05 (autoOpen existing/new), BTOMB vaultAllowance checked-add/cap + one-shot packing, the
S=8/S=9 >32-bit Degenerette payout-table packing, SWAP-03 jitter VRF-word source (freeze-safe),
SWAP-06 ticketQueue swap-pop consumer enumeration. Plus SPEC section structure / deliverable
decomposition.

## Deferred Ideas

None new — discussion stayed within phase scope. Downstream phase work (IMPL 326, TST 327,
TERMINAL 328) and the off-chain indexer track are recorded in CONTEXT.md's Deferred Ideas.
