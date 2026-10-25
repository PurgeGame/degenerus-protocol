// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameBoxInternals} from "./GameBoxInternals.sol";
import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {IDegenerusGameWhaleModule, IDegenerusGameDegenesisModule} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {BoundedCall} from "../libraries/BoundedCall.sol";
import {IStETH} from "../interfaces/IStETH.sol";

/// @dev Shared internal implementation in Game storage.
abstract contract GameAfkingClaims is DegenerusGameMintStreakUtils {
    /// @notice Emitted when settlement hands a sub's elapsed affiliate base to the affiliate
    ///         claim — attributes afking-sourced affiliate income to the subscriber whose buys
    ///         generated it. Zero bases do not emit.
    event AffiliateBaseDrained(uint32 indexed sub, uint256 base);

    /// @notice Emitted when settlement pays a sub its own elapsed reward (whole FLIP).
    event AfkingFlipClaimed(uint32 indexed player, uint256 owed);

    /// @dev Slot-0 quest completion reward — mirrors `DegenerusQuests.QUEST_SLOT0_REWARD`
    ///      (a internal constant not visible cross-contract). Every credited day earns it
    ///      (whole FLIP). Only values the FLIP mint, off the solvency path.
    uint256 internal constant QUEST_SLOT0_REWARD = 100;

    /// @dev Ticket-mode buyer bonus per ticket per day: 10% of the ticket's 1,000-FLIP value.
    uint256 internal constant TICKET_BONUS_PER_UNIT = 100;

    /// @dev Affiliate base per unit per day: 7% of the unit's 1,000-FLIP value.
    uint256 internal constant AFFILIATE_BASE_PER_UNIT = 70;

    /// @dev The one settlement: pay member `id` its own reward for every day after its checkpoint
    ///      through `endpoint`, move the checkpoint to `endpoint` (folding those days into the
    ///      checkpoint streak) and return the same days' affiliate base. A no-op while the
    ///      endpoint is not past the checkpoint, which covers a paused protocol seat; the
    ///      checkpoint never moves backward.
    /// @param id The member's wallet ID.
    /// @param position1 Its set position + 1.
    /// @param endpoint The reward endpoint.
    /// @return base Whole-FLIP affiliate base for the settled days.
    function _settle(uint32 id, uint256 position1, uint24 endpoint) internal returns (uint256 base) {
        uint256 lane = _subLaneAt(position1 - 1);
        uint24 day = _subDay(lane);
        if (endpoint <= day) return 0;
        uint256 elapsed;
        uint256 owed;
        uint256 quantity = _subQuantity(lane);
        unchecked {
            elapsed = endpoint - day;
            _setSubLaneAt(position1 - 1, _withSubCheckpoint(lane, endpoint, _subCheckpointStreak(lane) + elapsed));
            owed = elapsed * (lane & SUB_TICKETS_BIT != 0
                ? QUEST_SLOT0_REWARD + TICKET_BONUS_PER_UNIT * quantity
                : QUEST_SLOT0_REWARD);
            base = elapsed * AFFILIATE_BASE_PER_UNIT * quantity;
        }
        emit AfkingFlipClaimed(id, owed);
        coinflip.creditFlip_g317(id, owed); // whole → base units
        emit AffiliateBaseDrained(id, base);
    }

    /// @notice Affiliate-only settlement of up to eight subs of one run, the base drain the
    ///         affiliate `claim` consumes: pays each sub its own reward and returns their summed
    ///         affiliate base.
    /// @dev Each settlement moves its sub's checkpoint before it pays, so a duplicate sub
    ///      settles nothing the second time. Only `ContractAddresses.AFFILIATE` may drain, so a
    ///      non-affiliate caller can never redirect a sub's base. Returns zeros from the liveness
    ///      trigger onward. Runs in the Game's storage context; `msg.sender` is the original caller.
    /// @param ids Up to eight subscriber IDs, 32 bits each from the low end, all sharing one direct
    ///        affiliate. A zero lane and a non-member settle nothing.
    /// @param uplines The run's two upline IDs packed low/high 32 bits (zero for no referrer).
    /// @return sumB The settled whole-FLIP affiliate base.
    /// @return skipU1 The part of `sumB` from subs that are themselves the first upline.
    /// @return skipU2 The part of `sumB` from subs that are themselves the second upline.
    function _drainAffiliateBases(uint256 ids, uint256 uplines)
        internal returns (uint256 sumB, uint256 skipU1, uint256 skipU2)
    {
        if (msg.sender != ContractAddresses.AFFILIATE) revert NotApproved();
        if (_livenessTriggered()) return (0, 0, 0);
        uint24 endpoint = _afkingEndpoint();
        for (; ids != 0; ids >>= 32) {
            uint32 id = uint32(ids);
            uint256 position1 = _subPosition1(id);
            if (position1 == 0) continue;
            uint256 base = _settle(id, position1, endpoint);
            if (base != 0) {
                sumB += base;
                if (id == uint32(uplines)) skipU1 += base;
                if (id == uint32(uplines >> 32)) skipU2 += base;
            }
        }
    }

    /// @dev A member whose run is live (not pending removal): immune to curse and smite.
    function _isLiveMember(uint32 id) internal view returns (bool) {
        (uint256 lane, uint256 position1) = _subLaneOf(id);
        return position1 != 0 && lane & SUB_REMOVAL_BIT == 0;
    }

    /// @notice Cashout-curse SET (delegatecall target from the Game's claimClaimable): a stale
    ///         ghost-cashout adds a saturating +2 stack. Cheapest-first bails skip the SSTORE
    ///         for infra addresses (protects the sDGNRS redemption-snapshot score), gameOver, a
    ///         non-stale claimant, deity holders, active lazy/whale-pass holders, an
    ///         already-capped counter, and an active afker. Net: +2 only on a stale
    ///         cashout by a non-exempt, below-cap player.
    function _maybeCurse(uint32 player) internal {
        if (
            player == VAULT_WALLET_ID ||
            player == SDGNRS_WALLET_ID ||
            player == GNRUS_WALLET_ID
        ) return;
        if (gameOver) return;
        uint256 packed = mintPacked_[player];
        uint24 lastEthDay = uint24(
            (packed >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_24
        );
        if (lastEthDay + 5 > _currentMintDay()) return; // claimed within the 5-day window
        if ((packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1 != 0) return;
        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24
        );
        uint8 passType = uint8(
            (packed >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3
        );
        if (frozenUntilLevel >= level && (passType == 1 || passType == 3)) return;
        if ((packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_5 >= CURSE_COUNT_CAP) return;
        if (_isLiveMember(player)) return;
        _applyCurseStack(player);
    }
}
