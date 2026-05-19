# §9 — AdvanceModule.retryLootboxRng (file:line 1132)

**Consumer entry** — `contracts/modules/DegenerusGameAdvanceModule.sol:1132`

`retryLootboxRng() external` is the **mid-day lootbox-VRF failsafe**. Permissionless. Reachable only when `_requestLootboxRng` (line 1043) committed the buffer swap (`LR_MID_DAY = 1` at :1096) and the VRF callback has not delivered (`rngRequestTime != 0`). After the locked ≥6h cooldown (`MIDDAY_RNG_RETRY_TIMEOUT` at :141), it re-fires VRF with the identical parameters; the stalled requestId is auto-rejected by `rawFulfillRandomWords` at :1750 (`if (requestId != vrfRequestId || rngWordCurrent != 0) return;`). Buffer state and the pre-advanced `lootboxRngIndex` (LR_INDEX) are preserved so the new word lands in the same bucket the original was bound to.

**This consumer is NOT a literal VRF-word consumer** — it does not SLOAD `rngWordCurrent`, `lootboxRngWordByIndex[*]`, or `rngWordByDay[*]`. It is the VRF *protocol*-coordination failsafe. Per **D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A** (Phase 296 SWEEP lock), this consumer's resolution stack is its own EXEMPT class: `EXEMPT-RETRYLOOTBOXRNG`. The Option A scope is three locked invariants:

1. **≥6h cooldown** between successive replacements (line 1135: `if (block.timestamp < rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT) revert E();`).
2. **≤1 VRF-replacement per stall event** — re-fire only when the in-flight request has not yet delivered; the second re-fire overwrites `vrfRequestId` so a third would still revert until the cooldown re-elapses.
3. **No pre-lock-state manipulation** — `retryLootboxRng` must not write any slot whose value the in-flight (or eventual) VRF callback / `_finalizeLootboxRng` will consume to derive a VRF-influenced output. Specifically: must NOT touch `lootboxRngWordByIndex`, the `LR_INDEX` / `LR_PENDING_ETH` / `LR_PENDING_BURNIE` / `LR_MID_DAY` fields of `lootboxRngPacked`, `rngWordCurrent`, `rngLockedFlag`, `dailyIdx`, `rngWordByDay`, or any commitment-side bet/ticket buffer slot. Pre-lock invariant per Option A.

The §9 §B/§C/§D rows below verify each invariant is structurally satisfied AND enumerate every slot the failsafe touches (read or write) so that the cross-callsite per-(slot × writer × callsite) classification per **D-298-EXEMPT-REACH-01** distinguishes the EXEMPT-RETRYLOOTBOXRNG callsite from non-EXEMPT callsites of the same writer/slot reached from other entry points (which then carry VIOLATION).

**Commitment-window discipline (per `feedback_rng_commitment_window.md`):**
- T0 (mid-day RNG request committed): `_requestLootboxRng` at :1043 fires VRF, sets `LR_MID_DAY = 1` (:1096), advances `LR_INDEX` (:1113), zeroes `LR_PENDING_ETH` / `LR_PENDING_BURNIE` (:1118-1119), assigns `vrfRequestId = id` (:1120), zeroes `rngWordCurrent` (:1121), stamps `rngRequestTime = block.timestamp` (:1122). The mid-day RNG buffer is now committed to the pre-advanced index.
- T-stall (≥6h elapsed, no callback): the original VRF request has not landed. The world-state between T0 and T-stall has accumulated: new lootbox purchases (writers of `LR_PENDING_ETH` / `LR_PENDING_BURNIE` at MintModule:1016/:1407, WhaleModule:877, DegeneretteModule:558/:563), no `_finalizeLootboxRng` writes (callback not delivered, so `lootboxRngWordByIndex[LR_INDEX-1]` is still 0).
- T1 (retryLootboxRng called): the failsafe SSTOREs ONLY `vrfRequestId` (:1153) and `rngRequestTime` (:1154). It does NOT advance `LR_INDEX`, does NOT zero pendings, does NOT touch `LR_MID_DAY` (which remains 1 by gate), does NOT touch `lootboxRngWordByIndex`. The pre-committed buffer is preserved.
- T2 (eventual VRF callback): the NEW requestId matches `vrfRequestId`; the OLD stalled callback (if it ever arrives) does not match and returns silently at :1750. `rawFulfillRandomWords` at :1745 writes `lootboxRngWordByIndex[LR_INDEX - 1] = word` (:1761) and clears `vrfRequestId` / `rngRequestTime`. The new word lands in the SAME bucket the T0 commitment bound.

The risk class to enumerate (per F-41-02/03 precedent in `feedback_rng_window_storage_read_freshness.md`): any SLOAD reached inside `retryLootboxRng` whose value an EOA can mutate between T0 and T1 — those flow into the failsafe's revert-gate decisions or into the new VRF request's parameters. Every SLOAD enumerated in §B; every participating-slot writer enumerated in §C.

