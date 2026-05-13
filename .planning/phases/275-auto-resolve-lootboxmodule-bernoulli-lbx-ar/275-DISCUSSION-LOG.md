# Phase 275: Auto-Resolve LootboxModule Bernoulli (LBX-AR) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-13
**Phase:** 275-Auto-Resolve LootboxModule Bernoulli (LBX-AR)
**Areas discussed:** Bernoulli code shape, TST-LBX-AR-04 seed-uniqueness depth, Gas worst-case path, TST-LBX-AR-05 _rollRemainder zero-invocation surface

---

## Bernoulli Code Shape on `_resolveLootboxCommon`

| Option | Description | Selected |
|--------|-------------|----------|
| A1 — Hoist outside the index-sentinel branch | Compute scaledPre/whole/frac/roundedUp ONCE before the `if (index != type(uint48).max)` gate; manual branch handles consolation + `LootboxTicketRoll` emit; auto-resolve calls `_queueTickets(whole)`. Pre-stages Phase 277 EVT-UNI-05 sentinel-retirement. Manual-path bytecode shape changes vs v39 (Bernoulli moves out of manual-only block); math unchanged. | ✓ |
| A2 — Duplicate inline in the auto-resolve branch | Leave manual branch byte-identical at :1039–1061; add a fresh copy of the Bernoulli math inside the auto-resolve branch only. Minimum diff against v39. Phase 277 EVT-UNI-05 needs to consolidate the duplication when retiring the sentinel. | |
| A3 — Extract `_bernoulliWhole(seed, scaled)` private helper | New `internal pure` function returning (uint32 whole, bool roundedUp). Both branches call the helper. Costs +1 internal call frame (~20–40g per resolve on top of eliminated `_rollRemainder` savings). Cleanest abstraction, but Phase 277 will absorb the helper into a single inlined path anyway. | |

**User's choice:** A1 — Hoist outside the index-sentinel branch (Recommended).

**Selected preview snapshot (canonical reference for planner):**

```solidity
if (futureTickets != 0) {
    // distress bonus (unchanged)
    ...
    // Bernoulli (hoisted — applies to both branches)
    uint32 scaledPre = futureTickets;
    uint32 whole = futureTickets / uint32(TICKET_SCALE);
    uint32 frac = futureTickets % uint32(TICKET_SCALE);
    bool roundedUp = false;
    if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) {
        unchecked { whole += 1; }
        roundedUp = true;
    }
    if (index != type(uint48).max) {
        // manual: consolation + LootboxTicketRoll
        if (whole != 0) {
            _queueTickets(player, targetLevel, whole, false);
        } else {
            wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);
            emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);
        }
        emit LootboxTicketRoll(player, index, scaledPre, roundedUp);
    } else {
        // auto-resolve: silent (_queueTickets early-returns on whole==0)
        _queueTickets(player, targetLevel, whole, false);
    }
}
```

**Notes:** Captured as D-275-HOIST-01 in CONTEXT.md. EV-neutrality identity from v39 §4 (a) carries verbatim. Storage layout byte-identical preserved per LBX-AR-05.

---

## TST-LBX-AR-04 Seed-Uniqueness Test Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Direct-call `_resolveLootboxCommon` with synthetic seeds | Per-caller test functions inject distinct rngWord values, call `_resolveLootboxCommon` directly with synthesized inputs matching each caller's keccak shape, assert chi-square on bits[152..167] independence. Matches v39 TST-WT precedent. Faster, narrower scope. | ✓ |
| Full-stack integration through each caller (4 separate flows) | Exercise `claimDecimatorJackpot(lvl)` + Degenerette payout + sDGNRS redeem + Game:1721 5-ETH-chunk loop with N iterations of L1769 rngWord evolution. Slower, broader scope (verifies the L1769 evolution + per-level rngWord-storage + entropy-mixing all produce statistically-independent bits[152..167] in production). | |
| Hybrid — direct-call for (a)(b)(c), full-stack for (d) | Cheap test on cheap surface (DecimatorModule + DegeneretteModule + sDGNRS single-shot), expensive test on the surface that actually exercises rngWord evolution (Game:1721 redemption-loop). Best signal-to-runtime ratio. | |

**User's choice:** Direct-call (Recommended).

**Notes:** Captured as D-275-TST-04-01 in CONTEXT.md. The full-stack 4-caller integration test was kept as a deferred candidate to revisit if adversarial pass at Phase 280 surfaces a redemption-loop-specific concern around L1769 rngWord evolution.

---

## Gas Delta Reporting — Worst-Case Path

