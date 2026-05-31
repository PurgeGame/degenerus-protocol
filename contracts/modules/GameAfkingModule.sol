// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusGameLootboxModule, IDegenerusGameMintModule} from "../interfaces/IDegenerusGameModules.sol";

/// @title IGameRouter
/// @notice Minimal in-context self-call surface the router uses to reach the
///         Game-proper advance entrypoint. The router runs in the Game's storage
///         context (delegatecall), so `address(this)` IS the Game;
///         the self-call re-enters the Game's own `advanceGame` dispatch (which
///         delegatecalls the AdvanceModule, running the required-path process STAGE
///         in-context — 349-05). Signatures match `DegenerusGame.sol` verbatim
///         (`advanceGame` :275 / `advanceDue` :1690). `mintPrice` / `level` are read
///         in-context (inherited helpers), so they are NOT routed through here.
interface IGameRouter {
    function advanceGame() external returns (uint8 mult);
    function advanceDue() external view returns (bool);
}

/**
 * @title GameAfkingModule
 * @author Burnie Degenerus
 * @notice Delegate-called module owning the AfKing subscription logic. Its bytecode
 *         is its OWN EIP-170 budget — 0 B to the DegenerusGame image — so the
 *         running-total is unaffected by this module.
 *
 * @dev DELEGATECALL CONTEXT: the module inherits `DegenerusGameStorage` (via
 *      `DegenerusGameMintStreakUtils`), so the subscriber set
 *      (`_subOf`/`_subscribers`/`_subscriberIndex`), the cursors
 *      (`_subCursor`/`_subOpenCursor`), the `subsFullyProcessed` STAGE
 *      drain-completion flag, the `afkingFunding` ledger, `claimablePool`, `operatorApprovals`,
 *      and the activity-score helpers are all in-context plain SLOADs/SSTOREs.
 *      The operator-approval / pass-horizon / afking-snapshot / afking-funding
 *      reads are all in-context here (the established module pattern — cf.
 *      `DegenerusGameBingoModule` reading `operatorApprovals` directly). The Game
 *      reaches these via its delegatecall dispatch stubs; a direct call to this
 *      module address would have the wrong `msg.sender` for any Game-context
 *      invariant.
 *
 * @dev PART A: `subscribe` — the SINGLE consent-gated subscription
 *      entrypoint (create / replace / cancel) carrying the CONSENT-01 OPEN-E gates
 *      verbatim + the FREEZE-01 rngLock guard + the 500 active-sub cap guard — and
 *      the REQUIRED-PATH PROCESS
 *      STAGE (the chunked pre-RNG stamp pass the AdvanceModule STAGE drives across
 *      the set, 349-05).
 * @dev PART B (this plan, 349-04, same file): the post-RNG OPEN-PASS (the
 *      afking-stamp open leg, driven by `_subOpenCursor`, materializing each box
 *      from its frozen stamp via a delegatecall to the LootboxModule's
 *      `resolveAfkingBox` — the FROZEN-INPUT twin of `resolveLootboxDirect`) and
 *      the ROUTER (`mintBurnie`/`autoBuy`/`autoOpen`, the one-category early-return
 *      dispatch). The open consumes the stamp the PART-A process STAGE produces.
 * @dev PLACE-02 bounty: the buy/process bounty FOLDS INTO the advance bounty
 *      (`mintBurnie`'s advance leg pays `2×·mult`, scaling the AdvanceModule's
 *      day-epoch stall `mult` 2×/4×/6× — the process STAGE rides it); the OPEN
 *      stays a NORMAL post-RNG `OPEN_BATCH`-style router category with the
 *      `OPEN_KNEE` work-scaled pro-rate (farm-by-splitting resistant). Payment is
 *      the deferred `creditFlip` BURNIE flip-credit (never a transfer / mintForGame).
 *
 * @custom:invariant No reentrancy guard — strict CEI everywhere; the module is
 *                   never a payee. The two-tier funding-skip exemption keys on
 *                   the un-spoofable pinned `ContractAddresses.VAULT` / `SDGNRS`
 *                   identity (on `player`, never `src`) — no settable exemption.
 * @custom:invariant NO error-swallowing valve anywhere (D-348-04 / REVERT-02
 *                   no-valve): the funded process buy is revert-free by
 *                   construction (obligation 1 — REVERT-01); a class-B solvency
 *                   underflow FAILS LOUD (the `claimablePool -=` propagates, it is
 *                   never swallowed). There is no try-block / handler pair.
 */
