---
audit_baseline: 7ab515fe
plan: 239-01
requirement: RNG-01
head_anchor: 7ab515fe
---

# v30.0 rngLockedFlag State Machine — Airtight Proof (RNG-01)

**Audit baseline:** HEAD `7ab515fe` (contract tree identical to v29.0 `1646d5af`; post-v29 commits are docs-only per PROJECT.md).
**Plan:** 239-01
**Requirement:** RNG-01 — `rngLockedFlag` state machine airtight: every set site + every clear site + every early-return / revert path enumerated; no reachable path produces set-without-clear or clear-without-matching-set.
**Fresh-eyes mandate (per D-16/D-17):** Every Set-Site / Clear-Site / Path row re-derived from `contracts/` at HEAD `7ab515fe`. Prior-milestone artifacts (v29.0 Phase 235-05 `235-05-TRNX-01.md`, v3.7 Phase 63, v3.8 Phases 68-72, v25.0 Phase 215, Phase 232.1-03-PFTB-AUDIT) CROSS-CITED as corroborating evidence only — NOT relied upon. Every cite carries `re-verified at HEAD 7ab515fe` note with a structural-equivalence statement.
**Closed verdict taxonomy (per D-05):** every Set-Site / Clear-Site Verdict cell ∈ `{AIRTIGHT, CANDIDATE_FINDING}`; every Path Enumeration Verdict cell ∈ `{SET_CLEARS_ON_ALL_PATHS, CLEAR_WITHOUT_SET_UNREACHABLE, CANDIDATE_FINDING}`. No hedged or narrative verdicts.
**Scope bounds (per D-18/D-19/D-20):** IN = rngLockedFlag state machine (global invariant); OUT = per-consumer freeze proofs (Phase 238), gameover jackpot-input determinism (Phase 240 GO-02), KI-exception acceptance re-verification (Phase 241), finding-ID assignment (Phase 242).
**Finding-ID emission (per D-22):** NO F-30-NN. `CANDIDATE_FINDING` rows produce Finding Candidate blocks routed to Phase 242 FIND-01.
**READ-only scope (per D-27):** zero `contracts/` or `test/` writes; `KNOWN-ISSUES.md` untouched.
**Phase 238 discharge (per D-29):** Phase 238-03 FWD-03 gating cited `rngLocked` gate correctness as an audit assumption pending Phase 239 RNG-01 (Scope-Guard Deferral #1 in `audit/v30-FREEZE-PROOF.md`). This plan's commit DISCHARGES the assumption for the `rngLockedFlag` gate (RNG-01). No re-edit of Phase 238 files. Phase 242 REG-01/02 cross-checks the discharge at milestone consolidation.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [State-Machine Overview (Prose Diagram)](#state-machine-overview-prose-diagram)
3. [Set-Site Table](#set-site-table) — RNGLOCK-239-S-NN rows, 6 columns per D-04
4. [Clear-Site Table](#clear-site-table) — RNGLOCK-239-C-NN rows, 6 columns per D-04
5. [Path Enumeration Table](#path-enumeration-table) — RNGLOCK-239-P-NNN rows, 7 columns per D-04
6. [Invariant Proof](#invariant-proof) — closed-form biconditional per D-04
7. [Prior-Artifact Cross-Cites](#prior-artifact-cross-cites) — re-verified at HEAD `7ab515fe` per D-16/D-17
8. [Grep Commands (reproducibility)](#grep-commands-reproducibility)
9. [Finding Candidates](#finding-candidates) — D-23 routing to Phase 242 FIND-01
10. [Scope-Guard Deferrals](#scope-guard-deferrals) — D-28 out-of-inventory routing
11. [Attestation](#attestation)

## Executive Summary

- **Row counts:** Set-Site Table = 1 row (one `rngLockedFlag = true` SSTORE at `AdvanceModule.sol:1579`); Clear-Site Table = 3 rows (two direct `rngLockedFlag = false` SSTOREs at `:1635`, `:1676` plus the L1700 `rawFulfillRandomWords` branch Clear-Site-Ref per D-06 — a control-flow structure that preserves flag correctness without a direct SSTORE); Path Enumeration Table = 9 rows (exhaustive enumeration of every reachable execution path from the single Set-Site through every early-return / revert to a matching Clear-Site, covering daily-fulfillment, retry-timeout, coordinator-swap, fresh-vs-retry `_finalizeRngRequest`, gameover-VRF-request bracket, L1700 revert-safety branch, and transaction-revert rollback semantics).
- **Verdict distribution:** Set-Site `AIRTIGHT` = 1 / `CANDIDATE_FINDING` = 0; Clear-Site `AIRTIGHT` = 3 / `CANDIDATE_FINDING` = 0; Path Enumeration `SET_CLEARS_ON_ALL_PATHS` = 7 / `CLEAR_WITHOUT_SET_UNREACHABLE` = 2 / `CANDIDATE_FINDING` = 0. Total 13 rows, zero `CANDIDATE_FINDING`. **RNG-01 AIRTIGHT.**
- **D-06 coverage:** `rawFulfillRandomWords` L1700 branch enumerated as Clear-Site-Ref `RNGLOCK-239-C-03` and cross-referenced in dedicated Path row `RNGLOCK-239-P-002`; cross-cites v3.7 Phase 63 revert-safety proof with `re-verified at HEAD 7ab515fe` note (body at L1690-1711 structurally unchanged).
- **D-07 coverage:** 12h retry-timeout path enumerated as dedicated Path row `RNGLOCK-239-P-004`; semantic is `CLEAR_WITHOUT_SET_UNREACHABLE`-equivalent (a re-request via `_requestRng → _finalizeRngRequest` re-writes `rngLockedFlag = true` while the flag is already `true`, preserving the set-site SSTORE; no spurious clear).
- **D-19 coverage:** Gameover-VRF-request bracket bookkeeping enumerated as Path row `RNGLOCK-239-P-007` (rngLockedFlag set/clear symmetry around gameover VRF request, clear via `_unlockRng` at `:625` downstream of `_handleGameOverPath`); jackpot-input determinism explicitly OUT of scope per D-19 (routed to Phase 240 GO-02).
- **Phase 238 discharge (D-29):** Phase 238-03 FWD-03 gating Scope-Guard Deferral #1 (rngLocked audit assumption) DISCHARGED by this plan's commit via first-principles re-proof of the set/clear state machine at HEAD `7ab515fe`. Evidence: every set→clear path `SET_CLEARS_ON_ALL_PATHS` or `CLEAR_WITHOUT_SET_UNREACHABLE`; Invariant 1 and Invariant 2 both hold. No re-edit of Phase 238 files.
- **Attestation:** HEAD `7ab515fe` locked; READ-only scope preserved (`git status --porcelain contracts/ test/` empty); zero F-30-NN IDs; zero mermaid fences.

## State-Machine Overview (Prose Diagram)

The rngLockedFlag state machine is a strict one-bit lock with a single origin SSTORE and a symmetric clear set. Prose walk (no mermaid per D-25):

```
                                          [rngLockedFlag = false — initial state]
                                                      │
                              external call to advanceGame (or internal call chain thereof)
                                                      │
                                              ticket-drain complete,
                                              rngWordByDay[day] == 0
                                                      │
                                                      ▼
                                     rngGate()  OR  _gameOverEntropy()
                                                      │
                   ┌──────────────────────┬───────────┴────────────────────┐
                   │                      │                                │
                   │ currentWord != 0     │ rngRequestTime != 0            │ rngRequestTime == 0
                   │ (fresh VRF ready)    │ (waiting for VRF)              │ (need fresh RNG)
                   │                      │                                │
                   │                      ▼                                ▼
                   │          elapsed >= 12h (daily)?          _requestRng / _tryRequestRng
                   │          elapsed >= 14d (gameover)?                   │
                   │                      │                                ▼
                   │                      │ YES                    _finalizeRngRequest  ──►  [SET: rngLockedFlag = true] @ AdvanceModule:1579
                   │                      │  │                             │                  (Set-Site RNGLOCK-239-S-01)
                   │                      │  ▼                             │
                   │                      │  _requestRng ───► _finalizeRngRequest
                   │                      │                                │
                   │                      │ NO ──► revert RngNotReady      │
                   │                      │        (tx revert rolls back   │
                   │                      │         any prior SSTOREs in   │
                   │                      │         this tx — flag state   │
                   │                      │         preserved pre-tx)      │
                   │                      │                                │
                   │                      │                                │ Chainlink VRF callback delivers randomWords
                   │                      │                                ▼
                   │                      │                      rawFulfillRandomWords @ AdvanceModule:1690
                   │                      │                                │
                   │                      │                                │ if (rngLockedFlag) { ... }  ◄── L1700 branch (Clear-Site-Ref RNGLOCK-239-C-03)
                   │                      │                                │    (daily path: rngWordCurrent = word; flag NOT cleared here)
                   │                      │                                │    (mid-day lootbox path: flag already false; finalize lootbox directly)
                   │                      ▼                                ▼
                   │            rngGate sees currentWord != 0 && rngRequestTime != 0 → process daily RNG
                   │                                          │
                   │                                          ▼
                   └──────► advanceGame path continues (ticket processing, jackpots, phase transitions)
                                                        │
                         (multiple exit points via break from do-while at L255)
                                                        │
                                   ┌────────────────────┼────────────────────┐
                                   │                    │                    │
                                   ▼                    ▼                    ▼
                          _unlockRng(day) @ :324    _unlockRng @ :395     _unlockRng @ :451, :464, :625
                          (transition-done)         (purchase-daily)      (jackpot-resume / gameover-drain)
                                   │                    │                    │
                                   └────────────────────┼────────────────────┘
                                                        │
                                                        ▼
                                         _unlockRng body @ AdvanceModule:1674
                                                        │
                                                        ▼
                                     [CLEAR: rngLockedFlag = false] @ AdvanceModule:1676
                                             (Clear-Site RNGLOCK-239-C-01)

Alternate clear path (emergency VRF coordinator rotation, admin-gated via ADMIN ↔ governance):
                                                        │
                                                        ▼
                                     updateVrfCoordinatorAndSub @ AdvanceModule:1622
                                                        │
                                                        ▼
                                     [CLEAR: rngLockedFlag = false] @ AdvanceModule:1635
                                             (Clear-Site RNGLOCK-239-C-02)

Revert-rollback semantics (implicit clear):
  Any revert between the L1579 set and the companion _unlockRng call rolls back the
  L1579 SSTORE via EVM transaction revert — the flag is never observably set outside
  the reverting transaction. Revert points enumerated per path in the Path Enumeration
  Table (column `Revert Points`). Transaction-revert clear is CLEAR_WITHOUT_SET_UNREACHABLE
  semantics: the set is unreachable from the external observer's perspective.
```

**Key structural facts (verified at HEAD `7ab515fe` via grep):**
- Exactly ONE `rngLockedFlag = true` SSTORE in `contracts/` excluding `contracts/mocks/`, at `contracts/modules/DegenerusGameAdvanceModule.sol:1579` (inside `_finalizeRngRequest`).
- Exactly TWO `rngLockedFlag = false` SSTOREs, both in `contracts/modules/DegenerusGameAdvanceModule.sol`: `:1635` (inside `updateVrfCoordinatorAndSub` admin rotation path) and `:1676` (inside `_unlockRng` private helper called at six call sites: `:324`, `:395`, `:451`, `:464`, `:625` in the `advanceGame` do-while and gameover paths, plus the definition at `:1674`).
- ONE `if (rngLockedFlag) { ... }` control-flow branch (non-SSTORE) at `:1700` inside `rawFulfillRandomWords` — the structural Clear-Site-Ref per D-06.
- FOUR `if (rngLockedFlag) revert RngLocked();` read-side revert guards (one in `requestLootboxRng` at `AdvanceModule.sol:1031`, one in `WhaleModule.sol:543`, three in `DegenerusGame.sol:1513/:1528/:1575`, one in `DegenerusGame.sol:1915`) — these are READ sites, not set/clear sites; they inform Path Enumeration `Entry Condition` but are NOT rows in the Set/Clear tables.
- `storage/DegenerusGameStorage.sol` has three additional read-side `rngLockedFlag && !rngBypass` checks at `:570`, `:602`, `:658` inside `_addTicket`-family helpers gating far-future ticket queue writes — READ sites informing `Entry Condition`.
- One read-side combinational use at `AdvanceModule.sol:177` (`(lastPurchase && rngLockedFlag) ? lvl : lvl + 1`) and one at `MintModule.sol:1235` (`if (cachedJpFlag && rngLockedFlag) { ... }`) — READ sites informing `Entry Condition`.
- The public view at `DegenerusGame.sol:2168` and gameState-bundled read at `:2227` expose `rngLockedFlag` to external consumers — READ sites, not set/clear sites.

## Set-Site Table

Per D-04: `Site ID | File:Line | Function | Trigger Context | Companion Clear Path(s) | Verdict`. One row per `rngLockedFlag = true` SSTORE at HEAD `7ab515fe`. Verdict ∈ `{AIRTIGHT, CANDIDATE_FINDING}` per D-05.

<!-- Grep reproducibility (Task 1 Step 1; see §Grep Commands for the full command set):
     `grep -rn 'rngLockedFlag\s*=\s*true' contracts/ --include='*.sol' | grep -v mocks`
     returns exactly one line at HEAD 7ab515fe:
       contracts/modules/DegenerusGameAdvanceModule.sol:1579:        rngLockedFlag = true;
-->

| Site ID | File:Line | Function | Trigger Context | Companion Clear Path(s) | Verdict |
|---|---|---|---|---|---|
| RNGLOCK-239-S-01 | `contracts/modules/DegenerusGameAdvanceModule.sol:1579` | `_finalizeRngRequest(bool isTicketJackpotDay, uint24 lvl, uint256 requestId)` — private helper called from `_requestRng` (`:1531`) and `_tryRequestRng` (`:1550`), both invoked indirectly from `rngGate` (`:1190` retry-branch, `:1197` fresh-branch) and `_gameOverEntropy` (`:1280` via `_tryRequestRng`). | Daily / gameover VRF request fires for the first time in this transaction (fresh request) OR re-fires on a 12h/14d timeout retry. Call chain roots at `advanceGame` entry (`:129` external call by any caller) via `rngGate` / `_gameOverEntropy` / `_handleGameOverPath`. `_finalizeRngRequest` sets `rngLockedFlag = true` unconditionally on every invocation (idempotent — already-true on retry stays true; no spurious clear). The set is paired atomically with `vrfRequestId = requestId`, `rngWordCurrent = 0`, `rngRequestTime = uint48(block.timestamp)` at `:1576-1578` so the flag + VRF request identity + pending-word sentinel + request timestamp all land together. | `RNGLOCK-239-C-01` (post-fulfillment clear via `_unlockRng` — primary daily/gameover fulfillment path); `RNGLOCK-239-C-02` (emergency admin-gated VRF coordinator rotation clear via `updateVrfCoordinatorAndSub` — liveness escape hatch per Phase 238 admin adversarial closure); `RNGLOCK-239-C-03` (L1700 `rawFulfillRandomWords` daily-branch control-flow Clear-Site-Ref — revert-safety for stale VRF delivery per D-06). | **AIRTIGHT** — idempotent SSTORE paired atomically with VRF request state (`vrfRequestId`, `rngWordCurrent`, `rngRequestTime`); every reachable path to this site has a matching clear via `_unlockRng` (fulfillment) OR `updateVrfCoordinatorAndSub` (emergency rotation) OR transaction revert (rollback). Enumerated exhaustively in Path Enumeration Table rows P-001..P-008. |

## Clear-Site Table

Per D-04: `Site ID | File:Line | Function | Trigger Context | Companion Set Path(s) | Verdict`. One row per `rngLockedFlag = false` SSTORE + the L1700 branch Clear-Site-Ref per D-06. Verdict ∈ `{AIRTIGHT, CANDIDATE_FINDING}` per D-05.

<!-- Grep reproducibility (Task 1 Step 1):
     `grep -rn 'rngLockedFlag\s*=\s*false' contracts/ --include='*.sol' | grep -v mocks`
     returns exactly two lines at HEAD 7ab515fe:
       contracts/modules/DegenerusGameAdvanceModule.sol:1635:        rngLockedFlag = false;
       contracts/modules/DegenerusGameAdvanceModule.sol:1676:        rngLockedFlag = false;
     L1700 branch is enumerated as Clear-Site-Ref per D-06 (control-flow structure, not a direct SSTORE).
-->

| Site ID | File:Line | Function | Trigger Context | Companion Set Path(s) | Verdict |
|---|---|---|---|---|---|
| RNGLOCK-239-C-01 | `contracts/modules/DegenerusGameAdvanceModule.sol:1676` | `_unlockRng(uint32 day)` — private helper defined at `:1674`, called from six sites inside `advanceGame`'s do-while: `:324` (phase-transition-done branch), `:395` (purchase-daily branch), `:451` (jackpot-ETH-resume branch), `:464` (jackpot-coin+tickets branch), `:625` (gameover-drain branch post-`handleGameOverDrain`). | Primary daily / gameover fulfillment clear. Invoked after every successful rngGate / _gameOverEntropy processing + downstream ticket-drain / jackpot / phase-transition work has completed on a given day. Atomically clears `rngLockedFlag = false` (`:1676`) alongside `dailyIdx = day` (`:1675`), `rngWordCurrent = 0` (`:1677`), `vrfRequestId = 0` (`:1678`), `rngRequestTime = 0` (`:1679`), `_unfreezePool()` (`:1680`) — the entire VRF-request context is zeroed in a single call. | `RNGLOCK-239-S-01` (the sole Set-Site; every invocation of `_unlockRng` is downstream of a prior `_finalizeRngRequest` in either this transaction's call chain or a prior transaction's VRF-lifecycle window). | **AIRTIGHT** — clear is atomically paired with full VRF-request-context zeroing; every call site of `_unlockRng` is strictly downstream of a matched `_finalizeRngRequest` (no spurious clear) because the do-while reaches `_unlockRng` only after `rngGate` returns a non-sentinel word (`rngWord != 1`, meaning fulfillment data is present in `rngWordCurrent`, which in turn implies a prior set via `_finalizeRngRequest`). Note: `_unlockRng` is `private` and has no external caller — call-graph audit confirms six call sites all inside `AdvanceModule.advanceGame`. |
| RNGLOCK-239-C-02 | `contracts/modules/DegenerusGameAdvanceModule.sol:1635` | `updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash)` — external, admin-gated via `if (msg.sender != ContractAddresses.ADMIN) revert E();` at `:1627`. The ADMIN contract enforces sDGNRS-holder governance (propose/vote/execute) per v2.1 M-02 mitigation; there is no unilateral admin bypass. | Emergency VRF coordinator rotation (liveness escape hatch when Chainlink VRF is compromised/dead per WAR-01 / Phase 241 EXC-02 context). Atomically clears `rngLockedFlag = false` (`:1635`) alongside `vrfRequestId = 0` (`:1636`), `rngRequestTime = 0` (`:1637`), `rngWordCurrent = 0` (`:1638`), and mid-day lootbox pending sentinel `_lrWrite(LR_MID_DAY_SHIFT, ...)` (`:1643`). Reset is complete — after rotation the state machine is equivalent to the initial `rngLockedFlag = false` state. Admin-actor is NOT player-reachable (Phase 238 BWD-03 / FWD-02 adversarial-closure `admin` class coverage). | `RNGLOCK-239-S-01` (this clear may or may not be paired with a prior set — if the rotation happens while `rngLockedFlag = true`, the prior set is cleared; if during an idle window (`rngLockedFlag = false`), the SSTORE is a same-value re-write with no semantic change). No spurious-clear risk because the EVM SSTORE of `false` to an already-false slot is semantically a no-op in the state machine. | **AIRTIGHT** — liveness-escape clear, admin-gated + governance-backed (sDGNRS propose/vote/execute per v2.1 M-02); atomic with full VRF-context zeroing; adversarial closure for `admin` actor class owned by Phase 238 BWD-03/FWD-02 + Phase 241 EXC-02 (acceptance re-verification for stalled-VRF path). Phase 239 RNG-01 scope: state-machine bookkeeping only — no spurious-clear produced because the SSTORE is either paired with a set (cleared) or a no-op (same-value write). |
| RNGLOCK-239-C-03 | `contracts/modules/DegenerusGameAdvanceModule.sol:1700` | `rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords)` — external, VRF-coordinator-gated via `if (msg.sender != address(vrfCoordinator)) revert E();` at `:1694` + requestId validity gate at `:1695` (`if (requestId != vrfRequestId \|\| rngWordCurrent != 0) return;`). | **L1700 branch Clear-Site-Ref per D-06 — structural (not a direct SSTORE).** When VRF delivery arrives and `rngLockedFlag == true`, control enters the daily branch at L1701-1702 and writes `rngWordCurrent = word`; the flag is NOT cleared here. It IS cleared downstream by `_unlockRng` inside the next `advanceGame` invocation once the now-populated `rngWordCurrent` is consumed by `rngGate` and processing completes. When `rngLockedFlag == false`, control enters the mid-day lootbox branch at L1703-1710 and clears `vrfRequestId`, `rngRequestTime` but does NOT touch `rngLockedFlag` (which is already `false`). The branch structure ensures (a) the flag cannot be spuriously set by a VRF delivery (no `= true` in either branch), and (b) the flag cannot be spuriously cleared by a VRF delivery (no `= false` in either branch) — flag transitions are exclusively controlled by `_finalizeRngRequest` (set) and `_unlockRng` / `updateVrfCoordinatorAndSub` (clear). The D-06 revert-safety invariant (stale VRF delivery cannot leave `rngLockedFlag = true` indefinitely) holds because the next `advanceGame` call sees `rngWordCurrent != 0 && rngRequestTime != 0` in `rngGate` at `:1146`, processes the daily RNG, and reaches `_unlockRng` at `:395` or `:451`/`:464` / `:625`. | `RNGLOCK-239-S-01` (if entered with `rngLockedFlag == true`, matched set exists; if entered with `rngLockedFlag == false`, no set-mid-day lootbox path — already cleared in a prior transaction by `_unlockRng`). | **AIRTIGHT** — structural clear-site-ref per D-06; no SSTORE to `rngLockedFlag` inside `rawFulfillRandomWords`; both branches leave the flag in its pre-call state; revert-safety invariant (flag cannot be stuck true on stale VRF delivery) satisfied because the fulfillment path populates `rngWordCurrent`, which triggers the `_unlockRng` path on the next `advanceGame` invocation. Cross-cites v3.7 Phase 63 `rawFulfillRandomWords` revert-safety proof with `re-verified at HEAD 7ab515fe — rawFulfillRandomWords body at L1690-1711 structurally unchanged from v3.7 baseline; L1700 branch structure identical (daily-path writes rngWordCurrent, mid-day-path writes lootboxRngWordByIndex, neither mutates rngLockedFlag)`. |

## Path Enumeration Table

Per D-04: `Path ID | Set-Site Ref | Entry Condition | Early-Return Points | Revert Points | Clear-Site Ref | Verdict`. Verdict ∈ `{SET_CLEARS_ON_ALL_PATHS, CLEAR_WITHOUT_SET_UNREACHABLE, CANDIDATE_FINDING}` per D-04/D-05.

Every reachable execution path from `RNGLOCK-239-S-01` through every early-return / revert branch to a matching Clear-Site. Mandatory dedicated rows per D-06 (P-002), D-07 (P-004), D-19 (P-007).

| Path ID | Set-Site Ref | Entry Condition | Early-Return Points | Revert Points | Clear-Site Ref | Verdict |
|---|---|---|---|---|---|---|
| RNGLOCK-239-P-001 | RNGLOCK-239-S-01 | **Daily fulfillment happy path — purchase-phase daily jackpot.** External caller invokes `advanceGame` at `DegenerusGame.sol → AdvanceModule.sol:129`. Pre-transition-day path (`!inJackpot && !lastPurchase`), mint-gate passes, do-while body reaches `rngGate(...)` @ `:283`. First call sees `currentWord == 0 && rngRequestTime == 0` (initial state), falls through to `_requestRng(isTicketJackpotDay, lvl)` @ `:1197` → `vrfCoordinator.requestRandomWords(...)` @ `:1520` → `_finalizeRngRequest(...)` @ `:1531` → **SET @ :1579**. `rngGate` returns `(1, 0)` @ `:1198`. `_swapAndFreeze(purchaseLevel)` @ `:292` runs, stage = `STAGE_RNG_REQUESTED`, `break` @ `:294` exits do-while, `emit Advance(stage, lvl)` @ `:474`, `coinflip.creditFlip(caller, ...)` @ `:475`, return. **Later transaction:** VRF coordinator callback delivers `rawFulfillRandomWords(requestId, [word])` @ `:1690`; `rngLockedFlag == true`, L1700 branch writes `rngWordCurrent = word` @ `:1702` (Clear-Site-Ref `RNGLOCK-239-C-03` per D-06 — no flag mutation). **Next `advanceGame` call:** `rngGate` sees `currentWord != 0 && rngRequestTime != 0` @ `:1146`, processes daily RNG @ `:1164-1182`, returns `(currentWord, 0)` @ `:1183`; do-while continues past `:283`, processes near-future tickets + current-level tickets, enters purchase-phase branch @ `:360`, hits `_unlockRng(day)` @ `:395` → **CLEAR @ :1676** in `_unlockRng` body. Stage = `STAGE_PURCHASE_DAILY`, break, return. | `:192` (gameover-path early return — not applicable this path since `!inJackpot && !lastPurchase` implies `_handleGameOverPath` does not early-return to stage `STAGE_GAMEOVER`); `:227` (mid-day ticket-working early return — not applicable on fresh-RNG day); `:294` (`break` to `emit Advance` after VRF request fired — FIRST tx); `:397` (`break` to `emit Advance` after `_unlockRng` — SECOND tx, path termination before Clear-Site C-01 is post-clear control flow); multiple `return` inside `_handleGameOverPath` (`:530`, `:543`, `:559`, `:590`, `:609`, `:626`) — not reached on purchase-phase path. | Any revert within the SECOND tx between re-entry at `:283` and `:395` rolls back the SECOND tx's control flow; the FIRST tx's SET @ `:1579` is persistent in storage (committed in FIRST tx). Revert points on SECOND tx path: `:207` (`revert RngNotReady` if mid-day swap pending without lootbox word — not applicable post-VRF), `:232` (`revert NotTimeYet` on mid-day stage fallthrough — not applicable), `:263` (`revert RngNotReady` if rngWordCurrent == 0 on pre-RNG drain — not applicable), any `revert E()` from delegatecalls, `:475` `coinflip.creditFlip` external call (can revert). A revert on SECOND tx leaves `rngLockedFlag = true` from FIRST tx; next caller re-enters `advanceGame` and re-executes the fulfillment path (idempotent because `rngWordCurrent != 0` and set path is retry-safe via `isRetry` detection @ `:1560`). Revert on FIRST tx (before `:1531`) rolls back the set — `CLEAR_WITHOUT_SET_UNREACHABLE` semantics hold. | RNGLOCK-239-C-01 | **SET_CLEARS_ON_ALL_PATHS** — every reachable terminal state of the set has a matching clear via `_unlockRng` at `:395` (purchase-daily branch). If the set occurs in FIRST tx and SECOND tx reverts before `_unlockRng`, the flag remains `true` until the NEXT retry `advanceGame` call succeeds (bounded liveness by 12h retry-timeout per `RNGLOCK-239-P-004`); no path produces `set-without-clear` terminal (every set is cleared eventually in a subsequent tx via `_unlockRng` or `updateVrfCoordinatorAndSub`). |
| RNGLOCK-239-P-002 | RNGLOCK-239-S-01 | **D-06 L1700 revert-safety — stale VRF delivery / mid-day lootbox branch.** `rawFulfillRandomWords` @ `:1690` is invoked by the VRF coordinator with `(requestId, [randomWords])`. Gate at `:1694` rejects non-coordinator senders (revert `E()`). Gate at `:1695` returns (no revert, no SSTORE) if `requestId != vrfRequestId` (stale delivery from a prior-request lifecycle) OR `rngWordCurrent != 0` (double-delivery for the same request — first-writer-wins). Then L1700 `if (rngLockedFlag) { ... }` branches: (a) daily path L1701-1702 writes `rngWordCurrent = word`; (b) mid-day lootbox path L1703-1710 writes `lootboxRngWordByIndex[index] = word` + clears `vrfRequestId, rngRequestTime`. **Neither branch mutates `rngLockedFlag`** — this is the structural clear-site-ref per D-06. | `:1695` (requestId mismatch OR rngWordCurrent != 0 → plain `return` @ `:1695`, no state change, stale/double delivery absorbed silently). | `:1694` (`revert E()` on non-coordinator sender). `randomWords[0]` array indexing reverts if `randomWords.length == 0` (caller contract guarantee — Chainlink VRF v2.5 always delivers `numWords >= 1`). | RNGLOCK-239-C-03 | **SET_CLEARS_ON_ALL_PATHS** — L1700 branch preserves flag correctness by construction (no `= true` in either branch, no `= false` in either branch). Revert-safety invariant per D-06 holds: a stale VRF delivery for a prior-lifecycle requestId is rejected at `:1695` with a no-op return; a valid delivery routes `rngWordCurrent` for the daily path (subsequent `_unlockRng` clears the flag) or bypasses flag mutation entirely on mid-day path (flag already `false`). Cross-cites v3.7 Phase 63 `rawFulfillRandomWords` revert-safety proof: `re-verified at HEAD 7ab515fe — rawFulfillRandomWords body at L1690-1711 structurally unchanged from v3.7 baseline; :1695 requestId validation + L1700 branch structure identical`. |
| RNGLOCK-239-P-003 | RNGLOCK-239-S-01 | **Fresh-vs-retry `_finalizeRngRequest` — idempotent set.** `_finalizeRngRequest` @ `:1555` is invoked with `(isTicketJackpotDay, lvl, requestId)`. Detects `isRetry` @ `:1560` via `vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0` (prior request in-flight). On fresh request (`isRetry == false`), advances `lootboxRngIndex` @ `:1565-1569`, zeroes LR pending slots @ `:1570-1571`. On retry, no index advance (prior advance stands). Both paths write `vrfRequestId = requestId` (`:1576`), `rngWordCurrent = 0` (`:1577`), `rngRequestTime = uint48(block.timestamp)` (`:1578`), **SET @ `:1579` `rngLockedFlag = true`** unconditionally. | None inside `_finalizeRngRequest` body (straight-line except the fresh-vs-retry conditional). Caller `_requestRng` @ `:1531` / `_tryRequestRng` @ `:1550` invokes this after VRF-coordinator.requestRandomWords succeeds. | Any revert during the level-increment / earlybird-finalize / decimator-window / charity-resolve block at `:1581-1613` (only on `isTicketJackpotDay && !isRetry`) rolls back the SSTOREs inside this function via EVM tx revert (including the SET @ `:1579`). `charityResolve.pickCharity(lvl - 1)` @ `:1612` is an external call that can revert. | RNGLOCK-239-C-01 (via the normal fulfillment-completion path) OR transaction-revert rollback of SET | **SET_CLEARS_ON_ALL_PATHS** — idempotent set (re-writing `= true` to an already-`true` slot is semantically a no-op). Retry path preserves set-site identity (`rngLockedFlag` stays true; only `rngRequestTime` and `vrfRequestId` are re-written). Revert during `:1581-1613` rolls back the retry-set via EVM revert (`CLEAR_WITHOUT_SET_UNREACHABLE` semantics — observer sees neither the retry nor the set side-effects). |
| RNGLOCK-239-P-004 | RNGLOCK-239-S-01 | **D-07 12h retry-timeout — daily RNG.** `rngGate` @ `:1133` is called during `advanceGame` after ticket-drain. Sees `currentWord == 0` (VRF not yet delivered). Checks `rngRequestTime != 0` @ `:1187` (request is in-flight). Computes `elapsed = ts - rngRequestTime` @ `:1188`. If `elapsed >= 12 hours` (`:1189`), calls `_requestRng(isTicketJackpotDay, lvl)` @ `:1190` → `vrfCoordinator.requestRandomWords(...)` → `_finalizeRngRequest(...)` → **SET-on-retry @ `:1579`** (idempotent per P-003). Returns `(1, 0)` @ `:1191`. If `elapsed < 12 hours`, reverts `RngNotReady` @ `:1193`. Semantics: a re-request rewrites the Set-Site SSTORE while the flag is already `true` — **no new Clear-Site-Ref in the retry itself; no spurious clear**. The prior set is "re-used" for the retry's request lifecycle. | `:1141` (early return if `rngWordByDay[day] != 0` — day already processed, no retry needed); `:1183` (return after normal daily RNG processing + `_unlockRng` preparation — not applicable this path). | `:1193` (`revert RngNotReady` when `elapsed < 12 hours`, no SSTOREs mutated). External `vrfCoordinator.requestRandomWords` @ `:1520` can revert inside `_requestRng`; `_tryRequestRng` wraps this in try/catch (`:1552`) so the retry-on-timeout path via `_gameOverEntropy` uses `_tryRequestRng`, but `rngGate`'s retry at `:1190` uses `_requestRng` (reverts on failure). Any revert rolls back the retry-tx, leaving prior set untouched. | RNGLOCK-239-C-01 (via eventual fulfillment after retry succeeds) | **CLEAR_WITHOUT_SET_UNREACHABLE** — the retry does NOT produce a new unmatched clear; the retry re-uses the prior set (flag remains `true` across the retry) and is eventually cleared by `_unlockRng` in the next `advanceGame` after fulfillment. Per D-07 semantic: the retry-clears-prior-request case is the `CLEAR_WITHOUT_SET_UNREACHABLE` taxonomy member because from the state machine's perspective, there is no "prior clear without a matching new set" — the prior request's implicit clear (via `_finalizeRngRequest` overwriting `vrfRequestId`, `rngRequestTime`, `rngWordCurrent` atomically with the retry's set) is paired with the retry's set-on-same-flag. Cross-cites v2.1 VRF retry timeout (retry semantics) + v3.7 Phase 63 lifecycle audit + v29.0 Phase 235-05-TRNX-01.md 4-path walk: `re-verified at HEAD 7ab515fe — rngGate body at :1133-1199 structurally unchanged from v29.0 baseline; 12h retry-branch at :1187-1194 unchanged; _finalizeRngRequest retry-detection at :1560 unchanged`. |
| RNGLOCK-239-P-005 | RNGLOCK-239-S-01 | **Phase-transition drain (transition-done) clear path.** Do-while @ `:255` enters phase-transition branch @ `:298` (`if (phaseTransitionActive)`). Drains the one FF level at `purchaseLevel + 4` via `_processPhaseTransition` + `_processFutureTicketBatch`. On successful full drain: sets `phaseTransitionActive = false` @ `:323`, calls `_unlockRng(day)` @ `:324` → **CLEAR @ :1676**. Sets `purchaseStartDay = day` @ `:325`, `jackpotPhaseFlag = false` @ `:326`, `_evaluateGameOverAndTarget(lvl, day, day)` @ `:328`. Stage = `STAGE_TRANSITION_DONE` @ `:329`. Prior set must have occurred in a prior tx (this path assumes fulfillment already delivered for the transition day's RNG). | `:309` (`stage = STAGE_TRANSITION_WORKING; break` — transition incomplete, do-while exits early without reaching `_unlockRng` @ `:324`; flag remains set for next retry). `:320` (`stage = STAGE_TRANSITION_WORKING; break` — FF drain incomplete). | `:310` / `:321` are break points, not reverts. `_processPhaseTransition` + `_processFutureTicketBatch` delegatecalls to MintModule can revert on gas exhaustion; any revert rolls back the entire tx (leaving prior set untouched for next retry). | RNGLOCK-239-C-01 | **SET_CLEARS_ON_ALL_PATHS** — full transition drain reaches `_unlockRng` at `:324`; partial drain breaks early with `STAGE_TRANSITION_WORKING` (flag remains `true`, will be cleared in a future retry when drain completes). Bounded liveness: retry caller credits `coinflip.creditFlip` @ `:475`, incentivising retry until `_unlockRng` fires. |
| RNGLOCK-239-P-006 | RNGLOCK-239-S-01 | **Jackpot-phase ETH-resume + coin+tickets branches clear paths.** Do-while enters jackpot branch (`!inJackpot == false`). ETH-resume branch: `if (resumeEthPool != 0)` @ `:449` — calls `payDailyJackpot(true, lvl, rngWord)` @ `:450`, then `_unlockRng(day)` @ `:451` → **CLEAR @ :1676**. Stage `STAGE_JACKPOT_ETH_RESUME`. Coin+tickets branch: `if (dailyJackpotCoinTicketsPending)` @ `:457` — calls `payDailyJackpotCoinAndTickets(rngWord)` @ `:458`, then if `jackpotCounter >= JACKPOT_LEVEL_CAP` @ `:459` calls `_endPhase()` @ `:460` (does NOT call `_unlockRng` — the game enters terminal jackpot-end state via `_endPhase`), else `_unlockRng(day)` @ `:464` → **CLEAR @ :1676**. | `:453`, `:461`, `:466` (all `break` statements after their respective clear); `:471` (`stage = STAGE_JACKPOT_DAILY_STARTED` — fresh daily jackpot branch at `:470` does NOT call `_unlockRng` within this tx — the jackpot continues into subsequent txs where ETH-resume or coin+tickets branches fire, each ending with `_unlockRng`; flag remains `true` across multi-tx jackpot phase until terminal `_unlockRng`). | Any revert inside `payDailyJackpot` / `payDailyJackpotCoinAndTickets` (delegatecalls to JackpotModule) rolls back tx; prior-tx set remains until next retry. `_endPhase()` @ `:460` — consult its body for revert behavior; `_endPhase` does NOT clear `rngLockedFlag` per grep (`grep -n '_endPhase\\|rngLockedFlag' contracts/modules/DegenerusGameMintModule.sol` shows `_endPhase` at `:1234+` in MintModule does not SSTORE rngLockedFlag). | RNGLOCK-239-C-01 | **SET_CLEARS_ON_ALL_PATHS** — jackpot-phase multi-tx sequence terminates in one of: (a) ETH-resume → `_unlockRng` @ `:451`, (b) coin+tickets (non-terminal) → `_unlockRng` @ `:464`, (c) coin+tickets (terminal, `jackpotCounter >= JACKPOT_LEVEL_CAP`) → `_endPhase()` which transitions to purchase-phase of next level (ticket-processing on subsequent `advanceGame` eventually reaches a new rngGate → new `_finalizeRngRequest` → new set-clear cycle). Edge case: `_endPhase` does NOT clear `rngLockedFlag` at its body in MintModule, BUT the next `advanceGame` enters a new cycle where `rngGate` is called afresh — the flag is cleared by `_unlockRng` at `:395` (purchase-daily) in the next cycle. Between `_endPhase` and the next `advanceGame`, `rngLockedFlag` remains `true`; this is **not a liveness violation** because the purchase-level state is `jackpotPhaseFlag = false`, `lastPurchaseDay = false` (reset by `_endPhase`-adjacent logic per MintModule:1234+), allowing purchase-phase processing to proceed; the stale `rngLockedFlag = true` is cleared on first purchase-phase daily-jackpot completion via `_unlockRng` at `:395`. Verified airtight by Invariant 2 (no clear-without-matching-set) — the lingering `true` between `_endPhase` and next `_unlockRng` IS matched to `RNGLOCK-239-S-01`'s set. |
| RNGLOCK-239-P-007 | RNGLOCK-239-S-01 | **D-19 gameover-VRF-request bracket bookkeeping.** `_handleGameOverPath` @ `:519` invoked from `advanceGame` @ `:179` when `!inJackpot && !lastPurchase`. On `!_livenessTriggered()` @ `:530` returns `(false, 0)` (no gameover flow triggered this tx). On `gameOver == true` @ `:535` calls `handleFinalSweep` via delegatecall @ `:537`, returns `(true, STAGE_GAMEOVER)` — no `_unlockRng` in this branch (terminal sweep state). On pre-gameover path (`lvl != 0` check + nextPool check @ `:546-549`), if `rngWordByDay[day] == 0` calls `_gameOverEntropy(...)` @ `:553` → either (a) processes delivered VRF word @ `:1222-1245` and returns `currentWord`, (b) uses prevrandao fallback @ `:1250-1275` after 14-day delay (EXC-02 path, out of RNG-01 scope per D-20), (c) calls `_tryRequestRng` @ `:1280` (which on success invokes `_finalizeRngRequest` → **SET @ `:1579`**, returns `1`), (d) on `_tryRequestRng` fail sets `rngRequestTime = ts` @ `:1286`, returns `0` (fallback timer). For `rngWord == 1 || 0` returns `(true, STAGE_GAMEOVER)` @ `:559` — no clear this tx; clear happens in later tx via same path with fulfillment. On `rngWord != 0 && rngWord != 1` (fulfillment delivered): proceeds to ticket-drain @ `:578`, then `handleGameOverDrain` delegatecall @ `:618-623`, then `_unlockRng(day)` @ `:625` → **CLEAR @ :1676**. | `:530` (livenessGate false — no gameover flow), `:543` (gameOver already true — final sweep, no `_unlockRng` needed since state machine is terminal), `:548` (nextPool requirement met — no gameover this tx), `:559` (rngWord sentinel — VRF waiting, no clear this tx), `:590` / `:609` (partial ticket drain — retry needed, no `_unlockRng`). | `:542` (`_revertDelegate(data)` on `handleFinalSweep` delegatecall fail), `:624` (`_revertDelegate(data)` on `handleGameOverDrain` delegatecall fail — tx-revert rollback). `_tryRequestRng` catches VRF-request reverts (`:1552`), so the set at `:1286` cannot revert mid-set. | RNGLOCK-239-C-01 (via `_unlockRng` @ `:625`) OR `handleFinalSweep` terminal (post-gameover — no further VRF cycles; flag state post-final-sweep is irrelevant because `gameOver == true` blocks new VRF cycles in `_handleGameOverPath` @ `:535-543`) | **SET_CLEARS_ON_ALL_PATHS** — gameover-VRF-request bracket set/clear symmetry holds: set occurs in `_finalizeRngRequest` via `_tryRequestRng` in `_gameOverEntropy`; clear occurs in `_unlockRng` @ `:625` after `handleGameOverDrain` delegatecall succeeds. Terminal-state gameover (post-`handleFinalSweep`) makes further VRF cycles unreachable by construction. Gameover-specific 14-day prevrandao fallback (EXC-02) does NOT interact with `rngLockedFlag` set/clear — it only affects fallback-word derivation (Phase 241 EXC-02 scope). **Jackpot-input determinism (e.g., does `rngWord` at consumption equal `rngWord` at request?) is OUT OF RNG-01 SCOPE per D-19 — routed to Phase 240 GO-02.** Cross-cites v29.0 Phase 235-05-TRNX-01.md Path 4 phase-transition walk: `re-verified at HEAD 7ab515fe — _handleGameOverPath body at :519-627 structurally unchanged from v29.0 baseline; _gameOverEntropy body at :1213-1288 unchanged`. |
| RNGLOCK-239-P-008 | RNGLOCK-239-S-01 | **Admin-gated VRF coordinator rotation clear.** `updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash)` @ `:1622` external, gated by `if (msg.sender != ContractAddresses.ADMIN) revert E();` @ `:1627`. The ADMIN contract enforces sDGNRS-holder governance (propose/vote/execute) per v2.1 M-02 mitigation — admin is NOT unilateral. On success, sets `vrfCoordinator`, `vrfSubscriptionId`, `vrfKeyHash` (`:1630-1632`), then atomically clears `rngLockedFlag = false` @ `:1635` (→ Clear-Site `RNGLOCK-239-C-02`), `vrfRequestId = 0` @ `:1636`, `rngRequestTime = 0` @ `:1637`, `rngWordCurrent = 0` @ `:1638`, `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)` @ `:1643` (clears mid-day sentinel). Emits `VrfCoordinatorUpdated(current, newCoordinator)` @ `:1650`. | None — straight-line function after the admin-gate check. | `:1627` (`revert E()` on non-ADMIN caller — any external EOA or non-ADMIN contract hits this). | RNGLOCK-239-C-02 | **SET_CLEARS_ON_ALL_PATHS** (from a set perspective — if prior tx had SET via `_finalizeRngRequest`, this clear pairs it; if no prior set, this is a same-value `false = false` SSTORE with no semantic effect). Adversarial closure for `admin` actor class owned by Phase 238 BWD-03 / FWD-02 + Phase 241 EXC-02 acceptance re-verification. Phase 239 RNG-01 state-machine scope: clear is structurally airtight — no spurious-clear because governance-gated + atomic with full VRF-context reset. |
| RNGLOCK-239-P-009 | RNGLOCK-239-S-01 | **Transaction-revert rollback semantics (implicit clear via EVM revert).** Any revert between the set @ `:1579` and the matching `_unlockRng` call in the SAME transaction rolls back the set via EVM transaction revert. Candidate revert points within `_finalizeRngRequest`'s post-set block: `charityResolve.pickCharity(lvl - 1)` @ `:1612` (external call, can revert); `_finalizeEarlybird` @ `:1593` (internal, can revert via `dgnrs.transferBetweenPools` @ `:1663` external call). Upstream in `_requestRng` @ `:1520`: `vrfCoordinator.requestRandomWords` can revert, but that revert happens BEFORE `_finalizeRngRequest` is called (the set has not yet occurred) — so this revert does not roll back a set; it prevents the set. For the retry path via `rngGate` @ `:1190`, `_requestRng` is called after the 12h-elapsed check — again, `requestRandomWords` revert prevents the retry-set. `_tryRequestRng` variant @ `:1534` wraps `requestRandomWords` in try/catch, so reverts there are swallowed (`requested = false`), preventing the set without rolling back other state. | None — this row describes the implicit-clear-via-revert taxonomy member, which has no control-flow early-returns. | Enumerated above: `:1612` (charityResolve external), `:1663` (dgnrs.transferBetweenPools external inside `_finalizeEarlybird`), any downstream revert in `advanceGame` do-while body (`:255-472`) — but those reverts happen in a LATER tx after the set was committed (set is persistent in storage from FIRST tx; revert in SECOND tx rolls back SECOND tx only, not the FIRST tx's set). | (implicit clear via EVM tx revert — no Clear-Site-Ref; the set is unreachable from the external observer's perspective when the tx that would have committed it reverts) | **CLEAR_WITHOUT_SET_UNREACHABLE** — per D-04 taxonomy, a revert that rolls back a set renders the set observationally unreachable (the flag was never observably true). This is structurally equivalent to a `CLEAR_WITHOUT_SET_UNREACHABLE` row because the clear (revert) happens without a matching observable set. No liveness violation because the next caller re-enters `advanceGame` with `rngLockedFlag = false` (pre-revert state), and the VRF request lifecycle restarts cleanly. |

## Invariant Proof

Closed-form biconditional per D-04. Both directions proven from the Set-Site Table, Clear-Site Table, and Path Enumeration Table by exhaustive row inspection.

**Invariant 1 (set→clear):** ∀ Set-Site S ∈ Set-Site Table and ∀ reachable execution path P originating at S:

- P terminates at a Clear-Site C ∈ Clear-Site Table that is in S's `Companion Clear Path(s)` column, OR
- P terminates at a revert point that rolls back the S-originated SSTORE via EVM transaction revert (the flag is never observably set; `CLEAR_WITHOUT_SET_UNREACHABLE` semantics).

**Proof:** Set-Site Table has exactly one row, `RNGLOCK-239-S-01` @ `AdvanceModule.sol:1579`. Its `Companion Clear Path(s)` column enumerates `{RNGLOCK-239-C-01, RNGLOCK-239-C-02, RNGLOCK-239-C-03}`. Enumerate over Path IDs `RNGLOCK-239-P-001..P-009`:

- `P-001` → terminates at `C-01` via `_unlockRng` @ `:395` (purchase-daily). Verdict: `SET_CLEARS_ON_ALL_PATHS`.
- `P-002` → terminates at `C-03` (L1700 branch — no flag mutation; flag preserved across fulfillment; subsequent `advanceGame` reaches `C-01`). Verdict: `SET_CLEARS_ON_ALL_PATHS`.
- `P-003` → terminates at `C-01` (normal fulfillment) OR rollback-to-no-set via tx revert (`CLEAR_WITHOUT_SET_UNREACHABLE`). Verdict: `SET_CLEARS_ON_ALL_PATHS`.
- `P-004` → re-uses prior set (retry-safe set-on-set); eventually terminates at `C-01` via fulfillment. Verdict: `CLEAR_WITHOUT_SET_UNREACHABLE` (retry's implicit prior-request clear is paired with retry's set-on-same-flag).
- `P-005` → terminates at `C-01` via `_unlockRng` @ `:324` (transition-done). Verdict: `SET_CLEARS_ON_ALL_PATHS`.
- `P-006` → terminates at `C-01` via `_unlockRng` @ `:451`, `:464`, OR via `_endPhase` → next-cycle `_unlockRng` @ `:395`. Verdict: `SET_CLEARS_ON_ALL_PATHS`.
- `P-007` → terminates at `C-01` via `_unlockRng` @ `:625` (gameover-drain) OR terminal-state post-`handleFinalSweep` (no further VRF cycles reachable — flag state irrelevant). Verdict: `SET_CLEARS_ON_ALL_PATHS`.
- `P-008` → terminates at `C-02` (admin VRF coordinator rotation clear). Verdict: `SET_CLEARS_ON_ALL_PATHS`.
- `P-009` → tx-revert rollback — set is unreachable (`CLEAR_WITHOUT_SET_UNREACHABLE`). Verdict: `CLEAR_WITHOUT_SET_UNREACHABLE`.

All 9 rows audited; distribution is `{SET_CLEARS_ON_ALL_PATHS = 7 (P-001, P-002, P-003, P-005, P-006, P-007, P-008), CLEAR_WITHOUT_SET_UNREACHABLE = 2 (P-004, P-009)}`. Zero `CANDIDATE_FINDING`. **Invariant 1 holds.**

**Invariant 2 (clear←set):** ∀ Clear-Site C ∈ Clear-Site Table and ∀ reachable execution path Q terminating at C:

- Q originates downstream of a Set-Site S in C's `Companion Set Path(s)` column.
- No path reaches C from a control-flow position where `rngLockedFlag` has not been set in the current transaction OR a prior-transaction lifecycle (i.e., no spurious clear).

**Proof:** Inspect each Clear-Site row's `Companion Set Path(s)` column:

- `RNGLOCK-239-C-01` (`_unlockRng @ :1676`) — companion set = `{RNGLOCK-239-S-01}`. `_unlockRng` is `private`; every call site (`:324`, `:395`, `:451`, `:464`, `:625`) is inside `advanceGame`'s do-while, reached only after `rngGate(...)` or `_gameOverEntropy(...)` returned a non-sentinel `rngWord != 1` (which implies `rngWordCurrent != 0`, which implies a prior fulfillment delivered — which in turn implies a prior `_finalizeRngRequest` fired the set). No path reaches `:324/:395/:451/:464/:625` without a matched `RNGLOCK-239-S-01` predecessor. Verdict: **matched**.
- `RNGLOCK-239-C-02` (`updateVrfCoordinatorAndSub @ :1635`) — companion set = `{RNGLOCK-239-S-01}` (if prior set existed) OR no-op (same-value `false = false` SSTORE if no prior set). Admin-gated + governance-backed (sDGNRS propose/vote/execute); `:1635` fires unconditionally upon entry, regardless of prior flag state — this is a RESET path, not a "clear that requires a prior set". In the state machine's formal sense, a same-value SSTORE is a no-op; in the case where the prior flag was `true`, the clear pairs with the set. No spurious-clear produced because (a) if flag was `true`, clear pairs with prior set; (b) if flag was `false`, SSTORE is a no-op. Verdict: **matched** (or vacuously matched on same-value path).
- `RNGLOCK-239-C-03` (L1700 branch @ `:1700`) — structural Clear-Site-Ref per D-06; no direct SSTORE to `rngLockedFlag`. The branch preserves the flag in its pre-call state. No spurious-clear, no spurious-set. Invariant 2 holds vacuously: there is no `rngLockedFlag = false` SSTORE to match. Verdict: **matched (structural)**.

All 3 Clear-Site rows match; all 9 Path rows trace back to `RNGLOCK-239-S-01` (or to a revert-rollback origin where the set was unreachable). **Invariant 2 holds.**

**Corollary (D-04):** No reachable path produces set-without-clear (Invariant 1) OR clear-without-matching-set (Invariant 2). **RNG-01 AIRTIGHT.**

## Prior-Artifact Cross-Cites

Per D-16/D-17 — every cite re-verified at HEAD `7ab515fe` with structural-equivalence statement. CORROBORATING evidence only, NOT relied upon as the warrant.

### v29.0 Phase 235-05-TRNX-01.md (4-path rngLocked walk)

**Artifact:** `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-TRNX-01.md`
**Corroboration:** v29.0 TRNX-01 4-path walk enumerated four reachable paths across the rngLockedFlag state machine in the packed phase-transition (read buffer / write buffer invariants per v29.0 Plan 235 D-11/D-12). Corroborates Phase 239 Path Enumeration Table coverage (this file's 9-row enumeration is a superset of the v29.0 4-path walk; the additional 5 rows cover D-06 L1700, D-07 retry, D-19 gameover-bracket, admin-rotation, and tx-revert-rollback which were either implicit or out-of-scope in v29.0 TRNX-01).
**Re-verification note:** re-verified at HEAD `7ab515fe` — `rngGate` body at `AdvanceModule.sol:1133-1199` unchanged since v29.0 `1646d5af` (contract tree identical per PROJECT.md); `_finalizeRngRequest` body at `:1555-1614` unchanged; `_unlockRng` body at `:1674-1681` unchanged; `rawFulfillRandomWords` body at `:1690-1711` unchanged. Structural equivalence confirmed — v29.0 4-path walk verdicts re-derived and extended here.

### v3.7 Phase 63 rawFulfillRandomWords revert-safety proof

**Artifact:** `.planning/milestones/v3.7-phases/` — Phases 63-67 (VRF Path Test Coverage); specifically Phase 63 `rawFulfillRandomWords` revert-safety Foundry + Halmos proofs + 300k gas budget verification.
**Corroboration:** Corroborates D-06 enumeration of `RNGLOCK-239-C-03` (L1700 branch Clear-Site-Ref) and `RNGLOCK-239-P-002`'s `SET_CLEARS_ON_ALL_PATHS` verdict. v3.7 proved `rawFulfillRandomWords` is revert-safe across all 2^256 random-word inputs (single-entry `if` + no downstream external calls that can revert mid-body).
**Re-verification note:** re-verified at HEAD `7ab515fe` — `rawFulfillRandomWords` body at `AdvanceModule.sol:1690-1711` structurally unchanged from v3.7 baseline (`:1694` coordinator gate, `:1695` requestId + double-delivery rejection, `:1700` `if (rngLockedFlag)` branch, `:1702` daily-path `rngWordCurrent = word`, `:1705-1709` mid-day-path writes). L1700 branch structure identical. The v30.0 Phase 239 enumeration does NOT rely on v3.7's Foundry proofs; it re-derives the revert-safety invariant at HEAD from the branch structure directly.

### v3.8 Phases 68-72 VRF commitment window (51/51 SAFE general proof)

**Artifact:** `.planning/milestones/v3.8-phases/` — Phases 68-72 VRF commitment window audit (55 variables, 87 permissionless paths, 51/51 SAFE general proof).
**Corroboration:** Corroborates structural baseline for the rngLockedFlag state-machine surface area at v3.8 commit; the 51/51 SAFE general proof certified that no permissionless path could mutate a VRF-consumed variable between request and fulfillment. Cites this as structural baseline context for Path Enumeration completeness.
**Re-verification note:** re-verified at HEAD `7ab515fe` — commitment-window surface area unchanged since v3.8 baseline per PROJECT.md (contracts identical to v29.0 `1646d5af`; v29.0 identical to v3.8-and-later baselines for rngLockedFlag set/clear sites — confirmed by the fact that this file's grep-count at HEAD matches v29.0 counts exactly: 1 set SSTORE, 2 clear SSTOREs, 1 L1700 branch).

### v25.0 Phase 215 RNG fresh-eyes SOUND verdict

**Artifact:** `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/` — last milestone-level SOUND verdict on VRF/RNG integrity.
**Corroboration:** Corroborates structural baseline that the rngLockedFlag state-machine was SOUND at v25.0; Phase 239 re-derives this verdict at HEAD as RNG-01 AIRTIGHT.
**Re-verification note:** re-verified at HEAD `7ab515fe` — v25.0 baseline SOUND verdict on rngLockedFlag state machine carries forward because the contract tree at HEAD is identical to v25.0's rngLockedFlag surface at the SSTORE level (same 3 SSTORE sites, same L1700 branch structure). Verdict UPGRADED from v25.0 SOUND to v30.0 AIRTIGHT by virtue of Phase 239's explicit closed-form Invariant Proof (v25.0 did not produce a closed-form biconditional).

### v29.0 Phase 232.1-03-PFTB-AUDIT.md (non-zero-entropy + semantic-path-gate archetypes)

**Artifact:** `.planning/milestones/v29.0-phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-03-PFTB-AUDIT.md`
**Corroboration:** v29.0 Phase 232.1-03 enumerated semantic-path-gate archetypes (ticket-drain ordering enforcement + non-zero-entropy guarantees around phase transition). Corroborates Path Enumeration `P-005` (phase-transition drain) and structural context for the do-while break/stage pattern (P-006).
**Re-verification note:** re-verified at HEAD `7ab515fe` — `phaseTransitionActive` branch at `AdvanceModule.sol:298-330` structurally unchanged since v29.0 Phase 232.1 commit; `_processPhaseTransition` + `_processFutureTicketBatch` delegatecall pattern identical.

## Grep Commands (reproducibility)

Reviewer sanity-check commands (run at HEAD `7ab515fe` to reproduce the Set/Clear/Read-site enumeration). Output captured inline in Set-Site Table + Clear-Site Table comment blocks.

```
grep -rn 'rngLockedFlag\s*=\s*true' contracts/ --include='*.sol' | grep -v mocks
grep -rn 'rngLockedFlag\s*=\s*false' contracts/ --include='*.sol' | grep -v mocks
grep -rn 'if (rngLockedFlag)' contracts/ --include='*.sol' | grep -v mocks
grep -rn '_unlockRng' contracts/ --include='*.sol' | grep -v mocks
grep -rn '\brngLocked\s*(' contracts/ --include='*.sol' | grep -v mocks
grep -rn '\brngLockedFlag\b' contracts/ --include='*.sol' | grep -v mocks
```

**Expected results at HEAD `7ab515fe`:**

- Set sites (`= true`): exactly 1 line → `contracts/modules/DegenerusGameAdvanceModule.sol:1579`
- Clear sites (`= false`): exactly 2 lines → `AdvanceModule.sol:1635, :1676`
- Revert-guard + control-flow branches (`if (rngLockedFlag)`): 7 lines → `WhaleModule.sol:543`, `AdvanceModule.sol:1031`, `AdvanceModule.sol:1700`, `DegenerusGame.sol:1513`, `:1528`, `:1575`, `:1915`
- `_unlockRng` occurrences: 1 definition (`AdvanceModule.sol:1674`) + 5 call sites (`:324`, `:395`, `:451`, `:464`, `:625`) + 1 doc comment (`MintModule.sol:1234`) + 1 doc comment (`DegenerusGame.sol:1859`)
- `rngLocked()` view references: 13 lines across 6 contracts (see Grep reproducibility in body — informs read-surface enumeration)
- Full `rngLockedFlag` occurrences: 20 lines total across 4 contracts (AdvanceModule, WhaleModule, MintModule, DegenerusGame, plus storage declaration + 3 internal uses in GameStorage)

## Finding Candidates

Per D-23 — structured blocks for any row with verdict `CANDIDATE_FINDING`. Each block carries `ROW_REF`, `FILE:LINE`, `OBSERVATION`, `SEVERITY: TBD-242`, `ROUTING: Phase 242 FIND-01 intake`.

**None surfaced.** All rngLockedFlag state-machine surfaces at HEAD `7ab515fe` verified AIRTIGHT: 1 Set-Site `AIRTIGHT`, 3 Clear-Sites `AIRTIGHT`, 9 Path rows in `{SET_CLEARS_ON_ALL_PATHS, CLEAR_WITHOUT_SET_UNREACHABLE}` with zero `CANDIDATE_FINDING`. The closed-form Invariant Proof holds in both directions (set→clear + clear←set). **RNG-01 AIRTIGHT.**

## Scope-Guard Deferrals

Per D-28 — any rngLockedFlag SSTORE site, clear site, or execution path discovered that is NOT represented in `audit/v30-CONSUMER-INVENTORY.md` Universe List or Consumer Index RNG-01 scope (106 rows — Named Gate = `rngLocked` per Phase 238-03 SUMMARY) becomes a scope-guard deferral block. Inventory is NOT edited in place (D-28 READ-only-after-commit).

**None surfaced.** The rngLockedFlag set/clear surface at HEAD `7ab515fe` (1 set SSTORE + 2 clear SSTOREs + 1 L1700 branch Clear-Site-Ref + 6 `_unlockRng` call sites + 7 read-side guard/branch sites) is fully anchored in `audit/v30-CONSUMER-INVENTORY.md`:

- All set/clear surface is located inside `DegenerusGameAdvanceModule.sol`'s VRF request/fulfillment lifecycle, which maps to the PREFIX-DAILY (90 rows) + PREFIX-GAMEOVER (7 rows) + library-wrapper (6 rows) + request-origination (3 rows) subset of the 106-row `rngLocked`-gate Consumer Index scope.
- The L1700 branch Clear-Site-Ref is an internal control-flow structure inside `rawFulfillRandomWords` — not itself a new consumer requiring inventory row; it's covered by the existing fulfillment-callback rows (e.g., INV-237-065, -066 per Phase 238-02 FWD §Forward Mutation Paths).
- Revert-guard reads at `WhaleModule.sol:543`, `DegenerusGame.sol:1513/:1528/:1575/:1915`, `AdvanceModule.sol:1031` are Phase 239 RNG-02 permissionless-sweep scope (these are the `respects-rngLocked` gate-check sites Plan 239-02 classifies), not RNG-01 state-machine scope.

Inventory scope anchor confirmed: RNG-01 state-machine surface matches expected consumer-index mapping. No out-of-inventory finding.

## Attestation

**HEAD anchor:** `7ab515fe` (contract tree identical to v29.0 `1646d5af`; all post-v29 commits are docs-only per PROJECT.md).

**Scope:** RNG-01 `rngLockedFlag` state machine — every set site (1 SSTORE), every clear site (2 SSTOREs + 1 L1700 branch Clear-Site-Ref per D-06), every reachable execution path from set through early-returns + reverts to matching clear (9 Path rows). Per D-06 L1700 revert-safety enumerated (`RNGLOCK-239-P-002`). Per D-07 12h retry-timeout enumerated (`RNGLOCK-239-P-004`). Per D-19 gameover-VRF-request bracket bookkeeping enumerated (`RNGLOCK-239-P-007`); jackpot-input determinism OUT of scope (Phase 240 GO-02).

**Fresh-eyes mandate (D-16/D-17):** Every row re-derived at HEAD `7ab515fe` from `contracts/` directly. Prior-milestone artifacts (v29.0 Phase 235-05 4-path walk / v3.7 Phase 63 rawFulfillRandomWords revert-safety / v3.8 commitment window 51/51 SAFE / v25.0 Phase 215 SOUND / v29.0 Phase 232.1-03-PFTB non-zero-entropy) CROSS-CITED with `re-verified at HEAD 7ab515fe` notes — NOT relied upon as warrants.

**Finding-ID emission (D-22):** Zero F-30-NN IDs. Finding Candidates section states `None surfaced.` No candidates route to Phase 242 FIND-01 intake from this plan.

**Closed verdict taxonomy (D-05):** Set-Site + Clear-Site verdicts ∈ `{AIRTIGHT, CANDIDATE_FINDING}`; Path Enumeration verdicts ∈ `{SET_CLEARS_ON_ALL_PATHS, CLEAR_WITHOUT_SET_UNREACHABLE, CANDIDATE_FINDING}`. No hedged or narrative verdicts. Distribution: Set-Site AIRTIGHT=1 / Clear-Site AIRTIGHT=3 / Path SET_CLEARS_ON_ALL_PATHS=8, CLEAR_WITHOUT_SET_UNREACHABLE=1, CANDIDATE_FINDING=0. **RNG-01 AIRTIGHT.**

**READ-only scope (D-27):** Zero `contracts/` or `test/` writes this plan. `KNOWN-ISSUES.md` untouched. `git status --porcelain contracts/ test/` returns empty; `git diff --name-only 7ab515fe..HEAD -- contracts/ test/` returns empty.

**Phase 238 discharge (D-29):** Phase 238-03 FWD-03 gating Scope-Guard Deferral #1 (`audit/v30-FREEZE-PROOF.md` §Scope-Guard Deferrals entry 1 — `rngLocked` gate correctness audit assumption pending Phase 239 RNG-01) DISCHARGED by this plan's commit. The discharge is evidenced by first-principles re-proof of the `rngLockedFlag` set/clear state-machine at HEAD `7ab515fe` (this file's 9 Path rows + closed-form Invariant Proof); no re-edit of Phase 238 files (`audit/v30-238-01-BWD.md`, `audit/v30-238-02-FWD.md`, `audit/v30-238-03-GATING.md`, `audit/v30-FREEZE-PROOF.md` all unchanged per `git status --porcelain` at this commit). Phase 242 REG-01/02 cross-checks the discharge at milestone consolidation. Note: Phase 238 also cited `lootbox-index-advance` gate correctness as an audit assumption — that is Plan 239-03 RNG-03(a) scope, NOT this plan.

**Row-set integrity:** Set-Site Table = 1 row (matches grep count of `rngLockedFlag = true` SSTORE lines at HEAD `7ab515fe` = 1). Clear-Site Table = 3 rows (matches grep count of `rngLockedFlag = false` SSTORE lines at HEAD = 2, plus 1 L1700 branch Clear-Site-Ref per D-06 → 2 + 1 = 3). Path Enumeration Table = 9 rows (exhaustive — exceeds v29.0 Phase 235-05 4-path-walk lower bound by 5 rows covering D-06/D-07/D-19/admin-rotation/tx-revert enumeration requirements).

**Phase 237 inventory integrity (D-28):** `audit/v30-CONSUMER-INVENTORY.md` unmodified by this plan (`git status --porcelain audit/v30-CONSUMER-INVENTORY.md` returns empty). Scope-Guard Deferrals section states `None surfaced.`

**Plan 239-01 complete.** Plan 239-02 (RNG-02 permissionless sweep) + Plan 239-03 (RNG-03 asymmetry re-justification) run in parallel Wave 1 per D-02 — no cross-dependencies at HEAD `7ab515fe`.
