// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "./ContractAddresses.sol";

/// @notice Payment method for ticket / lootbox purchases. File-scope mirror of
///         `contracts/interfaces/IDegenerusGame.sol` so the keeper's batched
///         purchase carries the `uint8` mode cast through `batchPurchase`.
enum MintPaymentKind {
    DirectEth, // Pay with fresh ETH only
    Claimable, // Pay with claimable winnings only
    Combined // Pay with both ETH and claimable
}

/// @title IGame
/// @notice Minimal owner-less call surface into the protocol GAME contract.
/// @dev Signatures match `contracts/DegenerusGame.sol` verbatim: `batchPurchase`
///      is the AF_KING-gated batched mint (the keeper is the sole authorized
///      caller); `hasAnyLazyPass` is the exposed lazy-pass view; the rest are the
///      operator-approval / pricing / claimable views the autoBuy reads. The keeper
///      holds NO immutable IGame field — every call site is inline
///      `IGame(ContractAddresses.GAME).foo()`.
interface IGame {
    function isOperatorApproved(address owner, address operator) external view returns (bool);

    function batchPurchase(
        address[] calldata players,
        uint256[] calldata amounts,
        uint8[] calldata modes
    ) external payable;

    function rngLocked() external view returns (bool);
    function mintPrice() external view returns (uint256);
    function claimableWinningsOf(address player) external view returns (uint256);
    function hasAnyLazyPass(address player) external view returns (bool);

    // Router-surface rows the doWork router calls on GAME (match DegenerusGame).
    function advanceGame() external returns (uint8 mult);
    function autoOpen(uint256 maxCount) external returns (uint256 opened);
    function advanceDue() external view returns (bool);
    function boxesPending() external view returns (bool);
    function keeperSnapshot(address[] calldata players) external view returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables);
}

/// @title IBurnie
/// @notice Minimal call surface into the protocol BURNIE coin for the keeper's
///         subscription charge.
/// @dev `burnForKeeper(user, amount) returns (uint256 burned)` matches
///      `contracts/BurnieCoin.sol` verbatim. ALL-OR-NOTHING: when the player's
///      spendable total (wallet balance + pending coinflip stake) cannot cover
///      `amount`, NOTHING is burned and 0 is returned. The charge is a pure sink
///      — burned BURNIE leaves supply; it is never transferred to the keeper, so
///      the keeper holds no BURNIE custody and runs no payment pool. The BurnieCoin
///      side gates `burnForKeeper` to `ContractAddresses.AF_KING` via `onlyAfKing`;
///      the keeper IS that pinned address and does not re-check.
interface IBurnie {
    function burnForKeeper(address user, uint256 amount) external returns (uint256 burned);
}

/// @title ICoinflip
/// @notice Minimal call surface into BurnieCoinflip for the autoBuy bounty.
/// @dev `creditFlip(player, amount)` matches `contracts/BurnieCoinflip.sol`
///      verbatim. The keeper earns its per-autoBuy bounty as deferred coinflip-stake
///      credit (a deferred mint — liquid BURNIE only mints when the caller later
///      claims), so no liquid BURNIE leaves the keeper and the bounty needs no
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
///        offset 0  uint8   dailyQuantity   — 0 = paused / never-subscribed (minimum 1 when active)
///        offset 1  uint32  lastAutoBoughtDay    — keeper-local day index of the last successful buy
///        offset 5  uint32  paidThroughDay  — 30-day rolling prepay window endpoint
///        offset 9  uint8   reinvestPct     — claimable reinvest percentage (0..100), 0 = no reinvest
///        offset 10 uint8   flags           — bit 0 = windowPaid, bit 1 = drainGameCreditFirst, bit 2 = useTickets
///        offset 11 address fundingSource   — wallet whose _poolOf ETH + BURNIE fund this sub; address(0) = self
///      Offset 31 is free padding. Storage slots 0-3 (the four state
///      mappings/array below) are pinned; this struct occupies a single slot
///      reached through `_subOf` at slot 1.
struct Sub {
    uint8 dailyQuantity;
    uint32 lastAutoBoughtDay;
    uint32 paidThroughDay;
    uint8 reinvestPct;
    uint8 flags;
    address fundingSource;
}

