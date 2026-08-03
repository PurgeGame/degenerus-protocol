// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    DegenerusGameFoilPackModule
} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {
    DegenerusGameJackpotModule
} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {
    DegenerusGameStorage
} from "../../contracts/storage/DegenerusGameStorage.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title GoldenTicketFoilHarness -- drives the live drain and claim in the Game's context
/// @notice Extends the production DegenerusGameFoilPackModule so the inherited externals
///         `processFoilDrain` and `claimGoldenTicket` execute live in THIS contract's
///         storage. The harness is etched at ContractAddresses.GAME so the module's
///         delegatecall-only guard and the jackpot delegatecall both see
///         address(this) == GAME. Adds only storage seeders, read-only views, and two
///         passthroughs onto internals; overrides NO production logic.
/// @dev Test-only. NO contracts/*.sol logic is mutated; this harness lives under test/.
contract GoldenTicketFoilHarness is DegenerusGameFoilPackModule {
    function setFoilRecord(
        uint24 lvl,
        address buyer,
        uint16 multBps,
        uint24 resolveDay,
        uint16 score
    ) external {
        foilRecord[lvl][buyer] =
            uint256(resolveDay) |
            (uint256(multBps) << _FOIL_MULT_SHIFT) |
            (uint256(score) << _FOIL_SCORE_SHIFT);
    }

    function pushFoilBuyer(uint24 day, uint24 lvl, address buyer) external {
        foilBuyers[day].push((uint256(lvl) << 160) | uint256(uint160(buyer)));
    }

    function setRngWord(uint24 day, uint256 word) external {
        rngWordByDay[day] = word;
    }

    function setDrainWindow(uint24 drainDay, uint24 lastResolveDay) external {
        foilDrainDay = drainDay;
        foilLastResolveDay = lastResolveDay;
        foilCursor = 0;
    }

    function setPools(uint128 nextBal, uint128 futBal) external {
        _setPrizePools(nextBal, futBal);
    }

    function setCurrentPool(uint256 v) external {
        _setCurrentPrizePool(v);
    }

    function setYieldAcc(uint256 v) external {
        yieldAccumulator = v;
    }

    function setRngLocked(bool v) external {
        rngLockedFlag = v;
    }

    function setSnap(uint24 lvl, uint8 shift) external {
        snapLevel = lvl;
        snapPendingShift = shift;
    }

    function setLiveSnapShift(uint8 shift) external {
        snapShift = shift;
    }

    /// @dev The LIVE read the claim must not use — exposed so a test can prove it moved.
    function liveSnapShiftFor(uint24 lvl) external view returns (uint8) {
        return _snapShiftFor(lvl);
    }

    function setGoldenTicketRaw(uint256 v) external {
        goldenTicket = v;
    }

    function goldenTicketRaw() external view returns (uint256) {
        return goldenTicket;
    }

    /// @dev Drive one FLIP rung at a time. Every shape below is reachable in production,
    ///      but each needs its own brute-forced (buyer, entropy) vector to reach through
    ///      the live claim, so the rungs are exposed rather than each given a search.
    function settleGoldenTicket(
        address buyer,
        uint24 lvl,
        uint8 golds,
        uint8 allGold
    ) external {
        _settleGoldenTicket(buyer, lvl, golds, allGold);
    }

    /// @dev Drive the grand push directly — the branch the DRAIN takes when a pack's
    ///      lines come out holding two or more all-gold tickets. A pack reaches that
    ///      once in 7.1 billion, past any buyer/entropy search, so the push is exposed
    ///      rather than left unproven.
    function pushFoilGrand(
        address buyer,
        uint24 lvl,
        uint8 golds,
        uint8 allGold
    ) external {
        _pushFoilGrand(buyer, lvl, golds, allGold);
    }

    function goldenTicketClaimed(
        address buyer,
        uint24 lvl
    ) external view returns (bool) {
        return
            foilMatchClaimed[
                keccak256(
                    abi.encode(
                        buyer,
                        uint256(lvl),
                        keccak256("foil-golden-ticket")
                    )
                )
            ];
    }

    function packGold(
        uint32[4] memory lines
    ) external pure returns (uint8 golds, uint8 allGoldTickets) {
        return _packGold(lines);
    }

    function goldLadderFlip(uint8 golds) external pure returns (uint256) {
        return _goldLadderFlip(golds);
    }

    function traitEntryLen(uint24 lvl, uint8 traitId) external view returns (uint256) {
        return lvlTraitEntry[lvl][traitId].length;
    }

    function traitEntryAt(
        uint24 lvl,
        uint8 traitId,
        uint256 i
    ) external view returns (address) {
        return lvlTraitEntry[lvl][traitId][i];
    }

    function claimableOf(address who) external view returns (uint256) {
        return _claimableOf(who);
    }

    function whalePassOf(address who) external view returns (uint256) {
        return whalePassClaims[who];
    }

    function claimablePoolView() external view returns (uint256) {
        return uint256(claimablePool);
    }

    function poolsView() external view returns (uint128 nextBal, uint128 futBal) {
        (nextBal, futBal) = _getPrizePools();
    }

    function drainCursors() external view returns (uint24 dd, uint24 last, uint32 cur) {
        return (foilDrainDay, foilLastResolveDay, foilCursor);
    }
}

