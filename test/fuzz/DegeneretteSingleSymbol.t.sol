// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Expose an internal ETH award while keeping the real Game facade available
///      for callbacks from the resulting lootbox rewards (notably Lens.extsload).
contract DegeneretteEthAwardRouter {
    address private immutable facade;

    constructor(address facade_) { facade = facade_; }

    fallback() external payable {
        address target = msg.sig == IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector
            ? ContractAddresses.GAME_DEGENERETTE_MODULE : facade;
        (bool ok, bytes memory result) = target.delegatecall(msg.data);
        assembly ("memory-safe") {
            switch ok
            case 0 { revert(add(result, 32), mload(result)) }
            default { return(add(result, 32), mload(result)) }
        }
    }
}

contract DegeneretteSingleSymbolTest is DeployProtocol {
    DegeneretteMathHarness private math;
    address private alice;
    address private bob;
    Vm.Log[] private resolvedLogs;

    function setUp() public {
        _deployProtocol();
        math = new DegeneretteMathHarness();
        alice = makeAddr("single_symbol_alice");
        bob = makeAddr("single_symbol_bob");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        _giveWalletId(alice);
        _giveWalletId(bob);
        vm.deal(address(game), 10_000 ether);
        RecyclingState.seedWriteBuffer(address(game), 1);
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32(uint256(10_000 ether) << 128));
    }

    function _place(address who, uint8 currency, uint8 spins, uint8 symbol, uint128 stake) private returns (uint64 id) {
        if (currency == 1) {
            vm.prank(address(game));
            coin.mintForGame(who, uint256(stake) * spins);
        }
        vm.prank(who);
        game.placeDegeneretteBet{value: currency == 0 ? uint256(stake) * spins : 0}(
            0, currency, stake, spins, symbol
        );
        id = DQ.lastBetId(vm, address(game), 1);
    }

    function _land(uint256 word) private {
        RecyclingState.seedWord(address(game), 1, bytes32(word));
        RecyclingState.seedDailyWord(address(game), game.currentDayView(), word);
        vm.recordLogs();
        game.mineFlip{gas: 15_000_000}();
        resolvedLogs = vm.getRecordedLogs();
    }

    /// @dev Read this bet's event from the complete engine settlement captured by _land.
    ///      Filtering by id keeps shared-ticket and prefix assertions tied to each bet.
    function _resolve(address who, uint64 id, uint8 symbol, uint256 word)
        private
        returns (uint32[] memory tickets, uint32 firstHouse)
    {
        Vm.Log[] memory logs = resolvedLogs;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != DQ.RESOLVED_SIG) continue;
            if (uint256(logs[i].topics[3]) != id) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), who, "bet owner");
            bytes memory spins;
            (, firstHouse, spins) = abi.decode(logs[i].data, (uint256, uint32, bytes));
            tickets = new uint32[](spins.length / 5);
            for (uint8 spin; spin < tickets.length; ++spin) {
                (uint32 ticket, uint8 score, uint8 wilds) = DQ.spinAt(spins, spin);
                tickets[spin] = ticket;
                assertEq(
                    ticket, Ref.player(word, 1, symbol, spin, false), "generated ticket differs from public stream"
                );
                assertEq((ticket >> ((symbol >> 3) * 8)) & 7, symbol & 7, "hero pick was lost");
                uint32 house = Ref.house(word, 1, spin, false);
                (uint8 natural, uint8 naturalWilds) = Ref.score(ticket, house);
                assertEq(score, natural, "independent wild score mismatch");
                assertEq(wilds, naturalWilds, "house wild count mismatch");
            }
        }
        assertGt(tickets.length, 0, "bet resolution event missing");
    }

    function testSharedHeroTicketsAndPrefixAcrossPlayersBetsStakesAndEthFlip() public {
        uint8 symbol = 11;
        uint64 a = _place(alice, 0, 10, symbol, 0.005 ether);
        uint64 a2 = _place(alice, 0, 5, symbol, 0.01 ether);
        uint64 b = _place(bob, 1, 5, symbol, 100);
        uint256 word = uint256(keccak256("shared prefix"));
        _land(word);
        (uint32[] memory longRun, uint32 houseA) = _resolve(alice, a, symbol, word);
        (uint32[] memory shortRun, uint32 houseA2) = _resolve(alice, a2, symbol, word);
        (uint32[] memory otherPlayer, uint32 houseB) = _resolve(bob, b, symbol, word);
        assertEq(longRun.length, 10);
        assertEq(shortRun.length, 5);
        assertEq(otherPlayer.length, 5);
        for (uint8 i; i < 5; ++i) {
            assertEq(longRun[i], shortRun[i]);
            assertEq(longRun[i], otherPlayer[i]);
        }
        assertEq(houseA, houseA2);
        assertEq(houseA, houseB);
    }

    function testDifferentHeroesRerollRemainingTicketButShareHouse() public {
        uint64 a = _place(alice, 0, 10, 0, 0.005 ether);
        uint64 b = _place(bob, 0, 10, 1, 0.005 ether);
        uint256 word = uint256(keccak256("different heroes"));
        _land(word);
        (uint32[] memory first, uint32 houseA) = _resolve(alice, a, 0, word);
        (uint32[] memory second, uint32 houseB) = _resolve(bob, b, 1, word);
        assertEq(houseA, houseB);
        for (uint8 i; i < 10; ++i) {
            // Same quadrant, different hero symbols: all OTHER bits must use
            // different entropy, not a shared ticket with just 3 bits replaced.
            assertTrue((first[i] & ~uint32(7)) != (second[i] & ~uint32(7)));
        }
    }

    /// @notice Unsupported currencies fail before funding, nonce, pool, or boon changes,
    ///         for self-funded bets, approved operators, and permissionless gifts alike.
    function testUnsupportedCurrenciesRejectAtomicallyForEveryFundingRoute() public {
        address gifter = address(0xC0FFEE);
        vm.deal(gifter, 100 ether);
        vm.prank(alice);
        game.setOperatorApproval(0, bob, true);
        vm.prank(address(game));
        wwxrp.mintPrize(alice, 123);
        vm.prank(address(game));
        coin.mintForGame(alice, 456);
        uint32 aliceId = game.walletIdOf(alice);
        bytes32 boonSlot = bytes32(uint256(keccak256(abi.encode(uint256(aliceId), uint256(50)))) + 1);
        uint256 lane = (uint256(game.currentDayView()) << 3) | 3;
        vm.store(address(game), boonSlot, bytes32((lane << 184) | (lane << 208)));
        uint8[3] memory currencies = [uint8(2), 3, 255];
        address[3] memory callers = [alice, bob, gifter];
        for (uint256 route; route < callers.length; ++route) {
            for (uint256 c; c < currencies.length; ++c) {
                bytes32 beforeState = _rejectionState(callers[route], boonSlot);
                vm.expectRevert(bytes4(keccak256("UnsupportedCurrency()")));
                vm.prank(callers[route]);
                game.placeDegeneretteBet{value: 0.01 ether}(aliceId, currencies[c], 1 ether, 1, 7);
                assertEq(_rejectionState(callers[route], boonSlot), beforeState,
                    "unsupported bet mutated funding, bet queue, pool or boon state");
            }
        }
    }

    function _rejectionState(address caller, bytes32 boonSlot) private view returns (bytes32) {
        return keccak256(abi.encode(
            address(game).balance, alice.balance, caller.balance,
            coin.balanceOf(alice), wwxrp.balanceOf(alice), wwxrp.totalSupply(),
            vm.load(address(game), bytes32(GameSlots.CLAIMABLE_POOL)),
            vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)),
            DQ.lastBetId(vm, address(game), 1), // index-1 bet count
            vm.load(address(game), boonSlot)
        ));
    }

    function testInvalidSymbolRejectedAndNewBetJoinsUnrevealedWriteCohort() public {
        vm.expectRevert(bytes4(keccak256("InvalidBet()")));
        vm.prank(alice);
        game.placeDegeneretteBet{value: 0.005 ether}(0, 0, 0.005 ether, 1, 32);
        _land(2);
        vm.prank(alice);
        game.placeDegeneretteBet{value: 0.005 ether}(0, 0, 0.005 ether, 1, 0);
        assertEq(DQ.lastBetId(vm, address(game), 2), 1, "new bet binds the write cohort");
        assertEq(DQ.lastBetId(vm, address(game), 1), 0, "no bet joined the revealed cohort");
        assertEq(RecyclingState.word(address(game), 1), 2, "read entropy survives the new commitment");
        assertEq(RecyclingState.word(address(game), 0), 0, "the new bet's word is still hidden");
    }

    function testDiceBetsRejectAtomicallyForEveryCurrencyAndFundingRoute() public {
        address gifter = makeAddr("dice_gifter");
        vm.deal(gifter, 100 ether);
        vm.prank(alice);
        game.setOperatorApproval(0, bob, true);
        vm.prank(address(game));
        coin.mintForGame(alice, 1000);
        vm.prank(address(game));
        coin.mintForGame(gifter, 1000);
        uint32 aliceId = game.walletIdOf(alice);
        bytes32 boonSlot = bytes32(uint256(keccak256(abi.encode(uint256(aliceId), uint256(50)))) + 1);
        address[3] memory callers = [alice, bob, gifter];
        for (uint256 route; route < callers.length; ++route) {
            for (uint8 currency; currency < 2; ++currency) {
                bytes32 beforeState = _rejectionState(callers[route], boonSlot);
                uint256 beforeFlip = coin.balanceOf(callers[route]);
                uint128 stake = currency == 0 ? uint128(0.005 ether) : uint128(100);
                for (uint8 symbol = 24; symbol < 32; ++symbol) {
                    vm.expectRevert(bytes4(keccak256("InvalidBet()")));
                    vm.prank(callers[route]);
                    game.placeDegeneretteBet{value: currency == 0 ? stake : 0}(aliceId, currency, stake, 1, symbol);
                    assertEq(_rejectionState(callers[route], boonSlot), beforeState);
                    assertEq(coin.balanceOf(callers[route]), beforeFlip);
                    assertEq(game.getDailyHeroWager(game.currentDayView(), 3, symbol & 7), 0);
                }
            }
        }
    }

    function testWildScoringAndNoGoldPremium() public view {
        // Hero lane 0 wild (symbol 0); lanes 1..3 gold (color 7), symbol 0.
        uint32 p = 0x38383840;
        // Gold equal on lanes 1..3, every symbol missed: hero color 1 + three colors.
        (uint8 s, uint8 w) = math.score(p, 0x39393909);
        assertEq(s, 4);
        assertEq(w, 0);
        // The same board with ordinary color 2 instead of gold scores the same: gold has no premium.
        (uint8 s2,) = math.score(0x10101040, 0x11111109);
        assertEq(s2, s);
        // Four house wilds, every symbol missed: hero double wild 2 + three wild colors.
        (s, w) = math.score(p, 0x41414141);
        assertEq(s, 5);
        assertEq(w, 4);
        assertEq(math.payout(4, 1, 1, 1 ether, 0), 3.375 ether);
        assertEq(math.payout(4, 1, 3, 1 ether, 0), 2.160925838625 ether, "WWXRP base is calibrated for its rig");
        assertEq(math.payout(2, 4, 0, 1 ether, 30_000), 0, "S2 never pays");
    }

    /// @dev One valid board per combination of symbol hits, house wilds and ordinary color
    ///      equalities (lane `hero` holds the player wild), against the independent score and
    ///      the WWXRP help rule.
    function testAllAxesAllHeroesAndWildsAgainstIndependentScoreAndRig() public view {
        for (uint8 hero; hero < 4; ++hero) {
            uint32 p = uint32(0x40) << (hero * 8);
            for (uint16 mask; mask < 4096; ++mask) {
                uint32 r;
                for (uint8 q; q < 4; ++q) {
                    uint32 sym = (mask >> q) & 1 == 1 ? 0 : 1;
                    bool wild = (mask >> (q + 4)) & 1 == 1;
                    bool eq = (mask >> (q + 8)) & 1 == 1;
                    r |= (wild ? 0x40 | sym : (eq ? sym : 0x08 | sym)) << (q * 8);
                }
                (uint8 expected, uint8 wilds) = Ref.score(p, r);
                (uint8 actual, uint8 actualWilds) = math.score(p, r);
                assertEq(actual, expected);
                assertEq(actualWilds, wilds);
                assertGe(actual, 1);
                assertLe(actual, 9);
                uint8 matched = actual - uint8((r >> (hero * 8 + 6)) & 1);
                uint32 rigged = math.rig(p, r, hero, 0); // help gate fires
                (uint8 helped, uint8 helpedWilds) = math.score(p, rigged);
                assertEq(helped, actual >= 3 && matched <= 6 ? actual + 1 : actual, "help adds one point iff eligible");
                assertEq(helpedWilds, wilds, "help never creates or removes a wild");
                assertEq(rigged & 0x40404040, r & 0x40404040, "wild bits unchanged");
                if (actual != 9) assertLt(helped, 9);
                assertEq((rigged >> (hero * 8)) & 7, (r >> (hero * 8)) & 7, "rig changes hero symbol");
                assertEq(math.rig(p, r, hero, 1), r, "non-help draw must stay unchanged");
            }
        }
    }

    function testHouseProducerAllColorSymbolPairsAndWildNibble() public view {
        for (uint8 c; c < 8; ++c) {
            for (uint8 sy; sy < 8; ++sy) {
                for (uint256 nibble; nibble < 16; ++nibble) {
                    uint256 lane = uint256(c) | (nibble << 3) | (uint256(sy) << 32);
                    uint32 t = math.traits(lane | (lane << 64) | (lane << 128) | (lane << 192));
                    for (uint8 q; q < 4; ++q) {
                        assertEq(uint8(t >> (q * 8)), nibble == 0 ? 0x40 | sy : (c << 3) | sy);
                    }
                }
            }
        }
    }

    function testFuzzPayoutBoundsAndWwxrpBonusTiers(uint128 amount, uint8 score, uint8 wilds, uint16 activity)
        public
        view
    {
        score %= 10;
        wilds %= 5;
        uint256 wx = math.payout(score, wilds, 3, amount, activity);
        if (score < 6) assertEq(wx, math.payout(score, wilds, 3, amount, 0));
        else assertGe(wx, math.payout(score, wilds, 3, amount, 0));
        assertLe(wx, uint256(amount) * 3_844_040);
        assertLe(math.payout(score, wilds, 0, amount, activity), uint256(amount) * 907_708);
        assertLe(math.payout(score, wilds, 1, amount, activity), uint256(amount) * 459_540);
        assertLe(math.roi(activity), 9990);
        assertGe(math.roi(activity), 9000);
    }

    /// @dev Execute the actual award entry points in the Game storage context.
    /// The fixture already deploys all production dependencies; only dispatch is replaced.
    function _awardCall(bytes memory data) private returns (bytes memory returned, Vm.Log[] memory logs) {
        bytes memory facade = address(game).code;
        vm.etch(address(game), ContractAddresses.GAME_DEGENERETTE_MODULE.code);
        vm.recordLogs();
        (bool ok, bytes memory result) = address(game).call(data);
        logs = vm.getRecordedLogs();
        vm.etch(address(game), facade);
        require(ok, "automatic spin failed");
        return (result, logs);
    }

    function _boxRecord(Vm.Log[] memory logs) private pure returns (uint256 packed, uint256 payout) {
        bytes32 topic = keccak256("BoxSpin(address,uint64,uint256,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == topic) {
                (, packed, payout,) = abi.decode(logs[i].data, (uint64, uint256, uint256, uint256));
                return (packed, payout);
            }
        }
        revert("missing BoxSpin");
    }

    function testAutomaticFlipReelsExposeHeroAndUseIndependentColorsAndSharedMath() public {
        for (uint8 chosen; chosen < 3; ++chosen) {
            uint8 symbol = chosen == 2 ? 32 : chosen * 23; // symbol 0, symbol 23, random sentinel
            uint256 seed = uint256(keccak256(abi.encode("automatic flip", chosen)));
            (bytes memory returned, Vm.Log[] memory logs) = _awardCall(
                abi.encodeCall(
                    IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox,
                    (alice, 3000e18, uint16(305), seed, symbol)
                )
            );
            (uint256 packed, uint256 payout) = _boxRecord(logs);
            assertEq(uint8(packed >> 216), 3);
            uint256 expectedTotal;
            for (uint8 i; i < 3; ++i) {
                uint256 ss = uint256(keccak256(abi.encode(seed, uint256(i))));
                uint8 hero = symbol == 32 ? Ref.randomHero(ss) : symbol;
                uint32 p = uint32(packed >> (i * 72));
                uint32 r = uint32(packed >> (i * 72 + 32));
                assertEq((p >> ((hero >> 3) * 8)) & 0xFF, 0x40 | (hero & 7), "hero lane carries the wild");
                assertEq(p, math.ticket(ss, hero));
                assertEq(r, Ref.traits(uint256(keccak256(abi.encode(ss, uint256(0x446567656e526573756c74))))));
                (uint8 score, uint8 wilds) = Ref.score(p, r);
                assertEq(uint8(packed >> (i * 72 + 64)), score);
                expectedTotal += math.payout(score, wilds, 1, 1000e18, 305);
            }
            bool survived =
                expectedTotal != 0 && uint256(keccak256(abi.encode(seed, uint256(0x537572766976616c)))) & 1 == 1;
            assertEq((packed >> 224) & 1, survived ? 1 : 0);
            expectedTotal = survived ? expectedTotal * 2 / 1e18 : 0;
            expectedTotal = expectedTotal > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(
                    expectedTotal, uint256(keccak256(abi.encode(seed, uint256(0x466c6970526f756e64))))
                )
                : FlipRoundLib.floorWholeFlip(expectedTotal);
            assertEq(payout, expectedTotal);
            assertEq(abi.decode(returned, (uint256)), expectedTotal);
        }
    }

    function testAutomaticWwxrpHashesItsSeedAndScoresTheRiggedReel() public {
        for (uint256 seed = 1; seed <= 32; ++seed) {
            uint8 chosen = seed == 32 ? 32 : uint8(seed - 1);
            if (chosen >= 24 && chosen != 32) continue;
            (bytes memory returned, Vm.Log[] memory logs) = _awardCall(
                abi.encodeCall(
                    IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox, (alice, 1e18, uint16(305), seed, chosen)
                )
            );
            (uint256 packed, uint256 payout) = _boxRecord(logs);
            assertEq(uint8(packed >> 216), 1);
            uint256 wwSeed = Ref.drawWord(seed, true);
            uint8 symbol = math.hero(wwSeed, chosen);
            uint32 p = uint32(packed);
            uint32 r = uint32(packed >> 32);
            uint32 natural = Ref.traits(uint256(keccak256(abi.encode(wwSeed, uint256(0x446567656e526573756c74)))));
            uint32 rigged =
                math.rig(p, natural, symbol >> 3, uint256(keccak256(abi.encode(wwSeed, uint256(0x52494721)))));
            assertEq(p, math.ticket(wwSeed, symbol));
            assertEq(r, rigged);
            assertEq(packed >> 225, 0, "no hero-quadrant metadata: the player lane marks the hero");
            (uint8 score, uint8 wilds) = Ref.score(p, r);
            assertEq(uint8(packed >> 64), score);
            uint256 rawPayout = math.payout(score, wilds, 3, 1e18, 305);
            uint256 expected = rawPayout / 1e18;
            if (expected == 0 && rawPayout != 0) expected = 1;
            assertEq(payout, expected);
            assertEq(abi.decode(returned, (uint256)), payout);
        }
    }

    /// @notice A natural WWXRP jackpot pays its token prize through the ordinary payout path.
    /// @dev Pinned from an off-chain Keccak search (.planning/wild-color/find_box_jackpot.py):
    ///      seed 359696, hero 15 gives a natural S9 with two house wilds, before the rig.
    function testNaturalWwxrpJackpotPaysTokens() public {
        uint256 seed = 359_696;
        uint8 symbol = 15;
        uint256 drawSeed = Ref.drawWord(seed, true);
        uint32 ticket = math.ticket(drawSeed, symbol);
        uint32 natural = Ref.traits(
            uint256(keccak256(abi.encode(drawSeed, uint256(0x446567656e526573756c74))))
        );
        (uint8 naturalScore, uint8 wilds) = Ref.score(ticket, natural);
        assertEq(ticket, 0x3031473d, "pinned player ticket");
        assertEq(natural, 0x3041473d, "pinned natural house ticket");
        assertEq(naturalScore, 9, "jackpot must be natural, before the rig");
        assertEq(wilds, 2);

        (bytes memory returned, Vm.Log[] memory logs) = _awardCall(
            abi.encodeCall(
                IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox,
                (alice, 1e18, uint16(0), seed, symbol)
            )
        );
        (uint256 packed, uint256 payout) = _boxRecord(logs);
        assertEq(uint8(packed >> 64), 9, "production spin kept the natural jackpot");
        assertEq(uint32(packed >> 32), natural, "the rig never touches a jackpot");
        assertEq(payout, 864_370, "WWXRP jackpot payout changed");
        assertEq(abi.decode(returned, (uint256)), payout, "caller receives the token payout");
    }

    /// @notice Exercise a real jackpot through ETH's cash cap and lootbox recirculation.
    function testNaturalEthJackpotCapsCashAndResolvesOverflow() public {
        // Reuse the natural WWXRP jackpot's inner seed on the ordinary ETH stream.
        uint256 seed = Ref.drawWord(359_696, true);
        _place(alice, 1, 1, 0, 100); // registers alice's wallet ID
        uint256 claimableBefore = game.claimableWinningsOf(alice);
        bytes memory facade = address(game).code;
        address facadeCopy = makeAddr("eth_jackpot_facade");
        vm.etch(facadeCopy, facade);
        vm.etch(address(game), address(new DegeneretteEthAwardRouter(facadeCopy)).code);
        vm.recordLogs();
        IDegenerusGameDegeneretteModule(address(game)).resolveEthSpinFromBox(
            alice, game.walletIdOf(alice), 0.01 ether, uint16(30_000), seed, uint8(15)
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.etch(address(game), facade);
        (uint256 packed, uint256 payout) = _boxRecord(logs);
        assertEq(uint8(packed >> 64), 9, "must exercise the natural jackpot");
        assertEq(payout, 6_807.81 ether, "jackpot includes max activity, two wilds and the ETH addition");
        // 25% of gross exceeds the cap: exactly 10% of the 10,000 ETH future pool is cash.
        assertEq(game.claimableWinningsOf(alice) - claimableBefore, 1000 ether);
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED))) >> 128, 9000 ether);
        bytes32 capTopic = keccak256("PayoutCapped(address,uint256,uint256)");
        bool capped;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != capTopic) continue;
            (uint256 cash, uint256 overflow) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(cash, 1000 ether);
            assertEq(overflow, 5_807.81 ether);
            capped = true;
        }
        assertTrue(capped, "jackpot must report the capped cash and lootbox remainder");
    }

    function testHeroIsStoredOnlyInTheSelectedSymbol() public {
        uint64 id = _place(alice, 0, 1, 23, 0.005 ether);
        uint256 packed = game.degeneretteBetInfo(1, id);
        assertEq((packed >> 160) & 0x1F, 23, "symbol field holds the chosen hero");
        assertEq(packed >> 252, 0, "no separate hero field: the reserved tail stays zero");
        uint256 word = uint256(keccak256("last hero quadrant"));
        _land(word);
        _resolve(alice, id, 23, word);
    }

    function testAutomaticFlipRejectsOversizedPerSpinStakeWithoutTruncation() public {
        // The old uint128 cast could turn this into a small, paying stake.
        uint256 tooLarge = (uint256(type(uint128).max) + 1000 ether) * 3;
        (bytes memory returned, Vm.Log[] memory logs) = _awardCall(
            abi.encodeCall(
                IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox,
                (alice, tooLarge, uint16(0), uint256(1), uint8(0))
            )
        );
        assertEq(abi.decode(returned, (uint256)), 0);
        assertEq(logs.length, 0);
    }
}