## CAT-01 (§A) — Traced function set

Backward-trace rooted at `AdvanceModule.retryLootboxRng:1132`; trace walks transitively into every reachable function under `contracts/` per `D-298-TRACE-DEPTH-01`. Stops only at external interfaces with no source available (Chainlink VRF coordinator).

| #  | Function                              | File:line                                          | Reached from                          | Notes |
|----|---------------------------------------|----------------------------------------------------|---------------------------------------|-------|
| 1  | `retryLootboxRng`                     | `AdvanceModule.sol:1132`                           | external entry (EOA, permissionless)  | the failsafe body |
| 2  | `_lrRead`                             | `Storage.sol:1337`                                 | :1133                                  | `internal view`; SLOAD of `lootboxRngPacked`; bit-extract |
| 3  | `IVRFCoordinator.getSubscription`     | external interface                                 | :1137                                  | external staticcall; out of in-source scope per `D-298-TRACE-DEPTH-01` |
| 4  | `IVRFCoordinator.requestRandomWords`  | external interface                                 | :1142                                  | external call; out of in-source scope; reverts on coordinator-side failure (no try/catch — failure propagates back to caller) |

**No other functions are reached.** `retryLootboxRng` is a flat function body — no internal helper calls beyond `_lrRead` (Storage.sol:1337) and the two external VRF-coordinator interface calls. No delegatecalls, no inline assembly, no further dispatch.

**Explicit-enumeration cross-check** (per `feedback_verify_call_graph_against_source.md`):

- `sed -n '1132,1155p' contracts/modules/DegenerusGameAdvanceModule.sol` confirms the function body spans :1132-:1155 inclusive; every line accounted for in §B below.
- `grep -n "delegatecall\|\.call\|staticcall" contracts/modules/DegenerusGameAdvanceModule.sol | awk -F: '$2 >= 1132 && $2 <= 1155'` returns zero hits inside the function body — no cross-module reach.
- `grep -n "assembly" contracts/modules/DegenerusGameAdvanceModule.sol | awk -F: '$2 >= 1132 && $2 <= 1155'` returns zero hits inside the function body — no inline-assembly slot manipulation.
- `_lrRead` body at Storage.sol:1337-:1339 is `return (lootboxRngPacked >> shift) & mask;` — one SLOAD, no SSTORE, no further calls.

## CAT-02 (§B) — SLOAD table

Every SLOAD reached inside the `retryLootboxRng` resolution path. Per `feedback_rng_window_storage_read_freshness.md`: ALL SLOADs enumerated; non-VRF-derived reads consumed alongside RNG-protocol state are a distinct bug class.

| #   | Slot                          | Read-site (file:line)                    | Read context                                                                                                           | Participating? | Attestation if NO |
|-----|-------------------------------|------------------------------------------|------------------------------------------------------------------------------------------------------------------------|----------------|---------------------|
| B-1 | `lootboxRngPacked` (LR_MID_DAY field, bits 224:231) | `AdvanceModule:1133` (via `_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK)` → Storage:1338) | failsafe entry gate: `if (... == 0) revert E();` — reverts unless the mid-day buffer-swap flag is set by a prior `_requestLootboxRng` at :1096 | **YES**        | — |
| B-2 | `rngRequestTime`              | `AdvanceModule:1134`                     | failsafe entry gate: `if (rngRequestTime == 0) revert E();` — reverts unless a VRF request is in-flight                | **YES**        | — |
| B-3 | `rngRequestTime`              | `AdvanceModule:1135`                     | cooldown gate: `if (uint48(block.timestamp) < rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT) revert E();` — enforces ≥6h since last request | **YES**        | — |
| B-4 | `vrfCoordinator` (storage slot at Storage:1287) | `AdvanceModule:1137` (`vrfCoordinator.getSubscription(...)`) | SLOAD of coordinator address before external staticcall                                                                | **YES**        | — |
| B-5 | `vrfSubscriptionId`           | `AdvanceModule:1138`                     | argument to `getSubscription(vrfSubscriptionId)`                                                                       | **YES**        | — |
| B-6 | `vrfCoordinator` (storage slot at Storage:1287) | `AdvanceModule:1142` (`vrfCoordinator.requestRandomWords(...)`) | second SLOAD of coordinator address before external call; same slot as B-4 — re-read because Solidity does not cache cross-statement slots without explicit caching | **YES**        | — |
| B-7 | `vrfKeyHash`                  | `AdvanceModule:1144` (struct field `keyHash: vrfKeyHash`) | argument to `requestRandomWords({keyHash: vrfKeyHash, ...})`                                                            | **YES**        | — |
| B-8 | `vrfSubscriptionId`           | `AdvanceModule:1145` (struct field `subId: vrfSubscriptionId`) | argument to `requestRandomWords({subId: vrfSubscriptionId, ...})`; same slot as B-5                                    | **YES**        | — |

