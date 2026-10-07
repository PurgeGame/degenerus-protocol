// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {RECORD_KIND_BUY, RECORD_KIND_LUCKBOX} from "../interfaces/ICoinflip.sol";
import {
    IDegenerusGameBoonModule,
    IDegenerusGameLootboxModule,
    IDegenerusGameMintModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";

import {LiquidationQuote, ILiquidationDeity} from "../interfaces/ILiquidation.sol";

/**
 * @title DegenerusGameMintModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling purchases, payment routing and mint history.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 *
 * ## Functions
 *
 * - `_recordMintData`: Track per-player mint history and update Activity Score metrics
 *
 * ## Activity Score System
 *
 * Player engagement is tracked through multiple loyalty metrics:
 * - **Level Count**: Total levels minted (lifetime participation)
 * - **Level Streak**: Consecutive level purchases
 * - **Quest Streak**: Daily quest completion streak (tracked in DegenerusQuests)
 * - **Affiliate Points**: Referral program bonus points (tracked in DegenerusAffiliate)
 * - **Pass**: Active pass type (lazy = 10-lvl, whale = 100-lvl). Buying one also grants
 *   the buyer's one-time AFKing seat; awarded or conferred passes do not.
 *
 * ### Mint Data Bit Packing Layout (mintPacked_):
 *
 * ```
 * Bits 0-23:    lastLevel          - Last level with ETH mint
 * Bits 24-47:   levelCount         - Total levels minted (lifetime) [Activity Score]
 * Bits 48-71:   levelStreak        - Consecutive levels minted [Activity Score]
 * Bits 72-95:   lastMintDay        - Day index of last mint
 * Bits 96-119:  unitsLevel         - Level index for levelUnits tracking
 * Bits 120-143: frozenUntilLevel   - Whale pass: freeze stats until this level (0 = not frozen)
 * Bits 144-145: whalePassType      - Active pass type (0=none, 1=lazy/10-lvl, 3=whale/100-lvl) [Activity Score]
 * Bit  146:     seatClaimed        - AFKing seat mint latch
 * Bit  147:     smurfFlag          - Smurf account (set once by createSmurf)
 * Bits 148-171: mintStreakLast     - Last level credited for mint streak
 * Bit  172:     hasDeityPass       - Deity pass flag
 * Bits 173-196: affBonusLevel      - Cached affiliate bonus level
 * Bits 197-202: affBonusPoints     - Cached affiliate bonus points (0-50)
 * Bits 203-207: curseCount         - Cashout/smite curse counter (0-20)
 * Bits 208-223: levelUnits         - Units minted this level
 * Bits 224-255: walletId           - Permanent wallet ID (registration only)
 * ```
 *
 * Note: Quest Streak is tracked in DegenerusQuests.questPlayerState.
 * Affiliate Points are tracked in DegenerusAffiliate and cached in mintPacked_ bits 173-202 during that player's own mint (_recordMintData).
 *
 * Ticket materialization and its deterministic checkpoints live in DegenerusGameTicketModule.
 */
contract DegenerusGameMintModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------


    /// @dev LCG multiplier for trait generation.

    // -------------------------------------------------------------------------
    // Purchase / Lootbox Constants
    // -------------------------------------------------------------------------

    /// @dev Coin-presale-box minimum purchase amount (0.01 ETH). Checked on the
    ///      REQUESTED amount BEFORE the exactly-50-ETH clamp, so a sub-floor gap to
    ///      the 50-ETH cap can never lock the presale close.
    uint256 private constant PRESALE_BOX_MIN = 0.01 ether;
    /// @dev Absolute minimum ticket buy-in (ETH equivalent).
    uint256 private constant TICKET_MIN_BUYIN_WEI = 0.0025 ether;
    /// @dev Entry floor for the biggest-buy record, in whole tickets.
    uint256 private constant BIGGEST_BUY_MIN_TICKETS = 100;
    /// @dev Buys under 0.04 tickets (4 * QTY_SCALE = 400 units per ticket) are tested against the
    ///      routed level's snap exponent; larger buys skip that read. This is where the smallest
    ///      legal buys land — TICKET_MIN_BUYIN_WEI floors a buy at 5 units at the 0.24 ETH
    ///      milestone price and 13 at 0.08 ETH — so the cheap constant compare covers the dust
    ///      case and leaves the hot path paying nothing for a slot no purchase otherwise touches.
    uint256 private constant SNAP_CHECK_MAX_UNITS = 16;

    /// @dev Cap on the purchase cost basis the purchase-boost boon sizes its bonus tickets from.
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether;

    /// @dev Share of ticket purchases routed to future prize pool (10%).
    uint16 private constant PURCHASE_TO_FUTURE_BPS = 1000;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a purchase's box entry is appended, whether bought directly or
    ///         system-granted (`recordCoverBox`: pass purchases and the afking auto-buy).
    /// @param buyer The player whose entry this is.
    /// @param index The physical write buffer (0/1) the entry joined.
    /// @param position The entry's zero-based position in that buffer.
    /// @param amount The entry's ordinary box ETH.
    event LootBoxBuy(
        uint32 indexed buyer,
        uint48 indexed index,
        uint32 position,
        uint256 amount
    );
    /// @notice Emitted when a coin-presale box joins a purchase's entry.
    /// @param buyer The player who bought the box.
    /// @param index The physical write buffer (0/1) the entry joined.
    /// @param position The entry's zero-based position in that buffer (shared with the same
    ///        call's ordinary boxes).
    /// @param amount The applied box ETH (post-clamp).
    /// @param closing True iff this buy crossed the 50-ETH cap. It latches presaleOver, and
    ///        this box's own resolution pays the Pool.PresaleBox remainder to the buyer.
    event PresaleBoxBuy(
        uint32 indexed buyer,
        uint48 indexed index,
        uint32 position,
        uint256 amount,
        bool closing
    );

    /// @notice entryQuantityScaled in purchase units (4 * QTY_SCALE = 400 = one whole ticket);
    ///         weiIn = ETH-in for the manual-mint ticket leg (any funding source). The box leg
    ///         rides LootBoxBuy, so the two stay disjoint for off-chain ETH-in totals.
    event EntriesBought(uint32 indexed buyer, uint256 entryQuantityScaled, uint256 weiIn);


    // -------------------------------------------------------------------------
    // Mint Payment + Data Recording
    // -------------------------------------------------------------------------

    /// @notice Record a mint payment, funded by ETH, claimable winnings, and/or afking.
    /// @dev Direct internal call on the ETH-purchase path (this frame already runs in the
    ///      Game's storage context). `ethForLeg` is the exact fresh-ETH value the caller
    ///      allocates to this leg — every payment-mode check binds to it, never to the outer
    ///      purchase tx's msg.value (a combined purchase splits one msg.value across legs).
    ///      Payment modes:
    ///      - DirectEth: fresh ETH first (overage ignored); afking covers any shortfall; claimable skipped
    ///      - Claimable: deduct from claimableWinnings (ethForLeg must be 0)
    ///      - Combined: ETH first, then claimable for remainder
    ///      Afking covers any remaining shortfall on every mode.
    ///
    ///      SECURITY: Validates minimum payment amounts; overage is ignored for accounting.
    ///      Splits the prize contribution into its next/future shares and RETURNS them so the
    ///      caller can fold the ticket and lootbox legs into one prize-pool RMW.
    ///
    /// @param player The player address to record mint for.
    /// @param costWei Total cost in wei for this mint.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @param ethForLeg Fresh ETH allocated to this leg by the caller.
    /// @return nextShare Portion of this leg's contribution destined for the next prize pool.
    /// @return futureShare Portion destined for the future prize pool.
    /// @return claimableDraw Per-player claimable + afking drawn; caller subtracts it from claimablePool.
    /// @return claimableUsed Recycled winnings drawn, excluding afking principal.
    /// @custom:reverts E If payment validation fails or the funding tiers fall short.
    function _recordMintPayment(
        uint32 player,
        uint256 costWei,
        MintPaymentKind payKind,
        uint256 ethForLeg
    ) internal returns (uint256 nextShare, uint256 futureShare, uint256 claimableDraw, uint256 claimableUsed) {
        (claimableDraw, claimableUsed) = _processMintPayment(
            player,
            costWei,
            payKind,
            ethForLeg
        );
        // The funding waterfall covers exactly costWei or reverts, including when zero.
        futureShare = (costWei * PURCHASE_TO_FUTURE_BPS) / 10_000;
        nextShare = costWei - futureShare;
    }

    /// @dev Cover the full mint cost and return the amount drawn from player balances.
    ///      Handles three payment modes with strict validation:
    ///
    ///      DirectEth: fresh ETH first (overage ignored); afking covers any shortfall; claimable skipped
    ///      Claimable: ethForLeg must be 0, deduct from claimableWinnings
    ///      Combined: ETH first (any amount ≤ cost), then claimable for rest
    ///
    ///      SECURITY: Leaves 1 wei sentinel in claimable to prevent zeroing.
    ///      The per-player claimable/afking balances are debited here; the matching claimablePool
    ///      decrement is deferred to the caller (returned as claimableDraw) so a combined buy folds
    ///      both legs into one pool RMW.
    ///
    /// @param player Player whose claimable balance to check/deduct.
    /// @param amount Total cost in wei to cover.
    /// @param payKind Payment method enum.
    /// @param ethForLeg Fresh ETH allocated to this leg by the caller.
    /// @return claimableDraw Per-player claimable + afking drawn; caller subtracts it from claimablePool.
    /// @return claimableUsed Recycled winnings drawn, excluding afking principal.
    function _processMintPayment(
        uint32 player,
        uint256 amount,
        MintPaymentKind payKind,
        uint256 ethForLeg
    ) private returns (uint256 claimableDraw, uint256 claimableUsed) {
        uint256 ethUsed;
        if (payKind == MintPaymentKind.DirectEth) {
            // Direct ETH: fresh ETH first (overpay ignored), afking covers any shortfall;
            // claimable is skipped on this kind.
            ethUsed = ethForLeg < amount ? ethForLeg : amount;
        } else {
            if (payKind == MintPaymentKind.Claimable) {
                if (ethForLeg != 0) revert E();
            } else if (payKind == MintPaymentKind.Combined) {
                if (ethForLeg > amount) revert E();
                ethUsed = ethForLeg;
            } else {
                revert E();
            }
        }

        // Afking tier: the player's prepaid afking covers whatever fresh ETH + claimable did
        // not. afking is fresh-ETH-equivalent (own deposited principal), so it counts toward
        // the prize contribution. Reverts when the three tiers together fall short of the cost.
        claimableDraw = amount - ethUsed;
        if (claimableDraw == 0) return (0, 0);
        // No external calls occur between this snapshot and its write. Both payment
        // tiers and the event balance come from the same word, and callers receive the
        // exact recycled amount instead of re-reading the balance around this function.
        uint256 packed = balancesPacked[player];
        uint256 claimable = uint128(packed);
        if (payKind != MintPaymentKind.DirectEth && claimable > 1) {
            uint256 available = claimable - 1;
            claimableUsed = claimableDraw < available ? claimableDraw : available;
        }
        uint256 afkingUsed = claimableDraw - claimableUsed;
        if ((packed >> 128) < afkingUsed) revert Insolvent();
        balancesPacked[player] = packed - claimableUsed - (afkingUsed << 128);
        // The caller combines this draw with the box leg's claimablePool debit.

        if (claimableUsed != 0) {
            emit ClaimableSpent(
                player,
                claimableUsed,
                claimable - claimableUsed,
                payKind,
                amount
            );
        }
        if (afkingUsed != 0) {
            emit AfkingSpent(player, afkingUsed);
        }
    }

    /// @dev Past the purchase deadline, answer the liveness tail through the Game's own view
    ///      (this module runs in the Game's context, so `address(this)` is the Game). This module
    ///      sits at the EIP-170 ceiling; a self-staticcall paid only by purchases after the
    ///      deadline is cheaper in bytes than a copy of the tail. The Game re-evaluates the whole
    ///      predicate natively, so the answer is identical.
    function _pastDeadlineTriggered(uint24, uint24) internal view virtual override returns (bool) {
        return IDegenerusGame(address(this)).livenessTriggered();
    }

    // -------------------------------------------------------------------------
    // Purchases and Loot Boxes
    // -------------------------------------------------------------------------


    /// @notice Purchase tickets and loot boxes for a buyer.
    /// @dev Delegatecalled by DegenerusGame. Handles payment routing, affiliates, and queues.
    /// @param buyerId Recipient of the purchased items.
    /// @param entryQuantityScaled Purchase units: 100 = one entry (a quarter ticket), 400 = one whole ticket.
    /// @param boxOrder Packed box order: [small:8][med:8][large:8][customCount:8][customSize:56 gwei].
    /// @param affiliateCode Referral code for affiliate attribution.
    /// @param payKind Payment kind selector (ETH/claimable/combined).
    function purchase(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable {
        _purchaseFor(
            _resolveAccountId(buyerId),
            entryQuantityScaled,
            boxOrder,
            affiliateCode,
            payKind
        );
    }

    /// @notice Explicit-ethValue ticket-buy entry: like `purchase`, but the fresh-ETH portion
    ///         is the `ethValue` parameter rather than `msg.value`. Callers: the facade's foil
    ///         purchase, which funds the ticket/lootbox leg with the fresh ETH it carved while
    ///         the buyer's msg.value is in flight (that msg.value is ignored here — only
    ///         ethValue is spent), and createSmurf's one ticket. payable so the carried
    ///         msg.value does not revert the delegatecall.
    /// @param payerId Ledger the claimable/AFKing legs debit (0 = the buyer's own).
    function purchaseWith(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue,
        uint32 payerId
    ) external payable {
        _purchaseForWith(
            buyerId,
            entryQuantityScaled,
            boxOrder,
            affiliateCode,
            payKind,
            ethValue,
            payerId
        );
    }

    /// @notice Create a smurf account owned by the caller, give it the caller's referrer and buy
    ///         it one whole ticket paid by the caller (body of Game.createSmurf).
    /// @dev The caller must have an ordinary wallet ID. Resolve its referral, allocate the
    ///      subaccount with only its owner ID and smurf flag, copy the referral, then buy its
    ///      ticket. Admission uses the ticket quote. Payment uses the owner's fresh ETH,
    ///      claimable and AFKing balances according to payKind; overpay credits the owner.
    ///      Ticket history and quest progress belong to the new account.
    /// @param affiliateCode Referral code applied to the owner if its referral is unset.
    /// @param payKind How the owner funds the ticket.
    /// @return smurfId The new account's wallet ID.
    function createSmurf(bytes32 affiliateCode, MintPaymentKind payKind)
        external
        payable
        returns (uint32 smurfId)
    {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint32 ownerId = _requireWalletId(msg.sender);
        affiliate.payAffiliate(0, affiliateCode, ownerId, level + 1, true, 0);
        uint256 ticketCost = PriceLookupLib.priceForLevel(_activeTicketLevel());

        uint256 position = wallets.length;
        if (position > PAID_ADMISSION_WALLETS && ticketCost < PAID_ADMISSION_MIN_SPEND) revert E();
        if (position > type(uint32).max) revert E();
        smurfId = uint32(position);
        wallets.push(uint256(ownerId) << 160);
        mintPacked_[smurfId] = uint256(1) << BitPackingLib.SMURF_FLAG_SHIFT;
        emit SmurfCreated(ownerId, smurfId);

        affiliate.copyReferral(ownerId, smurfId);

        uint256 fresh = payKind == MintPaymentKind.Claimable
            ? 0
            : (msg.value < ticketCost ? msg.value : ticketCost);
        if (msg.value > fresh) _creditAfkingValue(ownerId, msg.value - fresh);
        // Nested delegatecall into this module's own explicit-value entry (the Game's storage
        // context): one shared copy of the purchase body serves this rare path.
        (bool ok, bytes memory data) = ContractAddresses.GAME_MINT_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameMintModule.purchaseWith.selector,
                smurfId, 4 * QTY_SCALE, 0, bytes32(0), payKind, fresh, ownerId
            )
        );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Redeem FLIP for current-jackpot tickets — allowed only inside the jackpot window.
    /// @dev Reverts unless the FLIP purchase window is open. The window latches open on the first
    ///      redeem that lands with the prize target met and no RNG in flight, stays open through the
    ///      jackpot days (later daily locks do not close it), and is cleared by the advance at the
    ///      final jackpot day's RNG request. While closed, FLIP ticket purchases revert so bonus
    ///      tickets and prize ETH accrue to real-ETH buyers.
    ///      Raw msg.data target of Game.redeemFlip: resolves the account here.
    /// @param id Account receiving the purchased tickets (0 = caller; account rule); the FLIP
    ///        burns from its payee.
    /// @param entryQuantityScaled Purchase units: 100 = one entry (a quarter ticket), 400 = one whole ticket.
    function redeemFlip(
        uint32 id,
        uint256 entryQuantityScaled
    ) external {
        uint32 buyerId = _resolveAccountId(id);
        _redeemFlipFor(buyerId, entryQuantityScaled);
    }

    function _redeemFlipFor(
        uint32 buyerId,
        uint256 entryQuantityScaled
    ) private {
        if (_livenessTriggered()) revert E();

        if (entryQuantityScaled != 0) {
            // FLIP purchase window: opens the first time a redeem lands once the prize target is met
            // in the purchase phase with no RNG in flight, latching a single warm slot-0 bit. It stays
            // open through the jackpot days and is cleared in the advance at the final jackpot day's RNG
            // request — the boundary where new tickets route to the next level (rngLockedFlag stays set
            // from that request until _unlockRng, so it can never flip back on during the wind-down).
            // While it is closed (an open/stalled purchase phase) FLIP purchases revert, so bonus
            // tickets and prize ETH accrue to real-ETH buyers. The target-met condition holds for the
            // whole of lastPurchaseDay, so even a one-day purchase phase still offers that day as a
            // redemption window.
            if (!_ticketRedemptionOpen()) {
                if (
                    rngLockedFlag ||
                    _getNextPrizePool() <= _prizePoolTarget(level + 1)
                ) revert E();
                _setTicketRedemptionOpen(true);
            }

            buyerId = _registerCallerAccount(buyerId, (PriceLookupLib.priceForLevel(_activeTicketLevel()) * entryQuantityScaled) / (4 * QTY_SCALE));
            uint24 cachedLevel = level;
            (
                ,
                uint32 adjustedQty32,
                uint24 targetLevel,
                uint32 flipMintUnits,
                ,
                ,
                ,
                ,
                ,
            ) = _callTicketPurchase(
                    buyerId,
                    0,
                    entryQuantityScaled,
                    MintPaymentKind.DirectEth,
                    0,
                    jackpotPhaseFlag
                );

            // The buyer registered when the FLIP leg priced the purchase.


            // MINT_FLIP quest leg only (no ETH spend, no lootbox): skips activity
            // score, affiliate, and non-mint quests. The returned reward is a FLIP
            // flip stake, awarded via creditFlip — the full coin cost was already
            // burned inside _callTicketPurchase.
            {
                uint256 nextLevelPrice = PriceLookupLib.priceForLevel(
                    cachedLevel + 1
                );
                (uint256 questReward, , , bool questCompleted, ) = quests
                    .handlePurchase(
                        buyerId,
                        0,
                        flipMintUnits,
                        0,
                        nextLevelPrice,
                        nextLevelPrice
                    );
                if (questCompleted && questReward != 0) {
                    coinflip.creditFlip(buyerId, questReward);
                }
            }

            // Queue tickets on the captured adjusted quantity.
            if (adjustedQty32 != 0) {
                _queuePurchaseEntries(buyerId, targetLevel, adjustedQty32);
            }
        }
    }

    function withdrawAfkingFunding(uint32 id, uint256 amount) external {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert AlreadySwept();
        if (amount == 0) return;
        uint32 wid = _resolveAccountId(id);
        address payee = wid == 0 ? msg.sender : _payee(_walletElement(wid));
        // One packed load: the guard reads the afking high half and the debit writes it back.
        uint256 packed = balancesPacked[wid];
        if (amount > (packed >> 128)) revert Insolvent();
        // Guard proved amount <= high half, so `amount << 128` subtracts only from the afking
        // half (no borrow into claimable) — byte-identical to _debitAfking's checked store.
        balancesPacked[wid] = packed - (amount << 128);
        claimablePool -= uint128(amount); // tandem release (checked math)
        emit AfkingWithdrew(wid, amount);
        // ETH first, stETH for any shortfall — the same backing claims draw on, so a game holding
        // most of its reserve as stETH can still pay a prepaid afking balance back.
        _payoutWithStethFallback(payee, amount);
    }

    event AccountLiquidated(uint32 indexed accountId, address indexed seller, uint32 indexed buyerId,
        uint256 price);
    event AcquiredAccountHarvested(uint32 indexed accountId, uint32 indexed buyerId, uint256 ethValue);
    event AfkingWithdrew(uint32 indexed player, uint256 amount);

    function previewLiquidateAccount(uint32 id) external view returns (LiquidationQuote memory q) {
        if (id == 0) id = _walletIdOf(msg.sender);
        _requireAllocated(id);
        q.accountId = id;
        (q.faceValue, q.quoteBudget, q.ticketValue, q.price) = _quoteLiquidation(id);
        if (q.price != 0) q.buyerId = _resolveLiquidationBuyer(q.price);
        q.nativeLiquidity = address(this).balance >= q.price;
        q.eligible = id > GNRUS_WALLET_ID && !_isAcquired(id)
            && !_liquidationDeity(_payee(_walletElement(id))) && !rngLockedFlag && !gameOver && !_livenessTriggered()
            && q.price != 0;
    }

    function _liquidationDeity(address seller) private view returns (bool) {
        return ILiquidationDeity(ContractAddresses.DEITY_PASS).balanceOf(seller) != 0;
    }

    /// @notice Sell one account and, for a main account, its entire family. Only the owner.
    function liquidateAccount(uint32 id, uint256 minEthOut) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (id == 0) id = _walletIdOf(msg.sender);
        _requireAllocated(id);
        uint256 element = _walletElement(id);
        address seller = _payee(element);
        if (seller != msg.sender) revert NotApproved();
        if (id <= GNRUS_WALLET_ID || _isAcquired(id) || _liquidationDeity(seller)) revert E();
        if (rngLockedFlag) revert RngLocked();
        if (gameOver || _livenessTriggered()) revert E();
        (, , , uint256 price) = _quoteLiquidation(id);
        if (price == 0 || price < minEthOut) revert E();
        uint32 buyer = _resolveLiquidationBuyer(price);
        if (buyer == 0) revert Insolvent();

        if (address(this).balance < price) revert Insolvent();
        dgnrs.burnForLiquidation(seller);
        if (uint32(element >> 160) == 0) walletIds[seller] &= uint64(type(uint32).max) << 32;
        // A nonzero seller key beside a buyer ID identifies an acquired root. Keep half passes.
        uint256 slot = _walletSlot(id);
        uint256 acquired = (element & (type(uint256).max << 192)) | (uint256(buyer) << 160) | uint160(seller);
        assembly ("memory-safe") { sstore(slot, acquired) }
        _debitLiquidationEth(buyer, price);
        claimablePool -= uint128(price);
        emit AccountLiquidated(id, seller, buyer, price);
        (bool paid, ) = seller.call{value: price}("");
        if (!paid) revert E();
    }

    /// @dev sDGNRS pays from claimable; Vault uses claimable then its own prepaid reserve.
    function _debitLiquidationEth(uint32 buyer, uint256 amount) private {
        uint256 available = _claimableOf(buyer);
        uint256 fromClaim = amount < available ? amount : available;
        if (buyer != VAULT_WALLET_ID) fromClaim = amount;
        _debitClaimableAndAfking(buyer, fromClaim, amount - fromClaim);
        if (fromClaim != 0) emit ClaimableSpent(buyer, fromClaim, available - fromClaim, MintPaymentKind.Internal, amount);
        if (amount > fromClaim) emit AfkingSpent(buyer, amount - fromClaim);
    }

    /// @notice Bounded, permissionless collection. Pays the recorded buyer and never the caller.
    function harvestAcquiredAccounts(uint32 buyer, uint32[] calldata ids) external returns (uint256 collected) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if ((buyer != VAULT_WALLET_ID && buyer != SDGNRS_WALLET_ID) || ids.length > 32) revert E();
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
        for (uint256 i; i < ids.length; ++i) {
            uint32 id = ids[i];
            _requireAllocated(id);
            if (_acquiredBuyer(id) != buyer) revert NotApproved();
            uint256 packed = balancesPacked[id];
            uint256 claimable = uint128(packed);
            uint256 amount = claimable > 1 ? claimable - 1 : 0;
            uint256 prepaid = packed >> 128;
            if (amount + prepaid == 0) continue;
            balancesPacked[id] = packed - amount - (prepaid << 128);
            collected += amount + prepaid;
            emit AcquiredAccountHarvested(id, buyer, amount + prepaid);
        }
        _creditClaimableLogged(buyer, collected);
        // Internal liability consolidation, so claimablePool does not change.
    }

    /// @dev Single-tx callers: the fresh-ETH portion is `msg.value`. Read here (a private fn)
    ///      so external non-payable callers (e.g. claimable-only paths) never reference msg.value.
    function _purchaseFor(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        ) = _purchaseCostInputs(entryQuantityScaled);
        // Single-tx path: cap fresh ETH at the mint cost and credit any overpay to the
        // payer's withdrawable afking, so excess never reverts or strands. The afking
        // ticket-buy path (purchaseWith) bypasses this, so it is unaffected.
        uint256 cost = ticketCost + _boxQuote(boxOrder);
        buyerId = _registerCallerAccount(buyerId, cost);
        uint256 fresh = payKind == MintPaymentKind.Claimable
            ? 0
            : (msg.value < cost ? msg.value : cost);
        if (msg.value > fresh) _creditAfkingValue(_requireWalletId(msg.sender), msg.value - fresh);
        uint256 boxWord = _purchaseForWithCached(
            buyerId,
            entryQuantityScaled,
            boxOrder,
            affiliateCode,
            payKind,
            fresh,
            cachedJpFlag,
            cachedLevel,
            priceWei,
            ticketCost,
            buyerId
        );
        // The ordinary leg's cost is the quote above: same input, same active level.
        if (boxWord != 0) _appendBoxOrder( boxWord, cost - ticketCost);
    }

    /// @dev Phase flag, level, whole-ticket price at the active purchase level, and the
    ///      ticket cost of `entryQuantityScaled` — read and computed once per purchase, then
    ///      threaded into _purchaseForWithCached so no caller recomputes them.
    function _purchaseCostInputs(uint256 entryQuantityScaled)
        private
        view
        returns (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        )
    {
        cachedJpFlag = jackpotPhaseFlag;
        cachedLevel = level;
        // Quote at the SAME level the queue delivers to (_activeTicketLevel), so the
        // final-jackpot-day reroute to level+1 cannot leave the charge / EntriesBought event /
        // affiliate / quest basis mispriced against the tickets actually queued.
        priceWei = PriceLookupLib.priceForLevel(_activeTicketLevel());
        ticketCost = (priceWei * entryQuantityScaled) / (4 * QTY_SCALE);
    }

    /// @dev `payerId` as in _purchaseForWithCached (0 = the buyer).
    function _purchaseForWith(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue,
        uint32 payerId
    ) private {
        (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        ) = _purchaseCostInputs(entryQuantityScaled);
        uint256 boxWord = _purchaseForWithCached(
            buyerId,
            entryQuantityScaled,
            boxOrder,
            affiliateCode,
            payKind,
            ethValue,
            cachedJpFlag,
            cachedLevel,
            priceWei,
            ticketCost,
            payerId
        );
        if (boxWord != 0) _appendBoxOrder( boxWord, _boxQuote(boxOrder));
    }

    // ---- Box-order legs ----
    // The boost consume, distress snapshot, bounty and EV draw are delegatecalled into the
    // Lootbox module, which owns the rest of the box logic. Each purchase builds one entry
    // word in flight and appends it once, after its last leg.

    /// @dev Price a purchase's ordinary leg at the active level, for the overpay cap and the
    ///      paid-admission spend. Validates the input exactly as `beginBoxOrder` will.
    function _boxQuote(uint256 boxOrder) private view returns (uint256 cost) {
        if (boxOrder != 0) (, cost) = _decodeBoxOrder(boxOrder, _activeTicketLevel());
    }

    /// @dev Append a purchase's completed entry and announce its ordinary leg.
    function _appendBoxOrder(uint256 word, uint256 ordinaryCost)
        private
        returns (uint48 index, uint32 position)
    {
        (index, position) = _appendBoxEntry(word, ordinaryCost);
        if (ordinaryCost != 0) emit LootBoxBuy(uint32(word), index, position, ordinaryCost);
    }

    /// @dev Delegatecall the Lootbox module in the Game's storage context, bubbling its revert
    ///      reason so an invalid order surfaces as itself.
    function _lootboxLeg(bytes memory payload) private returns (bytes memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(payload);
        if (!ok) _revertDelegate(data);
        return data;
    }

    /// @dev Core purchase body. `cachedJpFlag`/`cachedLevel`/`priceWei`/`ticketCost` are the
    ///      caller's same-frame _purchaseCostInputs snapshot (no external call sits between
    ///      that read and this frame, so the values cannot have changed). `payerId` is the
    ///      ledger the claimable/AFKing legs debit: the buyer's own (0 = the buyer), or a smurf's
    ///      owner on its creation ticket.
    function _purchaseForWithCached(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue,
        bool cachedJpFlag,
        uint24 cachedLevel,
        uint256 priceWei,
        uint256 ticketCost,
        uint32 payerId
    ) private returns (uint256 boxWord) {
        if (_livenessTriggered()) revert E();
        // Every caller registered the buyer before this frame; the mint word is warm.

        if (payerId == 0) payerId = buyerId;

        // Biggest-buy record, armed up front so any claim seeds the flip credit this
        // purchase already pays out below — the bounty rides the buy's own credit
        // instead of taking a second Coinflip write. The unit is whole tickets counted
        // RAW off the requested quantity (the pre-boost buy), so a boon boost cannot
        // carry a buy over the bar, and the floor is sound because the mark is only
        // ever written by a buy that cleared it. A revert anywhere below unwinds the
        // arm with the rest of the purchase, so a failed buy never arms. Every ticket
        // path through this body arms — manual buys and recycled purchases'
        // recycled ticket leg alike (a qualifying conversion is a real current-level
        // ticket mint and may hold the record). Coin-paid buys stay off the record
        // structurally: they route through FLIP redemption, never this body.
        uint256 lootboxFlipCredit;
        if (entryQuantityScaled >= BIGGEST_BUY_MIN_TICKETS * 4 * QTY_SCALE) {
            lootboxFlipCredit = coinflip.armRecord(
                RECORD_KIND_BUY,
                buyerId,
                entryQuantityScaled / (4 * QTY_SCALE)
            );
        }

        // --- Box-order leg (delegatecalled into the Lootbox module) ---
        // Builds this purchase's entry in flight before the payment split, which needs its
        // cost. The caller appends the finished word once; every effect here unwinds with the
        // rest of the purchase if anything below reverts.
        uint256 lootBoxAmount;
        uint256 lbShares; // (future << 128) | next
        if (boxOrder != 0) {
            uint256 lbCredit;
            (lootBoxAmount, lbShares, lbCredit, boxWord) = abi.decode(
                _lootboxLeg(
                    abi.encodeWithSelector(
                        IDegenerusGameLootboxModule.beginBoxOrder.selector,
                        buyerId,
                        boxOrder
                    )
                ),
                (uint256, uint256, uint256, uint256)
            );
            lootboxFlipCredit += lbCredit;
            // Box spend joins the minted-units tally (400 units = one ticket-price), combining
            // with the ticket leg so cumulative spend of either kind crosses the whole-ticket
            // participation floor (mint day / streak / quest gate). Mint-side, so it stays here.
            _recordLootboxUnits(buyerId, lootBoxAmount);
        }

        uint256 totalCost = ticketCost + lootBoxAmount;
        if (totalCost == 0) revert E();

        // Ticket-leg ETH-in (any funding source). The lootbox leg is carried by LootBoxBuy, so
        // the two events stay disjoint for off-chain ETH-in totals.
        if (ticketCost != 0) emit EntriesBought(buyerId, entryQuantityScaled, ticketCost);

        // ethValue is the per-slice fresh-ETH portion (== msg.value for single-tx callers; the
        // explicit afking ticket-buy slice routed through purchaseWith from the process STAGE).
        uint256 remainingEth = ethValue;
        uint256 lootboxFreshEth = 0;
        uint256 lootboxClaimableUsed = 0;
        // Lootbox-leg claimable + afking drawn here; folded with the ticket leg's draw into one
        // claimablePool decrement below.
        uint256 lootboxPoolDraw = 0;
        if (lootBoxAmount != 0) {
            // Lootbox payment uses msg.value first; afking covers any shortfall, and
            // claimable too unless the buyer insisted on DirectEth.
            if (remainingEth >= lootBoxAmount) {
                lootboxFreshEth = lootBoxAmount;
                unchecked {
                    remainingEth -= lootBoxAmount;
                }
            } else {
                lootboxFreshEth = remainingEth;
                uint256 shortfall = lootBoxAmount - remainingEth;
                remainingEth = 0;

                // Draw the shortfall from claimable (live balance == the entry snapshot
                // here; the mint leg has not run yet) then afking. afking is fresh-ETH-
                // equivalent for routing; claimable is recycled. DirectEth skips claimable.
                (uint256 cUsed, uint256 aUsed) = _settleShortfallNoPool(
                    payerId,
                    shortfall,
                    payKind != MintPaymentKind.DirectEth
                );
                lootboxFreshEth += aUsed;
                lootboxClaimableUsed = cUsed;
                lootboxPoolDraw = cUsed + aUsed;
            }
        }

        // --- Ticket purchase (returns quest units, defers x00 bonus + ticket queuing) ---
        uint32 flipMintUnits;
        uint32 adjustedQty;
        uint24 targetLevel;
        uint256 ticketFreshFlip;
        uint256 ticketRecycledFlip;
        // Prize-pool shares per leg (ticket here, lootbox below). Each leg keeps its own
        // next/future split; the two sums fold into a single _addPrizeContribution below.
        uint256 ticketNextShare;
        uint256 ticketFutureShare;
        // Ticket-leg claimable + afking drawn; folded with the lootbox draw into one pool RMW.
        uint256 ticketClaimableDraw;
        uint256 ticketClaimableUsed;
        if (ticketCost != 0) {
            // Accumulated, not assigned: lootboxFlipCredit may already carry the
            // biggest-buy record claim armed above.
            uint256 ticketBonusCredit;
            (
                ticketBonusCredit,
                adjustedQty,
                targetLevel,
                flipMintUnits,
                ticketFreshFlip,
                ticketRecycledFlip,
                ticketNextShare,
                ticketFutureShare,
                ticketClaimableDraw,
                ticketClaimableUsed
            ) = _callTicketPurchase(
                    buyerId,
                    payerId,
                    entryQuantityScaled,
                    payKind,
                    remainingEth,
                    cachedJpFlag
                );
            lootboxFlipCredit += ticketBonusCredit;
        }

        // --- One combined prize-pool RMW for both legs ---
        // Each leg's next/future split was computed above (ticket inside _callTicketPurchase,
        // lootbox in the block above); summing the post-split totals lands both in a single
        // packed write. This runs before the quest-handler / affiliate calls so no
        // observer ever sees a half-applied contribution, and prizePoolFrozen never flips
        // mid-purchase, so both legs route to the same accumulator.
        _addPrizeContribution(
            uint128(ticketNextShare + uint128(lbShares)),
            uint128(ticketFutureShare + (lbShares >> 128))
        );

        // --- One combined claimablePool decrement for both legs ---
        // Each leg already debited the buyer's per-player claimable/afking balance (the lootbox
        // shortfall settle above and _processMintPayment inside _callTicketPurchase); their pool
        // draws fold into a single decrement here, before the quest handler / affiliate calls. The
        // only external interactions in this deferral window are the boon-consume delegatecall
        // (reads no claimablePool, makes no reentrant call) and a read-only affiliate staticcall,
        // so no observer ever sees a half-applied pool, and the solvency identity holds at every
        // tx boundary.
        uint256 totalClaimableDraw = ticketClaimableDraw + lootboxPoolDraw;
        if (totalClaimableDraw != 0) {
            claimablePool -= uint128(totalClaimableDraw);
        }

        // --- Single quest handler call (post-action: handlers execute before score) ---
        // MINT_ETH quest progress is credited 1:1 in wei on the gross ETH-denominated
        // ticket + lootbox spend (totalCost), regardless of fresh-vs-recycled funding source.
        uint32 questStreak;
        bool questAfking;
        {
            (
                uint256 questReward,
                uint8 questType,
                uint32 streak,
                bool questCompleted,
                bool afking
            ) = quests.handlePurchase(
                    buyerId,
                    totalCost,
                    flipMintUnits,
                    lootBoxAmount,
                    priceWei,
                    // During the purchase phase the purchase level IS cachedLevel + 1,
                    // so priceWei already equals priceForLevel(cachedLevel + 1); only
                    // jackpot-phase buys need the lookup.
                    cachedJpFlag
                        ? PriceLookupLib.priceForLevel(cachedLevel + 1)
                        : priceWei
                );
            questStreak = streak;
            questAfking = afking;
            if (questCompleted) {
                lootboxFlipCredit += questReward;
                // Every purchase carries ETH spend (totalCost != 0 enforced at entry).
                if (questType == 1) {
                    _recordMintStreakForLevel(buyerId, _activeTicketLevel());
                }
            }
        }

        // --- Cure: any buy worth >= 1 ticket clears the cashout/smite curse, so the curing
        //     buy already scores un-penalized (cleared before the score read below). ---
        if (totalCost >= priceWei) {
            _clearCurse(buyerId);
        }

        // --- Compute score ONCE (post-action). Only the x00 century bonus and the lootbox
        //     EV/taper consume it, so a ticket-only non-x00 buy skips the score and its
        //     affiliate staticcall entirely. ---
        uint256 cachedScore;
        if (lootBoxAmount != 0 || targetLevel % 100 == 0) {
            // The quest handler already knows whether the buyer has an afking run.
            // Ordinary ticket buys need no score; non-afkers need no Sub lookup even
            // when buying boxes/century tickets. Lapsed runs retain the manual fallback.
            if (questAfking) {
                (bool afkLive, uint32 afkStreak) = _liveAfkingStreak(buyerId);
                if (afkLive) questStreak = afkStreak;
            }
            cachedScore = _playerActivityScore(buyerId, questStreak);
        }

        // --- x00 century bonus (uses cached post-action score) ---
        if (ticketCost != 0 && targetLevel % 100 == 0 && cachedScore != 0) {
            uint256 bonusQty = (uint256(adjustedQty) *
                ActivityCurveLib.centuryBps(cachedScore)) /
                ActivityCurveLib.CENTURY_MAX_BPS;
            if (bonusQty != 0) {
                // 20-ETH allowance in the bonus lane's scaled-entry units
                // (4 * QTY_SCALE units = 1 whole ticket = priceWei).
                uint256 maxBonus = (20 ether * 4 * QTY_SCALE) / priceWei;
                uint256 used = _centuryUsedFor(buyerId, targetLevel);
                uint256 remaining = maxBonus > used ? maxBonus - used : 0;
                if (bonusQty > remaining) bonusQty = remaining;
                if (bonusQty != 0) {
                    _setCenturyUsedFor(buyerId, targetLevel, used + bonusQty);
                    adjustedQty += uint32(bonusQty);
                }
            }
        }

        // --- Queue tickets ---
        if (adjustedQty != 0) {
            _queuePurchaseEntries(buyerId, targetLevel, adjustedQty);
        }

        // --- Box-order score and EV fraction (delegatecalled; needs the post-action score) ---
        if (lootBoxAmount != 0) {
            boxWord = abi.decode(
                _lootboxLeg(
                    abi.encodeWithSelector(
                        IDegenerusGameLootboxModule.applyBoxOrderScore.selector,
                        boxWord,
                        cachedScore,
                        cachedLevel + 1,
                        lootBoxAmount
                    )
                ),
                (uint256)
            );
        }

        // Settle all affiliate legs (ticket + lootbox, fresh + recycled) in ONE call. The kickback
        // joins the buyer's flip credit; the rolled winner credit is returned and paired below.
        // Runs unconditionally — every purchase carries ETH spend (totalCost != 0 enforced at
        // entry); affiliate scores freeze at level + 1.
        uint32 affWinnerId;
        uint256 affWinnerCredit;
        {
            uint256 lbFreshFlip = lootboxFreshEth != 0
                ? _ethToFlipValue(lootboxFreshEth, priceWei)
                : 0;
            uint256 lbRecycledFlip = lootboxClaimableUsed != 0
                ? _ethToFlipValue(lootboxClaimableUsed, priceWei)
                : 0;
            uint256 affKickback;
            (affWinnerId, affWinnerCredit, affKickback) = affiliate.payAffiliateCombined(
                affiliateCode,
                buyerId,
                cachedLevel + 1,
                ticketFreshFlip,
                ticketRecycledFlip,
                lbFreshFlip,
                lbRecycledFlip,
                uint16(cachedScore)
            );
            lootboxFlipCredit += affKickback;
        }

        // Coin-presale-box credit accrual: while the box presale is open, every ETH
        // ticket + lootbox spend (fresh + recycled) earns 25% spendable box credit.
        // Covers the afking ticket buy, which routes through this path.
        if (!presaleOver) {
            presaleBoxCredit[buyerId] += totalCost / 4;
        }

        // Recycle bonus: spending at least 3 whole tickets' worth of claimable
        // winnings (priceWei is the per-whole-ticket cost) earns 10% of the
        // recycled value back as FLIP flip credit, regardless of any remaining
        // claimable balance. Sum the exact tier debits returned by the payment legs;
        // DirectEth contributes zero and afking principal never earns a recycle bonus.
        uint256 totalClaimableUsed = ticketClaimableUsed + lootboxClaimableUsed;
        if (totalClaimableUsed >= priceWei * 3) {
            lootboxFlipCredit +=
                (totalClaimableUsed * PRICE_COIN_UNIT) /
                (priceWei * 10);
        }

        // One Coinflip write for the buyer credit + the rolled affiliate winner. winner != buyer
        // (winner == sender credits nothing), so no slot collision; the pair call skips zero legs.
        if (lootboxFlipCredit != 0 || affWinnerCredit != 0) {
            coinflip.creditFlipPair(
                buyerId,
                lootboxFlipCredit,
                affWinnerId,
                affWinnerCredit
            );
        }
    }

    /// @notice Buy a credit-gated coin-presale box (standalone), funded by msg.value
    ///         plus an optional claimable shortfall.
    /// @dev The box queues at the current lootbox RNG index and resolves off the
    ///      committed word later (RNG-freeze discipline). Reverts once presaleOver.
    /// @param id Account receiving the box (0 = caller; account rule). Raw msg.data target of
    ///        Game.buyPresaleBox.
    /// @param boxAmount Requested box ETH (>= PRESALE_BOX_MIN, checked pre-clamp).
    function buyPresaleBox(uint32 id, uint256 boxAmount) external payable {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value against empty local state.
        if (address(this) != ContractAddresses.GAME) revert E();
        uint32 buyerId = _resolveAccountId(id);
        buyerId = _registerCallerAccount(buyerId, boxAmount);
        _buyPresaleBoxFor(buyerId, boxAmount, msg.value, 0, 0);
    }

    /// @notice Buy tickets/lootbox (earning 25% presale-box credit) AND a presale box
    ///         in one call, sharing one queue entry. The mint leg takes fresh ETH up to its
    ///         own cost (none for Claimable payKind); the rest of msg.value funds the box,
    ///         with any shortfall drawn from the buyer's claimable, then afking balance. The
    ///         box is gated by the just-earned + banked presale-box credit.
    /// @param id Account receiving both legs (0 = caller; account rule). Raw msg.data target of
    ///        Game.buyLootboxAndPresaleBox.
    /// @param entryQuantityScaled Tickets to buy (0 to skip).
    /// @param boxOrder Packed box order (0 to skip): [small:8][med:8][large:8][customCount:8][customSize:56 gwei].
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (>= PRESALE_BOX_MIN; leftover msg.value
    ///        first, then the buyer's claimable/afking).
    function buyLootboxAndPresaleBox(
        uint32 id,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 boxAmount
    ) external payable {
        uint32 buyerId = _resolveAccountId(id);
        // Split msg.value across both legs so the box accepts the same funding mix as
        // every other purchase. The mint leg takes fresh ETH up to its own cost — capped
        // so the Combined/DirectEth payment guards never revert on or strand overpay;
        // the remainder funds the box as fresh ETH, with claimable/afking covering any
        // box shortfall. Claimable payKind sends no fresh ETH to the mint leg, leaving
        // all of msg.value for the box.
        (
            bool cachedJpFlag,
            uint24 cachedLevel,
            uint256 priceWei,
            uint256 ticketCost
        ) = _purchaseCostInputs(entryQuantityScaled);
        uint256 mintCost = ticketCost + _boxQuote(boxOrder);
        buyerId = _registerCallerAccount(buyerId, mintCost + boxAmount);
        uint256 mintFresh = payKind == MintPaymentKind.Claimable
            ? 0
            : (msg.value < mintCost ? msg.value : mintCost);
        // Mint leg first: accrues the 25% presale-box credit that gates the box below.
        uint256 boxWord = _purchaseForWithCached(
            buyerId,
            entryQuantityScaled,
            boxOrder,
            affiliateCode,
            payKind,
            mintFresh,
            cachedJpFlag,
            cachedLevel,
            priceWei,
            ticketCost,
            buyerId
        );
        // Both box legs share this call's one entry; the presale leg appends it.
        _buyPresaleBoxFor(buyerId, boxAmount, msg.value - mintFresh, boxWord, mintCost - ticketCost);
    }

    /// @dev Core credit-gated presale-box buy: clamp-to-50 close, 1:1 credit consume,
    ///      msg.value + claimable-shortfall payment, 80/20 ETH routing via
    ///      _creditBoxProceeds, then the presale fields join the purchase's entry and the
    ///      entry is appended. Independent presale purchases are independent entries.
    /// @param buyerId Player receiving the box.
    /// @param buyerId The buyer's wallet ID.
    /// @param boxAmount Requested box ETH (the MIN floor + no-overpay checks key on this).
    /// @param valueForBox The fresh-ETH (msg.value) portion available to fund the box.
    /// @param word The same call's ordinary entry, or zero for a presale-only entry.
    /// @param ordinaryCost The ordinary leg's box ETH (its RNG-pending ETH), or zero.
    function _buyPresaleBoxFor(
        uint32 buyerId,
        uint256 boxAmount,
        uint256 valueForBox,
        uint256 word,
        uint256 ordinaryCost
    ) private {
        if (presaleOver) revert E();
        if (_livenessTriggered()) revert E();
        // MIN floor on the REQUESTED amount, BEFORE the exactly-50 clamp, so a
        // sub-floor gap to the 50-ETH cap can never lock the close.
        if (boxAmount < PRESALE_BOX_MIN) revert E();
        // Overpay vs the requested amount is credited to the payer's afking, not reverted.
        if (valueForBox > boxAmount) {
            _creditAfkingValue(_requireWalletId(msg.sender), valueForBox - boxAmount);
            valueForBox = boxAmount;
        }

        uint256 sold = presaleBoxEthSold;
        uint256 remaining = PRESALE_BOX_ETH_CAP - sold; // sold <= cap by construction
        if (remaining == 0) revert E(); // sold out

        // Clamp the crossing box to land cumulative box-ETH at exactly 50.
        uint256 applied = boxAmount > remaining ? remaining : boxAmount;
        bool closing = applied == remaining;

        // Credit gate: consume spendable presale-box credit 1:1 (no clamp-to-credit;
        // an over-credit request reverts — the caller sizes the box to their credit).
        if (applied > presaleBoxCredit[buyerId]) revert E();
        unchecked {
            presaleBoxCredit[buyerId] -= applied;
        }

        // Payment: msg.value first (capped at the applied amount; clamp excess -> afking),
        // claimable shortfall for the rest (STRICT 1-wei sentinel preserved).
        uint256 freshUsed = valueForBox > applied ? applied : valueForBox;
        uint256 refund = valueForBox - freshUsed;
        uint256 shortfall = applied - freshUsed;
        _settleShortfall(buyerId, shortfall, true);

        // 80/20 routing: claimablePool += applied; VAULT 80% + SDGNRS 20% claimable.
        // The claimable-funded portion (shortfall) nets pool delta 0 (debited above,
        // re-credited here); the fresh-ETH portion bumps the pool by that ETH.
        _creditBoxProceeds(applied);

        // The DGNRS tier freezes off the purchase's starting position (sold), so a box crossing
        // a tier boundary keeps its starting tier. The closing purchase is the last presale box
        // ever appended; its own resolution pays the Pool.PresaleBox remainder.
        (uint48 index, uint32 position) = _appendBoxOrder(
            word | buyerId | (applied << LB_PRESALE_SHIFT) | (_presaleTier(sold) << LB_TIER_SHIFT)
                | (closing ? LB_CLOSING : 0),
            ordinaryCost
        );

        presaleBoxEthSold = uint96(sold + applied);
        // Latch the terminal in the crossing buy (stops further credit accrual and box buys).
        if (closing) presaleOver = true;

        emit PresaleBoxBuy(buyerId, index, position, applied, closing);

        // Fresh ETH the clamp-to-50 left unused is credited to the payer's afking, not
        // sent back via a value call (no reentrancy surface, consistent with overpay).
        if (refund != 0) _creditAfkingValue(_requireWalletId(msg.sender), refund);
    }

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data. A failure with no data (out of gas)
    ///      re-raises as EmptyRevert, the marker the game-over drain treats as a starved call.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Execute ticket purchase: payment, boost, affiliate routing, quest unit accumulation.
    ///      x00 century bonus and ticket queuing are handled by _purchaseFor after score computation.
    ///      `payerId` is the ledger an ETH leg's claimable/AFKing draw debits; zero selects the
    ///      FLIP leg (burned from the buyer's payee), which has no ledger payer.
    /// @return bonusCredit Bulk/recycle bonus flip credit (affiliate kickback is added by the caller)
    /// @return adjustedQty32 Adjusted ticket quantity (with boost, without x00 bonus)
    /// @return targetLevel The level tickets are queued to
    /// @return flipMintUnits FLIP-paid mint quest units
    /// @return ticketFreshFlip Ticket fresh-rate FLIP basis for the caller's combined affiliate call
    /// @return ticketRecycledFlip Ticket recycled-rate FLIP basis for the caller's combined affiliate call
    function _callTicketPurchase(
        uint32 buyerId,
        uint32 payerId,
        uint256 quantity,
        MintPaymentKind payKind,
        uint256 value,
        bool cachedJpFlag
    )
        private
        returns (
            uint256 bonusCredit,
            uint32 adjustedQty32,
            uint24 targetLevel,
            uint32 flipMintUnits,
            uint256 ticketFreshFlip,
            uint256 ticketRecycledFlip,
            uint256 ticketNextShare,
            uint256 ticketFutureShare,
            uint256 ticketClaimableDraw,
            uint256 ticketClaimableUsed
        )
    {
        if (quantity == 0) revert E();
        // Liveness is gated by both callers (_purchaseForWithCached / _redeemFlipFor)
        // before any state is touched, so it is not re-evaluated here.
        // Only the day before a standard phase's final draw earns the affiliate bonus.
        bool affiliateBonusDay = cachedJpFlag && (jackpotFlags & JACKPOT_TURBO) == 0
            && jackpotCounter >= JACKPOT_DAYS - 1;
        // Single source of truth shared with the purchase quote (so charge == award) and the
        // foil delivery. Routes to level+1 on the final jackpot day's RNG request to prevent
        // tickets stranded in a level whose draws have ended (_endPhase breaks before _unlockRng).
        targetLevel = _activeTicketLevel();
        uint256 priceWei = PriceLookupLib.priceForLevel(targetLevel);
        uint256 costWei = (priceWei * quantity) / (4 * QTY_SCALE);
        if (costWei < TICKET_MIN_BUYIN_WEI) revert E();
        // A dust ticket leg that cannot survive the routed level's snap divide fails closed instead
        // of charging full price for zero entries. The drain divides the accumulated
        // (player, level) balance by 2^s ONCE, so a buy under 2^s scaled units truncates to nothing
        // on its own and the remainder roll cannot recover it (rem == 0 always loses). The exponent
        // comes from targetLevel — the level these entries queue at — so it is the one the drain
        // applies. Gated on SNAP_CHECK_MAX_UNITS so only a dust-sized buy pays for the exponent
        // read: a buy at or above it still truncates once s exceeds 4, which is left uncovered
        // rather than charging every purchase for a slot it does not otherwise touch.
        if (
            quantity < SNAP_CHECK_MAX_UNITS &&
            quantity >> _snapShiftFor(targetLevel) == 0
        ) revert E();

        uint256 adjustedQuantity = quantity;
        bool payInCoin = payerId == 0;
        if (!payInCoin) {
            // Nested delegatecall straight into the boon module (this frame already
            // runs in the Game's storage context), skipping the external self-call
            // round trip through the Game dispatcher.
            (bool boostOk, bytes memory boostData) = ContractAddresses
                .GAME_BOON_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameBoonModule.consumePurchaseBoost.selector,
                        buyerId
                    )
                );
            if (!boostOk) _revertDelegate(boostData);
            uint16 boostBps = abi.decode(boostData, (uint16));
            if (boostBps != 0) {
                uint256 cappedValue = costWei > LOOTBOX_BOOST_MAX_VALUE
                    ? LOOTBOX_BOOST_MAX_VALUE
                    : costWei;
                uint256 cappedQty = priceWei == 0
                    ? 0
                    : ((cappedValue * 4 * QTY_SCALE) / priceWei);
                adjustedQuantity += (cappedQty * boostBps) / 10_000;
            }
        }
        adjustedQty32 = uint32(adjustedQuantity);

        if (payInCoin) {
            // The FLIP leg is a paying entry: register the buyer at its ETH-equivalent price
            // before anything else in this purchase loads the buyer's mint word.
            buyerId = _registerCallerAccount(buyerId, costWei);
            // Token debits round up: a fractional ticket price must not undercharge. The FLIP
            // burns from the account's payee (the owner for a smurf).
            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4) + QTY_SCALE - 1) /
                QTY_SCALE;
            _coinReceive(_payee(_walletElement(buyerId)), coinCost);

            // MINT_FLIP quest units (the reward is credited by the caller).
            uint32 questQty = uint32(quantity / (4 * QTY_SCALE));
            if (questQty != 0) {
                flipMintUnits += questQty;
            }
        } else {
            uint32 mintUnits = adjustedQty32;

            // Direct internal payment processing — `value` is the exact ETH this leg carries. The
            // prize-pool shares are returned, not written, so the caller folds the ticket and
            // lootbox legs into one pool RMW.
            (
                ticketNextShare,
                ticketFutureShare,
                ticketClaimableDraw,
                ticketClaimableUsed
            ) = _recordMintPayment(payerId, costWei, payKind, value);
            // Mint-data recording runs after payment, before quest eligibility is checked.
            _recordMintData(buyerId, targetLevel, mintUnits);

            // Fresh ETH for the affiliate split = ticket cost minus the recycled claimable
            // portion the payment just drew; the afking-drawn portion counts as fresh (own
            // principal -> fresh-rate affiliate, including the lootbox activity score). Pay-kind
            // validation already ran inside the payment processing.
            uint256 freshEth = costWei - ticketClaimableUsed;

            // Day before final jackpot draw (not turbo): +100 FLIP per ticket for affiliates
            // Basis inflated by 7/5 (lvl 0-3, 25% rate) or 3/2 (lvl 4+, 20% rate) to yield +100 after scaling
            uint256 freshFlip = freshEth != 0
                ? _ethToFlipValue(freshEth, priceWei)
                : 0;
            if (freshFlip != 0 && affiliateBonusDay) {
                freshFlip = targetLevel <= 3 ? (freshFlip * 7) / 5 : (freshFlip * 3) / 2;
            }

            // Affiliate is settled ONCE for the whole buy by the caller (payAffiliateCombined),
            // which needs this leg's fresh + recycled FLIP components. Fresh = the fresh-rate
            // basis (afking-drawn principal counts as fresh, already folded into freshFlip);
            // recycled = the claimable portion (costWei - freshEth) at the recycled rate. The
            // per-payKind split collapses to (freshFlip, recycledEth): DirectEth has no recycled
            // (recycledEth == 0); Combined/Claimable carry the claimable draw.
            uint256 recycledEth = costWei - freshEth;
            ticketFreshFlip = freshFlip;
            ticketRecycledFlip = recycledEth != 0
                ? _ethToFlipValue(recycledEth, priceWei)
                : 0;

            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) /
                QTY_SCALE;
            bonusCredit = coinCost / 10;
            if (quantity >= 10 * 4 * QTY_SCALE) {
                bonusCredit +=
                    (quantity * PRICE_COIN_UNIT) /
                    (80 * QTY_SCALE);
            }
        }
    }

    function _coinReceive(address payer, uint256 amount) private {
        coin.burnCoin(payer, amount);
    }

    /// @dev Convert ETH-denominated spend to FLIP base units at current ticket price.
    function _ethToFlipValue(
        uint256 amountWei,
        uint256 priceWei
    ) private pure returns (uint256) {
        if (amountWei == 0 || priceWei == 0) return 0;
        return (amountWei * PRICE_COIN_UNIT) / priceWei;
    }


}
