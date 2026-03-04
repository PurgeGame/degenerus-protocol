---
phase: 12-cross-function-reentrancy-synthesis-and-unchecked-blocks
plan: "01"
subsystem: audit
tags: [solidity, reentrancy, CEI, ERC721, safeTransferFrom, cross-function, security]

# Dependency graph
requires:
  - phase: 07-cross-contract-synthesis
    provides: "XCON-03/05/06 verdicts: 8 ETH-transfer sites enumerated, claimWinnings CEI confirmed, stETH/LINK callback analysis"
  - phase: 08-eth-accounting-invariant-and-cei-verification
    provides: "ACCT-04/05 verdicts: _claimWinningsInternal CEI line citations, payout helper analysis"
provides:
  - "REENT-01: authoritative 8-site cross-function reentrancy matrix with contract/line/CEI/verdict"
  - "REENT-02: ERC721 safeTransferFrom -> onERC721Received callback formal trace with attacker window enumeration"
affects: ["phase-13-report"]

# Tech tracking
tech-stack:
  added: []
  patterns: []

key-files:
  created:
    - .planning/phases/12-cross-function-reentrancy-synthesis-and-unchecked-blocks/12-01-SUMMARY.md
  modified: []

key-decisions:
  - "REENT-01: PASS — all 8 ETH-transfer sites across 4 contracts are CEI-safe; sentinel pattern protects arbitrary-recipient sites; trusted-recipient sites send to non-reentrant protocol contracts"
  - "REENT-02: PASS — onERC721Received attacker window is safe; game state is fully settled before _checkReceiver fires; purchaseDeityPass and refundDeityPass are both blocked; mint() does not trigger onERC721Received"
  - "REENT-02 INFO: _transfer() CEI deviation (onDeityPassTransfer called before _owners[tokenId] = to) is NOT exploitable because WhaleModule.handleDeityPassTransfer reads DegenerusGame storage only, never calls back to DegenerusDeityPass to read stale _owners"

patterns-established: []

requirements-completed:
  - REENT-01
  - REENT-02

# Metrics
duration: 15min
completed: 2026-03-04
---

# Phase 12-01: Cross-Function Reentrancy Synthesis Summary

**8-site reentrancy matrix complete (REENT-01 PASS) and ERC721 safeTransferFrom callback formally traced (REENT-02 PASS): no exploitable reentrancy vector exists across all protocol ETH-transfer paths or ERC721 callback surfaces.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-03-04T23:38:11Z
- **Completed:** 2026-03-04T23:53:11Z
- **Tasks:** 2 completed
- **Files modified:** 1

## Accomplishments

- Synthesized authoritative REENT-01 matrix unifying Phase 7-03 and Phase 8-02 ETH-transfer site analysis into a single verdicted 8-row table
- Formally traced the REENT-02 ERC721 safeTransferFrom -> _checkReceiver -> onERC721Received attack surface with attacker window enumeration
- Confirmed mint() does not trigger onERC721Received, closing the game-mint callback vector
- Identified and assessed the _transfer() CEI deviation (onDeityPassTransfer before _owners update) — not exploitable

---

## REENT-01: Cross-Function Reentrancy Matrix

**REENT-01 VERDICT: PASS — No cross-function reentrancy vector exists across all 8 confirmed ETH-transfer sites. All arbitrary-recipient sites are protected by the claimableWinnings[player] sentinel pattern; all trusted-recipient sites send to non-reentrant protocol contracts.**

### 8-Site Matrix

