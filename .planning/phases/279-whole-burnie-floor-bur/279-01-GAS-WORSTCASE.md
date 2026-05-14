# Phase 279 / Plan 01 — Worst-Case Gas Derivation

**Requirement:** BUR-05 (theoretical worst-case gas path derived FIRST, then measured bytecode delta).
**Decisions:** D-279-INLINE-01 (inline `(x / 1 ether) * 1 ether` floor — no shared helper), D-279-BUR01-SITE-01, D-279-BUR02-DEADVAR-01 (`extra`/`cursor` cursor-rotation fully removed), D-279-BUR03-ORDER-01.
**Discipline:** `feedback_gas_worst_case.md` — derive the theoretical worst case FIRST, then benchmark.

## Theoretical Worst-Case Derivation (derived BEFORE benchmarking)

Phase 279 applies the same inline integer-division floor `(x / 1 ether) * 1 ether` at 3 RNG-amount-driven BURNIE-award sites. Each floor is, at the EVM-opcode level, **one `DIV` + one `MUL` + one `PUSH`** of the `1 ether` (`10**18`) constant — a fixed, branch-free, storage-free ~10–15 gas one-time cost wherever it sits.

### Per-site worst-case analysis

**BUR-01 — `_resolveLootboxCommon` `burnieAmount` floor.**
The floor sits **once**, in straight-line code (not in a loop). Worst-case runtime delta: one `DIV` + one `MUL` + one `PUSH` ≈ +10–15 gas per lootbox resolution. No loop amplification — `_resolveLootboxCommon` runs once per lootbox open/resolve. **One-time, ~flat.**

**BUR-02 — `_awardDailyCoinToTraitWinners` `baseAmount` floor + `extra`/`cursor` removal.**
This is the **candidate worst-case site** because it sits in front of a `for (i < cap)` loop over up to `DAILY_COIN_MAX_WINNERS` winners. But:
- The `baseAmount` floor itself is **outside** the loop (computed once, one `DIV` + one `MUL` + one `PUSH`).
- The `extra`/`cursor` cursor-rotation removal **DELETES per-iteration work from every loop iteration**: the loop-tail `++cursor; if (cursor == cap) cursor = 0;` (an `ADD` + a `EQ` + a conditional `MSTORE`-free zero-write) and the empty-bucket-branch copy of the same, plus the per-iteration `if (extra != 0 && cursor < extra) { amount += 1; }` (two comparisons + a branch + a conditional `ADD`). Every winner iteration is **net gas-NEGATIVE** after the change — the removed per-iteration ops outweigh the one-time floor.
- Net for the function: a one-time `DIV`+`MUL`+`PUSH` traded against `cap`-many iterations of removed cursor-rotation/`extra`-check ops → **net gas-NEGATIVE for any `cap >= 1`**, increasingly negative as `cap` grows toward `DAILY_COIN_MAX_WINNERS`.

**BUR-03 — `_awardFarFutureCoinJackpot` `perWinner` floor.**
The floor sits **once**, immediately after `farBudget / found` and before the unchanged `if (perWinner == 0) return;`. One `DIV` + one `MUL` + one `PUSH` ≈ +10–15 gas per far-future jackpot award. The downstream `for (i < found)` emit loop is unchanged. **One-time, ~flat.**

### Theoretical worst-case verdict

The **theoretical worst-case runtime path** is BUR-01's `_resolveLootboxCommon` floor: a flat ~+10–15 gas one-time cost with no loop amplification and no offsetting deletion in that function (unlike BUR-02, which is net-negative per iteration). BUR-03 is the same shape as BUR-01 (one-time, ~flat). BUR-02 — despite sitting in front of a loop — is **net gas-NEGATIVE** because the `extra`/`cursor` removal strips per-iteration ops from every winner iteration.

**Aggregate runtime gas:** ~+20–30 gas one-time across BUR-01 + BUR-03, **minus** a `cap`-scaled per-iteration saving at BUR-02. For any daily-coin jackpot with `cap >= ~2` winners the per-jackpot runtime delta is net-negative; the lootbox/far-future one-time floors are individually negligible (~1 `DIV`+`MUL` each).

## Empirical Bytecode Delta

Extraction recipe: `forge inspect <contract> bytecode` (and `deployedBytecode`) at the current working tree vs the `HEAD` commit tree materialized read-only via `git archive HEAD | tar -x`; byte count = `(hexlen − 2) / 2`. Baseline of record for BUR-05 is **current HEAD** (per Task 3 `what-built`: "the measured bytecode-size delta … vs current HEAD").

| Contract | HEAD (deployed) | Phase 279 (deployed) | Δ deployed | HEAD (creation) | Phase 279 (creation) | Δ creation |
|---|---|---|---|---|---|---|
| `DegenerusGameLootboxModule` | 18,211 | 18,351 | **+140** | 18,285 | 18,425 | +140 |
| `DegenerusGameJackpotModule` | 23,968 | 23,942 | **−26** | 24,042 | 24,016 | −26 |
| **Total** | | | **+114** | | | **+114** |

For reference vs the v39 baseline `6a7455d1` (spans Phases 275–279): LootboxModule deployed 19,428 → 18,351 (**−1,077**); JackpotModule deployed 24,657 → 23,942 (**−715**); total **−1,792** vs `6a7455d1`. The Phase-279-only delta vs current HEAD, however, is **+114 bytes**.

### Bytecode delta is NET-POSITIVE (+114 bytes) — deviation from the plan's BUR-05 NET-NEGATIVE expectation