/// @title AfKing
/// @notice Permissionless, owner-less daily subscription keeper. Players (or
///         operator-approved third parties) subscribe to a daily ticket/lootbox
///         buy; anyone calls `autoBuy(maxCount)` to process the next chunk of
///         active subscribers and earns a gas-pegged bounty per successful player.
/// @dev No admin. No upgrade. No owner. No fallback. No multicall. `receive()` is
///      the only untyped entrypoint and credits msg.sender's pool. The keeper
///      holds NO immutable BURNIE/IGAME/ICOINFLIP references — every protocol call
///      is inline `IGame(ContractAddresses.GAME)` / `IBurnie(ContractAddresses.COIN)`
///      / `ICoinflip(ContractAddresses.COINFLIP)`. The constructor sets only the
///      three economic immutables with sanity reverts.
/// @custom:invariant Steady-state: sum(_poolOf) <= address(this).balance.
/// @custom:invariant No reentrancy guard — strict CEI everywhere; the keeper is
///                   never a payee in any contract it calls.
/// @custom:invariant Caller-scoped writes: every player-state mutator writes only
///                   to the resolved player's slot. The two-tier funding-skip
///                   exemption keys on the un-spoofable pinned
///                   `ContractAddresses.VAULT` / `SDGNRS` identity — there is no
///                   settable exemption flag.
contract AfKing {
    /*------------------------------------------------------------------
                              Custom errors
    ------------------------------------------------------------------*/
    /// @dev InsufficientBalance: withdraw(amount) with amount > _poolOf[msg.sender].
    error InsufficientBalance();
    /// @dev EthSendFailed: withdraw's low-level `.call{value: amount}("")` returned false.
    error EthSendFailed();
    /// @dev ZeroAddress: depositFor(address(0)).
    error ZeroAddress();
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
    /// @dev BurnieChargeFailed: subscribe paid-path got `burned != cost` back from
    ///      the all-or-nothing `burnForKeeper` — the player lacked sufficient
    ///      spendable BURNIE.
    error BurnieChargeFailed();
    /// @dev IndexOutOfBounds: subscriberAt(idx) with idx >= _subscribers.length.
    error IndexOutOfBounds();
    /// @dev NoWork: doWork() found no pending work in any category (all 3 O(1) predicates empty).
    error NoWork();

    /*------------------------------------------------------------------
                              Events
    ------------------------------------------------------------------*/
    /// @dev Single canonical credit stream — emitted by receive(), deposit(), depositFor().
    event Deposited(address indexed player, uint256 amount);
    /// @dev Withdrawal stream.
    event Withdrew(address indexed player, uint256 amount);
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
    ///        3 = InsufficientPool  (_poolOf[player] < msgValue) — funding skip
    ///        4 = LootboxFloor      (!useTickets && cost < LOOTBOX_MIN) — transient
    ///        5 = NotApproved       (operator-approval revoked or never granted)
    ///      lastAutoBoughtDay is UNCHANGED on a skip.
    event PlayerSkipped(address indexed player, uint8 reason);
    /// @dev Emitted once at the end of each successful autoBuy, after the bounty payout.
    event AutoBuyCompleted(address indexed caller, uint256 successfulPlayers, uint256 bountyEarned);
    /// @dev Day-31 PAID auto-extract — emitted after `burnForKeeper` succeeds and
    ///      paidThroughDay is written.
    event BurnieAutoExtracted(address indexed player, uint32 day, uint256 burnieAmount);
    /// @dev Day-31 FREE active-pass auto-extend — emitted after paidThroughDay is reset.
    event SubscriptionExtendedFree(address indexed player, uint32 day);
    /// @dev Subscription removed from the iterable set. `reason`:
    ///        1 = AutoPause (day-31 burnForKeeper shortfall OR funding-skip kill of a NORMAL sub)
    ///        2 = CancelReclaim (in-autoBuy reclaim of an externally-cancelled `dailyQuantity == 0` tombstone)
    event SubscriptionExpired(address indexed player, uint8 reason);

    /*------------------------------------------------------------------
                              State (4-slot layout pinned)
    ------------------------------------------------------------------*/
    /// @dev Slot 0 — per-player ETH pool credits/debits.
    mapping(address => uint256) private _poolOf; // slot 0

    /// @dev Slot 1 — per-player subscription record (file-scope Sub struct).
    mapping(address => Sub) private _subOf; // slot 1

    /// @dev Slot 2 — insertion-ordered iterable subscriber set (length here,
    ///      elements at keccak256(2)+i).
    address[] private _subscribers; // slot 2

    /// @dev Slot 3 — 1-indexed subscriber index (0 = not in set). Hand-inlined OZ
    ///      EnumerableSet pattern.
    mapping(address => uint256) private _subscriberIndex; // slot 3

    /// @dev AutoBuy progress cursor + the keeper-local day it belongs to, packed in
    ///      a single slot. `_autoBuyDay` stamps which day `_autoBuyCursor` indexes;
    ///      on the first autoBuy of a new day the cursor resets to 0. The cursor
    ///      advances monotonically within a day so concurrent same-block callers
    ///      self-partition (a later tx reads the earlier tx's advanced cursor and
    ///      takes the next chunk). The per-entry `lastAutoBoughtDay` day-stamp is the
    ///      idempotency backstop against any double-buy.
    uint32 private _autoBuyDay; // slot 4 (offset 0)
    uint224 private _autoBuyCursor; // slot 4 (offset 4)

    /*------------------------------------------------------------------
                              Constants
    ------------------------------------------------------------------*/
    /// @dev Rolling prepay window length in days. Not configurable post-deploy.
    uint32 internal constant WINDOW_DAYS = 30;

    /// @dev Keeper-local ticket scaling multiplier. TICKET_SCALE = 400 makes the
    ///      cost formula unit-consistent across modes: 400 * dailyQuantity *
    ///      mintPrice / 400 == mintPrice * dailyQuantity, so one dailyQuantity
    ///      unit resolves to exactly one mintPrice worth of spend in both ticket
    ///      and lootbox mode.
    uint256 internal constant TICKET_SCALE = 400;

    /// @dev BURNIE-per-ETH conversion unit, sourced verbatim from the protocol
    ///      (`DegenerusGameAdvanceModule` / `BurnieCoinflip` PRICE_COIN_UNIT). The
    ///      three ETH-target call sites convert to live BURNIE via
    ///      `(ethTarget * PRICE_COIN_UNIT) / mintPrice()`.
    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev windowPaid flag bit within Sub.flags. Set on a successful day-31
    ///      `burnForKeeper`; cleared on the free active-pass extend. Gates the
    ///      SUB-07 `_subOf` reclaim — a paid, unexpired window is preserved on
    ///      cancel; a free or expired window is deleted.
    uint8 internal constant FLAG_WINDOW_PAID = 1;

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
                          ETH ingress
    ------------------------------------------------------------------*/
    /// @notice Bare receive() — credits msg.sender's pool by msg.value. Zero-value
    ///         is a silent no-op (no event). Writes effects only; no outgoing call.
    receive() external payable {
        if (msg.value == 0) return;
        _poolOf[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Credit msg.sender's pool by msg.value. Silent no-op on zero.
    function deposit() external payable {
        if (msg.value == 0) return;
        _poolOf[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Credit `player`'s pool by msg.value. Reverts ZeroAddress on
    ///         player == 0 regardless of msg.value; silent no-op on zero value.
    ///         The Deposited event carries the credited `player`, not msg.sender.
    function depositFor(address player) external payable {
        if (player == address(0)) revert ZeroAddress();
        if (msg.value == 0) return;
        _poolOf[player] += msg.value;
        emit Deposited(player, msg.value);
    }

    /*------------------------------------------------------------------
                          Pool egress
    ------------------------------------------------------------------*/
    /// @notice Debit caller's pool by `amount` and send ETH to caller via CEI. No
    ///         reentrancy guard — effects-before-interactions makes a re-entrant
    ///         second call revert InsufficientBalance, which surfaces as
    ///         EthSendFailed on the outer frame and unwinds the pool debit.
    function withdraw(uint256 amount) external {
        if (amount == 0) return;
        uint256 bal = _poolOf[msg.sender];
        if (amount > bal) revert InsufficientBalance();

        unchecked {
            _poolOf[msg.sender] = bal - amount;
        }

        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert EthSendFailed();

        emit Withdrew(msg.sender, amount);
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
    /// @dev SUB-01 pass-OR-pay gate fires LAST (CEI: effects first, interaction
    ///      last). Active lazy pass (`IGame.hasAnyLazyPass(player)`) → free 30-day
    ///      extend-from-endpoint with no charge, and windowPaid is CLEARED (the
    ///      window is free, nothing to preserve on a later cancel). No pass →
    ///      all-or-nothing `burnForKeeper` charge; on a full burn windowPaid is
    ///      SET, on a shortfall the whole call reverts BurnieChargeFailed.
    /// @dev msg.value > 0 always credits the resolved player's pool via the
    ///      canonical Deposited event before the pass gate; msg.value never
    ///      participates in the BURNIE cost.
    /// @param player Subscriber to act for (0 or msg.sender = self).
    /// @param drainGameCreditFirst When true, the autoBuy spends protocol-side
    ///        claimable credit before tapping pool ETH.
    /// @param useTickets Mint mode — true = tickets, false = lootboxes.
    /// @param dailyQuantity Daily buy units, 1..255. MUST be non-zero; zero is the
    ///        paused sentinel handled by setDailyQuantity(0).
    /// @param reinvestPct Claimable reinvest percentage, 0..100. The effective
    ///        daily buy is max(dailyQuantity, floor(claimable * reinvestPct / price)).
    /// @param fundingSource Wallet whose `_poolOf` ETH and BURNIE fund this
    ///        subscription's keeper spends — the first-window SUB-01 burn, the
    ///        day-31 auto-extract burn, and the per-day ETH draw all resolve to
    ///        this address. `address(0)` = self. A non-zero, non-self source is
    ///        honored ONLY when it has operator-approved the subscriber on the
    ///        game (`IGame.isOperatorApproved(fundingSource, subscriber)`),
    ///        checked at subscribe() ONLY — never at the day-31 renewal, never
    ///        per-draw.
    /// @dev Subscribe-time auth only: a later `setOperatorApproval(subscriber,
    ///      false)` by the source does NOT stop an active sub — the renewal trusts
    ///      the stored source and keeps drawing/burning it. The source halts draws
    ///      by defunding (`withdraw()` its pool / spending down BURNIE); the
    ///      subscriber halts by cancelling; re-pointing the source means
    ///      re-subscribing (which re-checks). BURNIE blast-radius caveat: the same
    ///      approval also authorizes burning the source's general-wallet BURNIE and
    ///      pending coinflip — sharper than the pre-funded ETH escrow; the named
    ///      deferred tighter alternative is a dedicated `allowBurnieFunding[S][M]`.
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
            if (!IGame(ContractAddresses.GAME).isOperatorApproved(subscriber, msg.sender)) {
                revert NotApproved();
            }
        }

        // OPENE-04 — a non-zero, non-self fundingSource must have operator-approved
        // the subscriber on the game. address(0) (self) short-circuits the read;
        // checked HERE only — the renewal and per-draw paths never re-check.
        if (
            fundingSource != address(0) &&
            fundingSource != subscriber &&
            !IGame(ContractAddresses.GAME).isOperatorApproved(fundingSource, subscriber)
        ) {
            revert NotApproved();
        }

        // msg.value > 0 credits the subscriber's pool. Effects-first CEI; never
        // participates in the BURNIE cost.
        if (msg.value > 0) {
            _poolOf[subscriber] += msg.value;
            emit Deposited(subscriber, msg.value);
        }

        Sub storage s = _subOf[subscriber];
        uint32 today = _currentDay();

        // Extend-from-endpoint: anchor = max(paidThroughDay, today); new endpoint
        // = anchor + WINDOW_DAYS.
        uint32 anchor = s.paidThroughDay > today ? s.paidThroughDay : today;

        s.dailyQuantity = dailyQuantity;
        if (drainGameCreditFirst) s.flags |= FLAG_DRAIN_FIRST;
        else s.flags &= ~FLAG_DRAIN_FIRST;
        if (useTickets) s.flags |= FLAG_USE_TICKETS;
        else s.flags &= ~FLAG_USE_TICKETS;
        s.reinvestPct = reinvestPct;
        s.paidThroughDay = anchor + WINDOW_DAYS;
        s.fundingSource = fundingSource;

        _addToSet(subscriber);
        emit SubscriptionUpdated(subscriber, dailyQuantity, drainGameCreditFirst, useTickets, reinvestPct, s.fundingSource);

        // SUB-01 pass-OR-pay gate (interaction last). Active pass → free extend,
        // clear windowPaid. No pass → all-or-nothing burn, set windowPaid.
        if (IGame(ContractAddresses.GAME).hasAnyLazyPass(subscriber)) {
            s.flags &= ~FLAG_WINDOW_PAID;
        } else {
            uint256 mp = IGame(ContractAddresses.GAME).mintPrice();
            uint256 cost = (SUB_COST_ETH_TARGET * PRICE_COIN_UNIT) / mp;
            uint256 burned = IBurnie(ContractAddresses.COIN).burnForKeeper(
                s.fundingSource == address(0) ? subscriber : s.fundingSource,
                cost
            );
            if (burned != cost) revert BurnieChargeFailed();
            s.flags |= FLAG_WINDOW_PAID;
        }
    }

    /// @notice Update caller's daily buy units. q == 0 is the in-place tombstone
    ///         cancel (writes the sentinel, relocates no one); q > 0 reactivates
    ///         in place.
    /// @dev SUB-07 tombstone-on-cancel: cancel only writes `dailyQuantity = 0` (the
    ///      "paused" sentinel) and leaves the entry in the iterable set — it moves
    ///      nothing, so it can never relocate an unprocessed entry behind the chunked
    ///      autoBuy cursor. The `_subOf` record stays readable; the delete-vs-preserve
    ///      decision (keep the paid window iff windowPaid set AND paidThroughDay >
    ///      today, else delete) is applied by the in-autoBuy reclaim when the autoBuy
    ///      reaches the tombstone. Reactivation (q > 0) flips the sentinel back in
    ///      place with no set churn (the entry never left the set). Stranded
    ///      `_poolOf` ETH always stays withdrawable.
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
    /// @notice Return `player`'s current pool balance. Never reverts.
    function poolOf(address player) external view returns (uint256) {
        return _poolOf[player];
    }

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

    /// @notice Current autoBuy cursor and the keeper-local day it indexes.
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
    ///      of a new keeper-local day the cursor resets to 0.
    /// @dev RD-2 — the buy path carries NO rngLock guard (buys are freeze-safe by
    ///      construction; a box queues at the current LR_INDEX, pre-entropy, and the
    ///      orphan hazard is defended on the resolution side via the autoOpen word-gate).
    /// @dev Per-player ladder: (1) AlreadyAutoBoughtToday skip; (2) day-31 auto-extract
    ///      (free pass-extend OR all-or-nothing burnForKeeper, auto-pause on
    ///      shortfall); (3) cost + mode + payKind funding waterfall (claimable read once
    ///      via keeperSnapshot, GASOPT-03); (4) LootboxFloor transient skip; (5)
    ///      InsufficientPool — NORMAL sub is CANCELLED via swap-pop (two-tier kill),
    ///      Vault/sDGNRS are EXEMPT (no-op-and-retry) by pinned identity; (6) CEI debit +
    ///      day-stamp. The batched `IGame.batchPurchase` call carries one slice per
    ///      successful player and fires once after the per-player accounting loop; CEI
    ///      debit happens before the batched call, day-stamp after.
    /// @dev No try/catch and no `nonReentrant` guard. Per-player batch isolation
    ///      lives in the game's `batchPurchase` (per-slice try/catch + slice
    ///      refund); the keeper preserves strict CEI.
    /// @param maxCount Maximum number of un-autoBought active entries to process this
    ///        call. 0 = use the default batch (DOWORK_BATCH). Caller-bounded (no
    ///        contract-bounded loop) — the anti-gas-DoS property.
    /// @return boughtCount Number of successful per-player buys this chunk.
    function _autoBuy(uint256 maxCount) internal returns (uint256 boughtCount) {
        if (maxCount == 0) maxCount = DOWORK_BATCH;

        uint32 today = _currentDay();
        uint256 mp = IGame(ContractAddresses.GAME).mintPrice();

        // Daily cursor reset: the first autoBuy of a new keeper-local day restarts
        // the cursor at 0. Within a day the cursor advances monotonically so
        // concurrent callers self-partition.
        uint256 cursor = _autoBuyDay == today ? uint256(_autoBuyCursor) : 0;
        if (_autoBuyDay != today) {
            _autoBuyDay = today;
        }

        // Per-chunk accumulation buffers. The batched purchase fires once, after the
        // per-player accounting loop, with one slice per successful player.
        uint256 cap = maxCount;
        address[] memory players = new address[](cap);
        uint256[] memory amounts = new uint256[](cap);
        uint8[] memory modes = new uint8[](cap);
        uint256 batchLen;
        uint256 totalValue;
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
            // entry behind the cursor. The reclaim applies the deferred
            // delete-vs-preserve (keep `_subOf` with the sentinel iff the window is
            // paid and unexpired, else delete), swap-pops it out of the set, and
            // continues WITHOUT advancing the cursor — the swap-pop occupant (a
            // mover from ahead, hence still pending) is processed at this slot this
            // autoBuy. Ordered ahead of the AlreadyAutoBoughtToday skip so a tombstone is
            // ALWAYS reclaimed (never left as a permanent dead slot), independent of
            // its `lastAutoBoughtDay`.
            if (sub.dailyQuantity == 0) {
                bool preservePaidWindow = (sub.flags & FLAG_WINDOW_PAID) != 0 && sub.paidThroughDay > today;
                if (!preservePaidWindow) {
                    delete _subOf[player];
                }
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

            // (2) Day-31 auto-extract branch. The hasAnyLazyPass view fires only here.
            if (sub.paidThroughDay <= today) {
                if (IGame(ContractAddresses.GAME).hasAnyLazyPass(player)) {
                    // FREE active-pass extend — held-harmless reset; clear windowPaid.
                    sub.paidThroughDay = today + WINDOW_DAYS;
                    sub.flags &= ~FLAG_WINDOW_PAID;
                    emit SubscriptionExtendedFree(player, today);
                    didWork = true;
                } else {
                    // PAID branch — all-or-nothing burnForKeeper. On shortfall the
                    // burn took nothing, so there is nothing to refund; auto-pause.
                    uint256 extractCost = (SUB_COST_ETH_TARGET * PRICE_COIN_UNIT) / mp;
                    uint256 burned = IBurnie(ContractAddresses.COIN).burnForKeeper(
                        sub.fundingSource == address(0) ? player : sub.fundingSource,
                        extractCost
                    );
                    if (burned != extractCost) {
                        // Auto-pause: sentinel write, swap-pop, emit, continue
                        // WITHOUT advancing the cursor (the swap-pop occupant at
                        // this slot must be processed this autoBuy). windowPaid clears.
                        sub.dailyQuantity = 0;
                        sub.flags &= ~FLAG_WINDOW_PAID;
                        _removeFromSet(player);
                        emit SubscriptionExpired(player, 1);
                        didWork = true;
                        unchecked {
                            ++processed;
                        }
                        continue;
                    }
                    // PAID success — held-harmless reset; set windowPaid.
                    sub.paidThroughDay = today + WINDOW_DAYS;
                    sub.flags |= FLAG_WINDOW_PAID;
                    emit BurnieAutoExtracted(player, today, extractCost);
                    didWork = true;
                }
            }

            // (GASOPT-05) The per-iteration isOperatorApproved(player, this) check is
            // removed — the SUB is the consent unit (revoke = setDailyQuantity(0) →
            // tombstone-skip); the retained funding-consent boundary is the
            // subscribe-time isOperatorApproved(fundingSource, subscriber) gate.

            // SUB-04 funding resolution (cost + payment mode + msg.value slice). Extracted
            // to _resolveBuy so its temporaries (claimable / effectiveQty / cred + the
            // keeperSnapshot scratch) live in that frame, not this loop's — the loop is at
            // the stack-depth limit. GASOPT-03: ONE keeperSnapshot read per player.
            (
                MintPaymentKind payKind,
                uint256 msgValue,
                bool lootboxSkip
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

            // (6) InsufficientPool funding skip → two-tier skip-kill. A NORMAL sub
            // is CANCELLED via swap-pop (auto-pause WITHOUT advancing the cursor —
            // the mover at this slot is processed this autoBuy). Vault + sDGNRS are
            // EXEMPT by the un-spoofable pinned ContractAddresses.VAULT / SDGNRS
            // identity — a funding skip is transient for them (no-op-and-retry,
            // stays in the set). The exemption is the pinned-address branch only;
            // there is no settable exemption flag.
            if (_poolOf[src] < msgValue) {
                if (player == ContractAddresses.VAULT || player == ContractAddresses.SDGNRS) {
                    emit PlayerSkipped(player, 3);
                    unchecked {
                        ++cursor;
                        ++processed;
                    }
                    continue;
                }
                sub.dailyQuantity = 0;
                sub.flags &= ~FLAG_WINDOW_PAID;
                _removeFromSet(player);
                emit SubscriptionExpired(player, 1);
                didWork = true;
                unchecked {
                    ++processed;
                }
                continue;
            }

            // (7) CEI debit BEFORE the batched external call. Unchecked safe: the
            // line above guarantees _poolOf[src] >= msgValue.
            unchecked {
                _poolOf[src] -= msgValue;
            }

            // Accumulate this player's slice for the single batched purchase. The
            // game-side _batchPurchaseUnit forwards the per-player msg.value slice
            // into the mint module, so the slice IS the per-player cost.
            players[batchLen] = player;
            amounts[batchLen] = msgValue;
            modes[batchLen] = uint8(payKind);
            unchecked {
                ++batchLen;
                totalValue += msgValue;
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

        // Single batched purchase. Trim the buffers to the exact batch length so
        // the game's length-equality guard (players.length == amounts.length ==
        // modes.length) holds.
        if (batchLen != cap) {
            assembly {
                mstore(players, batchLen)
                mstore(amounts, batchLen)
                mstore(modes, batchLen)
            }
        }
        IGame(ContractAddresses.GAME).batchPurchase{value: totalValue}(players, amounts, modes);

        // Return the raw successful-buy count; the unified router (doWork) pays the flat
        // per-tx buy bounty (RD-4/D-07). This leg NEVER self-credits. Advance is the sole
        // stall epoch (invariant d) — the autoBuy stall ladder/absolute-day epoch is gone.
        emit AutoBuyCompleted(msg.sender, batchLen, 0);
        return batchLen;
    }

    /// @dev Per-player funding resolution for the _autoBuy loop: SUB-04 effective quantity
    ///      (max of dailyQuantity and the reinvest term) -> cost -> payment mode + msg.value
    ///      slice. GASOPT-03: reads the player's claimable ONCE via keeperSnapshot (per-player
    ///      fallback — the swap-pop walk makes a pre-loop chunk batch unsafe), reused by the
    ///      reinvest term AND the drain-first waterfall (identical value, one STATICCALL
    ///      instead of up to two). Extracted as a helper so its temporaries live in this frame
    ///      (the _autoBuy loop is at the stack-depth limit). View — no state writes.
    /// @return payKind Payment mode for the batched purchase slice.
    /// @return msgValue ETH-wei slice forwarded for this player (0 in the Claimable case).
    /// @return lootboxSkip True when a lootbox-mode sub is below LOOTBOX_MIN (transient skip).
    function _resolveBuy(
        Sub storage sub,
        address player,
        uint256 mp
    )
        internal
        view
        returns (MintPaymentKind payKind, uint256 msgValue, bool lootboxSkip)
    {
        bool drainFirst = (sub.flags & FLAG_DRAIN_FIRST) != 0;
        uint256 claimable;
        if (sub.reinvestPct > 0 || drainFirst) {
            address[] memory snap = new address[](1);
            snap[0] = player;
            (, , uint256[] memory cl) = IGame(ContractAddresses.GAME).keeperSnapshot(snap);
            claimable = cl[0];
        }
        uint256 effectiveQty = sub.dailyQuantity;
        if (sub.reinvestPct > 0) {
            uint256 reinvestQty = (claimable * sub.reinvestPct) / 100 / mp;
            if (reinvestQty > effectiveQty) effectiveQty = reinvestQty;
        }
        uint256 cost = mp * effectiveQty;

        // LootboxFloor transient skip (lootbox mode only) — stays in the set, retries next
        // autoBuy. Signalled out; the waterfall is skipped for it.
        if ((sub.flags & FLAG_USE_TICKETS) == 0 && cost < LOOTBOX_MIN) {
            lootboxSkip = true;
        } else if (!drainFirst) {
            payKind = MintPaymentKind.DirectEth;
            msgValue = cost;
        } else {
            // Drain-first funding waterfall — preserved byte-faithfully.
            uint256 cred = claimable;
            if (cred > cost) {
                payKind = MintPaymentKind.Claimable;
                msgValue = 0;
            } else if (cred > 1) {
                payKind = MintPaymentKind.Combined;
                unchecked {
                    msgValue = cost - (cred - 1);
                }
            } else {
                payKind = MintPaymentKind.DirectEth;
                msgValue = cost;
            }
        }
    }

    /*------------------------------------------------------------------
                          Unified keeper router (doWork)
    ------------------------------------------------------------------*/
    /// @dev GAS-331 PLACEHOLDER — fixed per-leg default batch (the prior caller-bounded
    ///      default). Calibrated under the USER-gated GAS phase (331), NOT locked here.
    uint256 internal constant DOWORK_BATCH = 100;
    /// @dev GAS-331 PLACEHOLDER — advance reward ratio (2x * mult). Calibrated at GAS (331).
    uint256 internal constant ADVANCE_RATIO_NUM = 2;
    /// @dev GAS-331 PLACEHOLDER — buy reward ratio (flat 1.5x per tx = NUM/DEN). At GAS (331).
    uint256 internal constant BUY_RATIO_NUM = 3;
    uint256 internal constant BUY_RATIO_DEN = 2;
    /// @dev GAS-331 PLACEHOLDER — open reward pro-rate knee (1x at/above, pro-rated below).
    uint256 internal constant OPEN_KNEE = 5;

    /// @notice Unified permissionless keeper router: do ONE category of pending work this
    ///         call (priority autoBuy -> advance -> autoOpen) and pay ONE flat-per-tx bounty.
    /// @dev ROUTER-01..06 — parameterless (each leg uses a fixed internal default batch).
    ///      RD-1 one-category STRUCTURAL early-return (invariant a): the rngLock-aware O(1)
    ///      predicates pick the first category with work; advance/buy/open bounties can never
    ///      stack in one tx. ROUTER-07: NO nonReentrant guard — keeper-never-a-payee, every
    ///      external call is to a pinned ContractAddresses.* (GAME/COINFLIP), player value
    ///      flows through the game's claimable pull ledger, and the bounty is minted
    ///      flip-credit (never an ETH push the keeper receives). The legs return raw
    ///      counts/mult and NEVER self-credit; only doWork credits, ONCE, CEI-last after the
    ///      one-category early-return. TST-02 (Phase 332) is the router->game->creditFlip
    ///      double-pay backstop proving this no-guard disposition.
    function doWork() external {
        uint256 mp = IGame(ContractAddresses.GAME).mintPrice();
        uint256 unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp;
        uint256 bountyEarned;

        // (1) autoBuy — highest priority (RD-1): subscriber buys queue at day-open,
        // pre-entropy, before advance requests the day's RNG. TRUE even during rngLock (RD-2).
        if (_autoBuyDay != _currentDay() || _autoBuyCursor < _subscribers.length) {
            uint256 bought = _autoBuy(DOWORK_BATCH);
            // Flat per-tx buy bounty (D-07) — NOT scaled by count (bounded once/day/sub).
            if (bought > 0) bountyEarned = (unit * BUY_RATIO_NUM) / BUY_RATIO_DEN;
        }
        // (2) advance — TRUE regardless of rngLock (liveness-critical).
        else if (IGame(ContractAddresses.GAME).advanceDue()) {
            uint8 mult = IGame(ContractAddresses.GAME).advanceGame();
            // Advance earns 2x * mult; mult == 0 (the gameover path) pays no bounty.
            if (mult > 0) bountyEarned = unit * ADVANCE_RATIO_NUM * mult;
        }
        // (3) autoOpen — FALSE during rngLock (RD-3); opens mid-day-resolved boxes.
        else if (IGame(ContractAddresses.GAME).boxesPending()) {
            uint256 opened = IGame(ContractAddresses.GAME).autoOpen(DOWORK_BATCH);
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
            ICoinflip(ContractAddresses.COINFLIP).creditFlip(msg.sender, bountyEarned);
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
        IGame(ContractAddresses.GAME).autoOpen(count);
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

    /// @dev Keeper-local day index. Offsets block.timestamp by 82620 seconds to
    ///      align with the protocol's 22:57 UTC day-rollover boundary, then divides
    ///      by 1 days. Single source of truth — never inlined at call sites.
    function _currentDay() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }
}