| Site | Contract | Function | Line | Recipient | CEI Mechanism | Re-entry Paths | Verdict |
|------|----------|----------|------|-----------|---------------|----------------|---------|
| 1 | DegenerusGame.sol | `_payoutWithStethFallback` | 2000 | Player (arbitrary) | `claimableWinnings[player] = 1` (sentinel) at line 1473; `claimablePool -= payout` at line 1476 — both BEFORE external call | All 48 DegenerusGame entry points assessed; self-reentrancy blocked by sentinel (amount == 1 reverts); msg.value=0 blocks payable functions; access controls block trusted-only functions | PASS |
| 2 | DegenerusGame.sol | `_payoutWithStethFallback` (retry path) | 2017 | Player (arbitrary) | Same sentinel as Site 1 — `_payoutWithStethFallback` is always called AFTER `_claimWinningsInternal` clears state | Same as Site 1 — sentinel already cleared before this path is reached | PASS |
| 3 | DegenerusGame.sol | `_payoutWithEthFallback` | 2038 | Player (arbitrary) | Same sentinel as Site 1 — `_payoutWithEthFallback` called after `_claimWinningsInternal` sentinel write | Same as Site 1 — sentinel already cleared; re-entrant claimWinnings finds amount == 1, reverts | PASS |
| 4 | GameOverModule.sol | `_sendToVault` | 264 | VAULT (trusted) | `gameOverFinalJackpotPaid = true` (line 128) and `gameOver = true` (line 126) set BEFORE any distribution; boolean gate prevents re-entry | VAULT.receive() is `external payable` — event-only (emits Deposit), no callback to DegenerusGame | PASS |
| 5 | GameOverModule.sol | `_sendToVault` | 281 | DGNRS (trusted) | Same `gameOverFinalJackpotPaid` boolean as Site 4 | DGNRS.receive() is `external payable onlyGame` — access-restricted, event-only, no DegenerusGame callback | PASS |
| 6 | MintModule.sol | `_purchaseFor` (vault share) | 724 | VAULT (trusted) | Compile-time constant address; no state-mutation dependency — ETH split calculation is arithmetic before send | VAULT.receive() is event-only; no callback; recipient is fixed protocol contract | N/A — trusted |
| 7 | DegenerusVault.sol | `_payEth` | 1038 | Player (arbitrary) | Share burning occurs before ETH send in all claim paths — CEI confirmed Phase 7-03 Part B | DegenerusVault is a separate contract; re-entry into VAULT itself would find shares already burned | PASS |
| 8 | DegenerusStonk.sol | `claim` path | 888 | Player (arbitrary) | Token burns and state updates before ETH send — CEI confirmed Phase 7-03 Part B | DegenerusStonk is a separate contract; no cross-contract DegenerusGame state accessible from DGNRS callback | PASS |

### CEI Mechanism Reference: Sites 1-3

Phase 8-02 (ACCT-04) confirmed the exact `_claimWinningsInternal` sequence (DegenerusGame.sol lines 1468-1483):

```
Step 1 CHECK:  claimableWinnings[player] = amount; if (amount <= 1) revert E()   [line 1469-1470]
Step 2 EFFECT: claimableWinnings[player] = 1  (sentinel, zeroes claimable)        [line 1473]
Step 3 EFFECT: claimablePool -= payout       (aggregate liability decremented)    [line 1476]
Step 4 INTERACT: _payoutWithEthFallback(player, payout) OR                        [line 1479]
                 _payoutWithStethFallback(player, payout)                          [line 1481]
```

Both EFFECTS precede the INTERACTION on all code paths. No conditional branch causes partial EFFECTS execution.

### All 48 DegenerusGame Entry Points Blocked During Mid-Claim Callback

Phase 7-03 Part C enumerated all 48 state-changing entry points and confirmed each is blocked during the mid-claim ETH callback by one of: sentinel (amount==1), msg.value==0, access control (trusted contract only), or delegatecall path (no direct ETH transfer). The notable entries:

- **Self-reentrancy** (`claimWinnings`): sentinel blocks — `amount = claimableWinnings[player] = 1`, `amount <= 1` reverts
- **Payable functions** requiring msg.value: blocked — `msg.value = 0` inside callback
- **Legitimate credits** (`resolveDegeneretteBets`, `claimDecimatorJackpot`): can add NEW `claimableWinnings` credits but these are legitimately earned (Phase 4-04 Scenarios 2 and 5); `claimablePool` properly incremented — NOT a double-spend
- **Trusted-only functions**: access gate requires `msg.sender == VAULT/DGNRS/COIN/etc.` — attacker contract is none of these

---

## REENT-02: ERC721 safeTransferFrom Callback Formal Trace

**REENT-02 VERDICT: PASS — The onERC721Received attacker window is safe. At callback time, all DegenerusDeityPass ownership state is finalized and all DegenerusGame deity pass state has been fully updated by onDeityPassTransfer. No DegenerusGame function callable from onERC721Received produces exploitable state corruption or value extraction.**

### Step 1: _transfer() Execution Sequence

Source: `DegenerusDeityPass.sol` lines 374-446 (confirmed by direct source read).

