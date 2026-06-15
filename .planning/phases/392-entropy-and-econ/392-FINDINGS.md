# 392-FINDINGS — Phase 392 ENTROPY-AND-ECON consolidated index (ECON-01..06 + BURNIE-01..06)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY throughout the phase).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110** (expected
forge-failure NAME-set strictly EMPTY); the **BurnieEmissionSeeds** invariant (5/5) is the emission-
conservation anchor; **CoinflipCarryClaim.t.sol** is the carry-settle anchor.
**Method:** COUNCIL + CLAUDE both, dual-net per slice (AUDIT-V63-PLAN §2 — a no-finding verdict for any slice
requires BOTH nets on record).
**Posture:** AUDIT-ONLY. Any CONFIRMED finding is DOCUMENTED + ROUTED to a SEPARATE gated USER-hand-review
boundary, BATCHED, never fixed/auto-committed in this phase; the subject re-freezes only after a gated fix.

This index ties the two phase-392 slice deliverables into one phase verdict:
- **ECON slice** — `392-FINDINGS-ECON.md` (ECON-01..06 + FC-392-01..10 + FC-392-14/-15; the reward
  game-theory surface). NET 1 = `392-01-COUNCIL-NET.md` + `council/econ.gemini.txt`; NET 2 = `392-03-CLAUDE-NET.md`.
- **BURNIE slice** — `392-FINDINGS-BURNIE.md` (BURNIE-01..06 + FC-392-16..20 + cross-refs FC-392-11/-12/-13;
  the coinflip-seeded-emission / sDGNRS-backing surface). NET 1 = `392-02-COUNCIL-NET.md` +
  `council/burnie.gemini.txt`; NET 2 = `392-04-CLAUDE-NET.md`.

---

## 1. Both-nets-on-record rollup (both slices)

A no-finding (REFUTED / BY-DESIGN / MONITOR) verdict for any item in either slice cites BOTH nets; each
CONFIRMED finding records both nets' convergence.

| Slice | NET 1 (council) | NET 2 (Claude) | both on record? | codex |
|-------|-----------------|----------------|-----------------|-------|
| ECON (392-01 / 392-03) | gemini on record — 2 HIGH candidates (ECON-04 money pump, ECON-06 streak pump) + SOUND on ECON-01/-02/-05 | `392-03-CLAUDE-NET.md` — per-surface bounded-accrual sweep, in-code EV-neutrality arithmetic, money-pump per-leg liquid accounting, whale-pass quant, streak machinery trace | ✓ both | SKIPPED (hard usage-limit cap) — post-reset re-run RECOMMENDED for the 2 HIGH candidates (→ 396) |
| BURNIE (392-02 / 392-04) | gemini on record — 2 FINDINGS on the prime targets (PRIME-01 carry strand, PRIME-02 VAULT window-aging) + SOUND on BURNIE-01/-02/-03/-06 | `392-04-CLAUDE-NET.md` — exhaustive carry-backing trace, VAULT-window determination, conservation re-verify, survive-before-mint enum, monotone-latch proof, packed-lane round-trip, loss-sequence backing model | ✓ both | SKIPPED (hard usage-limit cap) — post-reset re-run RECOMMENDED for the 2 CONFIRMED prime leads (→ 396) |

**Both nets are on record for BOTH slices.** The codex skip (a hard usage-limit cap, the same banner across
392-01/392-02 — NOT a refusal/timeout) is documented, not silently passed: gemini is on record with real
content for both slices and NET 2 (Claude) is a full independent net for both. A post-reset codex
second-source re-run is RECOMMENDED for the ECON 2 HIGH candidates (REFUTED at the gate) AND the BURNIE 2
CONFIRMED prime leads (before any gated fix), carried to **396 terminal council**.

---

## 2. Phase-392 verdict rollup — all 12 reqs

