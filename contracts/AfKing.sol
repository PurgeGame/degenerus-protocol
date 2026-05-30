// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";

/// @notice Payment method for ticket / lootbox purchases. File-scope mirror of
///         `contracts/interfaces/IDegenerusGame.sol` so the afking's batched
///         purchase carries the `uint8` mode cast through `batchPurchase`.
enum MintPaymentKind {
    DirectEth, // Pay with fresh ETH only
    Claimable, // Pay with claimable winnings only
    Combined // Pay with both ETH and claimable
}

/// @notice Per-subscriber buy descriptor for the batched afking purchase. File-scope mirror of
///         `DegenerusGame.BatchBuy` (identical field order/types ⇒ ABI-compatible). `funder` is the
///         resolved funding source (the bucket the Game debits); `player` is the beneficiary. `amount`
///         is ticket entry-units when `isTicket`, else a lootbox spend in wei (the two are mutually
///         exclusive); `ethValue` is the fresh-ETH portion debited from the funder's afking bucket
///         (0 = pure claimable), the rest drawn from the buyer's claimable per `mode`.
struct BatchBuy {
    address funder;
    address player;
    uint256 ethValue;
    uint256 amount;
    bool isTicket;
    uint8 mode;
}

/// @title IGame
/// @notice Minimal owner-less call surface into the protocol GAME contract.
/// @dev Signatures match `contracts/DegenerusGame.sol` verbatim: `batchPurchase`
///      is the AF_KING-gated batched mint (the afking is the sole authorized
///      caller); `level()` is the auto-getter for the current game level; the
///      `lazyPassHorizon` view is the v50.0 AFSUB pass-gating producer (D-11),
///      read once at subscribe-time and exactly once at the autoBuy crossing
///      branch; the rest are the operator-approval / pricing / claimable views
///      the autoBuy reads. Call sites use the compile-time constant handle
///      `GAME` (declared in the contract body); no immutable IGame field is
///      held — `ContractAddresses` remains the protocol's single source of
///      truth for the address.
interface IGame {
    function isOperatorApproved(address owner, address operator) external view returns (bool);

    function batchPurchase(BatchBuy[] calldata buys) external;

    // Afking-funding ledger: AfKing forwards subscribe ETH and reads afkingFunding (the
    // Game holds the ETH; AfKing holds none). Signatures match DegenerusGame verbatim.
    function depositAfkingFunding(address player) external payable;
    function withdrawAfkingFunding(uint256 amount) external;
    function afkingFundingOf(address player) external view returns (uint256);

    function rngLocked() external view returns (bool);
    function mintPrice() external view returns (uint256);
    function claimableWinningsOf(address player) external view returns (uint256);
    function level() external view returns (uint24);
    function lazyPassHorizon(address player) external view returns (uint24);

    // Router-surface rows the doWork router calls on GAME (match DegenerusGame).
    function advanceGame() external returns (uint8 mult);
    function autoOpen(uint256 maxCount) external returns (uint256 opened);
    function advanceDue() external view returns (bool);
    function boxesPending() external view returns (bool);
    function afkingSnapshot(address[] calldata players) external view returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables, uint256[] memory afkingFundings);
}

/// @title ICoinflip
/// @notice Minimal call surface into BurnieCoinflip for the autoBuy bounty.
/// @dev `creditFlip(player, amount)` matches `contracts/BurnieCoinflip.sol`
///      verbatim. The afking earns its per-autoBuy bounty as deferred coinflip-stake
///      credit (a deferred mint — liquid BURNIE only mints when the caller later
///      claims), so no liquid BURNIE leaves the afking and the bounty needs no
///      payment pool. BurnieCoinflip gates `creditFlip` to authorized flip
///      creditors via `onlyFlipCreditors`, extended to include
///      `ContractAddresses.AF_KING`.
interface ICoinflip {
    function creditFlip(address player, uint256 amount) external;
}

/// @notice Per-player subscription record. File-scope so view signatures
///         `subscriptionOf(address) returns (Sub memory)` name the type without
///         `AfKing.Sub` namespacing.
/// @dev Maximal-packing layout (single 32-byte slot):
///        offset 0  uint8   dailyQuantity     — 0 = paused / never-subscribed (minimum 1 when active)
///        offset 1  uint32  lastAutoBoughtDay  — afking-local day index of the last successful buy
///        offset 5  uint32  validThroughLevel — game-level horizon through which the sub's pass coverage
///                                              extends (`lazyPassHorizon` snapshot at subscribe; refreshed
///                                              on crossing; deity sentinel = `type(uint24).max`; non-pass = 0)
///        offset 9  uint8   reinvestPct       — claimable reinvest percentage (0..100), 0 = no reinvest
///        offset 10 uint8   flags             — bit 0 freed (was windowPaid; retired v50.0 AFSUB-01),
///                                              bit 1 = drainGameCreditFirst, bit 2 = useTickets
///        offset 11 address fundingSource     — wallet whose game-side afkingFunding funds this sub; address(0) = self
///      Offset 31 is free padding. Storage slots 0-2 (the three state
///      mappings/array below) hold the afking's state; this struct occupies a single
///      slot reached through `_subOf` at slot 0.
///      v50.0 AFSUB: slot offset 5 was `paidThroughDay` (30-day BURNIE prepay window
///      endpoint); repurposed in place to `validThroughLevel`. Width unchanged
///      (uint32 — zero packing churn) so the assignment from the `uint24`
///      `lazyPassHorizon` view casts up cleanly.
struct Sub {
    uint8 dailyQuantity;
    uint32 lastAutoBoughtDay;
    uint32 validThroughLevel;
    uint8 reinvestPct;
    uint8 flags;
    address fundingSource;
}