contract GameAfkingModule is DegenerusGameMintStreakUtils {
    /*------------------------------------------------------------------
                              Custom errors
    ------------------------------------------------------------------*/
    // error RngLocked() — inherited from DegenerusGameStorage. Reverts a
    // subscribe (create / replace / cancel) attempted during the RNG freeze
    // window: the subscriber set must be frozen across [request -> unlock].
    /// @dev subscribe with reinvestPct > 100 (a percentage).
    error InvalidReinvestPct();
    /// @dev Third-party subscribe(player, ...) where the caller is neither the
    ///      player nor a game operator the player approved; OR a non-zero,
    ///      non-self fundingSource that has not operator-approved the subscriber.
    error NotApproved();
    /// @dev subscribe(_, 0) cancel where the caller has no active subscription
    ///      (nothing to tombstone).
    error NotSubscribed();
    /// @dev subscribe would grow the active subscriber set past the uint16 cursor
    ///      cap (65,535). NEW-subscriber path only — re-subscribe never trips it.
    error SubscriberCapReached();
    /// @dev mintBurnie() found all router categories empty — the clean no-work signal
    ///      (ROUTER-06; the unbounded-scan-free early-return on no pending work).
    error NoWork();

    /*------------------------------------------------------------------
                              Events
    ------------------------------------------------------------------*/
    /// @dev Single canonical subscription-state stream — POST-WRITE full state.
    ///      Cancel (subscribe(_, 0)) emits with dailyQuantity == 0.
    ///      `fundingSource` is the stored funding wallet (address(0) = self);
    ///      indexed so a source can filter the log for every account it funds.
    event SubscriptionUpdated(
        address indexed player,
        uint8 dailyQuantity,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 reinvestPct,
        address indexed fundingSource
    );
    /// @dev Per-player pre-check skip inside the process pass. `reason`:
    ///        2 = AlreadyAutoBoughtToday (sub.lastAutoBoughtDay >= today)
    ///        3 = InsufficientPool  (afkingFunding[src] < ethValue) — funding skip
    ///      lastAutoBoughtDay is UNCHANGED on a skip.
    event PlayerSkipped(address indexed player, uint8 reason);
    /// @dev Pass-validity refresh — emitted at the AFSUB-03 crossing branch when
    ///      the re-read horizon still covers the current level. Writes the new
    ///      validThroughLevel and continues without eviction.
    event SubscriptionExtendedFree(address indexed player, uint32 day);
    /// @dev Subscription removed from the iterable set. `reason`:
    ///        1 = AutoPause (AFSUB-03 pass-eviction at crossing OR funding-skip kill of a NORMAL sub)
    ///        2 = CancelReclaim (in-pass reclaim of an externally-cancelled tombstone)
    event SubscriptionExpired(address indexed player, uint8 reason);

    /*------------------------------------------------------------------
                              Constants
    ------------------------------------------------------------------*/
    /// @dev Afking-local ticket scaling multiplier. TICKET_SCALE = 400 makes the
    ///      cost formula unit-consistent: a ticket `amount = effectiveQty * 400`
    ///      entry-units, which the Game's mint recompute divides by `4 * 100`
    ///      (the inherited Storage `TICKET_SCALE = 100`), so `cost` stays
    ///      `mintPrice * effectiveQty` in both ticket and lootbox mode.
    ///      ⚠ 348-INVARIANT-CARRY §3-i (LOAD-BEARING dual constant): this 400 is
    ///      NUMERICALLY EQUAL to the Game's `4 * TICKET_SCALE` (= 4 × 100) but is a
    ///      DISTINCT named constant — it must NOT be collapsed with the inherited
    ///      `TICKET_SCALE` (100). They play different roles (entry-unit multiplier
    ///      vs the Game divisor base) that happen to compose to the same 400.
    uint256 internal constant AFKING_TICKET_SCALE = 400;

    /// @dev drainGameCreditFirst bit within Sub.flags — when set the buy spends
    ///      protocol-side claimable credit before tapping afkingFunding ETH.
    uint8 internal constant FLAG_DRAIN_FIRST = 2;

    /// @dev useTickets bit within Sub.flags — set = ticket mint mode, clear =
    ///      lootbox mode.
    uint8 internal constant FLAG_USE_TICKETS = 4;

    /// @dev externalFunding bit within Sub.flags — set ONLY when a non-self
    ///      `fundingSource` is registered in the sparse `_fundingSourceOf` map.
    ///      Lets the common self-funded path resolve `src = player` from the
    ///      already-loaded flags byte and SKIP the per-sub `_fundingSourceOf` SLOAD
    ///      (the map is read only for the rare OPEN-E operator-funded sub).
    uint8 internal constant FLAG_EXTERNAL_FUNDING = 1;

    /// @dev Active-subscriber cap = 500. Bounds the iterable set the protocol pays
    ///      to iterate every cycle — the advance chain walks `_subscribers` in the
    ///      process/open passes, so an unbounded set would bog the daily heartbeat.
    ///      500 keeps the per-cycle work cheap and sits well within the uint16
    ///      `_subCursor`/`_subOpenCursor` range (no cursor aliasing). `subscribe`
    ///      reverts a NEW-subscriber insert at the cap; a re-subscribe of an existing
    ///      member does not grow the set, so it is exempt. Demand past 500 is not the
    ///      protocol's burden to service — those users arrange their own keepering.
    uint256 internal constant SUBSCRIBER_CAP = 500;

    /*------------------------------------------------------------------
                          Router bounty constants (PLACE-02)
    ------------------------------------------------------------------*/
    /// @dev ETH-equivalent advance/open-bounty target per unit of work (in ETH wei).
    ///      A frozen constant (a module cannot hold a deploy-time immutable in the
    ///      Game's storage context). ⚠ The bounty target tune is the GAS phase's charge;
    ///      this carries the current value unchanged.
    uint256 internal constant BOUNTY_ETH_TARGET = 885_000_000;

    /// @dev Advance reward ratio (2× · mult). The process STAGE rides the advance
    ///      bounty (PLACE-02 §6): mintBurnie's advance leg pays `unit · 2 · mult`, scaling
    ///      the AdvanceModule's day-epoch stall `mult` (1/2/4/6, AdvanceModule:226-242).
    uint256 internal constant ADVANCE_RATIO_NUM = 2;

    /// @dev Open reward pro-rate knee (1× at/above, pro-rated below): a mid-day open of
    ///      k < 5 boxes earns `unit · k / 5`, so a single-box open earns 0.2× — below a
    ///      one-box tx's gas. This is the in-codebase farm-by-splitting answer (pay for
    ///      work done, not once-per-call — the "middle-chunk-unpaid" liveness gap).
    uint256 internal constant OPEN_KNEE = 5;

    /// @dev Open-leg default box-count budget (the post-RNG `_subOpenCursor` drain).
    ///      Carried from AfKing's measurement-derived `OPEN_BATCH` (the per-box open is
    ///      uniform O(1); the afking box rolls boons like a human box ≈ 77K/box, so
    ///      200 boxes stays under the 16.7M per-tx ceiling). ⚠ The flat-budget
    ///      re-measurement is the GAS phase's charge (350); carried unchanged.
    uint256 internal constant OPEN_BATCH = 200;

    /*------------------------------------------------------------------
                          Subscription entrypoint (CONSENT-01 carried verbatim)
    ------------------------------------------------------------------*/
    /// @notice The SINGLE subscription entrypoint — create, replace, or cancel a
    ///         daily subscription for `player`. dailyQuantity >= 1 upserts
    ///         (create-or-replace in place); dailyQuantity == 0 cancels (writes the
    ///         SUB-07 tombstone sentinel, relocating no one). Every mutation flows
    ///         through this one consent-gated path.
    /// @dev FREEZE-01 rngLock guard: subscribe reverts during the RNG freeze window
    ///      (`rngLockedFlag`), for ALL of create / replace / cancel — the subscriber
    ///      set must be frozen across [request -> unlock] so the stamped set the open
    ///      consumes cannot shift mid-cycle. Callers wait for the unlock.
    /// @dev SUB-02 authorization is checked ONCE here, third-party path only:
    ///      `player == address(0)` or `player == msg.sender` is self-consent (no
    ///      check); otherwise the caller must be a game operator the player
    ///      approved (in-context `operatorApprovals[subscriber][msg.sender]` —
    ///      the same predicate `isOperatorApproved` returns). Authorization is
    ///      NEVER re-checked at process-time.
    /// @dev AFSUB-02 pass-gating: subscribe encodes the subscriber's current pass
    ///      horizon (in-context `_passHorizonOf(subscriber)`) into
    ///      `Sub.validThroughLevel` with a SINGLE read. No BURNIE charge — the
    ///      v50.0 pass-gated model. The per-iter process validity check is the
    ///      cheap stored-field compare `level <= sub.validThroughLevel`; at the
    ///      crossing the pass is re-read EXACTLY ONCE and refresh-or-evicted.
    /// @dev msg.value > 0 credits the Game's afkingFunding ledger in-context
    ///      (claimablePool moved in tandem — the SOLVENCY-01 invariant), keyed on the
    ///      resolved funding bucket (the funder for an operator-funded sub, else the
    ///      subscriber).
    /// @dev OPEN-E 4-protection (re-attested):
    ///        (1) consent-gate-at-subscribe — auth + fundingSource gate checked HERE only;
    ///        (2) default-self — `fundingSource == 0` resolves to `subscriber`, no gate;
    ///        (3) no-escalation — the source is fixed at subscribe, not changeable per-draw to escalate;
    ///        (4) trust-the-sub — a later approval revoke does NOT stop an active sub (re-pointing the source = re-subscribe, which re-checks).
    /// @param player Subscriber to act for (0 or msg.sender = self).
    /// @param drainGameCreditFirst When true, the buy spends claimable credit first.
    /// @param useTickets Mint mode — true = tickets, false = lootboxes.
    /// @param dailyQuantity Daily buy units, 1..255 (upsert); 0 cancels (SUB-07 tombstone).
    /// @param reinvestPct Claimable reinvest percentage, 0..100.
    /// @param fundingSource Wallet whose `afkingFunding` funds this sub; address(0) = self.
    ///        A non-zero, non-self source is honored ONLY when it has
    ///        operator-approved the subscriber (checked at subscribe ONLY).
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint8 reinvestPct,
        address fundingSource
    ) external payable {
        // FREEZE-01 — block ALL subscribe (create / replace / cancel) during the
        // RNG freeze window: the subscriber set the stamp pass + open consume must
        // stay frozen across [request -> unlock]. Callers wait for the unlock.
        if (rngLockedFlag) revert RngLocked();
        if (reinvestPct > 100) revert InvalidReinvestPct();

        // SUB-02 — self-consent (player == 0 or msg.sender) or operator-approval.
        address subscriber = player == address(0) ? msg.sender : player;
        if (subscriber != msg.sender) {
            if (!operatorApprovals[subscriber][msg.sender]) {
                revert NotApproved();
            }
        }

        // OPENE-04 — a non-zero, non-self fundingSource must have operator-approved
        // the subscriber on the game. address(0) (self) short-circuits the read;
        // checked HERE only — the renewal and per-draw paths never re-check.
        if (
            fundingSource != address(0) &&
            fundingSource != subscriber &&
            !operatorApprovals[fundingSource][subscriber]
        ) {
            revert NotApproved();
        }

        // msg.value > 0 credits the Game's afkingFunding ledger in-context (A2 —
        // the Game holds the ETH; claimablePool moved in tandem so the invariant
        // claimablePool == Σ claimableWinnings + Σ afkingFunding holds). It credits the
        // SAME bucket the draws debit: the resolved funding source — the non-self
        // `fundingSource` for an operator-funded sub (already OPENE-04-approved just
        // above, so the funder consented to fund this subscriber), else the subscriber
        // itself. So a deposit attached to subscribe always funds the bucket that
        // actually pays for this sub's auto-buys — never misdirected to an unused player
        // bucket on an operator-funded sub.
        if (msg.value > 0) {
            address fundDest = (fundingSource != address(0) &&
                fundingSource != subscriber)
                ? fundingSource
                : subscriber;
            afkingFunding[fundDest] += msg.value;
            claimablePool += uint128(msg.value);
        }

        // CANCEL branch (SUB-07 in-place tombstone) — dailyQuantity == 0 writes the
        // `dailyQuantity = 0` sentinel and relocates NO ONE (the in-pass reclaim
        // swap-pops the tombstone when the process STAGE reaches it; CONSENT-02 /
        // H-CANCEL-SWAP-MISS preserved). Revert if the caller has no active sub
        // (nothing to cancel). Any msg.value above was still credited to funding, so
        // a cancel-with-ETH never strands the deposit (it stays game-side withdrawable).
        if (dailyQuantity == 0) {
            if (_subscriberIndex[subscriber] == 0) revert NotSubscribed();
            Sub storage c = _subOf[subscriber];
            c.dailyQuantity = 0;
            emit SubscriptionUpdated(
                subscriber,
                0,
                (c.flags & FLAG_DRAIN_FIRST) != 0,
                (c.flags & FLAG_USE_TICKETS) != 0,
                c.reinvestPct,
                _fundingSourceOf[subscriber]
            );
            return;
        }

        // UPSERT branch (dailyQuantity >= 1) — create-or-replace in place. `_addToSet`
        // is idempotent (adds only when `_subscriberIndex == 0`), so a re-subscribe of
        // an active member replaces its fields without set churn.
        Sub storage s = _subOf[subscriber];

        s.dailyQuantity = dailyQuantity;
        if (drainGameCreditFirst) s.flags |= FLAG_DRAIN_FIRST;
        else s.flags &= ~FLAG_DRAIN_FIRST;
        if (useTickets) s.flags |= FLAG_USE_TICKETS;
        else s.flags &= ~FLAG_USE_TICKETS;
        s.reinvestPct = reinvestPct;
        // AFSUB-02 — single read; encodes the subscriber's pass horizon into the
        // stored field the per-iter check + crossing branch compare against.
        // Deity sentinel = type(uint24).max via _passHorizonOf (D-11).
        s.validThroughLevel = uint32(_passHorizonOf(subscriber));
        // Sparse funder map: store only a
        // non-self source; clear on self so re-pointing operator-funded → self does
        // not strand a stale funder (OPENE-03 no-escalation — the source is fixed
        // here, re-pointing it IS a re-subscribe, which re-runs the OPENE-04 gate).
        if (fundingSource != address(0)) {
            _fundingSourceOf[subscriber] = fundingSource;
            s.flags |= FLAG_EXTERNAL_FUNDING;
        } else {
            delete _fundingSourceOf[subscriber];
            s.flags &= ~FLAG_EXTERNAL_FUNDING;
        }

        _addToSet(subscriber);
        emit SubscriptionUpdated(
            subscriber,
            dailyQuantity,
            drainGameCreditFirst,
            useTickets,
            reinvestPct,
            fundingSource
        );
    }

    /*------------------------------------------------------------------
                          In-context views (CONSENT-01)
    ------------------------------------------------------------------*/
    /// @dev In-context pass-horizon read (the AFSUB pass-gating producer, D-11).
    ///      Mirrors the Game's `lazyPassHorizon` (:1582) so the
    ///      subscribe-time write + the process-pass crossing re-read share the exact
    ///      horizon semantics: deity holders return the type(uint24).max sentinel;
    ///      everyone else returns their frozenUntilLevel. Single definition (one
    ///      canonical horizon read), called at subscribe + the crossing branch.
    function _passHorizonOf(address player) internal view returns (uint24) {
        uint256 packed = mintPacked_[player];
        if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) {
            return type(uint24).max;
        }
        return
            uint24(
                (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                    BitPackingLib.MASK_24
            );
    }

    /*------------------------------------------------------------------
                          Iterable set (hand-inlined OZ EnumerableSet)
    ------------------------------------------------------------------*/
    /// @dev Iterable set insert. Idempotent on already-in-set. 1-indexed
    ///      `_subscriberIndex` (0 = not in set). Reverts a NEW insert at
    ///      SUBSCRIBER_CAP (500 active subs) — the protocol caps the set it pays to
    ///      iterate each cycle. A re-subscribe of an existing member is
    ///      already-in-set (no growth) so it never trips the cap.
    function _addToSet(address player) internal {
        if (_subscriberIndex[player] == 0) {
            // Cap the NEW-subscriber path only: bound the active set the advance
            // chain walks (SUBSCRIBER_CAP = 500) so the per-cycle work stays cheap.
            if (_subscribers.length >= SUBSCRIBER_CAP) {
                revert SubscriberCapReached();
            }
            _subscribers.push(player);
            _subscriberIndex[player] = _subscribers.length;
        }
    }

    /// @dev Iterable set remove via swap-and-pop. Idempotent on not-in-set.
    ///      1-indexed: move the last element into the vacated slot (and update its
    ///      index), pop the tail, clear the removed player's index. The process
    ///      pass's "no cursor-advance after swap-pop" pattern (CONSENT-02 —
    ///      H-CANCEL-SWAP-MISS) enforces iteration safety; this helper is itself
    ///      iteration-safe (membership ⟺ packed-index != 0 preserved).
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

    /*------------------------------------------------------------------
                  The _resolveBuy slice builder (REVERT-01)
    ------------------------------------------------------------------*/
    /// @dev Per-player funding resolution for the process pass — SUB-04 effective
    ///      quantity → cost → purchase mode + funding split, carrying the slice-builder
    ///      validation invariants that make a funded buy revert-free BY CONSTRUCTION (REVERT-01,
    ///      the SOLE no-brick guarantor under the D-348-04 no-valve model). The five
    ///      obligation-1 invariants (348-INVARIANT-CARRY §1, /contract-auditor PASS §5):
    ///        (1) effectiveQty = max(dailyQuantity, reinvestQty) ≥ 1 (dailyQuantity ≥ 1
    ///            is the subscribe-time floor) → never the Game's totalCost==0 / dust /
    ///            TICKET_MIN reverts;
    ///        (2) cost = mintPrice * effectiveQty → the exact cost the Game recomputes;
    ///        (3) cost ≥ mintPrice ≥ 0.01 ETH (the priceForLevel floor) → a lootbox amount
    ///            always meets any min-spend floor; no skip/decline needed;
    ///        (4) 1-wei claimable sentinel → leaves claimable > cost / basis > shortfall →
    ///            never Game:976 (Claimable claimable<=amount) nor Storage:843 (settle);
    ///        (5) ev = cost - claimableUse with claimableUse ∈ [0, cost], enum-typed
    ///            payKind ∈ {Claimable, DirectEth, Combined} → never Game:985/1003/1006
    ///            nor an out-of-range MintPaymentKind enum-cast Panic 0x21.
    ///      ⚠ Dual TICKET_SCALE (§3-i, LOAD-BEARING): the ticket entry-unit `amount`
    ///      uses `AFKING_TICKET_SCALE = 400`; the Game's `/ (4 * 100)` recompute uses the
    ///      inherited Storage `TICKET_SCALE = 100` — the two constants are NOT collapsed,
    ///      so `cost` stays `mintPrice * effectiveQty`.
    ///      ⚠ NO error-swallowing valve (REVERT-02 no-valve): a funded slice is revert-free
    ///      by construction, with no pre-emptive decline and no reactive error-trap; the
    ///      per-cycle eviction cap is DROPPED.
    ///      In-context: `claimable` is the swept-gated raw `claimableWinnings[player]`
    ///      (== afkingSnapshot's claimable / claimableWinningsOf, incl. the 1-wei sentinel)
    ///      and `playerFunding` is the raw `afkingFunding[player]` (== afkingFundingOf,
    ///      D-MR-01), read as in-context SLOADs. View — no state writes.
    /// @return payKind Payment mode (DirectEth / Claimable / Combined) for the slice.
    /// @return ethValue Fresh-ETH portion debited from the funder's afkingFunding (0 = pure claimable).
    /// @return amount Ticket entry-units (isTicket) or lootbox spend in wei (!isTicket).
    /// @return isTicket True = buy `amount` ticket entry-units; false = buy an `amount`-wei lootbox.
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
            uint256 playerFunding
        )
    {
        bool drainFirst = (sub.flags & FLAG_DRAIN_FIRST) != 0;
        // ONE in-context read pair: the player's
        // claimable (reinvest / drainFirst funding split) AND afkingFunding (the
        // common-path funding-skip source — D-MR-01; the src != player OPEN-E slice
        // reads afkingFunding[src] separately at the call site). Swept-gated to mirror
        // afkingSnapshot / claimableWinningsOf exactly.
        uint256 claimable = _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0
            ? 0
            : claimableWinnings[player];
        playerFunding = afkingFunding[player];

        // Total quantity = max(dailyQuantity, reinvestPct% of claimable / price).
        uint256 effectiveQty = sub.dailyQuantity;
        if (sub.reinvestPct > 0) {
            uint256 reinvestQty = (claimable * sub.reinvestPct) / 100 / mp;
            if (reinvestQty > effectiveQty) effectiveQty = reinvestQty;
        }
        uint256 cost = mp * effectiveQty;

        // Mode routing. Ticket mode buys `effectiveQty` whole tickets (entry-units =
        // effectiveQty * AFKING_TICKET_SCALE [= 400]); lootbox mode buys a `cost`-wei box.
        isTicket = (sub.flags & FLAG_USE_TICKETS) != 0;
        amount = isTicket ? effectiveQty * AFKING_TICKET_SCALE : cost;

        // Funding split (USER model): reinvestPct always spends that % of claimable;
        // drainFirst is a superset (claimable-first up to cost). The afkingFunding pool
        // funds the remainder. Never spend the entire claimable balance — leave >= 1 wei
        // (the GAME's Claimable branch needs claimable strictly > cost, and the claimable
        // shortfall settle needs basis > shortfall).
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
              The REQUIRED-PATH process STAGE (BOX-02 stamp + BOX-03 debit + CONSENT-02)
    ------------------------------------------------------------------*/
    /// @notice The chunked pre-RNG stamp/buy pass the AdvanceModule STAGE drives across
    ///         the subscriber set, immediately before `rngGate` on the new-day path
    ///         (D-348-01 required-path; 349.1-04 owns the AdvanceModule insertion). A
    ///         NO-ORPHAN guard (§3) runs FIRST per sub: a sub with a pending unopened box
    ///         (`lastOpenedDay < lastAutoBoughtDay`) is left ENTIRELY untouched this cycle
    ///         (no reclaim / evict / funding-kill / re-stamp), so its paid-for box is never
    ///         orphaned. For each funded, well-formed sub it then builds the `_resolveBuy`
    ///         slice (REVERT-01) and, per mode (P2): a LOOTBOX sub STAMPS the two
    ///         genuinely-per-sub box inputs (`scorePlus1`, `amount`) warm-dirty into the
    ///         single-slot Sub record (BOX-02) — the box is materialized LATER by the open
    ///         leg at the LIVE level (349.1-03); a TICKET sub QUEUES whole tickets NOW via
    ///         the MintModule `purchaseWith` path (no box). Both modes debit
    ///         `afkingFunding[src]` then set the `lastAutoBoughtDay` success-marker AFTER
    ///         the debit (BOX-03; it also doubles as the lootbox seed `day`), and carry the
    ///         CONSENT-02 set-mutation semantics (no cursor advance after swap-pop).
    /// @dev FREEZE-02b: the STAGE runs strictly pre-RNG (before `rngGate`), so the day-D
    ///      word `rngWordByDay[processDay]` is uncommitted at stamp — the freeze property
    ///      (349.1-DESIGN §2). The lootbox open sources its word from
    ///      `rngWordByDay[lastAutoBoughtDay]` and rolls the level LIVE at open; there is no
    ///      stored per-day epoch. The boundary-pinned `processDay` is computed once by the
    ///      STAGE and passed in (it is the stamped `lastAutoBoughtDay`, the frozen seed
    ///      `day`, FREEZE-03; never open-time `_simulatedDayIndex()`).
    /// @dev BOX-02 stamp-only (lootbox mode): this pass writes NO cold box-ledger entry —
    ///      the warm Sub stamp is the box record (no cold ledger). boons OFF ⇒ `amount` = spend.
    /// @dev DOUBLE-DRAW GUARD (EVCAP-01 producer): the lootbox path STAMPS only — the
    ///      single EV-cap RMW happens at OPEN, fed the FROZEN `evMultiplierBps`
    ///      derived from the stamped `scorePlus1`. The ticket path defers all EV to the
    ///      MintModule buy (it computes the ticket's own activity score on the buy path).
    /// @dev NO error-swallowing valve (REVERT-02 no-valve, D-348-04): a funded slice is
    ///      revert-free by construction (REVERT-01); there is no pre-emptive lootbox skip;
    ///      rule-(1) unfunded eviction is a separate pre-buy decision
    ///      (a NORMAL sub is auto-paused via swap-pop; VAULT/SDGNRS are EXEMPT by pinned
    ///      identity); the SOLVENCY-01 `claimablePool -=` site FAILS LOUD (class B, must
    ///      propagate). The per-cycle eviction cap is DROPPED.
    /// @param processDay The boundary-pinned process day (computed once by the STAGE).
    /// @param maxCount Maximum entries to process this chunk (caller-bounded — the
    ///        anti-gas-DoS property; the STAGE supplies a BUY_BATCH-style budget).
    /// @return processed Number of set entries advanced/handled this chunk.
    function processSubscriberStage(
        uint32 processDay,
        uint256 maxCount
    ) external returns (uint256 processed) {
        uint256 mp = _mintPriceInContext();
        // AFSUB-02 — hoist the level read ONCE so the per-iter validity check is a pure
        // stored-field compare (no SLOAD on the non-crossing path). GASOPT-05 preserved.
        uint24 currentLevel = level;

        uint256 cursor = _subCursor;

        while (processed < maxCount && cursor < _subscribers.length) {
            address player = _subscribers[cursor];
            Sub storage sub = _subOf[player];

            // (-1) NO-ORPHAN guard (§3 — the load-bearing correctness rule). A box is
            // STAMPED at process (day D) but OPENED later; it exists ONLY as
            // (Sub stamp + lastAutoBoughtDay) with no cold ledger, so ANY mutation of the
            // Sub OR removal from `_subscribers` between stamp and open ORPHANS the
            // paid-for box (the player was debited at stamp, gets nothing). A sub with a
            // pending unopened box (`lastOpenedDay < lastAutoBoughtDay`) is therefore left
            // ENTIRELY untouched this cycle — no reclaim, no evict, no funding-kill, no
            // re-stamp; it stays in-set (reachable), `_autoOpen` opens it, and a LATER
            // cycle processes it (now boxless, lastOpenedDay == lastAutoBoughtDay).
            // Positioned BEFORE the cancel-reclaim so it dominates ALL FOUR orphan paths
            // (re-stamp / cancel-reclaim / pass-evict / funding-kill). SKIP, not
            // force-open (LOCKED §3): keeps the heavy open out of the gas-critical advance
            // chain; the BURNIE open-bounty keeps opens prompt so it ~never skips a buy. No
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

            // (0) Cancel-tombstone reclaim (CONSENT-02 — SUB-07 / H-CANCEL-SWAP-MISS).
            // An externally-cancelled sub (subscribe(_, 0)) is an in-set
            // `dailyQuantity == 0` tombstone: it relocated no one on cancel, so it cannot
            // have pushed a pending entry behind the cursor. The reclaim deletes the
            // `_subOf` record, swap-pops it out, and continues WITHOUT advancing the cursor
            // — the swap-pop occupant (a mover from ahead, still pending) is processed at
            // this slot this pass. Ordered ahead of the AlreadyAutoBoughtToday skip so a
            // tombstone is ALWAYS reclaimed, independent of its lastAutoBoughtDay.
            if (sub.dailyQuantity == 0) {
                delete _subOf[player];
                _removeFromSet(player);
                emit SubscriptionExpired(player, 2);
                unchecked {
                    ++processed;
                }
                continue;
            }

            // (1) AlreadyAutoBoughtToday — cheapest SLOAD-only skip (the BOX-03 marker is
            // the idempotency backstop: a sub stamped this cycle is not re-stamped).
            if (sub.lastAutoBoughtDay >= processDay) {
                emit PlayerSkipped(player, 2);
                unchecked {
                    ++cursor;
                    ++processed;
                }
                continue;
            }

            // (2) AFSUB-02/03 pass-validity gate. Non-crossing path is a pure stored-field
            // compare (currentLevel <= validThroughLevel) — no extra read. At the crossing
            // the pass re-reads the horizon EXACTLY ONCE and refreshes (still covered) or
            // evicts via the tombstone-then-reclaim shape (CONSENT-02 — membership ⟺ packed
            // != 0 preserved; a direct mid-pass removal would re-open H-CANCEL-SWAP-MISS).
            if (currentLevel > sub.validThroughLevel) {
                uint24 h = _passHorizonOf(player);
                if (currentLevel <= h) {
                    // REFRESH — still covered (newly minted pass, upgrade, etc.).
                    sub.validThroughLevel = uint32(h);
                    emit SubscriptionExtendedFree(player, processDay);
                } else {
                    // EVICT — route through tombstone-then-reclaim so the swap-pop
                    // invariant survives (no cursor advance after the swap-pop).
                    sub.dailyQuantity = 0;
                    _removeFromSet(player);
                    emit SubscriptionExpired(player, 1);
                    unchecked {
                        ++processed;
                    }
                    continue;
                }
            }

            // SUB-04 funding resolution (cost + payment mode + ethValue slice). The slice
            // builder (REVERT-01) computes everything revert-free by construction.
            (
                MintPaymentKind payKind,
                uint256 ethValue,
                uint256 amount,
                bool isTicket,
                uint256 playerFunding
            ) = _resolveBuy(sub, player, mp);

            // OPENE-02 — resolve the once-per-iteration funding source. The common
            // self-funded path is detected from the already-loaded `sub.flags`
            // (FLAG_EXTERNAL_FUNDING clear ⇒ src = player) and SKIPS the
            // `_fundingSourceOf` SLOAD entirely; only the rare operator-funded sub
            // (flag set) reads the sparse map. Both the ETH skip-gate read and the CEI
            // debit key on this same `src`. The VAULT/SDGNRS exemption below stays keyed
            // on the un-spoofable `player`, never `src`.
            address src = (sub.flags & FLAG_EXTERNAL_FUNDING) != 0
                ? _fundingSourceOf[player]
                : player;

            // (5) Funding skip → two-tier skip-kill. Read afkingFunding[src]: the common
            // path (src == player) reuses the `playerFunding` from _resolveBuy (no extra
            // SLOAD); the rare OPEN-E operator-funded slice (src != player) reads
            // afkingFunding[src]. A NORMAL underfunded sub is CANCELLED via swap-pop
            // (auto-pause WITHOUT advancing the cursor — the mover at this slot is processed
            // this pass). VAULT + sDGNRS are EXEMPT by the un-spoofable pinned
            // ContractAddresses.VAULT / SDGNRS identity (kept on `player`, never `src`) — a
            // funding skip is transient for them (no-op-and-retry, stays in the set). The
            // exemption is the pinned-address branch only; there is no settable flag.
            if (
                (src == player ? playerFunding : afkingFunding[src]) < ethValue
            ) {
                if (
                    player == ContractAddresses.VAULT ||
                    player == ContractAddresses.SDGNRS
                ) {
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
                unchecked {
                    ++processed;
                }
                continue;
            }

            // (6) BUY (P2 split) + DEBIT + MARKER (BOX-03). The fresh-ETH `ethValue` is
            // debited from `afkingFunding[src]` with `claimablePool` released in TANDEM for
            // BOTH modes (the afking funding-ledger debit shape `afkingFunding[funder] -= ev;
            // claimablePool -= ev`). Then, per mode:
            //   • LOOTBOX (isTicket == false): STAMP the box (BOX-02) — freeze the two
            //     genuinely-per-sub inputs (scorePlus1 = activityScore + 1 [D-348-07, the EV
            //     multiplier input at open]; amount = the stamped spend, boons OFF ⇒
            //     amount == spend) warm-dirty into the single Sub slot. The box is
            //     materialized LATER by _openAfkingBox at the LIVE level (349.1-03), a pure
            //     function of the record + rngWordByDay[lastAutoBoughtDay]. No cold ledger,
            //     no purchaseWith here; the freed ETH becomes the box's spend at open and the
            //     buyer's own claimableUse portion is settled at OPEN.
            //   • TICKET (isTicket == true, P2 fix): do NOT stamp a box — queue `amount`
            //     ticket entry-units NOW via the MintModule purchaseWith path (the existing
            //     ticket-queue mechanic), and set lastOpenedDay = lastAutoBoughtDay so the
            //     open-leg never sees a ticket
            //     sub (no garbage micro-box). The MintModule computes the ticket's own
            //     activity score on the buy path — no per-sub box EV stamp. Revert-free by
            //     construction under REVERT-01 (funded, well-formed slice) — NO try/catch,
            //     no valve (D-348-04).
            // ⚠ SOLVENCY-01: the `claimablePool -= uint128(ethValue)` site FAILS LOUD on an
            // underflow (a debit can never exceed the per-account afkingFunding ≤ the
            // claimablePool reservation — a revert here means SOLVENCY-01 is already
            // violated; class B, MUST propagate, NEVER caught).
            if (ethValue != 0) {
                afkingFunding[src] -= ethValue;
                claimablePool -= uint128(ethValue);
            }

            if (isTicket) {
                // Queue whole tickets via purchaseWith — the ticket encoding: entry-units in
                // ticketQuantity, 0 lootbox wei, the protocol affiliate code bytes32("DGNRS"),
                // the resolved payKind, and the fresh-ETH ethValue param (non-payable; the
                // freed ETH is the buy's value).
                (bool ok, bytes memory data) = ContractAddresses
                    .GAME_MINT_MODULE
                    .delegatecall(
                        abi.encodeWithSelector(
                            IDegenerusGameMintModule.purchaseWith.selector,
                            player,
                            amount,
                            uint256(0),
                            bytes32("DGNRS"),
                            payKind,
                            ethValue
                        )
                    );
                if (!ok) _revertDelegate(data);
                // No pending box: keep lastOpenedDay == lastAutoBoughtDay so the no-orphan
                // guard + _afkingBoxReady never treat a ticket sub as box-pending.
                sub.lastOpenedDay = processDay;
            } else {
                // STAMP the lootbox box — ONE warm-dirty SSTORE (the single Sub slot;
                // amount is uint96, explicit cast SAFE: a single box can never exceed the
                // ETH in existence, uint96 max ≈ 79e9 ETH).
                uint256 activityScore = _playerActivityScore(
                    player,
                    _questStreakOf(player),
                    currentLevel + 1
                );
                uint16 scorePlus1 = activityScore + 1 > type(uint16).max
                    ? type(uint16).max
                    : uint16(activityScore + 1);
                sub.scorePlus1 = scorePlus1;
                sub.amount = uint96(amount);
            }

            // Success-marker (BOX-03) — set ONLY AFTER the successful debit + buy/stamp. A
            // failed/skipped buy writes no marker (no free box/tickets); a wallet
            // subscribing between this pass and the open has no this-cycle marker.
            // Preserves the lastAutoBoughtDay >= processDay idempotency at (1); for a
            // lootbox sub it doubles as the open's seed `day` (FREEZE-03).
            sub.lastAutoBoughtDay = processDay;

            unchecked {
                ++cursor;
                ++processed;
            }
        }

        // Persist the advanced cursor (uint16) for the next chunk / call.
        _subCursor = uint16(cursor);
        return processed;
    }

    /// @dev In-context quest-streak read for the activity-score stamp. Mirrors the
    ///      `questView.playerQuestStates(player)` streak extraction the Game's
    ///      `playerActivityScore` (:2633) and the DegeneretteModule (:504) use to feed
    ///      `_playerActivityScore`. Isolated so the stamp's score source is a single
    ///      point of truth.
    function _questStreakOf(address player) internal view returns (uint32) {
        (uint32 questStreak, , , ) = questView.playerQuestStates(player);
        return questStreak;
    }

    /*==================================================================
        PART B (349-04) — the post-RNG OPEN-PASS + the ROUTER + PLACE-02
    ==================================================================*/

    /// @dev Reverts with the delegatecall failure reason bytes. Canonical module tail
    ///      (cf. DegenerusGameDegeneretteModule:123 / DecimatorModule:90) for the
    ///      nested delegatecall into the LootboxModule's `resolveAfkingBox`.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Materialize ONE subscriber's stamped afking box (the freeze-critical open).
    ///      The box's word comes from `rngWordByDay[sub.lastAutoBoughtDay]` (the frozen
    ///      stamp day, §1); the level + the EV-cap key read LIVE inside `resolveAfkingBox`
    ///      (§2); the per-sub inputs (amount, scorePlus1) come from the Sub record. Day-keyed
    ///      no-double-open: the leg runs only while `lastOpenedDay < lastAutoBoughtDay`
    ///      (pre-gated by `_afkingBoxReady`), and advances the marker
    ///      (`lastOpenedDay = lastAutoBoughtDay`) BEFORE the resolve (effects-before-
    ///      interaction; a re-entrant open re-checks the now-equal marker and no-ops). The
    ///      box is materialized by delegatecalling the LootboxModule's `resolveAfkingBox`
    ///      (the LIVE-level twin of `resolveLootboxDirect`) with: the spend `amount` widened
    ///      uint96→uint256 (boons OFF ⇒ amount == spend, BOX-01), the FROZEN process `day` =
    ///      `lastAutoBoughtDay` (FREEZE-03 seed), the frozen day's word `rngWordByDay[day]`
    ///      (§1), and the FROZEN `activityScore = scorePlus1 - 1` (D-348-07). The draw math +
    ///      the single EV-cap RMW live in `resolveAfkingBox`; this leg is the thin
    ///      cursor/marker/dispatch shell. The box materialization is PRIVATE to the
    ///      LootboxModule, so the delegatecall to `resolveAfkingBox` is the one
    ///      freeze-correct seam (the public `resolveLootboxDirect` derives its seed from the
    ///      LIVE day and would NOT freeze the seed `day`). No stored baseLevel/index — the
    ///      live roll needs no floor.
    /// @param player The subscriber whose box is materialized.
    /// @param sub The subscriber's stamped record (storage ref — the marker advances here).
    function _openAfkingBox(address player, Sub storage sub) private {
        uint32 day = sub.lastAutoBoughtDay;
        // Advance the day-keyed no-double-open marker BEFORE the resolve (effects-first; a
        // re-entrant open re-checks `lastOpenedDay < lastAutoBoughtDay` → false → no-op).
        sub.lastOpenedDay = day;

        // boons OFF ⇒ the stamped spend IS the box amount (BOX-01) — widen uint96→uint256.
        // The word is the frozen stamp day's word (§1); the level + EV-cap read LIVE in the
        // callee (§2). No index, no baseLevel.
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveAfkingBox.selector,
                    player,
                    uint256(sub.amount),
                    day,
                    rngWordByDay[day],
                    uint16(sub.scorePlus1) - 1
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev O(1) afking-box-open materializability for a single stamped sub: it has a
    ///      pending unopened box (`lastOpenedDay < lastAutoBoughtDay`) AND the frozen stamp
    ///      day's word has landed (`rngWordByDay[lastAutoBoughtDay] != 0`). A zero word =
    ///      not-ready (the day's word hasn't been committed yet — the open is skipped until
    ///      it lands; mirrors LootboxModule's RngNotReady guard + the Game `autoOpen` skip).
    ///      View — no state writes.
    function _afkingBoxReady(Sub storage sub) private view returns (bool) {
        return
            sub.lastOpenedDay < sub.lastAutoBoughtDay &&
            rngWordByDay[sub.lastAutoBoughtDay] != 0;
    }

    /// @notice The post-RNG afking-box OPEN leg — a NORMAL `OPEN_BATCH`-style router
    ///         category driven by `_subOpenCursor` (NOT folded into advance, PLACE-02).
    /// @dev rngLock-block (RD-3): the open leg no-ops during the freeze (a mid-day RNG
    ///      lock or the terminal-jackpot liveness control), so the loop body is
    ///      guaranteed-non-reverting under the entry-gate (each open is pre-gated on a
    ///      landed word) — no per-item try/catch, no valve (D-348-04). Walks
    ///      `_subscribers` from `_subOpenCursor`, opening up to `maxCount` materializable
    ///      boxes; the per-sub day-keyed `lastOpenedDay` marker makes the walk
    ///      idempotent, so the cursor wrap-resets to 0 at the set end (a re-walk skips
    ///      already-opened subs by the marker — no extra per-index storage needed).
    ///      Concurrent callers self-partition via the advancing cursor.
    /// @param maxCount Max boxes to open this call (0 = OPEN_BATCH). Caller-bounded — the
    ///        anti-gas-DoS property (every afking box is uniform O(1), like a human box).
    /// @return opened The number of afking boxes materialized this call (drives OPEN_KNEE).
    function _autoOpen(uint256 maxCount) internal returns (uint256 opened) {
        if (maxCount == 0) maxCount = OPEN_BATCH;
        // Entry-gate (RD-3/RD-5): the open path no-ops in the freeze / terminal control.
        if (rngLockedFlag || _livenessTriggered()) return 0;

        uint256 len = _subscribers.length;
        if (len == 0) return 0;
        uint256 cursor = _subOpenCursor;
        // Wrap a spent cursor back to the set start (the marker makes the re-walk a no-op
        // on already-opened subs; a fresh-stamp sub past its marker opens).
        if (cursor >= len) cursor = 0;

        while (cursor < len && opened < maxCount) {
            address player = _subscribers[cursor];
            Sub storage sub = _subOf[player];
            unchecked {
                ++cursor;
            }
            // Skip subs with no fresh, RNG-ready stamp (already-opened / word not landed).
            if (!_afkingBoxReady(sub)) continue;
            // Guaranteed-non-reverting under the entry-gate + the readiness pre-gate.
            _openAfkingBox(player, sub);
            unchecked {
                ++opened;
            }
        }

        _subOpenCursor = uint16(cursor);
    }

    /// @notice Unified permissionless afking router: do ONE category of pending work this
    ///         call (priority advance → afking-box open) and pay ONE bounty (PLACE-02).
    /// @dev ROUTER one-category STRUCTURAL early-return: the rngLock-aware O(1) predicates
    ///      pick the first category with work; the advance and open bounties can never
    ///      stack in one tx. NO `nonReentrant` guard (ROUTER-07 — the module is
    ///      afking-never-a-payee: every external call is to a pinned `ContractAddresses.*`
    ///      [GAME self-call / LootboxModule delegatecall / COINFLIP], player value flows
    ///      through the game's claimable pull ledger, and the bounty is minted flip-credit
    ///      — never an ETH push the router receives). The legs return raw counts/mult and
    ///      NEVER self-credit; only `mintBurnie` credits, ONCE, CEI-last after the
    ///      one-category early-return.
    /// @dev PLACE-02 bounty: the buy/process bounty FOLDS INTO the advance bounty — the
    ///      process STAGE runs inside `advanceGame` (the required path, 349-05), so the
    ///      advance leg's `unit · 2 · mult` IS the process bounty, scaled by the
    ///      AdvanceModule's day-epoch stall `mult` (1/2/4/6, :226-242). The OPEN leg pays
    ///      the `OPEN_KNEE` work-scaled pro-rate (pay for work done, farm-by-splitting
    ///      resistant). `mult == 0` (the gameover advance path) pays no bounty.
    function mintBurnie() external {
        uint256 mp = _mintPriceInContext();
        uint256 unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp;
        uint256 bountyEarned;

        // (1) advance — highest priority, liveness-critical (TRUE regardless of rngLock).
        // The self-call re-enters the Game's advanceGame, which runs the required-path
        // process STAGE in-context (349-05); the process bounty rides this 2x·mult.
        if (IGameRouter(address(this)).advanceDue()) {
            uint8 mult = IGameRouter(address(this)).advanceGame();
            if (mult > 0) bountyEarned = unit * ADVANCE_RATIO_NUM * mult;
        }
        // (2) afking-box open — FALSE during rngLock (RD-3); opens mid-day-resolved
        // stamped boxes via _subOpenCursor. 1x pro-rated below the knee, flat 1x
        // at/above — kills the small-batch farm-by-splitting corner.
        else {
            uint256 opened = _autoOpen(OPEN_BATCH);
            if (opened > 0) {
                uint256 k = opened < OPEN_KNEE ? opened : OPEN_KNEE;
                bountyEarned = (unit * k) / OPEN_KNEE;
            } else {
                // (3) ROUTER-06 — both categories empty: the clean no-work signal.
                revert NoWork();
            }
        }

        // The single unified bounty: ONE creditFlip, CEI-LAST, after the one-category
        // early-return. Skipped at 0 (e.g. a mult==0 gameover advance); the category
        // still ran, so we return rather than reverting NoWork().
        if (bountyEarned > 0) {
            coinflip.creditFlip(msg.sender, bountyEarned);
        }
    }

    /// @notice Standalone UNREWARDED manual/emergency advance trigger — only mintBurnie()
    ///         credits. Post-fold the subscriber "buy" is the required-path process STAGE
    ///         that runs INSIDE `advanceGame` (D-348-01), so the manual buy-clear drives
    ///         the advance (the buy-equivalent). The `count` arg is accepted for router
    ///         ABI-shape parity with the afking surface; the STAGE's own
    ///         `BUY_BATCH`-style chunk budget is internal to the AdvanceModule,
    ///         so `advanceGame` is parameterless and `count` is intentionally inert here.
    /// @param count Unused (ABI-parity); the process chunk budget lives in the STAGE.
    function autoBuy(uint256 count) external {
        count; // silence unused-parameter; the process chunk budget is the STAGE's
        IGameRouter(address(this)).advanceGame();
    }

    /// @notice Standalone UNREWARDED manual/emergency afking-box open clear — only
    ///         mintBurnie() credits. Walks `_subOpenCursor` opening up to `count` stamped
    ///         afking boxes (0 = OPEN_BATCH).
    /// @param count Max afking boxes to open this call (0 = the default OPEN_BATCH).
    function autoOpen(uint256 count) external {
        _autoOpen(count);
    }

    /// @dev In-context mint price (the bounty's ETH→BURNIE conversion divisor). Mirrors
    ///      the Game's `mintPrice` (:2501) — the price for the active ticket level —
    ///      read in-context so the bounty math needs no external/self call. Single use
    ///      site (the bounty `unit`); never an open-time seed input (FREEZE-safe).
    function _mintPriceInContext() internal view returns (uint256) {
        return PriceLookupLib.priceForLevel(_activeTicketLevel());
    }
}
