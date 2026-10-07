// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";

/// @title RedemptionFlipCreditWalletId -- a redemption win credits FLIP to the claim's wallet ID
/// @notice The claim already holds the beneficiary's wallet ID (committed at the burn); a batch
///         whose synthetic flip wins credits `principal + principal * reward / 100` to that ID
///         through `creditFlip(id, …)`. The beneficiary never touched Coinflip, so the stake is
///         visible through walletIdOf and Coinflip's address-keyed cache stays empty.
contract RedemptionFlipCreditWalletIdTest is RedemptionFixture {
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 private constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

    function _cachedId(address p) private view returns (uint32) {
        return uint32(uint256(vm.load(address(coinflip), keccak256(abi.encode(p, uint256(2))))) >> 184);
    }

    /// @dev A settlement word with roll `roll` whose synthetic flip for `batchId` wins.
    function _winningWord(uint16 roll, uint32 batchId) private pure returns (uint256 word) {
        for (uint256 k;; ++k) {
            word = ((k * 155 + roll - 21) << 8) | 2;
            if (_synthReward(word, batchId) != 0) return word;
        }
    }

    function test_RedemptionWin_CreditsFlipToClaimWalletId() public {
        _seedFlipBacking(1_000_000);
        uint32 aliceId = game.walletIdOf(alice);
        assertTrue(aliceId != 0);
        assertEq(_cachedId(alice), 0, "fixture: alice never touched Coinflip");

        uint32 batchId = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() / 1000);
        _closeAsGame();
        settlementWord = _winningWord(100, batchId);
        vm.mockCall(address(game), abi.encodeWithSignature("rngConsumerStage()"), abi.encode(uint8(1)));
        vm.prank(address(game));
        sdgnrs.runRedemptionWork(settlementWord, 200_000);

        (uint256 tokens,, uint256 escrow, uint16 roll, uint16 reward) = _batch(batchId);
        assertEq(roll, 100);
        assertGt(reward, 0, "fixture: the synthetic flip wins");
        assertGt(escrow, 0, "fixture: the batch escrowed FLIP");
        uint256 principal = (escrow * _claimTokens(alice, batchId)) / tokens;
        assertGt(principal, 0);
        uint256 flipPaid = principal + (principal * reward) / 100;
        uint256 before = coinflip.coinflipAmount(alice);

        vm.expectCall(address(coinflip), abi.encodeCall(Coinflip.creditFlip, (aliceId, flipPaid)), 1);
        vm.recordLogs();
        assertTrue(_work(9_000_000), "settlement drains");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(_claimTokens(alice, batchId), 0, "claim settled");
        assertEq(coinflip.coinflipAmount(alice) - before, flipPaid, "credited under the claim's wallet ID");
        assertEq(_cachedId(alice), 0, "the ID credit never touches the address-keyed state");
        bool stake;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == WALLET_REGISTERED) {
                fail("settlement registered a wallet");
            }
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != STAKE_UPDATED) continue;
            if (uint32(uint256(logs[i].topics[1])) != aliceId) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(amount, flipPaid);
            stake = true;
        }
        assertTrue(stake, "stake event under the claim's ID");
    }
}
