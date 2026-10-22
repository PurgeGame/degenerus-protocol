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

import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {RECORD_KIND_BUY} from "../interfaces/ICoinflip.sol";
import {IGameAfkingModule} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {DegenerusGameMintStreakUtils, IDegenerusVaultOwner} from "./DegenerusGameMintStreakUtils.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {GamePurchaseBoon} from "./GamePurchaseBoon.sol";
import {GamePurchaseBox} from "./GamePurchaseBox.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";

/// @notice Shared purchase, account funding and loan implementation in Game storage.
abstract contract GamePurchase is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils,
    GamePurchaseBoon,
    GamePurchaseBox
{
    /// @dev Same-frame price and phase snapshot shared by both purchase entry points.
    struct PurchaseQuote {
        bool cachedJpFlag;
        uint24 cachedLevel;
        uint256 priceWei;
        uint256 ticketCost;
    }

    /// @dev Funding totals retained through combined prize and affiliate settlement.
    struct TicketFunding {
        uint256 bonusCredit;
        uint256 ticketFreshFlip;
        uint256 ticketRecycledFlip;
        uint256 ticketNextShare;
        uint256 ticketFutureShare;
        uint256 ticketClaimableDraw;
        uint256 ticketClaimableUsed;
    }

    // -------------------------------------------------------------------------
    // Purchase / Lootbox Constants
    // -------------------------------------------------------------------------

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
    ///         system-granted (`recordCoverBox`: pass purchases).
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
    ///      SECURITY: Never draws the account's unbacked 1-wei claimable sentinel.
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

    // -------------------------------------------------------------------------
    // Purchases and Loot Boxes
    // -------------------------------------------------------------------------

    /// @notice Purchase tickets and loot boxes for a buyer.
    /// @dev Handles payment routing, affiliates, and queues.
    /// @param buyerId Recipient of the purchased items.
    /// @param entryQuantityScaled Purchase units: 100 = one entry (a quarter ticket), 400 = one whole ticket.
    /// @param boxOrder Packed box order: [quantity:7][kind:2][customUnits:21].
    /// @param affiliateCode Referral code for affiliate attribution.
    /// @param payKind Payment kind selector (ETH/claimable/combined).
    function _purchase(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) internal {
        _purchaseForAccount(
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
    ///         ethValue is spent), and createSmurf's one ticket.
    /// @param payerId Ledger the claimable/AFKing legs debit (0 = the buyer's own).
    function _purchaseWith(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue,
        uint32 payerId
    ) internal {
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

    /// @notice Create a smurf account owned and referred by the caller and buy
    ///         it one whole ticket paid by the caller (body of Game.createSmurf).
    /// @dev The caller must have an ordinary wallet ID. Resolve its referral, allocate the
    ///      subaccount with only its owner ID and smurf flag, refer it through the owner, then buy its
    ///      ticket. Admission uses the ticket quote. Payment uses the owner's fresh ETH,
    ///      claimable and AFKing balances according to payKind; overpay credits the owner.
    ///      Ticket history and quest progress belong to the new account.
    /// @param affiliateCode Referral code applied to the owner if its referral is unset.
    /// @param payKind How the owner funds the ticket.
    /// @return smurfId The new account's wallet ID.
    function _createSmurf(bytes32 affiliateCode, MintPaymentKind payKind)
        internal
        returns (uint32 smurfId)
    {
        uint32 ownerId = _requireWalletId(msg.sender);
        uint256 mintWord = _smurfMain(ownerId);
        // An open loan fixes the family its seizure walks.
        if (address(uint160(_walletElement(ownerId))) != msg.sender || uint96(_loans[ownerId]) != 0) revert E();
        uint256 score = _playerActivityScore(ownerId, _effectiveQuestStreak(ownerId));
        uint16 created = uint16(mintWord >> BitPackingLib.SMURF_COUNT_SHIFT);
        if (created == type(uint16).max || created >= uint256(uint16(mintWord >> BitPackingLib.SMURF_BASE_SHIFT)) + score / SMURF_SCORE_PER_CREATION) {
            revert SmurfCreationLimitReached();
        }
        // Reserve this ID's lifetime slot before stateful external calls; failures undo it.
        mintPacked_[ownerId] = BitPackingLib.setPacked(
            mintWord, BitPackingLib.SMURF_COUNT_SHIFT, BitPackingLib.MASK_16, uint256(created) + 1
        );
        affiliate.payAffiliate(0, affiliateCode, ownerId, level + 1, true, 0);
        uint256 ticketCost = PriceLookupLib.priceForLevel(_activeTicketLevel());

        uint256 position = wallets.length;
        if (position > PAID_ADMISSION_WALLETS && ticketCost < PAID_ADMISSION_MIN_SPEND) revert E();
        if (position > type(uint32).max) revert E();
        smurfId = uint32(position);
        wallets.push(uint256(ownerId) << 160);
        mintPacked_[smurfId] = uint256(1) << BitPackingLib.SMURF_FLAG_SHIFT;
        balancesPacked[smurfId] = 1; // the unbacked claimable sentinel, as _registerWallet seeds it
        // Append to the owner's smurf list at index `created` (its pre-increment count).
        _smurfWords[ownerId][created >> 3] |= uint256(smurfId) << ((created & 7) * 32);
        emit SmurfCreated(ownerId, smurfId);

        affiliate.referSmurf(ownerId, smurfId);

        uint256 fresh = payKind == MintPaymentKind.Claimable
            ? 0
            : (msg.value < ticketCost ? msg.value : ticketCost);
        if (msg.value > fresh) _creditAfkingValue(ownerId, msg.value - fresh);
        _purchaseWith(smurfId, 4 * QTY_SCALE, 0, bytes32(0), payKind, fresh, ownerId);
    }

    /// @dev Only an allocated ordinary main can create children or receive grants.
    ///      Acquired roots and smurfs have a nonzero parent and cannot qualify.
    function _smurfMain(uint32 id) private view returns (uint256 mintWord) {
        _requireAllocated(id);
        uint256 element = _walletElement(id);
        mintWord = mintPacked_[id];
        if (uint160(element) == 0 || uint32(element >> 160) != 0
            || (mintWord >> BitPackingLib.SMURF_FLAG_SHIFT) & 1 != 0) revert E();
    }

    /// @notice Permanently raise this main ID's base allowance; never resets its lifetime count.
    function _raiseSmurfBaseAllowance(uint32 mainId, uint16 newBase) internal {
        if (!IDegenerusVaultOwner(ContractAddresses.VAULT).isVaultOwner(msg.sender)) revert OnlyVault();
        uint256 mintWord = _smurfMain(mainId);
        uint16 previous = uint16(mintWord >> BitPackingLib.SMURF_BASE_SHIFT);
        if (newBase <= previous) revert InvalidSmurfBaseIncrease();
        mintPacked_[mainId] = BitPackingLib.setPacked(mintWord, BitPackingLib.SMURF_BASE_SHIFT, BitPackingLib.MASK_16, newBase);
        emit SmurfBaseAllowanceRaised(mainId, previous, newBase);
    }

    /// @notice Redeem FLIP for current-jackpot tickets — allowed only inside the jackpot window.
    /// @dev Reverts unless the FLIP purchase window is open. The window latches open on the first
    ///      redeem that lands with the prize target met and no RNG in flight, stays open through the
    ///      jackpot days (later daily locks do not close it), and is cleared by the advance at the
    ///      final jackpot day's RNG request. While closed, FLIP ticket purchases revert so bonus
    ///      tickets and prize ETH accrue to real-ETH buyers.
    /// @param id Account receiving the purchased tickets (0 = caller; account rule); the FLIP
    ///        burns from its payee.
    /// @param entryQuantityScaled Purchase units: 100 = one entry (a quarter ticket), 400 = one whole ticket.
    function _redeemFlip(
        uint32 id,
        uint256 entryQuantityScaled
    ) internal {
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
            TicketFunding memory ticket;
            (uint32 adjustedQty32, uint24 targetLevel) = _callTicketPurchase(
                    buyerId,
                    0,
                    entryQuantityScaled,
                    MintPaymentKind.DirectEth,
                    0,
                    jackpotPhaseFlag,
                    ticket
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
                        uint32(entryQuantityScaled / (4 * QTY_SCALE)),
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

    function _withdrawAfkingFunding(uint32 id, uint256 amount) internal {
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert AlreadySwept();
        if (amount == 0) return;
        (uint32 wid, address payee) = _resolveAccountPayee(id);
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

    event LoanTaken(uint32 indexed accountId, address indexed borrower, uint32 indexed lenderId,
        uint256 principal, uint24 dueLevel, uint256 ticketWei);
    event LoanRepaid(uint32 indexed accountId, address indexed payer, uint256 owed);
    event AfkingWithdrew(uint32 indexed player, uint256 amount);

    /// @notice Borrow against the account's far-future tickets (levels `dueLevel + 2` and up),
    ///         due when the game enters `dueLevel`. Only the owner. Unrepaid by then, the lender
    ///         takes the account as a sale does: a main with its family, burning the borrower
    ///         wallet's native sDGNRS. A game that ends first with VRF alive settles the loan the
    ///         same way before the ending's draw, repaying at the price `repay` would charge then.
    ///         A main with more than five smurfs cannot borrow; smurfs can. Pays ETH first and
    ///         stETH for any shortfall. More than 20 days into a level's purchase phase, half the
    ///         principal arrives as whole tickets at the live ticket level, priced and pooled like
    ///         a ticket buy. The principal is the quote capped at `amount`; `minEthOut` bounds the
    ///         ETH part.
    function _borrow(uint32 id, uint24 dueLevel, uint256 amount, uint256 minEthOut) internal {
        if (id == 0) id = _walletIdOf(msg.sender);
        _requireAllocated(id);
        uint256 element = _walletElement(id);
        address borrower = _payee(element);
        if (borrower != msg.sender) revert NotApproved();
        if (id <= GNRUS_WALLET_ID || _isAcquired(id) || uint96(_loans[id]) != 0) revert E();
        if (gameOver || _livenessTriggered()) revert E();
        uint256 family = 1;
        if (uint32(element >> 160) == 0) {
            family += uint16(mintPacked_[id] >> BitPackingLib.SMURF_COUNT_SHIFT);
            if (family > LOAN_MAX_SMURFS + 1) revert E();
        }
        uint24 lvl = level;
        if (dueLevel <= lvl || uint256(dueLevel) + 2 > uint256(_activeTicketLevel()) + LOAN_HORIZON_LEVELS) revert E();
        (, uint256 principal) = _quoteLoan(id, dueLevel);
        if (amount < principal) principal = amount;
        uint24 buyLevel = _activeTicketLevel();
        uint256 price = PriceLookupLib.priceForLevel(buyLevel);
        uint256 ticketWei = _loanTicketWei(principal, _simulatedDayIndex(), purchaseStartDay, price,
            jackpotPhaseFlag);
        if (principal < LOAN_MIN_PRINCIPAL || principal - ticketWei < minEthOut) revert E();
        uint32 lender = _resolveLender(principal);
        if (lender == 0) revert Insolvent();
        uint256 index = _loansDueCount[dueLevel]++;
        _setLoanDueAt(dueLevel, index, id);
        _loans[id] = principal | (uint256(lender) << LOAN_LENDER_SHIFT) | (uint256(lvl) << LOAN_START_SHIFT)
            | (uint256(dueLevel) << LOAN_DUE_SHIFT) | (index << LOAN_INDEX_SHIFT) | (family << LOAN_FAMILY_SHIFT);
        _debitLender(lender, principal);
        claimablePool -= uint128(principal);
        if (ticketWei != 0) {
            _queuePurchaseEntries(id, buyLevel, uint32(ticketWei / price * (4 * QTY_SCALE)));
            uint256 futureShare = (ticketWei * PURCHASE_TO_FUTURE_BPS) / 10_000;
            _addPrizeContribution(uint128(ticketWei - futureShare), uint128(futureShare));
        }
        emit LoanTaken(id, borrower, lender, principal, dueLevel, ticketWei);
        _payoutWithStethFallback(borrower, principal - ticketWei);
    }

    /// @notice Repay an open loan before the game enters its due level. Owed: principal plus 5%
    ///         of it per level used (at least one) plus 1% per unused level of the chosen term,
    ///         all to the lender. Only the owner. ETH first, the account's own claimable for any
    ///         shortfall; excess ETH goes to the account's AFKing balance.
    function _repay(uint32 id) internal {
        if (id == 0) id = _walletIdOf(msg.sender);
        uint256 loan = _loans[id];
        if (uint96(loan) == 0) revert E();
        if (_payee(_walletElement(id)) != msg.sender) revert NotApproved();
        uint24 due = uint24(loan >> LOAN_DUE_SHIFT);
        uint24 lvl = level;
        if (lvl >= due || gameOver) revert E();
        uint256 owed = _loanOwedAt(loan, lvl);
        uint256 fresh = msg.value < owed ? msg.value : owed;

        uint256 index = uint32(loan >> LOAN_INDEX_SHIFT);
        uint256 last = --_loansDueCount[due];
        if (index != last) {
            uint32 moved = _loanDueAt(due, last);
            _setLoanDueAt(due, index, moved);
            uint256 indexMask = uint256(type(uint32).max) << LOAN_INDEX_SHIFT;
            _loans[moved] = (_loans[moved] & ~indexMask) | (index << LOAN_INDEX_SHIFT);
        }
        _loans[id] = LOAN_RETAINED;

        // The claimable leg leaves the 1-wei sentinel, as every claimable draw does.
        if (owed > fresh && _claimableOf(id) <= owed - fresh) revert Insolvent();
        _debitClaimable(id, owed - fresh);
        claimablePool += uint128(fresh);
        _creditClaimableLogged(uint32(uint8(loan >> LOAN_LENDER_SHIFT)), owed);
        _creditAfkingValue(id, msg.value - fresh);
        emit LoanRepaid(id, msg.sender, owed);
    }

    /// @dev sDGNRS pays from claimable; Vault uses claimable above its sentinel, then its own
    ///      prepaid reserve.
    function _debitLender(uint32 buyer, uint256 amount) private {
        uint256 available = _claimableOf(buyer);
        uint256 usable = available > 1 ? available - 1 : 0;
        uint256 fromClaim = amount < usable ? amount : usable;
        if (buyer != VAULT_WALLET_ID) fromClaim = amount;
        _debitClaimableAndAfking(buyer, fromClaim, amount - fromClaim);
        if (fromClaim != 0) emit ClaimableSpent(buyer, fromClaim, available - fromClaim, MintPaymentKind.Internal, amount);
        if (amount > fromClaim) emit AfkingSpent(buyer, amount - fromClaim);
    }

    event AccountSwept(uint32 indexed accountId, uint32 indexed mainId, uint256 ethValue, uint256 flipAmount);

    /// @notice Repeatable collection of subaccount balances into their current main's reserves.
    /// @dev No recipient override or external ETH payout. A normal smurf keeps its live prepaid
    ///      funding; acquired accounts and ended-game smurfs also consolidate prepaid ETH.
    function _sweepAccounts(uint32[] calldata ids) internal returns (uint256 ethCollected, uint256 flipCollected) {
        if (ids.length > 32 || _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
        for (uint256 i; i < ids.length; ++i) {
            uint32 id = ids[i];
            _requireAllocated(id);
            uint256 element = _walletElement(id);
            if (uint32(element >> 160) == 0) revert E();
            uint32 mainId = _ownerWalletId(id);
            if (mainId != SDGNRS_WALLET_ID) {
                (, , bool authorized) = _account(id, msg.sender);
                if (!authorized) revert NotApproved();
            }
            bool acquired = _acquiredRoot(id, element) != 0;
            uint256 packed = balancesPacked[id];
            uint256 amount = uint128(packed);
            amount = amount > 1 ? amount - 1 : 0;
            uint256 prepaid = acquired || gameOver ? packed >> 128 : 0;
            if (amount + prepaid != 0) {
                balancesPacked[id] = packed - amount - (prepaid << 128);
                _creditClaimableLogged(mainId, amount + prepaid);
                // Preserve the source account's cashout rule when an ordinary owner extracts
                // its winnings. No ETH leaves the Game and claimablePool is unchanged.
                if (!acquired && amount != 0) {
                    (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
                        abi.encodeWithSelector(IGameAfkingModule.maybeCurse.selector, id)
                    );
                    if (!ok) _revertDelegate(data);
                }
            }
            uint256 flipAmount = coinflip.sweepAccountCoinflips(id);
            ethCollected += amount + prepaid;
            flipCollected += flipAmount;
            emit AccountSwept(id, mainId, amount + prepaid, flipAmount);
        }
    }

    /// @dev Single-tx callers: the fresh-ETH portion is `msg.value`. Read here (a private fn)
    ///      so external non-payable callers (e.g. claimable-only paths) never reference msg.value.
    function _purchaseForAccount(
        uint32 buyerId,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) private {
        PurchaseQuote memory quote = _purchaseCostInputs(entryQuantityScaled);
        // Single-tx path: cap fresh ETH at the mint cost and credit any overpay to the
        // payer's withdrawable afking, so excess never reverts or strands. The explicit-value
        // ticket-buy path (_purchaseWith) bypasses this, so it is unaffected.
        uint256 cost = quote.ticketCost + _boxQuote(boxOrder);
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
            quote,
            buyerId
        );
        // The ordinary leg's cost is the quote above: same input, same active level.
        if (boxWord != 0) _appendBoxOrder( boxWord, cost - quote.ticketCost);
    }

    /// @dev Phase flag, level, whole-ticket price at the active purchase level, and the
    ///      ticket cost of `entryQuantityScaled` — read and computed once per purchase, then
    ///      threaded into _purchaseForWithCached so no caller recomputes them.
    function _purchaseCostInputs(uint256 entryQuantityScaled)
        private
        view
        returns (PurchaseQuote memory quote)
    {
        quote.cachedJpFlag = jackpotPhaseFlag;
        quote.cachedLevel = level;
        // Quote at the SAME level the queue delivers to (_activeTicketLevel), so the
        // final-jackpot-day reroute to level+1 cannot leave the charge / EntriesBought event /
        // affiliate / quest basis mispriced against the tickets actually queued.
        quote.priceWei = PriceLookupLib.priceForLevel(_activeTicketLevel());
        quote.ticketCost = (quote.priceWei * entryQuantityScaled) / (4 * QTY_SCALE);
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
        PurchaseQuote memory quote = _purchaseCostInputs(entryQuantityScaled);
        uint256 boxWord = _purchaseForWithCached(
            buyerId,
            entryQuantityScaled,
            boxOrder,
            affiliateCode,
            payKind,
            ethValue,
            quote,
            payerId
        );
        if (boxWord != 0) _appendBoxOrder( boxWord, _boxQuote(boxOrder));
    }

    // ---- Box-order legs ----
    // Each purchase builds one entry word and appends it after its last leg.

    /// @dev Price a purchase's ordinary leg at the active level, for the overpay cap and the
    ///      paid-admission spend. Validates the input exactly as `_beginBoxOrder` will.
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

    /// @dev Core purchase body. `quote` is the caller's same-frame _purchaseCostInputs snapshot
    ///      (no external call sits between
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
        PurchaseQuote memory quote,
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

        // --- Box-order leg ---
        // Builds this purchase's entry in flight before the payment split, which needs its
        // cost. The caller appends the finished word once; every effect here unwinds with the
        // rest of the purchase if anything below reverts.
        uint256 lootBoxAmount;
        uint256 lbShares; // (future << 128) | next
        if (boxOrder != 0) {
            uint256 lbCredit;
            (lootBoxAmount, lbShares, lbCredit, boxWord) = _beginBoxOrder(buyerId, boxOrder);
            lootboxFlipCredit += lbCredit;
            // Box spend joins the minted-units tally (400 units = one ticket-price), combining
            // with the ticket leg so cumulative spend of either kind crosses the whole-ticket
            // participation floor (mint day / streak / quest gate).
            _recordLootboxUnits(buyerId, lootBoxAmount);
        }

        uint256 totalCost = quote.ticketCost + lootBoxAmount;
        if (totalCost == 0) revert E();

        // Ticket-leg ETH-in (any funding source). The lootbox leg is carried by LootBoxBuy, so
        // the two events stay disjoint for off-chain ETH-in totals.
        if (quote.ticketCost != 0) emit EntriesBought(buyerId, entryQuantityScaled, quote.ticketCost);

        // ethValue is the per-slice fresh-ETH portion (== msg.value for single-tx callers; the
        // explicit-value ticket-buy slice for Foil purchases and smurf creation).
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

        // --- Ticket funding and quantity; x00 bonus and ticket queuing follow the quest call. ---
        TicketFunding memory ticket;
        uint32 adjustedQty32;
        uint24 targetLevel;
        if (quote.ticketCost != 0) {
            // Accumulated, not assigned: lootboxFlipCredit may already carry the
            // biggest-buy record claim armed above.
            (adjustedQty32, targetLevel) = _callTicketPurchase(
                    buyerId,
                    payerId,
                    entryQuantityScaled,
                    payKind,
                    remainingEth,
                    quote.cachedJpFlag,
                    ticket
                );
            lootboxFlipCredit += ticket.bonusCredit;
        }

        // --- One combined prize-pool RMW for both legs ---
        // Each leg's next/future split was computed above (ticket inside _callTicketPurchase,
        // lootbox in the block above); summing the post-split totals lands both in a single
        // packed write. This runs before the quest-handler / affiliate calls so no
        // observer ever sees a half-applied contribution, and prizePoolFrozen never flips
        // mid-purchase, so both legs route to the same accumulator.
        _addPrizeContribution(
            uint128(ticket.ticketNextShare + uint128(lbShares)),
            uint128(ticket.ticketFutureShare + (lbShares >> 128))
        );

        // --- One combined claimablePool decrement for both legs ---
        // Each leg already debited the buyer's per-player claimable/afking balance (the lootbox
        // shortfall settle above and _processMintPayment inside _callTicketPurchase); their pool
        // draws fold into a single decrement here, before the quest handler / affiliate calls. The
        // only external interaction in this deferral window is a read-only affiliate staticcall,
        // so no observer ever sees a half-applied pool, and the solvency identity holds at every
        // tx boundary.
        uint256 totalClaimableDraw = ticket.ticketClaimableDraw + lootboxPoolDraw;
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
                    0, // This body funds tickets with ETH, claimable or AFKing balances.
                    lootBoxAmount,
                    quote.priceWei,
                    // During the purchase phase the purchase level IS quote.cachedLevel + 1,
                    // so quote.priceWei already equals priceForLevel(quote.cachedLevel + 1); only
                    // jackpot-phase buys need the lookup.
                    quote.cachedJpFlag
                        ? PriceLookupLib.priceForLevel(quote.cachedLevel + 1)
                        : quote.priceWei
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
        if (totalCost >= quote.priceWei) {
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
        if (quote.ticketCost != 0 && targetLevel % 100 == 0 && cachedScore != 0) {
            uint256 bonusQty = (uint256(adjustedQty32) *
                ActivityCurveLib.centuryBps(cachedScore)) /
                ActivityCurveLib.CENTURY_MAX_BPS;
            if (bonusQty != 0) {
                // 20-ETH allowance in the bonus lane's scaled-entry units
                // (4 * QTY_SCALE units = 1 whole ticket = quote.priceWei).
                uint256 maxBonus = (20 ether * 4 * QTY_SCALE) / quote.priceWei;
                uint256 used = _centuryUsedFor(buyerId, targetLevel);
                uint256 remaining = maxBonus > used ? maxBonus - used : 0;
                if (bonusQty > remaining) bonusQty = remaining;
                if (bonusQty != 0) {
                    _setCenturyUsedFor(buyerId, targetLevel, used + bonusQty);
                    adjustedQty32 += uint32(bonusQty);
                }
            }
        }

        // --- Queue tickets ---
        if (adjustedQty32 != 0) {
            _queuePurchaseEntries(buyerId, targetLevel, adjustedQty32);
        }

        // --- Freeze the box-order score; the opener draws its EV allowance. ---
        if (lootBoxAmount != 0) {
            boxWord = _applyBoxOrderScore(boxWord, cachedScore);
        }

        // Settle all affiliate legs (ticket + lootbox, fresh + recycled) in ONE call. The kickback
        // joins the buyer's flip credit; the rolled winner credit is returned and paired below.
        // Runs unconditionally — every purchase carries ETH spend (totalCost != 0 enforced at
        // entry); affiliate scores freeze at level + 1.
        uint32 affWinnerId;
        uint256 affWinnerCredit;
        {
            uint256 lbFreshFlip = lootboxFreshEth != 0
                ? _ethToFlipValue(lootboxFreshEth, quote.priceWei)
                : 0;
            uint256 lbRecycledFlip = lootboxClaimableUsed != 0
                ? _ethToFlipValue(lootboxClaimableUsed, quote.priceWei)
                : 0;
            uint256 affKickback;
            (affWinnerId, affWinnerCredit, affKickback) = affiliate.payAffiliateCombined(
                affiliateCode,
                buyerId,
                quote.cachedLevel + 1,
                ticket.ticketFreshFlip,
                ticket.ticketRecycledFlip,
                lbFreshFlip,
                lbRecycledFlip,
                uint16(cachedScore)
            );
            lootboxFlipCredit += affKickback;
        }

        // Degenesis credit on the whole ticket + lootbox spend: every leg of this body is ETH,
        // claimable or AFKing funded (FLIP-paid tickets route through redeemFlip instead).
        _accruePurchaseDegenesisCredit(buyerId, totalCost);

        // Recycle bonus: spending at least 3 whole tickets' worth of claimable
        // winnings (quote.priceWei is the per-whole-ticket cost) earns 10% of the
        // recycled value back as FLIP flip credit, regardless of any remaining
        // claimable balance. Sum the exact tier debits returned by the payment legs;
        // DirectEth contributes zero and afking principal never earns a recycle bonus.
        uint256 totalClaimableUsed = ticket.ticketClaimableUsed + lootboxClaimableUsed;
        if (totalClaimableUsed >= quote.priceWei * 3) {
            lootboxFlipCredit +=
                (totalClaimableUsed * PRICE_COIN_UNIT) /
                (quote.priceWei * 10);
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
        _accrueAdapterDegenesisCredit(buyerId, totalCost);
    }

    function _accrueAdapterDegenesisCredit(uint32, uint256) internal virtual {}

    /// @dev Ordinary purchases, including smurf creation, retain their credit behavior.
    function _accruePurchaseDegenesisCredit(uint32 buyerId, uint256 cost) internal virtual {
        _accrueDegenesisCredit(buyerId, cost);
    }

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data. A failure with no data (out of gas)
    ///      re-raises as EmptyRevert, the marker the game-over drain treats as a starved call.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) internal pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Execute ticket purchase: payment, boost and affiliate basis. The FLIP caller derives
    ///      its quest units directly from the requested quantity.
    ///      x00 century bonus and ticket queuing are handled by _purchaseFor after score computation.
    ///      `payerId` is the ledger an ETH leg's claimable/AFKing draw debits; zero selects the
    ///      FLIP leg (burned from the buyer's payee), which has no ledger payer.
    /// @param ticket Payment shares and affiliate funding totals filled in place.
    function _callTicketPurchase(
        uint32 buyerId,
        uint32 payerId,
        uint256 quantity,
        MintPaymentKind payKind,
        uint256 value,
        bool cachedJpFlag,
        TicketFunding memory ticket
    )
        private
        returns (uint32 adjustedQty32, uint24 targetLevel)
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
            uint16 boostBps = _consumePurchaseBoost(buyerId);
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
        } else {
            uint32 mintUnits = adjustedQty32;

            // Direct internal payment processing — `value` is the exact ETH this leg carries. The
            // prize-pool shares are returned, not written, so the caller folds the ticket and
            // lootbox legs into one pool RMW.
            (
                ticket.ticketNextShare,
                ticket.ticketFutureShare,
                ticket.ticketClaimableDraw,
                ticket.ticketClaimableUsed
            ) = _recordMintPayment(payerId, costWei, payKind, value);
            // Mint-data recording runs after payment, before quest eligibility is checked.
            _recordMintData(buyerId, targetLevel, mintUnits);

            // Fresh ETH for the affiliate split = ticket cost minus the recycled claimable
            // portion the payment just drew; the afking-drawn portion counts as fresh (own
            // principal -> fresh-rate affiliate, including the lootbox activity score). Pay-kind
            // validation already ran inside the payment processing.
            uint256 freshEth = costWei - ticket.ticketClaimableUsed;

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
            ticket.ticketFreshFlip = freshFlip;
            ticket.ticketRecycledFlip = recycledEth != 0
                ? _ethToFlipValue(recycledEth, priceWei)
                : 0;

            uint256 coinCost = (quantity * (PRICE_COIN_UNIT / 4)) /
                QTY_SCALE;
            ticket.bonusCredit = coinCost / 10;
            if (quantity >= 10 * 4 * QTY_SCALE) {
                ticket.bonusCredit +=
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
