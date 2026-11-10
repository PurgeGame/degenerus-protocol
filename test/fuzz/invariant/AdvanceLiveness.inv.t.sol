// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {AdvanceLivenessHandler} from "../handlers/AdvanceLivenessHandler.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @dev Self-check double for the backlog ranking: forwards everything to the production code, but
///      after a mineRun that lowered one wallet's level-10 read lane, writes the pre-call word back.
contract StalledDrainGame {
    address private immutable impl;
    bytes32 private immutable lane;

    constructor(address impl_, bytes32 lane_) {
        impl = impl_;
        lane = lane_;
    }

    fallback() external payable {
        bool mine = msg.sig == bytes4(keccak256("mineRun(uint32)"));
        bytes32 slot = lane;
        uint256 prior;
        assembly ("memory-safe") { prior := sload(slot) }
        (bool ok, bytes memory ret) = impl.delegatecall(msg.data);
        if (mine && ok) {
            uint256 next;
            assembly ("memory-safe") { next := sload(slot) }
            if (uint32(next >> 50) < uint32(prior >> 50)) assembly ("memory-safe") { sstore(slot, prior) }
        }
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        assembly ("memory-safe") { return(add(ret, 32), mload(ret)) }
    }
}

/// @dev Self-check double for a late stall: as StalledDrainGame, but the first `honest` mineRuns
///      that lower the lane keep their progress (counted in a scratch slot of the Game's storage);
///      only later ones are put back, so the drain stalls with most of its tail already worked.
contract LateStalledDrainGame {
    bytes32 private constant COUNT = keccak256("late-stall double: lowering calls");
    address private immutable impl;
    bytes32 private immutable lane;
    uint256 private immutable honest;

    constructor(address impl_, bytes32 lane_, uint256 honest_) {
        impl = impl_;
        lane = lane_;
        honest = honest_;
    }

    fallback() external payable {
        bool mine = msg.sig == bytes4(keccak256("mineRun(uint32)"));
        bytes32 slot = lane;
        uint256 prior;
        assembly ("memory-safe") { prior := sload(slot) }
        (bool ok, bytes memory ret) = impl.delegatecall(msg.data);
        if (mine && ok) {
            uint256 next;
            assembly ("memory-safe") { next := sload(slot) }
            if (uint32(next >> 50) < uint32(prior >> 50)) {
                bytes32 c = COUNT;
                uint256 n;
                assembly ("memory-safe") {
                    n := add(sload(c), 1)
                    sstore(c, n)
                }
                if (n > honest) assembly ("memory-safe") { sstore(slot, prior) }
            }
        }
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        assembly ("memory-safe") { return(add(ret, 32), mload(ret)) }
    }
}

/// @dev Oracle self-test stand-in: `mineRun` latches `gameOver` with no ending due; every other
///      call runs the production Game code in the Game's own storage.
contract PrematureLatcher {
    address internal immutable production;

    constructor(address production_) {
        production = production_;
    }

    fallback() external payable {
        if (msg.sig == bytes4(keccak256("mineRun(uint32)"))) {
            assembly ("memory-safe") { sstore(0, or(sload(0), shl(168, 1))) }
            return;
        }
        (bool ok, bytes memory ret) = production.delegatecall(msg.data);
        assembly ("memory-safe") {
            if iszero(ok) { revert(add(ret, 32), mload(ret)) }
            return(add(ret, 32), mload(ret))
        }
    }
}

