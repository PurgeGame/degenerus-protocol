// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title KeeperFaucetResistance -- Proves the v55.0 game-resident permissionless router
///        (`game.mintBurnie()` advance/open legs + degeneretteResolve) is faucet-bounded by three
///        caller-independent locks:
///        (1) the purchase-gate (an item must already be a real, purchased, RNG-ready bet/box/stamp),
///        (2) the flat-per-tx LIVE-unit reward judged against the REAL prevailing gas of the identical
///            work at the >=1 gwei market floor (never measured gas, never the peg ref), and
///        (3) the coinflip-credit illiquidity (creditFlip = pending stake, not liquid BURNIE).
///
/// @notice A self-keeper / Sybil round-trip is net-zero-or-negative across the v55 router legs: the
///         `mintBurnie()` open-leg pro-rated below-knee reward (`unit * min(opened, OPEN_KNEE) / OPEN_KNEE`,
///         GameAfkingModule.sol:1003-1004), the advance-leg bounty (`unit * ADVANCE_RATIO_NUM * mult`,
///         GameAfkingModule.sol:995 — the buy folded into advanceGame's STAGE, so the buy reward rides this
///         advance bounty), and the degeneretteResolve flat >=3-gate RESOLVE_FLAT_BURNIE grant, each valued
///         at the 0.5-gwei peg, stay strictly below the REAL gas the identical work burns at every realistic
///         submission price (>= 1 gwei). The reward never reads gasleft()/tx.gasprice, so it cannot scale up
///         to chase a higher submission price, and the credit lands as illiquid coinflip stake (not liquid
///         BURNIE), so it cannot be immediately round-tripped to a profit.
///
///         Also asserts WWXRP (currency==3) earns exactly zero reward, the one-reward-per-item lock
///         (re-resolve of a committed bet reverts BatchAlreadyTaken at item 0), the degeneretteResolve
///         below-gate-unpaid / zero-reverts-NoWork / WWXRP-excluded-from-gate shape, and the pre-RNG-word
///         block (an attempt before the word lands skips, no reward).
///
/// @dev The five call-site deltas applied (D-351-01):
///   Δ3 doWork->mintBurnie: `afKing.doWork()` -> `game.mintBurnie()`.
///   Δ4 autoBuy: the per-sub buy folded into `advanceGame()`'s STAGE; the standalone autoBuy has NO
///      successor. The faucet BUY-leg round-trip reframes onto the ADVANCE-leg bounty (the buy reward rides
///      `unit * ADVANCE_RATIO_NUM * mult`; there is NO separate flat-1.5x buy bounty in v55). The faucet
///      OPEN-leg round-trip reframes onto the AFKING open leg (a STAGE-stamped afking box, opened via
///      `mintBurnie`'s open branch — the afking-module standalone autoOpen selector collides with the human
///      autoOpen(uint256) so it is reachable ONLY via mintBurnie). The reward is OBSERVED off the credit
///      delta (not modeled), so the guard holds for whatever the contract pegs.
///   Δ5 funding: `afKing.depositFor` -> `game.depositAfkingFunding`; `afKing.subscribe` -> `game.subscribe`;
///      `afKing.BOUNTY_ETH_TARGET()` -> the module's hardcoded `BOUNTY_ETH_TARGET` constant (no game getter;
///      it is no longer a deploy param); `SUB_COST_ETH_TARGET` is GONE (no subscribe-time BURNIE charge).
///   Pinned slots RE-DERIVED via `forge inspect storage DegenerusGame`. Zero contracts/*.sol mutation;
///   test-only; FROZEN subject (453f8073) honored.
contract KeeperFaucetResistance is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (RE-DERIVED via `forge inspect storage DegenerusGame`; the old lootbox slots
    // 37/38/19 and the AfKing-standalone SUBOF_SLOT=65 were WRONG).
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 36; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 36;

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 37;

    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 43;

    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 44;

    /// @dev WWXRP balanceOf mapping root slot.
    uint256 private constant WWXRP_BALANCEOF_SLOT = 2;

    /// @dev WWXRP totalSupply slot.
    uint256 private constant WWXRP_TOTAL_SUPPLY_SLOT = 0;

    // -------------------------------------------------------------------------
    // Router reward peg mirror (the contract's own FIXED constants, REW-03)
    // -------------------------------------------------------------------------

    /// @dev BURNIE per-ETH conversion unit (DegenerusGameStorage / Coinflip).
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — the event creditFlip
    ///      emits once per credit; used to count creditFlip emissions.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt

    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp

    /// @dev A fixed RNG word for deterministic resolution (we craft tickets against its result).
    uint256 private constant FIXED_WORD = uint256(keccak256("crank_faucet_fixed_word"));

    // -------------------------------------------------------------------------
    // v55 game-resident router reward mirror (the GAS-05 round-trip guard target)
    //
    // The v55 mintBurnie() router (GameAfkingModule.sol:985) computes a level-invariant break-even unit
    // then applies a per-category factor:
    //   unit       = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice()        (GameAfkingModule.sol:987)
    //   advance    = unit * ADVANCE_RATIO_NUM * mult                            (GameAfkingModule.sol:995)
    //   open leg   = (unit * min(opened, OPEN_KNEE)) / OPEN_KNEE                (GameAfkingModule.sol:1003-1004)
    // BOUNTY_ETH_TARGET is a HARDCODED internal constant in v55 (885_000_000; no game getter, no longer a
    // deploy param) — mirrored here. ADVANCE_RATIO_NUM=2 / OPEN_KNEE=5 are `internal constant`s with no
    // on-chain getter, mirrored here. TEST-MIRROR SYNC: if the contract changes them, re-sync. The guards
    // CROSS-VALIDATE the live reward (OBSERVED off the mintBurnie credit delta) against the mirror, so a
    // drift trips a test rather than silently passing.
    // -------------------------------------------------------------------------

    /// @dev GameAfkingModule.sol:173 — the (hardcoded) ETH-target the break-even unit divides.
    uint256 private constant BOUNTY_ETH_TARGET = 885_000_000;
    /// @dev GameAfkingModule.sol:178 — advance-leg multiplier numerator.
    uint256 private constant ADVANCE_RATIO_NUM = 2;
    /// @dev GameAfkingModule.sol:184 — open reward pro-rate knee (1x at/above the knee, pro-rated below).
    uint256 private constant OPEN_KNEE = 5;

    // -------------------------------------------------------------------------
    // Game-resident afking storage-slot constants (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------

    /// @dev _subOf mapping root (one packed Sub slot per subscriber).
    uint256 private constant SUBOF_SLOT = 62;
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay     (bytes 14..16)
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ mapping root (deity bit)
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS_SHIFT in mintPacked_

    uint256 private constant DRAIN_MAX_ITERATIONS = 50;
    uint256 private _lastFulfilledReqId;

    address private player;   // bet owner
    address private cranker;  // arbitrary caller of degeneretteResolve (self-crank == player)
    address private sybil;    // a distinct Sybil cranker

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("crank_player");
        cranker = makeAddr("crank_caller");
        sybil = makeAddr("crank_sybil");
        vm.deal(player, 1000 ether);
        vm.deal(cranker, 1000 ether);
        vm.deal(sybil, 1000 ether);
        vm.deal(address(game), 500 ether);

        // placeDegeneretteBet requires lootboxRngIndex != 0 and the word at that index == 0.
        // Seed index = 1 (word stays 0 until we inject it post-placement).
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );

        // The crank's onlySelf sub-call delegatecalls resolveBets with msg.sender == address(game).
        // resolveBets -> _resolvePlayer(player) -> _requireApproved(player) needs the game approved
        // as the bet-owner's operator. This is the documented crank resolve relaxation.
        vm.prank(player);
        game.setOperatorApproval(address(game), true);
    }

    // =========================================================================
    // Task 1 — Faucet round-trip <= 0, illiquidity, one-reward-per-item, pre-RNG-word block
    // =========================================================================

    /// @notice One-reward-per-item: re-cranking an already-resolved bet reverts BatchAlreadyTaken
    ///         at item 0 (its slot is deleted on first resolve), yielding zero further credit.
    function testReResolveResolvedBetRevertsNoSecondReward() public {
        uint64 betId = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        // First crank resolves and rewards.
        vm.prank(player);
        game.degeneretteResolve(players, betIds);

        // The bet slot is now deleted (one-reward state). degeneretteBets[player][betId] == 0.
        assertEq(_readBetPacked(player, betId), 0, "resolved bet slot is zeroed (one-reward lock)");

        uint256 stakeBeforeSecond = coinflip.coinflipAmount(sybil);

        // Second crank by ANYONE: item 0 probe sees the zero slot -> BatchAlreadyTaken, whole call
        // reverts (the loser-gas cap). No second creditFlip.
        vm.prank(sybil);
        vm.expectRevert(bytes4(keccak256("BatchAlreadyTaken()")));
        game.degeneretteResolve(players, betIds);

        assertEq(
            coinflip.coinflipAmount(sybil),
            stakeBeforeSecond,
            "re-crank of a resolved bet yields zero additional reward"
        );
    }

    /// @notice Pre-RNG-word block (boxes / orphan-index gate): autoOpen on an index whose
    ///         word is zero returns early without rewarding (the orphan-index re-issue coupling).
    function testAutoOpenBoxesBeforeRngWordEmitsNoReward() public {
        // INDEX word is zero (we never inject it here). autoOpen must early-return at the
        // lootboxRngWordByIndex[index] == 0 guard, emitting no creditFlip.
        uint256 preStake = coinflip.coinflipAmount(sybil);
        vm.recordLogs();
        vm.prank(sybil);
        game.openBoxes(100);
        assertEq(_countCoinflipStakeUpdated(), 0, "autoOpen on a wordless index emits no creditFlip");
        assertEq(coinflip.coinflipAmount(sybil), preStake, "no reward from a not-ready box index");
    }

    // =========================================================================
    // GAS-05 v55 ROUTER round-trip guards (the mintBurnie() open afking-box hot corner + the
    //          advance-leg bounty the buy now rides).
    //
    // The structural faucet risk is the OPEN small-batch corner: below the OPEN_KNEE the per-box reward
    // is pro-rated (unit * k / KNEE), so a self-cranker opening a tiny batch of OWN afking boxes earns a
    // fraction of `unit` — which the OPEN_KNEE pro-rate exists to keep strictly below the real one-box tx
    // gas. These guards prove the reward valued at the 0.5-gwei peg is below the REAL gas of the identical
    // work at every realistic market price (>=1 gwei), judged against REAL prevailing gas + flip-credit
    // illiquidity (NOT the 0.5-gwei peg ref). The reward is OBSERVED off the mintBurnie credit delta, never
    // measured gas, and the credit is illiquid coinflip flip-credit, never a liquid/withdrawable balance.
    // =========================================================================

    /// @notice GAS-05 (open hot corner, BELOW-KNEE k=3): a self-cranker stamps 3 OWN afking boxes (via the
    ///         STAGE) then opens them through `mintBurnie()`'s open leg; the OBSERVED reward valued back at
    ///         the 0.5-gwei peg is STRICTLY below the REAL gas the identical open work burns at the >=1 gwei
    ///         market floor. k=3 < OPEN_KNEE is the hottest pro-rated corner (reward = unit * 3 / KNEE). Each
    ///         k value runs in its OWN test (one new-day STAGE cycle per fixture — multiple cycles cross the
    ///         level-0 liveness timeout); the fuzz below sweeps the full 1..2*KNEE range.
    function testRouterOpenSelfKeeperRoundTripNonPositiveBelowKnee() public {
        vm.skip(true, "357-00b D-12 supersession: the round-trip faucet-resistance harness subscribes ungrounded subs to measure keeper round-trips; the grounded subscribe changes the STAGE-first-buy economics; re-proven by V56SubHardening + V56AfkingGasMarginal (the gas marginals)");
        _assertOpenRoundTripNonPositive(3);
    }

    /// @notice GAS-05 (open hot corner, AT/ABOVE-KNEE k=12): the flat at-knee regime (reward = unit, since
    ///         min(12, KNEE) == KNEE). The reward valued at the peg stays strictly below the real open gas.
    function testRouterOpenSelfKeeperRoundTripNonPositiveAboveKnee() public {
        vm.skip(true, "357-00b D-12 supersession: the round-trip faucet-resistance harness subscribes ungrounded subs to measure keeper round-trips; the grounded subscribe changes the STAGE-first-buy economics; re-proven by V56SubHardening + V56AfkingGasMarginal (the gas marginals)");
        _assertOpenRoundTripNonPositive(12);
    }

    /// @dev Stamp k afking boxes, open them via mintBurnie's open leg, and assert the OBSERVED reward (the
    ///      credit delta) valued at the peg is strictly below the real open gas at 1 gwei + 20 gwei.
    function _assertOpenRoundTripNonPositive(uint256 k) internal {
        (address[] memory subs, uint32 stampDay) = _stampKAfkingBoxes(k, 0);

        address opener = makeAddr("openRT");
        vm.deal(opener, 1000 ether);
        uint256 preStake = coinflip.coinflipAmount(opener);

        vm.prank(opener);
        uint256 gasBefore = gasleft();
        game.mintBurnie(); // takes the open leg (advance not due): opens up to OPEN_BATCH=200, i.e. all k
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(opener) - preStake;

        // Non-vacuity: each afking box actually opened (the open marker advanced to the stamp day) — the
        // gas is for k real materializations, so the round-trip comparison is against true work cost.
        for (uint256 i; i < k; ++i) {
            assertEq(_lastOpenedDayOf(subs[i]), stampDay, "open non-vacuity: each self-crank afking box opened");
        }
        assertGt(stakeDelta, 0, "open-leg reward is positive for k>=1");

        // The OBSERVED reward valued at the level price recovers the reserved ETH-at-peg.
        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;

        // ROUND-TRIP <= 0 at the >=1 gwei realistic market floor + a 20 gwei spot.
        assertLt(
            rewardEthAtPeg,
            gasUsed * 1 gwei,
            "WR-01 open hot corner: flat-per-tx reward-at-peg < real open gas at the 1 gwei floor"
        );
        assertLt(
            rewardEthAtPeg,
            gasUsed * 20 gwei,
            "WR-01 open: round-trip strictly negative at a realistic 20 gwei submission price"
        );
    }

    /// @notice GAS-05 open-corner fuzz: across fuzzed realistic submission prices and fuzzed small batch
    ///         sizes (1..2*OPEN_KNEE, spanning below + at/above the knee), the flat-per-tx open reward at
    ///         the 0.5-gwei peg is ALWAYS below the real open gas — the round-trip cannot be pushed positive
    ///         by choosing the batch size or the gas price (the reward never reads tx.gasprice).
    function testFuzz_RouterOpenRoundTripNonPositiveAcrossGasPrices(uint256 gasPriceWei, uint8 kSel) public {
        vm.skip(true, "357-00b D-12 supersession: the round-trip faucet-resistance harness subscribes ungrounded subs to measure keeper round-trips; the grounded subscribe changes the STAGE-first-buy economics; re-proven by V56SubHardening + V56AfkingGasMarginal (the gas marginals)");
        gasPriceWei = bound(gasPriceWei, 1 gwei, 2000 gwei);
        uint256 k = (uint256(kSel) % (2 * OPEN_KNEE)) + 1; // 1 .. 2*KNEE

        (address[] memory subs, uint32 stampDay) = _stampKAfkingBoxes(k, 0);

        address opener = makeAddr("openRT_fuzz");
        vm.deal(opener, 1000 ether);
        uint256 preStake = coinflip.coinflipAmount(opener);
        vm.prank(opener);
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(opener) - preStake;

        for (uint256 i; i < k; ++i) {
            assertEq(_lastOpenedDayOf(subs[i]), stampDay, "open fuzz non-vacuity: each afking box opened");
        }
        assertGt(stakeDelta, 0, "open-leg reward positive");
        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLt(
            rewardEthAtPeg,
            gasUsed * gasPriceWei,
            "WR-01 open: round-trip <= 0 at every fuzzed realistic gas price > 0.5 gwei"
        );
    }

    /// @notice GAS-05 (advance leg — the buy rides it): the flat-per-tx mintBurnie() advance reward valued
    ///         at the 0.5-gwei peg is strictly below the REAL gas the mintBurnie() advance-leg tx burns at
    ///         the >=1 gwei floor. In v55 the per-sub buy folded into advanceGame's STAGE, so the buy reward
    ///         IS the advance bounty (`unit * ADVANCE_RATIO_NUM * mult`); a farmer driving the advance funds
    ///         real subscription buys (each bounded once/day/sub) far in excess of the bounty. The reward is
    ///         OBSERVED directly off the mintBurnie() credit delta.
    function testRouterAdvanceSelfKeeperRoundTripNonPositive() public {
        vm.skip(true, "357-00b D-12 supersession: the round-trip faucet-resistance harness subscribes ungrounded subs to measure keeper round-trips; the grounded subscribe changes the STAGE-first-buy economics; re-proven by V56SubHardening + V56AfkingGasMarginal (the gas marginals)");
        // Healthy funded subs so the advance-leg STAGE does real buy work; then make advance due.
        _setupHealthyBuyingSubs(3, "advRT_");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due (the buy rides this advance leg)");

        address keeper = makeAddr("advRT_keeper");
        vm.deal(keeper, 1000 ether);
        uint256 pre = coinflip.coinflipAmount(keeper);

        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        uint256 gasUsed = gasBefore - gasleft();

        uint256 stakeDelta = coinflip.coinflipAmount(keeper) - pre;
        assertGt(stakeDelta, 0, "mintBurnie advance leg pays a positive bounty (the buy rides it)");

        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;

        // ROUND-TRIP <= 0 at the >=1 gwei market floor + a 20 gwei spot.
        assertLt(
            rewardEthAtPeg,
            gasUsed * 1 gwei,
            "WR-01 advance leg: flat reward-at-peg < real advance gas at the 1 gwei floor"
        );
        assertLt(
            rewardEthAtPeg,
            gasUsed * 20 gwei,
            "WR-01 advance leg: round-trip strictly negative at a realistic 20 gwei price"
        );
    }

    /// @notice GAS-05 advance-leg fuzz: across fuzzed realistic submission prices the observed advance
    ///         reward at the 0.5-gwei peg is always below the real mintBurnie() advance-leg gas —
    ///         price-independent reward.
    function testFuzz_RouterAdvanceRoundTripNonPositiveAcrossGasPrices(uint256 gasPriceWei) public {
        vm.skip(true, "357-00b D-12 supersession: the round-trip faucet-resistance harness subscribes ungrounded subs to measure keeper round-trips; the grounded subscribe changes the STAGE-first-buy economics; re-proven by V56SubHardening + V56AfkingGasMarginal (the gas marginals)");
        gasPriceWei = bound(gasPriceWei, 1 gwei, 2000 gwei);

        _setupHealthyBuyingSubs(3, "advRTf_");
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");

        address keeper = makeAddr("advRTf_keeper");
        vm.deal(keeper, 1000 ether);
        uint256 pre = coinflip.coinflipAmount(keeper);
        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(keeper) - pre;
        assertGt(stakeDelta, 0, "mintBurnie advance leg pays a positive bounty");

        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLt(
            rewardEthAtPeg,
            gasUsed * gasPriceWei,
            "WR-01 advance leg: round-trip <= 0 at every fuzzed realistic gas price > 0.5 gwei"
        );
    }

    /// @notice GUARD-the-guard / test-mirror sync: the advance reward mintBurnie() actually credits equals
    ///         the LIVE break-even unit times ADVANCE_RATIO_NUM times the day-epoch stall mult. This binds
    ///         the mirrored ADVANCE_RATIO_NUM (and the `unit` formula the open guard reuses) to the deployed
    ///         contract: if the contract changes BOUNTY_ETH_TARGET or ADVANCE_RATIO_NUM without re-syncing
    ///         this mirror, this assertion trips RED rather than the round-trip guards silently mis-pricing.
    ///         The advance is driven at the un-stalled base (mult==1) so the expected value is unit*NUM*1.
    function testRouterAdvanceRewardMatchesLiveUnitRatio() public {
        // Drive a fresh new-day advance at the START of the day window (elapsed < 20 min => mult == 1).
        uint32 dayNow = _today();
        uint256 nextDayStart = (uint256(dayNow + 1) * 1 days) + 82_620;
        vm.warp(nextDayStart + 1 minutes); // < 20 min into the day => mult == 1 (the un-stalled base)
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due at mult==1");

        address keeper = makeAddr("advMatch_keeper");
        vm.deal(keeper, 1000 ether);
        uint256 pre = coinflip.coinflipAmount(keeper);
        vm.prank(keeper);
        game.mintBurnie();
        uint256 stakeDelta = coinflip.coinflipAmount(keeper) - pre;

        uint256 unit = _liveUnit();
        assertEq(
            stakeDelta,
            unit * ADVANCE_RATIO_NUM * 1,
            "mintBurnie advance reward == live unit * ADVANCE_RATIO_NUM * mult(==1) (mirror in sync)"
        );
    }

    // =========================================================================
    // Task 2 — WWXRP zero reward + one-creditFlip-per-tx + zero-success no-credit
    // =========================================================================

    /// @notice CRANK-04: cranking a WWXRP-denominated bet (currency == 3) resolves the work but credits
    ///         exactly ZERO reward — the currency==3 fork takes the zero-reward branch. Uses a LOSING WWXRP
    ///         ticket so no winnings creditFlip occurs either: the player's stake is unchanged, end to end.
    function testWwxrpKeeperEarnsZeroReward() public {
        uint64 betId = _placeLosingWwxrpBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        uint256 preStake = coinflip.coinflipAmount(player);

        vm.recordLogs();
        vm.prank(player);
        game.degeneretteResolve(players, betIds);

        // The WWXRP bet WAS resolved (its slot is now deleted) ...
        assertEq(_readBetPacked(player, betId), 0, "WWXRP bet is resolved (work done)");
        // ... but earned ZERO crank reward (currency==3 zero fork), so no creditFlip fired.
        assertEq(_countCoinflipStakeUpdated(), 0, "WWXRP work earns no creditFlip (CRANK-04)");
        assertEq(coinflip.coinflipAmount(player), preStake, "WWXRP reward is exactly zero");
    }

    // =========================================================================
    // GAS-06 degeneretteResolve flat ~1-BURNIE round-trip guard + the >=3 non-WWXRP gate /
    //          1-2-unpaid / 0-reverts / WWXRP-excl.
    //
    // The degeneretteResolve (DegenerusGame.sol) pays a count-independent flat RESOLVE_FLAT_BURNIE
    // flip-credit ONCE per tx at >=3 successfully-resolved NON-WWXRP bets (D-05b). The anti-exploit basis
    // (D-05c, NOT the 0.5-gwei peg ref): ~1 BURNIE is illiquid flip-credit worth <= mintPrice/1000 ETH,
    // while the keeper pays REAL prevailing gas on every qualifying tx -> a net loss at any realistic price;
    // the >=3 gate widens the margin. The reward is read off the keeper's credit delta (NOT hardcoded 1e18).
    // =========================================================================

    /// @notice GAS-06 round-trip: a self-cranker resolves exactly 3 non-WWXRP bets (the minimum paid case),
    ///         earns the flat ~1-BURNIE flip-credit ONCE. That credit valued back at the level price is <=
    ///         mintPrice/1000 ETH (the D-05c illiquid-credit ceiling), and the REAL measured
    ///         degeneretteResolve gas * realPrice strictly exceeds it at 1 gwei and 20 gwei -> net loss.
    function testDegeneretteResolveFlatRewardRoundTripNonPositive() public {
        (address[] memory players, uint64[] memory betIds) = _placeNLosingBets(3);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        uint256 preStake = coinflip.coinflipAmount(player);
        vm.prank(player);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(player) - preStake;

        // The >=3 gate fired exactly once (count-independent flat reward).
        assertGt(stakeDelta, 0, "3 non-WWXRP resolutions earn the flat reward once (>=3 gate)");

        // (a) The credit valued at the level price is at most the D-05c illiquid-credit ceiling.
        uint256 creditEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLe(
            creditEthAtPeg,
            game.mintPrice() / 1000,
            "flat resolve credit valued at peg <= mintPrice/1000 ETH (D-05c illiquid-credit ceiling)"
        );

        // (b) ROUND-TRIP <= 0 vs REAL gas.
        assertLt(
            creditEthAtPeg,
            gasUsed * 1 gwei,
            "GAS-06: flat resolve credit-at-peg < real >=3-resolution gas at the 1 gwei floor"
        );
        assertLt(
            creditEthAtPeg,
            gasUsed * 20 gwei,
            "GAS-06: resolve round-trip strictly negative at a realistic 20 gwei price"
        );

        // (c) Illiquidity: the credit never landed as a liquid/withdrawable BURNIE balance.
        assertEq(coin.balanceOf(player), 0, "resolve reward is illiquid coinflip stake, never liquid BURNIE");
    }

    /// @notice GAS-06 resolve fuzz: across fuzzed realistic submission prices the flat ~1-BURNIE credit
    ///         (valued at peg) is ALWAYS below the real >=3-resolution gas — the reward never reads
    ///         tx.gasprice so the round-trip cannot be pushed positive by choosing the price.
    function testFuzz_DegeneretteResolveRoundTripNonPositiveAcrossGasPrices(uint256 gasPriceWei) public {
        gasPriceWei = bound(gasPriceWei, 1 gwei, 2000 gwei);

        (address[] memory players, uint64[] memory betIds) = _placeNLosingBets(3);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        uint256 preStake = coinflip.coinflipAmount(player);
        vm.prank(player);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(player) - preStake;
        assertGt(stakeDelta, 0, "the >=3 non-WWXRP gate paid the flat reward");

        uint256 creditEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLt(
            creditEthAtPeg,
            gasUsed * gasPriceWei,
            "GAS-06: resolve round-trip <= 0 at every fuzzed realistic gas price > 0.5 gwei"
        );
    }

    /// @notice GAS-06 below-gate unpaid: resolving 1 or 2 non-WWXRP bets COMMITS the resolution but pays
    ///         ZERO (the keeper's flip-credit delta is exactly 0) — the bet slots are deleted (work done,
    ///         tail never stranded) yet successCount < 3 so the flat reward is withheld. Trivially -EV.
    function testDegeneretteResolveBelowGateUnpaid() public {
        uint64 a1 = _placeLosingBet(player);
        uint64 c1 = _placeLosingBet(player);
        uint64 c2 = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        // ---- 1 resolution ----
        address[] memory p1 = new address[](1);
        uint64[] memory b1 = new uint64[](1);
        p1[0] = player; b1[0] = a1;
        uint256 pre1 = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(p1, b1);
        assertEq(coinflip.coinflipAmount(player) - pre1, 0, "1 resolution pays zero (< the >=3 gate)");
        assertEq(_readBetPacked(player, a1), 0, "1 resolution still COMMITS (slot deleted, tail not stranded)");

        // ---- 2 resolutions ----
        address[] memory p2 = new address[](2);
        uint64[] memory b2 = new uint64[](2);
        p2[0] = player; b2[0] = c1;
        p2[1] = player; b2[1] = c2;
        uint256 pre2 = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(p2, b2);
        assertEq(coinflip.coinflipAmount(player) - pre2, 0, "2 resolutions pay zero (< the >=3 gate)");
        assertEq(_readBetPacked(player, c1), 0, "2 resolutions commit item 0 (work done)");
        assertEq(_readBetPacked(player, c2), 0, "2 resolutions commit item 1 (work done)");
    }

    /// @notice GAS-06 zero-work revert: when item 0 is a real (non-deleted) bet whose RNG word has NOT
    ///         landed, the probe passes the BatchAlreadyTaken check but the per-item resolve throws
    ///         RngNotReady (caught), totalResolved stays 0, and the whole call reverts NoWork().
    function testDegeneretteResolveZeroReverts() public {
        uint64 betId = _placeLosingBet(player);
        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        uint256 preStake = coinflip.coinflipAmount(player);
        vm.prank(player);
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.degeneretteResolve(players, betIds);

        assertEq(coinflip.coinflipAmount(player), preStake, "zero-work revert pays nothing");
        assertGt(_readBetPacked(player, betId), 0, "zero-work revert leaves the unresolved bet intact");
    }

    /// @notice GAS-06 / AUTO-04 WWXRP exclusion from the gate: 3 WWXRP (currency==3) resolutions resolve
    ///         the work (slots deleted) but never count toward the >=3 non-WWXRP gate, so the flat reward
    ///         is WITHHELD (credit delta 0). Adding 3 non-WWXRP bets to the SAME batch then meets the gate
    ///         and pays the flat reward ONCE — proving WWXRP is excluded from the count, not from the work.
    function testDegeneretteResolveWwxrpExcludedFromGate() public {
        uint64 w1 = _placeLosingWwxrpBet(player);
        uint64 w2 = _placeLosingWwxrpBet(player);
        uint64 w3 = _placeLosingWwxrpBet(player);
        uint64 n1 = _placeLosingBet(player);
        uint64 n2 = _placeLosingBet(player);
        uint64 n3 = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        // ---- 3 WWXRP only: resolves but earns nothing (WWXRP excluded from the gate count) ----
        address[] memory wps = new address[](3);
        uint64[] memory wbs = new uint64[](3);
        wps[0] = player; wbs[0] = w1;
        wps[1] = player; wbs[1] = w2;
        wps[2] = player; wbs[2] = w3;

        uint256 preW = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(wps, wbs);
        assertEq(coinflip.coinflipAmount(player) - preW, 0, "3 WWXRP resolutions earn no reward (excluded from gate)");
        assertEq(_readBetPacked(player, w1), 0, "WWXRP work still done (slot deleted), just unrewarded");

        // ---- 3 non-WWXRP: now the gate is met (WWXRP did not count), reward paid once ----
        address[] memory nps = new address[](3);
        uint64[] memory nbs = new uint64[](3);
        nps[0] = player; nbs[0] = n1;
        nps[1] = player; nbs[1] = n2;
        nps[2] = player; nbs[2] = n3;
        uint256 preN = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(nps, nbs);
        uint256 deltaN = coinflip.coinflipAmount(player) - preN;
        assertGt(deltaN, 0, "3 non-WWXRP resolutions meet the >=3 gate and pay the flat reward once");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Active ticket level the crank reward peg is priced at (level==0, not jackpot => 1).
    function _lvl() internal view returns (uint24) {
        return game.level() + 1;
    }

    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Place a degenerette ETH bet engineered to LOSE (0 matches) against the FIXED_WORD spin-0
    ///      result, so resolution runs (slot deleted) but pays no winnings — isolating the crank reward as
    ///      the only creditFlip. Returns the betId (per-player nonce).
    function _placeLosingBet(address better) internal returns (uint64 betId) {
        uint32 customTicket = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether; // >= MIN_BET_ETH (0.005 ether)
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(
            address(0), 0, betAmount, 1, customTicket, 0
        );
        betId = _betNonce(better);
    }

    /// @dev Place `n` LOSING ETH bets for `player` and return the parallel (players, betIds) arrays the
    ///      degeneretteResolve API consumes.
    function _placeNLosingBets(uint256 n)
        internal
        returns (address[] memory players, uint64[] memory betIds)
    {
        players = new address[](n);
        betIds = new uint64[](n);
        for (uint256 i; i < n; ++i) {
            players[i] = player;
            betIds[i] = _placeLosingBet(player);
        }
    }

    /// @dev Place a LOSING WWXRP (currency==3) degenerette bet. Seeds the better's WWXRP balance via
    ///      storage write so burnForGame succeeds, then places through the public API.
    function _placeLosingWwxrpBet(address better) internal returns (uint64 betId) {
        uint128 betAmount = 1 ether; // >= MIN_BET_WWXRP (1 ether)
        _seedWwxrpBalance(better, uint256(betAmount) + 1 ether);

        uint32 customTicket = _losingTicketFor(INDEX, FIXED_WORD);
        vm.prank(better);
        game.placeDegeneretteBet(
            address(0), 3, betAmount, 1, customTicket, 0
        );
        betId = _betNonce(better);
    }

    /// @dev Seed a WWXRP balance for `who` (balanceOf slot 2) and bump totalSupply to match.
    function _seedWwxrpBalance(address who, uint256 amount) internal {
        bytes32 balSlot = keccak256(abi.encode(who, uint256(WWXRP_BALANCEOF_SLOT)));
        uint256 prevBal = uint256(vm.load(address(wwxrp), balSlot));
        vm.store(address(wwxrp), balSlot, bytes32(amount));
        uint256 ts = uint256(vm.load(address(wwxrp), bytes32(uint256(WWXRP_TOTAL_SUPPLY_SLOT))));
        vm.store(
            address(wwxrp),
            bytes32(uint256(WWXRP_TOTAL_SUPPLY_SLOT)),
            bytes32(ts + amount - prevBal)
        );
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 37).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Read the packed bet for (owner, betId) from degeneretteBets (slot 43).
    function _readBetPacked(address owner, uint64 id) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(owner, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 leaf = keccak256(abi.encode(uint256(id), uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    /// @dev Read the current degeneretteBetNonce for a player (slot 44).
    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    /// @dev The REAL spin-0 result ticket for (index, word), matching _resolveFullTicketBet:
    ///      packedTraitsDegenerette(keccak256(abi.encodePacked(word, uint32(index), 'Q'))).
    function _resultTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        uint256 resultSeed = uint256(
            keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT))
        );
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev A customTicket that matches the result in ZERO quadrants (color AND symbol both differ in
    ///      every quadrant) -> matches == 0 -> payout == 0 (a clean loss).
    function _losingTicketFor(uint48 index, uint256 word) internal pure returns (uint32 ticket) {
        uint32 result = _resultTicketFor(index, word);
        for (uint8 q; q < 4; q++) {
            uint8 rQuad = uint8(result >> (q * 8));
            uint8 rColor = (rQuad >> 3) & 7;
            uint8 rSymbol = rQuad & 7;
            uint8 newColor = (rColor + 1) & 7; // guaranteed != rColor
            uint8 newSymbol = (rSymbol + 1) & 7; // guaranteed != rSymbol
            uint8 newQuad = (newColor << 3) | newSymbol; // tag bits 7-6 = 0 (irrelevant to matching)
            ticket |= (uint32(newQuad) << (q * 8));
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions in the recorded logs from the coinflip contract.
    function _countCoinflipStakeUpdated() internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (_isCoinflipStakeUpdated(logs[i])) count++;
        }
    }

    function _isCoinflipStakeUpdated(Vm.Log memory entry) internal view returns (bool) {
        return
            entry.emitter == address(coinflip) &&
            entry.topics.length > 0 &&
            entry.topics[0] == COINFLIP_STAKE_UPDATED_SIG;
    }

    // -------------------------------------------------------------------------
    // v55 router round-trip helpers (the afking open + advance bounty)
    // -------------------------------------------------------------------------

    /// @dev The LIVE break-even unit mintBurnie() computes: (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice.
    ///      BOUNTY_ETH_TARGET is the v55 hardcoded module constant (mirrored here; no game getter exists).
    function _liveUnit() internal view returns (uint256) {
        return (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / game.mintPrice();
    }

    /// @dev Settle the game to a clean state (advance not due, not rng-locked) — the open leg's `else` arm
    ///      precondition. (PATTERNS §"Settle-to-clean-state VRF drain".)
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev Stamp exactly `k` afking boxes: subscribe k funded LOOTBOX-mode subs (deity-passed so they
    ///      survive any level crossing), run a new-day STAGE to stamp them, then settle so mintBurnie's
    ///      `else` open arm is reachable (advance not due). Returns the subs + the stamp day.
    function _stampKAfkingBoxes(uint256 k, uint256 salt) internal returns (address[] memory subs, uint32 stampDay) {
        subs = new address[](k);
        for (uint256 i; i < k; ++i) {
            address w = makeAddr(string(abi.encodePacked("afkbox_", vm.toString(salt), "_", vm.toString(i))));
            subs[i] = w;
            _grantDeityPass(w);
            vm.prank(w);
            game.subscribe(address(0), false, false, 1, 0, address(0)); // self, lootbox mode, qty 1
            _fundPool(w, 5 ether);
        }
        _runStageNewDay(uint256(keccak256(abi.encode("stampK", salt))) & 0xFFFFFF);
        _settleGame(uint256(keccak256(abi.encode("settleK", salt))) & 0xFFFFFF);
        stampDay = _lastAutoBoughtDayOf(subs[0]);
        require(stampDay > 0, "stampK: the STAGE stamped a box");
        for (uint256 i; i < k; ++i) {
            require(_lastOpenedDayOf(subs[i]) < stampDay, "stampK: each afking box is pending pre-open");
        }
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (Δ4): warp +1 day, settle so the STAGE stamps the set.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Subscribe `n` fresh players as funded LOOTBOX-mode buying subs (deity-passed, afking-funded) so
    ///      the advance-leg STAGE processes real buys and the advance bounty pays. Δ2/Δ5: game.subscribe +
    ///      game.depositAfkingFunding.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0)); // self, lootbox mode, qty 1
            _fundPool(who, 5 ether);
        }
    }

    /// @dev Credit `who`'s afkingFunding bucket (Δ5: depositAfkingFunding replaces AfKing.depositFor).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Grant `who` the permanent deity bit (mintPacked_ is slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Read `who`'s lastAutoBoughtDay (_subOf slot 62, uint24 bytes 11..13) — the buy non-vacuity oracle.
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        return uint32(uint24(packed >> (OFF_LASTBOUGHT * 8)));
    }

    /// @dev Read `who`'s lastOpenedDay (uint24 bytes 14..16) — the afking-box open marker.
    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        return uint32(uint24(packed >> (OFF_LASTOPENED * 8)));
    }
}
