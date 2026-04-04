# Phase 176 Comment Audit — Plan 03 Findings
**Contracts:** DegenerusStonk, GNRUS, StakedDegenerusStonk
**Requirement:** CMT-03
**Date:** 2026-04-03
**Total findings this plan:** 3 LOW, 4 INFO

---

## DegenerusStonk

### D03-01 — INFO — GameNotOver error comment directs user to wrong contract

**Location:** `DegenerusStonk.sol` line 57

**Comment says:**
```
/// @notice Thrown when burn() is called during active game (use burnWrapped() instead)
```

**Code does:**
The `GameNotOver` error is thrown in `burn()` (line 229) when `!game.gameOver()`. The comment is accurate that players should call `burnWrapped()` during an active game, but `burnWrapped()` lives on `StakedDegenerusStonk`, not on `DegenerusStonk`. A reader looking at `DegenerusStonk` who sees this comment has no indication to look at a different contract. The error message should clarify "use sDGNRS.burnWrapped()" or at minimum indicate the correct contract.

**Severity:** INFO — The comment is technically correct in intent but omits the contract context, which could confuse integrators.

---

### D03-02 — INFO — BurnThrough event comment says "burned through to sDGNRS" but flow burns FROM sDGNRS

**Location:** `DegenerusStonk.sol` line 68

**Comment says:**
```
/// @notice Emitted when DGNRS is burned through to sDGNRS for ETH + stETH + BURNIE
```

**Code does:**
`burn()` burns the player's DGNRS wrapper token first (line 228), then calls `stonk.burn(amount)` (line 231) which burns sDGNRS held by the DGNRS contract. The phrase "burned through to sDGNRS" implies the destination is sDGNRS, but the actual flow is the reverse: DGNRS is burned, which triggers sDGNRS to be burned FROM its reserves, releasing ETH/stETH/BURNIE to the player. A clearer description would be "burned to redeem proportional ETH + stETH + BURNIE from sDGNRS backing."

**Severity:** INFO — Directional imprecision; does not affect understanding of outputs.

---

## GNRUS

### G03-01 — LOW — burnAtGameOver NatSpec incorrectly states game sends ETH/stETH to "DGNRS"

**Location:** `GNRUS.sol` lines 337–340

**Comment says:**
```
/// @dev Only callable by the game contract. Can only be called once.
///      The game contract pushes final ETH/stETH to VAULT, DGNRS, and GNRUS
///      during gameover processing. This function handles the GNRUS-side cleanup
///      of burning unallocated tokens.
```

**Code does:**
The game's gameover processing sends ETH/stETH to `ContractAddresses.VAULT`, `ContractAddresses.SDGNRS` (StakedDegenerusStonk), and `ContractAddresses.GNRUS` — not to `ContractAddresses.DGNRS` (DegenerusStonk). This was confirmed by Phase 175 finding G05-01, which found that `DegenerusGameGameOverModule._sendToVault` uses `ContractAddresses.SDGNRS` as the third recipient, not DGNRS. The comment in GNRUS mirrors the incorrect description from the GameOverModule comments — a reader of GNRUS would incorrectly believe DGNRS receives final ETH/stETH at gameover.

**Fix:** Change "VAULT, DGNRS, and GNRUS" to "VAULT, sDGNRS, and GNRUS".

**Severity:** LOW — Misleads about which contract receives gameover ETH/stETH; could cause confusion during post-gameover fund tracking.

---

### G03-02 — LOW — vote() NatSpec says vault owner weight is "fixed at 5%" but code adds 5% BONUS on top of balance weight

**Location:** `GNRUS.sol` lines 410–411

**Comment says:**
```
/// @dev Vote weight equals the voter's sDGNRS balance, except the vault owner
///      (>50.1% DGVE) whose weight is fixed at 5% of the sDGNRS snapshot.
```

**Code does:**
```solidity
uint48 weight = uint48(sdgnrs.balanceOf(voter) / 1e18);
// ...
if (vault owner) {
    weight += uint48((uint256(levelSdgnrsSnapshot[level]) * VAULT_VOTE_BPS) / BPS_DENOM);
}
```
Lines 425–429: The vault owner's weight is computed as their own sDGNRS balance weight (`sdgnrs.balanceOf(voter) / 1e18`) PLUS 5% of the snapshot supply. The NatSpec says the vault owner weight is "fixed at 5% of the sDGNRS snapshot," implying the vault owner only ever gets 5% regardless of their own holdings. In reality, the vault owner receives their normal balance-based weight as a base, with the 5% bonus added on top. An auditor reading the NatSpec would conclude the vault owner is capped/fixed at 5%, which is incorrect.

**Fix:** Change "whose weight is fixed at 5% of the sDGNRS snapshot" to "who receives their own sDGNRS balance weight plus a 5% bonus of the sDGNRS snapshot."

**Severity:** LOW — Misleads about vault owner voting power calculation; directly affects governance security analysis.

---

### G03-03 — INFO — burn() NatSpec describes "last-holder sweep" trigger condition imprecisely

**Location:** `GNRUS.sol` lines 279–281

