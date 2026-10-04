// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";

/// @title CrapsHarness
/// @notice Exposes the craps table's `internal` settlement path so the TypeScript port of
///         the engine can be proven equal to the real Solidity.
///
/// @dev WHY THIS IS NEEDED AT ALL
///
///      The table deliberately emits no dice: `CrapsBetSettled` carries only `won` and
///      `paid`, because the whole run is a pure function of (word, slot, chips, owner) and
///      "information anyone can replay for nothing" is not worth the gas. The indexer
///      therefore REPLAYS every run off-chain to show players their rolls and standings.
///
///      That replay is only worth trusting if it is proven identical to the deployed code,
///      and re-proven after every re-vendor — a silent drift here would falsify every
///      player-facing number the table produces without failing anything.
///
///      |X| This harness adds NO logic. It inherits CrapsBattle so that every function
///      under test is the one the deployed table actually runs; a re-implementation here
///      would only prove that a copy agrees with a copy.
///
///      TEST-ONLY. Never deployed, never vendored into `contracts/`, and excluded from the
///      testnet profile's build (see the `test` path in foundry.toml) so it can never reach
///      forge-out-testnet, whose artifacts feed `database/scripts/sync-abis.mjs`.
///
///      NOTE ON SIZE: CrapsBattle's own runtime is already ~23.9 KB of the 24,576-byte
///      EIP-170 ceiling, so this subclass exceeds it. Deploy it against anvil started with
///      `--code-size-limit` raised; that changes nothing about the pure functions under test.
contract CrapsHarness is CrapsBattle {
    /// @notice `_crapsSeed` — the table seed for a bound slot.
    function xCrapsSeed(uint256 word, uint48 index) external pure returns (bytes32) {
        return _crapsSeed(word, index);
    }

    /// @notice `_survived` — the owner-keyed second-chance coin for round `n`.
    function xSurvived(bytes32 seed, uint256 n, address player) external pure returns (bool) {
        return _survived(seed, n, player);
    }

    /// @notice The battle-side board derivation, byte for byte as `_settlementOf` does it:
    ///         unpack the named chips, then let the table's word scatter the complement to
    ///         ten. A ticket places zero through seven, so the dice throw `10 - placed`.
    function xResolveBoard(uint256 packed, uint256 boardStakeWei, uint256 word, address owner)
        external
        pure
        returns (Craps.Bets memory board)
    {
        uint256 chipFlip = (boardStakeWei / 1) / 10;
        uint256 placed;
        (, placed) = _packChips(uint32(packed));
        board = _boardFrom(packed, chipFlip);
        // audit ed035463: the scatter draw has its own domain — `_hash3(word, SCATTER_TAG, owner)`.
        _scatterInto(board, _hash3(word, SCATTER_TAG, uint256(uint160(owner))), chipFlip, 10 - placed);
    }

    /// @notice `_settleSlip` — the whole multi-shooter run.
    /// @dev `boost` is the packed shooter-profit schedule the wrapper fixes before the seed
    ///      exists (audit 484a5d60b). Zero is no schedule, which is what a custom table passes
    ///      and what every pre-boost replay is equivalent to; `xShooterBoostTerms` below derives
    ///      the scheduled-window value so the TypeScript port can be proven equal to BOTH halves.
    function xSettle(
        Craps.Bets memory b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        uint256 rollBudget,
        address player,
        uint256 boost
    ) external pure returns (Craps.SlipResult memory) {
        return _settleSlip(b, seed, bankroll, goal, cap, rollBudget, player, boost);
    }

    /// @notice `_shooterBoostTerms` — the packed (roll threshold, uplift) schedule a scheduled window
    ///         hands `_settleSlip`, an eight-row table indexed by how many of the ten chips the
    ///         ticket placed itself. `_settlementOf` derives `placed` from the stored word and
    ///         passes 0 instead for any slot at or above `_CUSTOM_SLOT_BASE`.
    function xShooterBoostTerms(uint256 placed) external pure returns (uint256) {
        return _shooterBoostTerms(placed);
    }

    /// @notice `_packChips` — the board validation every door shares: per-leg cap, pick-a-side,
    ///         and the placed-count sum the settlement scatters against.
    function xPackChips(uint32 c) external pure returns (uint256 packed, uint256 count) {
        return _packChips(c);
    }

    function xStakeFor(Craps.Bets memory b) external pure returns (uint256) {
        return _stakeFor(b);
    }
}
