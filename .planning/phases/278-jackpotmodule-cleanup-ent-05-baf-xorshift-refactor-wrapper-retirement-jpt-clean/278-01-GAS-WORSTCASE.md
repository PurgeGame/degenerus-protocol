# Phase 278 / Plan 01 — Worst-Case Gas Derivation

**Requirement:** JPT-CLEAN-06 (bytecode delta NET-NEGATIVE).
**Decisions:** D-278-ENT05-01 (`entropyStep`→`hash2` swap), D-278-ENT05-CHAIN-01 (`hash2(entropy, entropy)` self-mix — zero new constants), D-278-ENTROPYSTEP-DELETE-01 (`entropyStep` deleted), D-278-EVT-UNIFY-01 (emit-value unification), JPT-CLEAN-05 (`_queueLootboxTickets` deleted).
**Discipline:** `feedback_gas_worst_case.md` — derive theoretical worst case FIRST, then benchmark.

## Theoretical Worst-Case Derivation

**Worst-case path:** `_jackpotTicketRoll(winner, amount, minTargetLevel, entropy)` reaching the **5%-branch** (`roll = entropy % 100 >= 95`), selecting the **maximum far-future offset** (`offset = 5 + (entropyDiv100 % 46)` at its `+50` ceiling → `targetLevel = minTargetLevel + 50`), with:
- `targetLevel > level + 5` → `isFarFuture == true` inside `_queueTickets` (`DegenerusGameStorage.sol`).
- First buyer at that far-future write-key → `_tqFarFutureKey(targetLevel)` → **cold** `ticketQueue[wk].push(buyer)` (`owed == 0 && rem == 0` at the slot) → a single `ticketsOwedPacked` SSTORE on a zero-to-nonzero slot.
- `frac != 0` (e.g. `scaledTickets = 9999` → `whole = 99`, `frac = 99`): exercises the full inline Bernoulli predicate path including the `unchecked { whole += 1; }` increment branch.

This path was chosen because it is the deepest code path through `_jackpotTicketRoll` — the far-future branch maximises `entropyDiv100 % 46` consumption, the cold `_tqFarFutureKey` push is the most expensive `_queueTickets` storage path, and a non-zero `frac` puts the Bernoulli predicate at its most expensive branch. It is head-to-head comparable with the Phase 276 `_jackpotTicketRoll` worst-case.

## Instruction-Level Diff vs v39 Baseline `6a7455d1`

Phase 278 changes only the **entropy-evolution primitive** at the head of `_jackpotTicketRoll` and the **emit-value expressions** — it does NOT change the queue-ticket call path (that was already `_queueTickets(whole, true)` post-Phase-276). So the gas analysis is confined to the `:2210` swap + the 3 emit sites.

| Category | v39 baseline | Phase 278 | Δ per roll |
|---|---|---|---|
| Entropy evolution at `_jackpotTicketRoll` entry | `EntropyLib.entropyStep(entropy)` — 3-op xorshift: `SHL/XOR + SHR/XOR + SHL/XOR` (6 ops, ~18–30 gas, stack-only) | `EntropyLib.hash2(entropy, entropy)` — 2× `MSTORE` to scratch (0x00, 0x20) + 1× `KECCAK256` over 0x40 bytes | `KECCAK256` base 30 + 6 per word ×2 = ~42 gas + 2 `MSTORE` ~6 gas ≈ **+48 gas raw; net ≈ +20 to +30 gas** vs the xorshift it replaces |
| `entropyStep` function body | Inlined 3-op xorshift at the one call site | Deleted from `EntropyLib` entirely | Removes inlined code region — bytecode shrink, no runtime cost change beyond the swap above |
| `_queueLootboxTickets` thin wrapper | Present in `DegenerusGameStorage.sol`, **zero callers** since Phase 276 | Deleted | **Zero runtime delta** — the wrapper was already dead code; the Solidity optimizer had already eliminated it from `DegenerusGame`'s deployed bytecode at baseline. Source-hygiene deletion only. |
| `JackpotTicketWin` 4th-arg emit value | `ticketCount * uint32(TICKET_SCALE)` / `uint32(units * TICKET_SCALE)` / `uint32(quantityScaled)` — each computes a `MUL` or carries a wider intermediate | `ticketCount` / `uint32(units)` / `whole` — the whole count already in a stack local | **−1 `MUL` per emit** at sites 1 & 2 (~−5 gas each); site 3 drops a `uint32()` cast of an already-`uint32` boundary value. The 32-byte event data word is the same size — no `LOG` gas delta. ≈ **−10 gas** across the 3 sites, amortised per jackpot. |

**Per-roll net (analytical):** ≈ **+20 to +30 gas** at the `_jackpotTicketRoll` call site (keccak slightly dearer than xorshift) **− ~5–10 gas** from the dropped emit-value `MUL`s ≈ **net-flat to slightly positive (~+15 to +25 gas) per roll at the runtime hot path.** This is the deliberate, accepted cost of D-278-ENT05-01: the swap buys full low-bit diffusion for the path/level + Bernoulli consumers (converting EXC-04 from a documented `NARROWS` KI to a fixed non-issue) at near-zero gas cost. `hash2` is ~10× cheaper than an `abi.encode`-based keccak (it uses scratch slots), so the keccak primitive choice is already the cheapest possible.