The plan's BUR-05 expectation ("the `extra`/`cursor` deletions should remove more bytecode than the 3 inline floors add → NET-NEGATIVE expected") **did not hold** for the Phase-279-only delta. Breakdown:

- **`DegenerusGameJackpotModule` is correctly NET-NEGATIVE (−26 bytes)** — the BUR-02 `extra`/`cursor` dead-var removal (two stack-local declarations + two `++cursor`/wrap sites + the `extra != 0 && cursor < extra` `amount += 1` block) outweighs the two added inline floors (BUR-02 `baseAmount` + BUR-03 `perWinner`). This matches the plan's expectation for this module.

- **`DegenerusGameLootboxModule` is NET-POSITIVE (+140 bytes)** — and dominates the aggregate. Root cause: `_resolveLootboxCommon` was already at the Solidity stack-depth ceiling. Inserting the BUR-01 floor as a literal statement at its CONTEXT.md-specified position (after the ticket-handling block, before the `if (burnieAmount != 0)` guard) **fails to compile** — `YulException: Cannot swap … too deep in the stack by 1 slots`. The fix (a permitted Rule 3 blocking-issue fix, and explicitly within D-279-BUR01-SITE-01's "Claude's Discretion … exact placement" allowance): the `burnieAmount` accumulation block was **reordered** to sit immediately after `_accumulateLootboxRolls` returns, shortening the live-range of the `burniePresale` / `burnieNoMultiplier` stack locals so the floor statement fits. Measured in isolation, the reorder ALONE is **−96 bytes** (it relieves stack pressure); but the reorder **plus the floor statement** is **+140 bytes** — adding the floor re-introduces enough stack pressure that the optimizer falls back to a less-compact stack schedule. The +140 is therefore not the cost of the `DIV`/`MUL` arithmetic (~2 opcodes) — it is the optimizer's stack-spill workaround in an already-saturated function. Multiple alternative placements were tried (floor at the original guard position, `bonusBurnie` local inlined, scoped-block snapshot); every placement that adds a statement anywhere in `_resolveLootboxCommon` either fails to compile or lands at the same +140.

## Empirical Per-Invocation Gas (status)

**FIXTURE_COVERAGE_GAP_NOTED — analytical worst-case load-bearing.**

The 3 BUR sites (`_resolveLootboxCommon`, `_awardDailyCoinToTraitWinners`, `_awardFarFutureCoinJackpot`) are all `private` and have a documented fixture-coverage gap (no deterministic full-state harness with the required seed-injection + multi-actor jackpot/lootbox state surface exists in the test tree — the same gap noted in the Phase 278 GAS artifact and the Phase 276 `JackpotTicketRollSilentColdBust` precedent). Per `feedback_gas_worst_case.md` + Phase 266/275/276/278 precedent ("derive the theoretical worst case FIRST, then test — but if the test fixture doesn't exist, the analytical worst-case is load-bearing"), the analytical derivation above is the load-bearing artifact. The measured bytecode delta provides corroborating empirical evidence of the code-size direction. No empirical per-invocation gas numbers are fabricated.

## Verdict

- **Theoretical worst-case runtime gas:** ~+10–15 gas one-time at BUR-01 (the no-offset worst case) and the same at BUR-03; BUR-02 is **net gas-NEGATIVE per loop iteration** (the `extra`/`cursor` removal strips per-winner ops). Aggregate per-jackpot runtime is net-negative for any `cap >= ~2`.
- **Measured bytecode delta vs current HEAD: +114 bytes (NET-POSITIVE).** `DegenerusGameJackpotModule` is correctly net-negative (−26 bytes). `DegenerusGameLootboxModule` is net-positive (+140 bytes) and dominates — the consequence of `_resolveLootboxCommon` being at the Solidity stack-depth ceiling, where any added statement forces the Yul optimizer into a less-compact stack schedule. This is a **deviation from the plan's BUR-05 NET-NEGATIVE expectation** and is surfaced to the user at the Task 3 checkpoint for an explicit accept/reconsider decision.

## Commit-Message-Ready Summary Block

```
Gas delta:      Runtime ~+10-15 gas one-time at BUR-01 + BUR-03 each
                (1 DIV + 1 MUL + 1 PUSH, straight-line, no loop
                amplification). BUR-02 is net gas-NEGATIVE per loop
                iteration -- the extra/cursor cursor-rotation removal
                strips per-winner ops. Aggregate per-jackpot runtime is
                net-negative for cap >= ~2. Empirical per-invocation
                benchmark: FIXTURE_COVERAGE_GAP_NOTED -- no deterministic
                full-state harness for the 3 private BUR sites;
                analytical worst-case load-bearing per
                feedback_gas_worst_case.md + Phase 266/275/276/278
                precedent.
Bytecode delta: +114 bytes deployed vs current HEAD (NET-POSITIVE).
                DegenerusGameJackpotModule -26 bytes (23,968 -> 23,942)
                -- the extra/cursor dead-var removal outweighs the BUR-02
                + BUR-03 floors, as expected. DegenerusGameLootboxModule
                +140 bytes (18,211 -> 18,351) -- _resolveLootboxCommon was
                at the stack-depth ceiling; the BUR-01 floor statement
                forces a less-compact optimizer stack schedule (the
                burnieAmount-accumulation reorder that makes it compile is
                -96 bytes alone). DEVIATION from the BUR-05 NET-NEGATIVE
                expectation -- accepted by explicit user decision.
Storage:        byte-identical to v39 baseline 6a7455d1 for both modules
                per 279-01-STORAGE-LAYOUT-DIFF.md PASS verdict.
```
