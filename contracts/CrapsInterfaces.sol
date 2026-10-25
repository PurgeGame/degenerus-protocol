// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MineFlipGas} from "./libraries/MineFlipGas.sol";
import {Craps} from "./Craps.sol";
import {CrapsBattleStorage} from "./storage/CrapsBattleStorage.sol";

/// @dev Read-only engine surface exposed by the consolidated table.
interface ICrapsEngine {
    function settleBattle(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll,
        uint256 goal, uint48 bound, uint256 field, uint256 word) external pure returns (Craps.SlipResult memory);

    function settleBattleCompact_g439244(uint256 betId, uint256 header, uint256 chipFlip, uint256 bankroll,
        uint256 goal, uint48 bound, uint256 field, uint256 word)
        external pure returns (uint256 paid, uint256 won, uint256 rank, uint256 hottestHand);

    function customDefinition(uint32 played, uint8 bankMult, uint16 goalMult, uint24 stakeUnits, uint40 closeTime, bool multiEntry, uint16 highRollerMult) external view returns (uint256);
}

/// @dev The one FLIP sink this game uses, authorized to `ContractAddresses.CRAPS` in the
///      protocol's FLIP.sol. Craps only ever BURNS: a stake goes in and nothing here hands liquid
///      FLIP back, because nothing here is ever given back. Every payment — a run's winnings, a
///      pot, a lane — ships as coinflip credit.
interface IFlipCoin {
    /// @notice FLIP.sol's burn of `amount` from `target`'s FLIP balance, consuming settled
    ///         coinflip winnings only for the shortfall.
    function burnCoin(address target, uint256 amount) external;
    /// @dev The paid-craps twin. Takes the price with action flags in its low byte and hands back
    ///      the one-hot craps-boon tier consumed by this burn (0 on every burn that consumed none).
    ///      The FLIP burn stays on `target`'s address, which is the account's PAYEE (the caller
    ///      for a self door, a smurf's owner, or an ordinary account's own key); `id` is the
    ///      account's nonzero wallet ID, obtained by the table before the bet body, which keys
    ///      the craps boon lane and the craps quest. A comp burn ignores `id`.
    function burnCoinForCraps(address target, uint32 id, uint256 grossAndFlags) external returns (uint8 boonMask);
    /// @dev Feed the craps comp lane: two percent of a completed field's eligible bankroll.
    function creditCrapsComps(uint256 amount) external;
}

/// @dev The vault's ownership test — the pinned DGVE governance executor. The only authority this contract
///      recognises: it opens a custom battle and grants or revokes battle creators
///      (`setBattleCreator`). The vault saves its board through the ordinary player surface.
interface IVaultOwnership {
    /// @notice DegenerusVault's pinned governance owner check for `account`.
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev Mint-history entry pricing, account resolution and the daily RNG lock.
interface IGameCraps {

    /// @notice Raw mint history: lifetime count, last mint level and deity ownership. Read for
    ///         the account ID (newcomer pricing follows its own mint history).
    function mintPackedOfId_g5372(uint32 id) external view returns (uint256);

    /// @notice Resolve account `id` for `caller`: key, payee and whether `caller` may act for it
    ///         (its key, a smurf's owner, or an approved operator). Reverts for an unallocated
    ///         or zero `id`; never reverts on authorization. Player doors require `authorized`;
    ///         `vaultComp` uses only the key.
    function resolveAccount_g7029(uint32 id, address caller)
        external view returns (address key, address payee, bool authorized);
    function currentLvl() external view returns (uint24);
    /// @notice Daily request through final day seal, including a fulfilled, pending jackpot battle.
    function rngLocked() external view returns (bool);
}

interface IHighRollerReserve {
    function settleHighRollerReserve(uint64 slot) external;
}

/// @dev Run winnings and competitive battle pots pay as next-day coinflip stake. The batch lane
///      lets a slot settle many entrants with one external call.
interface ICoinflipStake {

    /// @notice Coinflip's credit of `amount` FLIP stake to wallet `id` (0 is a no-op).
    function creditFlip_g317(uint32 id, uint256 amount) external;
    /// @notice Coinflip's batched credit of `amounts` FLIP stake to wallets `ids` (zero IDs and
    ///         zero amounts are skipped).
    function creditFlipBatch(uint32[] calldata ids, uint256[] calldata amounts) external;
    /// @notice Arm THE BIGGEST DICE RUN — the fifth category of the shared BIGGEST record.
    /// @dev CRAPS only, and this kind only: the generic `armRecord` door is the GAME's and
    ///      carries the four existing kinds' 20%-improvement claim rule, which is not this one's.
    ///      Coinflip credits the claim itself, so a finalization makes ONE call and the player
    ///      takes ONE credit.
    ///      The claim is credited by wallet ID; the sDGNRS leg and the trophy go to the payee
    ///      Game's `payRecordSdgnrs` returns. Bets hold nonzero IDs, so the table never passes 0.
    /// @param id The run owner's wallet ID, credited with the claim.
    /// @param candidate The winner's high point over its starting bankroll, in basis points.
    /// @dev DECLARED WITHOUT ITS RETURN, deliberately. `Coinflip` returns the FLIP it claimed and
    ///      logs it in `BigRecordUpdated`; nothing on this side of the call needs the figure, so
    ///      the table does not pay to decode one. The selector is the same either way.
    function armDiceRunRecord(uint32 id, uint256 candidate) external;
}

interface IReadCohortLifecycle {
    function admitCustom(uint64 slot) external;

    function registerRngSlot_g709(uint48 index, uint64 slot, bytes32 key) external;

    function resolveRngSlot_g1079(uint64 slot, uint256 allowance) external returns (MineFlipGas.Result memory);

    function finalizeBattle_g3665(CrapsBattleStorage.Window calldata w, uint256 board, uint256 word) external;
    function payBattlePot(uint64 slot, bytes32 key, uint256 winnerId, uint256 pot, uint256 boost, uint256 word) external;
}
