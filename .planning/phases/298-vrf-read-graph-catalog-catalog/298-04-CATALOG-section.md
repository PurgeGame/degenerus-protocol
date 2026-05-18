# §4 — DecimatorModule.runTerminalDecimatorJackpot (file:line 755)

**Consumer entry:** `contracts/modules/DegenerusGameDecimatorModule.sol:755`
**Signature:** `function runTerminalDecimatorJackpot(uint256 poolWei, uint24 lvl, uint256 rngWord) external returns (uint256 returnAmountWei)`
**Access guard:** `msg.sender != ContractAddresses.GAME` revert (self-call via `DegenerusGame.runTerminalDecimatorJackpot` at `DegenerusGame.sol:1142` → delegatecall).
**Caller chain:** `_handleGameOverPath` (`AdvanceModule.sol:522`) → `_gameOverEntropy` writes `rngWordByDay[day]` (`AdvanceModule.sol:1271`/`1841`) → multi-tx ticket drain (`STAGE_TICKETS_WORKING` re-entries) → `handleGameOverDrain` (`GameOverModule.sol:79`) → sets `gameOver=true` at line 139 → calls `runTerminalDecimatorJackpot` at line 168 with `rngWord = rngWordByDay[day]`.

## CAT-01 (§A) — Traced function set

Backward-trace from `runTerminalDecimatorJackpot` (`DecimatorModule.sol:755`); resolution code path includes ONLY pure/view helpers it invokes — `runTerminalDecimatorJackpot` itself is a single function with no internal cross-call beyond pure helpers + one mapping read.

| # | Function | File:line | Reached from | Notes |
|---|---|---|---|---|
| 1 | `runTerminalDecimatorJackpot` | `DegenerusGameDecimatorModule.sol:755` | entry | consumer root |
| 2 | `_decWinningSubbucket` | `DegenerusGameDecimatorModule.sol:422` | :773 (loop) | `private pure` — `keccak256(entropy, denom) % denom` |
| 3 | `_packDecWinningSubbucket` | `DegenerusGameDecimatorModule.sol:436` | :774 (loop) | `private pure` — bit-pack into uint64 |
| 4 | (transitive) `keccak256(abi.encode(lvl, denom, winningSub))` | `DegenerusGameDecimatorModule.sol:780` | inline | bucket-key derivation |

**Helpers are `pure`** — no SLOADs inside `_decWinningSubbucket` / `_packDecWinningSubbucket`. The only stateful interaction in the consumer is the SSTORE/SLOAD set enumerated in §B.

**Explicit-enumeration discipline** per `feedback_verify_call_graph_against_source.md`: confirmed by grep of `runTerminalDecimatorJackpot` body lines 755-803 — no `IDegenerusGame(...)`, no `delegatecall`, no module crosscall; no internal helper invocations other than the two pure functions above; no library call other than `keccak256`. The function body fits in <50 LoC, fully inlined here.

**Write-only ops (NOT participating SLOADs but recorded for SLOAD-table completeness):** §B lists every load operation; §B-W (auxiliary) lists every store in the consumer body for cross-check against `feedback_rng_window_storage_read_freshness.md` write-then-read freshness.

## CAT-02 (§B) — SLOAD table

Every SLOAD reached during `runTerminalDecimatorJackpot` execution, per F-41-02/03 enumeration discipline. Inline assembly slot directives + raw `sstore` grep returned zero hits in DecimatorModule (confirmed via `grep -n "assembly\|slot:" contracts/modules/DegenerusGameDecimatorModule.sol`).

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-1 | `ContractAddresses.GAME` | `DecimatorModule.sol:760` | `msg.sender != ContractAddresses.GAME` access guard | NO | `ContractAddresses.GAME` is a `library` constant resolved at compile time (`contracts/ContractAddresses.sol`); no SLOAD. Access guard outcome does not influence VRF-derived output — only governs reach. |
| B-2 | `lastTerminalDecClaimRound.lvl` | `DecimatorModule.sol:763` | double-resolution short-circuit (`if (lastTerminalDecClaimRound.lvl == lvl) return poolWei;`) | NO | Written ONLY by `runTerminalDecimatorJackpot` itself (lines 798-800; see §C-2). Default value zero; non-zero indicates prior terminal resolution. Short-circuit returns `poolWei` unchanged before any RNG-derived output is produced. Outcome (taken/not-taken) is a deterministic function of prior calls to the same EXEMPT-VRFCALLBACK / EXEMPT-ADVANCEGAME path; no external entry mutates it. Hence does not contribute participating entropy. |
| B-3 | `terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, denom, winningSub))]` | `DecimatorModule.sol:781` (inside denom 2..12 loop) | accumulates `totalWinnerBurn` (line 783); used as denominator in pro-rata share at `:847` / `:875` claim time | **YES** | — |

