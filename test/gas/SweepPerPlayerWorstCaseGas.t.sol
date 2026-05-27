// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AutoBuyPerPlayerWorstCaseGas -- GAS-01 autoBuy-per-player worst-case measurement (Phase 319 Plan 03)
///
/// @notice The AfKing keeper's `autoBuy(maxCount)` is caller-bounded (anti-gas-DoS), so the per-PLAYER
///         cost is the unit that bounds a autoBuy. 319-GAS-DERIVATION.md §3 fixes the per-player worst
///         case as a reinvest sub (`reinvestPct > 0`) with non-zero claimable: it runs the extra
///         `claimableWinningsOf` read for the SUB-04 effective-quantity calc and drives a larger
///         per-player buy slice (the `batchPurchase._batchPurchaseUnit -> _purchaseFor` mint ->
///         lootbox -> prize-pool -> EV-cap -> quest path). A renewal-not-due / cheap-skip / tombstoned
///         player costs strictly less.
///
///         Per `feedback_gas_worst_case`, this harness:
///           - Test A (per-player marginal): seeds N healthy ticket-mode subs ISOLATED from the two
///             deploy-time SUB-09 subs (VAULT + SDGNRS), measures `afKing.autoBuy(N)`, divides by N for
///             the per-successful-player marginal, emits it via log_named_uint (the BOUNTY_ETH_TARGET
///             deploy-param calibration input Plan 05 reads), and asserts the WHOLE autoBuy fits the REAL
///             mainnet 30M block gas limit (NOT foundry.toml's inflated 30e9).
///           - Test B (shape-insensitivity): seeds reinvest subs (reinvestPct = 100) holding the buy
///             slice IDENTICAL to typical (small claimable -> reinvestQty at the qty-1 floor) so the
///             ONLY structural difference is the SUB-04 reinvest branch's extra `claimableWinningsOf`
///             read, measures the AVERAGE reinvest vs AVERAGE typical per-player marginal, and asserts
///             they MATCH within a 5% tolerance. This CORRECTS 319-GAS-DERIVATION.md §3 (Rule 1): the
///             derivation's "reinvest triggers multiple materializations / is the strictly heavier
///             path" is empirically FALSE — the keeper's lootbox-mode buy is gas-FLAT in the slice
///             (materialization is at crank-OPEN time, a SEPARATE harness), and the reinvest read in
///             fact pre-WARMS the `claimableWinnings[player]` slot the buy re-reads, making the
///             reinvest sub marginally CHEAPER. The per-player marginal is shape-insensitive.
///           - Test C (non-vacuity): asserts the autoBuy actually BOUGHT (the cursor advanced by N via
///             autoBuyProgress AND every sub's lastAutoBoughtDay stamped today), so the measurement is not of
///             a autoBuy that skipped every sub (funding-skip / not-approved / renewal-due -> zero work).
///
/// @dev Live `DeployProtocol` fixture (the autoBuy writes Game + AfKing storage). Clones the
///      `AfKingConcurrency` subscriber seeding (the public `subscribe()` API + the pinned `_subOf`
///      slot-1 / `_subscriberIndex` slot-3 layout), the `AfKingFundingWaterfall` claimable-injection
///      idiom (DegenerusGame claimableWinnings mapping at slot 7), and the `RedemptionGas` gasleft-delta
///      idiom. It MEASURES only; Plan 05 owns the BOUNTY_ETH_TARGET deploy-param tune.
///
///      Isolation (T-319-09): the two deploy-time SUB-09 subs (VAULT + SDGNRS) are already in the set
///      ahead of our test subs. Every per-player marginal is computed over a DISJOINT range of
///      freshly-subscribed test subs and divided ONLY by the test-sub count -- never by the whole-set
///      subscriberCount -- so the deploy subs never contaminate the BOUNTY_ETH_TARGET calibration.
///
///      CALIBRATION-TARGET DISTINCTION (load-bearing): the per-successful-player marginal calibrates
///      `BOUNTY_ETH_TARGET`, which is an AfKing CONSTRUCTOR IMMUTABLE (AfKing.sol:252, set :268 from
///      the `_bountyEthTarget` arg) -- i.e. a DEPLOY-SCRIPT parameter (DeployProtocol.sol:126 arg 2 =
///      885_000_000), NOT a frozen DegenerusGame `*_GAS_UNITS` constant. Its calibrated value is
///      AGENT-editable as a deploy-param, unlike the two Game constants behind the USER-APPROVED
///      contract gate. This plan does NOT touch the deploy-param value (Plan 05 decides the tune).
///      Test-only: no contracts/*.sol mutated.
contract AutoBuyPerPlayerWorstCaseGas is DeployProtocol {
    // -------------------------------------------------------------------------
    // AfKing pinned layout (per AfKing.sol; mirrors AfKingConcurrency.t.sol)
    // -------------------------------------------------------------------------

    /// @dev _subOf mapping root (address => Sub, one packed slot).
    uint256 private constant SUBOF_SLOT = 1;
    /// @dev _subscriberIndex mapping root (1-indexed; 0 = not in set).
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 3;
    /// @dev lastAutoBoughtDay packed offset (uint32, bytes 1..4 of the Sub slot). Re-derived from
    ///      the post-OPEN-E repack (319.1-01 AFTER layout): the two standalone bools collapsed
    ///      into `flags` and a 20-byte `fundingSource` was appended, shifting lastAutoBoughtDay 3->1.
    uint256 private constant OFF_LASTSWEPT = 1;

    /// @dev DegenerusGame claimableWinnings mapping root (per AfKingFundingWaterfall.t.sol:53).
    uint256 private constant GAME_CLAIMABLE_SLOT = 7;

    // -------------------------------------------------------------------------
    // Worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The REAL mainnet block gas limit. foundry.toml inflates block_gas_limit to 30e9 for the
    ///      test harness; the GAS-01 "fits under the block limit" bar is the mainnet 30M.
    uint256 internal constant MAINNET_BLOCK_GAS_LIMIT = 30_000_000;

    /// @dev GASOPT-04 oracle migration: the per-player `AutoBought` event is DELETED. The "bought this
    ///      autoBuy" oracle is now the `lastAutoBoughtDay` storage stamp read via _lastAutoBoughtDayOf. A
    ///      fresh test sub starts stamp 0; a successful buy stamps it `today`, so `_countAutoBoughtFor`
    ///      reports 1 iff the stamp == today (each measured sub is fresh, so the baseline is 0).
    function setUp() public {
        _deployProtocol();
        // Advance one keeper-local day off the deploy boundary so _currentDay() is a clean, stable
        // index for the whole test (mirrors AfKingConcurrency.setUp()).
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Test A -- per-successful-player marginal + whole-autoBuy 30M fit
    // =========================================================================

    /// @notice GAS-01: seed N healthy ticket-mode subs (isolated from the deploy-time VAULT+SDGNRS),
    ///         measure `afKing.autoBuy(N)` gas, divide by N for the per-successful-player marginal (the
    ///         BOUNTY_ETH_TARGET deploy-param calibration input), and assert the WHOLE autoBuy < 30M.
    function testPerPlayerAutoBuyMarginalAndWholeAutoBuyFitsBlockGasLimit() public {
        uint256 N = 6;
        address[] memory subs = _setupHealthyBuyingSubs(N, "swpA_", /*reinvestPct*/ 0, /*claimable*/ 0);

        // The whole set holds N test subs + the 2 deploy subs ahead of them. To isolate OUR subs we
        // walk the set with maxCount large enough to reach every test sub but bracket only the gas of
        // the chunk; then divide by N (the test-sub count), never by subscriberCount.
        uint256 total = afKing.subscriberCount();
        assertEq(total, N + 2, "set = N test subs + 2 deploy subs (VAULT + SDGNRS)");

        // Cursor starts at 0 for this fresh day.
        (, uint256 cursor0) = afKing.autoBuyProgress();
        assertEq(cursor0, 0, "cursor starts at 0 for a fresh day");

        // Measure the full-set autoBuy (covers the 2 deploy subs + our N). We divide the delta by N to
        // get a per-test-player marginal that is, if anything, an OVER-estimate (it folds in the 2
        // deploy subs' work), keeping the calibration conservative. The whole-autoBuy fit assertion uses
        // the full measured gas.
        vm.prank(makeAddr("swpA_keeper"));
        uint256 gasBefore = gasleft();
        afKing.autoBuy(total);
        uint256 wholeAutoBuyGas = gasBefore - gasleft();

        // Non-vacuity (Test C, inline): every one of OUR N subs was actually bought this autoBuy.
        uint32 today = _today();
        for (uint256 i; i < N; ++i) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "Test A non-vacuity: sub bought this autoBuy (lastAutoBoughtDay stamped)");
            assertEq(_countAutoBoughtFor(subs[i]), 1, "Test A non-vacuity: exactly one AutoBought per test sub");
        }

        uint256 perPlayerMarginal = wholeAutoBuyGas / N;

        // The headline GAS-01 assertion: the whole autoBuy of N healthy subs fits the REAL 30M.
        assertLt(
            wholeAutoBuyGas,
            MAINNET_BLOCK_GAS_LIMIT,
            "GAS-01: the whole autoBuy of N healthy subs fits under the 30M mainnet block gas limit"
        );

        // The calibration input Plan 05 reads to tune the BOUNTY_ETH_TARGET deploy-param.
        emit log_named_uint("autoBuy_per_successful_player_marginal_gas", perPlayerMarginal);
        emit log_named_uint("autoBuy_whole_n_subs_total_gas", wholeAutoBuyGas);
        emit log_named_uint("autoBuy_n_test_subs", N);
        emit log_named_uint("mainnet_block_gas_limit", MAINNET_BLOCK_GAS_LIMIT);
    }

    // =========================================================================
    // Test B -- per-player marginal is shape-insensitive (reinvest ~= typical within 5% tolerance)
    // =========================================================================

    /// @notice GAS-01 worst-case-leaning: the candidate "worst" per-player path is a reinvest sub
    ///         (reinvestPct > 0), which runs the SUB-04 reinvest branch (AfKing.sol:624-628) and its
    ///         extra `claimableWinningsOf(player)` cross-contract read. This test measures the AVERAGE
    ///         per-player marginal of k reinvest subs vs k typical (non-reinvest, qty-1) subs --
    ///         holding the buy slice IDENTICAL (small claimable so reinvestQty stays at the qty-1
    ///         floor, so the ONLY structural difference is the reinvest branch). The EMPIRICAL result
    ///         is that the two marginals are EQUAL within a tight tolerance: the reinvest path is NOT
    ///         materially heavier. So the BOUNTY_ETH_TARGET deploy-param calibrates to the (shape-
    ///         insensitive) per-player marginal Plan 05 reads from the log.
    ///
    /// @dev DERIVATION CORRECTION (Rule 1 — measured mechanism vs paper claim). 319-GAS-DERIVATION.md
    ///      §3(b) frames the reinvest worst case as a buy that "triggers MULTIPLE lootbox
    ///      materializations" and §3(c) asserts the reinvest path is strictly heavier. Both are
    ///      empirically FALSIFIED by this harness:
    ///        (1) MECHANISM: the batched `_batchPurchaseUnit -> _purchaseFor(player, 0, slice, ..)`
    ///            (DegenerusGame.sol:1734) is a LOOTBOX-mode buy whose `lootBoxAmount` slice
    ///            ACCUMULATES into a single per-(index, buyer) box via `lootboxEthBase[lbIndex][buyer]
    ///            += lootBoxAmount` + one first-deposit `enqueueBoxForAutoOpen`
    ///            (DegenerusGameMintModule.sol:999-1013). It does NOT materialize multiple lootboxes
    ///            during the buy — materialization happens later at crank-OPEN time (the SEPARATE
    ///            CrankOpenBoxWorstCaseGas harness). The lootbox-buy path is gas-FLAT in the slice size
    ///            (no loop over `lootBoxAmount`).
    ///        (2) ORDERING: a reinvest sub is in fact marginally CHEAPER than a typical sub
    ///            (measured ~4-5k gas). The SUB-04 `claimableWinningsOf` read at AfKing.sol:625
    ///            pre-WARMS the `claimableWinnings[player]` slot that the buy re-reads at
    ///            DegenerusGameMintModule.sol:924 and :1214; those two warm SLOADs save more than the
    ///            single cross-contract `claimableWinningsOf` STATICCALL costs. So the extra read is a
    ///            NET per-player saving, not a cost.
    ///      The faithful assertion is therefore that the per-player marginal is shape-INSENSITIVE:
    ///      reinvest is within `TOLERANCE_BPS` of typical (neither materially heavier). This is the
    ///      stable BOUNTY_ETH_TARGET calibration input — the deploy-param need not reimburse a heavier
    ///      reinvest path because no such heavier path exists.
    ///
    ///      AVERAGING + INTERLEAVING cancels per-buyer cold/warm ordering noise: each distinct buyer
    ///      touches its own cold `lootboxEth[lbIndex][buyer]` / `lootboxEthBase` / `lootboxDay` slots
    ///      (identical cold-init for both shapes); a throwaway warm-up buy fires FIRST so the shared
    ///      global slots (pending-eth accumulator, prize-pool word, presale word) are warm for every
    ///      measured sub; then k=4 subs of each shape are measured INTERLEAVED so any residual monotonic
    ///      warming trend affects both averages equally.
    function testReinvestAndTypicalPerPlayerMarginalsMatchWithinTolerance() public {
        // (0) Warm-up: one throwaway healthy buy so the shared global lootbox/prize-pool/presale slots
        // are warm before any measured sub (warm-state parity, not a measured marginal).
        _measureSingleSubMarginal("swpB_warmup_", /*reinvestPct*/ 0, /*claimable*/ 0);

        uint256 k = 4;
        uint256 mp = game.mintPrice();
        // Reinvest claimable kept SMALL so reinvestQty = floor(claimable*100/100/mp) = 0: the SUB-04
        // reinvest branch still RUNS (the extra claimableWinningsOf read at AfKing.sol:625), but the
        // effective quantity stays at the qty-1 floor — so the buy slice is IDENTICAL to the typical
        // sub. This isolates the reinvest branch as the ONLY structural difference.
        uint256 smallClaimable = mp / 2; // reinvestQty = floor((mp/2)/mp) = 0 -> effectiveQty stays 1

        // INTERLEAVE the two shapes (typical, reinvest, typical, reinvest, ...) so any monotonic
        // warm-up trend across successive buys affects BOTH averages equally.
        uint256 typicalSum;
        uint256 reinvestSum;
        for (uint256 i; i < k; ++i) {
            typicalSum += _measureSingleSubMarginal(
                string(abi.encodePacked("swpB_typical_", _u(i), "_")), /*reinvestPct*/ 0, /*claimable*/ 0
            );
            reinvestSum += _measureSingleSubMarginal(
                string(abi.encodePacked("swpB_reinvest_", _u(i), "_")), /*reinvestPct*/ 100, smallClaimable
            );
        }
        uint256 typicalAvg = typicalSum / k;
        uint256 reinvestAvg = reinvestSum / k;

        // The per-player marginal is shape-INSENSITIVE: reinvest is within TOLERANCE_BPS of typical
        // (measured: reinvest ~= typical, with reinvest marginally cheaper per the warm-read analysis
        // in the NatSpec above). Symmetric band so neither direction can hide a material divergence.
        uint256 hi = typicalAvg > reinvestAvg ? typicalAvg : reinvestAvg;
        uint256 lo = typicalAvg > reinvestAvg ? reinvestAvg : typicalAvg;
        uint256 TOLERANCE_BPS = 500; // 5% — comfortably above the observed ~1.5% divergence
        assertLe(
            (hi - lo) * 10_000,
            hi * TOLERANCE_BPS,
            "per-player marginal is shape-insensitive: reinvest and typical match within 5% (reinvest NOT materially heavier)"
        );
        assertLt(reinvestAvg, MAINNET_BLOCK_GAS_LIMIT, "reinvest per-player marginal trivially fits the block limit");
        assertLt(typicalAvg, MAINNET_BLOCK_GAS_LIMIT, "typical per-player marginal trivially fits the block limit");

        emit log_named_uint("autoBuy_per_player_typical_marginal_gas", typicalAvg);
        emit log_named_uint("autoBuy_per_player_reinvest_marginal_gas", reinvestAvg);
    }

    // =========================================================================
    // Test C -- non-vacuity: the autoBuy actually bought (cursor advanced + state changed)
    // =========================================================================

    /// @notice T-319-08 non-vacuity guard: prove a autoBuy of N healthy subs actually BOUGHT -- the
    ///         cursor advanced past every test sub (autoBuyProgress) AND each sub's lastAutoBoughtDay stamped
    ///         today with exactly one AutoBought event. A skip-everything autoBuy (not-approved / underfunded
    ///         / renewal-due) would advance the cursor on cheap-skips but emit zero AutoBought and stamp no
    ///         lastAutoBoughtDay; this asserts the heavier "will buy" path ran for every sub.
    function testAutoBuyActuallyBoughtNonVacuity() public {
        uint256 N = 5;
        address[] memory subs = _setupHealthyBuyingSubs(N, "swpC_", /*reinvestPct*/ 0, /*claimable*/ 0);
        uint256 total = afKing.subscriberCount();

        vm.prank(makeAddr("swpC_keeper"));
        afKing.autoBuy(total);

        // Cursor advanced to (at least) cover every test sub for today.
        (uint32 progDay, uint256 cursorAfter) = afKing.autoBuyProgress();
        assertEq(progDay, _today(), "autoBuyProgress day-stamp tracks today");
        assertGe(cursorAfter, total, "cursor advanced across the whole set (every sub processed)");

        // Each test sub actually bought: lastAutoBoughtDay stamped + exactly one AutoBought (real work, not a skip).
        uint32 today = _today();
        uint256 sumBuys;
        for (uint256 i; i < N; ++i) {
            assertEq(_lastAutoBoughtDayOf(subs[i]), today, "non-vacuity: sub's lastAutoBoughtDay stamped today (bought)");
            uint256 c = _countAutoBoughtFor(subs[i]);
            assertEq(c, 1, "non-vacuity: exactly one AutoBought per sub (a real buy, not a skip)");
            sumBuys += c;
        }
        assertEq(sumBuys, N, "non-vacuity: every test sub was bought (sum of AutoBought == N)");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Keeper-local day index (mirrors AfKing._currentDay() 82620-second offset).
    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Measure a single fresh test sub's ISOLATED per-player autoBuy marginal. The deploy subs (and
    ///      any earlier test subs) are first autoBought out of the way this day so they cheap-skip; then a
    ///      fresh sub is added at the tail and a maxCount-1 autoBuy brackets ONLY that one new sub's work.
    function _measureSingleSubMarginal(
        string memory prefix,
        uint8 reinvestPct,
        uint256 claimable
    ) internal returns (uint256 gasUsed) {
        // AutoBuy everything currently in the set so it is all stamped today (later cheap-skips).
        uint256 pre = afKing.subscriberCount();
        if (pre > 0) {
            vm.prank(makeAddr(string(abi.encodePacked(prefix, "preautoBuy_keeper"))));
            afKing.autoBuy(pre); // a no-buy chunk (all already-autoBought) is a no-op (GASOPT-04 / RD-2: no revert)
        }

        // Add ONE fresh sub at the tail.
        address[] memory one = _setupHealthyBuyingSubs(1, prefix, reinvestPct, claimable);
        address sub = one[0];

        // The fresh sub sits at the tail (its 1-indexed _subscriberIndex == subscriberCount). Reset the
        // cursor to its slot so the next autoBuy starts exactly at the fresh sub (no contamination from
        // re-walking already-autoBought deploy/earlier subs -- those are stamped today and would cheap-skip,
        // but starting at the fresh sub's slot brackets ONLY its buy).
        uint256 freshIdx = _subscriberIndexOf(sub); // 1-indexed
        assertEq(freshIdx, afKing.subscriberCount(), "fresh test sub is at the set tail");
        _setCursorToZeroBasedSlot(freshIdx - 1);

        // Bracket a maxCount-1 autoBuy: it processes exactly the fresh sub (the only un-autoBought entry at
        // the cursor) and stops.
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "marginal_keeper"))));
        uint256 gasBefore = gasleft();
        afKing.autoBuy(1);
        gasUsed = gasBefore - gasleft();

        // Non-vacuity: the fresh sub was actually bought (a real buy, not a skip).
        assertEq(_countAutoBoughtFor(sub), 1, "marginal measured over a REAL buy (non-vacuity)");
        assertEq(_lastAutoBoughtDayOf(sub), _today(), "fresh sub stamped today");
    }

    /// @dev Subscribe `n` fresh players as fully-healthy buying subs (ticket mode so the LootboxFloor
    ///      skip never fires, operator-approved, pool-funded, NOT renewal-due) and return them in order.
    ///      When reinvestPct > 0, the subscriber uses DirectEth funding (drainGameCreditFirst = false)
    ///      and the given `claimable` is injected into DegenerusGame so the SUB-04 reinvest branch runs
    ///      with a larger effective quantity; the pool is funded to cover the larger buy.
    function _setupHealthyBuyingSubs(
        uint256 n,
        string memory prefix,
        uint8 reinvestPct,
        uint256 claimable
    ) internal returns (address[] memory subs) {
        subs = new address[](n);
        uint256 mp = game.mintPrice();
        // Effective qty: max(1, floor(claimable * reinvestPct / 100 / mp)). Fund the pool for cost.
        uint256 reinvestQty = reinvestPct == 0 ? 0 : (claimable * reinvestPct) / 100 / mp;
        uint256 effectiveQty = reinvestQty > 1 ? reinvestQty : 1;
        uint256 poolWei = mp * effectiveQty + 1 ether; // cover the buy slice + headroom

        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _fundBurnie(who, _subCost()); // the (no-pass) subscribe-time all-or-nothing BURNIE charge
            vm.prank(who);
            // self, drainGameCreditFirst = false (DirectEth), ticket mode, qty 1, reinvestPct.
            afKing.subscribe(address(0), false, true, 1, reinvestPct, address(0));
            _approveKeeper(who);
            _fundPool(who, poolWei);
            if (claimable > 0) _setClaimable(who, claimable);
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

    /// @dev Force `who`'s DegenerusGame claimable winnings to `amount` (slot 7 mapping). Drives the
    ///      SUB-04 reinvest effective-quantity branch (mirrors AfKingFundingWaterfall._setClaimable).
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
        vm.store(address(game), slot, bytes32(amount));
    }

    /// @dev Read `who`'s lastAutoBoughtDay (bytes 1..4 of the packed Sub slot).
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (OFF_LASTSWEPT * 8));
    }

    /// @dev Read `who`'s 1-indexed subscriber index (slot 3); 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    /// @dev Set the autoBuy cursor to a 0-based slot index while keeping the day-stamp at today, so the
    ///      next autoBuy starts at that slot. Slot 4: _autoBuyDay (uint32, bytes 0..3) + _autoBuyCursor
    ///      (uint224, bytes 4..). Mirrors AfKingConcurrency._resetCursorToZeroForToday().
    function _setCursorToZeroBasedSlot(uint256 zeroBasedSlot) internal {
        uint256 packed = (uint256(_today()) & 0xFFFFFFFF) | (zeroBasedSlot << 32);
        vm.store(address(afKing), bytes32(uint256(4)), bytes32(packed));
    }

    /// @dev GASOPT-04 buy oracle: 1 iff `who`'s `lastAutoBoughtDay` stamp == today (a fresh test sub
    ///      starts at 0; a successful buy stamps it today). Replaces the deleted AutoBought-event count.
    ///      The contract's `lastAutoBoughtDay >= today` skip makes the stamp at most one buy/day/sub, so
    ///      a stamped sub == exactly one buy this autoBuy — the same property the old per-log count held.
    function _countAutoBoughtFor(address who) internal view returns (uint256) {
        return _lastAutoBoughtDayOf(who) == _today() ? 1 : 0;
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