/// @dev Recorder etched at ContractAddresses.COINFLIP: captures creditFlip calls.
contract CoinflipRecorder {
    address public lastPlayer;
    uint256 public lastAmount;
    uint256 public calls;

    function creditFlip(address p, uint256 a) external {
        lastPlayer = p;
        lastAmount = a;
        ++calls;
    }

    fallback() external payable {
        assembly {
            mstore(0, 0)
            return(0, 32)
        }
    }
}

/// @dev Recorder etched at ContractAddresses.WWXRP: captures mintPrize calls.
contract WwxrpRecorder {
    address public lastTo;
    uint256 public lastAmount;
    uint256 public calls;

    function mintPrize(address to, uint256 a) external {
        lastTo = to;
        lastAmount = a;
        ++calls;
    }

    fallback() external payable {
        assembly {
            mstore(0, 0)
            return(0, 32)
        }
    }
}

/// @title GoldenTicketFoilPack -- the foil-pack route into the golden ticket
/// @notice Locks the second route:
///         - three or more golds anywhere in the pack's sixteen quadrants claim the
///           FLIP ladder (20k/80k/250k/750k/2.5M/7.5M for 3/4/5/6/7/8+)
///         - four golds landing inside ONE ticket add a 25,000 FLIP kicker
///         - TWO all-gold tickets claim the grand instead, off the jackpot module's
///           single definition (25% of futurePrizePool in ETH; the headline remainder
///           75% in half-passes / 25% in flip credit), with no FLIP on top
///         - the claim is permissionless, pays once, and is closed under three golds,
///           before the pack's word seals, and from the liveness trigger on
///         - the DRAIN pays nothing: the whole route is a pull, off the hot path
/// @dev The one-ticket case runs the LIVE drain and claim on a searched (buyer, entropy)
///      pair that really produces an all-gold line at the max boost, so the counting
///      logic is proven against the production trait producer rather than a mirror.
contract GoldenTicketFoilPack is Test {
    GoldenTicketFoilHarness internal h;
    CoinflipRecorder internal flipRec;
    WwxrpRecorder internal wwxrpRec;

    /// @dev Searched pair: at multBps 60000 (max boost) buyer BUYER's pack for level
    ///      LVL resolving against word ALL_GOLD_WORD derives line 0 as four gold
    ///      quadrants — traits [60, 127, 190, 251] — and lines 1-3 with none.
    address internal constant BUYER =
        address(0x00000000000000000000000000000000000000B0);
    uint24 internal constant LVL = 3;
    uint256 internal constant ALL_GOLD_WORD = 92194; // 4 golds, all in ticket 0
    uint256 internal constant NO_GOLD_WORD = 1; // 0 golds
    uint256 internal constant TWO_GOLD_WORD = 4; // 2 golds, under the floor
    uint256 internal constant THREE_GOLD_WORD = 19; // 3 golds, the floor rung
    uint256 internal constant FIVE_GOLD_WORD = 1595; // 5 golds, none aligned
    uint24 internal constant RESOLVE_DAY = 7;
    uint16 internal constant MAX_MULT = 60000;

    uint8 internal constant GOLD_A = 60;
    uint8 internal constant GOLD_B = 127;
    uint8 internal constant GOLD_C = 190;
    uint8 internal constant GOLD_D = 251;

    /// @dev The searched pack holds exactly four golds, all inside ticket 0 — so it
    ///      pays the ladder's 4-gold rung plus the single-all-gold-ticket kicker.
    uint8 internal constant PACK_GOLDS = 4;
    uint256 internal constant LADDER_4 = 80_000e18;
    uint256 internal constant KICKER = 25_000e18;
    uint256 internal constant EXPECTED_FLIP = LADDER_4 + KICKER;
    uint256 internal constant HALF_PASS_PRICE = 2.25 ether;
    uint256 internal constant COIN_UNIT = 1000 ether;

    function setUp() public {
        GoldenTicketFoilHarness impl = new GoldenTicketFoilHarness();
        vm.etch(ContractAddresses.GAME, address(impl).code);
        h = GoldenTicketFoilHarness(payable(ContractAddresses.GAME));

        // The grand delegatecalls the real jackpot module in the Game's context.
        DegenerusGameJackpotModule jm = new DegenerusGameJackpotModule();
        vm.etch(ContractAddresses.GAME_JACKPOT_MODULE, address(jm).code);

        CoinflipRecorder fr = new CoinflipRecorder();
        vm.etch(ContractAddresses.COINFLIP, address(fr).code);
        flipRec = CoinflipRecorder(payable(ContractAddresses.COINFLIP));

        WwxrpRecorder wr = new WwxrpRecorder();
        vm.etch(ContractAddresses.WWXRP, address(wr).code);
        wwxrpRec = WwxrpRecorder(payable(ContractAddresses.WWXRP));
    }

    /// @dev Seed BUYER's pack for RESOLVE_DAY against `word` and run the drain, so the
    ///      claim below sees exactly the state a real pack leaves behind.
    function seedAndDrain(uint256 word) internal {
        h.setFoilRecord(LVL, BUYER, MAX_MULT, RESOLVE_DAY, 0);
        h.pushFoilBuyer(RESOLVE_DAY, LVL, BUYER);
        h.setRngWord(RESOLVE_DAY, word);
        h.setDrainWindow(RESOLVE_DAY, RESOLVE_DAY);
        h.processFoilDrain(1000);
    }

    // -- the searched pair really is an all-gold ticket -----------------------

    /// @dev The drain files sixteen entries whatever the word; on ALL_GOLD_WORD four of
    ///      them are the all-gold line the claim keys on. The drain itself pays nothing
    ///      and calls nothing out — the whole route is a pull.
    function testDrainFilesEntriesAndPaysNothing() public {
        vm.recordLogs();
        seedAndDrain(ALL_GOLD_WORD);

        assertEq(h.traitEntryLen(LVL, GOLD_A), 1, "quadrant A gold entry filed");
        assertEq(h.traitEntryLen(LVL, GOLD_B), 1, "quadrant B gold entry filed");
        assertEq(h.traitEntryLen(LVL, GOLD_C), 1, "quadrant C gold entry filed");
        assertEq(h.traitEntryLen(LVL, GOLD_D), 1, "quadrant D gold entry filed");
        assertEq(h.traitEntryAt(LVL, GOLD_A, 0), BUYER, "entry owned by the buyer");

        uint256 total;
        for (uint256 t; t < 256; ++t) {
            total += h.traitEntryLen(LVL, uint8(t));
        }
        assertEq(total, 16, "the pack files exactly sixteen entries");

        assertEq(flipRec.calls(), 0, "the drain credits nothing");
        assertNoFoilEvent(vm.getRecordedLogs());
    }

    /// @dev The counter reads colors out of the packed lines, gold being color 7 in
    ///      bits 5-3 of each quadrant byte, and reports the total AND the all-gold
    ///      tickets — scattered gold counts for the ladder, aligned gold for the grand.
    function testPackGoldCountsTotalAndTickets() public view {
        uint32 goldLine = uint32(GOLD_A) |
            (uint32(GOLD_B) << 8) |
            (uint32(GOLD_C) << 16) |
            (uint32(GOLD_D) << 24);
        // Same line with quadrant D one colour below gold: three golds, no ticket.
        uint32 threeGold = uint32(GOLD_A) |
            (uint32(GOLD_B) << 8) |
            (uint32(GOLD_C) << 16) |
            (uint32(uint8(GOLD_D - 8)) << 24);
        uint32 noGold;

        (uint8 g, uint8 t) = h.packGold([goldLine, noGold, noGold, noGold]);
        assertEq(g, 4, "four golds"); assertEq(t, 1, "one all-gold ticket");

        (g, t) = h.packGold([goldLine, goldLine, noGold, noGold]);
        assertEq(g, 8, "eight golds"); assertEq(t, 2, "two all-gold tickets");

        (g, t) = h.packGold([goldLine, goldLine, goldLine, goldLine]);
        assertEq(g, 16, "sixteen golds"); assertEq(t, 4, "four all-gold tickets");

        // Scattered: three lines of three golds is nine golds and NO all-gold ticket.
        (g, t) = h.packGold([threeGold, threeGold, threeGold, noGold]);
        assertEq(g, 9, "nine scattered golds"); assertEq(t, 0, "no all-gold ticket");

        (g, t) = h.packGold([noGold, noGold, noGold, noGold]);
        assertEq(g, 0, "no gold"); assertEq(t, 0, "no all-gold ticket");
    }

    /// @dev The ladder's rungs, and that it caps at eight.
    function testGoldLadderRungs() public view {
        assertEq(h.goldLadderFlip(3), 20_000e18, "3 golds");
        assertEq(h.goldLadderFlip(4), 80_000e18, "4 golds");
        assertEq(h.goldLadderFlip(5), 250_000e18, "5 golds");
        assertEq(h.goldLadderFlip(6), 750_000e18, "6 golds");
        assertEq(h.goldLadderFlip(7), 2_500_000e18, "7 golds");
        assertEq(h.goldLadderFlip(8), 7_500_000e18, "8 golds");
        assertEq(h.goldLadderFlip(16), 7_500_000e18, "capped at the 8 rung");
    }

    // -- one all-gold ticket: 25,000 FLIP -------------------------------------

    function testPackGoldClaimPaysLadderPlusKicker() public {
        seedAndDrain(ALL_GOLD_WORD);

        vm.recordLogs();
        h.claimGoldenTicket(BUYER, LVL);

        assertEq(flipRec.calls(), 1, "one flip credit");
        assertEq(flipRec.lastPlayer(), BUYER, "credited to the buyer");
        assertEq(flipRec.lastAmount(), EXPECTED_FLIP, "4-gold rung + all-gold kicker");

        (uint8 golds, uint8 allGold, uint256 flipCredit) = foilEventPayload(
            vm.getRecordedLogs()
        );
        assertEq(golds, PACK_GOLDS, "four golds in the pack");
        assertEq(allGold, 1, "all four inside one ticket");
        assertEq(flipCredit, EXPECTED_FLIP, "event carries the credit");

        // The FLIP rungs move no pool value and grant no pass.
        assertEq(h.claimableOf(BUYER), 0, "no ETH on the flip rungs");
        assertEq(h.whalePassOf(BUYER), 0, "no pass on the flip rungs");
    }

    /// @dev The kicker is for the SHAPE: four golds scattered across tickets pay the
    ///      ladder rung alone, four golds inside one ticket pay the rung plus 25,000.
    function testKickerOnlyForAnAllGoldTicket() public {
        h.setPools(50 ether, 400 ether);
        h.settleGoldenTicket(BUYER, LVL, 4, 0); // four golds, none aligned
        assertEq(flipRec.lastAmount(), LADDER_4, "scattered pays the rung alone");

        h.settleGoldenTicket(BUYER, LVL, 4, 1); // four golds, all in one ticket
        assertEq(flipRec.lastAmount(), LADDER_4 + KICKER, "aligned adds the kicker");
    }

    /// @dev Anyone may settle it; the value still lands on the pack owner.
    function testClaimIsPermissionless() public {
        seedAndDrain(ALL_GOLD_WORD);
        vm.prank(address(0xCAFE));
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.lastPlayer(), BUYER, "credit follows the pack, not the caller");
    }

    function testClaimPaysOnce() public {
        seedAndDrain(ALL_GOLD_WORD);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.calls(), 1, "credited once");

        vm.expectRevert(DegenerusGameFoilPackModule.NoGoldenTicket.selector);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.calls(), 1, "no second credit");
    }

    /// @dev The floor rung, on a searched pack that really rolls three scattered golds
    ///      and no all-gold ticket: the ladder alone, no kicker.
    function testThreeScatteredGoldsPayTheFloorRung() public {
        seedAndDrain(THREE_GOLD_WORD);
        vm.recordLogs();
        h.claimGoldenTicket(BUYER, LVL);

        (uint8 golds, uint8 allGold, uint256 flipCredit) = foilEventPayload(
            vm.getRecordedLogs()
        );
        assertEq(golds, 3, "three golds");
        assertEq(allGold, 0, "scattered, no all-gold ticket");
        assertEq(flipCredit, 20_000e18, "the 3-gold rung, no kicker");
        assertEq(flipRec.lastAmount(), 20_000e18, "credited the rung");
    }

    function testFiveScatteredGoldsPayTheFiveRung() public {
        seedAndDrain(FIVE_GOLD_WORD);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.lastAmount(), 250_000e18, "the 5-gold rung");
    }

    function testClaimRevertsAtTwoGolds() public {
        seedAndDrain(TWO_GOLD_WORD);
        vm.expectRevert(DegenerusGameFoilPackModule.NoGoldenTicket.selector);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.calls(), 0, "nothing credited under the floor");
    }

    function testClaimRevertsWithNoGold() public {
        seedAndDrain(NO_GOLD_WORD);
        vm.expectRevert(DegenerusGameFoilPackModule.NoGoldenTicket.selector);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.calls(), 0, "nothing credited");
    }

    function testClaimRevertsWithoutAPack() public {
        h.setRngWord(RESOLVE_DAY, ALL_GOLD_WORD);
        vm.expectRevert(DegenerusGameFoilPackModule.NoGoldenTicket.selector);
        h.claimGoldenTicket(BUYER, LVL);
    }

    /// @dev A pack whose resolveDay word has not sealed has no lines yet.
    function testClaimRevertsBeforeTheWordSeals() public {
        h.setFoilRecord(LVL, BUYER, MAX_MULT, RESOLVE_DAY, 0);
        vm.expectRevert(DegenerusGameFoilPackModule.NoGoldenTicket.selector);
        h.claimGoldenTicket(BUYER, LVL);
    }

    /// @dev The claim closes from the liveness trigger on, matching the match claim:
    ///      past that point the terminal path is drawing down the pool the grand debits.
    function testClaimClosedAfterLiveness() public {
        seedAndDrain(ALL_GOLD_WORD);
        // Level 0 with purchaseStartDay 0 and no VRF request in flight: past the
        // 365-day deploy idle timeout the liveness trigger is live.
        vm.warp(400 days);
        vm.expectRevert(DegenerusGameStorage.GameOver.selector);
        h.claimGoldenTicket(BUYER, LVL);
    }

    // -- the snap valve reaches the price and stops there ----------------------
    //
    // No foil payout scales with the exponent, so on a thanos level the pack is simply
    // bad value: the buy pays 2^s and the ladder pays flat. The record never stores the
    // exponent, so the only way one could reach a claim is a LIVE read; the two cases
    // below move the live shift in both directions and must land on the same credit.

    /// @dev THE LEVER THIS CLOSES: a thanos declaration always targets level + 6 or
    ///      beyond, so once it commits a LIVE _snapShiftFor(pastLvl) returns the NEW
    ///      exponent. A claim parked across that commit would pay 2^(new - old) times
    ///      its face if any leg read the exponent live — which would make holding a
    ///      claim back strictly dominant. Nothing reads it, so nothing moves.
    function testClaimIgnoresASnapCommittedAfterTheBuy() public {
        seedAndDrain(ALL_GOLD_WORD);

        // A declaration commits: snapShift is now 8 for every level from here on, and
        // a live _snapShiftFor(LVL) on this past level would hand back 8.
        h.setSnap(0, 0);
        h.setLiveSnapShift(8);
        assertEq(h.liveSnapShiftFor(LVL), 8, "the live read really did move");

        h.claimGoldenTicket(BUYER, LVL);
        assertEq(
            flipRec.lastAmount(),
            EXPECTED_FLIP,
            "credit moved with a snap committed after the buy"
        );
    }

    /// @dev And the converse direction: a pack bought AT a snap pays the same flat
    ///      credit once the valve lifts. The exponent is not stored, so there is nothing
    ///      to lose here either — the claim is snap-invariant in both directions.
    function testClaimIgnoresTheValveLifting() public {
        seedAndDrain(ALL_GOLD_WORD);
        h.setLiveSnapShift(0);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.lastAmount(), EXPECTED_FLIP, "credit moved when the valve lifted");
    }

    // -- two all-gold tickets: the grand --------------------------------------

    function testTwoAllGoldTicketsPayGrand() public {
        uint128 futBal = 400 ether;
        uint128 nextBal = 50 ether;
        uint256 curPool = 30 ether;
        uint256 yieldAcc = 20 ether;
        h.setPools(nextBal, futBal);
        h.setCurrentPool(curPool);
        h.setYieldAcc(yieldAcc);

        vm.recordLogs();
        h.pushFoilGrand(BUYER, LVL, 8, 2);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 expectedEth = uint256(futBal) / 4;
        uint256 headline = curPool + nextBal + futBal + yieldAcc;
        uint256 remainder = headline - expectedEth;
        uint256 passValue = (remainder * 3) / 4;
        uint256 expectedPasses = passValue / HALF_PASS_PRICE;
        uint256 expectedFlip = ((remainder - passValue) * COIN_UNIT) /
            PriceLookupLib.priceForLevel(LVL + 1);

        assertEq(h.claimableOf(BUYER), expectedEth, "grand ETH = 25% of future");
        assertEq(h.whalePassOf(BUYER), expectedPasses, "grand half-passes");
        assertEq(flipRec.lastAmount(), expectedFlip, "grand flip credit");
        assertEq(flipRec.lastPlayer(), BUYER, "flip credit to the winner");

        (, uint128 futAfter) = h.poolsView();
        assertEq(futAfter, futBal - expectedEth, "future debited by the ETH leg");
        assertEq(h.claimablePoolView(), expectedEth, "claimable pool tracks the credit");

        // The consolation rung does not also fire.
        assertEq(flipRec.calls(), 1, "one flip credit, not two");
        (uint8 golds, uint8 allGold, uint256 consolation) = foilEventPayload(logs);
        assertEq(golds, 8, "eight golds");
        assertEq(allGold, 2, "two all-gold tickets");
        assertEq(consolation, 0, "the grand supersedes the ladder, no FLIP on top");

        // The jackpot module stamps the foil route on its own event.
        (uint8 route, uint8 goldCount, bool grand, uint256 ethAmount) = winEventPayload(
            logs
        );
        assertEq(route, 1, "foil route");
        assertEq(goldCount, 8, "eight gold quadrants");
        assertTrue(grand, "grand rung");
        assertEq(ethAmount, expectedEth, "event ETH matches the credit");
    }

    /// @dev Three and four all-gold tickets are the grand too — the rung is "two or
    ///      more", not "exactly two".
    function testThreeAllGoldTicketsAlsoPayGrand() public {
        h.setPools(50 ether, 400 ether);
        vm.recordLogs();
        h.pushFoilGrand(BUYER, LVL, 12, 3);
        (, uint8 goldCount, bool grand, ) = winEventPayload(vm.getRecordedLogs());
        assertTrue(grand, "three tickets still the grand");
        // goldCount stamps the pack's gold QUADRANTS (12), not its all-gold ticket
        // count (3) — the grand fires at 8, 12 or 16, always clear of the board
        // route's 0-4 range, so the two routes never read alike on the count alone.
        assertEq(goldCount, 12, "goldCount is the quadrant count, not the ticket count");
        assertEq(h.claimableOf(BUYER), uint256(400 ether) / 4, "grand ETH leg");
    }

    /// @dev The grand pushes from the DRAIN, which runs inside advanceGame — a
    ///      deterministic protocol function with no player discretion — and strictly
    ///      before the draw it feeds, since the readiness gate holds rngGate until the
    ///      foil drain catches up. So the futurePrizePool debit always lands ahead of
    ///      any pool math that reads it, exactly as the armed board route's own grand
    ///      does from payDailyJackpot, and the RNG lock is deliberately NOT consulted.
    ///      This pins that: the identical push under a held lock pays the identical
    ///      grand. A future sweep re-adding a lock guard here fails loudly.
    function testGrandPaysUnderTheRngLock() public {
        h.setPools(50 ether, 400 ether);
        h.setRngLocked(true);
        h.pushFoilGrand(BUYER, LVL, 8, 2);
        assertEq(
            h.claimableOf(BUYER),
            uint256(400 ether) / 4,
            "grand ETH leg paid under the lock"
        );
    }

    /// @dev The pull's FLIP rungs read no pool either, so nothing about the lock reaches
    ///      the claim side.
    function testFlipRungsClaimableWhileRngLocked() public {
        seedAndDrain(ALL_GOLD_WORD);
        h.setRngLocked(true);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.lastAmount(), EXPECTED_FLIP, "ladder settles under the lock");
    }

    // -- the grand closes the pull behind it -----------------------------------

    /// @dev THE DOUBLE-DIP THIS CLOSES: two all-gold tickets ARE eight golds, which is
    ///      also the ladder's top rung. Without a marker the same pack would take a
    ///      pool-sized grand from the drain and then pull 7,500,000 FLIP on top of it.
    ///      The push burns the pack's claim marker, so the pull is shut.
    function testGrandBurnsTheClaimMarker() public {
        h.setPools(50 ether, 400 ether);
        assertFalse(h.goldenTicketClaimed(BUYER, LVL), "unmarked before the push");

        h.pushFoilGrand(BUYER, LVL, 8, 2);

        assertTrue(h.goldenTicketClaimed(BUYER, LVL), "push burned the marker");
        uint256 flipCalls = flipRec.calls();

        // The pull is now shut for this pack — no ladder rung on top of the grand.
        vm.expectRevert(DegenerusGameFoilPackModule.NoGoldenTicket.selector);
        h.claimGoldenTicket(BUYER, LVL);
        assertEq(flipRec.calls(), flipCalls, "no FLIP credit after the grand");
    }

    /// @dev Sizes what that marker is worth. Two all-gold tickets ARE eight golds
    ///      (testPackGoldCountsTotalAndTickets pins the counting), and eight golds is
    ///      exactly where the ladder tops out — so the double-dip the marker closes is
    ///      a pool-sized grand PLUS 7,500,000 FLIP, not some rounding artifact.
    ///
    ///      The claim's own `allGold >= 2` guard sits behind the marker as a second
    ///      brace. It cannot be driven through the live claim: reaching it needs a real
    ///      two-all-gold pack, which is the same 1-in-7.1-billion draw that makes the
    ///      push itself untestable without an exposer. The marker is the guard that
    ///      actually fires; this records what it is holding back.
    function testTopLadderRungIsWhatTheMarkerWithholds() public view {
        uint32 goldLine = uint32(GOLD_A) |
            (uint32(GOLD_B) << 8) |
            (uint32(GOLD_C) << 16) |
            (uint32(GOLD_D) << 24);
        uint32 noGold;

        (uint8 golds, uint8 allGold) = h.packGold(
            [goldLine, goldLine, noGold, noGold]
        );
        assertEq(allGold, 2, "two all-gold tickets");
        assertEq(golds, 8, "which is eight golds");
        assertEq(
            h.goldLadderFlip(golds),
            7_500_000e18,
            "and eight golds is the ladder's top rung"
        );
    }

    /// @dev The foil grand leaves the armed-board slot alone: a pending arm still
    ///      resolves on its own next draw.
    function testGrandDoesNotTouchArmedBoard() public {
        uint256 armed = (uint256(1) << 189) | uint256(uint160(address(0xBEEF)));
        h.setGoldenTicketRaw(armed);

        h.setPools(50 ether, 400 ether);
        h.pushFoilGrand(BUYER, LVL, 8, 2);

        assertEq(h.goldenTicketRaw(), armed, "armed board untouched by the foil route");
    }

    // -- helpers --------------------------------------------------------------

    function assertNoFoilEvent(Vm.Log[] memory logs) internal pure {
        bytes32 topic = keccak256("GoldenTicketFoil(address,uint24,uint8,uint8,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            require(logs[i].topics[0] != topic, "no golden-ticket event");
        }
    }

    function foilEventPayload(
        Vm.Log[] memory logs
    ) internal pure returns (uint8 golds, uint8 allGold, uint256 flipCredit) {
        bytes32 topic = keccak256("GoldenTicketFoil(address,uint24,uint8,uint8,uint256)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) {
                found = true;
                (golds, allGold, flipCredit) = abi.decode(
                    logs[i].data,
                    (uint8, uint8, uint256)
                );
            }
        }
        require(found, "GoldenTicketFoil emitted");
    }

    function winEventPayload(
        Vm.Log[] memory logs
    )
        internal
        pure
        returns (uint8 route, uint8 goldCount, bool grand, uint256 ethAmount)
    {
        bytes32 topic = keccak256(
            "GoldenTicketWin(address,uint24,uint8,uint8,bool,uint256,uint256,uint256,uint256)"
        );
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) {
                found = true;
                (route, goldCount, grand, ethAmount, , , ) = abi.decode(
                    logs[i].data,
                    (uint8, uint8, bool, uint256, uint256, uint256, uint256)
                );
            }
        }
        require(found, "GoldenTicketWin emitted");
    }

}