**Auxiliary §B-W — SSTOREs inside the consumer body (cross-check, not classified):**

| # | Slot | Write-site (file:line) | Notes |
|---|---|---|---|
| B-W1 | `decBucketOffsetPacked[lvl]` | `DecimatorModule.sol:795` | post-RNG snapshot of winning-subbucket map for terminal `lvl`; written here, read at claim time (`:839`, `:867`). Not a participating SLOAD (no read of this slot inside `runTerminalDecimatorJackpot`). |
| B-W2 | `lastTerminalDecClaimRound.lvl/.poolWei/.totalBurn` | `DecimatorModule.sol:798-800` | post-RNG snapshot; written here, read at claim time. Not a participating SLOAD. |

## CAT-03 (§C) — Writer enumeration for participating slots

Single participating slot from §B: **`terminalDecBucketBurnTotal[bucketKey]`** (mapping declared at `DegenerusGameStorage.sol:1560`: `mapping(bytes32 => uint256) internal terminalDecBucketBurnTotal`). Exhaustive `grep -rn "terminalDecBucketBurnTotal" contracts/ --include="*.sol"` returns exactly two source hits:

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|---|
| C-1 | `terminalDecBucketBurnTotal[bucketKey]` | `DegenerusGameDecimatorModule.recordTerminalDecBurn` | `DegenerusGameDecimatorModule.sol:731` (`terminalDecBucketBurnTotal[bucketKey] += weightedAmount`) | `BurnieCoin.terminalDecimatorBurn` (`BurnieCoin.sol:634` external, EOA-callable) → `degenerusGame.recordTerminalDecBurn` (`BurnieCoin.sol:653`) → `DegenerusGame.recordTerminalDecBurn` (`DegenerusGame.sol:1116`, msg.sender==COIN guard) → delegatecall DecimatorModule. | Write-then-read participation: the `bucketKey` here is `keccak256(abi.encode(lvl, e.bucket, e.subBucket))` where `e.bucket` comes from `_terminalDecBucket(playerActivityScore(player))` and `e.subBucket = _decSubbucketFor(player, lvl, bucket) = keccak256(player, lvl, bucket) % bucket`. Attacker chooses `player` via CREATE2/EOA grind to match any winning subbucket once `rngWord` is known. |
| C-2 | `terminalDecBucketBurnTotal[bucketKey]` | `DegenerusGameDecimatorModule.runTerminalDecimatorJackpot` | — | — | **NO writer** — only read site for this slot is line 781. The consumer itself does not write `terminalDecBucketBurnTotal`; the slot is read-only inside `runTerminalDecimatorJackpot`. |

**OZ-inherited writers check:** `terminalDecBucketBurnTotal` is a private mapping in `DegenerusGameStorage`; no OZ inheritance (ERC20/ERC721 transfer/transferFrom/approve/_mint/_burn) writes this slot. Confirmed via storage-layout review (slot owned by app-state contract, not a token).

**Admin/owner writer check:** Zero hits — `grep -n "onlyOwner\|onlyAdmin" contracts/modules/DegenerusGameDecimatorModule.sol` returns empty. No admin path writes `terminalDecBucketBurnTotal`.

**Constructor/initializer writer check:** Mapping default zero; no constructor write of `terminalDecBucketBurnTotal`. Not applicable.

**Inline-assembly raw-sstore check:** `grep -rn "assembly { sstore\|assembly {sstore\|slot:" contracts/ --include="*.sol"` returns zero hits in DecimatorModule / BurnieCoin / Storage paths for this slot. Not applicable.

**Single writer-callsite resolved: C-1 only.** Proceeds to §D verdict matrix as one row.

## CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. **NO `SAFE_BY_DESIGN`** per milestone-goal prohibition.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `terminalDecBucketBurnTotal[bucketKey]` | `DegenerusGameDecimatorModule.recordTerminalDecBurn` | `:731` (via `BurnieCoin.terminalDecimatorBurn` at `BurnieCoin.sol:634`) | NO — `terminalDecimatorBurn` is an external EOA-callable function on BurnieCoin; reach is the EOA-caller stack, NOT `advanceGame()` / VRF coordinator callback / `retryLootboxRng()`. | **VIOLATION** |

**Reach-stack derivation for D-1:**