| Req | Verdict | Slice deliverable (detail) |
|-----|---------|-----------------------------|
| **ECON-01** | ATTESTED (REFUTED — bounded accrual; every consumer saturates below the 65,534 hard cap; uncapped quest-streak widens no ceiling) | `392-FINDINGS-ECON.md` §2a |
| **ECON-02** | ATTESTED (REFUTED — EV-neutrality re-verified in code: split 40/15/15/15/10/5, ×11/9=19,678 → 8,855==8,855, far/near 1.000, variance Σ=0.78595==0.786×) | `392-FINDINGS-ECON.md` §2a |
| **ECON-03** | ATTESTED (REFUTED — the two EV changes match documented intent in code: band 9000-14500 @ 40,000; recycle ≥3-whole-ticket, drain-detection deleted) | `392-FINDINGS-ECON.md` §2a |
| **ECON-04** | ATTESTED (REFUTED — no closed positive-EV money pump; gemini HIGH candidate REFUTED via per-leg liquid accounting + skeptic dual-gate) | `392-FINDINGS-ECON.md` §2a / §3a |
| **ECON-05** | ATTESTED (BY-DESIGN — box WWXRP-spin whale-half-pass near-unfarmable: P(S=9)≈6.74e-8 / ~99M boxes-per-pass; per-bracket flag caps supply across routes) | `392-FINDINGS-ECON.md` §2a |
| **ECON-06** | ATTESTED (REFUTED — quest-streak rate-bounded ≤3/day + decay-gated; gemini HIGH streak-pump candidate REFUTED; same-day double-channel does not exist) | `392-FINDINGS-ECON.md` §2a / §3b |
| **BURNIE-01** | ATTESTED (REFUTED — survive-before-mint complete across every BURNIE source; FC-392-19 no-box-on-BURNIE-bet) | `392-FINDINGS-BURNIE.md` §2a |
| **BURNIE-02** | ATTESTED (REFUTED — emission conserved: 8M stake / ~4M EV replaces 2M+2M; off-by-one-clean handoff; BurnieEmissionSeeds 5/5) | `392-FINDINGS-BURNIE.md` §2a |
| **BURNIE-03** | ATTESTED (REFUTED — `sdgnrsAutoRebuyArmed` latch monotone, set once, no double-mint, no carry-extraction toggle; FC-392-18 unreachable) | `392-FINDINGS-BURNIE.md` §2a |
| **BURNIE-04** | **FINDING (CONFIRMED MED — under-credit/strand)** — auto-rebuy carry not reflected in sDGNRS redemption backing, no liquidation path; conservative, off the ETH spine; routed (USER may rule BY-DESIGN) | `392-FINDINGS-BURNIE.md` §2a / §4a / §5a |
| **BURNIE-05** | **FINDING (CONFIRMED-as-risk MED — lost-emission window)** — VAULT day-1-20 seed at silent irreversible forfeiture risk, no safety net; runbook-contingent; routed (USER may rule BY-DESIGN with a deploy-runbook MUST) | `392-FINDINGS-BURNIE.md` §2a / §4b / §5b |
| **BURNIE-06** | ATTESTED (REFUTED — packed lanes round-trip losslessly; BURNIE off the ETH/`claimablePool` spine) | `392-FINDINGS-BURNIE.md` §2a |

**Phase rollup:** 10 of 12 reqs ATTESTED (REFUTED/BY-DESIGN, both nets); **2 reqs CARRY CONFIRMED MED
findings** (BURNIE-04 carry strand, BURNIE-05 VAULT window-aging) — both in the BURNIE slice, both off the ETH
spine, both routed to a gated USER-hand-review boundary (the USER may rule either BY-DESIGN). The ECON slice is
0 CONFIRMED.

---

## 3. Consolidated routed-findings list

| # | Finding | Slice | Weight | Routing | Second-source |
|---|---------|-------|--------|---------|---------------|
| 1 | **BURNIE-04 / FC-392-16** — sDGNRS auto-rebuy carry stranded from redemption backing (under-credit/strand, no liquidation path; conservative, off the ETH spine) | BURNIE | MED | gated USER hand-review, BATCHED; fix options = count carry in `burnieOwed` / add sDGNRS carry liquidation / rule BY-DESIGN + KNOWN-ISSUES note. USER may rule BY-DESIGN. | post-reset codex re-run RECOMMENDED → 396 |
| 2 | **BURNIE-05 / FC-392-17** — VAULT seed window-aging forfeiture (~2M expected BURNIE at silent irreversible forfeiture risk; no safety net; runbook-contingent) | BURNIE | MED | gated USER hand-review, BATCHED; fix options = auto-claim/arm-at-deploy / widen window / accept BY-DESIGN + deploy-runbook MUST. USER may rule BY-DESIGN. | post-reset codex re-run RECOMMENDED → 396 |

