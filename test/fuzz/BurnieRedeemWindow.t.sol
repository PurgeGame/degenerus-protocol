// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title BurnieRedeemWindow -- regression suite for the BURNIE purchase-window gate in
///        DegenerusGameMintModule._redeemBurnieFor.
///
/// @notice BURNIE redemptions are blocked during an open/stalled purchase phase and allowed only
///         once a jackpot is locked in or live, so bonus tickets and prize ETH accrue to real-ETH
///         buyers. The gate (MintModule:1102-1109): if the window is not open, revert when
///         rngLockedFlag is set OR (purchase phase AND nextPrizePool < levelPrizePool[level]);
///         otherwise latch burnieWindowOpen=true. Once latched the gate is bypassed; the window is
///         closed again at the final jackpot day's RNG request (verified separately in the advance
///         chain). These tests pin the player-facing open/close truth table by forcing the slot-0
///         flags + prize pool directly.
contract BurnieRedeemWindowTest is DeployProtocol {
    // Slot 0 byte offsets (confirmed via `forge inspect DegenerusGame storageLayout`).
    uint256 private constant SLOT_0 = 0;
    uint256 private constant JACKPOT_PHASE_SHIFT = 120; // byte 15: jackpotPhaseFlag
    uint256 private constant RNG_LOCKED_SHIFT = 152; // byte 19: rngLockedFlag
    uint256 private constant WINDOW_OPEN_SHIFT = 240; // byte 30: burnieWindowOpen
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2; // [future:128][next:128]

    // levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL (DegenerusGame constructor).
    uint128 private constant BOOTSTRAP_PRIZE_POOL = 50 ether;
    // One whole ticket = 4 * TICKET_SCALE = 400 purchase units; 4000 = 10 tickets, safely above
    // the 0.0025 ETH min buy-in so a redeem that clears the gate also clears the purchase floor.
    uint256 private constant REDEEM_QTY = 4000;

    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("burnie_buyer");
        vm.deal(address(game), 5_000 ether);
        // Fund enough BURNIE that the in-path burn (the only cost on the redeem leg) never binds.
        _fundBurnie(buyer, 1_000_000 ether);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    function _fundBurnie(address who, uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(who, amount);
    }

    function _windowOpen() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_0))));
        return ((s0 >> WINDOW_OPEN_SHIFT) & 0xFF) != 0;
    }

    function _setFlag(uint256 shift, bool v) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_0))));
        s0 &= ~(uint256(0xFF) << shift);
        if (v) s0 |= (uint256(1) << shift);
        vm.store(address(game), bytes32(uint256(SLOT_0)), bytes32(s0));
    }

    function _setNextPool(uint128 next) internal {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)))
        );
        uint128 future = uint128(packed >> 128);
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32((uint256(future) << 128) | uint256(next))
        );
    }

    function _redeem() internal returns (bool ok) {
        vm.prank(buyer);
        (ok, ) = address(game).call(
            abi.encodeWithSignature(
                "redeemBurnie(address,uint256)",
                buyer,
                REDEEM_QTY
            )
        );
    }

    // ---------------------------------------------------------------------
    // Window CLOSED -> redeem reverts
    // ---------------------------------------------------------------------

    /// @notice Open/stalled purchase phase (target unmet, no jackpot, RNG unlocked): redeem reverts
    ///         and the window stays shut.
    function testStalledPurchasePhaseBlocksRedeem() public {
        _setNextPool(BOOTSTRAP_PRIZE_POOL - 1); // strictly below levelPrizePool[0]
        assertFalse(_windowOpen(), "window must start closed");
        assertFalse(_redeem(), "redeem must revert in an open/stalled purchase phase");
        assertFalse(_windowOpen(), "window must stay closed after a blocked redeem");
    }

    /// @notice RNG in flight (rngLockedFlag set): the window cannot be opened even with target met.
    function testRngLockedBlocksWindowOpen() public {
        _setNextPool(BOOTSTRAP_PRIZE_POOL + 10 ether); // target met
        _setFlag(RNG_LOCKED_SHIFT, true); // but RNG locked
        assertFalse(_redeem(), "redeem must revert while RNG is locked");
        assertFalse(_windowOpen(), "window must not open while RNG is locked");
    }

    // ---------------------------------------------------------------------
    // Window OPENS -> redeem succeeds and latches
    // ---------------------------------------------------------------------

    /// @notice Prize target met in the purchase phase: the window opens and latches.
    function testTargetMetOpensWindow() public {
        _setNextPool(BOOTSTRAP_PRIZE_POOL + 10 ether); // >= levelPrizePool[0]
        assertTrue(_redeem(), "redeem should succeed once the prize target is met");
        assertTrue(_windowOpen(), "window must latch open after a target-met redeem");
    }

    /// @notice The jackpot phase alone does not open the window — the prize target governs. In a real
    ///         game the window is already latched from a lastPurchaseDay redeem; this pins that
    ///         jackpotPhaseFlag is not itself an open key (the clause was dropped), so a closed window
    ///         with the target unmet (the post-consolidation jackpot state) stays shut.
    function testJackpotPhaseAloneDoesNotOpenWindow() public {
        _setNextPool(BOOTSTRAP_PRIZE_POOL - 1); // target NOT met (post-consolidation jackpot state)
        _setFlag(JACKPOT_PHASE_SHIFT, true); // jackpot live, but pool below target
        assertFalse(_redeem(), "jackpotPhaseFlag alone must not open the window");
        assertFalse(_windowOpen(), "window must stay closed when the target is unmet");
    }

    /// @notice Already-open window: the gate is bypassed (idempotent latch) and the redeem proceeds
    ///         even from an otherwise-blocking state.
    function testOpenWindowLatchIsHonored() public {
        _setNextPool(BOOTSTRAP_PRIZE_POOL - 1); // target NOT met, no jackpot, RNG unlocked
        _setFlag(WINDOW_OPEN_SHIFT, true); // pre-latched open
        assertTrue(_redeem(), "redeem should proceed when the window is already open");
        assertTrue(_windowOpen(), "window must remain open");
    }
}
