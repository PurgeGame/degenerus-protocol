// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {EntropyLib} from "../libraries/EntropyLib.sol";
import {RngTags} from "../libraries/RngTags.sol";

import {GameAfkingClaims} from "./GameAfkingClaims.sol";
import {GameBoxInternals} from "./GameBoxInternals.sol";

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

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

/// @title ISeatToken
/// @notice Minimal AFKing Subscription Token surface for subscribe: a new run burns one seat.
interface ISeatToken {
    /// @notice GAME-only: burn seat `seatId`, which `holder` must hold. `holder` is the
    ///         subscriber's payee (the owner for a smurf). Called before the run is written.
    /// @custom:reverts OnlyGame If the caller is not GAME.
    /// @custom:reverts InvalidToken If `seatId` does not exist or is not held by `holder`.
    function consumeSeat(address holder, uint256 seatId) external;
}

/**
 * @title GameAfkingModule
 * @author Burnie Degenerus
 * @notice AfKing subscription logic, executed by delegatecall in Game storage.
 *
 * @dev DELEGATECALL CONTEXT: the module inherits `DegenerusGameStorage` (via
 *      `DegenerusGameMintStreakUtils`), so the subscriber set (`_subscribers` of packed
 *      85-bit lanes, `_subMeta` by wallet ID), the cursors (`_subCursor`/`_subOpenCursor`),
 *      the `subsFullyProcessed` STAGE drain-completion flag, the `afkingFunding` ledger,
 *      `claimablePool`, and the activity-score helpers are all in-context plain SLOADs/SSTOREs.
 *      The Game reaches these via its delegatecall dispatch stubs; a direct call to this
 *      module address would have the wrong `msg.sender` for any Game-context invariant.
 *
 * @dev Subscription preparation receives the engine's pinned logical day. Box
 *      consumption uses the active published session word. The Miner module
 *      owns global ordering, fixed gas accounting, and miner compensation.
 *
 * @dev Rewards are derived from each member's checkpoint, never accumulated per day: the
 *      daily pass buys and stamps, and settlement pays the player and the affiliate base for
 *      every day from the checkpoint through the endpoint in one step (see the lane layout in
 *      DegenerusGameStorage).
 *
 * @custom:invariant stETH fallback pulls use an atomic self-call to pinned Lido
 *                   stETH; funded delivery retains strict CEI. The protocol-seat
 *                   pause keys on the un-spoofable pinned VAULT / SDGNRS wallet IDs.
 * @custom:invariant No error-swallowing valve on the funded delivery path: the funded
 *                   process buy is revert-free by construction; a class-B solvency
 *                   underflow FAILS LOUD (the `claimablePool -=` propagates, it is never
 *                   swallowed).
 */
