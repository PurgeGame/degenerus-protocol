// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusGameLootboxModule} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";

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
 *      the ROUTER (`mintBurnie`/`autoOpen`, the one-category early-return
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
    /// @dev subscribe (upsert) where the subscriber's live pass horizon does not reach
    ///      the current level — an active sub must hold a pass that covers `level` so it
    ///      cannot occupy a subscriber slot without a valid pass.
    error NoPass();
    /// @dev subscribe (upsert) starting a NEW afking run that is not grounded on a real
    ///      purchase — neither already bought today nor a funded in-tx cover-buy. An
    ///      unfunded start now reverts instead of beginning an inert, free-riding run.
    error MustPurchaseToBeginAfking();

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
    event SubscriptionExtendedFree(address indexed player, uint24 day);
    /// @dev Subscription removed from the iterable set. `reason`:
    ///        1 = AutoPause (AFSUB-03 pass-eviction at crossing OR funding-skip kill of a NORMAL sub)
    ///        2 = CancelReclaim (in-pass reclaim of an externally-cancelled tombstone)
    event SubscriptionExpired(address indexed player, uint8 reason);

    /// @notice Emitted for an afking subscribe-time cover-buy box. Same signature/topic as the
    ///         mint + whale `LootBoxBuy` — one box-buy event across every path.
    /// @param buyer The box recipient.
    /// @param index The lootbox RNG index the box queued at.
    /// @param amount The box ETH spend (boons off ⇒ raw spend).
    /// @param presale True if presale is active at the cover-buy.
    event LootBoxBuy(
        address indexed buyer,
        uint48 indexed index,
        uint256 amount,
        bool presale
    );

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
    ///      1000 keeps the per-cycle work cheap (every pass is weight-/OPEN_BATCH-chunked,
    ///      so the cap bounds total subs, not per-tx gas) and sits well within the uint16
    ///      `_subCursor`/`_subOpenCursor` range (no cursor aliasing). `subscribe`
    ///      reverts a NEW-subscriber insert at the cap; a re-subscribe of an existing
    ///      member does not grow the set, so it is exempt. Demand past 1000 is not the
    ///      protocol's burden to service — those users arrange their own keepering.
    uint256 internal constant SUBSCRIBER_CAP = 1000;

    /// @dev Per-sub gas-weight of a LOOTBOX buy — the unit the ticket/evict weights are ratioed
    ///      against. Measured ≈34k marginal; pinned at 2 (not 1) so ticket (≈73k → 4) and evict
    ///      (≈18k → 1) land on integer ratios and every op costs ~18k per weight-unit, making the
    ///      chunk gas composition-flat (`per-call overhead + budget × ~18k`, any mix).
    uint256 internal constant SUB_STAGE_LOOTBOX_WEIGHT = 2;

    /// @dev Per-sub gas-weight of an in-stage sub-ending finalize (cancel-reclaim / pass-evict
    ///      / funding-kill) relative to the lootbox-buy unit (weight 2). The finalize does a
    ///      cross-contract quest read + streak write the call-free buy does not; measured ≈18k vs
    ///      the ≈34k lootbox marginal → weight 1. The chunk ends on accumulated weight, bounding
    ///      every mix under the advance-chain ceiling.
    uint256 internal constant SUB_STAGE_EVICT_WEIGHT = 1;

    /// @dev Per-sub gas-weight of a TICKET buy relative to the lootbox-buy unit (weight 2). A
    ///      ticket queues a cold ticketQueue push + an owed-mapping SSTORE the lootbox stamp does
    ///      not — measured ≈73k vs the ≈34k lootbox marginal → weight 4. Weighting the two buy
    ///      modes by true marginal cost makes the chunk gas composition-flat (~18k per weight-unit
    ///      either way), so the budget binds on real gas, not sub count.
    uint256 internal constant SUB_STAGE_TICKET_WEIGHT = 4;

    /// @dev Slot-0 quest completion reward — mirrors `DegenerusQuests.QUEST_SLOT0_REWARD`
    ///      (a private constant not visible cross-contract). Each delivered afking buy accrues
    ///      `QUEST_SLOT0_REWARD` (whole BURNIE) into the sub's claimable `pendingBurnie`, pulled
    ///      via `claimAfkingBurnie`. Only values the BURNIE mint, off the solvency path.
    uint256 internal constant QUEST_SLOT0_REWARD = 100 ether;

    /// @dev Prize-pool routing splits for the batched afking buy, mirroring the canonical
    ///      `DegenerusGameMintModule.LOOTBOX_SPLIT_FUTURE_BPS` (9000) and
    ///      `DegenerusGame.PURCHASE_TO_FUTURE_BPS` (1000) — both private cross-contract. A
    ///      lootbox spend routes 90% future / 10% next; a ticket spend the inverse.
    uint256 internal constant AFKING_LOOTBOX_FUTURE_BPS = 9000;
    uint256 internal constant AFKING_TICKET_FUTURE_BPS = 1000;

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

    /// @dev Open-leg default box-count budget (the post-RNG `_subOpenCursor` drain). The per-box
    ///      open is uniform O(1) (the afking box rolls boons like a human box). Measured ≈74k/box
    ///      (worst box): 80 boxes ≈ 9.15M, under the 10M comfort target and far under the 16.7M
    ///      hard ceiling.
    uint256 internal constant OPEN_BATCH = 80;

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
            _creditAfking(fundDest, msg.value);
            claimablePool += uint128(msg.value);
        }

        // CANCEL branch — dailyQuantity == 0 writes the `dailyQuantity = 0` tombstone in
        // place and relocates no one (the in-pass reclaim swap-pops the tombstone when the
        // process stage reaches it). Revert if the caller has no active sub. Any msg.value
        // above was still credited to funding, so a cancel-with-ETH never strands the
        // deposit (it stays game-side withdrawable).
        if (dailyQuantity == 0) {
            if (_subscriberIndex[subscriber] == 0) revert NotSubscribed();
            Sub storage c = _subOf[subscriber];
            // Auto-claim BEFORE clearing: the next advance-driven reclaim deletes the
            // slot (wiping both accumulators), so leaving them for a later pull would
            // lose them in that race. Pay the sub its own pendingBurnie (CEI: zero
            // first), then settle the upline affiliate tree, THEN finalize + tombstone.
            uint256 owed = uint256(c.pendingBurnie); // whole BURNIE
            if (owed != 0) {
                c.pendingBurnie = 0;
                if (!presaleOver) {
                    uint256 credit = (owed * 0.0025 ether) / 100;
                    if ((c.flags & FLAG_USE_TICKETS) != 0)
                        credit /= (c.dailyQuantity >= 10 ? 3 : 2);
                    presaleBoxCredit[subscriber] += credit;
                }
                coinflip.creditFlip(subscriber, owed * 1 ether);
            }
            // Drain affiliateBase to the 75/20/5 upline tree (50/50 VAULT/DGNRS if no
            // referrer). The affiliate consumes the base via the AFFILIATE-only
            // drainAffiliateBase callback, so this must run while the slot still holds it.
            address[] memory drainOne = new address[](1);
            drainOne[0] = subscriber;
            IDegenerusAffiliate(ContractAddresses.AFFILIATE).claim(drainOne);

            // Hand the afking-computed streak back to the manual quest system, then tombstone.
            _finalizeAfking(subscriber, c, _simulatedDayIndex());
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

        // Captured BEFORE the dailyQuantity overwrite: a non-zero stored dailyQuantity means the
        // sub is mid-afking-run (afkingActive set) — a re-subscribe CONTINUES that run; 0 means
        // new / cancelled / evicted (afkingActive cleared by a prior finalize) — a fresh run.
        bool wasActive = s.dailyQuantity != 0;

        // Settle the prior run's pendingBurnie under its CURRENT flag + dailyQuantity before the
        // overwrite below, so the presale-box credit keys on the state in force during accrual.
        if (wasActive) {
            uint256 owedPrev = uint256(s.pendingBurnie); // whole BURNIE
            if (owedPrev != 0) {
                s.pendingBurnie = 0;
                if (!presaleOver) {
                    uint256 credit = (owedPrev * 0.0025 ether) / 100;
                    if ((s.flags & FLAG_USE_TICKETS) != 0)
                        credit /= (s.dailyQuantity >= 10 ? 3 : 2);
                    presaleBoxCredit[subscriber] += credit;
                }
                coinflip.creditFlip(subscriber, owedPrev * 1 ether);
            }
        }

        s.dailyQuantity = dailyQuantity;
        if (drainGameCreditFirst) s.flags |= FLAG_DRAIN_FIRST;
        else s.flags &= ~FLAG_DRAIN_FIRST;
        if (useTickets) s.flags |= FLAG_USE_TICKETS;
        else s.flags &= ~FLAG_USE_TICKETS;
        s.reinvestPct = reinvestPct;
        // The two protocol self-subscribers (VAULT / sDGNRS) self-subscribe at
        // construction with no pass and no funds; they are exempt from the pass-required
        // and purchase-grounded gates below, keyed on the un-spoofable resolved subscriber
        // identity. Every other sub must clear both gates.
        bool exemptSub = subscriber == ContractAddresses.VAULT ||
            subscriber == ContractAddresses.SDGNRS;
        // Single read; encodes the subscriber's pass horizon (deity sentinel =
        // type(uint24).max) into the field the per-iter check and crossing branch compare
        // against.
        s.validThroughLevel = _passHorizonOf(subscriber);
        // Pass-required: the just-stored horizon must reach the current level (the deity
        // sentinel type(uint24).max always covers). Reuses the value written above — no
        // second pass read. A zero horizon means NO pass and is rejected at every level —
        // including level 0, where `< level` (0 < 0) would otherwise be vacuously false and
        // let a passless EOA afk through level 0 (a real pass has horizon >= passLevel+99,
        // never 0). A pass valid now can still be outgrown later; the per-iter crossing
        // eviction handles that.
        if (!exemptSub && (s.validThroughLevel == 0 || s.validThroughLevel < level))
            revert NoPass();
        // Sparse funder map: store only a non-self source; clear on self so re-pointing an
        // operator-funded sub back to self does not strand a stale funder. Re-pointing the
        // source IS a re-subscribe, which re-runs the operator-approval gate.
        if (fundingSource != address(0)) {
            _fundingSourceOf[subscriber] = fundingSource;
            s.flags |= FLAG_EXTERNAL_FUNDING;
        } else {
            delete _fundingSourceOf[subscriber];
            s.flags &= ~FLAG_EXTERNAL_FUNDING;
        }

        // Afking-run start (new sub) OR a streak-refreshing cover-buy (active sub re-subscribe).
        {
            uint24 today = _simulatedDayIndex();
            if (wasActive) {
                // ACTIVE sub re-subscribe — subscribe doubles as a manual "keep my streak alive +
                // buy something" action. Do a funded cover-buy for TODAY (advancing the funded
                // high-water afkCoveredThroughDay), which CONTINUES the run's streak via
                // _deliverAfkingBuy's own gap-resume/accrue: a still-current run keeps its streak
                // and gains today; a gapped run re-bases to 0 (a full missed day is gone, same as
                // the stage). No re-snapshot / no forfeit — the afking streak is never reset by a
                // re-subscribe. Skipped (streak just persists + decays on read) when already
                // bought today OR a pending unopened box exists (re-stamping would orphan it — the
                // no-orphan rule) OR the cover-buy is unfunded.
                if (
                    s.lastAutoBoughtDay != uint24(today) &&
                    s.lastOpenedDay >= s.lastAutoBoughtDay
                ) {
                    uint256 mp = _mintPriceInContext();
                    (
                        ,
                        uint256 ethValue,
                        uint256 buyAmount,
                        bool isTicket,
                        uint256 playerFunding,
                        uint256 claimableUse
                    ) = _resolveBuy(s, subscriber, mp);
                    address src = (s.flags & FLAG_EXTERNAL_FUNDING) != 0
                        ? _fundingSourceOf[subscriber]
                        : subscriber;
                    if (
                        (src == subscriber ? playerFunding : _afkingOf(src)) >=
                        ethValue
                    ) {
                        _deliverAfkingBuy(
                            subscriber,
                            s,
                            today,
                            mp,
                            level,
                            src,
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
                uint256 snap = quests.beginAfking(subscriber, today); // syncs + sets afkingActive
                // Frame the run on today (the compute-on-read base; afkCovered == today keeps the
                // delivery's gap-reset from wiping the snapshot and guarantees
                // afkCovered >= afkingStartDay so the streak span never underflows).
                s.afkCoveredThroughDay = uint24(today);
                s.afkingStartDay = uint24(today);

                (, , , bool[2] memory done) = questView.playerQuestStates(subscriber);
                if (s.lastOpenedDay < s.lastAutoBoughtDay) {
                    // A pending unopened box (this or a prior day) already grounds the run on a real
                    // purchase. Keep the snapshot and leave the box markers untouched so the open leg
                    // still materializes it — re-stamping here would orphan the prepaid box.
                    _setStreakBase(s, snap);
                } else if (done[0]) {
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
                    (
                        ,
                        uint256 ethValue,
                        uint256 buyAmount,
                        bool isTicket,
                        uint256 playerFunding,
                        uint256 claimableUse
                    ) = _resolveBuy(s, subscriber, mp);
                    address src = (s.flags & FLAG_EXTERNAL_FUNDING) != 0
                        ? _fundingSourceOf[subscriber]
                        : subscriber;
                    if (
                        (src == subscriber ? playerFunding : _afkingOf(src)) >=
                        ethValue
                    ) {
                        _setStreakBase(s, snap); // funded day-0 — keep the snapshot
                        _deliverAfkingBuy(
                            subscriber,
                            s,
                            today,
                            mp,
                            level,
                            src,
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
                        // today (the done[0] branch above) or a funded in-tx cover-buy (the
                        // branch above). An unfunded start would free-ride the advance gate.
                        revert MustPurchaseToBeginAfking();
                    }
                }
            }
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
    ///      The canonical horizon semantics: deity holders return the type(uint24).max
    ///      sentinel; everyone else returns their frozenUntilLevel. Single definition
    ///      (one canonical horizon read), called at the subscribe-time write + the
    ///      process-pass crossing re-read so both share the exact same semantics.
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
    /// @return claimableUse Claimable portion of `cost` (reinvest / drainFirst); cost == ethValue + claimableUse.
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
            uint256 playerFunding,
            uint256 claimableUse
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
            : _claimableOf(player);
        playerFunding = _afkingOf(player);

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
        claimableUse = drainFirst
            ? (claimable < cost ? claimable : cost)
            : reinvestSpend;
        if (claimable > 0 && claimableUse >= claimable) claimableUse = claimable - 1;
        ethValue = cost - claimableUse;
        payKind = ethValue == 0
            ? MintPaymentKind.Claimable
            : (claimableUse == 0 ? MintPaymentKind.DirectEth : MintPaymentKind.Combined);
    }

    /*------------------------------------------------------------------
              Shared per-sub funded delivery + compute-on-read streak
    ------------------------------------------------------------------*/
    /// @dev The shared per-sub funded delivery — used by both the process STAGE (after its
    ///      pre-buy gates, `coverBuy == false`) and the subscribe-time grounding cover-buy
    ///      (`coverBuy == true`). The slice is already confirmed funded by the caller
    ///      (`afkingFunding[src] >= ethValue`), so this is revert-free by construction (no
    ///      try/catch). Debits the fresh-ETH leg + the reinvest claimable leg (claimablePool in
    ///      tandem, fail-loud on underflow — a debit can never exceed afkingFunding[src] ≤ the
    ///      claimablePool reservation, so a revert here means solvency is already violated and
    ///      must propagate), materializes the buy per mode, accrues the day's affiliate base + the
    ///      slot-0 pendingBurnie reward, advances the compute-on-read streak markers (gap-resuming
    ///      a fresh run from zero if the last funded day is older than yesterday), and sets the
    ///      success marker. The frozen activity score reads the COMPUTE-ON-READ streak off the Sub
    ///      slot — no DegenerusQuests STATICCALL on the hot path. boons OFF ⇒ amount == spend.
    ///
    ///      Lootbox materialization differs by mode: the daily STAGE writes a gas-light warm
    ///      Sub-stamp box (the EV-cap RMW deferred to OPEN), whereas the cover-buy writes a full
    ///      INDEXED box resolved off `lootboxRngWordByIndex` — a future word never knowable at
    ///      subscribe — so a player-timed subscribe cannot select a pre-revealed seed (a
    ///      `rngWordByDay`-keyed Sub-stamp box would break the RNG-freeze invariant here, since
    ///      subscribe runs after the day's word is public). Pool routing also differs: the STAGE
    ///      accrues the cost into the caller's batched per-chunk credit; the cover-buy (a single
    ///      buy) routes inline here.
    /// @param player The subscriber being delivered to (the credit recipient).
    /// @param sub The subscriber's record (storage ref — stamped/accrued here).
    /// @param processDay The delivered day (the stamp's frozen seed day + the streak marker).
    /// @param mp The in-context mint price.
    /// @param currentLevel The hoisted level (the buy's target-level base).
    /// @param src The funding bucket the fresh-ETH leg debits.
    /// @param ethValue The fresh-ETH portion (0 = pure claimable).
    /// @param claimableUse The reinvest/drainFirst claimable portion of the cost.
    /// @param amount Ticket entry-units (ticket mode) or lootbox spend in wei (lootbox mode).
    /// @param isTicket Mode — true = queue tickets, false = a lootbox box.
    /// @param coverBuy True = subscribe-time grounding buy (indexed box + inline pool routing);
    ///        false = daily STAGE buy (Sub-stamp box + caller-batched pool routing).
    function _deliverAfkingBuy(
        address player,
        Sub storage sub,
        uint24 processDay,
        uint256 mp,
        uint24 currentLevel,
        address src,
        uint256 ethValue,
        uint256 claimableUse,
        uint256 amount,
        bool isTicket,
        bool coverBuy
    ) private {
        if (ethValue != 0) {
            _debitAfking(src, ethValue);
            claimablePool -= uint128(ethValue);
        }
        // Reinvest/drainFirst claimable portion of the cost. The _resolveBuy 1-wei sentinel
        // guarantees claimableUse <= claimable - 1, so this never underflows. claimableWinnings
        // rides in claimablePool, so the pool moves in tandem (the SOLVENCY-01 invariant).
        if (claimableUse != 0) {
            _debitClaimable(player, claimableUse);
            claimablePool -= uint128(claimableUse);
        }

        if (isTicket) {
            // Ticket minimal-write primitive: queue resolution-equivalent ticket entries and
            // accrue the ticket buyer-bonus into the warm Sub slot. The affiliate flat-7% and the
            // slot-0 reward are added by the mode-agnostic accrue below (not re-accrued here).
            uint24 targetLevel = jackpotPhaseFlag
                ? currentLevel
                : currentLevel + 1;

            // Century (x00-level) quantity bonus at parity with the manual mint, reusing the
            // per-player centuryBonusUsed storage and the per-buy activity score
            // off the COMPUTE-ON-READ streak (no STATICCALL). The purchase-boost quantity
            // multiplier is omitted, matching the boons-off lootbox leg.
            uint32 adjustedQty = uint32(amount);
            if (targetLevel % 100 == 0) {
                uint256 cachedScore = _playerActivityScore(
                    player,
                    _afkingStreak(sub, processDay),
                    targetLevel
                );
                if (cachedScore != 0) {
                    uint256 priceWei = PriceLookupLib.priceForLevel(targetLevel);
                    uint256 _score = cachedScore > 30_500 ? 30_500 : cachedScore;
                    uint256 bonusQty = (uint256(adjustedQty) * _score) / 30_500;
                    if (bonusQty != 0 && priceWei != 0) {
                        uint256 maxBonus = (20 ether) / (priceWei >> 2);
                        uint256 used = _centuryUsedFor(player, targetLevel);
                        uint256 remaining = maxBonus > used ? maxBonus - used : 0;
                        if (bonusQty > remaining) bonusQty = remaining;
                        if (bonusQty != 0) {
                            _setCenturyUsedFor(player, targetLevel, used + bonusQty);
                            adjustedQty += uint32(bonusQty);
                        }
                    }
                }
            }

            _queueTicketsScaled(player, targetLevel, adjustedQty, false);

            // 10%/20% ticket buyer-bonus → claimable pendingBurnie (pulled via
            // claimAfkingBurnie). Uses the pre-bonus `amount`; whole BURNIE with the 100M clamp.
            uint256 coinCost = (amount * (PRICE_COIN_UNIT / 4)) / TICKET_SCALE;
            uint256 bonusBase = coinCost / 10; // flat 10%
            if (amount >= 10 * 4 * TICKET_SCALE) {
                bonusBase += (amount * PRICE_COIN_UNIT) / (40 * TICKET_SCALE); // +10% → 20% on ≥10 tickets
            }
            uint256 bonusWhole = bonusBase / 1 ether;
            if (bonusWhole != 0) {
                uint256 newOwed = uint256(sub.pendingBurnie) + bonusWhole;
                if (newOwed > 100_000_000) newOwed = 100_000_000;
                sub.pendingBurnie = uint32(newOwed);
            }

            // No pending box: keep lastOpenedDay == lastAutoBoughtDay so the no-orphan guard and
            // _afkingBoxReady never treat a ticket sub as box-pending.
            sub.lastOpenedDay = uint24(processDay);
        } else {
            // Lootbox box. The per-buy manual side-effects (handlePurchase, affiliate ×2, the
            // per-buy creditFlip) are deferred to the in-slot accrue (affiliate pulled via
            // drainAffiliateBase; the slot-0 reward into pendingBurnie). The frozen score
            // (the EV input at open, off the compute-on-read streak — no STATICCALL) is computed
            // once for either box shape.
            uint256 activityScore = _playerActivityScore(
                player,
                _afkingStreak(sub, processDay),
                currentLevel + 1
            );
            uint16 score = activityScore > type(uint16).max
                ? type(uint16).max
                : uint16(activityScore);
            if (coverBuy) {
                // Subscribe-time grounding box: a full INDEXED box on the live lootbox index,
                // resolved off lootboxRngWordByIndex (a future word). Rides the auto-open queue,
                // so the markers go box-clean (lastOpenedDay == lastAutoBoughtDay) and the
                // no-orphan guard never trips on a freshly-subscribed sub.
                _recordAfkingCoverBox(
                    player,
                    currentLevel,
                    amount,
                    score,
                    activityScore
                );
                sub.lastOpenedDay = uint24(processDay);
            } else {
                // Daily STAGE Sub-stamp box: the warm Sub slot IS the box record (no cold
                // ledger); the EV-cap RMW is deferred to OPEN, fed this frozen score, and
                // the level + EV-cap key read LIVE at open. milli-ETH stamp (the EV/seed input
                // only — the ETH debit used the full wei ethValue).
                sub.score = score;
                sub.amount = uint24(_packEthToMilliEth(amount));
            }
        }

        // Mode-agnostic accrue — one warm in-slot write, zero cross-contract calls:
        //   • affiliate base: flat 7% of the full wei spend (ethValue + claimableUse = the cost in
        //     both modes; the dual-unit `amount` is entry-units in ticket mode), whole BURNIE, 100M clamp;
        //   • slot-0 quest reward: QUEST_SLOT0_REWARD (whole BURNIE) into the claimable pendingBurnie;
        //   • compute-on-read streak markers: gap-resume a fresh run from zero if the last funded
        //     day is older than yesterday (matching the decay-on-read), then advance the
        //     funded-day high-water mark afkCoveredThroughDay.
        {
            uint256 base = ((_ethToBurnie(ethValue + claimableUse, mp) * 7) / 100) / 1 ether;
            if (base != 0) {
                uint256 newBase = uint256(sub.affiliateBase) + base;
                if (newBase > 100_000_000) newBase = 100_000_000;
                sub.affiliateBase = uint32(newBase);
            }
            {
                uint256 newOwed = uint256(sub.pendingBurnie) +
                    (QUEST_SLOT0_REWARD / 1 ether);
                if (newOwed > 100_000_000) newOwed = 100_000_000;
                sub.pendingBurnie = uint32(newOwed);
            }
            if (sub.afkCoveredThroughDay + 1 < processDay) {
                sub.afkingStartDay = uint24(processDay);
                _setStreakBase(sub, 0);
            }
            sub.afkCoveredThroughDay = uint24(processDay);
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
    }

    /// @dev Write a subscribe-time grounding lootbox as a full INDEXED box on the live lootbox
    ///      index — the cover-buy's freeze-safe box record, mirroring the manual
    ///      `_recordLootboxEntry` minus the boons-off legs (no boost, no distress tally, no
    ///      mint-day record). The box binds to `lootboxRngWordByIndex[index]` — a future word
    ///      written at the next advance, never knowable at subscribe — and rolls from the LIVE
    ///      open level, so the stored day and purchase-level are pure seed labels (the day-1
    ///      genesis box resolves on its index word at the first advance, unlike `rngWordByDay[1]`,
    ///      which is never written, so a genesis lootbox sub is never bricked). First deposit
    ///      enqueues the index for the permissionless auto-open cursor and runs the purchase-time
    ///      EV-cap tally (a bonus box draws `add = min(spend, CAP - used)` from the shared
    ///      per-(player, level) accumulator, freezing the adjustedPortion into the packed word); a
    ///      subsequent deposit at the same un-advanced index accumulates onto it with the
    ///      multiplier frozen from the first-deposit score. The EV-cap key is `currentLevel + 1`
    ///      (== the resolver's open level = level + 1).
    /// @param player The box recipient.
    /// @param currentLevel The live game level (== the STAGE's hoisted currentLevel).
    /// @param amount The lootbox spend in wei (boons off ⇒ no boost; amount == spend).
    /// @param score The frozen activity score EV input (first deposit only).
    /// @param activityScore The raw activity score (first-deposit EV mult; == score, uncapped).
    function _recordAfkingCoverBox(
        address player,
        uint24 currentLevel,
        uint256 amount,
        uint16 score,
        uint256 activityScore
    ) private {
        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        uint24 capKey = currentLevel + 1; // resolver open level == the per-(player, level) cap key
        uint256 packed = lootboxEth[index][player];
        uint256 existingAmount = packed & LB_AMOUNT_MASK;

        uint16 sc;
        uint64 adj;
        if (existingAmount == 0) {
            sc = score;
            if (
                _lootboxEvMultiplierFromScore(activityScore) >
                LOOTBOX_EV_NEUTRAL_BPS
            ) {
                uint256 used = lootboxEvBenefitUsedByLevel[player][capKey];
                uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                    ? 0
                    : LOOTBOX_EV_BENEFIT_CAP - used;
                uint256 add = amount < remaining ? amount : remaining;
                lootboxEvBenefitUsedByLevel[player][capKey] = used + add;
                adj = uint64(add);
            }
            // First deposit for this (index, player): enqueue for the permissionless auto-open
            // cursor (the consumer gates each index on lootboxRngWordByIndex != 0, so this is
            // producer-only). The box is discovered via that cursor walk, not an event.
            boxPlayers[index].push(player);
        } else {
            // Subsequent deposit at the same un-advanced index (only reachable in the
            // pre-first-advance genesis window): the frozen score and accumulated adj come
            // from the box's prior packed word, the multiplier stays FROZEN from the
            // first-deposit snapshot.
            (, uint64 priorAdj, uint16 priorScore, ) = _unpackLootbox(packed);
            sc = priorScore;
            adj = priorAdj;
            if (amount != 0) {
                if (
                    _lootboxEvMultiplierFromScore(uint256(priorScore)) >
                    LOOTBOX_EV_NEUTRAL_BPS
                ) {
                    uint256 used = lootboxEvBenefitUsedByLevel[player][capKey];
                    uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                        ? 0
                        : LOOTBOX_EV_BENEFIT_CAP - used;
                    uint256 add = amount < remaining ? amount : remaining;
                    if (add != 0) {
                        lootboxEvBenefitUsedByLevel[player][capKey] = used + add;
                        adj = priorAdj + uint64(add);
                    }
                }
            }
        }

        // boons OFF for afking covers ⇒ no boost, so the stored amount is the raw spend; the
        // afking path never writes distress (preserved as zero in the packed word). All live
        // fields land in the single lootboxEth slot.
        uint256 distressUnits = (packed >> LB_DISTRESS_SHIFT) & LB_DISTRESS_MASK;
        lootboxEth[index][player] =
            _packLootbox(existingAmount + amount, adj, sc, distressUnits);
        _lrWrite(
            LR_PENDING_ETH_SHIFT,
            LR_PENDING_ETH_MASK,
            _lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK) +
                _packEthToMilliEth(amount)
        );

        // One box-buy event across paths (same topic as the mint + whale LootBoxBuy).
        emit LootBoxBuy(
            player,
            index,
            amount,
            _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0
        );
    }

    /// @dev Compute-on-read effective afking quest streak from the Sub slot — no DegenerusQuests
    ///      STATICCALL. The run's snapshot (`streakAtAfkingStart`) plus the funded delivered days
    ///      since the run's base day, while the last funded day is no older than yesterday;
    ///      otherwise 0 (decay-on-read: miss one full day and the streak is gone). Capped to 100
    ///      downstream by the activity score.
    function _afkingStreak(Sub storage sub, uint24 currentDay)
        private
        view
        returns (uint32)
    {
        uint24 covered = sub.afkCoveredThroughDay;
        if (currentDay == 0 || covered + 1 < currentDay) return 0;
        return uint32(_streakBaseOf(sub)) + uint32(covered - sub.afkingStartDay);
    }

    /// @dev Hand the afking-computed streak back to the manual quest system on a sub-ending path,
    ///      BEFORE the Sub slot is deleted. Computes the run's earned streak (snapshot + funded
    ///      delivered days) and the afking funded high-water day, then defers the decay decision
    ///      and the anchor to `quests.finalizeAfking`, which also folds in any manual completion
    ///      day (so a sub who let afking funding lapse but kept minting manually is not wrongly
    ///      zeroed) and is idempotent (a no-op if the player is not currently afking — safe for the
    ///      cancel-then-reclaim double call). Clears the Sub's afking framing. The cross-contract
    ///      read+write is the heavier (EVICT_WEIGHT) STAGE branch.
    /// @param player The subscriber whose run is ending.
    /// @param sub The subscriber's record (storage ref — afking framing cleared here).
    /// @param currentDay The current day (the decay reference passed to DegenerusQuests).
    function _finalizeAfking(
        address player,
        Sub storage sub,
        uint24 currentDay
    ) private {
        uint24 covered = sub.afkCoveredThroughDay;
        uint256 earned = uint256(_streakBaseOf(sub)) +
            (covered - sub.afkingStartDay);
        quests.finalizeAfking(
            player,
            earned > type(uint24).max ? type(uint24).max : uint24(earned),
            covered,
            currentDay
        );
        sub.afkingStartDay = 0;
        _setStreakBase(sub, 0);
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
    ///         genuinely-per-sub box inputs (`score`, `amount`) warm-dirty into the
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
    ///      derived from the stamped `score`. The ticket path defers all EV to the
    ///      MintModule buy (it computes the ticket's own activity score on the buy path).
    /// @dev NO error-swallowing valve (REVERT-02 no-valve, D-348-04): a funded slice is
    ///      revert-free by construction (REVERT-01); there is no pre-emptive lootbox skip;
    ///      rule-(1) unfunded eviction is a separate pre-buy decision
    ///      (a NORMAL sub is auto-paused via swap-pop; VAULT/SDGNRS are EXEMPT by pinned
    ///      identity); the SOLVENCY-01 `claimablePool -=` site FAILS LOUD (class B, must
    ///      propagate). The per-cycle eviction cap is DROPPED.
    /// @param processDay The boundary-pinned process day (computed once by the STAGE).
    /// @param weightBudget Per-call gas-weight budget (caller-bounded — the anti-gas-DoS
    ///        property). Each iteration consumes weight — a cheap local buy/skip 1, a
    ///        cross-contract sub-ending finalize `SUB_STAGE_EVICT_WEIGHT` — and the chunk ends
    ///        when the accumulated weight reaches the budget, bounding even an all-evicts chunk.
    /// @return processed Number of set entries advanced/handled this chunk.
    function processSubscriberStage(
        uint24 processDay,
        uint256 weightBudget
    ) external returns (uint256 processed) {
        uint256 mp = _mintPriceInContext();
        // AFSUB-02 — hoist the level read ONCE so the per-iter validity check is a pure
        // stored-field compare (no SLOAD on the non-crossing path). GASOPT-05 preserved.
        uint24 currentLevel = level;

        uint256 cursor = _subCursor;
        uint256 weight; // accumulated gas-weight; the chunk ends at weightBudget
        // Batched prize-pool routing: each funded buy debits its full cost from the funding
        // source and accrues that spend here by mode; the pools are credited ONCE at chunk end
        // (boxes 90% future / 10% next, tickets 90% next / 10% future) so the per-sub cost is
        // an add, not a pool SSTORE.
        uint256 boxEthAccrued;
        uint256 ticketEthAccrued;

        while (weight < weightBudget && cursor < _subscribers.length) {
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
                    ++weight;
                }
                continue;
            }

            // (0) Cancel-tombstone reclaim (CONSENT-02 — SUB-07 / H-CANCEL-SWAP-MISS).
            // An externally-cancelled sub (subscribe(_, 0)) is an in-set
            // `dailyQuantity == 0` tombstone: it relocated no one on cancel, so it cannot
            // have pushed a pending entry behind the cursor. Finalize the afking streak (a
            // no-op if the cancel already did — idempotent), then delete the `_subOf` record,
            // swap-pop it out, and continue WITHOUT advancing the cursor — the swap-pop
            // occupant (a mover from ahead, still pending) is processed at this slot this pass.
            // Ordered ahead of the AlreadyAutoBoughtToday skip so a tombstone is ALWAYS
            // reclaimed, independent of its lastAutoBoughtDay. The finalize is the cross-contract
            // work that makes this the heavier (EVICT_WEIGHT) branch.
            if (sub.dailyQuantity == 0) {
                _finalizeAfking(player, sub, processDay);
                // The streak base was already handed back to the manual streak by the finalize
                // above, so the sub is fully cleared on reclaim.
                delete _subOf[player];
                _removeFromSet(player);
                emit SubscriptionExpired(player, 2);
                unchecked {
                    ++processed;
                    weight += SUB_STAGE_EVICT_WEIGHT;
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
                    ++weight;
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
                    sub.validThroughLevel = h;
                    emit SubscriptionExtendedFree(player, processDay);
                } else {
                    // EVICT — finalize the afking streak (hand it back), then delete the slot
                    // and swap-pop out of the set (no cursor advance after the swap-pop). The
                    // finalize is the EVICT_WEIGHT cross-call. A got-kicked sub forfeits both
                    // accumulators: deleting _subOf wipes pendingBurnie / affiliateBase so
                    // nothing survives claimable out-of-set.
                    _finalizeAfking(player, sub, processDay);
                    delete _subOf[player];
                    _removeFromSet(player);
                    emit SubscriptionExpired(player, 1);
                    unchecked {
                        ++processed;
                        weight += SUB_STAGE_EVICT_WEIGHT;
                    }
                    continue;
                }
            }

            // Funding resolution (cost + payment mode + ethValue slice). The slice builder
            // computes everything revert-free by construction.
            (
                ,
                uint256 ethValue,
                uint256 amount,
                bool isTicket,
                uint256 playerFunding,
                uint256 claimableUse
            ) = _resolveBuy(sub, player, mp);

            // Resolve the once-per-iteration funding source. The common self-funded path
            // is detected from the already-loaded `sub.flags` (FLAG_EXTERNAL_FUNDING clear
            // ⇒ src = player) and skips the `_fundingSourceOf` SLOAD entirely; only the rare
            // operator-funded sub (flag set) reads the sparse map. Both the funding skip-gate
            // read and the debit key on this same `src`. The VAULT/SDGNRS exemption below
            // stays keyed on the un-spoofable `player`, never `src`.
            address src = (sub.flags & FLAG_EXTERNAL_FUNDING) != 0
                ? _fundingSourceOf[player]
                : player;

            // Funding skip → two-tier skip-kill. Read afkingFunding[src]: the common path
            // (src == player) reuses `playerFunding` from _resolveBuy (no extra SLOAD); the
            // rare operator-funded slice (src != player) reads afkingFunding[src]. A normal
            // underfunded sub is cancelled via swap-pop (auto-pause WITHOUT advancing the
            // cursor — the mover into this slot is processed this pass). VAULT and sDGNRS are
            // exempt by the un-spoofable pinned ContractAddresses identity (kept on `player`,
            // never `src`) — a funding skip is transient for them (no-op-and-retry, stays in
            // the set). The exemption is the pinned-address branch only; there is no flag.
            if (
                (src == player ? playerFunding : _afkingOf(src)) < ethValue
            ) {
                if (
                    player == ContractAddresses.VAULT ||
                    player == ContractAddresses.SDGNRS
                ) {
                    emit PlayerSkipped(player, 3);
                    unchecked {
                        ++cursor;
                        ++processed;
                        ++weight;
                    }
                    continue;
                }
                // Funding-kill of a NORMAL underfunded sub — finalize the afking streak (hand it
                // back; its decay-on-read zeroes only if a full prior day was missed with NO
                // valid mint, afking OR manual), then delete the slot + swap-pop. A got-kicked
                // sub forfeits both accumulators: deleting _subOf wipes pendingBurnie /
                // affiliateBase so nothing survives claimable out-of-set.
                _finalizeAfking(player, sub, processDay);
                delete _subOf[player];
                _removeFromSet(player);
                emit SubscriptionExpired(player, 1);
                unchecked {
                    ++processed;
                    weight += SUB_STAGE_EVICT_WEIGHT;
                }
                continue;
            }

            // BUY + DEBIT + ACCRUE + MARKER. The funded, well-formed slice is delivered
            // revert-free by construction (no try/catch) by the shared `_deliverAfkingBuy`:
            // debit `afkingFunding[src]` (claimablePool in tandem, fail-loud on underflow),
            // stamp the lootbox box / queue the tickets, accrue the day's affiliate + the
            // pendingBurnie reward, advance the compute-on-read streak markers (gap-resuming a
            // fresh run if a day was missed), and set the success marker. A lootbox buy is weight
            // SUB_STAGE_LOOTBOX_WEIGHT; a ticket buy SUB_STAGE_TICKET_WEIGHT (the cold ticketQueue
            // push makes it ~2x a lootbox), so the budget binds on the true per-buy cost.
            _deliverAfkingBuy(
                player,
                sub,
                processDay,
                mp,
                currentLevel,
                src,
                ethValue,
                claimableUse,
                amount,
                isTicket,
                false
            );

            // Accrue the full buy cost (afking ethValue + reinvest claimableUse) for the
            // batched pool credit below — a box buy funds the box pool, a ticket buy the ticket
            // pool. The afking entry-unit `amount` is the box's wei spend only in lootbox mode,
            // so the routing keys on `cost`, never `amount`.
            uint256 cost = ethValue + claimableUse;
            if (isTicket) ticketEthAccrued += cost;
            else boxEthAccrued += cost;

            unchecked {
                ++cursor;
                ++processed;
                weight += isTicket ? SUB_STAGE_TICKET_WEIGHT : SUB_STAGE_LOOTBOX_WEIGHT;
            }
        }

        // Persist the advanced cursor (uint16) for the next chunk / call.
        _subCursor = uint16(cursor);
        // Credit the prize pools once for this chunk's batched box + ticket spend.
        _routeAfkingPoolEth(boxEthAccrued, ticketEthAccrued);
        return processed;
    }

    /// @dev Route a chunk's batched afking spend to the prize pools, mirroring the normal-buy
    ///      splits: lootbox ETH 90% future / 10% next (100% next in distress, matching
    ///      `_purchaseForWith`), ticket ETH 90% next / 10% future (matching `recordMint`). One
    ///      pooled read+write per chunk; routes to the pending pools while the prize pool is
    ///      frozen. The per-buy debit already moved the ETH out of the funding source, so this
    ///      only credits the pools (the SOLVENCY-01 counterpart of that debit).
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
    ///      stamp day); the level and the EV-cap key read live inside `resolveAfkingBox`;
    ///      the per-sub inputs (amount, score) come from the Sub record. Day-keyed
    ///      no-double-open: the leg runs only while `lastOpenedDay < lastAutoBoughtDay`
    ///      (pre-gated by `_afkingBoxReady`), and advances the marker
    ///      (`lastOpenedDay = lastAutoBoughtDay`) BEFORE the resolve (effects-before-
    ///      interaction; a re-entrant open re-checks the now-equal marker and no-ops). The
    ///      box is materialized by delegatecalling the LootboxModule's `resolveAfkingBox`
    ///      (the live-level twin of `resolveLootboxDirect`) with: the stamped spend (boons
    ///      OFF ⇒ amount == spend), the frozen process `day` = `lastAutoBoughtDay`, the
    ///      frozen day's word `rngWordByDay[day]`, and the frozen
    ///      `activityScore = score`. The draw math and the single EV-cap RMW live in
    ///      `resolveAfkingBox`; this leg is the thin cursor/marker/dispatch shell.
    ///      `resolveAfkingBox` is the one freeze-correct seam (the public
    ///      `resolveLootboxDirect` derives its seed from the live day and would NOT freeze the
    ///      seed `day`). No stored baseLevel/index — the live roll needs no floor.
    /// @param player The subscriber whose box is materialized.
    /// @param sub The subscriber's stamped record (storage ref — the marker advances here).
    function _openAfkingBox(address player, Sub storage sub, uint256 word) private {
        // lastAutoBoughtDay is the frozen stamp day used as the seed/word key.
        uint24 day = sub.lastAutoBoughtDay;
        // Advance the day-keyed no-double-open marker BEFORE the resolve (effects-first; a
        // re-entrant open re-checks `lastOpenedDay < lastAutoBoughtDay` → false → no-op).
        sub.lastOpenedDay = sub.lastAutoBoughtDay;

        // boons OFF ⇒ the stamped spend IS the box amount (unpacked milli-ETH → wei). The
        // word (the frozen stamp day's `rngWordByDay[day]`, passed in from the readiness check
        // so it isn't re-read) keeps the open from being re-seeded; the level and EV-cap read
        // live in the callee. No index, no baseLevel.
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveAfkingBox.selector,
                    player,
                    _unpackMilliEthToWei(uint64(sub.amount)), // milli-ETH → wei
                    day,
                    word,
                    uint16(sub.score)
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice The post-RNG afking-box OPEN leg — an `OPEN_BATCH`-style router category
    ///         driven by `_subOpenCursor` (not folded into advance).
    /// @dev The open leg no-ops during the freeze (a mid-day RNG lock or the terminal-jackpot
    ///      liveness control), so the loop body cannot revert under the entry-gate (each open
    ///      is pre-gated on a landed word) — no per-item try/catch. Walks `_subscribers` from
    ///      `_subOpenCursor`, opening up to `maxCount` materializable boxes; the per-sub
    ///      day-keyed `lastOpenedDay` marker makes the walk idempotent, so the cursor
    ///      wrap-resets to 0 at the set end (a re-walk skips already-opened subs by the marker
    ///      — no extra per-index storage). Concurrent callers self-partition via the advancing
    ///      cursor.
    /// @param maxCount Max boxes to open this call (0 = OPEN_BATCH). Caller-bounded; every
    ///        afking box is uniform O(1), like a human box.
    /// @return opened The number of afking boxes materialized this call.
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

        // Day-cache: the boxes in one pass are almost always all stamped on the current day,
        // so the frozen stamp-day word is read from `rngWordByDay` once per DISTINCT day, not
        // once per box. Mixed days CAN occur (the open leg falls behind OPEN_BATCH or a keeper
        // skips a day → the no-orphan rule keeps an old-day box), so each box still resolves
        // ITS OWN stamp day — the cache only short-circuits the repeated same-day SLOAD, never
        // crosses a box to another day's word (the seed-freeze invariant).
        uint24 cachedDay;
        uint256 cachedWord; // != 0 ⇒ cache holds rngWordByDay[cachedDay]

        while (cursor < len && opened < maxCount) {
            address player = _subscribers[cursor];
            Sub storage sub = _subOf[player];
            unchecked {
                ++cursor;
            }
            // Skip subs with no pending box (already-opened: lastOpenedDay >= lastAutoBoughtDay).
            uint24 stampDay = sub.lastAutoBoughtDay;
            if (sub.lastOpenedDay >= stampDay) continue;
            // Resolve this box's frozen stamp-day word — cache hit on the common same-day path.
            uint256 word;
            if (stampDay == cachedDay && cachedWord != 0) {
                word = cachedWord;
            } else {
                word = rngWordByDay[stampDay];
                cachedDay = stampDay;
                cachedWord = word;
            }
            // word == 0 ⇒ the stamp day's word hasn't landed yet — skip until it does.
            if (word == 0) continue;
            // Guaranteed-non-reverting under the entry-gate + the readiness pre-gate.
            _openAfkingBox(player, sub, word);
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
            // Read pay-eligibility BEFORE the advance — it sees the pre-advance day (the
            // advance bumps dailyIdx). The advance work runs regardless; an ineligible
            // keeper just earns no bounty (real participants get first shot, free cranks
            // are welcome).
            bool eligible = _bountyEligible(msg.sender);
            uint8 mult = IGameRouter(address(this)).advanceGame();
            if (mult > 0 && eligible) bountyEarned = unit * ADVANCE_RATIO_NUM * mult;
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

    /// @notice Drain up to `count` ready afking boxes (walks `_subOpenCursor`); returns the
    ///         number opened so the caller can budget the remaining per-tx work. Unrewarded —
    ///         only mintBurnie() credits. Reached via the Game's openBoxes() liveness valve
    ///         (a distinct selector from the Game's human-box autoOpen(uint256), so the two
    ///         do not collide; calling this module contract directly hits empty storage).
    /// @param count Max afking boxes to open this call (0 = the default OPEN_BATCH).
    /// @return opened The number of afking boxes opened this call.
    function drainAfkingBoxes(uint256 count) external returns (uint256 opened) {
        return _autoOpen(count);
    }

    /// @dev In-context mint price (the bounty's ETH→BURNIE conversion divisor). Mirrors
    ///      the Game's `mintPrice` (:2501) — the price for the active ticket level —
    ///      read in-context so the bounty math needs no external/self call. Single use
    ///      site (the bounty `unit`); never an open-time seed input (FREEZE-safe).
    function _mintPriceInContext() internal view returns (uint256) {
        return PriceLookupLib.priceForLevel(_activeTicketLevel());
    }

    /// @dev ETH-denominated spend → BURNIE base units at the buy-context ticket price —
    ///      the VALUATION BASIS for the lootbox-branch affiliate routing (DESIGN §3:
    ///      affiliate + quest rewards are BURNIE flip-credit, never an ETH cut). A faithful
    ///      copy of MintModule._ethToBurnieValue (:1669-1675); PRICE_COIN_UNIT (= 1000 ETH)
    ///      is the inherited Storage constant already used at the bounty unit (:913). Pure —
    ///      no ETH moves, no state.
    function _ethToBurnie(
        uint256 amountWei,
        uint256 priceWei
    ) private pure returns (uint256) {
        if (amountWei == 0 || priceWei == 0) return 0;
        return (amountWei * PRICE_COIN_UNIT) / priceWei;
    }

    /*------------------------------------------------------------------
                                  BURNIE claim
    ------------------------------------------------------------------*/
    /// @notice Permissionless BURNIE claim — pays each sub its accrued `pendingBurnie` (the
    ///         per-delivered-day slot-0 quest reward + the ticket buyer-bonus) in ONE
    ///         `creditFlip` and zeroes it, so a re-claim finds 0. Always credits the sub, never
    ///         the caller; callable anytime — the reward is already earned per delivered day,
    ///         so there is no settle-timing or claim-timing edge to exploit. Off the solvency
    ///         path: a BURNIE flip-credit, never an ETH cut.
    /// @param subs The subscribers to pay (each credited its own accrued `pendingBurnie`).
    function claimAfkingBurnie(address[] calldata subs) external {
        uint256 len = subs.length;
        // Presale-box eligibility for afking buyers, materialized at claim (no advance-path cost).
        // The slot-0 BURNIE owed approximates the afking mint spend (100 whole BURNIE == one
        // 0.01-ETH early-level buy, the price at the levels presale spans), and 25% of that spend is
        // the manual buyer's presale-box credit. Granting it off the DRAINED `owed` counts each
        // BURNIE exactly once (cover-buys included — they accrue slot-0 like any buy), so there is no
        // double-count. Only while presale is open; the credit is unspendable once presaleOver.
        bool presaleLive = !presaleOver;
        for (uint256 i; i < len; ) {
            address player = subs[i];
            Sub storage s = _subOf[player];
            uint256 owed = uint256(s.pendingBurnie); // whole BURNIE
            if (owed != 0) {
                s.pendingBurnie = 0; // CEI: zero before the external credit
                if (presaleLive) {
                    // A ticket sub's pendingBurnie also carries the quantity-scaling buyer-bonus
                    // on top of the flat slot-0, overstating the mint spend — divide the ticket
                    // grant back toward it: /3 for heavy buyers (dailyQuantity >= 10, where the
                    // bonus doubles to 20%), else /2.
                    uint256 credit = (owed * 0.0025 ether) / 100;
                    if ((s.flags & FLAG_USE_TICKETS) != 0)
                        credit /= (s.dailyQuantity >= 10 ? 3 : 2);
                    presaleBoxCredit[player] += credit;
                }
                coinflip.creditFlip(player, owed * 1 ether); // whole → base units
            }
            unchecked {
                ++i;
            }
        }
    }

    /*------------------------------------------------------------------
                            Affiliate base accessor
    ------------------------------------------------------------------*/
    /// @notice Affiliate-only atomic read-and-zero of a sub's accrued `affiliateBase` (the
    ///         running unclaimed flat-7% affiliate balance, whole BURNIE), which the affiliate
    ///         `claim` consumes.
    /// @dev The read-and-zero happen together at the storage owner, so a duplicate sub in the
    ///      affiliate `claim` array drains 0 the second time — the key guard against
    ///      double-credit. There is no separate read accessor, so the caller can never
    ///      pre-load bases into a memory array. Only `ContractAddresses.AFFILIATE` may drain,
    ///      so a non-affiliate caller can never redirect a sub's base to a wrong recipient.
    ///      Runs in the Game's storage context; `msg.sender` is the original caller.
    /// @param sub The subscriber whose affiliate base is drained.
    /// @return base The drained whole-BURNIE affiliate base (0 if already drained / never accrued).
    function drainAffiliateBase(address sub) external returns (uint256 base) {
        if (msg.sender != ContractAddresses.AFFILIATE) revert NotApproved();
        Sub storage s = _subOf[sub];
        base = s.affiliateBase;
        s.affiliateBase = 0;
    }

    /// @notice Emitted when a curse is cleared via the permissionless paid cure.
    event Decursed(address indexed curer, address indexed target);

    /// @notice Emitted when a deity adds a curse stack to a smitee.
    event Smited(uint256 indexed deityId, address indexed smitee);

    /// @notice Cashout-curse SET (delegatecall target from the Game's claimWinnings): a stale
    ///         ghost-cashout adds a saturating +2 stack. Cheapest-first bails skip the SSTORE
    ///         for infra addresses (protects the sDGNRS redemption-snapshot score), gameOver, a
    ///         non-stale claimant, deity/whale-pass holders, an active afker, and an already-
    ///         capped counter. Net: +2 only on a stale cashout by a non-exempt, below-cap player.
    function maybeCurse(address player) external {
        if (
            player == ContractAddresses.VAULT ||
            player == ContractAddresses.SDGNRS ||
            player == ContractAddresses.GNRUS
        ) return;
        if (gameOver) return;
        uint256 packed = mintPacked_[player];
        uint24 lastEthDay = uint24(
            (packed >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32
        );
        if (lastEthDay + 5 > _currentMintDay()) return; // claimed within the 5-day window
        if ((packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT) & 1 != 0) return;
        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24
        );
        uint8 bundleType = uint8(
            (packed >> BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT) & 3
        );
        if (frozenUntilLevel >= level && (bundleType == 1 || bundleType == 3)) return;
        if (_subOf[player].dailyQuantity != 0) return;
        if ((packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_8 >= CURSE_COUNT_CAP) return;
        _applyCurseStack(player);
    }

    /// @notice Permissionless paid cure: clear `target`'s cashout/smite curse for 100 BURNIE.
    /// @dev No _resolvePlayer — clearing another player's curse is purely beneficial. Reverts
    ///      when the target already has no curse so the caller never wastes the burn.
    function decurse(address target) external {
        uint256 curse = (mintPacked_[target] >> BitPackingLib.CURSE_COUNT_SHIFT) &
            BitPackingLib.MASK_8;
        if (curse == 0) revert E();
        coin.burnCoin(msg.sender, PRICE_COIN_UNIT / 10);
        _clearCurse(target);
        emit Decursed(msg.sender, target);
    }

    /// @notice A deity (soulbound pass owner) adds a saturating +2 curse stack to `smitee` for
    ///         200 BURNIE. Validated before the burn: active afkers are immune (the sole
    ///         immunity), the smite path caps at a 10-point (5-stack) ceiling below the 20-point
    ///         counter cap, and the protocol addresses are skipped (the redemption-snapshot
    ///         reason). Self-smite is allowed — harmless, since the counter only lowers the score.
    function smite(uint256 deityId, address smitee) external {
        if (
            IDegenerusDeityPassOwner(ContractAddresses.DEITY_PASS).ownerOf(deityId) !=
            msg.sender
        ) revert E();
        if (_subOf[smitee].dailyQuantity != 0) revert E(); // active-afker immunity
        uint256 curse = (mintPacked_[smitee] >> BitPackingLib.CURSE_COUNT_SHIFT) &
            BitPackingLib.MASK_8;
        if (curse >= 10) revert E(); // 5-stack smite ceiling (1 stack = 2 points)
        if (
            smitee == ContractAddresses.VAULT ||
            smitee == ContractAddresses.SDGNRS ||
            smitee == ContractAddresses.GNRUS
        ) revert E(); // protocol-addr skip
        coin.burnCoin(msg.sender, PRICE_COIN_UNIT / 5);
        _applyCurseStack(smitee);
        emit Smited(deityId, smitee);
    }
}

/// @dev Minimal deity-pass owner view for the smite gate (soulbound, tokenId = symbolId 0-31).
interface IDegenerusDeityPassOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}