**Comment says:**
```
/// @dev ...Last-holder sweep: if the caller's
///      entire balance equals `amount` or all non-contract GNRUS equals `amount`,
///      sweeps the full caller balance to avoid dust.
```

**Code does:**
```solidity
if (burnerBal == amount || (supply - balanceOf[address(this)]) == amount) {
    amount = burnerBal; // sweep
}
```
Line 291: The second condition `(supply - balanceOf[address(this)]) == amount` computes total supply minus the GNRUS contract's own balance. This equals "all GNRUS held outside the contract" — which includes balances of any other contracts that received GNRUS distributions, not just EOA holders. The comment says "all non-contract GNRUS" which would exclude contract holders. The actual trigger is "all externally-held GNRUS" (both EOA and contract holders), not exclusively "non-contract GNRUS."

**Severity:** INFO — The nuance matters in edge cases (e.g., a contract holding GNRUS burning its entire slice), but the practical impact is minimal.

---

## StakedDegenerusStonk

### S03-01 — INFO — Constructor NatSpec omits setAfKingMode call

**Location:** `StakedDegenerusStonk.sol` lines 280–281

**Comment says:**
```
/// @notice Initializes token supply, distributes to pools, and claims whale pass for sDGNRS
```

**Code does:**
The constructor also calls `game.setAfKingMode(address(0), true, 10 ether, 0)` (lines 310–315), which sets afKing mode enabled with a 10 ETH takeProfit threshold for the sDGNRS contract's own game position. This call is not mentioned in the NatSpec. A developer auditing the constructor would not know from the comment alone that afKing mode configuration happens at deployment.

**Severity:** INFO — Missing NatSpec coverage of a constructor side effect; does not mislead, just omits.

---

### S03-02 — LOW — burnWrapped() NatSpec describes flow as "convert DGNRS to sDGNRS credit" which mischaracterizes the mechanics

**Location:** `StakedDegenerusStonk.sol` line 489

**Comment says:**
```
/// @dev Calls dgnrsWrapper to convert DGNRS to sDGNRS credit, then burns the resulting sDGNRS.
```

**Code does:**
```solidity
dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
// ...
_deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount);
// or
_submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
```
Lines 497–504: The function burns the player's DGNRS wrapper tokens by calling `dgnrsWrapper.burnForSdgnrs()`, which destroys DGNRS ERC20 tokens and reduces `totalSupply`. Then it burns `amount` of sDGNRS from the sDGNRS balance of `ContractAddresses.DGNRS` (the DGNRS contract holds sDGNRS as its backing). The comment says "convert DGNRS to sDGNRS credit" as if DGNRS is exchanged for sDGNRS, but no sDGNRS is minted or received by the player — the pre-existing sDGNRS in the DGNRS contract's balance is consumed. The phrase "resulting sDGNRS" implies new sDGNRS is created, which is incorrect.

**Fix:** Change to "Burns the player's DGNRS wrapper tokens and burns the corresponding sDGNRS from the DGNRS contract's backing balance."

**Severity:** LOW — Mischaracterizes the mechanics by implying a DGNRS→sDGNRS conversion; could mislead a reviewer auditing the burn path.

---

### S03-03 — INFO — Gambling burn system verified accurate

**Location:** `StakedDegenerusStonk.sol` lines 560–804

**Audit note:** The gambling burn system comments have been explicitly verified:
- `resolveRedemptionPeriod()` NatSpec accurately describes the roll-based ETH segregation adjustment and BURNIE credit return.
- `claimRedemption()` NatSpec accurately describes the 50/50 ETH split, 100% direct on gameOver, BURNIE forfeiture on coinflip loss, and second-claim on unresolved coinflip.
- `_submitGamblingClaimFrom()` inline comments about 50% supply cap, 160 ETH daily EV cap, and activity score snapshotting are all accurate.
- `hasPendingRedemptions()` NatSpec accurately describes "current period has unresolved ETH or BURNIE base."
- `pendingRedemptionEthValue`, `pendingRedemptionBurnie`, `pendingRedemptionEthBase`, `pendingRedemptionBurnieBase` variable definitions are accurate.

No discrepancies found in the gambling burn system comments.

---

### S03-04 — INFO — Vault interaction verified against Phase 175 G05-01 finding

**Location:** `StakedDegenerusStonk.sol` — `receive()`, `depositSteth()`, `_deterministicBurnFrom()`

**Audit note:** Phase 175 finding G05-01 established that `DegenerusGameGameOverModule` sends final ETH/stETH to `ContractAddresses.SDGNRS` (StakedDegenerusStonk), not `ContractAddresses.DGNRS`. The sDGNRS-side comments are consistent with this:
- `receive()` (line 363): `/// @notice Receive ETH deposit from game contract` — accurate, the game sends ETH to SDGNRS.
- `depositSteth()` (line 371): `/// @notice Receive stETH deposit from game contract` — accurate.
- `_deterministicBurnFrom()` (line 512): `/// @dev No BURNIE payout for gameOver burns — pure ETH/stETH only` — accurate.

No discrepancies found in sDGNRS vault interaction comments. The misidentification of the gameover recipient exists in GNRUS.sol (finding G03-01) and in GameOverModule (finding G05-01 from Phase 175), not in sDGNRS itself.
