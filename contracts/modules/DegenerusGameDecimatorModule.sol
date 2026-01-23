// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusGamepieces} from "../interfaces/IDegenerusGamepieces.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {IBurnieLootbox} from "../interfaces/IBurnieLootbox.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/**
 * @title DegenerusGameDecimatorModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling decimator claim credits and lootbox payouts.
 *
 * @dev This module is called via delegatecall from DegenerusGame, meaning all
 *      storage reads/writes operate on the game contract's storage.
 */
contract DegenerusGameDecimatorModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when ETH is credited to a player's claimable balance.
    /// @param player The original beneficiary (may be same as recipient).
    /// @param recipient The address receiving the credit.
    /// @param amount The wei amount credited.
    event PlayerCredited(
        address indexed player,
        address indexed recipient,
        uint256 amount
    );

    /// @notice Emitted when auto-rebuy converts winnings to tickets.
    /// @param player Player whose winnings were converted.
    /// @param targetLevel Level for which tickets were purchased.
    /// @param ticketsAwarded Number of tickets credited.
    /// @param ethSpent Amount of ETH spent on tickets.
    /// @param remainder Amount returned to claimableWinnings.
    event AutoRebuyProcessed(
        address indexed player,
        uint24 targetLevel,
        uint32 ticketsAwarded,
        uint256 ethSpent,
        uint256 remainder
    );

    /// @notice Emitted when a player burns tokens for jackpot tickets.
    /// @param player The player who burned the tokens.
    /// @param tokenIds Array of token IDs that were burned.
    event Degenerus(address indexed player, uint256[] tokenIds);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Generic revert for invalid values.
    error E();
    error InvalidQuantity();
    error NotTimeYet();
    error RngNotReady();
    error NotApproved();

    // -------------------------------------------------------------------------
    // Precomputed Addresses
    // -------------------------------------------------------------------------

    IDegenerusCoin internal constant coin = IDegenerusCoin(ContractAddresses.COIN);
    IDegenerusGamepieces internal constant gamepieces =
        IDegenerusGamepieces(ContractAddresses.GAMEPIECES);
    IDegenerusStonk internal constant dgnrs =
        IDegenerusStonk(ContractAddresses.DGNRS);
    IBurnieLootbox internal constant lootbox =
        IBurnieLootbox(ContractAddresses.LOOTBOX);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Auto-rebuy bonus in basis points.
    uint16 private constant AUTO_REBUY_BONUS_BPS = 13_000;

    /// @dev afKing auto-rebuy bonus in basis points.
    uint16 private constant AFKING_AUTO_REBUY_BONUS_BPS = 14_500;

    uint16 private constant ETH_PERK_TOTAL_BPS = 500;
    uint16 private constant ETH_PERK_BONUS_BPS = 12_500;
    uint16 private constant BURNIE_PERK_TOTAL_BPS = 500;
    uint16 private constant DGNRS_PERK_TOTAL_BPS = 500;
    uint16 private constant DGNRS_PERK_AQUARIUS_BONUS_BPS = 12_500;
    uint16 private constant BURNIE_PERK_SYMBOL_BONUS_BPS = 12_500;

    uint8 private constant AQUARIUS_SYMBOL_INDEX = 7;
    uint8 private constant ORANGE_KING_COLOR = 5;
    uint8 private constant ORANGE_KING_SYMBOL = 1;
    uint256 private constant ORANGE_KING_TRIBUTE = 25 ether;

    uint8 private constant ETH_PERK_ODDS = 100;
    uint8 private constant ETH_PERK_REMAINDER = 0;
    uint8 private constant BURNIE_PERK_REMAINDER = 1;
    uint8 private constant DGNRS_PERK_REMAINDER = 2;
    uint256 private constant ETH_PERK_SALT = 0x455448;

    uint8 private constant ETH_SYMBOL_INDEX = 6;
    uint8 private constant WWXRP_SYMBOL_INDEX = 0;

    uint16 private constant TRAIT_ID_TIMEOUT = 420;

    uint256 private constant MINT_MASK_24 = (uint256(1) << 24) - 1;
    uint256 private constant ETH_FROZEN_UNTIL_LEVEL_SHIFT = 128;

    struct BurnVars {
        uint24 lvl;
        uint8 mod10;
        uint32 endLevelFlag;
        uint16 prevExterminated;
        uint16 ethPerkExpected;
        uint16 newExterminated;
        uint16 orangeKingCount;
        uint256 currentPrizePool;
        uint256 burniePool;
        uint256 dgnrsPool;
        uint256 bonusTenths;
        address tribute;
        bool exOpen;
        bool ethPerkActive;
        bool dgnrsPerkActive;
        bool hasLazyPass;
    }

    // -------------------------------------------------------------------------
    // External Entry Points (delegatecall targets)
    // -------------------------------------------------------------------------

    /// @notice Batch variant: credit multiple decimator claims (ETH-only during gameover).
    /// @dev Access: ContractAddresses.JACKPOTS contract only.
    ///      Gas-optimized for multiple credits in single transaction.
    ///      Each claim splits 50/50 by default; during GAMEOVER credits 100% ETH.
    ///      Uses VRF randomness from jackpot resolution for lootbox derivation.
    /// @param accounts Array of player addresses to credit.
    /// @param amounts Array of corresponding wei amounts (total before split).
    /// @param rngWord VRF random word from jackpot resolution.
    function creditDecJackpotClaimBatch(
        address[] calldata accounts,
        uint256[] calldata amounts,
        uint256 rngWord
    ) external {
        if (msg.sender != ContractAddresses.JACKPOTS) revert E();
        uint256 len = accounts.length;
        if (len != amounts.length) revert E();

        if (gameState == GAME_STATE_GAMEOVER) {
            for (uint256 i; i < len; ) {
                uint256 amt = amounts[i];
                address account = accounts[i];
                if (amt != 0 && account != address(0)) {
                    _addClaimableEth(account, amt, rngWord);
                }
                unchecked {
                    ++i;
                }
            }
            return;
        }

        uint256 totalLootbox;

        for (uint256 i; i < len; ) {
            uint256 amt = amounts[i];
            address account = accounts[i];
            if (amt != 0 && account != address(0)) {
                // Split 50/50: half ETH, half lootbox tickets
                uint256 ethPortion = amt / 2;
                uint256 lootboxPortion = amt - ethPortion;

                // Credit ETH half
                if (ethPortion != 0) {
                    _addClaimableEth(account, ethPortion, rngWord);
                }

                // Award lootbox half as future tickets (using VRF randomness)
                if (lootboxPortion != 0) {
                    _awardDecimatorLootbox(account, lootboxPortion, rngWord);
                    totalLootbox += lootboxPortion;
                }
            }
            unchecked {
                ++i;
            }
        }

        // Add all lootbox ETH to futurePrizePool once at the end
        if (totalLootbox != 0) {
            futurePrizePool += totalLootbox;
        }
    }

    // -------------------------------------------------------------------------
    // Gamepiece Burning
    // -------------------------------------------------------------------------

    /// @notice Burn gamepieces for jackpot tickets, potentially triggering extermination.
    /// @param player Player address that owns the tokens (address(0) = msg.sender).
    /// @param tokenIds Array of token IDs to burn (1-75 tokens).
    function burnTokens(address player, uint256[] calldata tokenIds) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _burnTokensFor(player, tokenIds);
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    function _requireApproved(address player) private view {
        if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
            revert NotApproved();
        }
    }

    function _burnTokensFor(address caller, uint256[] calldata tokenIds) private {
        if (rngLockedFlag) revert RngNotReady();
        if (gameState != 3) revert NotTimeYet();
        uint256 count = tokenIds.length;
        if (count == 0 || count > 75) revert InvalidQuantity();
        gamepieces.burnFromGame(caller, tokenIds);
        coin.notifyQuestBurn(caller, uint32(count));

        BurnVars memory vars;
        vars.lvl = level;
        vars.mod10 = uint8(vars.lvl % 10);
        vars.endLevelFlag = vars.mod10 == 7 ? 1 : 0;
        vars.prevExterminated = lastExterminatedTrait;
        vars.exOpen = currentExterminatedTrait == TRAIT_ID_TIMEOUT;
        vars.currentPrizePool = currentPrizePool;
        vars.ethPerkExpected = _ethPerkExpectedCount(vars.lvl);
        vars.ethPerkActive = vars.ethPerkExpected != 0;
        if (vars.ethPerkActive && ethPerkLevel != vars.lvl) {
            ethPerkLevel = vars.lvl;
            ethPerkBurnCount = 0;
        }
        if (vars.ethPerkActive) {
            uint256 priceWei = price;
            uint256 lastPool = lastPrizePool;
            if (priceWei != 0 && lastPool != 0) {
                vars.burniePool = (lastPool * PRICE_COIN_UNIT) / priceWei;
            }
            if (vars.burniePool != 0 && burniePerkLevel != vars.lvl) {
                burniePerkLevel = vars.lvl;
                burniePerkBurnCount = 0;
            }
        }
        vars.dgnrsPerkActive = vars.ethPerkExpected != 0;
        if (vars.dgnrsPerkActive) {
            vars.dgnrsPool = dgnrs.poolBalance(IDegenerusStonk.Pool.Reward);
            if (vars.dgnrsPool == 0) {
                vars.dgnrsPerkActive = false;
            } else if (dgnrsPerkLevel != vars.lvl) {
                dgnrsPerkLevel = vars.lvl;
                dgnrsPerkBurnCount = 0;
            }
        }

        vars.hasLazyPass =
            uint24(
                (mintPacked_[caller] >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) &
                    MINT_MASK_24
            ) > vars.lvl;

        vars.tribute = tributeAddress;
        vars.newExterminated = TRAIT_ID_TIMEOUT;

        address[][256] storage tickets = traitBurnTicket[vars.lvl];

        for (uint256 i; i < count; ) {
            uint256 tokenId = tokenIds[i];
            uint32 traitPack = _traitsForToken(tokenId);
            uint8 trait0 = uint8(traitPack);
            bool topLeftEthereum = (trait0 & 0x07) == ETH_SYMBOL_INDEX;
            bool topLeftWwxrp = (trait0 & 0x07) == WWXRP_SYMBOL_INDEX;
            bool ethPerkEligible =
                vars.exOpen &&
                vars.ethPerkActive &&
                _isEthPerkToken(tokenId);
            if (ethPerkEligible) {
                uint256 burnIndex = uint256(ethPerkBurnCount) + 1;
                ethPerkBurnCount = uint16(burnIndex);
                uint256 payout = _ethPerkPayout(
                    vars.currentPrizePool,
                    burnIndex,
                    vars.ethPerkExpected,
                    topLeftEthereum
                );
                if (payout != 0) {
                    if (payout > vars.currentPrizePool) {
                        payout = vars.currentPrizePool;
                    }
                    vars.currentPrizePool -= payout;
                    uint256 entropy = uint256(
                        keccak256(
                            abi.encodePacked(
                                tokenId,
                                vars.lvl,
                                caller,
                                burnIndex
                            )
                        )
                    );
                    _creditEthPerk(caller, payout, entropy);
                }
            }
            bool burniePerkEligible =
                !ethPerkEligible &&
                vars.exOpen &&
                vars.burniePool != 0 &&
                _isBurniePerkToken(tokenId);
            if (burniePerkEligible) {
                uint256 burnIndex = uint256(burniePerkBurnCount) + 1;
                burniePerkBurnCount = uint16(burnIndex);
                uint256 payout = _burniePerkPayout(
                    vars.burniePool,
                    burnIndex,
                    vars.ethPerkExpected
                );
                if (payout != 0 && (topLeftEthereum || topLeftWwxrp)) {
                    payout = (payout * BURNIE_PERK_SYMBOL_BONUS_BPS) / 10_000;
                }
                if (payout != 0) {
                    coin.creditFlip(caller, payout);
                }
            }
            bool dgnrsPerkEligible =
                !ethPerkEligible &&
                !burniePerkEligible &&
                vars.exOpen &&
                vars.dgnrsPerkActive &&
                vars.hasLazyPass &&
                _isDgnrsPerkToken(tokenId);
            if (dgnrsPerkEligible) {
                uint256 burnIndex = uint256(dgnrsPerkBurnCount) + 1;
                dgnrsPerkBurnCount = uint16(burnIndex);
                bool isAquarius =
                    (uint8(traitPack >> 8) & 0x07) == AQUARIUS_SYMBOL_INDEX;
                uint256 payout = _dgnrsPerkPayout(
                    vars.dgnrsPool,
                    burnIndex,
                    vars.ethPerkExpected
                );
                if (isAquarius && payout != 0) {
                    payout = (payout * DGNRS_PERK_AQUARIUS_BONUS_BPS) / 10_000;
                }
                if (payout != 0) {
                    uint256 paid = dgnrs.transferFromPool(
                        IDegenerusStonk.Pool.Reward,
                        caller,
                        payout
                    );
                    if (paid != 0) {
                        vars.dgnrsPool -= paid;
                    }
                }
            }

            uint8 trait1 = uint8(traitPack >> 8);
            uint8 trait2 = uint8(traitPack >> 16);
            uint8 trait3 = uint8(traitPack >> 24);

            if (vars.tribute != address(0)) {
                uint8 cardTrait = trait2 - 128;
                if (
                    (cardTrait >> 3) == ORANGE_KING_COLOR &&
                    (cardTrait & 0x07) == ORANGE_KING_SYMBOL
                ) {
                    unchecked {
                        vars.orangeKingCount += 1;
                    }
                }
            }

            uint8 color0 = trait0 >> 3;
            uint8 color1 = (trait1 & 0x3F) >> 3;
            uint8 color2 = (trait2 & 0x3F) >> 3;
            uint8 color3 = (trait3 & 0x3F) >> 3;
            if (color0 == color1 && color0 == color2 && color0 == color3) {
                unchecked {
                    vars.bonusTenths += 49;
                }
            }

            bool tokenHasPrevExterminated =
                vars.prevExterminated != TRAIT_ID_TIMEOUT &&
                (uint16(trait0) == vars.prevExterminated ||
                    uint16(trait1) == vars.prevExterminated ||
                    uint16(trait2) == vars.prevExterminated ||
                    uint16(trait3) == vars.prevExterminated);

            if (
                (tokenHasPrevExterminated && vars.lvl != 90) ||
                (vars.lvl == 90 && !tokenHasPrevExterminated)
            ) {
                unchecked {
                    vars.bonusTenths += 4;
                }
            }

            if (_consumeTrait(trait0, vars.endLevelFlag, vars.exOpen)) {
                if (vars.newExterminated == TRAIT_ID_TIMEOUT) {
                    vars.newExterminated = trait0;
                }
                vars.exOpen = false;
            }
            if (_consumeTrait(trait1, vars.endLevelFlag, vars.exOpen)) {
                if (vars.newExterminated == TRAIT_ID_TIMEOUT) {
                    vars.newExterminated = trait1;
                }
                vars.exOpen = false;
            }
            if (_consumeTrait(trait2, vars.endLevelFlag, vars.exOpen)) {
                if (vars.newExterminated == TRAIT_ID_TIMEOUT) {
                    vars.newExterminated = trait2;
                }
                vars.exOpen = false;
            }
            if (_consumeTrait(trait3, vars.endLevelFlag, vars.exOpen)) {
                if (vars.newExterminated == TRAIT_ID_TIMEOUT) {
                    vars.newExterminated = trait3;
                }
                vars.exOpen = false;
            }
            unchecked {
                dailyBurnCount[trait0 & 0x07] += 1;
                dailyBurnCount[((trait1 - 64) >> 3) + 8] += 1;
                dailyBurnCount[trait2 - 128 + 16] += 1;
                ++i;
            }

            tickets[trait0].push(caller);
            tickets[trait1].push(caller);
            tickets[trait2].push(caller);
            tickets[trait3].push(caller);
        }

        if (vars.currentPrizePool != currentPrizePool) {
            currentPrizePool = vars.currentPrizePool;
        }

        uint256 tributeAmount;
        if (vars.tribute != address(0) && vars.orangeKingCount != 0) {
            tributeAmount = uint256(vars.orangeKingCount) * ORANGE_KING_TRIBUTE;
        }

        if (vars.mod10 == 2) count <<= 1;
        _creditBurnFlip(
            caller,
            count,
            vars.bonusTenths,
            vars.tribute,
            tributeAmount
        );
        emit Degenerus(caller, tokenIds);

        if (vars.newExterminated != TRAIT_ID_TIMEOUT) {
            _recordExtermination(uint8(vars.newExterminated), caller, vars.lvl);
        }
    }

    function _recordExtermination(
        uint8 exTrait,
        address exterminator,
        uint24 levelSnapshot
    ) private {
        if (currentExterminatedTrait != TRAIT_ID_TIMEOUT) return;

        currentExterminatedTrait = exTrait;
        exterminationPaidThisLevel = false;
        _setExterminatorForLevel(levelSnapshot, exterminator);

        uint16 prevTrait = lastExterminatedTrait;
        bool repeatTrait = prevTrait == uint16(exTrait);
        exterminationInvertFlag = repeatTrait;
    }

    function _creditBurnFlip(
        address caller,
        uint256 count,
        uint256 bonusTenths,
        address tribute,
        uint256 tributeAmount
    ) private {
        uint256 priceUnit = PRICE_COIN_UNIT / 10;
        uint256 flipCredit;
        unchecked {
            flipCredit = (count + bonusTenths) * priceUnit;
        }

        if (tributeAmount != 0 && tribute != address(0)) {
            if (tributeAmount > flipCredit) {
                tributeAmount = flipCredit;
            }
            flipCredit -= tributeAmount;
            if (tributeAmount != 0) {
                coin.creditCoin(tribute, tributeAmount);
            }
        }

        if (flipCredit != 0) {
            coin.creditFlip(caller, flipCredit);
        }
    }

    function _isEthPerkToken(uint256 tokenId) private pure returns (bool) {
        if (tokenId == 0) return false;
        return
            uint256(keccak256(abi.encodePacked(tokenId, ETH_PERK_SALT))) %
                ETH_PERK_ODDS ==
            ETH_PERK_REMAINDER;
    }

    function _isBurniePerkToken(uint256 tokenId) private pure returns (bool) {
        if (tokenId == 0) return false;
        return
            uint256(keccak256(abi.encodePacked(tokenId, ETH_PERK_SALT))) %
                ETH_PERK_ODDS ==
            BURNIE_PERK_REMAINDER;
    }

    function _isDgnrsPerkToken(uint256 tokenId) private pure returns (bool) {
        if (tokenId == 0) return false;
        return
            uint256(keccak256(abi.encodePacked(tokenId, ETH_PERK_SALT))) %
                ETH_PERK_ODDS ==
            DGNRS_PERK_REMAINDER;
    }

    function _ethPerkExpectedCount(uint24 /*lvl*/) private view returns (uint16) {
        return perkExpectedCount;
    }

    function _ethPerkPayout(
        uint256 rewardPoolLocal,
        uint256 burnIndex,
        uint256 expectedCount,
        bool bonusEligible
    ) private pure returns (uint256) {
        uint256 weight = _pow3(burnIndex);
        uint256 total = _sumPow3(expectedCount);
        uint256 base = (rewardPoolLocal * ETH_PERK_TOTAL_BPS * weight) /
            (total * 10_000);
        if (!bonusEligible) return base;
        return (base * ETH_PERK_BONUS_BPS) / 10_000;
    }

    function _burniePerkPayout(
        uint256 burniePool,
        uint256 burnIndex,
        uint256 expectedCount
    ) private pure returns (uint256) {
        uint256 weight = _pow3(burnIndex);
        uint256 total = _sumPow3(expectedCount);
        return (burniePool * BURNIE_PERK_TOTAL_BPS * weight) / (total * 10_000);
    }

    function _dgnrsPerkPayout(
        uint256 dgnrsPool,
        uint256 burnIndex,
        uint256 expectedCount
    ) private pure returns (uint256) {
        uint256 weight = _pow3(burnIndex);
        uint256 total = _sumPow3(expectedCount);
        return (dgnrsPool * DGNRS_PERK_TOTAL_BPS * weight) / (total * 10_000);
    }

    function _pow3(uint256 x) private pure returns (uint256) {
        return x * x * x;
    }

    function _sumPow3(uint256 n) private pure returns (uint256) {
        uint256 n1 = n + 1;
        uint256 sum = (n * n1) / 2;
        return sum * sum;
    }

    function _creditEthPerk(
        address beneficiary,
        uint256 weiAmount,
        uint256 entropy
    ) private {
        if (weiAmount == 0) return;

        if (autoRebuyEnabled[beneficiary]) {
            uint256 keepMultiple = autoRebuyKeepMultiple[beneficiary];
            uint256 reserved;
            uint256 rebuyAmount = weiAmount;
            if (keepMultiple != 0) {
                reserved = (weiAmount / keepMultiple) * keepMultiple;
                rebuyAmount = weiAmount - reserved;
            }

            uint24 targetLevel = (gameState == GAME_STATE_BURN) ? level + 1 : level;
            uint256 ticketPrice = _priceForLevel(targetLevel) / 4;
            if (ticketPrice == 0) ticketPrice = 0.00625 ether;

            uint256 baseTickets = rebuyAmount / ticketPrice;
            uint256 ethSpent = baseTickets * ticketPrice;
            uint256 dustRemainder = rebuyAmount - ethSpent;

            if (dustRemainder != 0) {
                uint256 rollSeed = _entropyStep(
                    entropy ^
                        uint256(uint160(beneficiary)) ^
                        rebuyAmount ^
                        ticketPrice
                );
                if ((rollSeed % ticketPrice) < dustRemainder) {
                    ++baseTickets;
                    ethSpent = rebuyAmount;
                    dustRemainder = 0;
                }
            }

            if (baseTickets == 0) {
                unchecked {
                    claimableWinnings[beneficiary] += weiAmount;
                }
                claimablePool += weiAmount;
                emit PlayerCredited(beneficiary, beneficiary, weiAmount);
                return;
            }

            uint256 bonusBps = afKingMode[beneficiary]
                ? AFKING_AUTO_REBUY_BONUS_BPS
                : AUTO_REBUY_BONUS_BPS;
            uint256 bonusTickets = (baseTickets * bonusBps) / 10_000;
            uint32 ticketCount = bonusTickets > type(uint32).max
                ? type(uint32).max
                : uint32(bonusTickets);

            nextPrizePool += ethSpent;
            _queueTickets(beneficiary, targetLevel, ticketCount);

            uint256 totalRemainder = reserved + dustRemainder;
            if (totalRemainder != 0) {
                unchecked {
                    claimableWinnings[beneficiary] += totalRemainder;
                    claimablePool += totalRemainder;
                }
            }

            emit AutoRebuyProcessed(
                beneficiary,
                targetLevel,
                ticketCount,
                ethSpent,
                totalRemainder
            );
            return;
        }

        unchecked {
            claimableWinnings[beneficiary] += weiAmount;
        }
        claimablePool += weiAmount;
        emit PlayerCredited(beneficiary, beneficiary, weiAmount);
    }

    function _traitWeight(uint32 rnd) private pure returns (uint8) {
        unchecked {
            uint32 scaled = uint32((uint64(rnd) * 75) >> 32);
            if (scaled < 10) return 0;
            if (scaled < 20) return 1;
            if (scaled < 30) return 2;
            if (scaled < 40) return 3;
            if (scaled < 49) return 4;
            if (scaled < 58) return 5;
            if (scaled < 67) return 6;
            return 7;
        }
    }

    function _deriveTrait(uint64 rnd) private pure returns (uint8) {
        uint8 category = _traitWeight(uint32(rnd));
        uint8 sub = _traitWeight(uint32(rnd >> 32));
        return (category << 3) | sub;
    }

    function _traitsForToken(
        uint256 tokenId
    ) private pure returns (uint32 packed) {
        uint256 rand = uint256(keccak256(abi.encodePacked(tokenId)));
        uint8 trait0 = _deriveTrait(uint64(rand));
        uint8 trait1 = _deriveTrait(uint64(rand >> 64)) | 64;
        uint8 trait2 = _deriveTrait(uint64(rand >> 128)) | 128;
        uint8 trait3 = _deriveTrait(uint64(rand >> 192)) | 192;
        packed =
            uint32(trait0) |
            (uint32(trait1) << 8) |
            (uint32(trait2) << 16) |
            (uint32(trait3) << 24);
    }

    function _consumeTrait(
        uint8 traitId,
        uint32 endLevel,
        bool checkExtermination
    ) private returns (bool reachedZero) {
        uint32 stored = traitRemaining[traitId];
        if (stored == 0) return false;

        unchecked {
            stored -= 1;
        }
        traitRemaining[traitId] = stored;
        if (!checkExtermination) return false;
        return stored == endLevel;
    }

    function _setExterminatorForLevel(uint24 lvl, address ex) private {
        if (lvl == 0) return;
        levelExterminators[lvl] = ex;
    }

    /// @dev Credit ETH winnings to a player's claimable balance.
    ///      Uses unchecked math as overflow is practically impossible.
    ///      Emits PlayerCredited for off-chain tracking.
    /// @param beneficiary Player to credit.
    /// @param weiAmount Amount in wei to add.
    /// @param entropy RNG seed for fractional ticket roll.
    function _addClaimableEth(
        address beneficiary,
        uint256 weiAmount,
        uint256 entropy
    ) private {
        claimablePool += weiAmount;
        if (autoRebuyEnabled[beneficiary]) {
            uint256 keepMultiple = autoRebuyKeepMultiple[beneficiary];
            uint256 reserved;
            uint256 rebuyAmount = weiAmount;
            if (keepMultiple != 0) {
                reserved = (weiAmount / keepMultiple) * keepMultiple;
                rebuyAmount = weiAmount - reserved;
            }

            uint24 targetLevel = (gameState == GAME_STATE_BURN)
                ? level + 1
                : level;
            uint256 ticketPrice = _priceForLevel(targetLevel) / 4;

            uint256 baseTickets = rebuyAmount / ticketPrice;
            uint256 ethSpent = baseTickets * ticketPrice;
            uint256 dustRemainder = rebuyAmount - ethSpent;

            // Roll fractional remainder into a chance for +1 base ticket.
            if (dustRemainder != 0) {
                uint256 rollSeed = _entropyStep(
                    entropy ^
                        uint256(uint160(beneficiary)) ^
                        rebuyAmount ^
                        ticketPrice
                );
                if ((rollSeed % ticketPrice) < dustRemainder) {
                    ++baseTickets;
                    ethSpent = rebuyAmount;
                    dustRemainder = 0;
                }
            }

            if (baseTickets == 0) {
                unchecked {
                    claimableWinnings[beneficiary] += weiAmount;
                }
                emit PlayerCredited(beneficiary, beneficiary, weiAmount);
                return;
            }

            uint256 bonusBps = afKingMode[beneficiary]
                ? AFKING_AUTO_REBUY_BONUS_BPS
                : AUTO_REBUY_BONUS_BPS;
            uint256 bonusTickets = (baseTickets * bonusBps) / 10000;
            uint32 ticketCount = bonusTickets > type(uint32).max
                ? type(uint32).max
                : uint32(bonusTickets);

            nextPrizePool += ethSpent;
            _queueTickets(beneficiary, targetLevel, ticketCount);

            uint256 totalRemainder = reserved + dustRemainder;
            if (totalRemainder != 0) {
                unchecked {
                    claimableWinnings[beneficiary] += totalRemainder;
                }
            }

            uint256 claimableInflow = weiAmount;
            if (claimableInflow > totalRemainder) {
                claimablePool -= (claimableInflow - totalRemainder);
            } else if (totalRemainder > claimableInflow) {
                claimablePool += (totalRemainder - claimableInflow);
            }

            emit AutoRebuyProcessed(
                beneficiary,
                targetLevel,
                ticketCount,
                ethSpent,
                totalRemainder
            );
            return;
        }

        unchecked {
            claimableWinnings[beneficiary] += weiAmount;
        }
        emit PlayerCredited(beneficiary, beneficiary, weiAmount);
    }

    /// @dev Award decimator lootbox rewards to a claimer.
    ///      Uses current level for ticket pricing (not old jackpot level).
    ///      Routes large amounts to deferred claim (gas safety).
    ///      Derives player-specific entropy from VRF randomness.
    /// @param winner Address to receive tickets.
    /// @param amount Lootbox portion of decimator claim.
    /// @param rngWord VRF random word from jackpot resolution.
    function _awardDecimatorLootbox(
        address winner,
        uint256 amount,
        uint256 rngWord
    ) private {
        if (winner == address(0) || amount == 0) return;
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            _queueWhalePassClaim(winner, amount, rngWord);
            return;
        }
        lootbox.resolveLootboxDirect(winner, amount, rngWord);
    }

    /// @dev Queue deferred whale pass claims for large lootbox amounts.
    ///      Calculates half-passes from ETH amount with RNG remainder roll.
    /// @param winner Address to receive whale pass claim.
    /// @param amount ETH amount to convert to half whale passes.
    /// @param entropy RNG word for remainder roll.
    function _queueWhalePassClaim(
        address winner,
        uint256 amount,
        uint256 entropy
    ) private {
        if (winner == address(0) || amount == 0) return;

        uint256 HALF_WHALE_PASS_PRICE = 1.75 ether /
            ContractAddresses.COST_DIVISOR;
        uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
        uint256 remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE);

        // Probabilistic roll for +1 half pass using RNG
        if (remainder > 0) {
            entropy = uint256(
                keccak256(abi.encodePacked(entropy, winner, amount))
            );
            uint256 chanceBps = (remainder * 10000) / HALF_WHALE_PASS_PRICE;
            uint256 roll = entropy % 10000;
            if (roll < chanceBps) {
                unchecked {
                    ++fullHalfPasses;
                }
            }
        }

        whalePassClaims[winner] += fullHalfPasses;
    }

    /// @dev Get price for a specific level (used for ticket calculations).
    ///      Matches the 100-level price cycle: x00=0.25, x01-x39=0.05, x40-x79=0.1, x80-x99=0.125
    /// @param targetLevel Level to query.
    /// @return Price in wei.
    function _priceForLevel(uint24 targetLevel) private pure returns (uint256) {
        // First 10 levels (0-9) start at lower price
        if (targetLevel < 10) return 0.025 ether;

        uint256 cycleOffset = targetLevel % 100;

        // Price changes at specific points in the 100-level cycle
        if (cycleOffset == 0) {
            return 0.25 ether; // Levels 100, 200, 300...
        } else if (cycleOffset >= 80) {
            return 0.125 ether; // Levels 80-99, 180-199...
        } else if (cycleOffset >= 40) {
            return 0.1 ether; // Levels 40-79, 140-179...
        } else {
            // Levels 10-39, 101-139... = 0.05 ether
            return 0.05 ether;
        }
    }

    /// @dev XOR-shift PRNG step for deterministic entropy derivation.
    function _entropyStep(uint256 state) private pure returns (uint256) {
        unchecked {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
        }
        return state;
    }
}