/// @title AfKing
/// @notice Permissionless, owner-less daily subscription afking. Players (or
///         operator-approved third parties) subscribe to a daily ticket/lootbox
///         buy; anyone calls `autoBuy(maxCount)` to process the next chunk of
///         active subscribers and earns a gas-pegged bounty per successful player.
/// @dev No admin. No upgrade. No owner. No fallback. No multicall. `receive()` is
///      the only untyped entrypoint and credits msg.sender's pool. The afking
///      holds NO immutable IGAME/ICOINFLIP references — every protocol call
///      flows through the compile-time constant handles `GAME` /
///      `COINFLIP` declared at the top of the contract body, which resolve
///      to `IGame(ContractAddresses.GAME)` and `ICoinflip(ContractAddresses.COINFLIP)`.
///      v50.0 AFSUB-01: subscriptions are pass-gated via `GAME.lazyPassHorizon`
///      (no BURNIE prepay window). The constructor sets only the three economic
///      immutables with sanity reverts (`SUB_COST_ETH_TARGET` is retained for
///      possible future re-use; under v50.0 it is unreferenced by any code path).
/// @custom:invariant No reentrancy guard — strict CEI everywhere; the afking is
///                   never a payee in any contract it calls.
/// @custom:invariant Caller-scoped writes: every player-state mutator writes only
///                   to the resolved player's slot. The two-tier funding-skip
///                   exemption keys on the un-spoofable pinned
///                   `ContractAddresses.VAULT` / `SDGNRS` identity — there is no
///                   settable exemption flag.
contract AfKing {
    /*------------------------------------------------------------------
                              Protocol handles (compile-time constants)
    ------------------------------------------------------------------*/
    /// @dev Compile-time-typed handles into the two protocol contracts the afking
    ///      calls. Both resolve to `address constant`s in `ContractAddresses.sol`,
    ///      so each call site compiles to a literal `PUSH20` — zero storage slots,
    ///      no constructor wiring, no immutable bytecode slots, and the
    ///      ContractAddresses library remains the protocol's single source of
    ///      truth for these addresses. Mirrors the same pattern used by
    ///      `DegenerusGameStorage.sol:136-147` for `coin` / `coinflip` / `quests` /
    ///      `affiliate` / `dgnrs`.
    IGame internal constant GAME = IGame(ContractAddresses.GAME);
    ICoinflip internal constant COINFLIP = ICoinflip(ContractAddresses.COINFLIP);

    /*------------------------------------------------------------------
                              Custom errors
    ------------------------------------------------------------------*/
    /// @dev InvalidSubCostTarget: constructor revert when _subCostEthTarget == 0.
    error InvalidSubCostTarget();
    /// @dev InvalidBountyTarget: constructor revert when _bountyEthTarget == 0.
    error InvalidBountyTarget();
    /// @dev InvalidLootboxFloor: constructor revert when _lootboxMin == 0.
    error InvalidLootboxFloor();
    /// @dev InvalidDailyQuantity: subscribe(_, 0) — 0 is the paused sentinel, not
    ///      a valid subscription quantity.
    error InvalidDailyQuantity();
    /// @dev InvalidReinvestPct: subscribe with reinvestPct > 100 (a percentage).
    error InvalidReinvestPct();
    /// @dev NotApproved: third-party subscribe(player, ...) where the caller is
    ///      neither the player nor a game operator the player approved.
    error NotApproved();
    /// @dev NotSubscribed: setDailyQuantity / setDrainGameCreditFirst / setMode /
    ///      setReinvestPct called while the caller is not in the iterable set.
    error NotSubscribed();
    /// @dev IndexOutOfBounds: subscriberAt(idx) with idx >= _subscribers.length.
    error IndexOutOfBounds();
    /// @dev NoWork: doWork() found no pending work in any category (all 3 O(1) predicates empty).
    error NoWork();

    /*------------------------------------------------------------------
                              Events
    ------------------------------------------------------------------*/
    /// @dev Single canonical subscription-state stream — POST-WRITE full state.
    ///      Manual pause (setDailyQuantity(0)) emits with dailyQuantity == 0.
    ///      `fundingSource` is the stored funding wallet (address(0) = self); indexed
    ///      so a source can filter the log for every account it funds — the off-chain
    ///      counterpart to the subscribe-time-only auth + BURNIE blast-radius caveat.
    event SubscriptionUpdated(
        address indexed player,
        uint8 dailyQuantity,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 reinvestPct,
        address indexed fundingSource
    );
    /// @dev Per-player pre-check skip inside the autoBuy loop. `reason`:
    ///        2 = AlreadyAutoBoughtToday (sub.lastAutoBoughtDay >= today)
    ///        3 = InsufficientPool  (afkingFunding[src] < ethValue) — funding skip
    ///        4 = LootboxFloor      (!useTickets && cost < LOOTBOX_MIN) — transient
    ///        5 = NotApproved       (operator-approval revoked or never granted)
    ///      lastAutoBoughtDay is UNCHANGED on a skip.
    event PlayerSkipped(address indexed player, uint8 reason);
    /// @dev Emitted once at the end of each successful autoBuy, after the bounty payout.
    event AutoBuyCompleted(address indexed caller, uint256 successfulPlayers, uint256 bountyEarned);
    /// @dev Pass-validity refresh — emitted at the AFSUB-03 crossing branch when
    ///      the afking re-reads `lazyPassHorizon(player)` and the subscriber's
    ///      coverage extends to or beyond the current level. Writes the new
    ///      validThroughLevel and continues without eviction.
    event SubscriptionExtendedFree(address indexed player, uint32 day);
    /// @dev Subscription removed from the iterable set. `reason`:
    ///        1 = AutoPause (AFSUB-03 pass-eviction at crossing OR funding-skip kill of a NORMAL sub)
    ///        2 = CancelReclaim (in-autoBuy reclaim of an externally-cancelled `dailyQuantity == 0` tombstone)
    event SubscriptionExpired(address indexed player, uint8 reason);

    /*------------------------------------------------------------------
                              State (slot layout)
    ------------------------------------------------------------------*/
    /// @dev Slot 0 — per-player subscription record (file-scope Sub struct).
    mapping(address => Sub) private _subOf; // slot 0

    /// @dev Slot 1 — insertion-ordered iterable subscriber set (length here,
    ///      elements at keccak256(1)+i).
    address[] private _subscribers; // slot 1

    /// @dev Slot 2 — 1-indexed subscriber index (0 = not in set). Hand-inlined OZ
    ///      EnumerableSet pattern.
    mapping(address => uint256) private _subscriberIndex; // slot 2

    /// @dev AutoBuy progress cursor + the afking-local day it belongs to, packed in
    ///      a single slot. `_autoBuyDay` stamps which day `_autoBuyCursor` indexes;
    ///      on the first autoBuy of a new day the cursor resets to 0. The cursor
    ///      advances monotonically within a day so concurrent same-block callers
    ///      self-partition (a later tx reads the earlier tx's advanced cursor and
    ///      takes the next chunk). The per-entry `lastAutoBoughtDay` day-stamp is the
    ///      idempotency backstop against any double-buy.
    uint32 private _autoBuyDay; // slot 3 (offset 0)
    uint224 private _autoBuyCursor; // slot 3 (offset 4)

    /*------------------------------------------------------------------
                              Constants
    ------------------------------------------------------------------*/
    /// @dev Afking-local ticket scaling multiplier. TICKET_SCALE = 400 makes the
    ///      cost formula unit-consistent across modes: 400 * dailyQuantity *
    ///      mintPrice / 400 == mintPrice * dailyQuantity, so one dailyQuantity
    ///      unit resolves to exactly one mintPrice worth of spend in both ticket
    ///      and lootbox mode.
    uint256 internal constant TICKET_SCALE = 400;

    /// @dev BURNIE-per-ETH conversion unit, sourced verbatim from the protocol
    ///      (`DegenerusGameAdvanceModule` / `BurnieCoinflip` PRICE_COIN_UNIT). The
    ///      live BURNIE bounty-credit call site converts via
    ///      `(ethTarget * PRICE_COIN_UNIT) / mintPrice()`.
    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev drainGameCreditFirst bit within Sub.flags — when set the autoBuy spends
    ///      protocol-side claimable credit before tapping pool ETH.
    uint8 internal constant FLAG_DRAIN_FIRST = 2;

    /// @dev useTickets bit within Sub.flags — set = ticket mint mode, clear =
    ///      lootbox mode.
    uint8 internal constant FLAG_USE_TICKETS = 4;

    /*------------------------------------------------------------------
                              Immutables (3 economic targets only)
    ------------------------------------------------------------------*/
    /// @notice ETH-equivalent subscription-cost target per subscriber per 30-day
    ///         window (in ETH wei). Set once at deploy; the live BURNIE cost is
    ///         `(SUB_COST_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice()`.
    uint256 public immutable SUB_COST_ETH_TARGET;

    /// @notice ETH-equivalent autoBuy-bounty target per successful player processed
    ///         (in ETH wei). Set once at deploy; the per-player bounty is
    ///         `(BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp`, scaled by the stall
    ///         multiplier and successful-player count, paid as one creditFlip.
    uint256 public immutable BOUNTY_ETH_TARGET;

    /// @dev Lootbox-mode minimum-cost floor (in ETH wei). Internal — no auto-getter.
    uint256 internal immutable LOOTBOX_MIN;

    /*------------------------------------------------------------------
                              Constructor (3-arg + 3-revert sanity)
    ------------------------------------------------------------------*/
    /// @param _subCostEthTarget ETH-equivalent subscription-cost target, in ETH wei.
    /// @param _bountyEthTarget ETH-equivalent autoBuy-bounty target, in ETH wei.
    /// @param _lootboxMin Lootbox-mode minimum-cost floor, in ETH wei.
    constructor(uint256 _subCostEthTarget, uint256 _bountyEthTarget, uint256 _lootboxMin) {
        if (_subCostEthTarget == 0) revert InvalidSubCostTarget();
        if (_bountyEthTarget == 0) revert InvalidBountyTarget();
        if (_lootboxMin == 0) revert InvalidLootboxFloor();
        SUB_COST_ETH_TARGET = _subCostEthTarget;
        BOUNTY_ETH_TARGET = _bountyEthTarget;
        LOOTBOX_MIN = _lootboxMin;
    }

    /*------------------------------------------------------------------
                          Subscription mutators
    ------------------------------------------------------------------*/
    /// @notice Start or extend a daily subscription for `player`.
    /// @dev SUB-02 authorization is checked ONCE here, third-party path only:
    ///      `player == address(0)` or `player == msg.sender` is self-consent (no
    ///      check); otherwise the caller must be a game operator the player
    ///      approved (`IGame.isOperatorApproved(player, msg.sender)`). Authorization
    ///      is NEVER re-checked at autoBuy.
    /// @dev AFSUB-02 pass-gating: subscribe encodes the subscriber's current pass
    ///      horizon (`IGame.lazyPassHorizon(subscriber)`) into `Sub.validThroughLevel`
    ///      with a SINGLE external read. No BURNIE charge — the v50.0 pass-gated
    ///      model replaces the 30-day BURNIE prepay window (AFSUB-01). The per-iter
    ///      autoBuy validity check is the cheap stored-field compare
    ///      `currentLevel <= sub.validThroughLevel`; at the crossing
    ///      (`currentLevel > validThroughLevel`) the afking re-reads the horizon
    ///      EXACTLY ONCE and refresh-or-evicts (AFSUB-03).
    /// @dev msg.value > 0 forwards to the Game's afkingFunding ledger
    ///      (GAME.depositAfkingFunding) — AfKing never retains ETH.
    /// @param player Subscriber to act for (0 or msg.sender = self).
    /// @param drainGameCreditFirst When true, the autoBuy spends protocol-side
    ///        claimable credit before tapping pool ETH.
    /// @param useTickets Mint mode — true = tickets, false = lootboxes.
    /// @param dailyQuantity Daily buy units, 1..255. MUST be non-zero; zero is the
    ///        paused sentinel handled by setDailyQuantity(0).
    /// @param reinvestPct Claimable reinvest percentage, 0..100. The effective
    ///        daily buy is max(dailyQuantity, floor(claimable * reinvestPct / price)).
    /// @param fundingSource Wallet whose game-side `afkingFunding` funds this subscription's
    ///        afking spends — the per-day ETH draw resolves to this address.
    ///        `address(0)` = self. A non-zero, non-self source is honored ONLY when
    ///        it has operator-approved the subscriber on the game
    ///        (`IGame.isOperatorApproved(fundingSource, subscriber)`), checked at
    ///        subscribe() ONLY — never per-draw. (OPEN-E preserved.)
    /// @dev Subscribe-time auth only: a later `setOperatorApproval(subscriber,
    ///      false)` by the source does NOT stop an active sub — the renewal trusts
    ///      the stored source and keeps drawing it. The source halts draws by
    ///      defunding (`withdraw()` its pool); the subscriber halts by cancelling;
    ///      re-pointing the source means re-subscribing (which re-checks).
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint8 reinvestPct,
        address fundingSource
    ) external payable {
        if (dailyQuantity == 0) revert InvalidDailyQuantity();
        if (reinvestPct > 100) revert InvalidReinvestPct();

        // SUB-02 — self-consent (player == 0 or msg.sender) or operator-approval.
        address subscriber = player == address(0) ? msg.sender : player;
        if (subscriber != msg.sender) {
            if (!GAME.isOperatorApproved(subscriber, msg.sender)) {
                revert NotApproved();
            }
        }

        // OPENE-04 — a non-zero, non-self fundingSource must have operator-approved
        // the subscriber on the game. address(0) (self) short-circuits the read;
        // checked HERE only — the renewal and per-draw paths never re-check.
        if (
            fundingSource != address(0) &&
            fundingSource != subscriber &&
            !GAME.isOperatorApproved(fundingSource, subscriber)
        ) {
            revert NotApproved();
        }

        // msg.value > 0 forwards to the Game's afkingFunding ledger (A2 — AfKing never
        // retains ETH; the Game emits AfkingFunded). Permissionless deposit-for-subscriber.
        if (msg.value > 0) {
            GAME.depositAfkingFunding{value: msg.value}(subscriber);
        }

        Sub storage s = _subOf[subscriber];

        s.dailyQuantity = dailyQuantity;
        if (drainGameCreditFirst) s.flags |= FLAG_DRAIN_FIRST;
        else s.flags &= ~FLAG_DRAIN_FIRST;
        if (useTickets) s.flags |= FLAG_USE_TICKETS;
        else s.flags &= ~FLAG_USE_TICKETS;
        s.reinvestPct = reinvestPct;
        // AFSUB-02 — single external read; encodes the subscriber's pass horizon
        // into the stored field the per-iter check + crossing branch compare against.
        // Deity sentinel = type(uint24).max via the lazyPassHorizon view (D-11).
        s.validThroughLevel = uint32(GAME.lazyPassHorizon(subscriber));
        s.fundingSource = fundingSource;

        _addToSet(subscriber);
        emit SubscriptionUpdated(subscriber, dailyQuantity, drainGameCreditFirst, useTickets, reinvestPct, s.fundingSource);
    }

    /// @notice Update caller's daily buy units. q == 0 is the in-place tombstone
    ///         cancel (writes the sentinel, relocates no one); q > 0 reactivates
    ///         in place.
    /// @dev SUB-07 tombstone-on-cancel: cancel only writes `dailyQuantity = 0` (the
    ///      "paused" sentinel) and leaves the entry in the iterable set — it moves
    ///      nothing, so it can never relocate an unprocessed entry behind the chunked
    ///      autoBuy cursor. The `_subOf` record stays readable; the in-autoBuy
    ///      reclaim deletes `_subOf` and swap-pops the entry out when the autoBuy
    ///      reaches the tombstone. Under v50.0 AFSUB-01 the pre-edit
    ///      delete-vs-preserve decision (which kept `_subOf` when the BURNIE
    ///      prepay window was paid + unexpired) is moot — every cancel = full
    ///      delete. Reactivation (q > 0) flips the sentinel back in place with no
    ///      set churn (the entry never left the set). Stranded afking ETH always
    ///      stays withdrawable game-side via GAME.withdrawAfkingFunding.
    function setDailyQuantity(uint8 q) external {
        if (_subscriberIndex[msg.sender] == 0) revert NotSubscribed();
        Sub storage s = _subOf[msg.sender];
        if (q == 0) {
            s.dailyQuantity = 0;
            emit SubscriptionUpdated(msg.sender, 0, (s.flags & FLAG_DRAIN_FIRST) != 0, (s.flags & FLAG_USE_TICKETS) != 0, s.reinvestPct, s.fundingSource);
            return;
        }
        s.dailyQuantity = q;
        emit SubscriptionUpdated(msg.sender, q, (s.flags & FLAG_DRAIN_FIRST) != 0, (s.flags & FLAG_USE_TICKETS) != 0, s.reinvestPct, s.fundingSource);
    }

    /// @notice Toggle caller's drain-game-credit-first flag.
    function setDrainGameCreditFirst(bool flag) external {
        if (_subscriberIndex[msg.sender] == 0) revert NotSubscribed();
        Sub storage s = _subOf[msg.sender];
        if (flag) s.flags |= FLAG_DRAIN_FIRST;
        else s.flags &= ~FLAG_DRAIN_FIRST;
        emit SubscriptionUpdated(msg.sender, s.dailyQuantity, flag, (s.flags & FLAG_USE_TICKETS) != 0, s.reinvestPct, s.fundingSource);
    }

    /// @notice Toggle caller's mint mode. true = tickets, false = lootboxes.
    function setMode(bool useTickets) external {
        if (_subscriberIndex[msg.sender] == 0) revert NotSubscribed();
        Sub storage s = _subOf[msg.sender];
        if (useTickets) s.flags |= FLAG_USE_TICKETS;
        else s.flags &= ~FLAG_USE_TICKETS;
        emit SubscriptionUpdated(msg.sender, s.dailyQuantity, (s.flags & FLAG_DRAIN_FIRST) != 0, useTickets, s.reinvestPct, s.fundingSource);
    }

    /// @notice Update caller's claimable reinvest percentage (0..100).
    function setReinvestPct(uint8 reinvestPct) external {
        if (_subscriberIndex[msg.sender] == 0) revert NotSubscribed();
        if (reinvestPct > 100) revert InvalidReinvestPct();
        Sub storage s = _subOf[msg.sender];
        s.reinvestPct = reinvestPct;
        emit SubscriptionUpdated(msg.sender, s.dailyQuantity, (s.flags & FLAG_DRAIN_FIRST) != 0, (s.flags & FLAG_USE_TICKETS) != 0, reinvestPct, s.fundingSource);
    }

    /*------------------------------------------------------------------
                          Views
    ------------------------------------------------------------------*/
    /// @notice Return the full subscription record for `player`. Never reverts; an
    ///         uninitialized player returns the zero-value Sub.
    function subscriptionOf(address player) external view returns (Sub memory) {
        return _subOf[player];
    }

    /// @notice Total active subscribers (length of the iterable set).
    function subscriberCount() external view returns (uint256) {
        return _subscribers.length;
    }

    /// @notice Return subscriber at `idx` in insertion order (modulo swap-pop on remove).
    function subscriberAt(uint256 idx) external view returns (address) {
        if (idx >= _subscribers.length) revert IndexOutOfBounds();
        return _subscribers[idx];
    }

    /// @notice Current autoBuy cursor and the afking-local day it indexes.
    /// @dev On the first autoBuy of a new day the cursor resets to 0; reads return
    ///      the live (possibly stale-day) packed values for off-chain planning.
    function autoBuyProgress() external view returns (uint32 day, uint256 cursor) {
        return (_autoBuyDay, _autoBuyCursor);
    }

    /*------------------------------------------------------------------
                          Cursor autoBuy
    ------------------------------------------------------------------*/
    /// @notice Internal buy leg: autoBuy the next `maxCount` un-autoBought active
    ///         subscribers from the internal daily-reset cursor and return the raw
    ///         count of successful buys. The re-homed buy bounty is paid by the
    ///         unified router (`doWork`); this leg NEVER self-credits (RD-4).
    /// @dev SUB-03 — No caller-supplied range. The cursor resumes from where the
    ///      previous autoBuy left off and advances as entries are processed.
    ///      Concurrent same-block callers self-partition via the advancing cursor;
    ///      the per-entry `lastAutoBoughtDay` day-stamp is the idempotency backstop
    ///      (an already-autoBought entry is skipped with reason 2). On the first autoBuy
    ///      of a new afking-local day the cursor resets to 0.
    /// @dev RD-2 — the buy path carries NO rngLock guard (buys are freeze-safe by
    ///      construction; a box queues at the current LR_INDEX, pre-entropy, and the
    ///      orphan hazard is defended on the resolution side via the autoOpen word-gate).
    /// @dev Per-player ladder: (0) cancel-tombstone reclaim (in-set
    ///      `dailyQuantity == 0` → swap-pop, no cursor advance — SUB-07 + v49
    ///      swap-pop preserved); (1) AlreadyAutoBoughtToday skip; (2) AFSUB-02/03
    ///      pass-validity gate (non-crossing path is the pure stored-field compare
    ///      `currentLevel <= sub.validThroughLevel`; at the crossing re-read
    ///      `lazyPassHorizon` EXACTLY ONCE → refresh-or-evict via tombstone-then-
    ///      reclaim shape); (3) cost + mode + payKind funding waterfall (claimable
    ///      read once via afkingSnapshot, GASOPT-03); (4) LootboxFloor transient
    ///      skip; (5) InsufficientPool — NORMAL sub is CANCELLED via swap-pop
    ///      (two-tier kill), Vault/sDGNRS are EXEMPT (no-op-and-retry) by pinned
    ///      identity; (6) CEI debit + day-stamp. The batched `IGame.batchPurchase`
    ///      call carries one slice per successful player and fires once after the
    ///      per-player accounting loop; CEI debit happens before the batched call,
    ///      day-stamp after.
    /// @dev No try/catch and no `nonReentrant` guard. Per-player batch isolation
    ///      lives in the game's `batchPurchase` (per-slice try/catch + slice
    ///      refund); the afking preserves strict CEI.
    /// @param maxCount Maximum number of un-autoBought active entries to process this
    ///        call. 0 = use the default batch (BUY_BATCH). Caller-bounded (no
    ///        contract-bounded loop) — the anti-gas-DoS property.
    /// @return boughtCount Number of successful per-player buys this chunk.
    function _autoBuy(uint256 maxCount) internal returns (uint256 boughtCount) {
        if (maxCount == 0) maxCount = BUY_BATCH;

        uint32 today = _currentDay();
        uint256 mp = GAME.mintPrice();
        // AFSUB-02 — hoist the level read ONCE per autoBuy call so the per-iter
        // validity check is a pure stored-field compare (no external SLOAD on
        // the non-crossing path). GASOPT-05 preserved.
        uint24 currentLevel = GAME.level();

        // Daily cursor reset: the first autoBuy of a new afking-local day restarts
        // the cursor at 0. Within a day the cursor advances monotonically so
        // concurrent callers self-partition.
        uint256 cursor = _autoBuyDay == today ? uint256(_autoBuyCursor) : 0;
        if (_autoBuyDay != today) {
            _autoBuyDay = today;
        }

        // Per-chunk accumulation buffers. The batched purchase fires once, after the
        // per-player accounting loop, with one slice per successful player.
        uint256 cap = maxCount;
        BatchBuy[] memory buys = new BatchBuy[](cap);
        uint256 batchLen;
        // True once the chunk commits real set work (cancel-tombstone reclaim,
        // auto-pause, or window renewal). Gates the tail so a buy-less chunk that
        // did such work commits it instead of hitting the no-buy revert and rolling
        // the removal back (which would strand the tombstone for re-griefing).
        bool didWork;

        uint256 processed;
        while (processed < maxCount && cursor < _subscribers.length) {
            address player = _subscribers[cursor];
            Sub storage sub = _subOf[player];

            // (0) Cancel-tombstone reclaim. An externally-cancelled sub
            // (setDailyQuantity(0)) is an in-set `dailyQuantity == 0` tombstone:
            // it relocated no one on cancel, so it cannot have pushed a pending
            // entry behind the cursor. The reclaim deletes the `_subOf` record,
            // swap-pops it out of the set, and continues WITHOUT advancing the
            // cursor — the swap-pop occupant (a mover from ahead, hence still
            // pending) is processed at this slot this autoBuy. Ordered ahead of
            // the AlreadyAutoBoughtToday skip so a tombstone is ALWAYS reclaimed
            // (never left as a permanent dead slot), independent of its
            // `lastAutoBoughtDay`. AFSUB-05: the v49 swap-pop / SUB-07 cancel
            // tombstone invariant (membership ⟺ packed != 0) is preserved by
            // construction — no cursor advance.
            // v50.0: the pre-AFSUB `preservePaidWindow` branch (keep `_subOf`
            // iff windowPaid && paidThroughDay > today) is DROPPED — under
            // AFSUB-01 there is no BURNIE-prepaid window to preserve; every
            // cancel = full delete.
            if (sub.dailyQuantity == 0) {
                delete _subOf[player];
                _removeFromSet(player);
                emit SubscriptionExpired(player, 2);
                didWork = true;
                unchecked {
                    ++processed;
                }
                continue;
            }

            // (1) AlreadyAutoBoughtToday — cheapest SLOAD-only skip.
            if (sub.lastAutoBoughtDay >= today) {
                emit PlayerSkipped(player, 2);
                unchecked {
                    ++cursor;
                    ++processed;
                }
                continue;
            }

            // (2) AFSUB-02/03 pass-validity gate. Non-crossing path is a pure
            // stored-field compare (currentLevel <= validThroughLevel) — no
            // external read. At the crossing the afking re-reads the horizon
            // EXACTLY ONCE and refreshes (if still covered) or evicts via
            // tombstone-then-reclaim (membership ⟺ packed != 0 preserved).
            if (currentLevel > sub.validThroughLevel) {
                uint24 h = GAME.lazyPassHorizon(player);
                if (currentLevel <= h) {
                    // REFRESH — still covered (newly minted pass, upgrade, etc.).
                    sub.validThroughLevel = uint32(h);
                    emit SubscriptionExtendedFree(player, today);
                    didWork = true;
                } else {
                    // EVICT — route through tombstone-then-reclaim shape so the
                    // v49 swap-pop invariant survives (Pitfall P6 — direct mid-
                    // sweep removal would re-open H-CANCEL-SWAP-MISS).
                    sub.dailyQuantity = 0;
                    _removeFromSet(player);
                    emit SubscriptionExpired(player, 1);
                    didWork = true;
                    unchecked {
                        ++processed;
                    }
                    continue;
                }
            }

            // (GASOPT-05) The per-iteration isOperatorApproved(player, this) check is
            // removed — the SUB is the consent unit (revoke = setDailyQuantity(0) →
            // tombstone-skip); the retained funding-consent boundary is the
            // subscribe-time isOperatorApproved(fundingSource, subscriber) gate.

            // SUB-04 funding resolution (cost + payment mode + msg.value slice). Extracted
            // to _resolveBuy so its temporaries (claimable / effectiveQty / cred + the
            // afkingSnapshot scratch) live in that frame, not this loop's — the loop is at
            // the stack-depth limit. GASOPT-03: ONE afkingSnapshot read per player.
            (
                MintPaymentKind payKind,
                uint256 ethValue,
                uint256 amount,
                bool isTicket,
                bool lootboxSkip,
                uint256 playerFunding
            ) = _resolveBuy(sub, player, mp);

            if (lootboxSkip) {
                emit PlayerSkipped(player, 4);
                unchecked {
                    ++cursor;
                    ++processed;
                }
                continue;
            }

            // OPENE-02 — resolve the once-per-iteration funding source. address(0)
            // = self; the ETH skip-gate read and the CEI debit both key on this
            // same `src`. The VAULT/SDGNRS exemption below stays keyed on the
            // un-spoofable `player`, never `src`.
            address src = sub.fundingSource == address(0) ? player : sub.fundingSource;

            // (6) Funding skip → two-tier skip-kill. The afking holds no ETH — read
            // afkingFunding[src] from the GAME: the common path (src == player) reuses the
            // per-player afkingSnapshot value from _resolveBuy (no extra staticcall); the rare
            // OPEN-E operator-funded slice (src != player) pays ONE extra afkingFundingOf(src)
            // (D-MR-01). A NORMAL underfunded sub is CANCELLED via swap-pop (auto-pause WITHOUT
            // advancing the cursor — the mover at this slot is processed this autoBuy). Vault +
            // sDGNRS are EXEMPT by the un-spoofable pinned ContractAddresses.VAULT / SDGNRS
            // identity (kept on `player`, never `src`) — a funding skip is transient for them
            // (no-op-and-retry, stays in the set). The exemption is the pinned-address branch
            // only; there is no settable exemption flag.
            if ((src == player ? playerFunding : GAME.afkingFundingOf(src)) < ethValue) {
                if (player == ContractAddresses.VAULT || player == ContractAddresses.SDGNRS) {
                    emit PlayerSkipped(player, 3);
                    unchecked {
                        ++cursor;
                        ++processed;
                    }
                    continue;
                }
                sub.dailyQuantity = 0;
                _removeFromSet(player);
                emit SubscriptionExpired(player, 1);
                didWork = true;
                unchecked {
                    ++processed;
                }
                continue;
            }

            // (7) No local debit: the GAME's batchPurchase debits afkingFunding[b.funder] per
            // slice (D-01, funder = src). AfKing holds no ETH. Accumulate this player's slice for
            // the single batched purchase: ethValue is the fresh-ETH portion the GAME spends from
            // the funder's afkingFunding; the GAME draws the rest (cost - ethValue) from the
            // buyer's claimable per payKind. `amount` is ticket entry-units (isTicket) or a
            // lootbox spend in wei.
            buys[batchLen] = BatchBuy({
                funder: src,
                player: player,
                ethValue: ethValue,
                amount: amount,
                isTicket: isTicket,
                mode: uint8(payKind)
            });
            unchecked {
                ++batchLen;
            }

            // Day-stamp after accounting (CEI). The single batched purchase fires
            // after the loop; per-player isolation lives in batchPurchase's
            // per-slice try/catch.
            sub.lastAutoBoughtDay = today;

            unchecked {
                ++cursor;
                ++processed;
            }
        }

        // Persist the advanced cursor for the next (possibly concurrent) caller.
        _autoBuyCursor = uint224(cursor);

        // No buys: any committed set work (cancel-tombstone reclaim, auto-pause, window
        // renewal — `didWork`) persists; reverting would roll the removal back and strand
        // the tombstone for re-griefing. No buys means no purchase and no bounty — return
        // 0 (the router pays nothing, and doWork's NoWork() covers all-categories-empty).
        if (batchLen == 0) {
            emit AutoBuyCompleted(msg.sender, 0, 0);
            return 0;
        }

        // Single batched purchase (non-value call). Trim the buffer to the exact batch length;
        // the GAME debits each slice's ethValue from afkingFunding[funder] (atomic — a poisoned
        // slice rolls the whole batch back; no per-slice refund).
        if (batchLen != cap) {
            assembly {
                mstore(buys, batchLen)
            }
        }
        GAME.batchPurchase(buys);

        // Return the raw successful-buy count; the unified router (doWork) pays the flat
        // per-tx buy bounty (RD-4/D-07). This leg NEVER self-credits. Advance is the sole
        // stall epoch (invariant d) — the autoBuy stall ladder/absolute-day epoch is gone.
        emit AutoBuyCompleted(msg.sender, batchLen, 0);
        return batchLen;
    }

    /// @dev Per-player funding resolution for the _autoBuy loop: SUB-04 effective quantity
    ///      (max of dailyQuantity and the reinvest term) -> cost -> purchase mode + funding split.
    ///      GASOPT-03: reads the player's claimable AND afkingFunding ONCE via the extended
    ///      afkingSnapshot (per-player fallback — the swap-pop walk makes a pre-loop chunk batch
    ///      unsafe); claimable feeds the reinvest term + funding split, afkingFunding is the
    ///      common-path funding-skip source (one STATICCALL per player). Extracted as a helper so
    ///      its temporaries live in this frame (the _autoBuy loop is at the stack-depth limit).
    ///      View — no state writes.
    /// @return payKind Payment mode (DirectEth / Claimable / Combined) for the slice.
    /// @return ethValue Fresh-ETH portion debited from the funder's afkingFunding (0 in the pure-Claimable case).
    /// @return amount Ticket entry-units (isTicket) or lootbox spend in wei (!isTicket).
    /// @return isTicket True = buy `amount` ticket entry-units; false = buy an `amount`-wei lootbox.
    /// @return lootboxSkip True when a lootbox-mode sub is below LOOTBOX_MIN (transient skip).
    /// @return playerFunding The player's afkingFunding (the common-path funding-skip source; D-MR-01).
    function _resolveBuy(
        Sub storage sub,
        address player,
        uint256 mp
    )
        internal
        view
        returns (
            MintPaymentKind payKind,
            uint256 ethValue,
            uint256 amount,
            bool isTicket,
            bool lootboxSkip,
            uint256 playerFunding
        )
    {
        bool drainFirst = (sub.flags & FLAG_DRAIN_FIRST) != 0;
        // ONE afkingSnapshot staticcall per player yields BOTH the claimable (reinvest /
        // drainFirst funding split) AND the player's afkingFunding (the common-path funding-skip
        // source — D-MR-01; the src != player OPEN-E slice reads afkingFundingOf(src) separately).
        uint256 claimable;
        {
            address[] memory snap = new address[](1);
            snap[0] = player;
            (, , uint256[] memory cl, uint256[] memory kf) = GAME.afkingSnapshot(snap);
            claimable = cl[0];
            playerFunding = kf[0];
        }
        // Total quantity = max(dailyQuantity, reinvestPct% of claimable / price).
        uint256 effectiveQty = sub.dailyQuantity;
        if (sub.reinvestPct > 0) {
            uint256 reinvestQty = (claimable * sub.reinvestPct) / 100 / mp;
            if (reinvestQty > effectiveQty) effectiveQty = reinvestQty;
        }
        uint256 cost = mp * effectiveQty;

        // Mode routing. Ticket mode buys `effectiveQty` whole tickets (entry-units =
        // effectiveQty * TICKET_SCALE); lootbox mode buys a `cost`-wei box. LootboxFloor
        // transient skip (lootbox mode ONLY) — the sub stays in the set and retries next
        // autoBuy. Ticket mode needs no floor skip: one ticket is >= the ticket buy-in floor,
        // so a >= 1-ticket buy never underflows it.
        isTicket = (sub.flags & FLAG_USE_TICKETS) != 0;
        if (isTicket) {
            amount = effectiveQty * TICKET_SCALE;
        } else {
            if (cost < LOOTBOX_MIN) {
                lootboxSkip = true;
                return (payKind, ethValue, amount, isTicket, lootboxSkip, playerFunding);
            }
            amount = cost;
        }

        // Funding split (USER model): reinvestPct always spends that % of claimable; drainFirst is
        // a superset (claimable-first up to cost). The AfKing pool funds the remainder. Never spend
        // the entire claimable balance — leave >= 1 wei (the GAME's Claimable branch needs claimable
        // strictly > cost, and the claimable shortfall settle needs basis > shortfall).
        uint256 reinvestSpend = sub.reinvestPct > 0
            ? (claimable * sub.reinvestPct) / 100
            : 0;
        if (reinvestSpend > cost) reinvestSpend = cost;
        uint256 claimableUse = drainFirst
            ? (claimable < cost ? claimable : cost)
            : reinvestSpend;
        if (claimable > 0 && claimableUse >= claimable) claimableUse = claimable - 1;
        ethValue = cost - claimableUse;
        payKind = ethValue == 0
            ? MintPaymentKind.Claimable
            : (claimableUse == 0 ? MintPaymentKind.DirectEth : MintPaymentKind.Combined);
    }

    /*------------------------------------------------------------------
                          Unified afking router (doWork)
    ------------------------------------------------------------------*/
    /// @dev Buy-leg default batch. A landed afking buy is ~262k gas (the per-subscriber
    ///      worst-case marginal at the 0.5 gwei reference; buys cannot roll boons, so the
    ///      per-item cost is uniform), so 50 buys ≈ 13.1M stays under the 16.7M HARD per-tx
    ///      ceiling. Buys must NEVER exceed 16.7M (a reverting batch would brick the daily
    ///      buy leg), so the per-call buy count is HARD-bounded here.
    uint256 internal constant BUY_BATCH = 50;
    /// @dev Open-leg default batch (v50.0 WHALE-03 / Plan 335-06 — measurement-derived flat
    ///      per-box budget). Under WHALE-01 every box-open is uniform O(1) (the 100-iter
    ///      _activateWhalePass loop is retired; whale-pass writes the O(1) `whalePassClaims +=`
    ///      accumulator), so the gas-weighted budget is retired too — `maxCount` is now an
    ///      opened-count guard, not a gas-weighted unit count.
    ///      AfkingOpenBoxWorstCaseGas re-run during Plan 335-06 (post-v50 contract diff):
    ///        - per-box MARGINAL gas, N=32 isolated harness (autoOpen direct):       74_756
    ///        - per-box MARGINAL gas, N=32 router doWork harness:                    75_941
    ///        - single-box TOTAL at N=1 (isolated, overhead included):              113_875
    ///        - single-box TOTAL at N=1 (router doWork, overhead included):         125_939
    ///        - effective per-box from `testTypicalOpenBatchAveragesNineMillion`
    ///          (1-ETH lootbox fixture, OPEN_BATCH=220 trial, larger boons rolled):  76_866
    ///      The fixture-bound effective per-box (~77K) is HIGHER than the synthetic harness
    ///      measurement (~75K) because the typical-batch fixture uses 1-ETH first-deposit boxes
    ///      that roll real boons (extra writes per open), so the safe peg is ~77K. Pick formula
    ///      with the conservative effective per-box:
    ///        OPEN_BATCH = floor((16_700_000 − HEADROOM) / 76_866), HEADROOM = 125_939 (router
    ///        single-box TOTAL = 1 full box including doWork overhead).
    ///        floor((16_700_000 − 125_939) / 76_866) = floor(215.62) = 215.
    ///      Rounded down to 200 (nearest 50 floor of 215) for SAFE headroom against the typical-
    ///      batch fixture's effective per-box variance:
    ///        200 × 76_866 + 125_939 = 15_499_139 ≤ 16_700_000 ✓ (1_200_861 slack ≈ 15.6 boxes).
    ///      Uniform-O(1) tolerance check (D-02/D-04): under WHALE-01 the per-box cost is uniform
    ///      across whale-pass and non-whale-pass openers BY CONSTRUCTION (the `_activateWhalePass`
    ///      body is the same O(1) accumulator for every roll; the boon flag toggles `whalePassClaims`
    ///      not the loop count) — divergence = 0 < 25% ✓. The intra-fixture variance between bare-
    ///      harness 74_756 and router-fixture 76_866 is 2.8% (the doWork dispatch overhead +
    ///      afking-bound bookkeeping), well under the 25% uniformity bar. The 220 attempt failed
    ///      at 16_910_554 (= 220 × 76_866 + 38_034 ≈ 16.91M, 1.3% above ceiling) — D-IMPL-04
    ///      attestation requires a NON-FAILING `testTypicalOpenBatchAveragesNineMillion`, so 200
    ///      is the final pick.
    uint256 internal constant OPEN_BATCH = 200;
    /// @dev Advance reward ratio (2x * mult), pegged to the advance base marginal. The
    ///      1/2/4/6 stall ladder (advance-only) is the escalation lever; the ladder peak
    ///      (6x) is faucet-bounded and one-shot per day-advance.
    uint256 internal constant ADVANCE_RATIO_NUM = 2;
    /// @dev Buy reward ratio (flat 1.5x per tx = NUM/DEN), the frozen 329-SPEC D-07 ratio.
    ///      The buy is the most expensive per-item leg yet carries this flat 1.5x; it stays
    ///      round-trip ≤ 0 against the buy marginal at the deploy-param BOUNTY_ETH_TARGET.
    uint256 internal constant BUY_RATIO_NUM = 3;
    uint256 internal constant BUY_RATIO_DEN = 2;
    /// @dev Open reward pro-rate knee (1x at/above, pro-rated below): a mid-day open of
    ///      k < 5 boxes earns unit·k/5, so a single-box open earns 0.2x — below a one-box
    ///      tx's gas. This closes the small-batch self-crank corner (−EV below the knee).
    uint256 internal constant OPEN_KNEE = 5;

    /// @notice Unified permissionless afking router: do ONE category of pending work this
    ///         call (priority autoBuy -> advance -> autoOpen) and pay ONE flat-per-tx bounty.
    /// @dev ROUTER-01..06 — parameterless (each leg uses a fixed internal default batch).
    ///      RD-1 one-category STRUCTURAL early-return (invariant a): the rngLock-aware O(1)
    ///      predicates pick the first category with work; advance/buy/open bounties can never
    ///      stack in one tx. ROUTER-07: NO nonReentrant guard — afking-never-a-payee, every
    ///      external call is to a pinned ContractAddresses.* (GAME/COINFLIP), player value
    ///      flows through the game's claimable pull ledger, and the bounty is minted
    ///      flip-credit (never an ETH push the afking receives). The legs return raw
    ///      counts/mult and NEVER self-credit; only doWork credits, ONCE, CEI-last after the
    ///      one-category early-return. TST-02 (Phase 332) is the router->game->creditFlip
    ///      double-pay backstop proving this no-guard disposition.
    function doWork() external {
        uint256 mp = GAME.mintPrice();
        uint256 unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp;
        uint256 bountyEarned;

        // (1) autoBuy — highest priority (RD-1): subscriber buys queue at day-open,
        // pre-entropy, before advance requests the day's RNG. TRUE even during rngLock (RD-2).
        if (_autoBuyDay != _currentDay() || _autoBuyCursor < _subscribers.length) {
            uint256 bought = _autoBuy(BUY_BATCH);
            // Flat per-tx buy bounty (D-07) — NOT scaled by count (bounded once/day/sub).
            if (bought > 0) bountyEarned = (unit * BUY_RATIO_NUM) / BUY_RATIO_DEN;
        }
        // (2) advance — TRUE regardless of rngLock (liveness-critical).
        else if (GAME.advanceDue()) {
            uint8 mult = GAME.advanceGame();
            // Advance earns 2x * mult; mult == 0 (the gameover path) pays no bounty.
            if (mult > 0) bountyEarned = unit * ADVANCE_RATIO_NUM * mult;
        }
        // (3) autoOpen — FALSE during rngLock (RD-3); opens mid-day-resolved boxes.
        else if (GAME.boxesPending()) {
            uint256 opened = GAME.autoOpen(OPEN_BATCH);
            // 1x pro-rated below the knee, flat 1x at/above — kills the small-batch corner.
            uint256 k = opened < OPEN_KNEE ? opened : OPEN_KNEE;
            bountyEarned = (unit * k) / OPEN_KNEE;
        }
        // (4) ROUTER-06 — all 3 O(1) predicates empty: the clean no-work signal.
        else {
            revert NoWork();
        }

        // R4 — the single unified bounty: ONE creditFlip, CEI-LAST, after the one-category
        // early-return. Skipped at 0 (e.g. a buy chunk that walked only already-bought subs);
        // the category still ran, so we return rather than reverting NoWork().
        if (bountyEarned > 0) {
            COINFLIP.creditFlip(msg.sender, bountyEarned);
        }
    }

    /// @notice Standalone UNREWARDED manual/emergency buy clear — only doWork() credits.
    /// @param count Max subscribers to process this call (0 = the default batch).
    function autoBuy(uint256 count) external {
        _autoBuy(count);
    }

    /// @notice Standalone UNREWARDED manual/emergency open clear — only doWork() credits.
    /// @param count Max boxes to open this call.
    function autoOpen(uint256 count) external {
        GAME.autoOpen(count);
    }

    /*------------------------------------------------------------------
                          Internal helpers (hand-inlined OZ EnumerableSet)
    ------------------------------------------------------------------*/
    /// @dev Iterable set insert. Idempotent on already-in-set. 1-indexed
    ///      `_subscriberIndex` (0 = not in set). Not imported — keeps the slot
    ///      layout explicit.
    function _addToSet(address player) internal {
        if (_subscriberIndex[player] == 0) {
            _subscribers.push(player);
            _subscriberIndex[player] = _subscribers.length;
        }
    }

    /// @dev Iterable set remove via swap-and-pop. Idempotent on not-in-set.
    ///      1-indexed: move the last element into the vacated slot (and update its
    ///      index), pop the tail, clear the removed player's index. The autoBuy's
    ///      "no cursor-advance after swap-pop" pattern enforces iteration safety;
    ///      this helper is itself iteration-safe.
    function _removeFromSet(address player) internal {
        uint256 idxPlus1 = _subscriberIndex[player];
        if (idxPlus1 == 0) return; // not in set — silent no-op
        uint256 idx = idxPlus1 - 1;
        uint256 last = _subscribers.length - 1;
        if (idx != last) {
            address mover = _subscribers[last];
            _subscribers[idx] = mover;
            _subscriberIndex[mover] = idxPlus1; // mover takes the vacated 1-indexed slot
        }
        _subscribers.pop();
        delete _subscriberIndex[player];
    }

    /// @dev Afking-local day index. Offsets block.timestamp by 82620 seconds to
    ///      align with the protocol's 22:57 UTC day-rollover boundary, then divides
    ///      by 1 days. Single source of truth — never inlined at call sites.
    function _currentDay() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }
}
