// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegeneretteMathHarness} from "../../contracts/mocks/DegeneretteMathHarness.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

contract DegeneretteSingleSymbolTest is DeployProtocol {
    DegeneretteMathHarness private math;
    address private alice;
    address private bob;
    bytes32 private constant RESULT = keccak256("DegeneretteResult(address,uint64,uint8,uint32,uint8,uint256)");
    bytes32 private constant RESOLVED = keccak256("DegeneretteResolved(address,uint64,uint8,uint256,uint32)");

    function setUp() public {
        _deployProtocol();
        math = new DegeneretteMathHarness();
        alice = makeAddr("single_symbol_alice");
        bob = makeAddr("single_symbol_bob");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(address(game), 10_000 ether);
        vm.store(address(game), bytes32(uint256(33)), bytes32(uint256(1)));
        vm.store(address(game), bytes32(uint256(2)), bytes32(uint256(10_000 ether) << 128));
    }

    function _place(address who, uint8 currency, uint8 spins, uint8 symbol, uint128 stake) private returns (uint64 id) {
        if (currency == 1) {
            vm.prank(address(game));
            coin.mintForGame(who, uint256(stake) * spins);
        }
        vm.prank(who);
        game.placeDegeneretteBet{value: currency == 0 ? uint256(stake) * spins : 0}(
            address(0), currency, stake, spins, symbol
        );
        id = uint64(uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(38))))));
    }

    function _land(uint256 word) private {
        vm.store(address(game), keccak256(abi.encode(uint48(1), uint256(34))), bytes32(word));
    }

    function _resolve(address who, uint64 id, uint8 symbol, uint256 word)
        private
        returns (uint32[] memory tickets, uint32 firstHouse)
    {
        uint64[] memory ids = new uint64[](1);
        ids[0] = id;
        vm.recordLogs();
        game.resolveDegeneretteBets(who, ids);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == RESULT) ++count;
        }
        tickets = new uint32[](count);
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == RESULT) {
                (uint8 spin, uint32 ticket, uint8 score,) = abi.decode(logs[i].data, (uint8, uint32, uint8, uint256));
                tickets[spin] = ticket;
                assertEq(
                    ticket, Ref.player(word, 1, symbol, spin, false), "generated ticket differs from public stream"
                );
                assertEq((ticket >> ((symbol >> 3) * 8)) & 7, symbol & 7, "hero pick was lost");
                uint32 house = Ref.house(word, 1, spin, false);
                (uint8 natural,) = Ref.score(ticket, house, symbol >> 3);
                assertEq(score, natural, "independent color score mismatch");
            } else if (logs[i].topics[0] == RESOLVED) {
                (,, firstHouse) = abi.decode(logs[i].data, (uint8, uint256, uint32));
            }
        }
    }

    function testSharedHeroTicketsAndPrefixAcrossPlayersBetsStakesAndEthFlip() public {
        uint8 symbol = 11;
        uint64 a = _place(alice, 0, 10, symbol, 0.005 ether);
        uint64 a2 = _place(alice, 0, 5, symbol, 0.01 ether);
        uint64 b = _place(bob, 1, 5, symbol, 100 ether);
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
        game.setOperatorApproval(bob, true);
        vm.prank(address(game));
        wwxrp.mintPrize(alice, 123 ether);
        vm.prank(address(game));
        coin.mintForGame(alice, 456 ether);
        bytes32 boonSlot = bytes32(uint256(keccak256(abi.encode(alice, uint256(50)))) + 1);
        uint256 lane = (uint256(game.currentDayView()) << 3) | 3;
        vm.store(address(game), boonSlot, bytes32((lane << 184) | (lane << 208)));
        uint8[3] memory currencies = [uint8(2), 3, 255];
        address[3] memory callers = [alice, bob, gifter];
        for (uint256 route; route < callers.length; ++route) {
            for (uint256 c; c < currencies.length; ++c) {
                bytes32 beforeState = _rejectionState(callers[route], boonSlot);
                vm.expectRevert(bytes4(keccak256("UnsupportedCurrency()")));
                vm.prank(callers[route]);
                game.placeDegeneretteBet{value: 0.01 ether}(alice, currencies[c], 1 ether, 1, 7);
                assertEq(_rejectionState(callers[route], boonSlot), beforeState,
                    "unsupported bet mutated funding, nonce, pool or boon state");
            }
        }
    }

    function _rejectionState(address caller, bytes32 boonSlot) private view returns (bytes32) {
        return keccak256(abi.encode(
            address(game).balance, alice.balance, caller.balance,
            coin.balanceOf(alice), wwxrp.balanceOf(alice), wwxrp.totalSupply(),
            vm.load(address(game), bytes32(uint256(1))),
            vm.load(address(game), bytes32(uint256(2))),
            vm.load(address(game), keccak256(abi.encode(alice, uint256(38)))),
            vm.load(address(game), boonSlot)
        ));
    }

    function testInvalidSymbolAndRevealedRoundRejected() public {
        vm.expectRevert(bytes4(keccak256("InvalidBet()")));
        vm.prank(alice);
        game.placeDegeneretteBet{value: 0.005 ether}(address(0), 0, 0.005 ether, 1, 32);
        _land(1);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        vm.prank(alice);
        game.placeDegeneretteBet{value: 0.005 ether}(address(0), 0, 0.005 ether, 1, 0);
    }

    function testIndependentColorsHeroWeightAndMatchedGold() public view {
        // All symbols differ; four gold colors match independently.
        (uint8 s, uint8 g) = math.score(0x38383838, 0x39393939, 0);
        assertEq(s, 4);
        assertEq(g, 4);
        (s, g) = math.score(0x38383838, 0x39393938, 0);
        assertEq(s, 6);
        assertEq(g, 4);
        (s, g) = math.score(0x38383838, 0, 0);
        assertEq(s, 5);
        assertEq(g, 0, "unmatched gold must not boost");
        assertEq(math.payout(4, 1, 1, 1 ether, 0), 11.25 ether);
        assertEq(math.payout(4, 1, 3, 1 ether, 0), 7.299_884_997_5 ether, "WWXRP base is calibrated for its rig");
        assertEq(math.payout(1, 1, 0, 1 ether, 0), 0);
    }

    function testAllAxesAndAllHeroesAgainstIndependentScore() public view {
        for (uint16 mask; mask < 256; ++mask) {
            uint32 p = 0x38383838;
            uint32 r;
            for (uint8 q; q < 4; ++q) {
                r |= uint32(((mask >> q) & 1 == 1 ? 0 : 1) | ((mask >> (q + 4)) & 1 == 1 ? 56 : 0)) << (q * 8);
            }
            for (uint8 hero; hero < 4; ++hero) {
                (uint8 expected, uint8 gold) = Ref.score(p, r, hero);
                (uint8 actual, uint8 actualGold) = math.score(p, r, hero);
                assertEq(actual, expected);
                assertEq(actualGold, gold);
                assertLe(actual, 9);
                uint32 rigged = math.rig(p, r, hero, 0); // help gate fires
                (uint8 helped, uint8 helpedGold) = math.score(p, rigged, hero);
                assertGe(helped, actual);
                assertLe(helped, actual + 1);
                assertGe(helpedGold, gold);
                if (actual != 9) assertLt(helped, 9);
                assertEq((rigged >> (hero * 8)) & 7, (r >> (hero * 8)) & 7, "rig changes hero symbol");
                assertEq(math.rig(p, r, hero, 1), r, "non-help draw must stay unchanged");
            }
        }
    }

    function testUniformProducerAllColorSymbolPairs() public view {
        for (uint8 c; c < 8; ++c) {
            for (uint8 sy; sy < 8; ++sy) {
                uint256 lane = uint256(c) | (uint256(sy) << 32);
                uint32 t = math.traits(lane | (lane << 64) | (lane << 128) | (lane << 192));
                for (uint8 q; q < 4; ++q) {
                    assertEq(uint8(t >> (q * 8)), (q << 6) | (c << 3) | sy);
                }
            }
        }
    }

    function testFuzzPayoutBoundsAndWwxrpBonusTiers(uint128 amount, uint8 score, uint8 gold, uint16 activity)
        public
        view
    {
        score %= 10;
        gold %= 5;
        uint256 wx = math.payout(score, gold, 3, amount, activity);
        if (score < 6) assertEq(wx, math.payout(score, gold, 3, amount, 0));
        else assertGe(wx, math.payout(score, gold, 3, amount, 0));
        assertLe(wx, uint256(amount) * 5_485_508);
        assertLe(math.payout(score, gold, 0, amount, activity), uint256(amount) * 647_193);
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
            uint8 symbol = chosen == 2 ? 32 : chosen * 31; // symbol 0, symbol 31, random sentinel
            uint256 seed = uint256(keccak256(abi.encode("automatic flip", chosen)));
            (bytes memory returned, Vm.Log[] memory logs) = _awardCall(
                abi.encodeCall(
                    IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox,
                    (alice, 3000 ether, uint16(305), seed, symbol)
                )
            );
            (uint256 packed, uint256 payout) = _boxRecord(logs);
            assertEq(uint8(packed >> 216), 3);
            uint256 expectedTotal;
            for (uint8 i; i < 3; ++i) {
                uint256 ss = uint256(keccak256(abi.encode(seed, uint256(i))));
                uint8 hero = symbol == 32
                    ? uint8(uint256(keccak256(abi.encode(ss, uint256(0x446567656e4865726f)))) & 31)
                    : symbol;
                uint32 p = uint32(packed >> (i * 72));
                uint32 r = uint32(packed >> (i * 72 + 32));
                assertEq((packed >> (225 + i * 2)) & 3, hero >> 3);
                assertEq(p, math.ticket(ss, hero));
                assertEq(r, Ref.traits(uint256(keccak256(abi.encode(ss, uint256(0x446567656e526573756c74))))));
                (uint8 score, uint8 gold) = Ref.score(p, r, hero >> 3);
                assertEq(uint8(packed >> (i * 72 + 64)), score);
                expectedTotal += math.payout(score, gold, 1, 1000 ether, 305);
            }
            bool survived =
                expectedTotal != 0 && uint256(keccak256(abi.encode(seed, uint256(0x537572766976616c)))) & 1 == 1;
            assertEq((packed >> 224) & 1, survived ? 1 : 0);
            expectedTotal = survived ? expectedTotal * 2 : 0;
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
            (bytes memory returned, Vm.Log[] memory logs) = _awardCall(
                abi.encodeCall(
                    IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox, (alice, 1 ether, uint16(305), seed, chosen)
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
            assertEq((packed >> 225) & 3, symbol >> 3);
            (uint8 score, uint8 gold) = Ref.score(p, r, symbol >> 3);
            assertEq(uint8(packed >> 64), score);
            assertEq(payout, math.payout(score, gold, 3, 1 ether, 305));
            assertEq(abi.decode(returned, (uint256)), payout);
        }
    }

    /// @notice A natural WWXRP jackpot keeps its token payout and cannot create a whale pass.
    /// @dev Pinned from an off-chain Keccak search: seed 729121, hero 7 produces identical
    ///      player and natural house tickets 0xd3a34927 (score 9, zero matched gold).
    function testNaturalWwxrpJackpotPaysTokensWithoutWhalePass() public {
        uint256 seed = 729_121;
        uint8 symbol = 7;
        uint256 drawSeed = Ref.drawWord(seed, true);
        uint32 ticket = math.ticket(drawSeed, symbol);
        uint32 natural = Ref.traits(
            uint256(keccak256(abi.encode(drawSeed, uint256(0x446567656e526573756c74))))
        );
        (uint8 naturalScore, uint8 gold) = Ref.score(ticket, natural, symbol >> 3);
        assertEq(ticket, 0xd3a34927, "pinned player ticket");
        assertEq(ticket, natural, "jackpot must be natural, before the rig");
        assertEq(naturalScore, 9, "must exercise the removed whale-pass award branch");
        assertEq(gold, 0);

        // These mappings retain their layout even though the WWXRP award is removed.
        bytes32 claimsSlot = keccak256(abi.encode(alice, uint256(20)));
        bytes32 bracketSlot = keccak256(abi.encode(uint256(game.level()) / 10, uint256(21)));
        // The retired increment would also revert at this claim balance.
        vm.store(address(game), claimsSlot, bytes32(type(uint256).max));
        assertEq(vm.load(address(game), bracketSlot), bytes32(0), "fresh award bracket");

        (bytes memory returned, Vm.Log[] memory logs) = _awardCall(
            abi.encodeCall(
                IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox,
                (alice, 1 ether, uint16(0), seed, symbol)
            )
        );
        (uint256 packed, uint256 payout) = _boxRecord(logs);
        assertEq(uint8(packed >> 64), 9, "production spin kept the natural jackpot");
        assertEq(payout, 58_399.07998 ether, "WWXRP jackpot payout changed");
        assertEq(abi.decode(returned, (uint256)), payout, "caller receives the token payout");
        assertEq(vm.load(address(game), claimsSlot), bytes32(type(uint256).max), "WWXRP changed whale-pass claims");
        assertEq(vm.load(address(game), bracketSlot), bytes32(0), "WWXRP consumed a whale-pass bracket");
        bytes32 retiredAward = keccak256("WwxrpJackpotWhalePass(address,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0) assertTrue(logs[i].topics[0] != retiredAward, "retired award emitted");
        }
    }

    function testHeroIsStoredOnlyInTheSelectedSymbol() public {
        uint64 id = _place(alice, 0, 1, 31, 0.005 ether);
        bytes32 leaf = keccak256(abi.encode(id, keccak256(abi.encode(alice, uint256(37)))));
        uint256 packed = uint256(vm.load(address(game), leaf));
        assertEq(uint32(packed), 31);
        assertEq((packed >> 218) & 3, 0, "redundant hero field must remain reserved");
        uint256 word = uint256(keccak256("last hero quadrant"));
        _land(word);
        _resolve(alice, id, 31, word);
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
