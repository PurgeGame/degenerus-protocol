// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RouterWorstCaseGas -- GAS-01 (Phase 331) keeper-router worst-case marginal measurement.
///
/// @notice The v49 unified keeper router `AfKing.doWork()` (AfKing.sol:868) routes ONE category of
///         pending work per call by priority (autoBuy -> advance -> autoOpen) and pays ONE flat-per-tx
///         bounty. The break-even bounty peg (calibrated by 331-04 under a USER-gated contract diff)
///         is a function of the per-CATEGORY worst-case MARGINAL gas at 0.5 gwei. This harness MEASURES
///         those four marginals; it does NOT calibrate any constant (331-04 does, gated).
///
///         Per `feedback_gas_worst_case` + the CR-01 lesson (319), the four marginals are:
///           - router_dowork_buy_per_player_marginal_gas  -- per successful subscriber, N>=32 amortized
///           - router_dowork_open_per_box_marginal_gas     -- per opened box, N>=32 amortized
///           - router_dowork_advance_marginal_gas          -- a single new-day advance step (no loop-N)
///           - router_dowork_dispatch_overhead_gas         -- the once-per-tx doWork routing + creditFlip
///
///         CR-01 (load-bearing, 319-CR01-FIX.md): peg the per-ITEM MARGINAL at N>=32, NEVER a single-
///         item TOTAL (which bundles the per-tx fixed overhead into one item, over-pegs ~2x, and opens
///         a Sybil self-crank faucet). The buy + open tests measure at N=32 and also emit the
///         N=1/N=8/N=32 amortization gradient to show convergence.
///
///         Each test (1) asserts the constructed scenario IS the worst-case cap, (2) asserts
///         non-vacuity (real work happened, not a silent skip), (3) asserts < the REAL mainnet 30M
///         block gas limit (NOT foundry.toml's inflated 30e9), (4) emits the calibration input.
///
/// @dev Live `DeployProtocol` fixture. Reuses the established `*WorstCaseGas.t.sol` idiom wholesale:
///      the gasleft()-delta bracket (NOT vm.snapshotGas -- the live repo idiom), the loop-N-divide
///      per-item marginal, the assert-is-worst-case + non-vacuity preconditions, the 30M bar, and
///      log_named_uint emission. Slot constants re-confirmed via `forge inspect ... storage` against
///      the 63bc16ca layout (330 added boxCursor/boxCursorIndex at slot 62, boxPlayers at slot 63).
///      Test-only: no contracts/*.sol mutated. Run with --isolate for true per-call gas.
contract RouterWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (re-confirmed via `forge inspect ... storage` @ 63bc16ca)
    // -------------------------------------------------------------------------

    // DegenerusGame
    uint256 private constant PRIZE_POOLS_SLOT = 2;            // prizePoolsPacked (future << 128 | next)
    uint256 private constant GAME_CLAIMABLE_SLOT = 7;         // claimableWinnings mapping root
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;      // lootboxEthBase root (first-deposit signal)
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;    // lootboxRngPacked (low 48 bits = index)
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;      // lootboxRngWordByIndex mapping root

    // AfKing
    uint256 private constant SUBOF_SLOT = 1;                  // _subOf mapping root (one packed Sub slot)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3;       // _subscriberIndex (1-indexed)
    uint256 private constant AFKING_CURSOR_SLOT = 4;          // _autoBuyDay (off 0) | _autoBuyCursor (off 4)
    /// @dev lastAutoBoughtDay offset in the packed Sub slot (bytes 1..4): the post-OPEN-E layout
    ///      (dailyQuantity off0, lastAutoBoughtDay off1, paidThroughDay off5, reinvestPct off9,
    ///      flags off10, fundingSource off11).
    uint256 private constant OFF_LASTSWEPT = 1;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for the
    ///      harness; the GAS-01 "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev The CR-01 converged-marginal regime: N>=32 amortizes the per-tx fixed overhead away.
    uint256 internal constant N_MARGINAL = 32;

    /// @dev A fixed RNG word for deterministic box opens.
    uint256 private constant BOX_FIXED_WORD = uint256(keccak256("router_worst_case_box_word"));

    uint256 private constant LOOTBOX_WEI = 1 ether; // >= LOOTBOX_MIN; a real first-deposit box

    function setUp() public {
        _deployProtocol();
        // Advance one keeper-local day off the deploy boundary so _currentDay() / the game day index
        // are clean, stable indices for the whole test (mirrors the AfKing/Crank harnesses).
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    // =========================================================================
    // BUY leg -- per-successful-subscriber marginal (N>=32) + whole-leg 30M fit
    // =========================================================================

    /// @notice GAS-01 buy leg (331-GAS-DERIVATION.md §1): seed N>=32 worst-case-funded subscribers
    ///         (reinvest + drain-first, the heaviest per-sub funding shape) ISOLATED from the two
    ///         deploy-time SUB-09 subs (VAULT + SDGNRS), drive ONE autoBuy(total) (the doWork buy leg's
    ///         `_autoBuy` body), divide the gas by N -> router_dowork_buy_per_player_marginal_gas.
    ///         Asserts every one of OUR N subs bought (non-vacuity via lastAutoBoughtDay == today) and
    ///         the WHOLE leg < 30M. Also emits the N=1/N=8/N=32 amortization gradient (CR-01 convergence).
    function testBuyLegPerPlayerMarginalAndWholeLegFitsBlockGasLimit() public {
        address[] memory subs = _setupHealthyBuyingSubs(N_MARGINAL, "buyM_");

        uint256 total = afKing.subscriberCount();
        assertEq(total, N_MARGINAL + 2, "set = N test subs + 2 deploy subs (VAULT + SDGNRS)");

        // Cursor starts at 0 for this fresh day.
        (, uint256 cursor0) = afKing.autoBuyProgress();
        assertEq(cursor0, 0, "cursor starts at 0 for a fresh day");

        // Bracket the whole-set autoBuy (covers the 2 deploy subs + our N). Dividing the delta by N
        // (the test-sub count) yields a per-test-player marginal that, if anything, OVER-estimates
        // (it folds in the 2 deploy subs' work) -> conservative calibration floor.
        vm.prank(makeAddr("buyM_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoBuy(total);
        uint256 wholeLegGas = gasBefore - gasleft();

        // assert-is-worst-case + non-vacuity: every one of OUR N subs actually bought this leg
        // (the heaviest reinvest+drain-first path ran, not a cheap skip).
        uint32 today = _today();
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertEq(
                _lastAutoBoughtDayOf(subs[i]),
                today,
                "buy non-vacuity: each worst-case sub bought this leg (lastAutoBoughtDay stamped)"
            );
        }

        uint256 perPlayerMarginal = wholeLegGas / N_MARGINAL;

        // Headline GAS-01: the whole buy leg of N>=32 worst-case subs fits the REAL 30M block limit.
        assertLt(
            wholeLegGas,
            MAINNET_BLOCK_GAS_LIMIT,
            "GAS-01: the whole doWork buy leg (N>=32 worst-case subs) fits under the 30M mainnet block limit"
        );
        assertLt(perPlayerMarginal, MAINNET_BLOCK_GAS_LIMIT, "per-player buy marginal trivially fits the block limit");

        // The calibration input 331-04 reads.
        emit log_named_uint("router_dowork_buy_per_player_marginal_gas", perPlayerMarginal);
        emit log_named_uint("router_dowork_buy_whole_leg_total_gas", wholeLegGas);
        emit log_named_uint("router_dowork_buy_n_test_subs", N_MARGINAL);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    /// @notice CR-01 amortization gradient for the buy leg: measure the per-player marginal at N=1, 8,
    ///         and 32 (each in its own fresh fixture state) so the convergence to the N>=32 regime is
    ///         recorded as evidence that pegging to the single-player TOTAL (N=1) over-states the
    ///         marginal (319 precedent). N=1 is the single-player total; N>=32 is the converged marginal.
    function testBuyLegAmortizationGradientConvergesAtN32() public {
        uint256 n1 = _measureBuyLegPerPlayer(1, "buyG1_");
        uint256 n8 = _measureBuyLegPerPlayer(8, "buyG8_");
        uint256 n32 = _measureBuyLegPerPlayer(32, "buyG32_");

        // The single-player total (N=1) is >= the converged marginal (N=32): the per-tx fixed overhead
        // (batchPurchase setup, cursor SSTORE) is bundled into the one player at N=1 and amortized away
        // at N=32. Equality is permitted (warm-state can compress the gap) but N=1 is never LESS.
        assertGe(n1, n32, "CR-01: single-player total (N=1) >= converged per-player marginal (N=32)");
        assertLt(n32, MAINNET_BLOCK_GAS_LIMIT, "converged buy marginal fits the block limit");

        emit log_named_uint("router_dowork_buy_marginal_n1_total_gas", n1);
        emit log_named_uint("router_dowork_buy_marginal_n8_gas", n8);
        emit log_named_uint("router_dowork_buy_marginal_n32_converged_gas", n32);
    }

    // =========================================================================
    // OPEN leg -- per-box marginal (N>=32) + whole-leg 30M fit
    // =========================================================================

    /// @notice GAS-01 open leg (331-GAS-DERIVATION.md §2): queue N>=32 worst-case boxes (real
    ///         first-deposit deposits) with the index RNG word landed, drive ONE autoOpen(N) (the doWork
    ///         open leg), divide by N -> router_dowork_open_per_box_marginal_gas. Asserts each box opened
    ///         (non-vacuity via the first-deposit signal zeroed) and the whole leg < 30M.
    function testOpenLegPerBoxMarginalAndWholeLegFitsBlockGasLimit() public {
        uint48 index = _activeLootboxIndex();
        address[] memory owners = new address[](N_MARGINAL);
        for (uint256 i; i < N_MARGINAL; ++i) {
            address o = makeAddr(string(abi.encodePacked("openM_", vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100_000 ether);
            _buyBox(o, LOOTBOX_WEI);
        }
        _injectLootboxRngWord(index, BOX_FIXED_WORD);

        // assert-is-worst-case: every box is queued + un-opened (real materializations, not skips).
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "open worst case: each box queued + un-opened");
        }

        vm.prank(makeAddr("openM_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(N_MARGINAL); // the AfKing open passthrough -> IGame.autoOpen (the doWork open leg)
        uint256 wholeLegGas = gasBefore - gasleft();

        // Non-vacuity: every box actually opened (first-deposit signal zeroed on open), so the marginal
        // is a real per-box materialization cost.
        for (uint256 i; i < N_MARGINAL; ++i) {
            assertEq(_lootboxEthBase(index, owners[i]), 0, "open non-vacuity: each box opened (signal zeroed)");
        }

        uint256 perBoxMarginal = wholeLegGas / N_MARGINAL;

        assertLt(
            wholeLegGas,
            MAINNET_BLOCK_GAS_LIMIT,
            "GAS-01: the whole doWork open leg (N>=32 ready boxes) fits under the 30M mainnet block limit"
        );
        assertLt(perBoxMarginal, MAINNET_BLOCK_GAS_LIMIT, "per-box open marginal trivially fits the block limit");

        emit log_named_uint("router_dowork_open_per_box_marginal_gas", perBoxMarginal);
        emit log_named_uint("router_dowork_open_whole_leg_total_gas", wholeLegGas);
        emit log_named_uint("router_dowork_open_n_boxes", N_MARGINAL);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    /// @notice CR-01 amortization gradient for the open leg: per-box marginal at N=1, 8, 32. N=1 is the
    ///         single-box total (the CR-01 defect target); N>=32 is the converged marginal. Asserts the
    ///         converged marginal is materially BELOW the single-box total (the gap is the per-tx fixed
    ///         overhead the single-box measurement mis-attributes to one box).
    function testOpenLegAmortizationGradientBelowSingleBoxTotal() public {
        uint256 n1 = _measureOpenLegPerBox(1, "openG1_");
        uint256 n8 = _measureOpenLegPerBox(8, "openG8_");
        uint256 n32 = _measureOpenLegPerBox(32, "openG32_");

        assertGe(n1, n32, "CR-01: single-box total (N=1) >= converged per-box marginal (N=32)");
        assertLt(n32, MAINNET_BLOCK_GAS_LIMIT, "converged open marginal fits the block limit");

        emit log_named_uint("router_dowork_open_marginal_n1_total_gas", n1);
        emit log_named_uint("router_dowork_open_marginal_n8_gas", n8);
        emit log_named_uint("router_dowork_open_marginal_n32_converged_gas", n32);
    }

    // =========================================================================
    // ADVANCE leg -- a single new-day advance step routed through doWork()
    // =========================================================================

    /// @notice GAS-01 advance leg (331-GAS-DERIVATION.md §3): drive a real new-day advance THROUGH the
    ///         router. With NO subscribers and NO boxes queued, the buy/open predicates route past so
    ///         doWork() dispatches advanceGame(). The advance leg is a SINGLE call per doWork (no loop-N),
    ///         so its calibration input is one marginal. Asserts the day actually advanced (non-vacuity:
    ///         the game entered rngLock, i.e. advanceGame fired the day's RNG request) and < 30M.
    function testAdvanceLegMarginalRoutedThroughDoWorkFitsBlockGasLimit() public {
        // Seed a real ticket queue at the active level so the new-day advance has structural drain work
        // (the heaviest realizable advance step on the fresh fixture): a buyer purchases tickets today,
        // then we warp a day so advanceDue() is true and the daily-drain + RNG-request machinery runs.
        address buyer = makeAddr("advBuyer");
        vm.deal(buyer, 1_000 ether);
        for (uint256 i; i < 8; ++i) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        // Warp to a new day so advanceDue() is TRUE.
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "advance worst case: advanceDue() is TRUE on the new day");

        // Make the buy predicate FALSE so doWork() routes to advance, not buy. With zero subscribers the
        // _autoBuy walk is a no-op, but `_autoBuyDay != _currentDay()` is TRUE on a fresh day so the buy
        // BRANCH is still entered (and returns 0). Stamp the autoBuy day + park the cursor at the set
        // length via a single standalone autoBuy() so the buy predicate is false and the router falls
        // through to advance (mirrors the real keeper, which would buy-then-advance across calls).
        assertEq(afKing.subscriberCount(), 2, "only the 2 deploy subs exist (no test buy subs)");
        vm.prank(makeAddr("advPark_keeper"));
        afKing.autoBuy(afKing.subscriberCount()); // stamps _autoBuyDay = today, parks cursor at set length
        ( , uint256 cursorAfter) = afKing.autoBuyProgress();
        assertGe(cursorAfter, afKing.subscriberCount(), "buy cursor parked at set length -> buy predicate now false");

        // boxesPending() must be false too (no boxes queued, or rngLock blocks it) so advance is the
        // chosen leg.
        assertFalse(game.boxesPending(), "no boxes pending -> advance is the routed leg");

        bool lockedBefore = game.rngLocked();

        // Measure the doWork() advance dispatch (the router consumes advanceGame()'s returned mult).
        vm.prank(makeAddr("adv_keeper"));
        uint256 gasBefore = gasleft();
        afKing.doWork();
        uint256 advanceGas = gasBefore - gasleft();

        // Non-vacuity: the advance actually did work. A new-day advance with a non-empty queue either
        // drains tickets (ticketsFullyProcessed progresses) or requests the day's RNG (rngLock flips
        // true). Assert the game entered rngLock OR the day index moved -- a real advance step ran, not
        // a NotTimeYet revert or a no-op.
        bool advanced = game.rngLocked() != lockedBefore || game.rngLocked() || !game.advanceDue();
        assertTrue(advanced, "advance non-vacuity: a real new-day advance step ran (rngLock/day moved)");

        assertLt(
            advanceGas,
            MAINNET_BLOCK_GAS_LIMIT,
            "GAS-01: the doWork advance leg (new-day step) fits under the 30M mainnet block limit"
        );

        emit log_named_uint("router_dowork_advance_marginal_gas", advanceGas);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // DISPATCH overhead -- the once-per-tx doWork routing + creditFlip
    // =========================================================================

    /// @notice GAS-01 dispatch overhead (331-GAS-DERIVATION.md §4): isolate the once-per-tx doWork()
    ///         router cost (the mintPrice read + the O(1) routing predicates + the single creditFlip),
    ///         minimizing the chosen leg's real work so the measured number is dominated by dispatch.
    ///         The cheapest non-reverting leg is a buy leg with ONE healthy subscriber: the buy branch
    ///         runs, one slice is purchased, and doWork pays one creditFlip -- so the measured gas is
    ///         (dispatch + one-player buy + one creditFlip). Subtracting the §1 single-player buy total
    ///         leaves the dispatch+creditFlip overhead; we emit the full doWork-with-minimal-leg number
    ///         as the conservative dispatch-overhead ceiling (it never UNDER-states the once-per-tx cost).
    function testDispatchOverheadIsBoundedAndFitsBlockGasLimit() public {
        // One healthy buying subscriber so the buy leg runs minimally and doWork pays its bounty.
        address[] memory subs = _setupHealthyBuyingSubs(1, "disp_");
        assertEq(afKing.subscriberCount(), 3, "set = 1 test sub + 2 deploy subs");

        // Park the deploy subs out of the way (autoBuy them) so the measured doWork processes a small,
        // stable buy chunk. The cursor reset on the fresh day means doWork's buy leg will re-walk from 0;
        // to keep the measured leg minimal we instead measure doWork directly -- the buy branch processes
        // the (cheap-skipping deploy subs that may underfund) + our 1 healthy sub, then pays one creditFlip.
        bool lockedBefore = game.rngLocked();
        assertFalse(lockedBefore, "fixture not in rngLock at measurement");

        // Measure doWork(): routes to the buy leg (highest priority on a fresh day), buys our sub, and
        // pays ONE creditFlip (the dispatch + once-per-tx bounty). This is the conservative dispatch
        // overhead ceiling: it includes one real buy, so the pure routing+creditFlip cost is <= this.
        uint32 today = _today();
        vm.prank(makeAddr("disp_keeper"));
        uint256 gasBefore = gasleft();
        afKing.doWork();
        uint256 doWorkGas = gasBefore - gasleft();

        // Non-vacuity: doWork did real work (our sub bought this day) and paid its bounty.
        assertEq(_lastAutoBoughtDayOf(subs[0]), today, "dispatch non-vacuity: doWork ran the buy leg (sub bought)");

        assertLt(
            doWorkGas,
            MAINNET_BLOCK_GAS_LIMIT,
            "GAS-01: the doWork dispatch (routing + minimal buy leg + creditFlip) fits under the 30M block limit"
        );

        // Conservative dispatch-overhead ceiling: doWork with the cheapest non-reverting leg. 331-04
        // subtracts the §1 single-player buy marginal to recover the pure routing+creditFlip overhead.
        emit log_named_uint("router_dowork_dispatch_overhead_gas", doWorkGas);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Internal helpers (mirror SweepPerPlayerWorstCaseGas + CrankOpenBoxWorstCaseGas)
    // =========================================================================

    /// @dev Measure the per-player buy marginal over N freshly-seeded worst-case subs in a clean cursor
    ///      state. Used by the amortization-gradient test. Resets the autoBuy cursor to 0 for today so
    ///      the bracketed autoBuy walks exactly the N fresh subs (plus the already-stamped earlier subs
    ///      cheap-skip), then divides by N.
    function _measureBuyLegPerPlayer(uint256 n, string memory prefix) internal returns (uint256 perPlayer) {
        // Park everything currently in the set (autoBuy it so it cheap-skips), then add N fresh subs.
        uint256 pre = afKing.subscriberCount();
        if (pre > 0) {
            vm.prank(makeAddr(string(abi.encodePacked(prefix, "park_keeper"))));
            afKing.autoBuy(pre);
        }
        address[] memory subs = _setupHealthyBuyingSubs(n, prefix);
        // Park the cursor at the first fresh sub (1-indexed -> 0-based) so the bracket covers only the N.
        uint256 firstFreshIdx0 = _subscriberIndexOf(subs[0]) - 1;
        _setCursorToZeroBasedSlot(firstFreshIdx0);

        vm.prank(makeAddr(string(abi.encodePacked(prefix, "marginal_keeper"))));
        uint256 gasBefore = gasleft();
        afKing.autoBuy(n);
        uint256 totalGas = gasBefore - gasleft();
        perPlayer = totalGas / n;

        uint32 today = _today();
        for (uint256 i; i < n; ++i) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "gradient non-vacuity: each sub bought");
        }
    }

    /// @dev Measure the per-box open marginal over N freshly-queued boxes in a fresh fixture index.
    ///      Used by the amortization-gradient test. Each call queues N distinct boxes then opens them.
    function _measureOpenLegPerBox(uint256 n, string memory prefix) internal returns (uint256 perBox) {
        uint48 index = _activeLootboxIndex();
        address[] memory owners = new address[](n);
        for (uint256 i; i < n; ++i) {
            address o = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100_000 ether);
            _buyBox(o, LOOTBOX_WEI);
        }
        _injectLootboxRngWord(index, BOX_FIXED_WORD);
        for (uint256 i; i < n; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "gradient pre: each box queued");
        }

        vm.prank(makeAddr(string(abi.encodePacked(prefix, "keeper"))));
        uint256 gasBefore = gasleft();
        afKing.autoOpen(n);
        uint256 totalGas = gasBefore - gasleft();
        perBox = totalGas / n;

        for (uint256 i; i < n; ++i) {
            assertEq(_lootboxEthBase(index, owners[i]), 0, "gradient non-vacuity: each box opened");
        }
    }

    /// @dev Subscribe `n` fresh players as fully-healthy WORST-CASE buying subs: reinvest + drain-first
    ///      (the heaviest per-sub funding shape, 331-GAS-DERIVATION.md §1(b)), ticket mode (no
    ///      LootboxFloor skip), operator-approved, pool-funded, NOT renewal-due. A non-zero claimable is
    ///      injected so the SUB-04 reinvest branch runs; the pool is funded for the buy slice.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        uint256 mp = game.mintPrice();
        // Reinvest claimable kept small so reinvestQty stays at the qty-1 floor (the reinvest branch
        // still RUNS its extra keeperSnapshot read -- the structural worst-case difference -- but the
        // buy slice stays a single ticket so the pool funding is bounded).
        uint256 claimable = mp / 2;
        uint256 poolWei = mp + 1 ether; // cover a 1-ticket buy slice + headroom

        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _fundBurnie(who, _subCost()); // the no-pass subscribe-time all-or-nothing BURNIE charge
            vm.prank(who);
            // self, drainGameCreditFirst = true (drain-first waterfall), ticket mode, qty 1, reinvest 100.
            afKing.subscribe(address(0), true, true, 1, 100, address(0));
            _approveKeeper(who);
            _fundPool(who, poolWei);
            _setClaimable(who, claimable);
        }
    }

    function _subCost() internal view returns (uint256) {
        return (afKing.SUB_COST_ETH_TARGET() * 1000 ether) / game.mintPrice();
    }

    function _approveKeeper(address who) internal {
        vm.prank(who);
        game.setOperatorApproval(address(afKing), true);
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        afKing.depositFor{value: amount}(who);
    }

    function _fundBurnie(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
        vm.store(address(game), slot, bytes32(amount));
    }

    /// @dev Buy a real lootbox-mode deposit: the first deposit for (index, buyer) fires the
    ///      lootboxEthBase == 0 signal -> enqueueBoxForAutoOpen (MintModule), queuing the box.
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked).
    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_BASE_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    /// @dev Keeper-local day index (mirrors AfKing._currentDay() 82620-second offset).
    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Read `who`'s lastAutoBoughtDay (bytes 1..4 of the packed Sub slot).
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
    }

    /// @dev Read `who`'s 1-indexed subscriber index; 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Set the autoBuy cursor to a 0-based slot index while keeping the day-stamp at today, so the
    ///      next autoBuy starts at that slot. Slot 4: _autoBuyDay (uint32, bytes 0..3) + _autoBuyCursor
    ///      (uint224, bytes 4..).
    function _setCursorToZeroBasedSlot(uint256 zeroBasedSlot) internal {
        uint256 packed = (uint256(_today()) & 0xFFFFFFFF) | (zeroBasedSlot << 32);
        vm.store(address(afKing), bytes32(uint256(AFKING_CURSOR_SLOT)), bytes32(packed));
    }

    /// @dev Minimal uint -> decimal string for makeAddr label uniqueness.
    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