**No CATASTROPHE/HIGH across either slice.** The skeptic gate was applied to both ECON HIGH candidates
(REFUTED) and both BURNIE prime leads (CONFIRMED-MED, below the HIGH bar — no money pump, no supply break, no
ETH insolvency, no attacker profit; value-bearing but bounded off the ETH spine). Both CONFIRMED findings are
DOCUMENTED + ROUTED, never fixed in this phase; the subject stays byte-frozen.

Carried INFO/MONITOR (no contract change): ECON — FC-392-04 stale EV-band comment, FC-392-03 documented
decimator ramp, FC-392-15 carried affiliate-score asymmetry (`392-FINDINGS-ECON.md` §4b); BURNIE — FC-392-18
latent `fromGame` branch, FC-392-20 claim-window gas (→ 393), FC-392-11 backing-dynamics (REFUTED; RNG-lock
half attested at 391) (`392-FINDINGS-BURNIE.md` §5c).

---

## 4. Cross-ref consistency notes (FC-392-08, FC-392-11)

- **FC-392-08 (redemption ETH-spin pool RMW + recirc):** the **ECON cap-RMW half** is BY-DESIGN here (the
  recirc cap RMW funnels into the same packed cap, monotonic within a level; ETH-spin recirc depth 1) —
  `392-FINDINGS-ECON.md` §2b / §3c. The **solvency-CEI half** is REFUTED at **390 SOLVENCY-SPINE**
  (`390-FINDINGS.md` §2c FC-392-08: flush-before-recirc, stETH-remainder pulled in before crediting, chunks
  sequential in one delegatecall frame, no cross-chunk cap-RMW race; `_pendingRedemptionEthValue` release ==
  leg movement). The **permissionless-race half** is owned by **393** (FC-393-03 partial-balance same-block
  redemption-leg solvency). **Consistent across 390/392/393** — the cap-RMW funnels into one monotonic packed
  cap (ECON), the CEI/pool reconciliation holds (390), the cross-chunk race is owned by 393. No divergence.
- **FC-392-11 (sDGNRS auto-rebuy backing dynamics):** the **RNG-lock half** is REFUTED at **391 RNG-SPINE**
  (`391-FINDINGS.md` §2c: the lock over the carry roll is airtight — `claimCoinflipCarry` reverts on
  `rngLocked()` before reading the carry; `processCoinflipPayouts` applies the roll inside the locked window).
  The **backing-dynamics half** is REFUTED here (`392-FINDINGS-BURNIE.md` §2c / §3c: the loss-sequence variance
  couples only to the stranded carry — which IS the FC-392-16 CONFIRMED finding — never to the accounted
  held-balance obligations `burnieOwed` tracks; no mid-roll extraction). **Consistent across 391/392** — the
  lock is airtight (391), the backing variance is confined to the (separately-CONFIRMED) stranded carry (392),
  not a distinct solvency break. No divergence.

---

## 5. Phase-392 byte-freeze attestation

`git diff a8b702a7 -- contracts/` is EMPTY before and after every task across BOTH slices
(392-01/392-02/392-03/392-04); `git status --porcelain contracts/` EMPTY; the contracts tree held at
`2934d3d8987a09c5f073549a0cb499f6c5f28620` throughout. The council ran read-only (`--approval-mode plan` /
`--sandbox read-only`); NET 2 read all source via `git show a8b702a7:`; hardhat was never invoked (the
ContractAddresses-regeneration landmine avoided). No CONFIRMED finding was fixed in-phase — both BURNIE
findings are DOCUMENTED + ROUTED to a gated USER-hand-review boundary. The only untracked working-tree file is
the pre-existing `PLAYER-PURCHASE-REWARDS.html` (unrelated; left untouched).

**Phase-392 verdict:** the ENTROPY-AND-ECON surface (all 12 reqs — ECON-01..06 + BURNIE-01..06, + the owned
+ cross-ref leads) is adjudicated with BOTH nets on record for BOTH slices, the skeptic gate applied (0
CATASTROPHE/HIGH), and every item carrying an explicit verdict. **2 CONFIRMED MED findings** (BURNIE-04 carry
strand, BURNIE-05 VAULT window-aging — both off the ETH spine, both routed to a gated USER-hand-review
boundary, the USER may rule either BY-DESIGN), **0 CONFIRMED in the ECON slice**, and a recommended post-reset
codex second-source for both the ECON HIGH candidates and the BURNIE prime leads carried to 396. The byte-
frozen subject `a8b702a7` is attested throughout.
