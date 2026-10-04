// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

// CURRENT ENGINE (60d31f775 / 72fc06f6c): the router below is retired. `mineFlip()` is the
//      single engine (DegenerusGameMinerModule); it pays once per call, CEI-last, in FLIP coinflip
//      credit: (measured gas - unpaid first MIN_REWARDED_GAS) x min(basefee, cap) x (0.3x + 0.45x per
//      30 minutes, x2 pass, x2 lock) at the ticket price. Bets resolve as the Degenerette read
//      consumer, never through `openBoxes`. The guards read the measured gas and the pay from each
//      call's MinerWork event and pin them to that formula; the self-keeper round trip is checked at
//      the fixture's sub-1x multiplier, where it must stay net negative. The history below is kept for
//      the requirement IDs.
/// @title KeeperFaucetResistance -- Proves the v55.0 game-resident permissionless router
///        (`game.mineFlip()` advance/open legs, including the queued-bet sweep) is faucet-bounded by three
///        caller-independent locks:
///        (1) the purchase-gate (an item must already be a real, purchased, RNG-ready bet/box/stamp),
///        (2) the flat-per-tx LIVE-unit reward judged against the REAL prevailing gas of the identical
///            work at the >=1 gwei market floor (never measured gas, never the peg ref), and
///        (3) the coinflip-credit illiquidity (creditFlip = pending stake, not liquid FLIP).
///
/// @notice A self-keeper / Sybil round-trip is net-zero-or-negative across the v55 router legs: the
///         `mineFlip()` open-leg pro-rated below-knee reward (`unit * min(opened, OPEN_KNEE) / OPEN_KNEE`,
///         GameAfkingModule.sol:1003-1004), the advance-leg bounty (`unit * ADVANCE_RATIO_NUM * mult`,
///         GameAfkingModule.sol:995 — the buy folded into mineFlip's STAGE, so the buy reward rides this
///         advance bounty), and the bet-sweep share of the open bounty (credited at the work run), each valued
///         at the 0.5-gwei peg, stay strictly below the REAL gas the identical work burns at every realistic
///         submission price (>= 1 gwei). The reward never reads gasleft()/tx.gasprice, so it cannot scale up
///         to chase a higher submission price, and the credit lands as illiquid coinflip stake (not liquid
///         FLIP), so it cannot be immediately round-tripped to a profit.
///
///         Also asserts the one-reward-per-item lock
///         (re-sweeping a drained queue makes no progress and pays nothing), the
///         below-gate-unpaid / zero-reverts-NoWork shape, and the pre-RNG-word
///         block (an attempt before the word lands skips, no reward).
///
/// @dev The five call-site deltas applied (D-351-01):
///   Δ3 doWork->mineFlip: `afKing.doWork()` -> `game.mineFlip()`.
///   Δ4 autoBuy: the per-sub buy folded into `mineFlip()`'s STAGE; the standalone autoBuy has NO
///      successor. The faucet BUY-leg round-trip reframes onto the ADVANCE-leg bounty (the buy reward rides
///      `unit * ADVANCE_RATIO_NUM * mult`; there is NO separate flat-1.5x buy bounty in v55). The faucet
///      OPEN-leg round-trip reframes onto the AFKING open leg (a STAGE-stamped afking box, opened via
///      `mineFlip`'s open branch — the afking-module standalone autoOpen selector collides with the human
///      autoOpen(uint256) so it is reachable ONLY via mineFlip). The reward is OBSERVED off the credit
///      delta (not modeled), so the guard holds for whatever the contract pegs.
///   Δ5 funding: `afKing.depositFor` -> `game.depositAfkingFunding`; `afKing.subscribe` -> `game.subscribe`;
///      `afKing.BOUNTY_ETH_TARGET()` -> the module's hardcoded `BOUNTY_ETH_TARGET` constant (no game getter;
///      it is no longer a deploy param); `SUB_COST_ETH_TARGET` is GONE (no subscribe-time FLIP charge).
///   Pinned slots RE-DERIVED via `forge inspect storage DegenerusGame`. Zero contracts/*.sol mutation;
///   test-only; FROZEN subject (453f8073) honored.
contract KeeperFaucetResistance is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (RE-DERIVED via `forge inspect storage DegenerusGame`; the old lootbox slots
    // 37/38/19 and the AfKing-standalone SUBOF_SLOT=65 were WRONG).
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 34; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 33;

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 3;


    // -------------------------------------------------------------------------
    // Router reward peg mirror (the contract's own FIXED constants, REW-03)
    // -------------------------------------------------------------------------

    /// @dev FLIP per-ETH conversion unit (DegenerusGameStorage / Coinflip).
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)") — the event creditFlip
    ///      emits once per credit; used to count creditFlip emissions.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt

    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp

    /// @dev Lowest gas price the self-keeper round trip is checked at (see GAS-06).
    uint256 private constant MIN_GAS_PRICE = 0.1 gwei;

    /// @dev A fixed RNG word for deterministic resolution (we craft tickets against its result).
    uint256 private constant FIXED_WORD = uint256(keccak256("crank_faucet_fixed_word"));

    // -------------------------------------------------------------------------
    // Miner reward mirror (72fc06f6c). The v55 flat unit (BOUNTY_ETH_TARGET, ADVANCE_RATIO_NUM,
    // OPEN_KNEE) is gone: mineFlip pays the call's measured gas above an unpaid first
    // MIN_REWARDED_GAS, at min(basefee, cap), times 0.3x + 0.45x per 30 minutes on one clock (the
    // later of the last accepted callback and the day reset; cap 0.5 gwei doubling per step, four
    // steps max), x2 for an active pass holder, x2 when the daily lock is held at call start, in FLIP
    // at the active ticket price. The guards below read the measured gas and the paid amount off the
    // call's MinerWork event and cross-check them against this mirror, so a drift trips a test.
    // -------------------------------------------------------------------------

    bytes32 private constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");
    uint256 private constant INITIAL_REWARD_BASEFEE_CAP = 0.5 gwei;

    // -------------------------------------------------------------------------
    // Game-resident afking storage-slot constants (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------

    /// @dev _subOf mapping root (one packed Sub slot per subscriber).
    uint256 private constant SUBOF_SLOT = 52;
    uint256 private constant OFF_LASTBOUGHT = 7; // uint24 lastAutoBoughtDay (bytes 7..9; Sub: u8 qty, u8 flags, u16 score, u24 amount)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay     (bytes 10..12)
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ mapping root (deity bit)
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS_SHIFT in mintPacked_

    uint256 private constant DRAIN_MAX_ITERATIONS = 50;
    uint256 private _lastFulfilledReqId;

    address private player;   // bet owner
    address private cranker;  // arbitrary third-party caller (self-crank == player)
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
        RecyclingState.seedWriteBuffer(address(game), INDEX);
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

    /// @notice One-reward-per-item: a bet is marked processed in its queue once the engine's
    ///         Degenerette stage resolves it, so a second crank over the same drained queue finds no
    ///         work (NoWork) and pays nothing; no path pays for it twice. The unrewarded `openBoxes`
    ///         valve drives only the AFK and human box stages (60d31f775), never bets, and pays no
    ///         keeper reward at all.
    function testReResolveResolvedBetRevertsNoSecondReward() public {
        uint64 betId = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);
        _openSweepFor(INDEX);

        uint256 stakeBefore = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.openBoxes(type(uint256).max);
        assertGt(game.degeneretteBetInfo(INDEX, betId), 0, "the box valve does not resolve bets");
        assertEq(coinflip.coinflipAmount(player), stakeBefore, "the box valve pays no keeper reward");

        vm.fee(1 gwei);
        vm.recordLogs();
        vm.prank(player);
        game.mineFlip();
        (, uint256 measured, uint256 reward) = _minerWork(vm.getRecordedLogs());
        assertEq(game.degeneretteBetInfo(INDEX, betId), 0, "resolved bet is marked processed (one-reward lock)");
        assertEq(reward, _expectedPay(measured, false, false), "the resolving crank is paid its measured gas only");
        assertEq(coinflip.coinflipAmount(player), stakeBefore + _whole(reward), "the only credit is the measured-gas bounty");

        uint256 stakeBeforeSecond = coinflip.coinflipAmount(sybil);
        vm.prank(sybil);
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.mineFlip();
        vm.prank(sybil);
        uint256 openedAgain = game.openBoxes(type(uint256).max);
        assertEq(openedAgain, 0, "an already-drained queue offers a second sweep nothing to resolve");
        assertEq(coinflip.coinflipAmount(sybil), stakeBeforeSecond, "re-sweeping a resolved queue yields nothing");
    }

    /// @notice Pre-RNG-word block (boxes / orphan-index gate): autoOpen on an index whose
    ///         word is zero returns early without rewarding (the orphan-index re-issue coupling).
    function testAutoOpenBoxesBeforeRngWordEmitsNoReward() public {
        // INDEX word is zero (we never inject it here). autoOpen must early-return at the
        // _lootboxWord(index) == 0 guard, emitting no creditFlip.
        uint256 preStake = coinflip.coinflipAmount(sybil);
        vm.recordLogs();
        vm.prank(sybil);
        game.openBoxes(100);
        assertEq(_countCoinflipStakeUpdated(), 0, "autoOpen on a wordless index emits no creditFlip");
        assertEq(coinflip.coinflipAmount(sybil), preStake, "no reward from a not-ready box index");
    }


    /// @dev Stamp k afking boxes, open them via mineFlip's open leg, and assert the OBSERVED reward (the
    ///      credit delta) valued at the peg is strictly below the real open gas at 1 gwei + 20 gwei.
    function _assertOpenRoundTripNonPositive(uint256 k) internal {
        (address[] memory subs, uint32 stampDay) = _stampKAfkingBoxes(k, 0);

        address opener = makeAddr("openRT");
        vm.deal(opener, 1000 ether);
        uint256 preStake = coinflip.coinflipAmount(opener);

        vm.prank(opener);
        uint256 gasBefore = gasleft();
        game.mineFlip(); // takes the open leg (advance not due): opens up to OPEN_BATCH=200, i.e. all k
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


    /// @notice GUARD-the-guard / test-mirror sync: the advance reward mineFlip() actually credits equals
    ///         the measured-gas formula (72fc06f6c) evaluated on the call's own MinerWork-reported gas.
    ///         This binds the mirror (unpaid first million, capped base fee, 0.3x base, lock doubling,
    ///         FLIP at the ticket price) to the deployed engine: a contract change without a re-sync
    ///         trips RED rather than the round-trip guards silently mis-pricing. Replaces the retired
    ///         flat `unit * ADVANCE_RATIO_NUM * mult` check (testRouterAdvanceRewardMatchesLiveUnitRatio).
    function testRouterAdvanceRewardMatchesMeasuredGasFormula() public {
        // A fresh new-day advance at the START of the day window: the clock is the day reset, so the
        // request call runs at the base 0.3x and the 0.5 gwei cap.
        uint32 dayNow = _today();
        uint256 nextDayStart = (uint256(dayNow + 1) * 1 days) + 82_620;
        vm.warp(nextDayStart + 1 minutes);
        assertTrue(game.advanceDue(), "pre: a fresh day-advance is due");
        vm.fee(1 gwei);

        address keeper = makeAddr("advMatch_keeper");
        vm.deal(keeper, 1000 ether);
        // The day's preparation (subscriber stamp, scheduled table upkeep) and its request may take
        // more than one call; every one is paid exactly its measured-gas formula.
        uint256 pre;
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) {
            pre = coinflip.coinflipAmount(keeper);
            vm.recordLogs();
            vm.prank(keeper);
            game.mineFlip();
            (, uint256 prepGas, uint256 prepReward) = _minerWork(vm.getRecordedLogs());
            assertEq(prepReward, _expectedPay(prepGas, false, false), "preparation call: reward == measured-gas formula");
            assertEq(coinflip.coinflipAmount(keeper) - pre, _whole(prepReward), "preparation call: the credit is the reported reward");
        }
        assertTrue(game.rngLocked(), "the request took the daily lock");

        // The day's processing after its word lands: the accepted callback restarts the clock (base
        // rate) and the lock is held at call start (x2).
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256("advMatch_word")));
        pre = coinflip.coinflipAmount(keeper);
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        (, uint256 measured, uint256 reward) = _minerWork(vm.getRecordedLogs());
        emit log_named_uint("advance call measured gas", measured);
        emit log_named_uint("advance call reward", reward);
        assertGt(measured, MineFlipGas.MIN_REWARDED_GAS, "non-vacuity: the advance measured past the unpaid first million");
        assertEq(reward, _expectedPay(measured, false, true), "advance reward == measured-gas formula (mirror in sync)");
        assertEq(coinflip.coinflipAmount(keeper) - pre, _whole(reward), "the credit is the reported reward");
    }

    // =========================================================================
    // GAS-06 bet-sweep bounty round trip
    //
    // Queued bets resolve inside mineFlip's human-box sweep and earn its box-open bounty, credited
    // at the work each bet actually ran (never the worst-case budget price). A self-keeper who
    // places the cheapest bets purely to crank them must pay more gas placing and cranking than
    // the bounty is worth. The house edge is ignored (it only deepens the loss), so this is the
    // high-activity player's best case.
    // =========================================================================

    /// @notice GAS-06: placing N bets and cranking them yourself costs more gas than the bounty is
    ///         worth at the level price, down to MIN_GAS_PRICE, for every cheap shape at every
    ///         batch size one crank can resolve: ETH and FLIP minimums at 1 spin and at the maximum
    ///         spins, and an ETH minimum on a protocol-deity symbol whose two-day boon-draw ring is
    ///         already warm. Each resolved bet earns the keeper a small flat credit, so the most a
    ///         self-keeper can win is about one knee step per ~47 bets. The keeper's gas is
    ///         discounted by the largest EIP-3529 refund it could get (a fifth), and the house edge
    ///         is ignored (it only deepens the loss), so this is the self-keeper's best case.
    /// forge-config: default.fuzz.runs = 256
    function testFuzz_BetSweepSelfKeeperRoundTripNonPositive(uint16 nSel, uint256 gasPriceWei, uint8 shapeSel) public {
        gasPriceWei = bound(gasPriceWei, MIN_GAS_PRICE, 2000 gwei);
        // shape: 0 ETH 1 spin, 1 FLIP 1 spin, 2 ETH 1 spin on symbol 0 (warm ring),
        //        3 ETH 25 spins, 4 FLIP 15 spins. Caps keep every bet inside one crank's budget.
        uint8 shape = shapeSel % 5;
        uint16[5] memory caps = [uint16(48), 300, 48, 21, 95];
        uint8[5] memory spinsOf = [uint8(1), 1, 1, 25, 15];
        uint256 n = (uint256(nSel) % caps[shape]) + 1;
        bool flip = shape == 1 || shape == 4;
        if (flip) {
            vm.prank(address(game));
            coin.mintForGame(player, 100_000_000 ether);
        }
        if (shape == 2) _warmBoonRing(address(vault), n + 5);
        uint256 placeGas;
        for (uint256 i; i < n; ++i) {
            vm.prank(player);
            uint256 g = gasleft();
            if (flip) game.placeDegeneretteBet(address(0), 1, 100 ether, spinsOf[shape], 9);
            else game.placeDegeneretteBet{value: uint256(0.005 ether) * spinsOf[shape]}(
                address(0), 0, 0.005 ether, spinsOf[shape], shape == 2 ? 0 : 9
            );
            placeGas += g - gasleft();
        }
        if (shape == 2) {
            // The warm-ring shape really entered the boon draw: the ring slot now holds today.
            uint24 d = game.currentDayView();
            uint256 w = uint256(vm.load(address(game), keccak256(abi.encode(uint256(d & 1),
                keccak256(abi.encode(address(vault), uint256(48)))))));
            assertEq(uint24(w >> 216), d, "ring slot not retagged to today");
            assertEq(uint32(w >> 176), n, "every bet entered the boon draw");
        }
        _injectLootboxRngWord(INDEX, FIXED_WORD);
        _openSweepFor(INDEX);

        // The keeper pays the base fee as its gas price; the bounty is priced at min(basefee, cap).
        vm.fee(gasPriceWei);
        vm.txGasPrice(gasPriceWei);
        uint256 preStake = coinflip.coinflipAmount(player);
        vm.recordLogs();
        vm.prank(player);
        uint256 g0 = gasleft();
        game.mineFlip();
        uint256 crankGas = g0 - gasleft();
        uint256 bounty = coinflip.coinflipAmount(player) - preStake;
        (, uint256 measured, uint256 reported) = _minerWork(vm.getRecordedLogs());

        assertEq(DQ.lastBetId(vm, address(game), INDEX), n, "n bets queued");
        for (uint64 id = 1; id <= n; ++id) assertEq(game.degeneretteBetInfo(INDEX, id), 0, "sweep resolved every bet");
        assertEq(bounty, _whole(reported), "the credit is the reported bounty");
        assertEq(reported, _expectedPay(measured, false, false), "the bounty is the measured-gas formula");
        // The fixture's clock is one half-hour step into the day (0.75x, cap 1 gwei), no pass, no lock:
        // below 1x, so the measured-gas bounty can never cover the gas the self-keeper burned.
        uint256 bountyEth = (bounty * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLt(bountyEth, ((placeGas + crankGas) * 4 / 5) * gasPriceWei, "self-keeping bets is net-negative");
    }

    /// @dev Steady state of the protocol boon draw's two-day ring: the pool slot two days back holds
    ///      an older, drawn day and its entry slots hold old entries, so a new day's entries rewrite
    ///      warm-shaped slots (the cheapest boon-draw placement there is).
    function _warmBoonRing(address issuer, uint256 entries) internal {
        uint24 d = game.currentDayView();
        uint256 ring = uint256(d & 1);
        bytes32 poolRoot = keccak256(abi.encode(issuer, uint256(48)));
        bytes32 entryRoot = keccak256(abi.encode(ring, keccak256(abi.encode(issuer, uint256(49)))));
        uint256 old = uint256(d - 2);
        vm.store(address(game), keccak256(abi.encode(ring, poolRoot)),
            bytes32((old << 216) | (uint256(7) << 208) | (uint256(entries) << 176) | (uint256(1) << 112) | 1));
        for (uint256 i; i < entries; ++i) {
            vm.store(address(game), keccak256(abi.encode(i, entryRoot)), bytes32((uint256(i + 1) << 160) | 0xBEEF));
        }
    }

    /// @notice The credit is work-based: a queue of cheap losing bets earns far less than the
    ///         worst-case budget price the sweep charged for them.
    function testBetSweepCreditsWorkNotBudget() public {
        for (uint256 i; i < 8; ++i) {
            vm.prank(player);
            game.placeDegeneretteBet{value: 0.005 ether}(address(0), 0, 0.005 ether, 1, 9);
        }
        uint256 word;
        for (uint256 k; ; ++k) {
            word = uint256(keccak256(abi.encodePacked("faucet_losing_word", k)));
            (uint8 score,) = Ref.score(Ref.player(word, uint32(INDEX), 9, 0, false), Ref.house(word, uint32(INDEX), 0, false), 1);
            if (score < 2) break;
        }
        _injectLootboxRngWord(INDEX, word);
        _openSweepFor(INDEX);
        vm.fee(1 gwei);
        uint256 preStake = coinflip.coinflipAmount(player);
        vm.recordLogs();
        vm.prank(player);
        game.mineFlip();
        uint256 bounty = coinflip.coinflipAmount(player) - preStake;
        (, uint256 measured,) = _minerWork(vm.getRecordedLogs());
        for (uint64 id = 1; id <= 8; ++id) assertEq(game.degeneretteBetInfo(INDEX, id), 0, "the crank resolved every bet");
        // Eight ETH 1-spin bets are admitted at their declared worst-case bounds (base + one spin
        // each), but the bounty is priced on the gas the crank actually measured (72fc06f6c).
        uint256 budget = 8 * (MineFlipGasBounds.DEGENERETTE_ETH_BASE_GAS + MineFlipGasBounds.DEGENERETTE_ETH_SPIN_GAS);
        emit log_named_uint("measured crank gas", measured);
        emit log_named_uint("declared admission budget", budget);
        assertLt(measured, budget, "the crank measured less than the declared budget it admitted");
        assertEq(bounty, _expectedPay(measured, false, false), "the credit is priced on measured work");
        assertLt(bounty, _expectedPay(budget, false, false), "cheap bets do not buy the budget's price");
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
        uint32 customTraits = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether; // >= MIN_BET_ETH (0.005 ether)
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(address(0), 0, betAmount, 1, uint8(customTraits & 7));
        betId = DQ.lastBetId(vm, address(game), INDEX);
    }

    /// @dev Ready the delivered cohort at `idx` on a sealed day, 30+ minutes into it: dailyIdx = today
    ///      and the cohort's tickets certified (slot 0 bits 24..47 and bit 192, golden layout), the
    ///      scheduled Craps table quiet. Its read consumers (boxes, then bets) are then the engine's
    ///      only work (60d31f775 consumer order); `advanceDue()` now reports any engine work, so the
    ///      settled precondition is the next selected action.
    function _openSweepFor(uint48 idx) internal {
        assertEq(RecyclingState.readBuffer(address(game)), idx, "the cohort was delivered at idx");
        uint256 elapsed = (vm.getBlockTimestamp() - 82620) % 1 days;
        if (elapsed < 30 minutes) vm.warp(vm.getBlockTimestamp() + 30 minutes - elapsed);
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        _quietCrapsTable();
        uint8 next = game.nextMinerAction();
        assertTrue(
            next == uint8(DegenerusGameStorage.MinerAction.HumanBoxes)
                || next == uint8(DegenerusGameStorage.MinerAction.Degenerette),
            "advance settled"
        );
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 35).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        RecyclingState.seedWord(address(game), uint48(index), bytes32(rngWord));
    }

    /// @dev The REAL spin-0 result ticket for (index, word), matching _resolveBet:
    ///      packedTraitsDegenerette(keccak256(abi.encodePacked(word, uint32(index), 'Q'))).
    function _resultTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        uint256 resultSeed = uint256(
            keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT))
        );
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev A customTraits that matches the result in ZERO quadrants (color AND symbol both differ in
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

    /// @dev The MinerWork(caller, firstAction, executionGas, flipReward) of a single mineFlip.
    function _minerWork(Vm.Log[] memory logs) internal view returns (uint8 first, uint256 measured, uint256 reward) {
        uint256 seen;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 0 && logs[i].topics[0] == MINER_WORK_SIG) {
                (first, measured, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++seen;
            }
        }
        assertEq(seen, 1, "one MinerWork per mineFlip");
    }

    /// @dev The miner clock: the later of the last accepted callback (lootboxRngPacked low 48 bits)
    ///      and the current day reset.
    function _rewardDueAt() internal view returns (uint256 due) {
        due = uint48(uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))));
        uint256 ts = vm.getBlockTimestamp();
        uint256 reset = ts - (ts - 82_620) % 1 days;
        if (reset > due) due = reset;
    }

    /// @dev Coinflip stake lanes hold whole FLIP: a credit floors to the whole FLIP it lands as.
    function _whole(uint256 amount) internal pure returns (uint256) {
        return (amount / 1 ether) * 1 ether;
    }

    /// @dev Mirror of the miner pay for `measured` gas at the current base fee and clock.
    function _expectedPay(uint256 measured, bool pass, bool locked) internal view returns (uint256) {
        if (measured <= MineFlipGas.MIN_REWARDED_GAS) return 0;
        uint256 ts = vm.getBlockTimestamp();
        uint256 due = _rewardDueAt();
        uint256 steps = (ts > due ? ts - due : 0) / 30 minutes;
        if (steps > 4) steps = 4;
        uint256 cap = INITIAL_REWARD_BASEFEE_CAP << steps;
        uint256 bps = 3_000 + 4_500 * steps;
        if (pass) bps <<= 1;
        if (locked) bps <<= 1;
        uint256 rate = block.basefee < cap ? block.basefee : cap;
        uint256 raw = (measured - MineFlipGas.MIN_REWARDED_GAS) * rate * PRICE_COIN_UNIT * bps / (game.mintPrice() * 10_000);
        // Whole-FLIP normalization at the payment site: 0 stays 0, positive sub-FLIP pays 1 FLIP.
        if (raw == 0) return 0;
        return raw < 1 ether ? 1 ether : _whole(raw);
    }

    /// @dev Settle the game to a clean state (advance not due, not rng-locked) — the open leg's `else` arm
    ///      precondition. (PATTERNS §"Settle-to-clean-state VRF drain".)
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip();
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
    ///      survive any level crossing), run a new-day STAGE to stamp them, then settle so mineFlip's
    ///      `else` open arm is reachable (advance not due). Returns the subs + the stamp day.
    function _stampKAfkingBoxes(uint256 k, uint256 salt) internal returns (address[] memory subs, uint32 stampDay) {
        subs = new address[](k);
        for (uint256 i; i < k; ++i) {
            address w = makeAddr(string(abi.encodePacked("afkbox_", vm.toString(salt), "_", vm.toString(i))));
            subs[i] = w;
            _grantDeityPass(w);
            vm.prank(w);
            game.subscribe(address(0), false, false, 1, address(0)); // self, lootbox mode, qty 1
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
            game.subscribe(address(0), false, false, 1, address(0)); // self, lootbox mode, qty 1
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

    /// @dev Read `who`'s lastAutoBoughtDay (_subOf slot 52, uint24 bytes 11..13) — the buy non-vacuity oracle.
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