`safeTransferFrom(from, to, tokenId)` at line 374:
```
→ _transfer(from, to, tokenId)                              [line 371]
    → tokenOwner = _owners[tokenId]  (== from, verified)    [line 417]
    → msg.sender authorization check                        [lines 421-424]
    → IDeityPassCallback(GAME).onDeityPassTransfer(...)     [line 428]   << CALLBACK FIRES HERE
    → delete _tokenApprovals[tokenId]                       [line 430]
    → unchecked { _balances[from]--; }                      [line 431]
    → _balances[to]++                                       [line 432]
    → _owners[tokenId] = to                                 [line 433]
    → emit Transfer(from, to, tokenId)                      [line 435]
→ _checkReceiver(from, to, tokenId)                         [line 376]
    → if (to.code.length != 0):                            [line 439]
        IERC721Receiver(to).onERC721Received(...)           [line 440]  << ATTACKER WINDOW
```

**CEI Deviation in _transfer():** `onDeityPassTransfer` (line 428) fires BEFORE `_owners[tokenId] = to` (line 433). This is a formal CEI deviation: the external callback occurs while `_owners[tokenId]` still equals `from`.

### Step 2: _transfer() CEI Deviation Exploitability Assessment

**handleDeityPassTransfer reads DegenerusGame storage — NOT DegenerusDeityPass storage.**

`DegenerusGameWhaleModule._handleDeityPassTransfer` (lines 559-597) operates entirely on DegenerusGame storage:
- `deityPassCount[from]`, `deityPassCount[to]` (DegenerusGame)
- `deityBySymbol[symbolId]`, `deityPassSymbol[from]` (DegenerusGame)
- `deityPassPurchasedCount`, `deityPassPaidTotal` (DegenerusGame)
- `deityPassOwners` array (DegenerusGame)
- `deityPassRefundable[from] = 0` (DegenerusGame)
- External call: `IDegenerusCoin(COIN).burnCoin(from, burnAmount)` — BURNIE burn, no DegenerusDeityPass reads
- External call: `IDegenerusQuestsReset(QUESTS).resetQuestStreak(from)` — quest state, no DegenerusDeityPass reads

**handleDeityPassTransfer does NOT call DegenerusDeityPass to read `_owners[tokenId]` or `_balances`.** The stale `_owners` state at callback time is invisible to the WhaleModule. DegenerusGame's own deity tracking is fully updated during onDeityPassTransfer.

**Verdict: _transfer() CEI deviation is NOT exploitable.** Rated INFO/QA.

### Step 3: Attacker Window at onERC721Received

At the point `onERC721Received` fires (line 440), state is:

| State | Value | Source |
|-------|-------|--------|
| `DegenerusDeityPass._owners[tokenId]` | `to` (FINALIZED) | Set at line 433, before _checkReceiver |
| `DegenerusDeityPass._balances[from]` | decremented (FINALIZED) | Line 431 |
| `DegenerusDeityPass._balances[to]` | incremented (FINALIZED) | Line 432 |
| `DegenerusGame.deityPassCount[from]` | 0 (FINALIZED) | WhaleModule line 575 |
| `DegenerusGame.deityPassCount[to]` | 1 (FINALIZED) | WhaleModule line 574 |
| `DegenerusGame.deityBySymbol[symbolId]` | `to` (FINALIZED) | WhaleModule line 570 |
| `DegenerusGame.deityPassRefundable[from]` | 0 (FINALIZED) | WhaleModule line 593 |
| `IDegenerusCoin(COIN).burnCoin(from, ...)` | COMPLETED | WhaleModule line 566 |

**Attacker (the `to` contract) can call any DegenerusGame function from onERC721Received. Specific attack surface assessment:**

#### (a) purchaseDeityPass() — BLOCKED

`_purchaseDeityPass` checks `if (deityPassCount[buyer] != 0) revert E()` (WhaleModule line 460).

At onERC721Received time, `deityPassCount[to] = 1` (finalized). The attacker (`to`) cannot purchase a second pass. If attacker calls `purchaseDeityPass` with a different address as buyer, that would be a separate player's context — not exploitable via this path.

#### (b) refundDeityPass() — BLOCKED

`refundDeityPass` reads `deityPassRefundable[buyer]` (DegenerusGame.sol line 706). For the `from` address (pass sender), `deityPassRefundable[from]` was zeroed at WhaleModule line 593 during `onDeityPassTransfer`. Any re-entrant call to `refundDeityPass` with `from` as buyer sees `refundAmount == 0` and reverts.

