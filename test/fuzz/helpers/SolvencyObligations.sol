// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {TicketQueueStorage} from "./TicketQueueStorage.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {IStETH} from "../../../contracts/interfaces/IStETH.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @title SolvencyObligations -- canonical ETH-obligation set for the game contract
/// @notice Computes the contract's ETH-denominated obligations and backing so solvency invariants
///         can assert `backing(game) >= obligations(game)` across automatic ETH-to-stETH staking.
///
///         The set mirrors the contract's own obligation sum, `DegenerusGameStorage._untrackedYield`
///         (current + next + future + claimablePool + yieldAccumulator + the frozen purchase
///         buffer). Two facts a naive `current + next + future + claimable + yield` sum gets wrong:
///
///         1. FREEZE-WINDOW PENDING BUFFER (must be INCLUDED). During the daily-RNG freeze window,
///            revenue credited to the pools routes to `prizePoolPendingPacked` (packed
///            `[sentinel:1 | future:127 | next:128]`). That buffer has NO external view, so the live
///            pool views miss it while the ETH is in balance and owed. `_untrackedYield` adds
///            `pNext + pFuture`, so the helper does too. Bit 255 is the slot's nonzero sentinel,
///            never value. Reads 0 when not frozen (`_unfreezePool` folds the buffer and leaves only
///            the sentinel).
///
///         2. DEAD POST-GAME-OVER LIVE POOLS (must be EXCLUDED). The terminal drain
///            (`DegenerusGameGameOverModule._handleGameOverDrain`) zeroes the live pools and
///            distributes `available = totalFunds - claimablePool`; the only remaining ETH
///            obligation is `claimablePool`. Any `futurePrizePool` residual after the drain is
///            whale-pass-conversion bookkeeping whose `claimWhalePass` reverts under
///            `_livenessTriggered()` (`DegenerusGameWhaleModule.claimWhalePass`): it awards only
///            post-game tickets, never withdrawable ETH. Counting it double-counts a dead pool.
///
///         `obligations()` is exactly the set of ETH the contract is on the hook to pay out, so
///         `backing(game) < obligations(game)` is a genuine insolvency signal. `claimablePool` stays in
///         the post-game-over set, so a path that raises `claimablePool` above custody is caught.
library SolvencyObligations {
    /// @dev Authoritative slot for `prizePoolPendingPacked` on DegenerusGame (GameSlots, pinned by
    ///      StorageSlotPins). Packed `[sentinel:1 | future:127 | next:128]`, matching _setPendingPools.
    uint256 internal constant PRIZE_POOL_PENDING_PACKED_SLOT = GameSlots.PRIZE_POOL_PENDING_PACKED;

    // Cheatcode address (forge-std Vm). Used to read the no-external-view pending buffer.
    address internal constant VM_ADDRESS =
        address(uint160(uint256(keccak256("hevm cheat code"))));

    /// @notice Game-held backing, matching `_untrackedYield`'s ETH + stETH assets.
    /// @dev Pool obligations are ETH-denominated; automatic staking changes the custody asset
    ///      without reducing those obligations. Count only assets held by the Game itself.
    function backing(DegenerusGame game) internal view returns (uint256) {
        return address(game).balance + IStETH(ContractAddresses.STETH_TOKEN).balanceOf(address(game));
    }

    /// @notice The contract's TRUE ETH obligation set at the current state.
    /// @param game The DegenerusGame under test.
    /// @return The sum of all ETH obligations the contract is liable to pay out.
    function obligations(DegenerusGame game) internal view returns (uint256) {
        // Queue records share the registry slot; attest their boundaries while checking pool solvency.
        uint24 active = game.currentLvl();
        for (uint24 lvl = active; lvl <= active + 5; ++lvl) {
            TicketQueueStorage.assertQueue(address(game), lvl);
            TicketQueueStorage.assertQueue(address(game), lvl | uint24(1 << 23));
            TicketQueueStorage.assertQueue(address(game), lvl | uint24(1 << 22));
        }
        // Post-game-over: the live pools are dead (drain zeroed them and distributed the
        // difference to claimable). The only withdrawable ETH obligation is claimablePool.
        if (game.gameOver()) {
            return game.claimablePoolView();
        }

        // Live: the full set the contract reserves, including the freeze-window pending buffer.
        (uint256 pendingNext, uint256 pendingFuture) = pendingPools(game);
        return game.currentPrizePoolView()
            + game.nextPrizePoolView()
            + game.futurePrizePoolView()
            + game.claimablePoolView()
            + game.yieldAccumulatorView()
            + pendingNext
            + pendingFuture;
    }

    function ticketViewMatches(DegenerusGame game, uint24 lvl, address player) internal view returns (bool) {
        uint256 sum = uint32(TicketQueueStorage.owed(address(game), lvl, player) >> 8);
        sum += uint32(TicketQueueStorage.owed(address(game), lvl | uint24(1 << 23), player) >> 8);
        sum += uint32(TicketQueueStorage.owed(address(game), lvl | uint24(1 << 22), player) >> 8);
        return uint32(sum) == game.entriesOwedView(lvl, player);
    }

    /// @notice Read the freeze-window pending buffer (no external view exists for it).
    /// @return next  The pending next-pool accumulator (low 128 bits of the slot).
    /// @return future The pending future-pool accumulator (bits 128-254; bit 255 is the sentinel).
    function pendingPools(DegenerusGame game)
        internal
        view
        returns (uint256 next, uint256 future)
    {
        // Mirrors _getPendingPools: unfrozen, the buffer holds only the sentinel.
        bytes32 packed = Vm(VM_ADDRESS).load(
            address(game),
            bytes32(PRIZE_POOL_PENDING_PACKED_SLOT)
        );
        next = uint256(packed) & ((uint256(1) << 128) - 1);
        future = (uint256(packed) >> 128) & ((uint256(1) << 127) - 1);
    }
}