abstract contract GameAfkingModule is GameBoxInternals, DegenerusGameMintStreakUtils, GameAfkingClaims
{
    uint256 private constant HUMAN_ENTRY_GAS = GasBounds.HUMAN_ENTRY_GAS;
    uint256 private constant HUMAN_BOX_GAS = GasBounds.HUMAN_BOX_GAS;
    uint256 private constant HUMAN_TAIL_GAS = GasBounds.HUMAN_TAIL_GAS;

    uint256 private constant SUBSCRIBER_ITEM_GAS = GasBounds.SUBSCRIBER_ITEM_GAS;
    uint256 private constant SUBSCRIBER_WHALE_GAS = GasBounds.SUBSCRIBER_WHALE_GAS;
    uint256 private constant SUBSCRIBER_TAIL_GAS = GasBounds.SUBSCRIBER_TAIL_GAS;
    uint256 private constant AFKING_OPEN_GAS = GasBounds.AFKING_OPEN_GAS;
    uint256 private constant AFKING_SKIP_GAS = GasBounds.AFKING_SKIP_GAS;
    uint256 private constant AFKING_TAIL_GAS = GasBounds.AFKING_TAIL_GAS;

    /*------------------------------------------------------------------
                              Custom errors
    ------------------------------------------------------------------*/
    // error RngLocked() — inherited from DegenerusGameStorage. Reverts a subscribe
    // (create / replace / cancel) from daily preparation being due through the last
    // paid AFKing box opening, and a new run before the day's subscriber pass completed.
    /// @notice Thrown when smite() targets an active afking subscriber, which is immune to
    ///         smite stacks.
    error SmiteeAfkingImmune();
    /// @notice Thrown when smite() targets a player who already holds 10 or more curse
    ///         points (5-stack ceiling) and cannot take on more smite stacks.
    error SmiteCeilingReached();
    // error NotApproved() — inherited from DegenerusGameStorage: a subscribe caller not
    // authorized for the account.
    /// @dev subscribe(_, 0) cancel where the account has no subscription.
    error NotSubscribed();
    /// @dev mineFlip() found all router categories empty — the clean no-work signal
    ///      (the unbounded-scan-free early-return on no pending work).
    error NoWork();

    /*------------------------------------------------------------------
                              Events
    ------------------------------------------------------------------*/
    /// @dev Single canonical subscription-state stream — POST-WRITE state. A cancel, and the
    ///      Vault owner's pause, emit dailyQuantity == 0.
    event SubscriptionUpdated(uint32 indexed player, uint8 dailyQuantity, bool useTickets);
    /// @dev A protocol seat entered (`paused`) or left a pause.
    event SubscriptionPaused(uint32 indexed player, bool paused);
    /// @dev Subscription removed from the iterable set. `reason`:
    ///        1 = unfunded (its unsettled rewards are forfeited)
    ///        2 = seized (its run was closed at the loan seizure)
    event SubscriptionExpired(uint32 indexed player, uint8 reason);
    /// @notice The subscriber's payee paid the residual subscription cost in stETH.
    /// @dev Any share-rounding excess remains in the subscriber's prepaid balance.
    event AfkingStethFunded(uint32 indexed subscriber, uint256 shortfall, uint256 received);

    /// @notice Emitted once per subscriber per delivered afking day — the authoritative
    ///         afking-buy delivery signal (covers VAULT / sDGNRS and every real afker).
    /// @dev The hottest log in the protocol, so its fields ride one word. Packed layout
    ///      (LSB -> MSB):
    ///      - [0..127]   weiIn: delivery ETH-in, claimable leg + prepaid leg. Bounded by ETH supply.
    ///      - [128..151] day: the delivered afking day
    ///      The claimable leg of `weiIn` is itemised by the ClaimableSpent emitted in the
    ///      same receipt, and only when the drain actually moves money.
    event AfkingDelivered(uint32 indexed player, uint256 packed);

    /// @notice The daily subscriber draw paid `winner` for a run `spanDays` old.
    event SubDrawWon(uint32 indexed winner, uint24 day, uint24 spanDays, uint256 flipAmount);

    /*------------------------------------------------------------------
                              Constants
    ------------------------------------------------------------------*/
    /// @dev Afking-local ticket scaling multiplier. AFKING_TICKET_SCALE = 400 makes the
    ///      cost formula unit-consistent: a ticket `amount = quantity * 400`
    ///      entry-units, which the Game's mint recompute divides by `4 * 100`
    ///      (the inherited Storage `QTY_SCALE = 100`), so `cost` stays
    ///      `mintPrice * quantity` in both ticket and lootbox mode.
    ///      ⚠ LOAD-BEARING dual constant: this 400 is
    ///      NUMERICALLY EQUAL to the Game's `4 * QTY_SCALE` (= 4 × 100) but is a
    ///      DISTINCT named constant — it must NOT be collapsed with the inherited
    ///      `QTY_SCALE` (100). They play different roles (entry-unit multiplier
    ///      vs the Game divisor base) that happen to compose to the same 400.
    uint256 internal constant AFKING_TICKET_SCALE = 400;

    /// @dev Prize-pool routing splits for the batched afking buy, mirroring the canonical
    ///      `DegenerusGameMintModule.LOOTBOX_SPLIT_FUTURE_BPS` (9000) and
    ///      `DegenerusGame.PURCHASE_TO_FUTURE_BPS` (1000) — both private cross-contract. A
    ///      lootbox spend routes 90% future / 10% next; a ticket spend the inverse.
    uint256 internal constant AFKING_LOOTBOX_FUTURE_BPS = 9000;
    uint256 internal constant AFKING_TICKET_FUTURE_BPS = 1000;

    /// @dev Daily subscriber draw: FLIP per day of run age, and its cap.
    uint256 private constant SEAT_DRAW_FLIP_PER_DAY = 10;
    uint256 private constant SEAT_DRAW_MAX_FLIP = 4000;

    /*------------------------------------------------------------------
                          Subscription entrypoint
    ------------------------------------------------------------------*/
    /// @notice The SINGLE subscription entrypoint — create, change, or cancel a daily
    ///         subscription for account `id` (0 = caller). dailyQuantity 1..8 upserts;
    ///         dailyQuantity == 0 cancels (the Vault's pauses instead).
    /// @dev Lock create/change/cancel from the day boundary through preparation, RNG and all
    ///      AFKing opens. Outside that window, mode changes may safely relocate IDs.
    /// @dev Authorization is checked ONCE here under the account rule (`_resolveAccount`:
    ///      the caller is the account's payee — its key or a smurf's owner — or an operator
    ///      approved for its ID). Authorization is NEVER re-checked at process-time.
    /// @dev A new run burns seat `seatId` of the subscriber's payee through the token's
    ///      Game-only `consumeSeat`, before the run is written; it starts only after today's
    ///      subscriber pass completed, checkpointed today, so its first purchase and first
    ///      credited day are tomorrow. Changing a live run and a cancel burn nothing. The exempt
    ///      VAULT / SDGNRS subscriptions (made in their own constructors, before the token
    ///      exists) never call the token. Every non-exempt set entry burned a seat and the token
    ///      caps live seats plus set entries.
    /// @dev Every change to a live run settles it first, so a new quantity or mode earns from
    ///      the change onward. A cancel settles both sides, hands the streak back to Quests and
    ///      removes the member; the Vault's quantity 0 is a pause that keeps its seat and earns
    ///      nothing until the owner sets a quantity again.
    /// @dev msg.value > 0 credits the subscriber's prepaid afking ETH (claimablePool moved in
    ///      tandem — the solvency invariant).
    /// @param id Subscriber account (0 = caller).
    /// @param useTickets Mint mode — true = tickets, false = lootboxes.
    /// @param dailyQuantity Daily buy units, 1..8 (upsert); 0 cancels.
    /// @param seatId Seat serial burned when this call starts a new run (ignored otherwise).
    function subscribe(
        uint32 id,
        bool useTickets,
        uint8 dailyQuantity,
        uint256 seatId
    ) external payable {
        // Closed from the liveness trigger onward, which subsumes post-gameOver: the
        // predicate stays true once death is declared (_unlockRng deliberately freezes
        // dailyIdx so the deadman never un-fires, and the phase flags it reads can no
        // longer be cleared). AFKing reward collection closes at the same boundary.
        if (_livenessTriggered()) revert GameOver();

        // Include the pre-first-miner-call window and post-unlock AFKing consumption.
        // The old RNG completion flag remains true during preparation, so it is not a lock.
        if (rngLockedFlag || _afkingResetDay > dailyIdx
            || _simulatedDayIndex() > dailyIdx || _pendingBoxCount != 0) revert RngLocked();

        // The account rule: the caller for id 0, else an account the caller may act for.
        uint32 subId = _resolveAccountId(id);
        if (dailyQuantity != 0) subId = _registerCallerAccount(subId, msg.value);
        // The self shorthand names the caller's own ordinary main (a main sale clears the
        // address's ID), so only an explicit ID can name an acquired account.
        if (id != 0 && _isAcquired(subId)) revert NotApproved();
        // The permanent protocol entries stay at box positions 0 (Vault) and 1 (sDGNRS).
        // This also applies to an approved operator acting for the Vault's account.
        bool vault = subId == VAULT_WALLET_ID;
        bool exemptSub = vault || subId == SDGNRS_WALLET_ID;
        if (dailyQuantity > SUB_MAX_QUANTITY || (useTickets && exemptSub)) revert E();

        if (msg.value > 0) _creditAfkingValue(subId, msg.value);

        uint24 today = _simulatedDayIndex();
        uint256 position1 = _subPosition1(subId);

        if (dailyQuantity == 0) {
            if (position1 == 0) revert NotSubscribed();
            // sDGNRS has no owner to resume it; its only pause is the unfunded one.
            if (exemptSub && !vault) revert E();
            if (vault) {
                // The owner's pause: settle what it earned, then earn nothing while paused.
                if (_afkingProtocolFlags & AFK_VAULT_OWNER_PAUSED == 0) {
                    _pauseProtocolSeat(subId, position1, AFK_VAULT_OWNER_PAUSED);
                }
                emit SubscriptionUpdated(subId, 0, false);
                return;
            }
            // Pay both sides before the record goes, then hand the streak back to Quests.
            _settleBoth(subId);
            uint256 cancelled = _subLaneAt(position1 - 1);
            _finalizeAfking(subId, cancelled, today);
            _removeFromSet(position1);
            _setSubMetaLane(subId, 0);
            emit SubscriptionUpdated(subId, 0, cancelled & SUB_TICKETS_BIT != 0);
            return;
        }

        uint256 config = ((uint256(dailyQuantity) - 1) << SUB_QTY_SHIFT) | (useTickets ? SUB_TICKETS_BIT : 0);
        if (position1 == 0) {
            // A NEW run. The protocol bootstrap runs in the Vault / sDGNRS constructors, before
            // any subscriber pass; every other run starts once today's pass has completed.
            if (!exemptSub) {
                if (_afkingEndpoint() != today) revert RngLocked();
                // A new run burns one seat held by the subscriber's payee, before the run is
                // written. The token makes no callback into the Game.
                ISeatToken(ContractAddresses.AFKING_SUB_TOKEN).consumeSeat(_payee(_walletElement(subId)), seatId);
            }
            // Snapshot the player's (gap-synced) manual quest streak and flip the afking flag
            // (slot-0 completions become streak-neutral / reward-deferred until finalize hands
            // the streak back). The protocol seats start from 0.
            uint256 snap = quests.beginAfking(subId, today);
            _insertMember(subId, _withSubCheckpoint(uint256(subId) | config, today, exemptSub ? 0 : snap), today);
        } else {
            uint256 lane;
            if (vault && _afkingProtocolFlags & AFK_VAULT_OWNER_PAUSED != 0) {
                // The owner's resume; an unfunded pause still holds until the Vault can pay.
                _resumeProtocolSeat(subId, position1, AFK_VAULT_OWNER_PAUSED, _afkingEndpoint());
            } else {
                // Settle at the old rate; the new quantity and mode earn from here on.
                _settleBoth(subId);
            }
            lane = _subLaneAt(position1 - 1);
            uint256 updated = (lane & ~((uint256(7) << SUB_QTY_SHIFT) | SUB_TICKETS_BIT)) | config;
            if ((lane & SUB_TICKETS_BIT != 0) == useTickets) {
                if (updated != lane) _setSubLaneAt(position1 - 1, updated);
            } else {
                // A mode change moves the member to the other section, keeping its run.
                uint24 runStart = _subRunStart(subId);
                _removeFromSet(position1);
                _insertMember(subId, updated, runStart);
            }
        }
        emit SubscriptionUpdated(subId, dailyQuantity, useTickets);
    }

    /// @dev Pause protocol seat `id` for `reason`: settle what it earned, then park its checkpoint
    ///      day so it earns nothing and its streak stands still.
    function _pauseProtocolSeat(uint32 id, uint256 position1, uint8 reason) private {
        if (!_protocolPaused(id)) {
            _settleBoth(id);
            uint256 lane = _subLaneAt(position1 - 1);
            _setSubLaneAt(position1 - 1, _withSubCheckpoint(lane, SUB_PAUSED_DAY, _subCheckpointStreak(lane)));
        }
        _afkingProtocolFlags |= reason;
        emit SubscriptionPaused(id, true);
    }

    /// @dev Clear protocol seat `id`'s pause `reason`. Once no pause holds, its checkpoint day
    ///      becomes `endpoint` — paused days are never credited — and its draw age restarts.
    /// @return lane The seat's lane after the resume.
    function _resumeProtocolSeat(uint32 id, uint256 position1, uint8 reason, uint24 endpoint)
        private returns (uint256 lane)
    {
        _afkingProtocolFlags &= ~reason;
        emit SubscriptionPaused(id, false);
        lane = _subLaneAt(position1 - 1);
        if (_protocolPaused(id)) return lane;
        lane = _withSubCheckpoint(lane, endpoint, _subCheckpointStreak(lane));
        _setSubLaneAt(position1 - 1, lane);
        _setSubRunStart(id, endpoint);
    }

    /// @dev Settle `id` on both sides through the affiliate claim, whose base drain callback
    ///      (`_drainAffiliateBases`) runs the one settlement and pays the player its own share.
    function _settleBoth(uint32 id) private {
        uint32[] memory one = new uint32[](1);
        one[0] = id;
        IDegenerusAffiliate(ContractAddresses.AFFILIATE).claim(one);
    }

    /// @dev Keep the purchase's claimable/prepaid split: top up its prepaid residual only
    ///      (the caller reaches it only while `funding < ethValue`). A refused token top-up uses the ordinary insufficient-funding policy.
    ///      The outer minimum admits the inner calls and the receipt/credit tail;
    ///      all gas beyond the caller's 300k tail reserve is forwarded, without a fixed cap.
    ///      caller starvation fails admission before the atomic attempt. Protocol custody is never pulled: sDGNRS
    ///      preapproves GAME for redemptions whose stETH backing must remain segregated.
    /// @param subscriber The subscriber's wallet ID.
    function _tryFundAfkingSteth(
        uint32 subscriber,
        uint256 ethValue,
        uint256 funding,
        MineFlipGas.Meter memory meter
    ) private returns (uint256) {
        if (subscriber == VAULT_WALLET_ID || subscriber == SDGNRS_WALLET_ID) return funding;
        (bool ok, bytes memory result) = BoundedCall.callRemaining(meter, address(this), 1_000_000, 300_000,
            abi.encodeWithSelector(IDegenerusGame.pullAfkingSteth.selector, subscriber, _payee(_walletElement(subscriber)), ethValue - funding, MineFlipGas.child(meter, 300_000)), 32);
        // Admission already proved the outer attempt was funded. Any failure inside this
        // optional atomic pull leaves funding unchanged, including a dependency that returns
        // successfully only after exhausting the budget for a later inner call.
        return ok ? funding + abi.decode(result, (uint256)) : funding;
    }

    /// @notice Atomic stETH funding operation, callable only by GAME itself.
    /// @dev Dependency failures and invalid receipts roll back the entire attempt.
    ///      Zero is returned only after successful reads prove missing allowance/funds.
    /// @param subId The subscriber account ID.
    /// @param source The subscriber's payee, where the stETH comes from.
    function pullAfkingSteth(uint32 subId, address source, uint256 shortfall)
        external returns (uint256 received)
    {
        if (address(this) != ContractAddresses.GAME || msg.sender != address(this)) revert E();
        if (
            shortfall == 0 || _subPosition1(subId) == 0 || _isAcquired(subId)
                || subId == VAULT_WALLET_ID || subId == SDGNRS_WALLET_ID
                || source != _payee(_walletElement(subId))
        ) revert AfkingStethPullFailed();

        MineFlipGas.Meter memory meter = MineFlipGas.fromCall(100);
        uint256 balanceBefore = _stethFundingWord(meter, abi.encodeWithSelector(IStETH.balanceOf.selector, address(this)));
        uint256 shares = _stethFundingWord(meter, abi.encodeWithSelector(IStETH.getSharesByPooledEth.selector, shortfall));
        // Lido floors both conversions; include the one rounding share if needed.
        if (_stethFundingWord(meter, abi.encodeWithSelector(IStETH.getPooledEthByShares.selector, shares)) < shortfall) ++shares;
        uint256 quote = _stethFundingWord(meter, abi.encodeWithSelector(IStETH.getPooledEthByShares.selector, shares));
        if (_stethFundingWord(meter, abi.encodeWithSelector(IStETH.sharesOf.selector, source)) < shares) return 0;
        // Unlimited allowances are valid; this word is only compared, never added or multiplied.
        (bool allowanceOk, uint256 allowance) = BoundedCall.staticWordRemaining(meter, ContractAddresses.STETH_TOKEN,
            EXTERNAL_READ_GAS, 100_000, abi.encodeWithSelector(IStETH.allowance.selector, source, address(this)));
        if (!allowanceOk) revert AfkingStethPullFailed();
        if (allowance < quote) return 0;
        (bool ok, bytes memory result) = BoundedCall.callRemaining(meter, ContractAddresses.STETH_TOKEN, 300_000, 200_000,
            abi.encodeWithSelector(IStETH.transferSharesFrom.selector, source, address(this), shares), 32);
        if (!ok) revert AfkingStethPullFailed();
        uint256 transferred = abi.decode(result, (uint256));
        uint256 afterBalance = _stethFundingWord(meter, abi.encodeWithSelector(IStETH.balanceOf.selector, address(this)));
        if (afterBalance < balanceBefore) revert AfkingStethPullFailed();
        received = afterBalance - balanceBefore;

        // The recipient's pre-existing fractional share value can contribute
        // one extra wei to its balance delta. Subtraction avoids return+1 overflow.
        if (
            transferred < shortfall || received < transferred || received - transferred > 1
        ) revert AfkingStethPullFailed();

        if (
            received > type(uint128).max - _afkingOf(subId) ||
            received > type(uint128).max - claimablePool
        ) revert AfkingStethPullFailed();

        _creditAfkingValue(subId, received);
        emit AfkingStethFunded(subId, shortfall, received);
    }

    function _stethFundingWord(MineFlipGas.Meter memory meter, bytes memory input) private view returns (uint256 value) {
        bool ok;
        (ok, value) = BoundedCall.staticWordRemaining(meter, ContractAddresses.STETH_TOKEN, EXTERNAL_READ_GAS, 100_000, input);
        if (!ok || value > type(uint128).max) revert AfkingStethPullFailed();
    }

    /*------------------------------------------------------------------
                          Two-ended packed subscriber set
    ------------------------------------------------------------------*/
    /// @dev Insert a member into its mode's section with run-start day `runStart`. Members move
    ///      only from subscribe's unlocked window, with no active AFKing cursor.
    function _insertMember(uint32 id, uint256 lane, uint256 runStart) internal {
        uint256 count = _subscribers.length;
        if (count >= SUBSCRIBER_CAP) revert E();
        uint256 boxes = _subBoxCount;
        uint256 index;
        if (lane & SUB_TICKETS_BIT != 0) {
            index = SUBSCRIBER_CAP - (count - boxes);
        } else {
            index = boxes;
            _subBoxCount = uint16(boxes + 1);
        }
        _setSubLaneAt(index, lane);
        _setSubscriberCount(count + 1);
        _setSubMetaLane(id, (index + 1) | (runStart << 11));
    }

    /// @dev Remove a physical 1-based position, replacing it with its own section's tail.
    ///      The caller clears the removed member's metadata, or immediately reinserts it on a
    ///      mode switch. During preparation do not advance the cursor: the mover still needs
    ///      processing.
    function _removeFromSet(uint256 position) internal {
        uint256 index = position - 1;
        uint256 count = _subscribers.length;
        uint256 boxes = _subBoxCount;
        uint256 last;
        if (index < boxes) {
            last = boxes - 1;
            _subBoxCount = uint16(last);
        } else {
            last = SUBSCRIBER_CAP + 1 - (count - boxes);
        }
        if (index != last) {
            uint256 mover = _subLaneAt(last);
            _setSubLaneAt(index, mover);
            _setSubPosition1(uint32(mover), position);
        }
        _setSubLaneAt(last, 0);
        _setSubscriberCount(count - 1);
    }

    /*------------------------------------------------------------------
                  The _resolveBuy slice builder
    ------------------------------------------------------------------*/
    /// @dev Per-member funding resolution for the process pass — quantity → cost → purchase
    ///      mode + funding split, carrying the slice-builder validation invariants that make a
    ///      funded buy revert-free BY CONSTRUCTION (the SOLE no-brick guarantor under the
    ///      no-valve model):
    ///        (1) quantity ≥ 1 (the lane stores quantity − 1) → never the Game's
    ///            totalCost==0 / dust / TICKET_MIN reverts;
    ///        (2) cost = mintPrice * quantity → the exact cost the Game recomputes;
    ///        (3) cost ≥ mintPrice ≥ 0.01 ETH (the priceForLevel floor) → a lootbox amount
    ///            always meets any min-spend floor; no skip/decline needed;
    ///        (4) 1-wei claimable sentinel → the claimable leg never takes the whole balance;
    ///        (5) ethValue = cost - claimableUse with claimableUse ∈ [0, cost].
    ///      Claimable always pays first; the subscriber's prepaid afking ETH covers the rest.
    ///      ⚠ Dual scale (LOAD-BEARING): the ticket entry-unit `amount`
    ///      uses `AFKING_TICKET_SCALE = 400`; the Game's `/ (4 * 100)` recompute uses the
    ///      inherited Storage `QTY_SCALE = 100` — the two constants are NOT collapsed.
    ///      The caller passes `claimable` as 0 once the game-over sweep has run (GO_SWEPT,
    ///      written only by that one-time sweep, so it is invariant within a tx).
    /// @param claimable The subscriber's claimable balance, sentinel included.
    /// @return ethValue Prepaid portion debited from the subscriber's afkingFunding.
    /// @return amount Ticket entry-units (isTicket) or lootbox spend in wei (!isTicket).
    /// @return isTicket True = buy `amount` ticket entry-units; false = buy an `amount`-wei lootbox.
    /// @return claimableUse Claimable portion of `cost`; cost == ethValue + claimableUse.
    function _resolveBuy(uint256 lane, uint256 mp, uint256 claimable)
        private
        pure
        returns (uint256 ethValue, uint256 amount, bool isTicket, uint256 claimableUse)
    {
        uint256 quantity = _subQuantity(lane);
        uint256 cost = mp * quantity;
        isTicket = lane & SUB_TICKETS_BIT != 0;
        amount = isTicket ? quantity * AFKING_TICKET_SCALE : cost;
        uint256 spendableClaimable = claimable > 0 ? claimable - 1 : 0;
        claimableUse = spendableClaimable < cost ? spendableClaimable : cost;
        ethValue = cost - claimableUse;
    }

    /*------------------------------------------------------------------
                         Shared per-sub funded delivery
    ------------------------------------------------------------------*/
    /// @dev The per-member funded delivery of the process STAGE. The slice is already
    ///      confirmed funded by the caller, so this is revert-free by construction (no
    ///      try/catch). Debits both legs from the subscriber's balance word in one write
    ///      (claimablePool moves once per chunk at the caller; fail-loud on underflow),
    ///      queues the tickets or freezes the box's activity score into the lane. Nothing
    ///      else is written: rewards and the streak derive from the checkpoint.
    /// @param element The subscriber ID receiving the delivery.
    /// @param position The member's physical set position.
    /// @param lane The member's lane.
    /// @param processDay The delivered day.
    /// @param endpoint The reward endpoint while the pass runs: the streak earned strictly
    ///        before this delivery.
    /// @param currentLevel The hoisted level.
    /// @param ticketTargetLevel The resolved ticket mint target (jackpot phase ⇒
    ///        currentLevel, else currentLevel + 1).
    /// @param balances The subscriber's balance word, as loaded after any stETH top-up.
    function _deliverAfkingBuy(
        uint32 element,
        uint256 position,
        uint256 lane,
        uint24 processDay,
        uint24 endpoint,
        uint24 currentLevel,
        uint24 ticketTargetLevel,
        uint256 balances,
        uint256 ethValue,
        uint256 claimableUse,
        uint256 amount,
        bool isTicket
    ) private {
        balances = _debitClaimableAndAfkingFrom(element, balances, claimableUse, ethValue);
        if (claimableUse != 0) {
            // The drain is the one claimable debit with no event of its own, which forces a
            // reader to carry the balance forward from every prior credit. ClaimableSpent
            // already has the shape for it, post-state included. `weiIn` on AfkingDelivered
            // still reports the full cost including this leg; the two are the same money seen
            // twice, not two draws.
            emit ClaimableSpent(
                element,
                claimableUse,
                uint128(balances),
                MintPaymentKind.Internal,
                ethValue + claimableUse
            );
        }

        if (isTicket) {
            // The x00 century quantity bonus is a manual-mint mechanic; afking
            // deliveries queue the paid quantity as-is. The target is at most level + 1, inside
            // the mint ceiling, so it never routes far-future.
            _queuePurchaseEntries(element, ticketTargetLevel, uint32(amount));
        } else {
            // Freeze the box's activity score: the EV input read at opening.
            uint256 activityScore = _playerActivityScoreCachedAt(
                element,
                uint32(_subStreakAt(lane, endpoint)),
                // Streak basis is the phase-correct active ticket level (== the level the manual mint
                // streak is recorded against), NOT the EV/resolver open level (currentLevel + 1):
                // in jackpot phase those differ, and currentLevel + 1 would silently zero a streak
                // whose lastCompleted == level - 1.
                ticketTargetLevel,
                // currentLevel == storage `level` here (sole writer advanceGame, no in-window
                // advance), so pass it directly and skip the 3-arg wrapper's redundant `level` SLOAD.
                currentLevel
            );
            uint256 code = _encodeSubScore(activityScore);
            if ((lane >> SUB_SCORE_SHIFT) & SUB_SCORE_MASK != code) {
                _setSubLaneAt(position, (lane & ~(SUB_SCORE_MASK << SUB_SCORE_SHIFT)) | (code << SUB_SCORE_SHIFT));
            }
        }

        emit AfkingDelivered(element, uint128(ethValue + claimableUse) | (uint256(processDay) << 128));
    }

    /// @dev Hand the afking-computed streak back to the manual quest system on a run-ending path.
    ///      Anchors the handback at `currentDay - 1` (floored at the endpoint): the run's streak
    ///      hands back intact and the manual decay owns it from `currentDay` forward.
    ///      `quests.finalizeAfking` also folds in any manual completion day and is idempotent (a
    ///      no-op if the player is not currently afking).
    /// @param id The wallet ID of the subscriber whose run is ending.
    /// @param lane The subscriber's lane.
    /// @param currentDay The current day (the decay reference passed to DegenerusQuests).
    function _finalizeAfking(uint32 id, uint256 lane, uint24 currentDay) private {
        uint24 endpoint = _afkingEndpoint();
        uint256 earned = _subStreakAt(lane, endpoint);
        uint24 anchor = endpoint;
        if (currentDay != 0 && currentDay - 1 > anchor) anchor = currentDay - 1;
        quests.finalizeAfking(
            id,
            earned > type(uint24).max ? type(uint24).max : uint24(earned),
            anchor,
            currentDay
        );
    }

    /// @notice Stop the AFKing runs a loan seizure hands to its lender: the seized account's own
    ///         and, for a main, every smurf's. Reached only by AdvanceModule's `_seizeLoan`
    ///         delegatecall, after the ownership write.
    /// @dev Walks the main's append-only smurf list (`_smurfWords`, length = lifetime
    ///      `SMURF_COUNT`). Each stopped run hands its streak back to Quests now and keeps its
    ///      lane, marked for removal: a box it already paid still opens in order, and the next
    ///      preparation pass removes it before buying. Until then its earned days stay
    ///      settleable.
    /// @param id The seized account.
    /// @param mainSale True when `id` was an ordinary main (its smurfs transfer with it).
    function cancelLiquidatedSubscriptions(uint32 id, bool mainSale) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        _cancelAcquiredSubscription(id);
        if (!mainSale) return;
        uint256 count = uint16(mintPacked_[id] >> BitPackingLib.SMURF_COUNT_SHIFT);
        mapping(uint256 => uint256) storage words = _smurfWords[id];
        uint256 word;
        for (uint256 i; i < count; ++i) {
            if (i & 7 == 0) word = words[i >> 3];
            _cancelAcquiredSubscription(uint32(word >> ((i & 7) * 32)));
        }
    }

    function _cancelAcquiredSubscription(uint32 id) private {
        (uint256 lane, uint256 position1) = _subLaneOf(id);
        if (position1 == 0 || lane & SUB_REMOVAL_BIT != 0) return;
        _finalizeAfking(id, lane, _simulatedDayIndex());
        _setSubLaneAt(position1 - 1, lane | SUB_REMOVAL_BIT);
        emit SubscriptionUpdated(id, 0, lane & SUB_TICKETS_BIT != 0);
    }

    /*------------------------------------------------------------------
              The REQUIRED-PATH process STAGE (stamp + debit)
    ------------------------------------------------------------------*/


    /// @notice Prepare the pinned day's subscriptions, boxes first and tickets second.
    /// @dev The previous read cohort completes before this pass. Public subscription changes
    ///      remain locked from daily due through the last AFKing open, so each member is visited
    ///      once and no signup can join this day. Same-section removal reprocesses its
    ///      unvisited tail mover. A funded box freezes its score into the lane; tickets queue
    ///      directly. The cohort's unit price and which protocol seats bought live in the shared
    ///      header. The daily commitment follows completion, and boxes consume that published
    ///      word later.
    /// @dev Funding: an ordinary member that cannot pay expires and forfeits what it has not
    ///      settled. A protocol seat that cannot pay is settled and paused instead (no purchase,
    ///      nothing earned), and resumes on the first day it can pay again.
    /// @dev NO error-swallowing valve: a funded slice is revert-free by construction; the
    ///      chunk-end `claimablePool -=` FAILS LOUD (class B, must propagate).
    /// @notice Stage the pinned daily subscription cohort before its request is sealed.
    function runSubscriberWork_g6352(uint24 processDay, uint256 gasAllowance)
        external returns (MineFlipGas.Result memory)
    {
        return _runSubscriberWork(processDay, gasAllowance);
    }

    struct SubscriberWork {
        MineFlipGas.Meter meter;
        uint256 processed;
        uint256 mp;
        uint256 cursor;
        uint256 boxStamps;
        uint256 boxEthAccrued;
        uint256 ticketEthAccrued;
        uint24 resumeDay;
    }

    function _runSubscriberWork(uint24 processDay, uint256 gasAllowance)
        private returns (MineFlipGas.Result memory result)
    {
        SubscriberWork memory c;
        c.meter = MineFlipGas.start(gasAllowance);
        if (processDay != _afkingResetDay || processDay <= dailyIdx) revert E();
        if (subsFullyProcessed) { result.done = true; return result; }
        if (!_rngComplete() || rngLockedFlag || _rngRequestActive() || _livenessTriggered()) return result;

        c.mp = _mintPriceInContext();
        // Hoist the level read once.
        uint24 currentLevel = level;
        // Chunk-invariant global reads, hoisted once: the GO_SWEPT flag (written only by
        // the one-time game-over sweep, unreachable from this loop) and the ticket target
        // level (jackpotPhaseFlag is fixed across the pre-RNG stage). Quest finalization
        // writes only quests-side storage; the pinned Lido stETH funding path has no
        // sender or recipient callbacks that could change these game-phase inputs.
        bool swept = _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0;
        uint24 ticketTargetLevel = jackpotPhaseFlag
            ? currentLevel
            : currentLevel + 1;
        // While this pass runs, rewards accrue through the last completed pass; a protocol seat
        // resuming in this pass earns from this day on.
        uint24 endpoint = _afkingEndpoint();
        c.resumeDay = processDay - 1;

        // sDGNRS level-start whale purchase, attempted ONCE per level here at the start of
        // afking processing (out of the per-sub loop, so it adds NO per-sub cost). On the first
        // STAGE pass of each new level (the `_sdgnrsBonusLevel` latch — level 0 excluded, latch
        // starts at 0), the whale module sizes and delivers sDGNRS's aggregate whale-pass
        // purchase: the largest whole group of five paid passes whose quote fits a quarter of
        // its claimable, capped at the route's 1,000. The latch stamps on the ATTEMPT, whatever
        // its outcome: a level whose first STAGE pass finds sDGNRS too poor for one group buys
        // nothing that level, and no later chunk/day this level tries again — one probe per
        // level, never a per-day poll of the claimable. The module re-checks the RNG timing
        // contract live (unlocked AND the process day's word uncommitted — the same two halves
        // the STAGE gate keys on) and skips a terminal game, returning 0 for both, so this
        // block never reverts the crank; those returns
        // latch too (they are unreachable through this gate and cost the level its buy, not
        // the crank its day). sDGNRS's ordinary daily box is untouched — the per-sub loop still
        // stamps it. A real purchase's operation consumes first-progress permission; subsequent
        // items use the remaining caller budget. The attempted-level latch makes even a no-buy
        // probe resumable.
        if (!swept && currentLevel > _sdgnrsBonusLevel) {
            if (!MineFlipGas.canRun(c.meter, SUBSCRIBER_WHALE_GAS, SUBSCRIBER_TAIL_GAS)) return result;
            _sdgnrsBonusLevel = currentLevel;
            // Before the whale module sizes its budget, sDGNRS AFKing funding is topped up to its
            // target, kept whether or not a group is bought. The STAGE gate above already
            // excludes every state the whale module refuses.
            (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENESIS_MODULE.delegatecall(
                abi.encodeWithSelector(IDegenerusGameDegenesisModule.topUpSdgnrsAfking_g318.selector)
            );
            if (!ok) _revertDelegate(data);
            (ok, data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseWhalePassForSdgnrs_g470.selector, processDay
                )
            );
            if (!ok) _revertDelegate(data);
            abi.decode(data, (uint256)); // Authenticate the pinned worker's return shape.
            result.progressed = true;
            MineFlipGas.markProgress(c.meter);
        }

        c.cursor = _subCursor;
        if (c.cursor == 0) {
            // The pass's first visit: price the new cohort and clear the protocol BOUGHT bits.
            _afkingCohortPriceMilli = uint16(_packEthToMilliEth(c.mp));
            _afkingProtocolFlags &= ~(AFK_VAULT_BOUGHT | AFK_SDGNRS_BOUGHT);
        }
        // Batched pool accounting: each funded buy debits its full cost from its funding
        // accounts and accrues that spend here by mode. At chunk end claimablePool releases the
        // sum once and the prize pools are credited once (boxes 90% future / 10% next, tickets
        // 90% next / 10% future), so the per-sub cost is an add, not a pool SSTORE.

        // Public membership/mode changes are locked throughout this pass. Each section
        // is dense, and its zero sentinel stays empty even at the combined 2000-member cap.
        while (true) {
            uint256 position = c.cursor < SUBSCRIBER_TICKET_PHASE
                ? c.cursor : SUBSCRIBER_CAP - (c.cursor - SUBSCRIBER_TICKET_PHASE);
            uint256 lane = _subLaneAt(position);
            uint32 element = uint32(lane);
            if (!MineFlipGas.canRun(c.meter, element == 0 ? 0 : SUBSCRIBER_ITEM_GAS, SUBSCRIBER_TAIL_GAS)) break;
            MineFlipGas.markProgress(c.meter);
            if (element == 0) {
                result.progressed = true;
                if (c.cursor < SUBSCRIBER_TICKET_PHASE) {
                    c.cursor = SUBSCRIBER_TICKET_PHASE;
                    continue;
                }
                result.done = true;
                break;
            }

            // A seized run closed at its seizure; remove it before it buys again. The section
            // tail replaces it and is processed at this cursor.
            if (lane & SUB_REMOVAL_BIT != 0) {
                _removeFromSet(position + 1);
                _setSubMetaLane(element, 0);
                emit SubscriptionExpired(element, 2);
                unchecked { ++c.processed; }
                continue;
            }

            bool protocolSeat = element == VAULT_WALLET_ID || element == SDGNRS_WALLET_ID;
            // The Vault owner's pause buys nothing until the owner resumes it.
            if (protocolSeat && element == VAULT_WALLET_ID
                && _afkingProtocolFlags & AFK_VAULT_OWNER_PAUSED != 0) {
                unchecked { ++c.cursor; ++c.processed; }
                continue;
            }

            uint256 balances = balancesPacked[element];
            (uint256 ethValue, uint256 amount, bool isTicket, uint256 claimableUse) =
                _resolveBuy(lane, c.mp, swept ? 0 : uint128(balances));
            uint256 funding = balances >> 128;
            if (funding < ethValue) {
                funding = _tryFundAfkingSteth(element, ethValue, funding, c.meter);
                // A stETH pull credits the prepaid half.
                balances = balancesPacked[element];
            }

            if (funding < ethValue) {
                if (protocolSeat) {
                    // Settle what it earned, then pause: no purchase and nothing earned until
                    // it can pay again.
                    uint8 unfunded = element == VAULT_WALLET_ID ? AFK_VAULT_UNFUNDED : AFK_SDGNRS_UNFUNDED;
                    if (_afkingProtocolFlags & unfunded == 0) _pauseProtocolSeat(element, position + 1, unfunded);
                    unchecked { ++c.cursor; ++c.processed; }
                    continue;
                }
                // An unfunded ordinary member expires: hand its streak back (anchored at
                // yesterday; the manual decay owns it from today), then remove it. What it had
                // not settled is forfeited.
                _finalizeAfking(element, lane, processDay);
                _removeFromSet(position + 1);
                _setSubMetaLane(element, 0);
                emit SubscriptionExpired(element, 1);
                unchecked { ++c.processed; }
                continue;
            }

            if (protocolSeat) {
                uint8 unfunded = element == VAULT_WALLET_ID ? AFK_VAULT_UNFUNDED : AFK_SDGNRS_UNFUNDED;
                // Funded again: resume, with this pass's endpoint as its checkpoint day.
                if (_afkingProtocolFlags & unfunded != 0) {
                    lane = _resumeProtocolSeat(element, position + 1, unfunded, c.resumeDay);
                }
                _afkingProtocolFlags |= element == VAULT_WALLET_ID ? AFK_VAULT_BOUGHT : AFK_SDGNRS_BOUGHT;
            }

            // BUY + DEBIT. The funded, well-formed slice is delivered revert-free by
            // construction (no try/catch). Admission reserves the complete item and the
            // accounting/checkpoint tail.
            _deliverAfkingBuy(
                element,
                position,
                lane,
                processDay,
                endpoint,
                currentLevel,
                ticketTargetLevel,
                balances,
                ethValue,
                claimableUse,
                amount,
                isTicket
            );

            // Accrue the full buy cost for the batched pool credit below — a box buy funds the
            // box pool, a ticket buy the ticket pool. The entry-unit `amount` is the box's wei
            // spend only in lootbox mode, so the routing keys on `cost`, never `amount`.
            uint256 cost = ethValue + claimableUse;
            if (isTicket) {
                c.ticketEthAccrued += cost;
            } else {
                c.boxEthAccrued += cost;
                unchecked { ++c.boxStamps; }
            }

            unchecked { ++c.cursor; ++c.processed; }
        }

        // Persist the advanced cursor (uint16) for the next chunk / call.
        _subCursor = uint16(c.cursor);
        // Commit this chunk's pending-box count in ONE warm RMW (the cursor write above
        // already dirtied the shared slot) — the per-stamp version would pay it per sub.
        if (c.boxStamps != 0) {
            unchecked {
                _pendingBoxCount += uint16(c.boxStamps);
            }
        }
        // Release the chunk's spend from claimablePool in one checked debit, then credit the
        // prize pools once for the batched box + ticket spend.
        uint256 spent = c.boxEthAccrued + c.ticketEthAccrued;
        if (spent != 0) claimablePool -= uint128(spent);
        _routeAfkingPoolEth(c.boxEthAccrued, c.ticketEthAccrued);
        result.progressed = result.progressed || c.processed != 0;
        result.rewardBasis = c.processed;
        if (result.done) {
            subsFullyProcessed = true;
            _afkingEndpointDay = processDay;
            result.progressed = true;
            MineFlipGas.markProgress(c.meter);
        }
        MineFlipGas.finish(c.meter);
    }

    /// @dev Route a chunk's batched afking spend to the prize pools, mirroring the normal-buy
    ///      splits: lootbox ETH 90% future / 10% next (100% next in distress, matching
    ///      `_purchaseForWith`), ticket ETH 90% next / 10% future (matching `_recordMintPayment`). One
    ///      pooled read+write per chunk; routes to the pending pools while the prize pool is
    ///      frozen. The per-buy debit already moved the ETH out of the funding source, so this
    ///      only credits the pools (the counterpart of that debit).
    function _routeAfkingPoolEth(uint256 boxEth, uint256 ticketEth) private {
        if (boxEth == 0 && ticketEth == 0) return;
        uint256 nextShare;
        uint256 futureShare;
        if (boxEth != 0) {
            if (_isDistressMode()) {
                nextShare += boxEth;
            } else {
                uint256 boxFuture = (boxEth * AFKING_LOOTBOX_FUTURE_BPS) / 10_000;
                futureShare += boxFuture;
                nextShare += boxEth - boxFuture;
            }
        }
        if (ticketEth != 0) {
            uint256 tFuture = (ticketEth * AFKING_TICKET_FUTURE_BPS) / 10_000;
            futureShare += tFuture;
            nextShare += ticketEth - tFuture;
        }
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(
                pNext + uint128(nextShare),
                pFuture + uint128(futureShare)
            );
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(
                next + uint128(nextShare),
                future + uint128(futureShare)
            );
        }
    }

    /*==================================================================
        PART B — the post-RNG OPEN-PASS + the ROUTER
    ==================================================================*/

    /// @dev Reverts with the delegatecall failure reason bytes. Canonical module tail
    ///      (cf. DegenerusGameDegeneretteModule / DecimatorModule) for the
    ///      calls into the Degenesis and Whale modules.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Materialize ONE subscriber's stamped afking box (the freeze-critical open).
    ///      The box uses the published active session word and subscriber ID; the stamp
    ///      day identifies the cohort, not the seed. The level reads live inside `resolveAfkingBox`. Each stamp opens
    ///      exactly once because the opener walks the box section in order and its cursor
    ///      only moves forward. `resolveAfkingBox` is the one freeze-correct seam (the public
    ///      `resolveLootboxDirect` uses a different action tag).
    /// @param element The subscriber ID whose stamped box is materialized.
    /// @param amount The box spend in wei: the cohort's unit price times the member's quantity.
    /// @param day The cohort's stamp day.
    /// @param word The published active session word, read once by the caller.
    /// @param score The member's frozen activity score.
    function _openAfkingBox(uint32 element, uint256 amount, uint24 day, uint256 word, uint16 score) private {
        _boxResolveAfkingBox(element, amount, day, word, score);
    }



    /// @notice Open stamped boxes belonging to the unlocked active session.
    function runAfkingWork_g8553(uint256 gasAllowance) external returns (MineFlipGas.Result memory) {
        return _runAfkingWork(gasAllowance);
    }

    /// @dev The cursor and the pending count are held locally and stored once after the loop.
    ///      `resolveAfkingBox` reads neither and calls only pinned protocol contracts, none of
    ///      which re-enters this walk.
    function _runAfkingWork(uint256 gasAllowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(gasAllowance);
        uint256 pending = _pendingBoxCount;
        if (pending == 0) { result.done = true; return result; }
        if (_rngConsumerStage() != 2) return result;
        uint256 cursor = _subOpenCursor;
        uint256 initialCursor = cursor;
        uint256 initialPending = pending;
        // Preparation for this day stamped every paid box; the next preparation waits for
        // pending to reach zero, so the reset day, the cohort price and the protocol BOUGHT
        // bits still describe this cohort.
        uint24 stampDay = _afkingResetDay;
        uint256 unitPrice = _unpackMilliEthToWei(_afkingCohortPriceMilli);
        uint8 protocolFlags = _afkingProtocolFlags;
        uint256 word = _lootboxWord(_rngReadBuffer());
        // Cache three lanes at a time. Membership cannot change until pending is zero.
        uint256 lanes = _subscriberWordAt(cursor) >> ((cursor % 3) * SUB_LANE_BITS);
        while (true) {
            uint256 lane = lanes & SUB_LANE_MASK;
            uint32 element = uint32(lane);
            // Every ordinary member left in the box section bought in preparation. Only the
            // permanent protocol members may remain without buying (paused).
            bool skip = (element == VAULT_WALLET_ID && protocolFlags & AFK_VAULT_BOUGHT == 0)
                || (element == SDGNRS_WALLET_ID && protocolFlags & AFK_SDGNRS_BOUGHT == 0);
            if (!MineFlipGas.canRun(meter, skip ? AFKING_SKIP_GAS : AFKING_OPEN_GAS, AFKING_TAIL_GAS)) break;
            if (!skip) {
                // The stamp/count invariant guarantees a positive count here.
                unchecked { --pending; }
                _openAfkingBox(
                    element,
                    unitPrice * _subQuantity(lane),
                    stampDay,
                    word,
                    _decodeSubScore((lane >> SUB_SCORE_SHIFT) & SUB_SCORE_MASK)
                );
                ++result.rewardBasis;
            }
            ++cursor;
            MineFlipGas.markProgress(meter);
            if (pending == 0) break;
            lanes = cursor % 3 == 0 ? _subscriberWordAt(cursor) : lanes >> SUB_LANE_BITS;
        }
        if (cursor != initialCursor) {
            _subOpenCursor = uint16(cursor);
            if (pending != initialPending) _pendingBoxCount = uint16(pending);
        }
        result.progressed = cursor != initialCursor;
        result.done = pending == 0;
        if (result.done) _tryCompleteRng();
        MineFlipGas.finish(meter);
    }



    /// @notice Settle the active session's box entries in FIFO order, after AFKing.
    function runHumanBoxWork_g315(uint256 gasAllowance) external returns (MineFlipGas.Result memory) {
        return _runHumanBoxWork(gasAllowance);
    }

    /// @dev Each entry is admitted against its own box bound, then the advanced
    ///      cursor is stored BEFORE the entry's rewards run: the cursor alone marks an entry
    ///      settled, and the entry's legs and the cursor move revert together. The cursor counts
    ///      entries, not words, so a call may stop or resume at any of a word's three lanes.
    ///      Once every entry has settled, completion needs only the tail allowance; a call that
    ///      cannot afford it leaves boxCursor at the read count and the next call completes
    ///      without replaying.
    function _runHumanBoxWork(uint256 gasAllowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(gasAllowance);
        if (humanReadComplete) { result.done = true; return result; }
        if (_rngConsumerStage() != 3) return result;
        uint48 idx = _rngReadBuffer();
        uint256 indexWord = _lootboxWord(idx);
        uint256 cur = boxCursor;
        uint256 qlen = boxReadCount;
        uint24 currentLevel = level + 1;
        while (cur < qlen) {
            uint256 entry = _boxEntryAt(idx, cur);
            uint256 boxes = _boxEntryCount(entry);
            if (!MineFlipGas.canRun(meter, HUMAN_ENTRY_GAS + boxes * HUMAN_BOX_GAS, HUMAN_TAIL_GAS)) break;
            boxCursor = uint48(cur + 1);
            _boxResolveHumanBoxOrder(idx, cur, entry, indexWord, currentLevel);
            ++cur;
            result.progressed = true;
            MineFlipGas.markProgress(meter);
            result.rewardBasis += boxes;
        }
        if (cur == qlen && MineFlipGas.canRun(meter, 0, HUMAN_TAIL_GAS)) {
            humanReadComplete = true;
            result.progressed = true;
            MineFlipGas.markProgress(meter);
            result.done = true;
            _tryCompleteRng();
        }
        MineFlipGas.finish(meter);
    }

    /// @dev In-context mint price (the bounty's ETH→FLIP conversion divisor). Mirrors
    ///      the Game's `mintPrice` — the price for the active ticket level —
    ///      read in-context so the bounty math needs no external/self call. Single use
    ///      site (the bounty `unit`); never an open-time seed input (FREEZE-safe).
    function _mintPriceInContext() internal view returns (uint256) {
        return PriceLookupLib.priceForLevel(_activeTicketLevel());
    }

    /*------------------------------------------------------------------
                              Daily subscriber draw
    ------------------------------------------------------------------*/


    /// @notice One member wins FLIP by the age of its run: 10 per day since its run started,
    ///         capped at 4,000. Reached only by AdvanceModule's delegatecall when a day's word
    ///         lands after that day's lock.
    /// @dev The Vault (box position 0) is never drawn; sDGNRS (position 1) is. A seized run and
    ///      a paused protocol seat sit out; a resumed protocol seat's age restarts at its resume.
    /// @param day The day whose recorded word picks the winner.
    function runSubDraw_g1232(uint24 day) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint256 len = _subscribers.length;
        uint256 word = _recordedDailyWord(day);
        if (len < 2 || word == 0) return;
        uint256 boxes = _subBoxCount;
        uint256 idx = 1 + uint256(EntropyLib.hash2(RngTags.SUBSCRIBER_DRAW, word)) % (len - 1);
        uint256 lane = _subLaneAt(idx < boxes ? idx : SUBSCRIBER_CAP - (idx - boxes));
        uint32 winner = uint32(lane);
        if (lane & SUB_REMOVAL_BIT != 0 || _protocolPaused(winner)) return;
        uint24 startDay = _subRunStart(winner);
        uint24 endpoint = _afkingEndpoint();
        if (endpoint <= startDay) return;
        uint256 spanDays;
        unchecked {
            spanDays = endpoint - startDay;
        }
        uint256 prize = spanDays * SEAT_DRAW_FLIP_PER_DAY;
        if (prize > SEAT_DRAW_MAX_FLIP) prize = SEAT_DRAW_MAX_FLIP;
        coinflip.creditFlip_g317(winner, prize);
        emit SubDrawWon(winner, day, uint24(spanDays), prize);
    }

    /*------------------------------------------------------------------
                                  Claims
    ------------------------------------------------------------------*/
    /// @notice Permissionless AFKing claim — settles each listed sub on both sides: the sub
    ///         its own reward and its affiliate base to the upline, for every day from its
    ///         checkpoint through the last completed subscriber pass. Always credits the subs
    ///         and their uplines, never the caller; a re-claim finds nothing. Closed from the
    ///         liveness trigger onward.
    /// @dev Routed through the affiliate claim, which resolves each run of consecutive subs
    ///      sharing a direct affiliate once; ordering a batch by affiliate keeps it cheapest.
    /// @param ids The subscriber accounts to settle (0 = caller). A non-member settles nothing.
    function claimAfkingFlip(uint32[] calldata ids) external {
        if (_livenessTriggered()) revert GameOver();
        uint256 len = ids.length;
        uint32[] memory subs = new uint32[](len);
        uint32 self = _walletIdOf(msg.sender);
        for (uint256 i; i < len; ) {
            uint32 id = ids[i];
            subs[i] = id == 0 ? self : id;
            unchecked { ++i; }
        }
        IDegenerusAffiliate(ContractAddresses.AFFILIATE).claim(subs);
    }

    /// @notice Emitted when a curse is cleared via the permissionless paid cure.
    event Decursed(address indexed curer, uint32 indexed target);

    /// @notice Emitted when a deity adds a curse stack to a smitee.
    event Smited(uint256 indexed deityId, uint32 indexed smitee);

    /// @notice Permissionless paid cure: clear account `id`'s cashout/smite curse for 100 FLIP.
    /// @dev No authorization — clearing another account's curse is purely beneficial, and the
    ///      caller pays from its own wallet. Reverts when the target already has no curse so
    ///      the caller never wastes the burn.
    /// @param id The cursed account (0 = caller; otherwise allocated).
    function decurse(uint32 id) external {
        uint32 target = _creditAccountId(id);
        uint256 curse = (mintPacked_[target] >> BitPackingLib.CURSE_COUNT_SHIFT) &
            BitPackingLib.MASK_5;
        if (curse == 0) revert NothingToClaim();
        coin.burnCoin(msg.sender, PRICE_COIN_UNIT / 10);
        _clearCurse(target);
        emit Decursed(msg.sender, target);
    }

    /// @notice A deity (soulbound pass owner) adds a saturating +2 curse stack to account
    ///         `smiteeId` for 200 FLIP from the caller. Validated before the burn: active afkers
    ///         are immune (the sole immunity), the smite path caps at a 10-point (5-stack)
    ///         ceiling below the 20-point counter cap, and the protocol accounts are skipped (the
    ///         redemption-snapshot reason). Self-smite is allowed — harmless, since the counter
    ///         only lowers the score. The pass NFT sits at the deity account's main wallet, so
    ///         the main wallet smites.
    /// @param smiteeId The account receiving the stack (0 = caller; otherwise allocated).
    function smite(uint256 deityId, uint32 smiteeId) external {
        if (
            IDegenerusDeityPassOwner(ContractAddresses.DEITY_PASS).ownerOf(deityId) !=
            msg.sender
        ) revert Unauthorized();
        uint32 smitee = _creditAccountId(smiteeId);
        uint256 packed = mintPacked_[smitee];
        if (_isLiveMember(smitee)) {
            revert SmiteeAfkingImmune(); // active-afker immunity
        }
        uint256 curse = (packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_5;
        if (curse >= 10) revert SmiteCeilingReached(); // 5-stack smite ceiling (1 stack = 2 points)
        if (
            smitee == VAULT_WALLET_ID ||
            smitee == SDGNRS_WALLET_ID ||
            smitee == GNRUS_WALLET_ID
        ) revert Unauthorized(); // protocol-addr skip
        coin.burnCoin(msg.sender, PRICE_COIN_UNIT / 5);
        _applyCurseStack(smitee);
        emit Smited(deityId, smitee);
    }
}

/// @dev Minimal deity-pass owner view for the smite gate (soulbound, tokenId = symbolId 0-31).
interface IDegenerusDeityPassOwner {
    /// @notice DegenerusDeityPass's ERC721 owner of `tokenId` (reverts if it does not exist).
    function ownerOf(uint256 tokenId) external view returns (address);
}