Additionally, `refundDeityPass` is only callable at `level == 0` (game hasn't started). Transfer of a deity pass requires `level != 0` (WhaleModule line 560: `if (level == 0) revert E()`). These gates are mutually exclusive — post-start transfers cannot enable pre-start refunds.

#### (c) Any function exploiting `to`'s new token ownership — NO VALUE EXTRACTION

All DegenerusGame state visible to the attacker (`to`) is fully finalized before _checkReceiver fires. No function can exploit the brief window between _transfer completion and onERC721Received because there is no inconsistency in DegenerusGame storage at that point.

The attacker can call claimWinnings, purchase tickets, or any other function, but these are governed by their own separate state (claimableWinnings[to], etc.) unrelated to the transfer.

### Step 4: mint() — No onERC721Received

`mint()` at lines 389-398 in `DegenerusDeityPass.sol`:
```solidity
function mint(address to, uint256 tokenId) external {
    if (msg.sender != ContractAddresses.GAME) revert NotAuthorized();
    if (tokenId >= 32) revert InvalidToken();
    if (_owners[tokenId] != address(0)) revert InvalidToken();
    if (to == address(0)) revert ZeroAddress();
    _balances[to]++;
    _owners[tokenId] = to;
    emit Transfer(address(0), to, tokenId);
}
```

`mint()` does NOT call `_checkReceiver`. GAME-triggered mints (`_purchaseDeityPass` calling `DEITY_PASS.mint(buyer, symbolId)` at WhaleModule line 502) are not subject to the ERC721 callback. **The "attacker triggers from mint" vector is closed.**

### Step 5: safeTransferFrom Caller Access Control

`safeTransferFrom` at lines 374-382 calls `_transfer` which checks (lines 421-424):
```
msg.sender != from
&& msg.sender != _tokenApprovals[tokenId]
&& !_operatorApprovals[from][msg.sender]
```
— reverts unless caller is token owner, approved address, or approved operator.

An attacker must already own a deity pass (or be approved by the owner) to trigger the callback. This limits the attack surface to players who legitimately hold passes. An unprivileged external account cannot initiate `safeTransferFrom`.

### REENT-02 Findings Summary

| Vector | Status | Evidence |
|--------|--------|----------|
| _transfer CEI deviation (onDeityPassTransfer before _owners update) | INFO — not exploitable | WhaleModule reads DegenerusGame storage only, never reads DegenerusDeityPass._owners |
| onERC721Received: purchaseDeityPass() re-entry | BLOCKED | deityPassCount[to] = 1, revert at WhaleModule:460 |
| onERC721Received: refundDeityPass() re-entry | BLOCKED | deityPassRefundable[from] = 0 (WhaleModule:593); level != 0 gate contradicts refund gate |
| onERC721Received: arbitrary DegenerusGame function | NO VALUE | All relevant state finalized before _checkReceiver; no inconsistency to exploit |
| mint() triggering onERC721Received | CLOSED | mint() does not call _checkReceiver (line 389-398) |
| Unprivileged safeTransferFrom call | CLOSED | Requires token ownership or approval (lines 421-424) |

---

## Task Commits

1. **Task 1: REENT-01 — Synthesize 8-site reentrancy matrix** — analysis delivered in SUMMARY.md
2. **Task 2: REENT-02 — ERC721 safeTransferFrom callback formal trace** — analysis delivered in SUMMARY.md

## Files Created/Modified

- `.planning/phases/12-cross-function-reentrancy-synthesis-and-unchecked-blocks/12-01-SUMMARY.md` — This file (REENT-01 matrix + REENT-02 trace)

## Decisions Made

- REENT-01: PASS — 8-site matrix complete; sentinel pattern correctly protects all arbitrary-recipient sends; trusted-recipient sends are to non-reentrant contracts
- REENT-02: PASS — onERC721Received window is safe; all game state finalized before _checkReceiver; mint() confirmed no callback
- REENT-02 INFO: _transfer() CEI deviation (onDeityPassTransfer before _owners[tokenId] = to) documented as INFO/QA — not exploitable because WhaleModule never reads DegenerusDeityPass._owners

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- REENT-01 and REENT-02 verdicts complete and available for Phase 13 final report
- Phase 12-02 (unchecked blocks analysis) can proceed independently

---
*Phase: 12-cross-function-reentrancy-synthesis-and-unchecked-blocks*
*Completed: 2026-03-04*
