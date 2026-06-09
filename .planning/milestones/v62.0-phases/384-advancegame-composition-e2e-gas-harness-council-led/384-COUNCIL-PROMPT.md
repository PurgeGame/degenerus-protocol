# Council Sweep 384 — COMPOSITION: advanceGame stage graph + e2e gas + liveness

You are an external auditor on a cross-model council auditing the **Degenerus Protocol** before a Code4rena
audit. Read the EXACT frozen source at `c4d48008` via `git show c4d48008:contracts/<File>.sol` (ignore the
working tree). Concrete + reachable only.

**Threat priority:** HIGH here = gas-DoS in the `advanceGame` chain — a single tx exceeding **16,777,216
gas** (EIP-7825) permanently bricks game-over advancement. Also DOMINANT = RNG/freeze + solvency.

**ALREADY FOUND (do NOT re-report):** V62-01 (lootbox auto-open off-by-one). Known: the game-over
ticket-drain→terminal-jackpot composition was FIXED (`6d2c8d0c`, per-ticket-batch broken out, terminal
jackpot isolated; post-fix worst-case ~6.4M < 10M soft target). A reusable harness
(`AdvanceGasCeilingBase` + parameterized `GameSeeder`) already drives the REAL `advanceGame()` and asserts
every tx ≤ 16,777,216 over fuzzed reachable pre-states (max observed ~6.6M).

**KNOWN BY-DESIGN (do NOT flag):** as in the other sweeps (lootbox timing, RTP/WWXRP, operator trust
boundary, inclusive eviction, claimBingo, affiliate direct-mint, PRESALE-01).

## Focus (COMPO-01..03 + NETGAP-02 liveness)

1. **Two-stages-in-one-tx composition (COMPO-01/03).** Enumerate EVERY stage-break in `advanceGame`
   (`DegenerusGameAdvanceModule.sol` — the `STAGE_*` returns/breaks). For each "finished"/break branch ask:
   **what runs NEXT in the SAME tx?** Find a stage that falls through into another heavy stage (the v60
   gasceil shape) or a break that re-enters heavy work. Re-verify the known-checked fall-throughs post-v61:
   game-over ticket-drain→terminal-jackpot (FIXED), entropy→ticket (BOUNDED), and the
   subscriber / jackpot / transition / gap-backfill break points.
2. **Worst-case gas (COMPO-02).** Derive the theoretical WORST-CASE `advanceGame` pre-state (bucket
   geometry / owed sizes / level / max winners 305+50 / max subscribers 1000 / full gap-backfill 120) —
   NOT a typical seed. Is there a reachable composition where a single tx could approach or exceed
   16,777,216? If you believe every single tx is provably bounded < 16.7M, state the bounding argument per
   heavy stage.
3. **advanceGame LIVENESS (NETGAP-02).** Can `advanceGame()` REVERT from a reachable state where it is due
   and not rng-locked (i.e. a permanent stall / brick that a gas-only check would miss)? Trace every
   `revert`/`require`/unchecked-subtraction/division reachable inside the advance chain. (A reverting
   advance bricks the game even though it costs little gas.)

## Output (per finding)
PROPERTY · reachable pre-state / CALL SEQUENCE · the heavy stage + `file:line` at `c4d48008` · the gas or
revert mechanism · SEVERITY. If `advanceGame` is provably bounded and revert-free from reachable states,
say so with the per-stage argument.
