// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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
import {
    IDegenerusGameLootboxModule,
    IDegenerusGameWhaleModule
} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {IStETH} from "../interfaces/IStETH.sol";

/// @title IQuestCompletionView
/// @notice Minimal quest-view surface for the day-0 grounding check: the per-slot
///         completion flags alone, skipping the full `playerQuestStates` tuple
///         (streak / lastCompletedDay / progress) and its per-slot validity and
///         native-unit conversion work.
interface IQuestCompletionView {
    /// @notice Quests' today-completion flags for wallet `id` ((false, false) for 0).
    function questCompletionToday(uint32 id) external view returns (bool slot0, bool slot1);
}

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
 * @notice Delegate-called module owning the AfKing subscription logic. The bulk of that
 *         logic sits in this module's OWN EIP-170 budget; only the thin dispatch stubs
 *         (subscribe / claimAfkingFlip / drainAffiliateBase / decurse / smite /
 *         subscriberSetLength) occupy space in the DegenerusGame image.
 *
 * @dev DELEGATECALL CONTEXT: the module inherits `DegenerusGameStorage` (via
 *      `DegenerusGameMintStreakUtils`), so the subscriber set
 *      (`_subOf` by wallet ID, `_subscribers` of packed uint32 IDs), the cursors
 *      (`_subCursor`/`_subOpenCursor`), the `subsFullyProcessed` STAGE
 *      drain-completion flag, the `afkingFunding` ledger, `claimablePool`, `operatorApprovals`,
 *      and the activity-score helpers are all in-context plain SLOADs/SSTOREs.
 *      The account-resolution / pass-horizon / afking-snapshot / afking-funding
 *      reads are all in-context here. The Game
 *      reaches these via its delegatecall dispatch stubs; a direct call to this
 *      module address would have the wrong `msg.sender` for any Game-context
 *      invariant.
 *
 * @dev Subscription preparation receives the engine's pinned logical day. Box
 *      consumption uses the active published session word. The Keeper module
 *      owns global ordering, fixed gas accounting, and miner compensation.
 *
 * @custom:invariant stETH fallback pulls use an atomic self-call to pinned Lido
 *                   stETH; funded delivery retains strict CEI. The
 *                   two-tier funding-skip exemption keys on
 *                   the un-spoofable pinned `ContractAddresses.VAULT` / `SDGNRS`
 *                   identity (on `player`, never `src`) — no settable exemption.
 * @custom:invariant No error-swallowing valve on the funded delivery path: the funded
 *                   process buy is revert-free by construction; a class-B solvency
 *                   underflow FAILS LOUD (the `claimablePool -=` propagates, it is never
 *                   swallowed).
 */