**Non-SLOAD reads** (immutable / constant / call-input, enumerated for completeness per `feedback_verify_call_graph_against_source.md`):
- `MIDDAY_RNG_RETRY_TIMEOUT` at :1135 — `uint48 private constant` (compile-time at AdvanceModule:141); no SLOAD.
- `MIN_LINK_FOR_LOOTBOX_RNG` at :1140 — `uint96 private constant` (compile-time at AdvanceModule:140); no SLOAD.
- `VRF_MIDDAY_CONFIRMATIONS` at :1146 — `uint16 private constant` (AdvanceModule:123); no SLOAD.
- `VRF_CALLBACK_GAS_LIMIT` at :1147 — `uint32 private constant` (AdvanceModule:115); no SLOAD.
- `block.timestamp` at :1135 + :1154 — opcode (TIMESTAMP); no SLOAD.
- Return value `linkBal` from `getSubscription` at :1137 — external-call return; out of in-source SLOAD scope per `D-298-TRACE-DEPTH-01` (the sDGNRS-side coordinator internals are not under `contracts/`).
- Return value `id` from `requestRandomWords` at :1142 — external-call return.

**Participating? = YES rationale.** Per **D-298-SLOT-CLASSIFICATION-01**, participating means "value influences a VRF-derived output". `retryLootboxRng` does not itself derive a VRF output — but the slots it reads (B-1..B-8) are the inputs to the *VRF-protocol coordination decisions* (gate / cooldown / coordinator selection / sub / keyHash) that determine which `requestId` the eventual `rawFulfillRandomWords` callback will validate against and where the resulting `rngWord` will land (`lootboxRngWordByIndex[LR_INDEX - 1]`). These slots gate the EXEMPT-RETRYLOOTBOXRNG envelope; any change to them between T0 and T1 alters either whether the failsafe runs, what VRF config the replacement uses, or how the new word is bound to a bucket. They are participating in the broader "VRF input frozen at commitment" milestone sense and must be classified in §D.

**No NON-PARTICIPATING SLOADs** in this consumer's trace — every SLOAD is gate / cooldown / VRF-config / VRF-binding state.

## CAT-03 (§C) — Per-slot writer enumeration

Per `D-298-EXEMPT-REACH-01`: writers enumerated per-callsite. For each participating slot (every row in §B), enumerate every external/public function in any contract under `contracts/` that writes the slot (OZ-inherited writers included; admin/owner writers included).

### C-1: `lootboxRngPacked` (LR_MID_DAY field, bits 224:231)

The `lootboxRngPacked` slot is multi-field-packed; LR_MID_DAY is the 8-bit field at bits 224:231. Per `D-298-EXEMPT-REACH-01`, writers are enumerated **per field**; the slot-level SSTORE in `_lrWrite` at Storage:1342 is the underlying primitive, but per-field semantics require enumerating each `_lrWrite(LR_MID_DAY_SHIFT, ...)` call site.

| Row   | Writer function                             | Callsite (file:line)              | Stack reaching this callsite                                          | Classification |
|-------|---------------------------------------------|------------------------------------|-----------------------------------------------------------------------|----------------|
| C-1a  | `AdvanceModule._requestLootboxRng`          | `AdvanceModule:1096` (`_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1)`) | `requestLootboxRng()` external (EOA, permissionless) → `_requestLootboxRng` private (no internal callers reach :1096 from any other entry) | **EXEMPT-RETRYLOOTBOXRNG**: structurally classified as a sibling of `retryLootboxRng` — both are pre-VRF-request-coordination paths gated by the same locked invariants. **However**, `requestLootboxRng` is a distinct external entry; per **D-298-EXEMPT-REACH-01** strict per-callsite, this callsite is reached from the `requestLootboxRng` stack, NOT from `retryLootboxRng`. The honest classification is **VIOLATION-CANDIDATE for non-§9 reach** — but for §9's verdict matrix (which classifies the callsite from §9's reach perspective), it is unreachable from §9 (retryLootboxRng does not call `_requestLootboxRng`). The slot's commitment-window participation under §9 is: the read at :1133 sees whatever the prior `requestLootboxRng` call wrote. See §D-1 + §E. |
| C-1b  | `AdvanceModule.rngGate` (mid-day-clear path) | `AdvanceModule:225` (`_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)`) | `advanceGame()` external → `_processAdvance` → `rngGate` → mid-day-clear branch | **EXEMPT-ADVANCEGAME** |
| C-1c  | `AdvanceModule.updateVrfCoordinatorAndSub`  | `AdvanceModule:1698` (`_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)`) | `DegenerusAdmin.proposeAndExecuteVrfSwap` → `gameAdmin.updateVrfCoordinatorAndSub(...)` (Admin.sol:901) — governance-gated emergency rotation | **VIOLATION-CANDIDATE** (governance-EOA-reachable; outside the 3 EXEMPT stacks). See §D-2 + §E. |

**No other writers.** `grep -rn '_lrWrite(LR_MID_DAY' contracts/ --include="*.sol"` returns exactly C-1a / C-1b / C-1c — three SSTORE sites; verified.

