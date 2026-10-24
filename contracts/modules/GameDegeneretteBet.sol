// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameBoxInternals} from "./GameBoxInternals.sol";
import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {RECORD_KIND_SPIN} from "../interfaces/ICoinflip.sol";
import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {GameBoonActions} from "./GameBoonActions.sol";

/// @dev Shared internal implementation in Game storage.
abstract contract GameDegeneretteBet is DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils, GameBoonActions {
    /// @notice Thrown when bet parameters are invalid (zero amount, below minimum, invalid spec, etc.).
    error InvalidBet();

    /// @notice Thrown when an unsupported currency type is specified.
    error UnsupportedCurrency();

    /// @notice Emitted when a Degenerette bet is placed.
    /// @param player The bet owner (the address paid when it resolves).
    /// @param index The lootbox RNG index this bet is tied to.
    /// @param betId The bet's id within `index`: its queue position + 1.
    /// @param packed The queued bet word (layout on DegenerusGameStorage.degeneretteQueue).
    event DegeneretteBetPlaced(
        uint32 indexed player,
        uint32 indexed index,
        uint64 indexed betId,
        uint256 packed
    );

    /// @notice Paid ETH on a protocol deity's hero enters its next-day boon draw.
    event ProtocolBoonDrawEntered(
        uint32 indexed issuer,
        uint32 indexed player,
        uint24 indexed day,
        uint256 amount,
        uint16 scoreSnapshot,
        uint64 weight,
        uint32 entryIndex
    );

    /// @dev Currency type identifier for ETH.
    uint8 internal constant CURRENCY_ETH = 0;

    /// @dev Currency type identifier for FLIP token.
    uint8 internal constant CURRENCY_FLIP = 1;

    /// @dev Minimum bet amount for ETH (0.005 ETH on mainnet).
    uint256 internal constant MIN_BET_ETH = 5 ether / 1000;

    /// @dev Minimum bet amount for FLIP (100 whole FLIP).
    uint256 internal constant MIN_BET_FLIP = 100;

    /// @dev Entry floor for the record path, on the bet's total ETH. A bet under this
    ///      never pays the record call at all, which keeps the external arm off the
    ///      overwhelming majority of ETH bets. Sound because the record is only ever
    ///      written by a bet that cleared this floor, so it is always 0 or >= the
    ///      floor: a smaller bet could not have beaten it anyway. The floor is the
    ///      record's bootstrap minimum.
    uint256 internal constant BIGGEST_SPIN_MIN_ETH = 1 ether;

    /// @dev Maximum spins per bet, per currency (encoded as ticketCount in the packed bet).
    uint8 internal constant MAX_SPINS_ETH = 25;

    uint8 internal constant MAX_SPINS_FLIP = 15;

    /// Every symbol choice has the same distribution. The hero lane's color is wild, the
    /// house rolls a wild per lane at 1/16, and the result-wild multiplier shares the
    /// ETH/FLIP table. Internal WWXRP reward spins add a 5% help gate and a 70–130%
    /// activity target.
    //
    // -------------------------------------------------------------------------

    uint256 internal constant BET_SYMBOL_SHIFT = 32;

    uint256 internal constant BET_COUNT_SHIFT = 37;

    uint256 internal constant BET_CURRENCY_SHIFT = 42;

    uint256 internal constant BET_RECORD_FLAG = uint256(1) << 43;

    uint256 internal constant BET_ACTIVITY_SHIFT = 44;

    uint256 internal constant BET_STAKE_SHIFT = 60;

    /// @dev Stake units. An ETH stake is whole gwei and a FLIP stake whole FLIP, so 64 bits
    ///      cover any stake (about 1.8e10 ETH or 1.8e19 FLIP per spin). Placement rejects an
    ///      amount that is not a whole unit; a boon bonus floors to the unit.
    uint256 internal constant ETH_STAKE_UNIT = 1 gwei;

    uint256 internal constant FLIP_STAKE_UNIT = 1;

    uint256 internal constant MASK_64 = 0xFFFFFFFFFFFFFFFF;

    /// @dev Placement inputs and values kept across registration, accounting and funding.
    struct BetPlacement {
        uint32 playerId;
        address burnFrom;
        bool gift;
        uint8 currency;
        uint128 amountPerSpin;
        uint8 spinCount;
        uint8 symbol;
        uint24 lvl;
        uint32 funderId;
        uint256 unit;
        uint256 totalBet;
        uint48 index;
        uint32 questStreak;
        uint16 activityScore;
        uint256 recordBounty;
    }

    /// @notice Places a Degenerette bet with one chosen symbol and a generated ticket.
    /// @dev Single chosen-attribute pick.
    ///      spinCount is treated as "spin count": each spin resolves independently but shares
    ///      the same lootbox RNG index/word (derived per spin).
    ///      The bet always belongs to account `id` (0 = caller). Funding source: a caller
    ///      authorized for the account (its payee — the key or a smurf's owner — or an approved
    ///      operator) spends the account's funds: fresh ETH from the caller, the claimable
    ///      shortfall from the account's ledger, FLIP burned from the account's payee, quest to
    ///      the account. Any other caller funds the bet itself — a permissionless gift (the
    ///      caller pays and earns the quest, the existing account receives the bet and its
    ///      winnings).
    /// @param id The account the bet belongs to (0 = caller; otherwise allocated).
    /// @param currency Currency type (0=ETH, 1=FLIP; all other values unsupported).
    /// @param amountPerSpin Bet amount per ticket.
    /// @param spinCount Number of spins (per-currency cap: ETH 25 / FLIP 15).
    /// @param symbol Chosen hero symbol (0..23: Crypto, Zodiac, Cards); quadrant = symbol >> 3.
    function _placeBet(uint32 id, uint8 currency, uint128 amountPerSpin, uint8 spinCount, uint8 symbol) internal {
        if (_livenessTriggered()) revert GameOver();
        BetPlacement memory c;
        c.playerId = id;
        c.currency = currency;
        c.amountPerSpin = amountPerSpin;
        c.spinCount = spinCount;
        c.symbol = symbol;
        c.burnFrom = msg.sender;
        if (id != 0) {
            bool authorized;
            (, c.burnFrom, authorized) = _account(id, msg.sender);
            c.gift = !authorized;
        }
        if (c.gift) c.burnFrom = msg.sender;
        _placeDegeneretteBet(c);
    }

    /// @dev Internal implementation for placing a Degenerette bet. The bet and its winnings
    ///      belong to `player`. An authorized bet is funded by the account (claimable by its
    ///      ID, FLIP from `burnFrom` = its payee) and earns the account's quest; a gift is
    ///      funded entirely by the caller (`burnFrom` = the caller), which registers as a paying
    ///      funder and earns the quest.
    function _placeDegeneretteBet(BetPlacement memory c) internal {
        c.lvl = level;
        {
            uint256 spendWei = uint256(c.amountPerSpin) * c.spinCount;
            if (c.currency != CURRENCY_ETH) spendWei = spendWei * PriceLookupLib.priceForLevel(c.lvl + 1) / PRICE_COIN_UNIT;
            c.playerId = _registerCallerAccount(c.playerId == 0 ? _walletIdOf(msg.sender) : c.playerId, spendWei);
            c.funderId = c.playerId;
            if (c.gift) (c.funderId, ) = _registerWallet(msg.sender, spendWei);
        }
        _placeDegeneretteBetCore(c);
        _collectBetFunds(c.burnFrom, c.funderId, c.currency, c.totalBet, c.symbol);
        quests.handleDegenerette(c.funderId, c.totalBet, c.currency == CURRENCY_ETH,
            c.currency == CURRENCY_ETH ? PriceLookupLib.priceForLevel(c.lvl + 1) : 0);
    }

    function _placeDegeneretteBetCore(BetPlacement memory c) internal {
        // Only ETH and FLIP may fund a player bet. WWXRP remains an internal
        // reward-spin currency and never enters the bet book.
        uint8 maxSpins;
        uint256 minBet;

        if (c.currency == CURRENCY_ETH) {
            maxSpins = MAX_SPINS_ETH;
            minBet = MIN_BET_ETH;
            c.unit = ETH_STAKE_UNIT;
        } else if (c.currency == CURRENCY_FLIP) {
            maxSpins = MAX_SPINS_FLIP;
            minBet = MIN_BET_FLIP;
            c.unit = FLIP_STAKE_UNIT;
        } else {
            revert UnsupportedCurrency();
        }
        if (c.spinCount == 0 || c.spinCount > maxSpins) revert InvalidBet();
        if (uint256(c.amountPerSpin) < minBet || uint256(c.amountPerSpin) % c.unit != 0) revert InvalidBet();
        if (c.symbol >= DEGENERETTE_HERO_COUNT) revert InvalidBet();

        c.index = _rngWriteBuffer();
        // The physical write buffer is always the opposite of the published
        // read buffer. Its word cannot be exposed by _lootboxWord; admission
        // already fixes this bet to the next session before any external call.

        c.totalBet = uint256(c.amountPerSpin) * uint256(c.spinCount);
        // Decay-aware effective quest streak: a streak
        // lapsed past its shields reads 0, so a returning-inactive player can't snapshot a
        // stale-high streak into the bet's activityScore (which scales the ETH ROI and the
        // lootbox-share EV multiplier). This snapshot precedes the new bet's quest credit.
        c.questStreak = _effectiveQuestStreak(c.playerId);
        c.activityScore = uint16(
            _playerActivityScoreCachedAt(c.playerId, c.questStreak, c.lvl + 1, c.lvl)
        );

        // ETH-only per-bet bookkeeping: biggest-spin record and protocol boon entries.

        if (c.currency == CURRENCY_ETH) {
            uint24 day = _gameDay();
            // Gate the record behind the entry floor: a bet under it can never hold
            // the record, so skipping the call costs no outcome and keeps the external
            // arm off the bets that make up nearly all ETH volume. The candidate is
            // the bet's TOTAL ETH — the whole transaction's wager, spins included.
            // Gifted bets arm normally: the ETH is real and the record belongs to
            // `player`.
            //
            // The claim does not pay out here. It waits beside the queued bet as whole FLIP
            // and resolves as its own FLIP spin chain off the very word THIS bet is
            // already bound to — the unpublished write buffer,
            // so a claim can never be armed against a known word. Beating the
            // biggest-spin record therefore buys a spin, not flip credit.
            if (c.totalBet >= BIGGEST_SPIN_MIN_ETH) {
                uint256 whole = coinflip.armRecord(
                    RECORD_KIND_SPIN,
                    c.playerId,
                    c.totalBet
                );
                c.recordBounty = whole;
            }

            uint256 wagerUnit = c.totalBet / 1e14;
            if (c.symbol == 0 || c.symbol == 6) {
                // Canonical boon score uses the routed ticket level. Reuse the
                // effective quest streak already read, before this bet's quest credit.
                uint16 boonScore = _activeTicketLevel() == c.lvl + 1
                    ? c.activityScore
                    : uint16(_playerActivityScore(c.playerId, c.questStreak));
                _enterProtocolBoonDraw(
                    c.playerId, c.symbol, day, c.totalBet, wagerUnit, boonScore
                );
            }
        }

        // Degenerette stake boon: consumed here, AFTER every raw-stake consumer above (the
        // biggest-spin record, protocol boon entries, and the caller's `totalBet` —
        // which funds collection and the pool credit). The bonus rides the PACKED bet only,
        // so the player spins on more than they paid without any unfunded ETH entering the
        // pools. ETH solvency is unaffected: an ETH win is capped at a share of the live pool
        // at distribution time. The jackpot also respects the million-x paid-stake cap.
        //
        // Self-or-operator-funded bets only, mirroring the coinflip deposit boon's funder
        // gate: a permissionless gift must never spend the recipient's boon (a dust gift
        // could burn it), so a gifted bet skips even the lane read. The bet's own currency
        // lane is read inline first (this module shares the Game's storage), so a player
        // holding no boon in THIS currency — the overwhelmingly common case — pays one
        // SLOAD instead of a nested dispatch; boons in the other currency lanes are
        // untouched by construction.
        uint256 stakeUnits = uint256(c.amountPerSpin) / c.unit;
        uint16 boonBps;
        if (
            !c.gift &&
            ((boonPacked[c.playerId].slot1 >> _degeneretteLaneShift(c.currency)) &
                BP_LANE_TIER_MASK) != 0
        ) {
            boonBps = _consumeDegeneretteBoon(c.playerId, c.currency);
        }
        if (boonBps != 0) {
            uint256 boostBase = c.totalBet;
            if (c.currency == CURRENCY_ETH) {
                if (boostBase > DEGENERETTE_BOON_ETH_CAP) boostBase = DEGENERETTE_BOON_ETH_CAP;
            } else if (c.currency == CURRENCY_FLIP) {
                if (boostBase > DEGENERETTE_BOON_FLIP_CAP) boostBase = DEGENERETTE_BOON_FLIP_CAP;
            }
            // Spread across the spins, then floor to the stake unit: integer division drops
            // the sub-unit dust, matching the whole-granule rounding of the other award paths.
            stakeUnits += ((boostBase * boonBps) / 10_000) / c.spinCount / c.unit;
        }
        if (stakeUnits > MASK_64) revert InvalidBet();

        // The bet itself is the sweep's queue entry: a paired lane, appended at this index. Its
        // id is the queue position + 1, fixed here while the index word is still unset. The
        // position is the buffer's write count, which `_collectBetFunds` commits in the
        // lootboxRngPacked write it makes for every bet.
        uint256 position = uint32(lootboxRngPacked >> LR_BET_COUNT_SHIFT);
        uint64 betId = uint64(position + 1);
        uint256 bet =
            uint256(c.playerId) |
            (uint256(c.symbol) << BET_SYMBOL_SHIFT) |
            (uint256(c.spinCount) << BET_COUNT_SHIFT) |
            (uint256(c.currency) << BET_CURRENCY_SHIFT) |
            (uint256(c.activityScore) << BET_ACTIVITY_SHIFT) |
            (stakeUnits << BET_STAKE_SHIFT);
        if (c.recordBounty != 0) {
            bet |= BET_RECORD_FLAG;
            degeneretteRecordBounty[(uint256(c.index) << 64) | betId] = c.recordBounty;
        }
        _storeDegeneretteBet(c.index, position, bet);
        emit DegeneretteBetPlaced(c.playerId, uint32(c.index), betId, bet);
    }

    /// @dev Only ordinary ETH placements reach this helper. A gifted bet belongs
    ///      to its recipient; all weight is paid stake, before any boon boost.
    ///      Pool and entry writes revert atomically if later funding fails.
    function _enterProtocolBoonDraw(
        uint32 playerId, uint8 symbol, uint24 day, uint256 amount, uint256 wagerUnits, uint16 score
    ) internal {
        uint32 issuer = symbol == 0 ? VAULT_WALLET_ID : SDGNRS_WALLET_ID;
        if (deityBySymbol[symbol] != (symbol == 0 ? VAULT_WALLET_ID : SDGNRS_WALLET_ID)) return;
        uint256 weight = wagerUnits * ActivityCurveLib.boonDrawMultUnits(score);
        if (weight > type(uint64).max) revert InvalidBet();
        // The ring slot for `day` (see protocolBoonPools). One still tagged with an older day
        // starts over empty; its entries are overwritten from index 0.
        uint24 ring = day & 1;
        ProtocolBoonPool memory pool = protocolBoonPools[_protocolBoonIndex(issuer)][ring];
        if (pool.day != day) pool = ProtocolBoonPool(0, 0, 0, 0, day);
        uint32 index = pool.entryCount;
        uint64 cumulativeWeight = pool.totalWeight + uint64(weight);
        ProtocolBoonEntry storage entryTarget = protocolBoonEntries[_protocolBoonIndex(issuer)][ring][index];
        uint256 entryWord = uint256(playerId) | (uint256(cumulativeWeight) << 32) | (uint256(score) << 96);
        assembly ("memory-safe") { sstore(entryTarget.slot, entryWord) }
        // Weight <= uint64.max and multiplier >= 800 bound amount well below uint112.
        pool.totalWageredWei += uint112(amount);
        pool.totalWeight = cumulativeWeight;
        pool.entryCount = index + 1;
        // Write the packed header once. Struct assignment can emit multiple read/modify
        // writes for these fields even though all five fit in one word.
        ProtocolBoonPool storage target = protocolBoonPools[_protocolBoonIndex(issuer)][ring];
        uint256 header = uint256(pool.totalWageredWei) | (uint256(pool.totalWeight) << 112)
            | (uint256(pool.entryCount) << 176) | (uint256(pool.awardedMask) << 208)
            | (uint256(pool.day) << 216);
        assembly ("memory-safe") { sstore(target.slot, header) }
        emit ProtocolBoonDrawEntered(issuer, playerId, day, amount, score, uint64(weight), index);
    }

    /// @dev Processes bet funds (burn tokens, handle ETH, check pool). `burnFrom` pays a FLIP
    ///      bet; `playerId` is the funding ledger.
    function _collectBetFunds(
        address burnFrom,
        uint32 playerId,
        uint8 currency,
        uint256 totalBet,
        uint8 symbol
    ) internal {
        if (currency == CURRENCY_ETH) {
            // ETH covers the bet first; any shortfall draws claimable (to the 1-wei
            // sentinel) then afking via the canonical single-sink waterfall.
            if (msg.value > totalBet) revert InvalidBet();
            if (msg.value < totalBet) {
                _settleShortfall(playerId, totalBet - msg.value, true);
            }

            // Update pool and pending
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(pNext, pFuture + uint128(totalBet));
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(next, future + uint128(totalBet));
            }
            // The raw paid total also feeds the hero ledger. Merge its buffer metadata
            // into the already-required pending-ETH write: no extra metadata word or
            // SSTORE on a bet. The minimum ETH stake guarantees nonzero hero units.
            uint256 lrWord = _recordHeroWager(
                symbol >> 3, symbol & 7, totalBet / 1e14, lootboxRngPacked
            );
            uint256 pendingEth = ((lrWord >> LR_PENDING_ETH_SHIFT) & LR_PENDING_ETH_MASK)
                + _packEthToMilliEth(totalBet);
            // The bet's queue count commits in this same write.
            lootboxRngPacked = ((lrWord & ~(LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT))
                | ((pendingEth & LR_PENDING_ETH_MASK) << LR_PENDING_ETH_SHIFT)) + (uint256(1) << LR_BET_COUNT_SHIFT);
            // No max payout check needed: ETH payouts are capped at 10% of pool at distribution
            // time, so solvency is guaranteed regardless of jackpot size
        } else if (currency == CURRENCY_FLIP) {
            coin.burnCoin(burnFrom, totalBet);
            // Pending FLIP and the bet's queue count commit in one write.
            uint256 lrWord = lootboxRngPacked;
            lootboxRngPacked = ((lrWord & ~(LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT))
                | ((((lrWord >> LR_PENDING_FLIP_SHIFT) + totalBet) & LR_PENDING_FLIP_MASK) << LR_PENDING_FLIP_SHIFT))
                + (uint256(1) << LR_BET_COUNT_SHIFT);
            // A token bet consumes no ETH; any ETH sent alongside it is absorbed to the funder's
            // withdrawable afking balance (solvency-preserving) rather than stranded in the pool.
            // Zero-value is a no-op, so a normal token bet pays no extra gas.
            _creditAfkingValue(playerId, msg.value);
        }
    }

    /// @dev Consume the degenerette stake boon in this
    ///      bet's own currency lane. Returns 0 when the lane is empty or expired (an
    ///      expired lane is cleared); the other currencies' lanes are never touched.
    function _consumeDegeneretteBoon(
        uint32 id,
        uint8 currency
    ) internal returns (uint16 boonBps) {
        return _consumeDegeneretteStakeBoon(id, currency);
    }
}