/// @title AdvanceLiveness — no "flag set, no work, every entry point reverts" state.
///
/// @notice From ANY fuzzed state, with VRF cooperating and without moving time, mineFlip
///         calls capped at 15M execution gas, each writing engine state, within a per-daily-cycle
///         call budget and at most two logical-day moves, must reach a sealed, idle day: terminal revert
///         NoWork (the engine idle signal), today's word recorded, rng unlocked, the mid-day latch clear, nothing
///         staged without a worker (ticketsFullyProcessed), advanceDue() consistent, and a
///         mid-day lootbox request not blocked by MidDayActive. A CRAPS-table probe request
///         (exempt from the pending-value gates) plus fulfil + cranks must return to the same
///         idle state, and every Kth step the next day must seal. See AdvanceLivenessHandler.
contract AdvanceLiveness is DeployProtocol {
    AdvanceLivenessHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 100_000 ether);
        // Native floor for mid-day / craps requests (admin ctor creates subId 1)
        mockVRF.fundSubscription(1, 1_000_000 ether);

        handler = new AdvanceLivenessHandler(game, mockVRF, 16);
        targetContract(address(handler));

        bytes4[] memory sels = new bytes4[](16);
        sels[0] = AdvanceLivenessHandler.actBuyTickets.selector;
        sels[1] = AdvanceLivenessHandler.actBuyLootbox.selector;
        sels[2] = AdvanceLivenessHandler.actFoil.selector;
        sels[3] = AdvanceLivenessHandler.actWhalePass.selector;
        sels[4] = AdvanceLivenessHandler.actOpenBoxes.selector;
        sels[5] = AdvanceLivenessHandler.actMiddayRequest.selector;
        sels[6] = AdvanceLivenessHandler.actFulfill.selector;
        sels[7] = AdvanceLivenessHandler.actCrank.selector;
        sels[8] = AdvanceLivenessHandler.actRunToIdle.selector;
        sels[9] = AdvanceLivenessHandler.actWarpWithinDay.selector;
        sels[10] = AdvanceLivenessHandler.actNextDay.selector;
        sels[11] = AdvanceLivenessHandler.actStall.selector;
        sels[12] = AdvanceLivenessHandler.actSeedPool.selector;
        // LIVE_NO_BIAS=true drops the biased compound so only the generic actions + probe run.
        sels[13] = vm.envOr("LIVE_NO_BIAS", false)
            ? AdvanceLivenessHandler.actSeedPool.selector
            : AdvanceLivenessHandler.actLastPurchaseDayMidday.selector;
        // extra weight on the day driver and the mid-day request
        sels[14] = AdvanceLivenessHandler.actNextDay.selector;
        sels[15] = AdvanceLivenessHandler.actMiddayRequest.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sels}));
    }

    /// Keep the quick default campaign: each step runs a snapshot-isolated liveness check
    /// (a few hundred bounded cranks plus a craps-probe cycle), so 64 x 100 already takes minutes.
    /// Inline default settings override the inherited deep profile too; explicitly restore
    /// deep's full 1000 x 256 campaign here and verify the executed run/call totals.
    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    /// forge-config: deep.invariant.runs = 1000
    /// forge-config: deep.invariant.depth = 256
    /// CI uses twenty distinct seeds; each process still crosses every coverage threshold.
    /// forge-config: deep_advance_ci.invariant.runs = 50
    /// forge-config: deep_advance_ci.invariant.depth = 256
    function invariant_advanceLiveness() public view {
        if (handler.ghost_violations() == 0) return;
        AdvanceLivenessHandler.Violation memory v = handler.firstViolation();
        _logViolation(v);
        revert(string.concat("LIVENESS violation code ", vm.toString(uint256(v.code))));
    }

    /// Per-run coverage, accumulated across runs through the process environment
    /// (the only state that survives the per-run setUp).
    function afterInvariant() public {
        string[27] memory keys = [
            "checks",
            "nextDayChecks",
            "probeRequests",
            "probeOnLpd",
            "probeOnLpdFrozenPool",
            "lpdSeals",
            "turboSeals",
            "normalSeals",
            "levelTransitions",
            "x9Levels",
            "x0Levels",
            "maxLevel",
            "middayRequests",
            "middayLatchSet",
            "middayLatchOnLpd",
            "middayLatchOnLpdFrozenPool",
            "vrfStalls",
            "vrfStallsDaily",
            "vrfStallsMidday",
            "foilBuys",
            "foilPendingMidday",
            "biasedReachedLpd",
            "gameOverRuns",
            "runs",
            "backlogCompressions",
            "lootboxBuys",
            "crankOnLpdFrozenPool"
        ];
        uint256[27] memory vals = [
            handler.ghost_checks(),
            handler.ghost_nextDayChecks(),
            handler.ghost_probeRequests(),
            handler.ghost_probeOnLpd(),
            handler.ghost_probeOnLpdFrozenPool(),
            handler.ghost_lpdSeals(),
            handler.ghost_turboSeals(),
            handler.ghost_normalSeals(),
            handler.ghost_levelTransitions(),
            handler.ghost_x9Levels(),
            handler.ghost_x0Levels(),
            handler.ghost_maxLevel(),
            handler.ghost_middayRequests(),
            handler.ghost_middayLatchSet(),
            handler.ghost_middayLatchOnLpd(),
            handler.ghost_middayLatchOnLpdFrozenPool(),
            handler.ghost_vrfStalls(),
            handler.ghost_vrfStallsDaily(),
            handler.ghost_vrfStallsMidday(),
            handler.ghost_foilBuys(),
            handler.ghost_foilPendingMidday(),
            handler.ghost_biasedReachedLpd(),
            game.gameOver() ? 1 : 0,
            1,
            handler.ghost_backlogCompressions(),
            handler.ghost_lootboxBuys(),
            handler.ghost_crankOnLpdFrozenPool()
        ];
        string memory line = "LIVENESS_COVERAGE";
        for (uint256 i = 0; i < 27; i++) {
            string memory k = string.concat("LIVE_COV_", keys[i]);
            uint256 acc = vm.envOr(k, uint256(0));
            // maxLevel is a max, everything else a sum
            acc = i == 11 ? (vals[i] > acc ? vals[i] : acc) : acc + vals[i];
            vm.setEnv(k, vm.toString(acc));
            line = string.concat(line, " ", keys[i], "=", vm.toString(acc));
        }
        console.log(line);
        string memory run = string.concat(
            "LIVENESS_RUN maxCranks=",
            vm.toString(handler.ghost_maxCranks()),
            " actions=",
            vm.toString(handler.ghost_actions()),
            " maxLevel=",
            vm.toString(handler.ghost_maxLevel()),
            " backlogCompressions=",
            vm.toString(handler.ghost_backlogCompressions()),
            " backlogMaxOwed=",
            vm.toString(handler.ghost_backlogMaxOwed()),
            " lootboxBuys=",
            vm.toString(handler.ghost_lootboxBuys()),
            " justifiedEndings=",
            vm.toString(handler.ghost_justifiedEndings())
        );
        console.log(run);
        if (handler.ghost_violations() != 0) _logViolation(handler.firstViolation());

        // Non-vacuity. Coverage is accumulated (above) because one run can legitimately miss a shape.
        // Measured over 65 default-profile runs (accumulated totals, seed 0xdeadbeef): checks 8,125,
        // next-day checks 1,625, probe requests 7,457, probe on a last purchase day 226, lpd seals 204
        // (turbo 110, normal 94), level transitions 1,067, x9 levels 78, x0 levels 45, mid-day requests
        // 322 (latch set 159, on a last purchase day 132), VRF stalls 117 (daily 42, mid-day 75), foil
        // buys 401 (pending at mid-day 282), biased compound reaching the last purchase day 215, checks
        // whose cranking drained a frozen pool on a last purchase day 381 (273 under a second seed).
        // A late day arms its elapsed Craps windows, and their mid-day request freezes and drains the
        // next-level pool inside that cranking, before the donor probe or a handler request can: probe
        // with a frozen pool and middayLatchOnLpdFrozenPool read 0 here and are logged, not required.
        // Shapes seen at >= 1 per run are required from 16 runs; the rarer ones (x0 levels, a frozen
        // pool drained while cranking, daily stalls) from 48 runs.
        uint256 runs = vm.envOr("LIVE_COV_runs", uint256(0));
        if (runs < 16) return;
        string[16] memory common = [
            "checks", "nextDayChecks", "probeRequests", "probeOnLpd", "lpdSeals", "turboSeals", "normalSeals",
            "levelTransitions", "x9Levels", "middayRequests", "middayLatchSet", "middayLatchOnLpd", "vrfStallsMidday",
            "foilBuys", "biasedReachedLpd", "lootboxBuys"
        ];
        for (uint256 i; i < common.length; ++i) {
            assertGt(vm.envOr(string.concat("LIVE_COV_", common[i]), uint256(0)), 0,
                string.concat("vacuous: liveness coverage never reached ", common[i]));
        }
        assertGt(vm.envOr("LIVE_COV_foilPendingMidday", uint256(0)), 0, "vacuous: liveness coverage never reached foilPendingMidday");
        if (runs < 48) return;
        string[3] memory rare = ["x0Levels", "crankOnLpdFrozenPool", "vrfStallsDaily"];
        for (uint256 i; i < rare.length; ++i) {
            assertGt(vm.envOr(string.concat("LIVE_COV_", rare[i]), uint256(0)), 0,
                string.concat("vacuous: liveness coverage never reached ", rare[i]));
        }
    }

    /// The liveness probe must actually request and finish a mid-day cycle.
    function test_donorProbeRequestsMidday() public {
        handler.actRunToIdle(0);
        assertEq(handler.ghost_violations(), 0, "liveness violation in donor probe");
        assertGt(handler.ghost_probeRequests(), 0, "donor probe must issue a request");
    }

    /// @dev The unshrunk 20-action campaign counterexample (the shrinker's one-call version did
    ///      not reproduce). Its next-day check works through two daily cycles, which the former
    ///      flat 250-call cutoff (one direct coin-ticket round per call, 280 calls) misread as
    ///      nontermination. Typed calls make any handler revert fail the replay instead of
    ///      passing silently.
    function test_BackloggedTicketJackpotStillReachesIdle() public {
        AdvanceLivenessHandler h = handler;
        h.actFulfill();
        h.actFulfill();
        h.actBuyTickets(987973558385376108849394590885168956720493512112609995, 1935583008242558388719462530735388318471);
        h.actMiddayRequest(9970, 900);
        h.actSeedPool(1874555648000875330519283469014130688475938277111934308827207);
        h.actMiddayRequest(30796461393168801175815566740, 340949541655144437384211277808400785192);
        h.actNextDay(41299094766155748286151641988568637358933361195574772186612623152482089, 2625);
        h.actFulfill();
        h.actLastPurchaseDayMidday(838577680921497);
        h.actWhalePass(2931);
        h.actNextDay(59, 100000);
        h.actFulfill();
        h.actNextDay(12760, 70288520262548602561809328627061950964226901219486286149240540285536414457052);
        h.actBuyTickets(238820929411270246290542585567, 1031759998269520168895688991388934435654640608096489774789269293622877549);
        h.actStall(73274681686168728259960734043533118148390246983530491227646187673309033888016);
        h.actWarpWithinDay(73274681686168728259960734043533118148390246983530491227646187673309033815728);
        h.actStall(1329828);
        h.actCrank(7249676749272314, 2656675073431816517);
        h.actFulfill();
        h.actFulfill();
        if (h.ghost_violations() != 0) _logViolation(h.firstViolation());
        assertEq(h.ghost_violations(), 0, "backlogged jackpot must reach idle");
        assertEq(h.ghost_actions(), 20, "every replayed action ran");
        assertEq(h.ghost_nextDayChecks(), 5, "every fourth action ran its next-day check");
        assertEq(h.ghost_maxDayAdvances(), 1, "non-vacuity: that check spanned two daily cycles");
        assertLe(h.ghost_maxCranksPerCycle(), h.MAX_CRANKS_PER_CYCLE());
        console.log("backlog max cranks", h.ghost_maxCranks());
        console.log("backlog max cranks per cycle", h.ghost_maxCranksPerCycle());
    }

    /// @dev Replayed from a persisted 34-call deep-campaign failure. During the final check a
    ///      human-box crank opens sDGNRS's boxes; one Degenerette box spin pays about 274,645 ETH,
    ///      the 10% pool cap leaves 1,449 ETH as ETH and converts the rest to a lootbox, and that
    ///      box queues 57,599,640 entries for sDGNRS at level 10. Every Tickets call then drains
    ///      about 4,770 of them (~12,100 calls in all), which the flat per-cycle budget misread as
    ///      nontermination. The ranked window must prove the drain, compress it, and still reach
    ///      a sealed, idle day.
    function test_DegeneretteJackpotBacklogStillReachesIdle() public {
        AdvanceLivenessHandler h = handler;
        _jackpotBacklogPrefix(h);
        h.actWhalePass(4570);
        if (h.ghost_violations() != 0) _logViolation(h.firstViolation());
        assertEq(h.ghost_violations(), 0, "ranked jackpot backlog must reach idle");
        assertEq(h.ghost_actions(), 34, "every replayed action ran");
        assertGe(h.ghost_backlogCompressions(), 1, "non-vacuity: the ranked window compressed the backlog");
        assertGt(h.ghost_backlogMaxOwed(), 50_000_000, "non-vacuity: the compressed queue held the jackpot's entries");
        console.log("jackpot backlog compressions", h.ghost_backlogCompressions());
        console.log("jackpot backlog max owed entries", h.ghost_backlogMaxOwed());
        console.log("jackpot backlog max cranks", h.ghost_maxCranks());
    }

    /// @dev Replayed from a persisted 72-call deep-campaign failure. In the final check a human-box
    ///      crank queues about 2.7M owed entries on the far-future lane two levels up (five
    ///      holders), and about 560 Tickets calls drain it, past the flat per-cycle budget. The
    ///      ranked window opens at the budget and the queue empties inside it, so the drain is
    ///      proven without compression.
    function test_FarFutureBacklogDrainsInsideTheWindow() public {
        AdvanceLivenessHandler h = handler;
        _farFutureBacklogSequence(h);
        if (h.ghost_violations() != 0) _logViolation(h.firstViolation());
        assertEq(h.ghost_violations(), 0, "far-future backlog must reach idle");
        assertEq(h.ghost_actions(), 72, "every replayed action ran");
        assertEq(h.ghost_backlogCompressions(), 0, "the queue drained inside the window");
        assertGe(h.ghost_maxCranks(), 600, "non-vacuity: the drain ran past the flat budget");
        console.log("far-future backlog max cranks", h.ghost_maxCranks());
    }

    function _farFutureBacklogSequence(AdvanceLivenessHandler h) internal {
        h.actLastPurchaseDayMidday(274);
        h.actOpenBoxes(170920198);
        h.actNextDay(7461, 1182342661);
        h.actStall(135487606500527586351396372573970);
        h.actWhalePass(0);
        h.actNextDay(25152830347282153503188519620118582881988189301823, 807994665343541085186688395858116735451107686371994668632633347684632836);
        h.actFoil(1);
        h.actStall(271015127546492286);
        h.actMiddayRequest(10530, 15843);
        h.actMiddayRequest(16383, 51008);
        h.actWarpWithinDay(29585757801757273);
        h.actMiddayRequest(9891, 40000);
        h.actNextDay(195385690415954796681348944496431052, 300247704870238078677354724831087287);
        h.actWarpWithinDay(20767640357497770256279353060187481269882393874846213356981);
        h.actMiddayRequest(609546087, 11525759209690640403245518757014742738608);
        h.actOpenBoxes(299);
        h.actSeedPool(121694457631354755510522309771267);
        h.actRunToIdle(7067244);
        h.actCrank(21392, 4200);
        h.actNextDay(151, 6471);
        h.actMiddayRequest(18354, 64);
        h.actNextDay(1592938749427352, 10193259210801627536606023519637210985769338823634901);
        h.actFulfill();
        h.actWarpWithinDay(64408888034188890720070650829666195471956032333875740335693);
        h.actSeedPool(197);
        h.actWhalePass(115792089237316195423570985008687907853269984665640564039457584007913129639934);
        h.actCrank(40000, 10000000000000000);
        h.actWhalePass(1334);
        h.actOpenBoxes(75376775);
        h.actFoil(8529708965949716113068400558660783296355391638931501);
        h.actSeedPool(69130708002671459875891056038483667730483996010888719835580737139095618);
        h.actFulfill();
        h.actNextDay(695529900000000000000000, 7000);
        h.actSeedPool(33675099802033142722284742171626861);
        h.actNextDay(4033, 127);
        h.actMiddayRequest(142573, 431029027849377293009099935400);
        h.actNextDay(271, 1670);
        h.actBuyTickets(540582017019437939590336746323671769881342, 749163715548394569311016492773352054539982728864150183338766563850192230);
        h.actSeedPool(72370055827242515480310246955150653346168791186507307785844490411625550981024);
        h.actFoil(17101159876);
        h.actMiddayRequest(230450, 18472);
        h.actSeedPool(2300000);
        h.actWarpWithinDay(2425861200000000000);
        h.actStall(925248084803030739962363);
        h.actWarpWithinDay(73274681551368994924207535070198042713292093615344769114943325267790982571728);
        h.actFulfill();
        h.actCrank(144, 21283);
        h.actNextDay(33, 15574);
        h.actWarpWithinDay(198706581);
        h.actMiddayRequest(1048275337840070235943100006270253348235546146472015940475531694073093297336, 49632);
        h.actCrank(136, 220);
        h.actFoil(296559413407705156846667172373792659201822231808113863242551897620482);
        h.actFoil(2400000);
        h.actFulfill();
        h.actOpenBoxes(33786);
        h.actNextDay(18734, 72370055827242515480310246955150653346168791186507307785844490411625550990688);
        h.actBuyTickets(1, 252172160071787583100405538257);
        h.actOpenBoxes(594730600550082);
        h.actNextDay(15889, 17499);
        h.actNextDay(30, 2203);
        h.actFulfill();
        h.actCrank(99767263412294512300870728527097100384088503632307663483594949343659103765790, 40397545929600181636417047310492680856735821878925485025261764560649566326334);
        h.actFulfill();
        h.actFoil(19472803273692390626381003004625429934);
        h.actMiddayRequest(450400, 21388);
        h.actStall(72370055827242515474033145219763972582333001763299641369742134967161516481472);
        h.actMiddayRequest(1000000000, 279);
        h.actRunToIdle(31566534335);
        h.actMiddayRequest(40605464961392864732564, 2741784328782609243352012543);
        h.actFulfill();
        h.actFulfill();
        h.actNextDay(535705892984595775627082949891588200867428984749124026489312514865, 43510324585678702396257909749461766590921469660499526204881869305016456411);
    }

    /// @dev The first 33 actions of that sequence; its 34th (actWhalePass(4570)) runs the
    ///      check that meets the jackpot backlog.
    function _jackpotBacklogPrefix(AdvanceLivenessHandler h) internal {
        h.actSeedPool(1322);
        h.actWhalePass(491097668805913737166441422320207150778401246708159625892686045777185076);
        h.actFoil(9941);
        h.actCrank(1655260984718715425435, 1479213843194745850558504502893737106795);
        h.actMiddayRequest(11242815, 73274681551368994924207535070198042713292093615344769114943325267790982566672);
        h.actWhalePass(176404421621618529934044969842097160113943218);
        h.actNextDay(60924590352216425073238997996751312033674802929955, 206168849288354654415779);
        h.actBuyTickets(16604207830365491876213400846227384836999803595354511760697079131146673586163, 20000);
        h.actBuyTickets(26508109422230358590066026783865593567, 152442866293369741439262463789663257539770822457738252527343218146715654);
        h.actStall(17868);
        h.actSeedPool(363999);
        h.actBuyTickets(15360, 4000000000000000000);
        h.actMiddayRequest(1575718623160900586, 56068530670415006546437936714509210445628705336155484719832337508);
        h.actMiddayRequest(875819144, 84577192631695642232076651949857587631);
        h.actNextDay(154492951, 6787364146);
        h.actFoil(9375);
        h.actWhalePass(220521399483054597444270403749570237183);
        h.actRunToIdle(9749);
        h.actBuyTickets(51201562599859365977474564423688, 92338176);
        h.actLastPurchaseDayMidday(73274681578328941591358174864865057800311724288981913537483897748894592827664);
        h.actSeedPool(13506512847431197627377327090963309);
        h.actFulfill();
        h.actMiddayRequest(455638151205566443242641212496764951782317509806921322, 434986180889105379627522348739026594153658531625299);
        h.actStall(4689366805399555359566614494964251575282446);
        h.actStall(382969925940);
        h.actStall(1057393236136550042428361090712810826039454179298451523752660804727940);
        h.actWarpWithinDay(77318076419392289299902264530);
        h.actWarpWithinDay(30088724374045935260142156206433004870839028484991476196186345887703051508107);
        h.actMiddayRequest(3162753877957340906046201827136843102484899215157352315337502331, 325734073256572);
        h.actBuyTickets(104265765657418059170669937121245398121528523680836293485708500746458423056128, 23688);
        h.actNextDay(10095346766061645851, 72822368675825781893791978056887563541563784756938131903533043377012599702064);
        h.actMiddayRequest(4000000000000000000, 73274681659208781592810094248866103061370616309893346805105615192205423574880);
        h.actFulfill();
    }

    /// @dev Oracle self-check: the same backlog, with every call that lowers sDGNRS's level-10
    ///      read lane put back afterwards (each call still writes, so the no-progress check stays
    ///      quiet). The ranked window must reject its first call instead of compressing.
    function test_OracleFlagsStalledBacklogDrain() public {
        AdvanceLivenessHandler h = handler;
        _jackpotBacklogPrefix(h);
        address impl = address(uint160(0x5A11ED));
        vm.etch(impl, address(game).code);
        bytes32 lane = keccak256(abi.encode(uint256(2), GameSlots.TICKET_PENDING));
        vm.etch(address(game), address(new StalledDrainGame(impl, lane)).code);
        h.actWhalePass(4570);
        assertEq(h.ghost_violations(), 1, "a drain that never lowers owed must be flagged");
        assertEq(h.firstViolation().code, h.V_NO_QUIESCENCE());
        // The day moves on the check's first call, so the cycle budget trips at call 502 and the
        // window's first call, which must be rejected, is call 503.
        assertEq(h.firstViolation().cranks, h.MAX_CRANKS_PER_CYCLE() + 3, "rejected on the window's first call");
        assertEq(h.ghost_backlogCompressions(), 0);
    }

    /// @dev The full replays drain a recorded backlog without the cut (about 25,900 calls and 345B
    ///      gas), which needs the deep profile's gas limit; the default profile skips them.
    function _deepOnly() internal {
        vm.skip(keccak256(bytes(vm.envOr("FOUNDRY_PROFILE", string("")))) != keccak256("deep"),
            "full backlog drains run under the deep profile");
    }

    function _etchLateStall(uint256 honest) internal {
        address impl = address(uint160(0x5A11ED));
        vm.etch(impl, address(game).code);
        bytes32 lane = keccak256(abi.encode(uint256(2), GameSlots.TICKET_PENDING));
        vm.etch(address(game), address(new LateStalledDrainGame(impl, lane, honest)).code);
    }

    /// @dev The jackpot backlog replayed without the cut: every one of its ~57.6M entries is drained
    ///      by real Tickets calls, each strictly lowering the owed total, and the day still seals idle.
    function test_DegeneretteJackpotBacklogDrainsInFull() public {
        _deepOnly();
        AdvanceLivenessHandler h = handler;
        h.setFullBacklogDrain(true);
        _jackpotBacklogPrefix(h);
        h.actWhalePass(4570);
        if (h.ghost_violations() != 0) _logViolation(h.firstViolation());
        assertEq(h.ghost_violations(), 0, "the uncut jackpot backlog must drain and reach idle");
        assertEq(h.ghost_actions(), 34, "every replayed action ran");
        assertEq(h.ghost_backlogCompressions(), 0, "nothing was cut");
        assertGt(h.ghost_backlogRenewals(), 100, "non-vacuity: the ranking held over the whole drain");
        assertGt(h.ghost_backlogMaxOwed(), 50_000_000, "non-vacuity: the queue held the jackpot's entries");
        assertGt(h.ghost_maxCranks(), 12_000, "non-vacuity: every call of the tail ran");
        console.log("full drain renewals", h.ghost_backlogRenewals());
        console.log("full drain max cranks", h.ghost_maxCranks());
    }

    /// @dev Oracle self-check for the full drain: the same backlog, honest for its first
    ///      LATE_STALL_AFTER lowering calls (about 90% of the queue), then stalled. The full replay
    ///      must reject the first stalled call.
    function test_OracleFlagsLateStallInAFullDrain() public {
        _deepOnly();
        AdvanceLivenessHandler h = handler;
        h.setFullBacklogDrain(true);
        _jackpotBacklogPrefix(h);
        _etchLateStall(LATE_STALL_AFTER);
        h.actWhalePass(4570);
        assertEq(h.ghost_violations(), 1, "a drain that stalls late must be flagged");
        assertEq(h.firstViolation().code, h.V_NO_QUIESCENCE());
        assertGt(h.firstViolation().cranks, LATE_STALL_AFTER, "flagged late in the drain");
        assertEq(h.ghost_backlogCompressions(), 0);
    }

    /// @dev Why the full replays exist: with the cut, the campaign check finishes a smaller
    ///      workload and never reaches that stall.
    function test_CutDrainNeverReachesALateStall() public {
        AdvanceLivenessHandler h = handler;
        _jackpotBacklogPrefix(h);
        _etchLateStall(LATE_STALL_AFTER);
        h.actWhalePass(4570);
        assertEq(h.ghost_violations(), 0, "the cut drain ends before the stall");
        assertGe(h.ghost_backlogCompressions(), 1);
    }

    /// @dev About 90% of the full drain's ~25,300 lowering calls.
    uint256 private constant LATE_STALL_AFTER = 23_000;

    /// @dev Oracle self-check: if entriesOwedView disagrees with the raw lanes the compression
    ///      reads, the check fails with its own code rather than writing.
    function test_OracleFlagsUnverifiedBacklogWrite() public {
        AdvanceLivenessHandler h = handler;
        _jackpotBacklogPrefix(h);
        vm.mockCall(address(game), abi.encodeWithSelector(game.entriesOwedView.selector), abi.encode(uint32(7)));
        h.actWhalePass(4570);
        assertEq(h.ghost_violations(), 1, "an unverifiable compression must be flagged");
        assertEq(h.firstViolation().code, h.V_BACKLOG_UNVERIFIED());
        assertEq(h.firstViolation().cranks, h.MAX_CRANKS_PER_CYCLE() + 2 + h.BACKLOG_WINDOW(), "flagged at the compression");
    }

    /// @dev Oracle self-check: a mineFlip that succeeds without writing engine state is flagged
    ///      at once rather than consuming the cycle budget.
    function test_OracleFlagsSuccessWithoutProgress() public {
        vm.mockCall(address(game), abi.encodeWithSignature("mineRun(uint32)", uint32(0)), "");
        handler.actFulfill();
        assertEq(handler.ghost_violations(), 1);
        assertEq(handler.firstViolation().code, handler.V_NO_PROGRESS());
        assertEq(handler.firstViolation().cranks, 1);
    }

    /// Deterministic replay of the biased scenario — a quick regression for the seed bug.
    function test_lastPurchaseDayMiddayScenario() public {
        for (uint256 s = 0; s < 6 && handler.ghost_violations() == 0; s++) {
            handler.actLastPurchaseDayMidday(uint256(keccak256(abi.encode("lpd-midday", s))) & ~uint256(1));
            handler.actNextDay(1 hours, 0);
            handler.actRunToIdle(0);
        }
        console.log("biasedReachedLpd", handler.ghost_biasedReachedLpd());
        console.log("middayLatchOnLpdFrozenPool", handler.ghost_middayLatchOnLpdFrozenPool());
        console.log("probeOnLpdFrozenPool", handler.ghost_probeOnLpdFrozenPool());
        if (handler.ghost_violations() != 0) _logViolation(handler.firstViolation());
        assertEq(handler.ghost_violations(), 0, "liveness violation in the biased scenario");
    }

    /// @dev Oracle self-check: a mining call that latches terminal state with no ending due is
    ///      flagged, through the same wrapper every handler mining call uses.
    function test_OracleFlagsPrematureEnding() public {
        handler.actRunToIdle(0);
        assertEq(handler.ghost_violations(), 0, "healthy idle first");
        bytes memory code = address(game).code;
        address impl = address(uint160(0xC0DE51));
        vm.etch(impl, code);
        vm.etch(address(game), address(new PrematureLatcher(impl)).code);
        handler.oracleProbeMine();
        vm.etch(address(game), code);
        assertEq(handler.ghost_violations(), 1, "premature latch flagged");
        assertEq(handler.firstViolation().code, handler.V_UNJUSTIFIED_ENDING());
    }

    /// @dev A real deadman ending (no certified day for 14 days) is justified, not flagged.
    function test_OracleAcceptsDeadmanEnding() public {
        handler.actRunToIdle(0);
        vm.warp(block.timestamp + 15 days);
        for (uint256 i; i < 50 && !game.gameOver(); ++i) handler.oracleProbeMine();
        assertTrue(game.gameOver(), "deadman ended the game");
        assertEq(handler.ghost_violations(), 0, "a due ending is not premature");
        assertEq(handler.ghost_justifiedEndings(), 1, "the latch was observed and justified");
    }

    /// @dev Oracle self-check: an idle, sealed day whose completion was never certified would
    ///      stop the deadman clock; the check reports it instead of calling the day sealed.
    function test_OracleFlagsUnstampedCompletion() public {
        handler.actRunToIdle(0);
        _clearDailyComplete();
        handler.actFulfill();
        assertEq(handler.ghost_violations(), 1, "uncertified idle day flagged");
        assertEq(handler.firstViolation().code, handler.V_COMPLETION_UNSTAMPED());
    }

    /// @dev Oracle self-check: with completion stuck the next wall day never requests; the
    ///      logical day (and its old word) would otherwise pass as sealed.
    function test_OracleFlagsDayNeverRequested() public {
        handler.actRunToIdle(0);
        _clearDailyComplete();
        vm.warp(_nextDayStart() + 1 hours);
        handler.actFulfill();
        assertEq(handler.ghost_violations(), 1, "unrequested wall day flagged");
        assertEq(handler.firstViolation().code, handler.V_DAY_NOT_REQUESTED());
    }

    function _clearDailyComplete() internal {
        bytes32 slot = bytes32(GameSlots.DAILY_COMPLETE);
        uint256 word = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(word & ~(uint256(0xFF) << (GameSlots.DAILY_COMPLETE_OFFSET * 8))));
    }

    function _nextDayStart() internal view returns (uint256) {
        uint256 ts = vm.getBlockTimestamp();
        return ts - ((ts - 82_620) % 1 days) + 1 days;
    }

    function _logViolation(AdvanceLivenessHandler.Violation memory v) internal pure {
        console.log("=== LIVENESS VIOLATION ===");
        console.log("code (1 noQuiesce,2 terminalRevert,3 latchStuck,4 notSealed,5 stagedNoWorker,6 advanceDueLies,7 requestBlocked,8 noProgress,9 backlogUnverified,10 unjustifiedEnding,11 dayNotRequested,12 completionUnstamped)", uint256(v.code));
        console.log("phase (0 same-day,1 after CRAPS probe,2 next-day,3 next-day+probe)", uint256(v.phase));
        console.logBytes4(v.selector);
        console.log("cranks", uint256(v.cranks));
        console.log("actionNo", uint256(v.actionNo));
        console.log("lastAction", v.lastAction);
        console.log("level", uint256(v.level));
        console.log("wallDay", uint256(v.wallDay));
        console.log("dailyIdx", uint256(v.dailyIdx));
        console.log("jackpotPhase", v.jackpotPhase);
        console.log("lastPurchaseDay", v.lastPurchaseDay);
        console.log("turbo", v.turbo);
        console.log("rngLocked", v.rngLocked);
        console.log("ticketsFullyProcessed", v.ticketsFullyProcessed);
        console.log("midDayLatch", uint256(v.midDayLatch));
        console.log("rngRequestTime", uint256(v.rngRequestTime));
        console.log("wordToday", uint256(v.wordToday));
        console.log("advanceDue", v.advanceDue);
        console.log("readLen L / L+1 / L+2", v.readLenL, v.readLenL1, v.readLenL2);
        console.log("farFuture len L+1 / L+2", v.ffLenL1, v.ffLenL2);
        console.log("foilPending", v.foilPending);
        console.log("timestamp", uint256(v.timestamp));
        console.log("lastDailyCompletedAt", v.lastCompletedAt);
        console.log("lastDailyRequestWallDay", uint256(v.lastRequestWallDay));
        console.log("dailyComplete", v.dailyComplete);
    }
}
