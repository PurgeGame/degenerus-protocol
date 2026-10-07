// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Test} from "forge-std/Test.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract OwedEightPurchaseSeeder is DegenerusGame, WalletSeed {
    function seedClaim(address player) external { _seedHalfPasses(player, 4); }
}

contract OwedEightPurchaseBaselineTest is DeployProtocol {
    address private constant BUYER = address(0xABC125);

    function setUp() public {
        _deployProtocol();
        vm.deal(BUYER, 100 ether);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(OwedEightPurchaseSeeder).runtimeCode);
        OwedEightPurchaseSeeder(payable(address(game))).seedClaim(BUYER);
        vm.etch(address(game), code);
    }

    function test_ColdWhaleClaim100Levels() public {
        uint32 id = game.walletIdOf(BUYER);
        vm.cool(address(game));
        uint256 beforeGas = gasleft();
        game.claimWhalePass(id);
        emit log_named_uint("OWED8_WHALE_CLAIM_100", beforeGas - gasleft());
        for (uint24 lvl = 1; lvl <= 100; ++lvl) assertEq(game.entriesOwedView(lvl, BUYER), 4);
    }

    function test_ColdDeityBuy100Levels() public {
        vm.cool(address(game));
        vm.prank(BUYER);
        uint256 beforeGas = gasleft();
        game.purchaseDeityPass{value: 24 ether}(0, 4, bytes32(0));
        emit log_named_uint("OWED8_DEITY_BUY_100", beforeGas - gasleft());
        for (uint24 lvl = 1; lvl <= 100; ++lvl) assertEq(game.entriesOwedView(lvl, BUYER), 4);
    }

    function test_ColdLazyBundle10Levels() public {
        vm.cool(address(game));
        vm.prank(BUYER);
        uint256 beforeGas = gasleft();
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        emit log_named_uint("OWED8_LAZY_BUNDLE_10", beforeGas - gasleft());
        for (uint24 lvl = 2; lvl <= 10; ++lvl) assertEq(game.entriesOwedView(lvl, BUYER), 4);
    }
}

contract OwedEightDrainHarness is DegenerusGameTicketModule, WalletSeed {
    function credit(address player, uint24 lvl, uint32 entries) external {
        _queueEntries(_seedWallet(player), lvl, entries, false);
    }
    function commit(uint24 lvl, uint8 shift) external {
        level = lvl - 1;
        lastPurchaseDay = true;
        rngLockedFlag = true;
        rngWordCurrent = 0x12902fc2cb1a37;
        _setRngSessionPublished(true);
        _setRngComplete(false);
        snapShift = shift;
    }
    function owed(address player, uint24 lvl) external view returns (uint80) {
        return _owedOf(_tqFarFutureKey(lvl), player);
    }
    function count(uint24 lvl) external view returns (uint256 n) {
        for (uint256 t; t < 256; ++t) n += _bucketLength(lvl, t);
    }
    function queueLength(uint24 lvl) external view returns (uint256) {
        return _ticketQueueLength(_tqFarFutureKey(lvl));
    }
    function routing(uint24 lvl, bool jackpot, bool transition, bool locked, bool last, uint8 counter)
        external returns (uint24 target, uint24 ceiling)
    {
        level = lvl;
        jackpotPhaseFlag = jackpot;
        phaseTransitionActive = transition;
        rngLockedFlag = locked;
        lastPurchaseDay = last;
        jackpotCounter = counter;
        return (_activeTicketLevel(), _mintCeiling());
    }
}

contract OwedEightDrainBaselineTest is Test {
    OwedEightDrainHarness private h;
    uint24 private constant LVL = 3;
    uint256 private constant OWNERS = 600;

    function setUp() public {
        vm.warp(10 days);
        h = new OwedEightDrainHarness();
        for (uint160 i = 1; i <= OWNERS; ++i) {
            h.credit(address(0x10000 + i), LVL, 4);
            h.credit(address(0x10000 + i), LVL + 1, 4);
        }
        h.commit(LVL, 0);
    }

    function test_ColdDrainCompleteLevel600Owners() public {
        uint256 totalGas;
        uint256 peak;
        uint256 calls;
        bool done;
        while (!done && calls < 100) {
            vm.cool(address(h));
            uint256 beforeGas = gasleft();
            MineFlipGas.Result memory result = h.runTicketWork(LVL - 1, 9_000_000);
            uint256 used = beforeGas - gasleft();
            emit log_named_uint("OWED8_DRAIN_CALL_EXECUTION", used);
            totalGas += used;
            if (used > peak) peak = used;
            assertTrue(result.progressed);
            done = result.done;
            ++calls;
        }
        assertTrue(done);
        assertEq(h.queueLength(LVL), 0);
        assertEq(h.count(LVL), OWNERS * 4);
        assertLt(peak, 10_000_000);
        emit log_named_uint("OWED8_DRAIN_LEVEL_TOTAL", totalGas);
        emit log_named_uint("OWED8_DRAIN_PEAK_CALL", peak);
        emit log_named_uint("OWED8_DRAIN_CALLS", calls);
    }
}

contract OwedEightPremiseTest is Test {
    function test_WholeFarFutureSnapRoundsBeforeCheckpoint() public {
        OwedEightDrainHarness h = new OwedEightDrainHarness();
        address player = address(0x1234);
        h.credit(player, 3, 819_204);
        assertEq(uint8(h.owed(player, 3)), 0);
        h.commit(3, 3);
        MineFlipGas.Result memory result = h.runTicketWork(2, 9_000_000);
        uint80 pending = h.owed(player, 3);
        assertTrue(result.progressed);
        assertFalse(result.done);
        assertEq(uint8(pending), 0, "checkpoint owes only whole entries");
        assertTrue(pending & (uint80(1) << 40) != 0, "resume must not snap twice");
        emit log_named_uint("OWED8_SNAP_REMAINDER", uint8(pending));
    }

    function test_WholeFarFutureSinkSaturatesAt30Bits() public {
        OwedEightDrainHarness h = new OwedEightDrainHarness();
        h.credit(address(0x1234), 3, uint32(1 << 30));
        assertEq(uint32(h.owed(address(0x1234), 3) >> 8), uint32((1 << 30) - 1));
        emit log_named_uint("OWED8_ACCEPTED_ENTRIES", uint32(h.owed(address(0x1234), 3) >> 8));
    }

    function test_PurchaseTargetNeverExceedsCeiling() public {
        OwedEightDrainHarness h = new OwedEightDrainHarness();
        for (uint256 bits; bits < 16; ++bits) {
            for (uint8 counter; counter < 10; ++counter) {
                (uint24 target, uint24 ceiling) = h.routing(10, bits & 1 != 0, bits & 2 != 0,
                    bits & 4 != 0, bits & 8 != 0, counter);
                assertLe(target, ceiling);
            }
        }
    }
}
