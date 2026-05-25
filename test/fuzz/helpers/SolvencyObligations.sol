// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";

/// @title SolvencyObligations -- canonical ETH-obligation set for the game contract
/// @notice Computes the contract's TRUE ETH obligation set so solvency invariants can assert
///         `address(game).balance >= obligations()` and still catch a real `balance < obligations`.
///
///         The set mirrors the contract's own canonical reservation calc in
///         DegenerusGameJackpotModule.distributeYieldSurplus (the only on-chain place the protocol
///         sums its own obligations). Two facts the naive `current + next + future + claimable + yield`
///         sum gets wrong:
///
///         1. FREEZE-WINDOW PENDING BUFFER (must be INCLUDED). During the daily-RNG freeze window,
///            `_swapAndFreeze` (DegenerusGameStorage.sol:755) moves 1% of futurePrizePool into
///            `prizePoolPendingPacked` (slot 11, packed `[future<<128 | next]`). That buffer has NO
///            external view, so `futurePrizePoolView()` drops by the seed while the ETH is still in
///            balance and still owed. The contract counts it (`distributeYieldSurplus` adds
///            `pNext + pFuture`, JackpotModule:710-711), so the harness must too. Reads 0 when not
///            frozen (the buffer is cleared by `_unfreezePool`).
///
///         2. DEAD POST-GAME-OVER LIVE POOLS (must be EXCLUDED). After `handleGameOverDrain`
///            (DegenerusGameGameOverModule.sol:78) the live pools are zeroed and `available =
///            totalFunds - claimablePool` is distributed to claimants; the only remaining ETH
///            obligation is `claimablePool`. Any `futurePrizePool` residual after the drain is
///            whale-pass-conversion bookkeeping whose `claimWhalePass` reverts under
///            `_livenessTriggered()` (DegenerusGameWhaleModule.sol) -- it awards only worthless
///            post-game tickets, never withdrawable ETH. Counting it double-counts a dead pool.
///
///         This is a PRINCIPLED correction, NOT a weakening: `obligations()` still equals the exact
///         set of ETH the contract is on the hook to pay out, so `balance < obligations()` remains a
///         genuine insolvency signal. (The §1 post-game-over Degenerette resolve in
///         323-SOLVENCY-FINDING.md pushed `claimablePool` itself above balance; that path is now
///         contract-guarded at HEAD, and this helper keeps `claimablePool` in the post-GO set so any
///         regression of that guard is still caught.)
library SolvencyObligations {
    /// @dev Authoritative slot for `prizePoolPendingPacked` on DegenerusGame
    ///      (forge inspect contracts/DegenerusGame.sol:DegenerusGame storageLayout @ HEAD).
    ///      Packed `(uint256(future) << 128) | uint256(next)`, matching _setPendingPools.
    uint256 internal constant PRIZE_POOL_PENDING_PACKED_SLOT = 11;

    // Cheatcode address (forge-std Vm). Used to read the no-external-view pending buffer.
    address internal constant VM_ADDRESS =
        address(uint160(uint256(keccak256("hevm cheat code"))));

    /// @notice The contract's TRUE ETH obligation set at the current state.
    /// @param game The DegenerusGame under test.
    /// @return The sum of all ETH obligations the contract is liable to pay out.
    function obligations(DegenerusGame game) internal view returns (uint256) {
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

    /// @notice Read the freeze-window pending buffer (no external view exists for it).
    /// @return next  The pending next-pool accumulator (low 128 bits of slot 11).
    /// @return future The pending future-pool accumulator (high 128 bits of slot 11).
    function pendingPools(DegenerusGame game)
        internal
        view
        returns (uint256 next, uint256 future)
    {
        bytes32 packed = Vm(VM_ADDRESS).load(
            address(game),
            bytes32(PRIZE_POOL_PENDING_PACKED_SLOT)
        );
        next = uint256(uint128(uint256(packed)));
        future = uint256(uint128(uint256(packed) >> 128));
    }
}
