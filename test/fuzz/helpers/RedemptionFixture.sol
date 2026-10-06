// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./DeployProtocol.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {FlipRoundLib} from "../../../contracts/libraries/FlipRoundLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Latches game over directly, for unit checks of the post-game-over doors.
contract RedemptionGameOverLatch is DegenerusGame {
    function end() external { gameOver = true; }
}

/// @notice Forward-priced redemption batches: one close price per batch, closed by whichever
///         live request comes next (daily or mid-day), settled on the word that request returns.
///         Burns leave supply at once; the open batch's escrow keeps them in the holder base.
abstract contract RedemptionFixture is DeployProtocol {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA201);

    bytes32 internal constant CLAIMED_TOPIC =
        keccak256("RedemptionClaimed(address,uint32,uint16,uint256,uint256,uint256)");
    bytes32 internal constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant SYNTH_FLIP_TAG = keccak256("sdgnrs.redemption.synthetic-flip");

    uint256 internal fulfilled;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fundSubscription(1, 100 ether);
        _complete(2);
        vm.deal(address(sdgnrs), 10_000 ether);
        // The Reward pool holds 10% of supply: 3% to each holder.
        uint256 share = sdgnrs.totalSupply() * 3 / 100;
        // Reward recipients are game players, so each holds a wallet ID (a burn requires one).
        _giveWalletId(alice);
        _giveWalletId(bob);
        _giveWalletId(carol);
        vm.startPrank(address(game));
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Reward, alice, share), share);
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Reward, bob, share), share);
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Reward, carol, share), share);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Drivers
    // ---------------------------------------------------------------------

    function _fulfillPending(uint256 word) internal returns (bool answered) {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0 || req == fulfilled) return false;
        (,, bool done) = mockVRF.pendingRequests(req);
        if (!done) mockVRF.fulfillRandomWords(req, word);
        fulfilled = req;
        return true;
    }

    /// @dev Crank and answer every request with `word` until the engine is idle.
    function _complete(uint256 word) internal {
        for (uint256 i; i < 500; ++i) {
            if (!game.advanceDue() && !game.rngLocked() && game.rngComplete()) return;
            game.mineFlip();
            _fulfillPending(word);
        }
        revert("fixture did not finish");
    }

    /// @dev Crank without answering anything: stop at the first new VRF request or when idle.
    function _runUntilNewRequestOrIdle() internal returns (bool requested) {
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < 300; ++i) {
            uint8 action = game.nextMinerAction();
            if (action == 0) return false; // Idle
            require(action != 2, "harness: an unanswered request is waiting"); // Wait
            game.mineFlip();
            if (mockVRF.lastRequestId() != before) return true;
        }
        revert("harness: engine did not settle");
    }

    /// @dev Send a mid-day request: buy a 1 ETH box so the mid-day request is due, then crank.
    function _sendMiddayRequest() internal {
        address buyer = makeAddr("boxBuyer");
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(
            buyer, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertTrue(_runUntilNewRequestOrIdle(), "mid-day request sent");
        assertFalse(game.rngLocked(), "a mid-day request takes no daily lock");
    }

    /// @dev Crank the ending through to game over, answering every new request with `word`.
    function _endGame(uint256 word) internal {
        for (uint256 i; i < 200; ++i) {
            _fulfillPending(word);
            if (game.gameOver()) return;
            game.mineFlip();
        }
        revert("harness: the ending did not reach game over");
    }

    function _latchGameOver() internal {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RedemptionGameOverLatch).runtimeCode);
        RedemptionGameOverLatch(payable(address(game))).end();
        vm.etch(address(game), original);
        assertTrue(game.gameOver());
    }

    function _burn(address player, uint256 amount) internal {
        vm.prank(player);
        sdgnrs.burn(amount);
    }

    /// @dev ETH plus stETH a holder receives from `run`, measured around the call.
    function _received(address who) internal view returns (uint256) {
        return who.balance + mockStETH.balanceOf(who);
    }

    function _claimTokens(address player, uint32 id) internal view returns (uint256 tokens) {
        (tokens,) = sdgnrs.pendingRedemptions(game.walletIdOf(player), id);
    }

    function _batch(uint32 id)
        internal view returns (uint256 tokens, uint256 ethBase, uint256 flipEscrow, uint16 roll, uint16 flipReward)
    {
        (uint128 t,, uint96 e, uint96 f, uint16 r, uint16 w) = sdgnrs.redemptionBatches(id);
        return (t, e, f, r, w);
    }

    function _state() internal view returns (uint32 open, uint32 settling) {
        (open, settling,,) = sdgnrs.redemptionBatchState();
    }

    function _escrow() internal view returns (uint256 escrowed) {
        (,,, escrowed) = sdgnrs.redemptionBatchState();
    }

    function _roll(uint256 word) internal pure returns (uint16) {
        return uint16(((word >> 8) % 155) + 21);
    }

    function _synthReward(uint256 word, uint32 id) internal pure returns (uint16) {
        uint256 synth = uint256(keccak256(abi.encodePacked(SYNTH_FLIP_TAG, word, id)));
        return (synth & 1) == 1 ? FlipRoundLib.coinflipRewardPercent(0, synth, uint24(id)) : 0;
    }

    /// @dev sDGNRS's live money: ETH + stETH + Game claimable (less 1 wei dust) − reserves.
    function _money() internal view returns (uint256) {
        uint256 claimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 gross = address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs))
            + (claimable > 1 ? claimable - 1 : 0);
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        return gross > reserved ? gross - reserved : 0;
    }

    function _closeAsGame() internal returns (uint256 pull) {
        uint256 claimable = game.claimableWinningsOf(address(sdgnrs));
        vm.prank(address(game));
        pull = sdgnrs.closeRedemptionBatch(claimable);
    }

    /// @dev Direct and lootbox legs of `player`'s RedemptionClaimed in `logs` (batch `id`).
    function _claimedLegs(Vm.Log[] memory logs, address player, uint32 id)
        internal view returns (bool found, uint256 direct, uint256 lootbox)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(sdgnrs) || logs[i].topics[0] != CLAIMED_TOPIC) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != player) continue;
            if (uint32(uint256(logs[i].topics[2])) != id) continue;
            (, direct, lootbox,) = abi.decode(logs[i].data, (uint16, uint256, uint256, uint256));
            return (true, direct, lootbox);
        }
    }

    function _sdgnrsTransfers(Vm.Log[] memory logs) internal view returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(sdgnrs) && logs[i].topics[0] == TRANSFER_TOPIC) ++count;
        }
    }

    function _seedFlipBacking(uint128 wholeFlip) internal {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), uint256(2)));
        uint256 packed = uint256(vm.load(address(coinflip), slot));
        vm.store(address(coinflip), slot, bytes32((packed & (type(uint256).max << 128)) | wholeFlip));
        vm.prank(address(sdgnrs));
        assertGe(coinflip.redeemableFlipBacking(), wholeFlip);
    }

    uint256 internal settlementWord;

    function _openBatchId() internal view returns (uint32 id) { (id,,,) = sdgnrs.redemptionBatchState(); }
    function _rollOf(uint32 id) internal view returns (uint16 roll) { (,,,,roll,) = sdgnrs.redemptionBatches(id); }
    function _claimBase(address player, uint32 id) internal view returns (uint256) {
        (uint128 tokens,,uint96 ethBase,,,) = sdgnrs.redemptionBatches(id);
        return tokens == 0 ? 0 : uint256(ethBase) * _claimTokens(player, id) / tokens;
    }
    function _wordForRoll(uint16 roll) internal pure returns (uint256) {
        require(roll >= 21 && roll <= 175, "roll range");
        return (uint256(roll - 21) << 8) | 2;
    }
    /// @dev Isolated worker fixture. Uses production close and resolution; only the Game's
    /// stage view is mocked. Engine integration tests use real requests instead.
    function _resolveLive(uint16 roll) internal returns (uint32 id) {
        id = _openBatchId();
        _closeAsGame();
        settlementWord = _wordForRoll(roll);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage()"), abi.encode(uint8(1)));
        vm.prank(address(game));
        sdgnrs.runRedemptionWork(settlementWord, 200_000);
        assertEq(_rollOf(id), roll);
    }
    function _work(uint256 budget) internal returns (bool done) {
        vm.prank(address(game));
        return sdgnrs.runRedemptionWork(settlementWord, budget).done;
    }
    function _cursor() internal view returns (uint32 cursor) { (,,cursor,) = sdgnrs.redemptionBatchState(); }
    function _oneClaimBudget() internal returns (uint256 budget) {
        uint32 cursor = _cursor();
        for (budget = 500_000; budget <= 4_000_000; budget += 25_000) {
            uint256 snap = vm.snapshotState();
            _work(budget);
            bool moved = _cursor() != cursor || !sdgnrs.redemptionSettlementPending();
            assertTrue(vm.revertToState(snap));
            if (moved) return budget;
        }
        revert("no admissible claim");
    }
    function _terminalize() internal {
        vm.clearMockedCalls();
        vm.prank(address(game));
        sdgnrs.resolveTerminalRedemptions();
        _latchGameOver();
    }
}