| Option | Description | Selected |
|--------|-------------|----------|
| `resolveRedemptionLootbox` single-chunk @ peak EV multiplier | Single `_resolveLootboxCommon` invocation with maximum scaled `futureTickets`, far-future target level triggering boon roll + distress bonus + DGNRS path. Per-resolve hot path. Head-to-head comparable with v39 manual-path `openLootBox` gas. Clean delta number. | ✓ |
| `Game:1721` 5-ETH-chunk redemption-loop with N iterations | Multi-iteration worst case: large sDGNRS redemption emitting N chunks, each evolving rngWord at L1769 and calling resolveRedemptionLootbox per chunk. Tests amortized per-chunk cost + cumulative gas envelope. Per-chunk gas dominates; delta scales with N. Noisier number for a per-resolve commit message. | |
| `claimDecimatorJackpot(lvl)` with maximum scaled `futureTickets` | Decimator settlement path. Single-shot per call; rngWord from per-level storage. Comparable to v39 manual-path benchmark but on the decimator surface. Useful if the highest-volume auto-resolve traffic is claimDecimatorJackpot. | |

**User's choice:** `resolveRedemptionLootbox` single-chunk @ peak EV multiplier (Recommended).

**Notes:** Captured as D-275-GAS-WC-01 in CONTEXT.md. Per `feedback_gas_worst_case.md`: derive theoretical worst case FIRST, then benchmark. Expected delta: net-neutral within ±300 gas per resolve after factoring eliminated `_rollRemainder` consumption at trait-assignment time. Commit message reports bytecode delta + gas delta against this path.

---

## TST-LBX-AR-05 `_rollRemainder` Zero-Invocation Assertion Surface

| Option | Description | Selected |
|--------|-------------|----------|
| Snapshot `ticketsOwedPacked` rem byte before/after activation | Open N auto-resolve lootboxes, advance level so target queue activates, read `ticketsOwedPacked[wk][buyer]` and assert `uint8(packed) == 0` both pre and post (rem byte stays zero because Bernoulli-collapsed `_queueTickets` never wrote rem). No test-only contract hook; pure observability via existing storage. | ✓ |
| Forge `vm.mockCall` on `_rollRemainder` + assert call count | Mock the `_rollRemainder` selector, run auto-resolve + activation, assert mock was invoked zero times. Direct call-count assertion. Caveat: `_rollRemainder` is internal (not external-call-mockable via standard `vm.mockCall`) — would require coverage-trace hack or internal-virtual + override pattern. More complex setup. | |
| Test-only counter injection in `_rollRemainder` | Add a `#ifdef TEST_HARNESS` style counter increment inside `_rollRemainder` (or use a test-only inheriting contract that overrides). Direct call counting. Costs a test-mode contract variant; adds discipline overhead to keep test vs prod bytecode aligned. | |

**User's choice:** Snapshot `ticketsOwedPacked` rem byte before/after activation (Recommended).

**Notes:** Captured as D-275-TST-05-01 in CONTEXT.md. Strongest signal — directly observes the state change `_rollRemainder` would mutate. No test-only contract hook required; pure observability via existing storage layout.

---

## Claude's Discretion

- Exact wording of bit-allocation NatSpec update at `DegenerusGameLootboxModule.sol:891-892` (per D-275-NATSPEC-01).
- Storage-layout byte-identity proof recipe (`forge inspect storage-layout` diff vs `git show 6a7455d1` artifact).
- Exact test filenames + function names within the `test/unit/` + `test/edge/` + `test/stat/` placement scheme (per D-275-TST-PLACEMENT-01).

## Deferred Ideas

- **Full-stack 4-caller integration test for seed-uniqueness** — option B from TST-LBX-AR-04 discussion. Revisit if Phase 280 adversarial pass surfaces a redemption-loop-specific concern around L1769 rngWord evolution.
- **`_bernoulliWhole(seed, scaled)` private helper** — option A3 from code-shape discussion. Phase 277 EVT-UNI-05 will absorb the hoisted shape into a single inlined path; helper extraction redundant.
- **Sentinel retirement + event surface unification** — Phase 277 EVT-UNI (D-40N-SENTINEL-RETIRE-01 + D-40N-EVT-BREAK-01).
- **JackpotModule:2216 BAF Bernoulli + `_queueLootboxTickets` wrapper retirement** — Phase 276 JPT-BR + Phase 278 JPT-CLEAN.
- **Mint-boost fractional retirement** — D-40N-MINTBOOST-OUT-01 retains the status quo.