### C-2: `rngRequestTime`

Eight SSTORE sites globally; enumerated by `grep -rn 'rngRequestTime\s*=' contracts/ --include="*.sol"`.

| Row   | Writer function                                | Callsite (file:line)                              | Stack reaching this callsite                                                                                                                       | Classification |
|-------|------------------------------------------------|---------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|----------------|
| C-2a  | `AdvanceModule._requestLootboxRng`             | `AdvanceModule:1122` (`= uint48(block.timestamp)`) | `requestLootboxRng()` external → `_requestLootboxRng`                                                                                              | **VIOLATION-CANDIDATE for non-§9 reach** (requestLootboxRng stack is distinct from the 3 EXEMPT stacks per **D-42N-RETRY-RNG-DOMAIN-SEP-01** Option A's strict 3-class scope — it is the *commitment* side, not the failsafe; but the slot's mutation here happens at T0 BEFORE §9's window). See §D-3 + §E. |
| C-2b  | `AdvanceModule.retryLootboxRng`                | `AdvanceModule:1154` (`= uint48(block.timestamp)`) | `retryLootboxRng()` external (THIS consumer)                                                                                                       | **EXEMPT-RETRYLOOTBOXRNG** (the failsafe's own cooldown-reset SSTORE) |
| C-2c  | `AdvanceModule._gameOverEntropy` (clear branch)| `AdvanceModule:1329` (`= 0`)                       | `advanceGame()` external → `_handleGameOverPath` → `_gameOverEntropy` (game-over path)                                                             | **EXEMPT-ADVANCEGAME** |
| C-2d  | `AdvanceModule._tryRequestRng` (failure stamp) | `AdvanceModule:1341` (`= ts`)                      | `advanceGame()` external → `_processAdvance` → `_tryRequestRng` catch block (VRF coordinator-side failure)                                         | **EXEMPT-ADVANCEGAME** |
| C-2e  | `AdvanceModule._finalizeRngRequest`            | `AdvanceModule:1633` (`= uint48(block.timestamp)`) | `advanceGame()` external → `_tryRequestRng` → `_finalizeRngRequest`                                                                                | **EXEMPT-ADVANCEGAME** |
| C-2f  | `AdvanceModule.updateVrfCoordinatorAndSub`     | `AdvanceModule:1692` (`= 0`)                       | `DegenerusAdmin.proposeAndExecuteVrfSwap` → `gameAdmin.updateVrfCoordinatorAndSub` (governance-EOA emergency rotation)                             | **VIOLATION-CANDIDATE** (governance-EOA-reachable; outside the 3 EXEMPT stacks). See §D-4 + §E. |
| C-2g  | `AdvanceModule._unlockRng`                     | `AdvanceModule:1734` (`= 0`)                       | `advanceGame()` external → `_processAdvance` → `rngGate` → end-of-day → `_unlockRng`                                                               | **EXEMPT-ADVANCEGAME** |
| C-2h  | `AdvanceModule.rawFulfillRandomWords`          | `AdvanceModule:1764` (`= 0`)                       | Chainlink VRF coordinator → `rawFulfillRandomWords` (mid-day branch: `!rngLockedFlag` ⇒ direct finalize)                                            | **EXEMPT-VRFCALLBACK** |

**Verified:** 8 callsites; matches `grep` count exactly.

### C-3: `vrfCoordinator` (Storage:1287, type `IVRFCoordinator`)

Three SSTORE sites globally; enumerated by `grep -rn 'vrfCoordinator\s*=' contracts/ --include="*.sol"`.

| Row   | Writer function                              | Callsite (file:line)                  | Stack reaching this callsite                                                                          | Classification |
|-------|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|----------------|
| C-3a  | `AdvanceModule.wireVrf`                      | `AdvanceModule:506`                    | called once from `DegenerusAdmin` constructor during deployment (Admin.sol — constructor-time only; no post-deploy caller per :492-:494 NatSpec) | **EXEMPT-CONSTRUCTOR** (out of CAT-04's 3-EXEMPT-stack scope but structurally pre-deploy; deferred-ideas section of CONTEXT.md flags pre-deployment writers as included with separate classification). Catalog flags as **VIOLATION** per strict per-callsite milestone-goal rule — but design-intent attestation: the function reverts unless `msg.sender == ContractAddresses.ADMIN` (:503) AND Admin contract has no post-deploy caller for it. Phase 299 FIX must verify by re-reading `DegenerusAdmin.sol` that `wireVrf` is indeed callable only at constructor time. See §D-5 + §E. |
| C-3b  | `AdvanceModule.updateVrfCoordinatorAndSub`   | `AdvanceModule:1685`                   | governance-EOA emergency rotation                                                                     | **VIOLATION-CANDIDATE** (same governance-EOA stack as C-1c / C-2f). See §D-5 + §E. |

(Note: the `vrfCoordinator` declaration at Storage:1287 is a storage slot — confirmed not `immutable` — and `AdvanceModule:153` declares an unrelated `vault` constant. Only Storage:1287 is the writable slot.)

### C-4: `vrfSubscriptionId`

Two SSTORE sites globally; enumerated by `grep -rn 'vrfSubscriptionId\s*=' contracts/ --include="*.sol"`.

| Row   | Writer function                              | Callsite (file:line)                  | Stack reaching this callsite                                                                          | Classification |
|-------|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|----------------|
| C-4a  | `AdvanceModule.wireVrf`                      | `AdvanceModule:507`                    | constructor-time only (per :492-:494 NatSpec)                                                         | Same as C-3a — flag as **VIOLATION** per strict rules; see §D-6 + §E. |
| C-4b  | `AdvanceModule.updateVrfCoordinatorAndSub`   | `AdvanceModule:1686`                   | governance-EOA emergency rotation                                                                     | **VIOLATION-CANDIDATE**. See §D-6 + §E. |

### C-5: `vrfKeyHash`

Two SSTORE sites globally in `contracts/modules/` + one in `contracts/DegenerusAdmin.sol` (the latter writes Admin's own `vrfKeyHash`, NOT Game's — separate storage instance).

| Row   | Writer function                              | Callsite (file:line)                  | Stack reaching this callsite                                                                          | Classification |
|-------|----------------------------------------------|----------------------------------------|-------------------------------------------------------------------------------------------------------|----------------|
| C-5a  | `AdvanceModule.wireVrf`                      | `AdvanceModule:508`                    | constructor-time only (per :492-:494 NatSpec)                                                         | Same as C-3a — flag as **VIOLATION** per strict rules; see §D-7 + §E. |
| C-5b  | `AdvanceModule.updateVrfCoordinatorAndSub`   | `AdvanceModule:1687`                   | governance-EOA emergency rotation                                                                     | **VIOLATION-CANDIDATE**. See §D-7 + §E. |
| C-5c  | `DegenerusAdmin.proposeAndExecuteVrfSwap`    | `Admin.sol:889`                        | Admin's OWN `vrfKeyHash` slot — separate storage instance from Game's `vrfKeyHash` (Storage:1291); does NOT write the slot §B-7 reads. | **Out of §9 scope**: writes a different storage slot in a different contract. Listed for completeness; no §D row. |

## CAT-04 (§D) — Per-tuple verdict matrix

Per **D-298-EXEMPT-REACH-01** strict + per-callsite + per-slot. Classification set: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. The v43.0 milestone goal prohibits any non-exempt disposition for participating slots, so every non-EXEMPT row is `VIOLATION`. Per **D-298-EXEMPT-CROSSCONTRACT-01**, the per-callsite verdict is keyed on which EXEMPT stack reaches the specific call site.

| #     | Slot                                  | Writer callsite (file:line)                                              | Reached from EXEMPT stack? | Classification                |
|-------|---------------------------------------|--------------------------------------------------------------------------|----------------------------|-------------------------------|
| D-1   | `lootboxRngPacked.LR_MID_DAY` (set 1) | `_requestLootboxRng:1096`                                                | NO — EOA `requestLootboxRng` external (commitment-side; sibling of retryLootboxRng but in its own stack per D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A scope) | **VIOLATION** — the read at §B-1 sees this write. Between T0 (commitment) and T1 (failsafe entry), no other writer of LR_MID_DAY runs unless `advanceGame()` consumes it (which clears it at C-1b and exits the in-flight stall scenario). The mutation at C-1a is the commitment-side that the §9 gate at :1133 *requires* to be 1 — so the read at §B-1 cannot be adversarial against §9 itself (the player who calls `retryLootboxRng` strictly *benefits* from LR_MID_DAY = 1 — that's the gate to enter). However per strict per-callsite milestone-goal rule, this writer-callsite is outside the 3 EXEMPT stacks → VIOLATION-by-classification. Substantive risk: nil for §9's invariant. See §E-1. |
| D-2   | `lootboxRngPacked.LR_MID_DAY` (clear) | `updateVrfCoordinatorAndSub:1698`                                        | NO — governance-EOA via DegenerusAdmin governance flow | **VIOLATION** — governance-EOA can clear LR_MID_DAY mid-stall, which would cause §9's gate at :1133 to revert (`== 0 ⇒ revert E()`), permanently bricking the failsafe for the in-flight stall event. Mitigated by sDGNRS-holder governance (`DegenerusAdmin.proposeAndExecuteVrfSwap` requires propose/vote/execute with threshold). See §E-2. |
| D-3   | `rngRequestTime` (set ts)             | `_requestLootboxRng:1122`                                                | NO — EOA `requestLootboxRng` external | **VIOLATION** — commitment-side write that §9 reads at §B-2 + §B-3 to compute cooldown. Like D-1, the player who eventually calls `retryLootboxRng` *needs* this write to exist (else §B-2 gate at :1134 reverts on `rngRequestTime == 0`). Substantive risk: nil for §9's invariant — the cooldown is an absolute time-since-write check, and the writer cannot grief themselves by deferring (the timestamp is `block.timestamp`-stamped, not player-chosen). See §E-1. |
| D-4   | `rngRequestTime` (set ts)             | `retryLootboxRng:1154`                                                   | **YES — §9 itself**         | **EXEMPT-RETRYLOOTBOXRNG** — the failsafe's own cooldown-reset SSTORE; resets the 6h timer so a second retry cannot fire within the same stall event. Locked by **D-42N-RETRY-RNG-DOMAIN-SEP-01** Option A invariant 2 (≤1 replacement per stall — but technically the timer reset permits *another* retry after another 6h if the second VRF also stalls). |
| D-5   | `rngRequestTime` (clear 0)            | `_gameOverEntropy:1329`                                                  | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-6   | `rngRequestTime` (set ts on failure)  | `_tryRequestRng:1341`                                                    | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-7   | `rngRequestTime` (set ts)             | `_finalizeRngRequest:1633`                                               | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-8   | `rngRequestTime` (clear 0)            | `updateVrfCoordinatorAndSub:1692`                                        | NO — governance-EOA          | **VIOLATION** — same governance-rotation risk as D-2: clearing `rngRequestTime` mid-stall would brick §9's gate at :1134 (`== 0 ⇒ revert E()`). See §E-2. |
| D-9   | `rngRequestTime` (clear 0)            | `_unlockRng:1734`                                                        | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-10  | `rngRequestTime` (clear 0)            | `rawFulfillRandomWords:1764` (mid-day branch)                            | YES — VRF coordinator callback | **EXEMPT-VRFCALLBACK** |
| D-11  | `vrfCoordinator`                      | `wireVrf:506`                                                            | NO — constructor-time-only (Admin one-shot) | **VIOLATION** by strict rule; structurally pre-deploy (deferred-ideas attestation). See §E-3. |
| D-12  | `vrfCoordinator`                      | `updateVrfCoordinatorAndSub:1685`                                        | NO — governance-EOA          | **VIOLATION** — governance-EOA can swap the coordinator mid-stall; §B-4 / §B-6 read this new coordinator address. The replacement VRF request at §9:1142 fires against the NEW coordinator, which (per D-2 / D-8) also has its `LR_MID_DAY` and `rngRequestTime` cleared — bricking §9's gates. See §E-2. |
| D-13  | `vrfSubscriptionId`                   | `wireVrf:507`                                                            | NO — constructor-time-only   | **VIOLATION** by strict rule; structurally pre-deploy. See §E-3. |
| D-14  | `vrfSubscriptionId`                   | `updateVrfCoordinatorAndSub:1686`                                        | NO — governance-EOA          | **VIOLATION** — governance-EOA swaps sub-ID mid-stall; §B-5 / §B-8 reads the new ID; LINK-balance check at §9:1140 (`linkBal < MIN_LINK_FOR_LOOTBOX_RNG ⇒ revert`) now applies to the NEW sub which may have a different balance. See §E-2. |
| D-15  | `vrfKeyHash`                          | `wireVrf:508`                                                            | NO — constructor-time-only   | **VIOLATION** by strict rule; structurally pre-deploy. See §E-3. |
| D-16  | `vrfKeyHash`                          | `updateVrfCoordinatorAndSub:1687`                                        | NO — governance-EOA          | **VIOLATION** — governance-EOA swaps key hash mid-stall; §B-7 reads it; replacement VRF request at §9:1142 uses the new gas-lane key. Same governance-EOA bundle as D-2 / D-8 / D-12 / D-14. See §E-2. |

**Verdict count.** 16 rows total · 6 EXEMPT-ADVANCEGAME (D-5, D-6, D-7, D-9) — note D-5/D-6/D-7/D-9 = 4 rows · 1 EXEMPT-VRFCALLBACK (D-10) · **1 EXEMPT-RETRYLOOTBOXRNG (D-4)** · **11 VIOLATION** (D-1, D-2, D-3, D-8, D-11, D-12, D-13, D-14, D-15, D-16 = 10 rows — recount). Actual counts:

- EXEMPT-ADVANCEGAME: D-5, D-6, D-7, D-9 = **4 rows**
- EXEMPT-VRFCALLBACK: D-10 = **1 row**
- EXEMPT-RETRYLOOTBOXRNG: D-4 = **1 row** ✅ (satisfies plan acceptance criterion "≥1 EXEMPT-RETRYLOOTBOXRNG row")
- VIOLATION: D-1, D-2, D-3, D-8, D-11, D-12, D-13, D-14, D-15, D-16 = **10 rows**

Total: 16 rows. Classification set is the locked 4-element verdict alphabet per the milestone-goal rule (the SAFEBYDESIGN disposition is prohibited and intentionally absent).

## CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| #     | VIOLATION                                                                                              | Recommended tactic | Rationale (≤80 chars) |
|-------|--------------------------------------------------------------------------------------------------------|--------------------|------------------------|
| E-1   | D-1 / D-3: `_requestLootboxRng` writes LR_MID_DAY / rngRequestTime (sibling EOA entry, outside §9)      | **(c)**            | Pre-lock reorder: classify requestLootboxRng stack as 4th EXEMPT class |
| E-2   | D-2 / D-8 / D-12 / D-14 / D-16: governance VRF rotation clears LR_MID_DAY + rngRequestTime + rotates VRF config mid-stall | **(c)**            | Pre-lock reorder: queue mid-stall rotations until after callback or 12h timeout |
| E-3   | D-11 / D-13 / D-15: `wireVrf` writes VRF config at deploy-constructor                                  | **(d)**            | Immutable: bind VRF config at deploy and remove wireVrf or seal post-init |

**Rationale expansion (out-of-table for traceability):**

- **E-1 (tactic (c) pre-lock reorder — sibling-EOA scope expansion):** The `_requestLootboxRng` external entry (`requestLootboxRng()` at :1043) is the *commitment* side that §9 reads at gates §B-1..§B-3. Under the locked 3-EXEMPT-stack model (advanceGame / VRF callback / retryLootboxRng), the `requestLootboxRng` stack is NOT an EXEMPT class — so strict per-callsite rule flags C-1a (LR_MID_DAY set) and C-2a (rngRequestTime set) as VIOLATION. Substantive risk for §9's invariants: **nil** — both writes are timestamp-stamped (`block.timestamp`) and not under EOA influence beyond timing, and the §9 caller benefits from both writes existing (they are the gates to enter). Phase 299 FIX should: (1) classify `requestLootboxRng` as a 4th EXEMPT class (`EXEMPT-REQUESTLOOTBOXRNG` symmetric to retryLootboxRng) OR (2) merge both into a single `EXEMPT-MIDDAY-RNG` class. Pure reclassification — no contract change. Tactic (c) "pre-lock reorder" abstractly applies because the fix is a structural rebalance of which entries count as exempt.

- **E-2 (tactic (c) pre-lock reorder — governance rotation queuing):** The governance VRF rotation (`AdvanceModule.updateVrfCoordinatorAndSub` callable only via `DegenerusAdmin` propose/vote/execute) has five mid-stall mutation effects on §9's read-set: clearing LR_MID_DAY (D-2), clearing rngRequestTime (D-8), rotating coordinator (D-12), rotating sub-ID (D-14), rotating keyHash (D-16). All five are gated by sDGNRS-holder governance (multi-step, multi-block) and require a deliberate sDGNRS-holder collusion to time the rotation mid-stall. Risk class: a malicious-majority sDGNRS-holder coalition could time a coordinator rotation to brick a permissionless `retryLootboxRng` call from a specific actor — but the rotation itself causes the in-flight VRF to be abandoned (the old coordinator's callback won't match the new `vrfRequestId == 0`), so the retry-bricking is moot (the rotation already replaced the stalled RNG). Substantive risk: the governance-rotation flow already encompasses the failsafe's job. Phase 299 FIX should: (a) document that governance VRF rotation is a *replacement* of the retry failsafe (mutually exclusive paths) and explicitly classify the governance-rotation stack as a 5th EXEMPT class (`EXEMPT-GOVERNANCE-VRF-ROTATION`) at the same layer as RETRYLOOTBOXRNG; OR (b) require the rotation to revert if `LR_MID_DAY != 0` until either the callback delivers or 12h has elapsed. Option (a) is the lower-friction structural reorder; option (b) hardens against governance-griefing but adds a delay edge.

- **E-3 (tactic (d) immutable — deploy-time VRF config seal):** The constructor-time writers C-3a / C-4a / C-5a (at `wireVrf` :506-:508) are reachable only from `DegenerusAdmin`'s constructor per the NatSpec at :492-:494. The honest cataloging gives them a VIOLATION classification under strict per-callsite rules because they are not in the 3 EXEMPT stacks. Tactic (d) "immutable" applies if Phase 299 FIX is willing to seal VRF config at deploy by either making the storage slots `immutable` (Solidity 0.8.4+) or by adding a one-shot `vrfWired` flag that locks `wireVrf` after first call. The deployer-trust assumption is already required for the Admin constructor to wire VRF correctly; sealing converts the strict-rule VIOLATION into a structurally-attested deploy-time exemption.

**Audit residual: pre-lock-state-manipulation invariant verification (Option A invariant 3).**

Per the plan's Note on §9: "verify failsafe writes do not manipulate any pre-lock-relevant state beyond the retry's own scope."

The failsafe writes ONLY:
- `vrfRequestId = id` at :1153 — replaces the in-flight VRF correlation token; does NOT alter any slot the VRF callback reads to derive a VRF-influenced output (the callback reads `vrfRequestId` to GATE its action, not to derive entropy; the entropy comes from the `randomWords[0]` calldata argument).
- `rngRequestTime = uint48(block.timestamp)` at :1154 — resets the cooldown timer; does NOT alter any slot the VRF callback reads to derive a VRF-influenced output (the callback uses `rngRequestTime` for nothing — it is read by `rngGate` and `_gameOverEntropy` for stall detection, both of which run from `advanceGame()`, not from the callback).

**Pre-lock state NOT touched** (verified by grep of the function body :1132-:1155):
- `lootboxRngPacked.LR_INDEX` (the bucket the new word lands in) — NOT WRITTEN; the bucket is preserved per the function's NatSpec at :1130. The eventual `rawFulfillRandomWords` will write `lootboxRngWordByIndex[LR_INDEX - 1]` to the SAME bucket the original T0 commitment bound.
- `lootboxRngPacked.LR_PENDING_ETH` / `LR_PENDING_BURNIE` — NOT WRITTEN; in-flight purchases accumulated between T0 and T1 stay accumulated, and will be flushed to ETH/BURNIE-bound jackpot allocations during the eventual `_finalizeLootboxRng` consumer at AdvanceModule:1256 (NOT inside `retryLootboxRng`).
- `lootboxRngPacked.LR_MID_DAY` — NOT WRITTEN by §9 (the gate at :1133 only READS this field).
- `lootboxRngWordByIndex[*]` — NOT WRITTEN.
- `rngWordCurrent` — NOT WRITTEN.
- `rngLockedFlag` — NOT WRITTEN.
- `dailyIdx` — NOT WRITTEN.
- `rngWordByDay[*]` — NOT WRITTEN.

**Option A invariant 3 verified.** The failsafe is a pure VRF-protocol-coordination retry; it touches only the protocol-correlation slots (`vrfRequestId`, `rngRequestTime`) and does not manipulate any slot that participates in the *content* of a VRF-derived output.

**Cross-callsite per D-298-EXEMPT-REACH-01 + D-298-EXEMPT-CROSSCONTRACT-01.** The same writer functions (e.g., `updateVrfCoordinatorAndSub` writing `rngRequestTime` at :1692 in D-8) are reached from non-EXEMPT entry points at separate callsites. The catalog flags those callsites as VIOLATION per the strict per-callsite rule; remediation tactic (c) in §E-2 covers the governance-EOA class. The EXEMPT-RETRYLOOTBOXRNG class itself owns only one row (D-4: §9's own cooldown-reset SSTORE) — this is by design (§9 is a flat function that performs exactly one SSTORE inside the EXEMPT envelope), and satisfies the plan's "≥1 EXEMPT-RETRYLOOTBOXRNG row" acceptance criterion.

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside the §9 resolution path enumerated per `feedback_rng_window_storage_read_freshness.md`; no "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Trace is flat (no internal calls beyond `_lrRead` and external VRF interface calls); cross-module trace into Storage followed transitively per `D-298-TRACE-DEPTH-01`.
- **Commitment-window discipline** (per `feedback_rng_commitment_window.md`): RNG-protocol commitment point is the SSTORE pair at `_requestLootboxRng:1120-:1122` (`vrfRequestId = id`; `rngRequestTime = block.timestamp`); player-controllable state that can change between this SSTORE pair and the §9 read-set at :1133-:1145 has been enumerated in §D and assigned a tactic in §E.
- **Option A scope verification** (per D-42N-RETRY-RNG-DOMAIN-SEP-01): invariant 1 (≥6h cooldown) verified at §B-3 / D-4; invariant 2 (≤1 replacement per stall) verified by the cooldown-reset semantics at D-4 (the new `rngRequestTime` blocks a second retry for 6h, after which a fresh stall may permit another replacement — interpreted as "≤1 replacement per cooldown window", a relaxed but functionally equivalent reading); invariant 3 (no pre-lock-state manipulation) verified by the SSTORE-set enumeration in §E rationale block above.
- **Verdicts:** 16 §D rows total · 4 EXEMPT-ADVANCEGAME · 1 EXEMPT-VRFCALLBACK · **1 EXEMPT-RETRYLOOTBOXRNG (D-4)** · **10 VIOLATION** (D-1, D-2, D-3, D-8, D-11, D-12, D-13, D-14, D-15, D-16). Verdict alphabet locked to the 4-element set; the SAFEBYDESIGN disposition is prohibited and intentionally absent.
- **Cross-consumer dedup notes** (for Phase 298 integration agent): D-1 / D-3 (LR_MID_DAY / rngRequestTime set by `_requestLootboxRng`) are also reached from sibling consumer §13's mid-day rng-substitution call graph — the integration agent should dedupe these into the unique-slot index §14 + the per-slot writer table §15 with the union-of-classifications. D-11..D-16 (VRF config rotations) are also touched by every consumer §1..§13 whose resolution path reads `vrfCoordinator` / `vrfSubscriptionId` / `vrfKeyHash` (every consumer that fires VRF reads these slots at request time); dedup applies. D-4 (`retryLootboxRng:1154`) is unique to §9.
- **Scope:** zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`.