contract GameAfkingModule is DegenerusGameMintStreakUtils {
    uint256 private constant HUMAN_ENTRY_GAS = GasBounds.HUMAN_ENTRY_GAS;
    uint256 private constant HUMAN_BOX_GAS = GasBounds.HUMAN_BOX_GAS;
    uint256 private constant HUMAN_PRESALE_GAS = GasBounds.HUMAN_PRESALE_GAS;
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
    // (create / replace / cancel) attempted during the RNG freeze window: the subscriber
    // set must be frozen across [request -> unlock].
    /// @notice Thrown when smite() targets an active afking subscriber, which is immune to
    ///         smite stacks.
    error SmiteeAfkingImmune();
    /// @notice Thrown when smite() targets a player who already holds 10 or more curse
    ///         points (5-stack ceiling) and cannot take on more smite stacks.
    error SmiteCeilingReached();
    // error NotApproved() — inherited from DegenerusGameStorage: a subscribe caller not
    // authorized for the account, or an external funding source that does not authorize
    // the subscriber.
    /// @dev subscribe(_, 0) cancel where the caller has no active subscription
    ///      (nothing to tombstone).
    error NotSubscribed();
    /// @dev mineFlip() found all router categories empty — the clean no-work signal
    ///      (the unbounded-scan-free early-return on no pending work).
    error NoWork();
    /// @dev subscribe (upsert) starting a NEW afking run that is not grounded on a real
    ///      purchase — neither already bought today nor a funded in-tx cover-buy. An
    ///      unfunded start reverts rather than beginning an inert, free-riding run.
    error MustPurchaseToBeginAfking();

    /*------------------------------------------------------------------
                              Events
    ------------------------------------------------------------------*/
    /// @dev Single canonical subscription-state stream — POST-WRITE full state.
    ///      Cancel (subscribe(_, 0)) emits with dailyQuantity == 0.
    ///      `fundingSource` is the external funding account's key (address(0) = self);
    ///      indexed so a source can filter the log for every account it funds.
    event SubscriptionUpdated(
        uint32 indexed player,
        uint8 dailyQuantity,
        bool drainGameCreditFirst,
        bool useTickets,
        uint32 indexed fundingSource
    );
    /// @dev Per-player pre-check skip inside the process pass. `reason`:
    ///        2 = AlreadyAutoBoughtToday (sub.lastAutoBoughtDay >= today)
    ///        3 = InsufficientPool  (afkingFunding[src] < ethValue) — funding skip
    ///      lastAutoBoughtDay is UNCHANGED on a skip.
    event PlayerSkipped(uint32 indexed player, uint8 reason);
    /// @dev Subscription removed from the iterable set. `reason`:
    ///        1 = AutoPause (funding-skip kill of a NORMAL sub)
    ///        2 = CancelReclaim (in-pass reclaim of an externally-cancelled tombstone)
    event SubscriptionExpired(uint32 indexed player, uint8 reason);
    /// @dev A pending-box count with no openable stamp behind it was cleared so the read
    ///      cohort can complete; the stamps' ETH stays in the prize pools.
    event AfkingBoxCountForfeited(uint16 count);

    /// @notice A consented funding account paid the residual subscription cost in stETH.
    /// @dev `source` is the funding account's key (the stETH leaves its payee). Any
    ///      share-rounding excess remains in the source's prepaid balance.
    event AfkingStethFunded(
        uint32 indexed subscriber,
        uint32 indexed source,
        uint256 shortfall,
        uint256 received
    );

    /// @notice Emitted for an afking subscribe-time cover-buy box. Same signature/topic as the
    ///         mint + whale `LootBoxBuy` — one box-buy event across every path.
    event LootBoxBuy(
        uint32 indexed buyer,
        uint48 indexed index,
        uint32 position,
        uint256 amount
    );

    /// @notice Emitted once per subscriber per delivered afking day — the authoritative
    ///         afking-buy delivery signal (covers VAULT / sDGNRS and every real afker).
    ///         Carries the post-accrue accumulator balances so the in-slot accrual
    ///         (slot-0 reward + ticket buyer-bonus into `pendingFlip`, flat 7% into
    ///         `affiliateBase`, both saturating) is observable without a storage read.
    /// @dev The hottest log in the protocol — up to 250 per advance chunk — so its four
    ///      fields ride one word instead of four. Each was a full 32-byte slot for at most
    ///      32 bits of payload; packed they cost 256 gas instead of 1,024.
    ///      Packed layout (LSB -> MSB):
    ///      - [0..127]   weiIn: delivery ETH-in, fresh afking leg + claimable leg (cover-buy
    ///                   box reports 0; its spend rides LootBoxBuy). Bounded by ETH supply.
    ///      - [128..151] day: the delivered afking day (funded-day high-water covered)
    ///      - [152..175] pendingFlipAfter: claimable whole-FLIP balance after this accrue
    ///      - [176..207] affiliateBaseAfter: unclaimed whole-FLIP affiliate base after it
    ///      Widths are load-bearing: this word has no version field, so any change to a
    ///      field's size must rename the event rather than shift bits under a live decoder.
    ///      The claimable leg of `weiIn` is itemised by the ClaimableSpent emitted in the
    ///      same receipt, and only when the drain actually moves money.
    event AfkingDelivered(uint32 indexed player, uint256 packed);

    /// @notice Emitted when the affiliate claim drains a sub's accrued `affiliateBase`
    ///         to the upline tree — attributes afking-sourced affiliate income to the
    ///         subscriber whose buys generated it. Zero drains (already drained /
    ///         never accrued) do not emit.
    event AffiliateBaseDrained(uint32 indexed sub, uint256 base);

    /// @notice Emitted when a sub's accrued `pendingFlip` is settled (player-pull
    ///         claim or the finalize path) — the zeroing half of the balance
    ///         `AfkingDelivered.pendingFlipAfter` reports accruing.
    event AfkingFlipClaimed(uint32 indexed player, uint256 owed);

    /*------------------------------------------------------------------
                              Constants
    ------------------------------------------------------------------*/
    /// @dev Afking-local ticket scaling multiplier. AFKING_TICKET_SCALE = 400 makes the
    ///      cost formula unit-consistent: a ticket `amount = effectiveQty * 400`
    ///      entry-units, which the Game's mint recompute divides by `4 * 100`
    ///      (the inherited Storage `QTY_SCALE = 100`), so `cost` stays
    ///      `mintPrice * effectiveQty` in both ticket and lootbox mode.
    ///      ⚠ LOAD-BEARING dual constant: this 400 is
    ///      NUMERICALLY EQUAL to the Game's `4 * QTY_SCALE` (= 4 × 100) but is a
    ///      DISTINCT named constant — it must NOT be collapsed with the inherited
    ///      `QTY_SCALE` (100). They play different roles (entry-unit multiplier
    ///      vs the Game divisor base) that happen to compose to the same 400.
    uint256 internal constant AFKING_TICKET_SCALE = 400;

    /// @dev drainGameCreditFirst bit within Sub.flags — when set the buy spends
    ///      protocol-side claimable credit before tapping afkingFunding ETH.
    uint8 internal constant FLAG_DRAIN_FIRST = 2;

    /// @dev useTickets bit within Sub.flags — set = ticket mint mode, clear =
    ///      lootbox mode.
    uint8 internal constant FLAG_USE_TICKETS = 4;

    /// @dev externalFunding bit within Sub.flags — set when an external funding account (an ID
    ///      other than 0 and the subscriber's own) is registered in the sparse `_fundingSourceOf`
    ///      map. Lets the common self-funded path resolve the source to the subscriber's own set
    ///      element from the already-loaded flags byte and SKIP the per-sub
    ///      `_fundingSourceOf` SLOAD (the map is read only for the rare operator-funded sub).
    uint8 internal constant FLAG_EXTERNAL_FUNDING = 1;

    /// @dev Slot-0 quest completion reward — mirrors `DegenerusQuests.QUEST_SLOT0_REWARD`
    ///      (a private constant not visible cross-contract). Each delivered afking buy accrues
    ///      `QUEST_SLOT0_REWARD` (whole FLIP) into the sub's claimable `pendingFlip`, pulled
    ///      via `claimAfkingFlip`. Only values the FLIP mint, off the solvency path.
    uint256 internal constant QUEST_SLOT0_REWARD = 100;

    /// @dev Prize-pool routing splits for the batched afking buy, mirroring the canonical
    ///      `DegenerusGameMintModule.LOOTBOX_SPLIT_FUTURE_BPS` (9000) and
    ///      `DegenerusGame.PURCHASE_TO_FUTURE_BPS` (1000) — both private cross-contract. A
    ///      lootbox spend routes 90% future / 10% next; a ticket spend the inverse.
    uint256 internal constant AFKING_LOOTBOX_FUTURE_BPS = 9000;
    uint256 internal constant AFKING_TICKET_FUTURE_BPS = 1000;

    /*------------------------------------------------------------------
                          Subscription entrypoint
    ------------------------------------------------------------------*/
    event AfkingFundingApproval(uint32 indexed funderId, uint32 indexed subscriberId, bool approved);

    function setAfkingFundingApproval(uint32 funderId, uint32 subscriberId, bool approved) external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (funderId == 0) funderId = _requireWalletId(msg.sender);
        _requireAllocated(funderId);
        _requireAllocated(subscriberId);
        if (_isAcquired(funderId) || _isAcquired(subscriberId)) revert NotApproved();
        if (_payee(_walletElement(funderId)) != msg.sender) revert NotApproved();
        afkingFundingApprovals[funderId][subscriberId] = approved;
        emit AfkingFundingApproval(funderId, subscriberId, approved);
    }

    /// @notice The SINGLE subscription entrypoint — create, replace, or cancel a
    ///         daily subscription for account `id` (0 = caller). dailyQuantity >= 1 upserts
    ///         (create-or-replace in place); dailyQuantity == 0 cancels (writes the
    ///         tombstone sentinel, relocating no one). Every mutation flows
    ///         through this one consent-gated path.
    /// @dev rngLock guard: subscribe reverts during the RNG freeze window
    ///      (`rngLockedFlag`), for ALL of create / replace / cancel — the subscriber
    ///      set must be frozen across [request -> unlock] so the stamped set the open
    ///      consumes cannot shift mid-cycle. Callers wait for the unlock.
    /// @dev Authorization is checked ONCE here under the account rule (`_resolveAccount`:
    ///      the caller is the account's payee — its key or a smurf's owner — or an operator
    ///      approved for its ID). Authorization is NEVER re-checked at process-time.
    /// @dev Seats: a NEW run (no live run — never subscribed, cancelled or evicted) burns seat
    ///      `seatId` of the subscriber's payee through the token's Game-only `consumeSeat`,
    ///      before the run is written. Changing a live run and a cancel burn nothing; the
    ///      exempt VAULT / SDGNRS subscriptions (made in their own constructors, before the
    ///      token exists) never call the token. Every non-exempt set entry burned a seat and
    ///      the token caps live seats plus set entries, so the set needs no runtime cap. No
    ///      pass requirement and no per-level validity horizon.
    /// @dev msg.value > 0 credits the Game's afkingFunding ledger in-context
    ///      (claimablePool moved in tandem — the solvency invariant), keyed on the
    ///      resolved funding bucket (the external source for an externally funded sub, else
    ///      the subscriber).
    /// @dev Funding-source 4-protection:
    ///        (1) prepaid consent at subscribe — auth + funding-source gate checked here;
    ///        (2) default-self — `fundingSourceId` 0 or the subscriber's own ID self-funds from
    ///            the subscriber's ledger, no gate; its stETH top-up pulls from the subscriber's
    ///            payee;
    ///        (3) no-escalation — the source is fixed at subscribe, not changeable per-draw to escalate;
    ///        (4) later consent revocation does not stop prepaid draws; stETH pulls from an
    ///            external source's payee require the consent to remain live on every attempt
    ///            (a source sharing the subscriber's main wallet consents implicitly).
    /// @param id Subscriber account (0 = caller).
    /// @param drainGameCreditFirst When true, the buy spends claimable credit first.
    /// @param useTickets Mint mode — true = tickets, false = lootboxes.
    /// @param dailyQuantity Daily buy units, 1..255 (upsert); 0 cancels (tombstone).
    /// @param fundingSourceId Account whose `afkingFunding` funds this sub; 0 (or the
    ///        subscriber's own ID) = self. An external source must be allocated and must
    ///        consent: it shares the subscriber's main wallet (equal payees: an owner and its
    ///        smurfs, in any pairing) or its owner granted funding approval to the subscriber ID.
    /// @param seatId Seat serial burned when this call starts a new run (ignored otherwise).
    function subscribe(
        uint32 id,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint32 fundingSourceId,
        uint256 seatId
    ) external payable {
        // Block ALL subscribe (create / replace / cancel) during the
        // RNG freeze window: the subscriber set the stamp pass + open consume must
        // stay frozen across [request -> unlock]. Callers wait for the unlock.
        if (rngLockedFlag) revert RngLocked();

        // Closed from the liveness trigger onward, which subsumes post-gameOver: the
        // predicate stays true once death is declared (_unlockRng deliberately freezes
        // dailyIdx so the deadman never un-fires, and the phase flags it reads can no
        // longer be cleared). The subscribe path delivers its cover buy
        // in-transaction, which queues ticket entries, and the terminal drain spans
        // several transactions with gameOver still unlatched. The rngLock does not span
        // that whole window — the terminal sequence takes it only when the fallback word
        // commits, leaving the drain's earlier transactions unlocked — so liveness, not
        // the lock, is what keeps a subscribe from queueing entries into the terminal
        // cohort. Accrued value stays recoverable — afkingFunding
        // via claim, pendingFlip via claimAfkingFlip, affiliateBase via the affiliate
        // claim path.
        if (_livenessTriggered()) revert GameOver();

        // The account rule: the caller for id 0, else an account the caller may act for.
        uint32 subId = _resolveAccountId(id);
        if (dailyQuantity != 0) subId = _registerCallerAccount(subId, msg.value);
        if (_isAcquired(subId)) revert NotApproved();

        // An external funding source (an ID other than 0 and the subscriber's own) must be
        // allocated and must consent: the same main wallet as the subscriber (equal payees)
        // consents implicitly, any other source must have approved the subscriber's key as an
        // operator. Prepaid draws retain this consent; stETH pulls from the source's payee
        // re-check it live.
        uint32 fundId = subId;
        if (fundingSourceId != 0 && fundingSourceId != subId) {
            _requireAllocated(fundingSourceId);
            if (!_afkingFundingAllowed(subId, fundingSourceId)) revert NotApproved();
            fundId = fundingSourceId;
        }

        // msg.value > 0 credits the Game's afkingFunding ledger in-context (the Game
        // holds the ETH; claimablePool increases by the same amount). It credits the
        // SAME bucket the draws debit: the resolved funding source — the external
        // source for an externally funded sub (its consent was checked just above),
        // else the subscriber itself. So a deposit attached to subscribe always funds the
        // bucket that actually pays for this sub's auto-buys — never misdirected to an
        // unused bucket on an externally funded sub. Routed through _creditAfkingValue so the credit
        // emits AfkingFunded like every other money-in path; the ledger is otherwise
        // write-asymmetric here (debits log, credits do not) and off-chain consumers cannot
        // attribute a funded subscribe made through a contract wallet.
        if (msg.value > 0) {
            _creditAfkingValue(fundId, msg.value);
        }

        // Cancel branch — dailyQuantity == 0 writes the `dailyQuantity = 0` tombstone in
        // place and relocates no one (the in-pass reclaim swap-pops the tombstone when the
        // process stage reaches it). Revert if the caller has no active sub. Any msg.value
        // above was still credited to funding, so a cancel-with-ETH never strands the
        // deposit (it stays game-side withdrawable).
        if (dailyQuantity == 0) {
            Sub storage c = _subOf[subId];
            if (c.setPosition == 0) revert NotSubscribed();
            // Auto-claim BEFORE clearing: the next advance-driven reclaim deletes the
            // slot (wiping both accumulators), so leaving them for a later pull would
            // lose them in that race. Pay the sub its own pendingFlip (CEI: zero
            // first), then settle the upline affiliate tree, THEN finalize + tombstone.
            _settlePendingFlip(subId, c);
            // Drain affiliateBase to the 75/20/5 upline tree (50/50 VAULT/DGNRS if no
            // referrer). The affiliate consumes the base via the AFFILIATE-only
            // drainAffiliateBase callback, so this must run while the slot still holds it.
            uint32[] memory drainOne = new uint32[](1);
            drainOne[0] = subId;
            IDegenerusAffiliate(ContractAddresses.AFFILIATE).claim(drainOne);

            // Hand the afking-computed streak back to the manual quest system, then tombstone.
            // The run's seat was burned when it started; a later new run burns another.
            _finalizeAfking(subId, c, _simulatedDayIndex());
            c.dailyQuantity = 0;
            // The sparse `_fundingSourceOf` map holds an entry iff FLAG_EXTERNAL_FUNDING
            // is set (the upsert writes/clears both together), so the common self-funded
            // cancel emits address(0) straight from the already-loaded flags — no map read.
            emit SubscriptionUpdated(
                subId,
                0,
                (c.flags & FLAG_DRAIN_FIRST) != 0,
                (c.flags & FLAG_USE_TICKETS) != 0,
                (c.flags & FLAG_EXTERNAL_FUNDING) != 0
                    ? _fundingSourceOf[subId]
                    : 0
            );
            return;
        }

        // UPSERT branch (dailyQuantity >= 1) — create-or-replace in place. `_addToSet`
        // is idempotent (adds only when `setPosition == 0`), so a re-subscribe of
        // an active member replaces its fields without set churn.
        Sub storage s = _subOf[subId];

        // Captured BEFORE the dailyQuantity overwrite: a non-zero stored dailyQuantity means the
        // sub is mid-afking-run (afkingActive set) — a re-subscribe CONTINUES that run; 0 means
        // new / cancelled / evicted (afkingActive cleared by a prior finalize) — a fresh run.
        bool wasActive = s.dailyQuantity != 0;
        // The two protocol self-subscribers (VAULT / sDGNRS) self-subscribe at
        // construction with no funds and BEFORE the AFKing Subscription Token exists in the
        // deploy order (the token deploys last; its constructor mints both
        // permanent construction seats — serial 1 to SDGNRS, serial 2 to the
        // vault); they are exempt from the seat burn and the
        // purchase-grounded gate below, keyed on the un-spoofable resolved
        // subscriber identity. Every other sub must clear both.
        bool exemptSub = subId == VAULT_WALLET_ID || subId == SDGNRS_WALLET_ID;

        if (wasActive) {
            // Settle the prior run's pendingFlip under its CURRENT flag + dailyQuantity before
            // the overwrite below, so the presale-box credit keys on the state in force during
            // accrual.
            _settlePendingFlip(subId, s);
        } else if (!exemptSub) {
            // A new run burns one seat held by the subscriber's payee, before the run is
            // written. The token makes no callback into the Game.
            ISeatToken(ContractAddresses.AFKING_SUB_TOKEN).consumeSeat(_payee(_walletElement(subId)), seatId);
        }

        s.dailyQuantity = dailyQuantity;
        if (drainGameCreditFirst) s.flags |= FLAG_DRAIN_FIRST;
        else s.flags &= ~FLAG_DRAIN_FIRST;
        if (useTickets) s.flags |= FLAG_USE_TICKETS;
        else s.flags &= ~FLAG_USE_TICKETS;
        // Sparse funder map: store an external source (its key beside its wallet ID); a
        // self-funded subscribe clears it, so re-pointing an externally funded sub back to
        // self does not strand a stale funder. Re-pointing the source IS a re-subscribe,
        // which re-runs the consent gate.
        if (fundId != subId) {
            _fundingSourceOf[subId] = fundId;
            s.flags |= FLAG_EXTERNAL_FUNDING;
        } else {
            // A live self-funded run has already cleared this map at its start.
            // Fresh/restarted runs must still clear it: process removal deletes
            // the Sub (including its flag) but may leave an old sparse source.
            if (!wasActive || (s.flags & FLAG_EXTERNAL_FUNDING) != 0) {
                delete _fundingSourceOf[subId];
            }
            s.flags &= ~FLAG_EXTERNAL_FUNDING;
        }
        // The cover-buys below draw on the source just recorded (`srcWord`, the subscriber's
        // own word when self-funded), so they need no map read.

        // Afking-run start (new sub) OR a streak-refreshing cover-buy (active sub re-subscribe).
        {
            uint24 today = _simulatedDayIndex();
            if (wasActive) {
                // ACTIVE sub re-subscribe — subscribe doubles as a manual "keep my streak alive +
                // buy something" action. Do a funded cover-buy for TODAY (advancing the funded
                // high-water afkCoveredThroughDay), which CONTINUES the run's streak via
                // _deliverAfkingBuy's own gap-freeze/accrue: a still-current run keeps its streak
                // and gains today; a gapped run keeps its streak too (gap days earn nothing, same
                // as the stage). No re-snapshot / no forfeit — the afking streak is never reset by
                // a re-subscribe. Skipped (streak just persists + decays on read) when already
                // bought today OR a pending unopened box exists (re-stamping would orphan it — the
                // no-orphan rule) OR the cover-buy is unfunded.
                if (
                    s.lastAutoBoughtDay != uint24(today) &&
                    s.lastOpenedDay >= s.lastAutoBoughtDay
                ) {
                    uint256 mp = _mintPriceInContext();
                    uint256 srcFunding = _afkingOf(fundId);
                    (
                        uint256 ethValue,
                        uint256 buyAmount,
                        bool isTicket,
                        uint256 claimableUse
                    ) = _resolveBuy(
                            s,
                            subId,
                            mp,
                            _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0,
                            srcFunding
                        );
                    srcFunding = _tryFundAfkingSteth(subId, fundId, ethValue, srcFunding);
                    if (srcFunding >= ethValue) {
                        _deliverAfkingBuy(
                            subId,
                            s,
                            today,
                            mp,
                            level,
                            jackpotPhaseFlag ? level : level + 1,
                            fundId,
                            ethValue,
                            claimableUse,
                            buyAmount,
                            isTicket,
                            true
                        );
                    }
                }
            } else {
                // NEW run. Snapshot the player's (gap-synced) manual quest streak and flip the
                // afking flag (slot-0 completions become streak-neutral / reward-deferred — the
                // Game-side compute-on-read owns the streak until finalize hands it back). The run
                // is grounded on a FUNDED day-0 (a funded min-buy OR an already-complete manual
                // slot-0 today) — the debit-gate that makes the streak unfarmable. An unfunded
                // start reverts (MustPurchaseToBeginAfking); only VAULT / SDGNRS, which
                // self-subscribe with no funds at construction, forfeit the snapshot (base 0)
                // instead.
                uint256 snap = quests.beginAfking(subId, today); // syncs + sets afkingActive
                // Frame the run on today (the compute-on-read base; afkCovered == today keeps the
                // day-0 delivery gap-free and guarantees
                // afkCovered >= afkingStartDay so the streak span never underflows).
                s.afkCoveredThroughDay = uint24(today);
                s.afkingStartDay = uint24(today);

                (bool done0, ) = IQuestCompletionView(address(quests)).questCompletionToday(subId);
                if (s.lastOpenedDay < s.lastAutoBoughtDay) {
                    // A pending unopened box (this or a prior day) already grounds the run on a real
                    // purchase. Keep the snapshot and leave the box markers untouched so the open leg
                    // still materializes it — re-stamping here would orphan the prepaid box.
                    _setStreakBase(s, snap);
                } else if (done0) {
                    _setStreakBase(s, snap); // funded (manual) day-0 — keep the snapshot
                    s.lastAutoBoughtDay = uint24(today);
                    s.lastOpenedDay = uint24(today); // no pending box
                } else if (s.lastAutoBoughtDay == uint24(today)) {
                    // Already bought today in a prior subscribe cycle this day — the cancel
                    // tombstone retained the stamp across the unsub/re-subscribe. The run is
                    // already purchase-grounded, so keep the snapshot and skip a second
                    // cover-buy: the per-day flat slot-0 reward is not re-accrued, and
                    // lastOpenedDay is left untouched so a pending box is not orphaned. This
                    // mirrors the active-sub re-subscribe guard above.
                    _setStreakBase(s, snap);
                } else {
                    uint256 mp = _mintPriceInContext();
                    uint256 srcFunding = _afkingOf(fundId);
                    (
                        uint256 ethValue,
                        uint256 buyAmount,
                        bool isTicket,
                        uint256 claimableUse
                    ) = _resolveBuy(
                            s,
                            subId,
                            mp,
                            _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0,
                            srcFunding
                        );
                    srcFunding = _tryFundAfkingSteth(subId, fundId, ethValue, srcFunding);
                    if (srcFunding >= ethValue) {
                        _setStreakBase(s, snap); // funded day-0 — keep the snapshot
                        _deliverAfkingBuy(
                            subId,
                            s,
                            today,
                            mp,
                            level,
                            jackpotPhaseFlag ? level : level + 1,
                            fundId,
                            ethValue,
                            claimableUse,
                            buyAmount,
                            isTicket,
                            true
                        );
                    } else if (exemptSub) {
                        // VAULT / sDGNRS bootstrap: unfunded at construction — forfeit the
                        // snapshot and start the run from base 0 without reverting.
                        _setStreakBase(s, 0);
                    } else {
                        // A NEW run must be grounded on a real purchase: already bought
                        // today (the done0 branch above) or a funded in-tx cover-buy (the
                        // branch above). An unfunded start would free-ride the advance gate.
                        revert MustPurchaseToBeginAfking();
                    }
                }
            }
        }

        _addToSet(s, subId);
        emit SubscriptionUpdated(
            subId,
            dailyQuantity,
            drainGameCreditFirst,
            useTickets,
            fundId == subId ? 0 : fundId
        );
    }

    /// @dev Keep the original claimable/prepaid split: top up its residual only,
    ///      without resolving the purchase again against the new prepaid balance.
    ///      A refused token top-up uses the ordinary insufficient-funding policy.
    ///      Empty/OOG and known metering failures still propagate, so caller starvation
    ///      cannot expire a funded subscription.
    /// @param subscriber The sub's set element: its key (bits 0..159) and wallet ID (160..191).
    /// @param funding The funding account in the same layout; equal to `subscriber` when
    ///        self-funded.
    function _tryFundAfkingSteth(
        uint32 subscriber,
        uint32 funding,
        uint256 ethValue,
        uint256 srcFunding
    ) private returns (uint256) {
        if (srcFunding >= ethValue) return srcFunding;
        (address source, bool allowed) = _stethSource(subscriber, funding);
        if (!allowed) return srcFunding;
        try IDegenerusGame(address(this)).pullAfkingSteth(
            subscriber, source, ethValue - srcFunding
        ) returns (uint256 received) {
            return srcFunding + received;
        } catch (bytes memory reason) {
            MineFlipGas.rethrowGasFailure(reason);
            return srcFunding;
        }
    }

    /// @dev The address a sub's stETH top-up is pulled from — the funding account's payee (the
    ///      owner for a smurf account) — and whether the pull may run. Protocol custody is not a
    ///      wallet funding allowance: sDGNRS preapproves GAME for redemptions whose stETH backing
    ///      must remain segregated, so neither protocol sink is ever pulled. An external source
    ///      must still consent live: the same main wallet as the subscriber (equal payees), or
    ///      an operator approval of the subscriber's key. A self-funded sub reads only its own
    ///      element; the subscriber's payee is read only for an external source that is not
    ///      the subscriber's own key. Never reverts.
    /// @param subscriber The sub's set element (key | ID << 160).
    /// @param funding The funding account's element in the same layout.
    function _stethSource(uint32 subscriber, uint32 funding)
        private view returns (address source, bool allowed)
    {
        source = _payee(_walletElement(funding));
        allowed = source != ContractAddresses.SDGNRS && source != ContractAddresses.VAULT
            && _afkingFundingAllowed(subscriber, funding);
    }

    /// @notice Atomic stETH funding operation, callable only by GAME itself.
    /// @dev Dependency failures and invalid receipts roll back the entire attempt.
    ///      Zero is returned only after successful reads prove missing consent/funds.
    /// @param subId The subscriber account ID.
    /// @param source The funding account's payee, where the stETH comes from.
    function pullAfkingSteth(uint32 subId, address source, uint256 shortfall)
        external returns (uint256 received)
    {
        if (address(this) != ContractAddresses.GAME || msg.sender != address(this)) revert E();
        // Recheck the subscriber's current funder ID and consent before pulling from its payee.
        Sub storage sub = _subOf[subId];
        uint32 sourceId = (sub.flags & FLAG_EXTERNAL_FUNDING) != 0
            ? _fundingSourceOf[subId]
            : subId;
        (address expected, bool allowed) = _stethSource(subId, sourceId);
        if (shortfall == 0 || sub.dailyQuantity == 0 || !allowed || source != expected) {
            revert AfkingStethPullFailed();
        }

        IStETH token = IStETH(ContractAddresses.STETH_TOKEN);
        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 shares = token.getSharesByPooledEth(shortfall);
        // Lido floors both conversions; include the one rounding share if needed.
        if (token.getPooledEthByShares(shares) < shortfall) ++shares;
        uint256 quote = token.getPooledEthByShares(shares);
        if (token.sharesOf(source) < shares || token.allowance(source, address(this)) < quote) return 0;
        uint256 transferred = token.transferSharesFrom(source, address(this), shares);
        uint256 afterBalance = token.balanceOf(address(this));
        if (afterBalance < balanceBefore) revert AfkingStethPullFailed();
        received = afterBalance - balanceBefore;

        // The recipient's pre-existing fractional share value can contribute
        // one extra wei to its balance delta. Subtraction avoids return+1 overflow.
        if (
            transferred < shortfall || received < transferred || received - transferred > 1
        ) revert AfkingStethPullFailed();

        if (
            received > type(uint128).max - _afkingOf(sourceId) ||
            received > type(uint128).max - claimablePool
        ) revert AfkingStethPullFailed();

        _creditAfkingValue(sourceId, received);
        emit AfkingStethFunded(subId, sourceId, shortfall, received);
    }

    /*------------------------------------------------------------------
                          Iterable set (hand-inlined OZ EnumerableSet)
    ------------------------------------------------------------------*/
    /// @dev Iterable set insert. Idempotent on already-in-set. Pushes the subscriber ID
    ///      and records its 1-indexed position
    ///      in the subscriber's `Sub.setPosition` (0 = not in set). The set is bounded without a
    ///      runtime cap: every non-exempt entry burned a seat, and the seat token caps live
    ///      seats plus set entries at 2,000.
    /// @param s The subscriber's record (`_subOf[id]`).
    /// @param id The subscriber's wallet ID.
    function _addToSet(Sub storage s, uint32 id) internal {
        if (s.setPosition == 0) {
            uint256 len = _subscribers.length;
            _subscribers.push(id);
            s.setPosition = uint32(len + 1);
        }
    }

    /// @dev Iterable set remove via swap-and-pop of the element at 1-indexed `position`
    ///      (the process pass's cursor + 1, known without reading the removed record, which
    ///      the caller deletes — its `setPosition` with the rest of it). Moves the last
    ///      element word into the vacated slot, rewrites the mover's `setPosition` to the
    ///      vacated position, and pops the tail. The process pass's "no cursor-advance
    ///      after swap-pop" pattern enforces iteration safety; this helper is itself
    ///      iteration-safe (membership ⟺ `setPosition != 0` preserved).
    function _removeFromSet(uint256 position) internal {
        uint256 last = _subscribers.length;
        if (position != last) {
            uint32 mover = _subscribers[last - 1];
            _subscribers[position - 1] = mover;
            _subOf[mover].setPosition = uint32(position); // mover takes the vacated slot
        }
        _subscribers.pop();
    }

    /*------------------------------------------------------------------
                  The _resolveBuy slice builder
    ------------------------------------------------------------------*/
    /// @dev Per-player funding resolution for the process pass — effective
    ///      quantity → cost → purchase mode + funding split, carrying the slice-builder
    ///      validation invariants that make a funded buy revert-free BY CONSTRUCTION (the
    ///      SOLE no-brick guarantor under the no-valve model). The five
    ///      obligation-1 invariants:
    ///        (1) effectiveQty = dailyQuantity ≥ 1 (the subscribe-time floor) → never the
    ///            Game's totalCost==0 / dust / TICKET_MIN reverts;
    ///        (2) cost = mintPrice * effectiveQty → the exact cost the Game recomputes;
    ///        (3) cost ≥ mintPrice ≥ 0.01 ETH (the priceForLevel floor) → a lootbox amount
    ///            always meets any min-spend floor; no skip/decline needed;
    ///        (4) 1-wei claimable sentinel → leaves claimable > cost / basis > shortfall →
    ///            never the Game's Claimable (claimable<=amount) nor the settle revert;
    ///        (5) ethValue = cost - claimableUse with claimableUse ∈ [0, cost] → never the
    ///            Game's downstream cost reverts.
    ///      ⚠ Dual scale (LOAD-BEARING): the ticket entry-unit `amount`
    ///      uses `AFKING_TICKET_SCALE = 400`; the Game's `/ (4 * 100)` recompute uses the
    ///      inherited Storage `QTY_SCALE = 100` — the two constants are NOT collapsed,
    ///      so `cost` stays `mintPrice * effectiveQty`.
    ///      ⚠ NO error-swallowing valve: a funded slice is revert-free
    ///      by construction, with no pre-emptive decline and no reactive error-trap; there
    ///      is no per-cycle eviction cap.
    ///      In-context: `claimable` is the subscriber's swept-gated raw claimable balance by
    ///      wallet ID (== afkingSnapshot's claimable / claimableWinningsOf, incl. the 1-wei
    ///      sentinel), read as an in-context SLOAD; `srcFunding` is the caller-resolved
    ///      afkingFunding of the source (the funder — self or operator-approved source). The
    ///      GO_SWEPT gate arrives as the caller-read `swept` flag (written only by the one-time
    ///      game-over sweep, so it is invariant within a tx — the STAGE reads it once per
    ///      chunk, the subscribe cover-buys inline at the call). View — no state writes.
    /// @return ethValue Fresh-ETH portion debited from the funder's afkingFunding (0 = pure claimable).
    /// @return amount Ticket entry-units (isTicket) or lootbox spend in wei (!isTicket).
    /// @return isTicket True = buy `amount` ticket entry-units; false = buy an `amount`-wei lootbox.
    /// @return claimableUse Claimable portion of `cost` (drainFirst / funding-shortfall); cost == ethValue + claimableUse.
    function _resolveBuy(
        Sub storage sub,
        uint32 id,
        uint256 mp,
        bool swept,
        uint256 srcFunding
    )
        internal
        view
        returns (
            uint256 ethValue,
            uint256 amount,
            bool isTicket,
            uint256 claimableUse
        )
    {
        bool drainFirst = (sub.flags & FLAG_DRAIN_FIRST) != 0;
        // The player's claimable — the claimable leg of the funding split. Swept-gated to
        // mirror afkingSnapshot / claimableWinningsOf exactly. The fresh-ETH leg draws from
        // the caller-resolved `srcFunding` (afkingFunding[src], self or operator).
        uint256 claimable = swept ? 0 : _claimableOf(id);

        // Box size is the FROZEN dailyQuantity (set at subscribe, which reverts under
        // rngLockedFlag). It is never scaled by live claimable, so the box amount — and the
        // seed derived from it — cannot be steered after the day's word is knowable.
        uint256 effectiveQty = sub.dailyQuantity;
        uint256 cost = mp * effectiveQty;

        // Mode routing. Ticket mode buys `effectiveQty` whole tickets (entry-units =
        // effectiveQty * AFKING_TICKET_SCALE [= 400]); lootbox mode buys a `cost`-wei box.
        isTicket = (sub.flags & FLAG_USE_TICKETS) != 0;
        amount = isTicket ? effectiveQty * AFKING_TICKET_SCALE : cost;

        // Funding split (USER model). Never spend the entire claimable balance — leave >= 1
        // wei (the Game's Claimable branch needs claimable strictly > cost, and the claimable
        // shortfall settle needs basis > shortfall), so the claimable leg caps at
        // `spendableClaimable`. drainGameCreditFirst spends claimable first (up to cost);
        // otherwise afkingFunding funds first and claimable covers only the remainder. Both
        // legs are tapped when one alone is short.
        uint256 spendableClaimable = claimable > 0 ? claimable - 1 : 0;
        if (drainFirst) {
            claimableUse = spendableClaimable < cost ? spendableClaimable : cost;
        } else {
            uint256 fundingUse = srcFunding < cost ? srcFunding : cost;
            uint256 need = cost - fundingUse;
            claimableUse = need < spendableClaimable ? need : spendableClaimable;
        }
        ethValue = cost - claimableUse;
    }

    /*------------------------------------------------------------------
              Shared per-sub funded delivery + compute-on-read streak
    ------------------------------------------------------------------*/
    /// @dev The shared per-sub funded delivery — used by both the process STAGE (after its
    ///      pre-buy gates, `coverBuy == false`) and the subscribe-time grounding cover-buy
    ///      (`coverBuy == true`). The slice is already confirmed funded by the caller
    ///      (`afkingFunding[src] >= ethValue`), so this is revert-free by construction (no
    ///      try/catch). Debits the fresh-ETH leg + the claimable leg (claimablePool in
    ///      tandem, fail-loud on underflow — a debit can never exceed afkingFunding[src] ≤ the
    ///      claimablePool reservation, so a revert here means solvency is already violated and
    ///      must propagate), materializes the buy per mode, accrues the day's affiliate base + the
    ///      slot-0 pendingFlip reward, advances the compute-on-read streak markers (gap days
    ///      earn nothing; the streak freezes across them, never resets), and sets the
    ///      success marker. The frozen activity score reads the COMPUTE-ON-READ streak off the Sub
    ///      slot — no DegenerusQuests STATICCALL on the hot path. boons OFF ⇒ amount == spend.
    ///
    ///      Lootbox materialization differs by mode: the daily STAGE writes a gas-light warm
    ///      Sub-stamp box (the EV-cap RMW deferred to OPEN), whereas the cover-buy writes a full
    ///      INDEXED box resolved off its sealed cohort's live word — a future word never knowable at
    ///      subscribe — so a player-timed subscribe cannot select a pre-revealed seed (a
    ///      `rngWordByDay`-keyed Sub-stamp box would break the RNG-freeze invariant here, since
    ///      subscribe runs after the day's word is public). Pool routing also differs: the STAGE
    ///      accrues the cost into the caller's batched per-chunk credit; the cover-buy (a single
    ///      buy) routes inline here.
    /// @param element The subscriber ID receiving the delivery.
    /// @param sub The subscriber's record (storage ref — stamped/accrued here).
    /// @param processDay The delivered day (the stamp's frozen seed day + the streak marker).
    /// @param mp The in-context mint price.
    /// @param currentLevel The hoisted level (the buy's target-level base).
    /// @param ticketTargetLevel The resolved ticket mint target (jackpot phase ⇒
    ///        currentLevel, else currentLevel + 1) — read once by the caller, since
    ///        jackpotPhaseFlag is fixed across a pre-RNG stage chunk. Ticket mode only.
    /// @param srcId Wallet ID of the funding bucket the fresh-ETH leg debits.
    /// @param ethValue The fresh-ETH portion (0 = pure claimable).
    /// @param claimableUse The drainFirst/funding-shortfall claimable portion of the cost.
    /// @param amount Ticket entry-units (ticket mode) or lootbox spend in wei (lootbox mode).
    /// @param isTicket Mode — true = queue tickets, false = a lootbox box.
    /// @param coverBuy True = subscribe-time grounding buy (indexed box + inline pool routing);
    ///        false = daily STAGE buy (Sub-stamp box + caller-batched pool routing).
    function _deliverAfkingBuy(
        uint32 element,
        Sub storage sub,
        uint24 processDay,
        uint256 mp,
        uint24 currentLevel,
        uint24 ticketTargetLevel,
        uint32 srcId,
        uint256 ethValue,
        uint256 claimableUse,
        uint256 amount,
        bool isTicket,
        bool coverBuy
    ) private {
        if (ethValue != 0) {
            _debitAfking(srcId, ethValue);
        }
        // Reinvest/drainFirst claimable portion of the cost. The _resolveBuy 1-wei sentinel
        // guarantees claimableUse <= claimable - 1, so this never underflows. claimableWinnings
        // rides in claimablePool, so the pool moves in tandem (the solvency invariant).
        if (claimableUse != 0) {
            uint32 id = element;
            _debitClaimable(id, claimableUse);
            // The drain is the one claimable debit with no event of its own, which forces a
            // reader to carry the balance forward from every prior credit. ClaimableSpent
            // already has the shape for it, post-state included, and the slot is warm from
            // the debit above — so the delta and its checkpoint both land here, on the only
            // deliveries that move claimable. `weiIn` on AfkingDelivered still reports the
            // full cost including this leg; the two are the same money seen twice, not two
            // draws (`costWei` below carries that full cost, so the pairing is explicit).
            emit ClaimableSpent(
                id,
                claimableUse,
                _claimableOf(id),
                MintPaymentKind.Internal,
                ethValue + claimableUse
            );
        }
        // Both legs draw the solvency-tracked claimablePool (afking-funded ETH and claimableWinnings
        // both ride in it); apply the combined debit as one checked RMW after the per-account writes
        // above. The merged uint128 underflow guard reverts on the same condition as the two separate
        // subtractions, and the whole call is atomic.
        if (ethValue != 0 || claimableUse != 0) {
            claimablePool -= uint128(ethValue + claimableUse);
        }

        // Reframe the run before freezing any lootbox activity score. The returned value is the
        // streak earned strictly before this delivery: gap days neither erase it nor
        // inflate the funded-day span.
        uint32 preBuyStreak = _advanceAfkingStreak(sub, processDay);

        if (isTicket) {
            // Ticket minimal-write primitive: queue resolution-equivalent ticket entries and
            // accrue the ticket buyer-bonus into the warm Sub slot. The affiliate flat-7% and the
            // slot-0 reward are added by the mode-agnostic accrue below (not re-accrued here).
            uint24 targetLevel = ticketTargetLevel;

            // The x00 century quantity bonus is a manual-mint mechanic; afking
            // deliveries queue the paid quantity as-is.
            _queueEntriesScaled(element, targetLevel, uint32(amount));

            // 10%/15% ticket buyer-bonus → claimable pendingFlip (pulled via
            // claimAfkingFlip). Uses the pre-bonus `amount`; whole FLIP with the ~16.7M (2^24-1) clamp.
            uint256 coinCost = (amount * (PRICE_COIN_UNIT / 4)) / QTY_SCALE;
            uint256 bonusBase = coinCost / 10; // flat 10%
            if (amount >= 10 * 4 * QTY_SCALE) {
                bonusBase += (amount * PRICE_COIN_UNIT) / (80 * QTY_SCALE); // +5% → 15% on ≥10 tickets
            }
            uint256 bonusWhole = bonusBase;
            if (bonusWhole != 0) {
                uint256 newOwed = uint256(sub.pendingFlip) + bonusWhole;
                if (newOwed > type(uint24).max) newOwed = type(uint24).max;
                sub.pendingFlip = uint24(newOwed);
            }

            // No pending box: keep lastOpenedDay == lastAutoBoughtDay so the no-orphan guard and
            // the open leg's `lastOpenedDay < lastAutoBoughtDay` gate never treat a ticket sub as
            // box-pending.
            sub.lastOpenedDay = uint24(processDay);
        } else {
            // Lootbox box. The per-buy manual side-effects (handlePurchase, affiliate ×2, the
            // per-buy creditFlip) are deferred to the in-slot accrue (affiliate pulled via
            // drainAffiliateBase; the slot-0 reward into pendingFlip). The frozen score
            // (the EV input at open, off the compute-on-read streak — no STATICCALL) is computed
            // once for either box shape.
            uint256 activityScore = _playerActivityScoreCachedAt(
                element,
                preBuyStreak,
                // Streak basis is the phase-correct active ticket level (== the level the manual mint
                // streak is recorded against), NOT the EV-cap/resolver open level (currentLevel + 1):
                // in jackpot phase those differ, and currentLevel + 1 would silently zero a streak
                // whose lastCompleted == level - 1.
                ticketTargetLevel,
                // currentLevel == storage `level` here (sole writer advanceGame, no in-window
                // advance), so pass it directly and skip the 3-arg wrapper's redundant `level` SLOAD.
                currentLevel
            );
            uint16 score = activityScore > type(uint16).max
                ? type(uint16).max
                : uint16(activityScore);
            if (coverBuy) {
                // Subscribe-time grounding box: a full INDEXED box on the live lootbox index,
                // resolved off its sealed cohort's live word (a future word). Rides the auto-open queue,
                // so the markers go box-clean (lastOpenedDay == lastAutoBoughtDay) and the
                // no-orphan guard never trips on a freshly-subscribed sub.
                _recordAfkingCoverBox(
                    element,
                    currentLevel,
                    amount,
                    score
                );
                sub.lastOpenedDay = uint24(processDay);
            } else {
                // Daily STAGE Sub-stamp box: the warm Sub slot IS the box record (no cold
                // ledger); the EV-cap RMW is deferred to OPEN, fed this frozen score, and
                // the level + EV-cap key read LIVE at open. milli-ETH stamp (the EV/seed input
                // only — the ETH debit used the full wei ethValue).
                // The stamp below leaves lastOpenedDay behind lastAutoBoughtDay — the ONLY
                // pending-box-creating shape (ticket buys and cover-buys mark themselves
                // box-clean above). `_pendingBoxCount` is maintained by the STAGE loop, the
                // only caller that reaches this branch: it batches one add per chunk off its
                // box-accrual count, atomic with this stamp (same tx, revert-together).
                sub.score = score;
                sub.amount = uint24(_packEthToMilliEth(amount));
            }
        }

        // Mode-agnostic accrue — one warm in-slot write, zero cross-contract calls:
        //   • affiliate base: flat 7% of the full wei spend (ethValue + claimableUse = the cost in
        //     both modes; the dual-unit `amount` is entry-units in ticket mode), whole FLIP, 100M clamp;
        //   • slot-0 quest reward: QUEST_SLOT0_REWARD (whole FLIP) into the claimable pendingFlip, ~16.7M (2^24-1) clamp;
        // The compute-on-read streak markers were advanced before materialization so the frozen
        // lootbox score observes the same real-miss decision as the persisted run framing.
        {
            uint256 base = ((_ethToFlip(ethValue + claimableUse, mp) * 7) / 100);
            if (base != 0) {
                uint256 newBase = uint256(sub.affiliateBase) + base;
                if (newBase > 100_000_000) newBase = 100_000_000;
                sub.affiliateBase = uint32(newBase);
            }
            {
                uint256 newOwed = uint256(sub.pendingFlip) +
                    (QUEST_SLOT0_REWARD);
                if (newOwed > type(uint24).max) newOwed = type(uint24).max;
                sub.pendingFlip = uint24(newOwed);
            }
        }

        sub.lastAutoBoughtDay = uint24(processDay);

        // The cover-buy is a single buy (not part of a STAGE chunk), so it credits the prize
        // pools inline here — a box spend funds the box pool, a ticket spend the ticket pool. The
        // STAGE path instead defers this to the caller's batched per-chunk `_routeAfkingPoolEth`.
        if (coverBuy) {
            uint256 cost = ethValue + claimableUse;
            if (isTicket) _routeAfkingPoolEth(0, cost);
            else _routeAfkingPoolEth(cost, 0);
        }
        // weiIn = afking auto-buy ETH-in (the fresh-ETH leg + the claimable leg), folded into
        // AfkingDelivered so the delivery marker doubles as the ETH-in record with no extra log.
        // The cover-buy box reports weiIn 0 — its spend is carried by LootBoxBuy — keeping the
        // off-chain ETH-in total free of double counting.
        uint256 weiIn = (isTicket || !coverBuy) ? ethValue + claimableUse : 0;
        emit AfkingDelivered(
            element,
            uint128(weiIn) |
                (uint256(processDay) << 128) |
                (uint256(sub.pendingFlip) << 152) |
                (uint256(sub.affiliateBase) << 176)
        );
    }

    /// @dev Returns the pre-delivery streak and advances the run through `processDay`.
    ///      Gap days (unadvanced days or protocol-side skips — a live funded sub is never
    ///      the cause of its own gap, since underfunding kills the sub the same day) shift
    ///      the base day forward so they add no earned span; the streak freezes across a
    ///      gap and never resets while the sub is live.
    function _advanceAfkingStreak(
        Sub storage sub,
        uint24 processDay
    ) private returns (uint32 preBuyStreak) {
        uint24 covered = sub.afkCoveredThroughDay;
        preBuyStreak = uint32(_streakBaseOf(sub)) +
            uint32(covered - sub.afkingStartDay);
        // The run frame only moves forward. A day-0 cover-buy delivers with covered already
        // framed to processDay, and an exempt VAULT/sDGNRS run re-framed unfunded on a later
        // day can still receive the lagging pinned pass of an earlier day; neither advances
        // it, so covered never drops below afkingStartDay. The shifted afkingStartDay lands
        // at most at processDay - 1, never above the new covered day.
        if (processDay > covered) {
            if (uint32(processDay) > uint32(covered) + 1) {
                sub.afkingStartDay += processDay - covered - 1;
            }
            sub.afkCoveredThroughDay = processDay;
        }
    }

    /// @dev Append a subscribe-time grounding lootbox as its own cover entry in the live write
    ///      buffer, mirroring the manual `_recordLootboxEntry` minus the boons-off legs (no boost,
    ///      no distress tally, no mint-day record). The entry opens on that buffer's word, requested
    ///      only after the append, and rolls from the LIVE open level. The append draws this box's
    ///      EV fraction from the shared per-(wallet, level) accumulator (`add = min(spend, CAP -
    ///      used)`) and freezes it with the score into the entry. The EV-cap key is
    ///      `currentLevel + 1` (== the resolver's open level = level + 1).
    /// @param player The box recipient.
    /// @param currentLevel The live game level (== the STAGE's hoisted currentLevel).
    /// @param amount The lootbox spend in wei (boons off ⇒ no boost; amount == spend).
    /// @param score The frozen activity score EV input.
    function _recordAfkingCoverBox(
        uint32 player,
        uint24 currentLevel,
        uint256 amount,
        uint16 score
    ) private {
        // The cover box is appended by the Lootbox module — one place owns the entry word
        // encoding. Boons stay OFF for afking covers, so no boost is consumed here.
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameLootboxModule.recordCoverBox.selector,
                player,
                amount,
                score,
                currentLevel + 1,
                false,
                0
            )
        );
        if (!ok) {
            if (data.length == 0) revert EmptyRevert();
            assembly ("memory-safe") {
                revert(add(32, data), mload(data))
            }
        }
    }

    /// @dev Hand the afking-computed streak back to the manual quest system on a sub-ending path,
    ///      BEFORE the Sub slot is deleted. Computes the run's earned streak (snapshot + funded
    ///      delivered days) and anchors the handback at `currentDay - 1` (floored at the funded
    ///      high-water): any covered-day lag on a live sub is protocol-caused (an unopened-box
    ///      skip or an unadvanced day — underfunding kills the sub on its first short day), so
    ///      the run's streak hands back intact and the manual decay owns it from `currentDay`
    ///      forward. `quests.finalizeAfking` also folds in any manual completion day and is
    ///      idempotent (a no-op if the player is not currently afking). Clears the
    ///      Sub's afking framing. The cross-contract read+write is the heavier (EVICT_WEIGHT)
    ///      STAGE branch.
    /// @param id The wallet ID of the subscriber whose run is ending.
    /// @param sub The subscriber's record (storage ref — afking framing cleared here).
    /// @param currentDay The current day (the decay reference passed to DegenerusQuests).
    function _finalizeAfking(
        uint32 id,
        Sub storage sub,
        uint24 currentDay
    ) private {
        uint24 covered = sub.afkCoveredThroughDay;
        uint256 earned = uint256(_streakBaseOf(sub)) +
            (covered - sub.afkingStartDay);
        uint24 anchor = covered;
        if (currentDay != 0 && currentDay - 1 > anchor) anchor = currentDay - 1;
        quests.finalizeAfking(
            id,
            earned > type(uint24).max ? type(uint24).max : uint24(earned),
            anchor,
            currentDay
        );
        sub.afkingStartDay = 0;
        _setStreakBase(sub, 0);
    }

    function _cancelAcquiredSubscription(uint32 id) private {
        Sub storage sub = _subOf[id];
        if (sub.setPosition == 0 || sub.dailyQuantity == 0) return;
        // Same forfeiture as an expired run: claim pending accrual before liquidation.
        _finalizeAfking(id, sub, _simulatedDayIndex());
        // Leave its paid box stamp reachable by the ordinary open worker.
        sub.dailyQuantity = 0;
        emit SubscriptionUpdated(id, 0, (sub.flags & FLAG_DRAIN_FIRST) != 0,
            (sub.flags & FLAG_USE_TICKETS) != 0,
            (sub.flags & FLAG_EXTERNAL_FUNDING) != 0 ? _fundingSourceOf[id] : 0);
    }

    /// @dev Settle a sub's accrued `pendingFlip` (the per-delivered-day slot-0 quest
    ///      reward + the ticket buyer-bonus): zero it FIRST (CEI — before the external
    ///      credit, so a re-entrant claim finds 0), grant the presale-box credit while
    ///      presale is open (the slot-0 FLIP owed approximates the afking mint spend;
    ///      25% of that spend is the manual buyer's presale-box credit; a ticket sub's
    ///      owed also carries the quantity-scaling buyer-bonus on top of the flat slot-0,
    ///      overstating the mint spend — divide the ticket grant back toward it: /3 for
    ///      heavy buyers (dailyQuantity >= 10, where the bonus rises to 15%), else /2),
    ///      then pay the whole-FLIP owed in ONE `creditFlip`. Always credits the sub,
    ///      never the caller; no-op at owed == 0. Keyed on the record's CURRENT flags +
    ///      dailyQuantity, so the credit reflects the state in force during accrual.
    /// @param id The subscriber's wallet ID (keys the presale-box credit).
    /// @param s The subscriber's record (storage ref — pendingFlip zeroed here).
    function _settlePendingFlip(uint32 id, Sub storage s) private {
        uint256 owed = uint256(s.pendingFlip); // whole FLIP
        if (owed == 0) return;
        s.pendingFlip = 0;
        if (!presaleOver) {
            uint256 credit = (owed * 0.0025 ether) / 100;
            if ((s.flags & FLAG_USE_TICKETS) != 0)
                credit /= (s.dailyQuantity >= 10 ? 3 : 2);
            presaleBoxCredit[id] += credit;
        }
        emit AfkingFlipClaimed(id, owed);
        coinflip.creditFlip(id, owed); // whole → base units
    }

    /*------------------------------------------------------------------
              The REQUIRED-PATH process STAGE (stamp + debit)
    ------------------------------------------------------------------*/
    /// @notice The chunked pre-RNG stamp/buy pass the AdvanceModule STAGE drives across
    ///         the subscriber set, immediately before `rngGate` on the new-day path
    ///         (the required path; the AdvanceModule owns the insertion). A
    ///         NO-ORPHAN guard runs FIRST per sub: a sub with a pending unopened box
    ///         (`lastOpenedDay < lastAutoBoughtDay`) is left ENTIRELY untouched this cycle
    ///         (no reclaim / evict / funding-kill / re-stamp), so its paid-for box is never
    ///         orphaned. For each funded, well-formed sub it then builds the `_resolveBuy`
    ///         slice and, per mode: a LOOTBOX sub STAMPS the two
    ///         genuinely-per-sub box inputs (`score`, `amount`) warm-dirty into the
    ///         single-slot Sub record — the box is materialized LATER by the open
    ///         leg at the LIVE level; a TICKET sub QUEUES whole tickets NOW directly
    ///         via the inherited `_queueEntriesScaled` primitive (no box). Both modes debit
    ///         `afkingFunding[src]` then set the `lastAutoBoughtDay` success-marker AFTER
    ///         the debit (it also doubles as the lootbox seed `day`), and carry the
    ///         set-mutation semantics (no cursor advance after swap-pop).
    /// @dev The STAGE runs strictly pre-RNG (before `rngGate`), so the day-D
    ///      session word is uncommitted at stamp — the freeze property.
    ///      The lootbox open uses the published active session word after the stamped day
    ///      has sealed, and rolls the level LIVE at open; there is no
    ///      stored per-day epoch. The boundary-pinned `processDay` is computed once by the
    ///      STAGE and passed in (it is the stamped `lastAutoBoughtDay`, the frozen seed
    ///      `day`; never open-time `_simulatedDayIndex()`).
    /// @dev Stamp-only (lootbox mode): this pass writes NO cold box-ledger entry —
    ///      the warm Sub stamp is the box record (no cold ledger). boons OFF ⇒ `amount` = spend.
    /// @dev DOUBLE-DRAW GUARD: the lootbox path STAMPS only — the
    ///      single EV-cap RMW happens at OPEN, fed the FROZEN `evMultiplierBps`
    ///      derived from the stamped `score`. The ticket path queues the paid quantity
    ///      directly (`_queueEntriesScaled`, no century bonus) and accrues its own
    ///      10%/15% FLIP buyer bonus into the Sub slot; no MintModule buy runs.
    /// @dev NO error-swallowing valve: a funded slice is
    ///      revert-free by construction; there is no pre-emptive lootbox skip;
    ///      rule-(1) unfunded eviction is a separate pre-buy decision
    ///      (a NORMAL sub is auto-paused via swap-pop; VAULT/SDGNRS are EXEMPT by pinned
    ///      identity); the `claimablePool -=` site FAILS LOUD (class B, must
    ///      propagate). There is no per-cycle eviction cap.
    /// @notice Stage the pinned daily subscription cohort before its request is sealed.
    function runSubscriberWork(uint24 processDay, uint256 gasAllowance)
        external returns (MineFlipGas.Result memory)
    {
        return _runSubscriberWork(processDay, gasAllowance);
    }

    function _runSubscriberWork(uint24 processDay, uint256 gasAllowance)
        private returns (MineFlipGas.Result memory result)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(gasAllowance);
        if (processDay != _afkingResetDay || processDay <= dailyIdx) revert E();
        if (subsFullyProcessed) { result.done = true; return result; }
        if (!_rngComplete() || rngLockedFlag || _rngRequestActive() || _livenessTriggered()) return result;
        uint256 processed;
        uint256 mp = _mintPriceInContext();
        // Hoist the level read ONCE so the per-iter validity check is a pure
        // stored-field compare (no SLOAD on the non-crossing path).
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


        // sDGNRS level-start whale purchase, attempted ONCE per level here at the start of
        // afking processing (out of the per-sub loop, so it adds NO per-sub cost). On the first
        // STAGE pass of each new level (the `_sdgnrsBonusLevel` latch — level 0 excluded, latch
        // starts at 0), the whale module sizes and delivers sDGNRS's aggregate whale-pass
        // purchase: the largest whole group of five paid passes whose quote fits a quarter of
        // its claimable, capped at the route's 100. The latch stamps on the ATTEMPT, whatever
        // its outcome: a level whose first STAGE pass finds sDGNRS too poor for one group buys
        // nothing that level, and no later chunk/day this level tries again — one probe per
        // level, never a per-day poll of the claimable. The module re-checks the RNG timing
        // contract live (unlocked AND the process day's word uncommitted — the same two halves
        // the STAGE gate keys on) and skips a terminal game, returning 0 for both, so this
        // block never reverts the crank; those returns
        // latch too (they are unreachable through this gate and cost the level its buy, not
        // the crank its day). sDGNRS's ordinary daily box is untouched — the per-sub loop still
        // stamps it (no Sub field is written here, no pending-box count). A real purchase's
        // gas-weight is charged to this chunk, so the loop below starts with it consumed and
        // the chunk stays on the <10M target; a no-buy probe charges nothing.
        if (!swept && currentLevel > _sdgnrsBonusLevel) {
            if (!MineFlipGas.canRun(meter, SUBSCRIBER_WHALE_GAS, SUBSCRIBER_TAIL_GAS)) return result;
            _sdgnrsBonusLevel = currentLevel;
            (bool ok, bytes memory data) = ContractAddresses.GAME_WHALE_MODULE.delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameWhaleModule.purchaseWhalePassForSdgnrs.selector, processDay
                )
            );
            if (!ok) _revertDelegate(data);
            abi.decode(data, (uint256)); // Authenticate the pinned worker's return shape.
            result.progressed = true;
            MineFlipGas.markProgress(meter);
        }

        uint256 cursor = _subCursor;
        uint256 boxStamps; // pending boxes stamped this chunk — one batched counter add at chunk end
        // Batched prize-pool routing: each funded buy debits its full cost from the funding
        // source and accrues that spend here by mode; the pools are credited ONCE at chunk end
        // (boxes 90% future / 10% next, tickets 90% next / 10% future) so the per-sub cost is
        // an add, not a pool SSTORE.
        uint256 boxEthAccrued;
        uint256 ticketEthAccrued;

        // Locally mirrored set length: each in-loop swap-pop removal
        // (tombstone reclaim / funding-kill) decrements it in lockstep with
        // `_removeFromSet`'s pop — every removed player came from `_subscribers[cursor]`
        // and is provably in-set, so the pop always happens — keeping the loop bound
        // SLOAD-free per iteration.
        uint256 len = _subscribers.length;

        // Reserve the largest per-subscriber branch before reading or mutating it.
        while (cursor < len && MineFlipGas.canRun(meter, SUBSCRIBER_ITEM_GAS, SUBSCRIBER_TAIL_GAS)) {
            MineFlipGas.markProgress(meter);
            // Packed subscriber IDs key mint history, quests, events and balances directly.
            uint32 element = _subscribers[cursor];
            uint32 player = element;
            uint32 id = element;
            Sub storage sub = _subOf[id];

            // (-1) NO-ORPHAN guard (the load-bearing correctness rule). A box is
            // STAMPED at process (day D) but OPENED later; it exists ONLY as
            // (Sub stamp + lastAutoBoughtDay) with no cold ledger, so ANY mutation of the
            // Sub OR removal from `_subscribers` between stamp and open ORPHANS the
            // paid-for box (the player was debited at stamp, gets nothing). A sub with a
            // pending unopened box (`lastOpenedDay < lastAutoBoughtDay`) is therefore left
            // ENTIRELY untouched this cycle — no reclaim, no evict, no funding-kill, no
            // re-stamp; it stays in-set (reachable), `_runAfkingWork` opens it, and a LATER
            // cycle processes it (now boxless, lastOpenedDay == lastAutoBoughtDay).
            // Positioned BEFORE the cancel-reclaim so it dominates ALL the orphan paths
            // (re-stamp / cancel-reclaim / funding-kill). SKIP, not
            // force-open: keeps the heavy open out of the gas-critical advance
            // chain; the FLIP open-bounty keeps opens prompt so it ~never skips a buy. No
            // double-charge — the debit is downstream of this guard. Composes with the
            // same-day idempotency skip at (1) (lastAutoBoughtDay >= processDay), which
            // still handles the chunked-same-day case.
            if (sub.lastOpenedDay < sub.lastAutoBoughtDay) {
                unchecked {
                    ++cursor;
                    ++processed;

                }
                continue;
            }

            // Acquisition takes effect for every child before any further debit. Paid stamps
            // were handled by the no-orphan guard above; unclaimed run accrual may forfeit.
            if (sub.dailyQuantity != 0 && _isAcquired(id)) _cancelAcquiredSubscription(id);

            // (0) Cancel-tombstone reclaim.
            // An externally-cancelled sub (subscribe(_, 0)) is an in-set
            // `dailyQuantity == 0` tombstone: it relocated no one on cancel, so it cannot
            // have pushed a pending entry behind the cursor. The cancel branch — the ONLY
            // writer of an in-set zero-quantity record — already finalized the afking
            // streak (quests-side `afkingActive` is clear) before tombstoning, so the
            // reclaim just deletes the `_subOf` record, swap-pops it out, and continues
            // WITHOUT advancing the cursor — the swap-pop occupant (a mover from ahead,
            // still pending) is processed at this slot this pass. Ordered ahead of the
            // AlreadyAutoBoughtToday skip so a tombstone is ALWAYS reclaimed, independent
            // of its lastAutoBoughtDay. Budgeted at EVICT_WEIGHT — the call-free reclaim
            // runs under that weight, conservative for the chunk bound. The removed element
            // sits at the cursor, so its position (cursor + 1) needs no record read and the
            // record can be deleted before the swap-pop.
            if (sub.dailyQuantity == 0) {
                delete _subOf[id];
                _removeFromSet(cursor + 1);
                unchecked {
                    --len;
                }
                emit SubscriptionExpired(player, 2);
                unchecked {
                    ++processed;

                }
                continue;
            }

            // (1) AlreadyAutoBoughtToday — cheapest SLOAD-only skip (the lastAutoBoughtDay
            // marker is the idempotency backstop: a sub stamped this cycle is not re-stamped).
            if (sub.lastAutoBoughtDay >= processDay) {
                emit PlayerSkipped(player, 2);
                unchecked {
                    ++cursor;
                    ++processed;

                }
                continue;
            }

            // No pass/validity gate: the run's seat was burned when it started, so the
            // process pass never re-checks membership credentials.

            // Resolve the once-per-iteration funding source. The common self-funded path
            // is detected from the already-loaded `sub.flags` (FLAG_EXTERNAL_FUNDING clear
            // ⇒ the source is the subscriber's own element) and skips the `_fundingSourceOf`
            // SLOAD entirely; only the rare operator-funded sub (flag set) reads the sparse
            // map holding its funder ID. Both the
            // funding skip-gate read and the debit key on this same source ID. The
            // VAULT/SDGNRS exemption below stays keyed on the un-spoofable `player`, never
            // the source.
            uint32 srcWord = (sub.flags & FLAG_EXTERNAL_FUNDING) != 0
                ? _fundingSourceOf[id]
                : element;
            if (srcWord != id && _isAcquired(srcWord)) {
                _cancelAcquiredSubscription(id);
                // Reclaim the tombstone at the same cursor on the next bounded iteration.
                unchecked { ++processed; }
                continue;
            }
            uint256 srcFunding = _afkingOf(srcWord);

            // Funding resolution (cost + ethValue slice). The slice builder computes
            // everything revert-free by construction off this same `srcFunding` (the
            // fresh-ETH leg) and the player's claimable (the claimable leg).
            (
                uint256 ethValue,
                uint256 amount,
                bool isTicket,
                uint256 claimableUse
            ) = _resolveBuy(sub, id, mp, swept, srcFunding);

            srcFunding = _tryFundAfkingSteth(element, srcWord, ethValue, srcFunding);

            // Funding skip → two-tier skip-kill. A normal underfunded sub is cancelled via
            // swap-pop (auto-pause WITHOUT advancing the cursor — the mover into this slot is
            // processed this pass). VAULT and sDGNRS are exempt by the un-spoofable pinned
            // ContractAddresses identity (kept on `player`, never `src`) — a funding skip is
            // transient for them (no-op-and-retry, stays in the set). The exemption is the
            // pinned-address branch only; there is no flag.
            if (srcFunding < ethValue) {
                if (
                    player == VAULT_WALLET_ID ||
                    player == SDGNRS_WALLET_ID
                ) {
                    emit PlayerSkipped(player, 3);
                    unchecked {
                        ++cursor;
                        ++processed;

                    }
                    continue;
                }
                // Funding-kill of a NORMAL underfunded sub — finalize the afking streak (hands
                // back intact, anchored at yesterday; the manual decay owns it from today), then
                // delete the slot + swap-pop. A got-kicked
                // sub forfeits both accumulators: deleting _subOf wipes pendingFlip /
                // affiliateBase so nothing survives claimable out-of-set.
                _finalizeAfking(id, sub, processDay);
                delete _subOf[id];
                _removeFromSet(cursor + 1);
                unchecked {
                    --len;
                }
                emit SubscriptionExpired(player, 1);
                unchecked {
                    ++processed;

                }
                continue;
            }

            // BUY + DEBIT + ACCRUE + MARKER. The funded, well-formed slice is delivered
            // revert-free by construction (no try/catch) by the shared `_deliverAfkingBuy`:
            // debit `afkingFunding[src]` (claimablePool in tandem, fail-loud on underflow),
            // stamp the lootbox box / queue the tickets, accrue the day's affiliate + the
            // pendingFlip reward, advance the compute-on-read streak markers (gap days earn
            // nothing; the streak never resets in-run), and set the success marker. A lootbox buy is weight
            // SUB_STAGE_LOOTBOX_WEIGHT; a ticket buy SUB_STAGE_TICKET_WEIGHT (the cold ticketQueue
            // push makes it ~2x a lootbox), so the budget binds on the true per-buy cost.
            _deliverAfkingBuy(
                element,
                sub,
                processDay,
                mp,
                currentLevel,
                ticketTargetLevel,
                srcWord,
                ethValue,
                claimableUse,
                amount,
                isTicket,
                false
            );

            // Accrue the full buy cost (afking ethValue + claimableUse) for the
            // batched pool credit below — a box buy funds the box pool, a ticket buy the ticket
            // pool. The afking entry-unit `amount` is the box's wei spend only in lootbox mode,
            // so the routing keys on `cost`, never `amount`.
            uint256 cost = ethValue + claimableUse;
            if (isTicket) {
                ticketEthAccrued += cost;
            } else {
                boxEthAccrued += cost;
                // Every non-ticket STAGE delivery is a Sub-stamp box (coverBuy=false here),
                // i.e. one pending box — counted locally, committed once per chunk below.
                unchecked {
                    ++boxStamps;
                }
            }

            unchecked {
                ++cursor;
                ++processed;

            }
        }

        // Persist the advanced cursor (uint16) for the next chunk / call.
        _subCursor = uint16(cursor);
        // Commit this chunk's pending-box count in ONE warm RMW (the cursor write above
        // already dirtied the shared slot) — the per-stamp version would pay it per sub.
        if (boxStamps != 0) {
            unchecked {
                _pendingBoxCount += uint16(boxStamps);
            }
        }
        // Credit the prize pools once for this chunk's batched box + ticket spend.
        _routeAfkingPoolEth(boxEthAccrued, ticketEthAccrued);
        result.progressed = result.progressed || processed != 0;
        result.rewardBasis = processed;
        result.done = cursor == len;
        if (result.done) {
            subsFullyProcessed = true;
            result.progressed = true;
            MineFlipGas.markProgress(meter);
        }
        MineFlipGas.finish(meter);
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
    ///      nested delegatecall into the LootboxModule's `resolveAfkingBox`.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Materialize ONE subscriber's stamped afking box (the freeze-critical open).
    ///      The box uses the published active session word; the stamped day stays in its
    ///      seed domain. The level and EV-cap key read live inside `resolveAfkingBox`;
    ///      the per-sub inputs (amount, score) come from the Sub record. Day-keyed
    ///      no-double-open: the leg runs only while `lastOpenedDay < lastAutoBoughtDay`
    ///      (the router pre-gates on the same condition), and advances the marker
    ///      (`lastOpenedDay = lastAutoBoughtDay`) BEFORE the resolve (effects-before-
    ///      interaction; a re-entrant open re-checks the now-equal marker and no-ops). The
    ///      box is materialized by delegatecalling the LootboxModule's `resolveAfkingBox`
    ///      (the live-level twin of `resolveLootboxDirect`) with: the stamped spend (boons
    ///      OFF ⇒ amount == spend), the frozen process `day` = `lastAutoBoughtDay`, the
    ///      active session's word, and the frozen
    ///      `activityScore = score`. The draw math and the single EV-cap RMW live in
    ///      `resolveAfkingBox`; this leg is the thin cursor/marker/dispatch shell.
    ///      `resolveAfkingBox` is the one freeze-correct seam (the public
    ///      `resolveLootboxDirect` derives its seed from the live day and would NOT freeze the
    ///      seed `day`). No stored baseLevel/index — the live roll needs no floor.
    /// @param element The subscriber ID whose stamped box is materialized.
    /// @param sub The subscriber's stamped record (storage ref — the marker advances here).
    /// @param word The published active session word, read once by the caller.
    function _openAfkingBox(uint32 element, Sub storage sub, uint256 word) private {
        // lastAutoBoughtDay is the frozen stamp day used in the seed domain.
        uint24 day = sub.lastAutoBoughtDay;
        // Advance the day-keyed no-double-open marker BEFORE the resolve (effects-first; a
        // re-entrant open re-checks `lastOpenedDay < lastAutoBoughtDay` → false → no-op).
        sub.lastOpenedDay = sub.lastAutoBoughtDay;
        // Pending box consumed — the sole decrement paired with the daily stamp's sole
        // increment. The stamp/count invariant guarantees a positive count here. An
        // erroneous underflow would fail closed by blocking session completion; flooring
        // at zero would instead conceal outstanding work and permit word reuse.
        unchecked {
            --_pendingBoxCount;
        }
        // Backlog fully drained (via ANY open path, rewarded or valve): the forced-split
        // bounty batch is over — clear the carry so the next backlog's knee starts fresh.
        // Same packed slot as the counter, so both accesses are warm.

        // boons OFF ⇒ the stamped spend IS the box amount (unpacked milli-ETH → wei). The
        // active session word (passed in from the readiness check so it isn't re-read)
        // remains retained until every pending box opens; the level and EV-cap read
        // live in the callee. No index, no baseLevel.
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveAfkingBox.selector,
                    element,
                    _unpackMilliEthToWei(uint64(sub.amount)), // milli-ETH → wei
                    day,
                    word,
                    uint16(sub.score)
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Open stamped boxes belonging to the unlocked active session.
    function runAfkingWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory) {
        return _runAfkingWork(gasAllowance);
    }

    function _runAfkingWork(uint256 gasAllowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(gasAllowance);
        if (_pendingBoxCount == 0) { result.done = true; return result; }
        if (_rngConsumerStage() != 2) return result;
        uint256 len = _subscribers.length;
        uint256 cursor = _subOpenCursor;
        uint256 initialCursor = cursor;
        if (cursor >= len) cursor = 0;
        uint256 word = _lootboxWord(_rngReadBuffer());
        uint24 sealedDay = dailyIdx;
        uint256 scanned;
        while (scanned < len) {
            if (cursor >= len) cursor = 0;
            uint32 element = _subscribers[cursor];
            Sub storage sub = _subOf[element];
            uint24 stampDay = sub.lastAutoBoughtDay;
            bool skip = sub.lastOpenedDay >= stampDay || stampDay > sealedDay;
            if (!MineFlipGas.canRun(meter, skip ? AFKING_SKIP_GAS : AFKING_OPEN_GAS, AFKING_TAIL_GAS)) break;
            if (!skip) {
                _openAfkingBox(element, sub, word);
                MineFlipGas.markProgress(meter);
                ++result.rewardBasis;
            }
            ++cursor;
            ++scanned;
            if (_pendingBoxCount == 0) break;
        }
        uint16 nextCursor = uint16(cursor >= len ? 0 : cursor);
        if (nextCursor != initialCursor) _subOpenCursor = nextCursor;
        result.progressed = nextCursor != initialCursor || result.rewardBasis != 0;
        if (result.rewardBasis == 0 && scanned == len && _pendingBoxCount != 0) {
            // A full scan found no openable stamp, so the count has no box behind it.
            _forfeitPendingBoxCount(result);
        } else {
            result.done = _pendingBoxCount == 0;
            if (result.done) _tryCompleteRng();
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Clear a pending-box count that no stamp in the ring can satisfy, so the read
    ///      cohort completes instead of reselecting this stage. The ETH that bought the
    ///      counted boxes reached the prize pools when they were stamped and stays there;
    ///      no box opens and no stamp is written.
    function _forfeitPendingBoxCount(MineFlipGas.Result memory result) private {
        emit AfkingBoxCountForfeited(_pendingBoxCount);
        _pendingBoxCount = 0;
        result.progressed = true;
        result.done = true;
        _tryCompleteRng();
    }

    /// @notice Settle the active session's box entries in FIFO order, after AFKing.
    function runHumanBoxWork(uint256 gasAllowance) external returns (MineFlipGas.Result memory) {
        return _runHumanBoxWork(gasAllowance);
    }

    /// @dev Each entry is admitted against its own box and presale bound, then the advanced
    ///      cursor is stored BEFORE the entry's rewards run: the cursor alone marks an entry
    ///      settled, and the entry's legs and the cursor move revert together. Once every entry
    ///      has settled, completion needs only the tail allowance; a call that cannot afford it
    ///      leaves boxCursor at the read count and the next call completes without replaying.
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
            bool presale = (entry >> LB_PRESALE_SHIFT) & LB_PRESALE_MASK != 0;
            if (!MineFlipGas.canRun(
                meter, HUMAN_ENTRY_GAS + boxes * HUMAN_BOX_GAS + (presale ? HUMAN_PRESALE_GAS : 0), HUMAN_TAIL_GAS
            )) break;
            boxCursor = uint48(cur + 1);
            (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
                abi.encodeWithSelector(IDegenerusGameLootboxModule.resolveHumanBoxOrder.selector,
                    idx, cur, entry, indexWord, currentLevel)
            );
            if (!ok) _revertDelegate(data);
            ++cur;
            result.progressed = true;
            MineFlipGas.markProgress(meter);
            result.rewardBasis += boxes + (presale ? 1 : 0);
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

    /// @dev ETH-denominated spend → FLIP base units at the buy-context ticket price —
    ///      the VALUATION BASIS for the lootbox-branch affiliate routing (affiliate +
    ///      quest rewards are FLIP flip-credit, never an ETH cut). A faithful
    ///      copy of MintModule._ethToFlipValue; PRICE_COIN_UNIT (= 1000 FLIP in 18-decimal base units)
    ///      is the inherited Storage constant already used at the bounty unit. Pure —
    ///      no ETH moves, no state.
    function _ethToFlip(
        uint256 amountWei,
        uint256 priceWei
    ) private pure returns (uint256) {
        if (amountWei == 0 || priceWei == 0) return 0;
        return (amountWei * PRICE_COIN_UNIT) / priceWei;
    }

    /*------------------------------------------------------------------
                                  FLIP claim
    ------------------------------------------------------------------*/
    /// @notice Permissionless FLIP claim — pays each sub its accrued `pendingFlip` (the
    ///         per-delivered-day slot-0 quest reward + the ticket buyer-bonus) in ONE
    ///         `creditFlip` and zeroes it, so a re-claim finds 0. Always credits the sub, never
    ///         the caller; callable anytime — the reward is already earned per delivered day,
    ///         so there is no settle-timing or claim-timing edge to exploit. Off the solvency
    ///         path: a FLIP flip-credit, never an ETH cut.
    /// @param ids The subscriber accounts to pay (0 = caller; each credited its own accrued
    ///        `pendingFlip`). An ID with nothing accrued, an unallocated one included, settles
    ///        nothing.
    function claimAfkingFlip(uint32[] calldata ids) external {
        uint256 len = ids.length;
        uint32 self = _walletIdOf(msg.sender);
        // Presale-box eligibility for afking buyers, materialized at claim (no advance-path cost).
        // The slot-0 FLIP owed approximates the afking mint spend (100 whole FLIP == one
        // 0.01-ETH early-level buy, the price at the levels presale spans), and 25% of that spend is
        // the manual buyer's presale-box credit. Granting it off the DRAINED `owed` counts each
        // FLIP exactly once (cover-buys included — they accrue slot-0 like any buy), so there is no
        // double-count. Only while presale is open; the credit is unspendable once presaleOver.
        for (uint256 i; i < len; ) {
            uint32 id = ids[i];
            if (id == 0) id = self;
            Sub storage s = _subOf[id];
            // Only an allocated account accrues, so the key read is in bounds.
            if (s.pendingFlip != 0) _settlePendingFlip(id, s);
            unchecked {
                ++i;
            }
        }
    }

    /*------------------------------------------------------------------
                            Affiliate base accessor
    ------------------------------------------------------------------*/
    /// @notice Affiliate-only atomic read-and-zero of a sub's accrued `affiliateBase` (the
    ///         running unclaimed flat-7% affiliate balance, whole FLIP), which the affiliate
    ///         `claim` consumes.
    /// @dev The read-and-zero happen together at the storage owner, so a duplicate sub in the
    ///      affiliate `claim` array drains 0 the second time — the key guard against
    ///      double-credit. There is no separate read accessor, so the caller can never
    ///      pre-load bases into a memory array. Only `ContractAddresses.AFFILIATE` may drain,
    ///      so a non-affiliate caller can never redirect a sub's base to a wrong recipient.
    ///      Runs in the Game's storage context; `msg.sender` is the original caller.
    /// @param id The subscriber whose affiliate base is drained.
    /// @return base The drained whole-FLIP affiliate base (0 if already drained / never accrued).
    function drainAffiliateBase(uint32 id) external returns (uint256 base) {
        if (msg.sender != ContractAddresses.AFFILIATE) revert NotApproved();
        Sub storage s = _subOf[id];
        base = s.affiliateBase;
        if (base != 0) {
            s.affiliateBase = 0;
            emit AffiliateBaseDrained(id, base);
        }
    }

    /// @notice QUESTS-only: record a secondary/level quest completion against an afking sub's
    ///         streak base, so the run's compute-on-read activity score reflects the player's own
    ///         quest effort (the primary rides the funded delivered days).
    /// @dev No-op unless wallet `id` has a live afking run (`afkingStartDay != 0`); otherwise an
    ///      `amount` bump to the Sub streak base, saturating at 65535. `amount` is 1 for a daily
    ///      secondary completion and LEVEL_QUEST_STREAK_BONUS for a level-quest completion. Runs in
    ///      the Game's storage context under delegatecall; `msg.sender` is the original caller
    ///      (DegenerusQuests). ID 0 has no Sub record, so it returns before any write.
    /// @param id Wallet ID of the afking subscriber whose secondary completion is being recorded.
    /// @param amount The streak-base increment to apply.
    function recordAfkingSecondary(uint32 id, uint16 amount) external {
        if (msg.sender != ContractAddresses.QUESTS) revert NotApproved();
        Sub storage s = _subOf[id];
        if (s.setPosition == 0) return;
        if (s.afkingStartDay == 0) return;
        _setStreakBase(s, uint256(_streakBaseOf(s)) + amount);
    }

    /// @notice QUESTS-only: floor a live afking sub's streak base to `floor`, so a foil-pack
    ///         purchase's quest-streak guarantee reaches a mid-run afker (whose reward streak is
    ///         the sub base plus funded delivered days, not the manual quest streak that the
    ///         foil-pack streak floor raises). The funded days continue to add on top of the
    ///         floored base.
    /// @dev No-op unless wallet `id` has a live afking run (`afkingStartDay != 0`); otherwise raises
    ///      the Sub streak base to `floor` if it is below. Runs in the Game's storage context
    ///      under delegatecall; `msg.sender` is the original caller (DegenerusQuests). ID 0 has no
    ///      Sub record, so it returns before any write.
    /// @param id Wallet ID of the afking subscriber whose streak base is floored.
    /// @param floor The minimum streak base to set.
    function floorAfkingStreakBase(uint32 id, uint16 floor) external {
        if (msg.sender != ContractAddresses.QUESTS) revert NotApproved();
        Sub storage s = _subOf[id];
        if (s.setPosition == 0) return;
        if (s.afkingStartDay == 0) return;
        if (_streakBaseOf(s) < floor) _setStreakBase(s, floor);
    }

    /// @notice Emitted when a curse is cleared via the permissionless paid cure.
    event Decursed(address indexed curer, uint32 indexed target);

    /// @notice Emitted when a deity adds a curse stack to a smitee.
    event Smited(uint256 indexed deityId, uint32 indexed smitee);

    /// @notice Cashout-curse SET (delegatecall target from the Game's claimWinnings): a stale
    ///         ghost-cashout adds a saturating +2 stack. Cheapest-first bails skip the SSTORE
    ///         for infra addresses (protects the sDGNRS redemption-snapshot score), gameOver, a
    ///         non-stale claimant, deity holders, active lazy/whale-pass holders, an
    ///         already-capped counter, and an active afker. Net: +2 only on a stale
    ///         cashout by a non-exempt, below-cap player.
    function maybeCurse(uint32 player) external {
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
        if (_subOf[player].dailyQuantity != 0) return;
        _applyCurseStack(player);
    }

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
        if (_subOf[smitee].dailyQuantity != 0) {
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