- `BurnieCoin.terminalDecimatorBurn` external entry point: `msg.sender` is the EOA / external contract; gate is `terminalDecWindow.open == (!gameOver && !lastPurchaseDay)`.
- Across the multi-tx game-over window: after TX A writes `rngWordByDay[day]` via `_applyDailyRng` (`AdvanceModule.sol:1841`) — but BEFORE TX N reaches `handleGameOverDrain` (which is what flips `gameOver=true` at `GameOverModule.sol:139` and then calls the consumer at `:168`) — the global state is `rngWordByDay[day] != 0` (RNG word publicly readable) AND `gameOver == false` (terminal burn window OPEN). Multi-tx gap is forced by `STAGE_TICKETS_WORKING` early returns in `_handleGameOverPath` (`AdvanceModule.sol:596`, `:615`) when ticket queue exceeds single-tx gas.
- Within this multi-tx gap: attacker reads `rngWordByDay[day]`, computes `_decWinningSubbucket(rngWord, denom) = keccak256(rngWord, denom) % denom` for denom 2..12 (function is `pure`, fully predictable from published `rngWord`), then grinds a CREATE2 contract / fresh EOA address `player` such that `_decSubbucketFor(player, lvl, bucket) = keccak256(player, lvl, bucket) % bucket` lands in a winning subbucket. Calls `terminalDecimatorBurn(player_or_self, amount)` — `terminalDecWindow.open == true`, no `rngLockedFlag` gate exists on `recordTerminalDecBurn`, no `gameOver` gate, no `rngRequestTime` gate — `terminalDecBucketBurnTotal[winning_bucketKey] += weightedAmount` succeeds, pre-funding a winning entry.
- Mid-window write is consumed at TX N when `runTerminalDecimatorJackpot` reads `terminalDecBucketBurnTotal[bucketKey]` at `:781`: attacker's post-RNG burn now contributes to `totalWinnerBurn` and inflates the pro-rata claim payable to the grinded address.
- Window minimum guard: `daysRemaining > 7` (`:676` `if (daysRemaining <= 7) revert TerminalDecDeadlinePassed();`). Liveness-triggered game-over fires at `psd + 120` death-clock (level >= 10) OR via inactivity, and inactivity-triggered game-over CAN fire well before `psd + 113`, leaving `daysRemaining > 7` and the attack window OPEN. Even at psd+113 exactly, ≥ 1 day of attack window remains. Across `lvl == 0` the death clock is `psd + 365`, widening the window substantially.

D-1 is the sole non-EXEMPT writer-callsite tuple for the single participating slot. No SAFE_BY_DESIGN escape per milestone-goal prose.

## CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Recommended tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-1: `recordTerminalDecBurn` writes `terminalDecBucketBurnTotal` after rngWord published, before `gameOver=true` | **(a)** | Gate `recordTerminalDecBurn` on `rngWordByDay[day]==0` so window closes at RNG publish |

**Rationale expansion (out-of-table for traceability; the 80-char cell above is the verdict-matrix entry):** Tactic (a) `rngLockedFlag-gated revert` is the structurally minimal fix: introduce a revert in `recordTerminalDecBurn` (or in `BurnieCoin.terminalDecimatorBurn` via a view query) once the day's `rngWordByDay[day] != 0` AND a game-over path is in progress. Mirrors Phase 290 MINTCLN pattern at `DegenerusGameMintModule.sol:1221` (`if (cachedJpFlag && rngLockedFlag) {...}`). Tactic (b) snapshot/anchor is rejected: terminal-decimator burn-totals are aggregates, not per-day snapshots; snapshotting at game-over kickoff would require freezing across the multi-tx ticket-drain window, which is structurally the same as gating. Tactic (c) pre-lock reorder is rejected: there is no `advanceGame()`-internal reorder that closes the window, because the multi-tx STAGE_TICKETS_WORKING split is unavoidable for queue-exhaustion. Tactic (d) immutable is rejected: `terminalDecBucketBurnTotal` is an aggregate keyed on `bucketKey` that legitimately accrues throughout the level (cannot be made immutable). Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md` discipline.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside `runTerminalDecimatorJackpot` enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`.
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point is the SSTORE at `AdvanceModule.sol:1841` (`rngWordByDay[day] = finalWord`); attacker reachability of writers between that moment and the consumer read at `DecimatorModule.sol:781` was the gating analysis.
- **Verdicts:** 1 SLOAD reached / 1 participating / 1 writer-callsite / 1 VIOLATION / 0 EXEMPT (none of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` apply).
- **Scope:** zero `contracts/` + zero `test/` mutations per D-43N-AUDIT-ONLY-01.