The **bytecode** delta, by contrast, is strongly **NET-NEGATIVE** — the two function deletions (`entropyStep` + `_queueLootboxTickets`) remove more code than the swap adds.

## Empirical Bytecode Delta

Extraction recipe: `forge inspect <contract> bytecode` (and `deployedBytecode`) at the current working tree vs a detached-HEAD git worktree at `6a7455d1`; byte count = `(hexlen − 2) / 2`.

| Contract | v39 baseline `6a7455d1` (creation) | Phase 278 HEAD (creation) | Δ creation |
|---|---|---|---|
| `DegenerusGameJackpotModule` | 24,731 bytes | 24,042 bytes | **−689 bytes** |
| `EntropyLib` | 87 bytes | 87 bytes | 0 (library has only `internal` fns — no standalone deployed code; `entropyStep` removal surfaces in JackpotModule's size) |
| `DegenerusGameStorage` | 0 bytes | 0 bytes | 0 (abstract — `internal` helpers inline into the consuming `DegenerusGame` contract) |

| Contract | v39 baseline `6a7455d1` (deployed) | Phase 278 HEAD (deployed) | Δ deployed |
|---|---|---|---|
| `DegenerusGameJackpotModule` | 24,657 bytes | 23,968 bytes | **−689 bytes** |
| `DegenerusGame` (consumes `DegenerusGameStorage` helpers) | 20,823 bytes | 20,823 bytes | 0 — the `_queueLootboxTickets` wrapper had zero callers and was already dead-code-eliminated from `DegenerusGame`'s deployed bytecode at baseline; its source deletion is a hygiene cleanup with no deployed-bytecode effect |

**Net deployed-bytecode delta: −689 bytes (NET-NEGATIVE).** The reduction comes entirely from `DegenerusGameJackpotModule` — the `entropyStep` inlining is gone (replaced by the more compact `hash2` library call) and the emit-value `MUL`s are dropped. The `_queueLootboxTickets` deletion contributes zero deployed bytes (already eliminated) but removes 18 lines of dead source per `feedback_no_dead_guards.md`.

## Empirical Per-Invocation Gas (status)

**FIXTURE_COVERAGE_GAP_NOTED — analytical worst-case load-bearing.**

Reaching the `_jackpotTicketRoll` 5%-branch with a `+50` far-future target deterministically requires precise control of the *internally evolved* entropy word (`hash2(entropy, entropy)` then `% 100 >= 95` AND `(entropy / 100) % 46 == 45`) inside the jackpot-payout loop, plus a jackpot winner with a BAF lootbox win of the right ETH magnitude queued at the right game stage. No harness with that seed-injection + multi-actor jackpot-state surface exists in the test tree today; building it for a single benchmark is scope-creep beyond Plan 01 (it belongs with the Wave 2 `278-02` statistical-invariant fixtures if at all).

Per **Phase 266 GAS-01 / Phase 275 / Phase 276 precedent** + **`feedback_gas_worst_case.md` discipline** ("derive the theoretical worst case FIRST, then test — but if the test fixture doesn't exist, the analytical worst-case is load-bearing"), the analytical derivation above is the load-bearing artifact. The −689 byte deployed-bytecode delta provides corroborating empirical evidence that the code region shrank. No empirical per-invocation numbers are fabricated.

## Verdict

**Bytecode delta NET-NEGATIVE (−689 bytes deployed) per JPT-CLEAN-06.** Per-roll runtime gas is analytically net-flat to slightly positive (~+15 to +25 gas) — the deliberate, accepted, near-zero cost of the ENT-05 keccak swap; the keccak primitive (`hash2`, scratch-slot) is already the cheapest available. Empirical per-invocation benchmark is FIXTURE_COVERAGE_GAP_NOTED; the −689 byte delta corroborates the net-negative bytecode direction.

## Commit-Message-Ready Summary Block

```
Gas delta:      Per-roll runtime ~net-flat to ~+15-25 gas (hash2 keccak
                slightly dearer than the 3-op xorshift it replaces; offset
                partly by 3 dropped emit-value MULs). Deliberate, accepted,
                near-zero cost of the ENT-05 keccak swap — hash2 (scratch-
                slot) is the cheapest keccak primitive available. Empirical
                per-invocation benchmark: FIXTURE_COVERAGE_GAP_NOTED — no
                deterministic 5%-branch far-future _jackpotTicketRoll harness
                exists; analytical worst-case load-bearing per
                feedback_gas_worst_case.md + Phase 266/275/276 precedent.
Bytecode delta: -689 bytes deployed (DegenerusGameJackpotModule
                24,657 -> 23,968). EntropyLib + DegenerusGameStorage:
                0 deployed delta (entropyStep removal surfaces in
                JackpotModule; _queueLootboxTickets was already dead-code-
                eliminated). NET-NEGATIVE per JPT-CLEAN-06.
Storage:        byte-identical to v39 baseline 6a7455d1 per
                278-01-STORAGE-LAYOUT-DIFF.md PASS verdict.
```
