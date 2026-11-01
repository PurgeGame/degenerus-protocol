// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {GnrusTicketHost, GnrusFlipSeeder} from "../fuzz/GnrusFlipTickets.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PeripheralSlots} from "../helpers/PeripheralSlots.sol";
import {MinerloopGasProbe} from "../helpers/MinerloopGasProbe.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {MineFlipRequestGasTest, RequestGameSeeder, RequestCharitySeeder} from "./MineFlipRequestGas.t.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract GnrusFlipTicketsGasTest is DeployProtocol, MinerloopGasProbe {
    GnrusTicketHost internal host;
    uint24 internal constant LATEST = 1381;

    function setUp() public {
        _deployProtocol();
        vm.warp((uint256(LATEST) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
        vm.etch(address(game), type(GnrusTicketHost).runtimeCode);
        host = GnrusTicketHost(payable(address(game)));
        host.prime(4, 0);
    }

    function seedHistory(uint8 pattern, uint24 gap) external {
        require(msg.sender == address(this));
        _seedHistory(pattern, gap, 1_000_000_000);
    }

    function _seedHistory(uint8 pattern, uint24 gap, uint128 bank) private {
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        uint24 latest = 1342 + gap; // first walked day: lane 31 of results, lane 6 of stakes
        vm.warp((uint256(latest) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 1);
        host.prime(4, 0);
        // A bank survives the final loss, so the full purchase still executes after settlement.
        GnrusFlipSeeder(address(coinflip)).history(latest, gap, bank,
            type(uint128).max, 1, 2, 0, pattern);
        vm.etch(address(coinflip), code);
        vm.prank(address(game));
        quests.rollDailyQuest(latest, 123, false, false, false);
    }

    function _buy(uint8 pattern, uint24 gap) internal returns (uint256 total) {
        this.seedHistory(pattern, gap);
        assertEq(game.currentDayView_g542950(), 1342 + gap, "quest and resolved frontier match");
        uint256 supply = coin.totalSupply();
        uint256 wallet = coin.balanceOf(ContractAddresses.GNRUS);
        (GlamsterdamReprice.Result memory r,) = _probe(address(host), address(this),
            abi.encodeCall(host.buyOnly, ()), 9_000_000);
        emit log_named_uint("unclaimed_days", gap);
        _report(string.concat("gnrus_", vm.toString(gap), "_days_pattern_", vm.toString(pattern)), r, Bounds.GNRUS_TICKET_PURCHASE);
        assertGt(host.readEntries(4), 0);
        assertEq(coin.totalSupply(), supply - wallet);
        assertEq(coin.balanceOf(ContractAddresses.GNRUS), 0);
        assertLe(r.glamsterdamExec + r.stateGas, gap <= 40 ? Bounds.GNRUS_TICKET_PURCHASE : 2_000_000);
        assertLe(r.osakaExec, gap <= 40 ? Bounds.GNRUS_TICKET_PURCHASE : 2_000_000);
        assertLt(r.glamsterdamExec + r.stateGas, 10_000_000);
        return r.glamsterdamExec + r.stateGas;
    }

    function seedDust(uint128 bank) external {
        require(msg.sender == address(this));
        // A final loss after the full maximum-carry history leaves only dust (or zero).
        // This includes BAF recording and the WWXRP loss mint before skipping the purchase.
        _seedHistory(2, 40, bank);
    }

    function test_ColdEmptyAndDustSettleOnly() public {
        for (uint128 bank; bank < 3; ++bank) {
            uint256 clean = vm.snapshotState();
            this.seedDust(bank);
            (GlamsterdamReprice.Result memory r,) = _probe(address(host), address(this),
                abi.encodeCall(host.buyOnly, ()), 5_000_000);
            _report(string.concat("settle_only_bank_", vm.toString(bank)), r, Bounds.GNRUS_TICKET_PURCHASE);
            assertLe(r.osakaExec, Bounds.GNRUS_TICKET_PURCHASE);
            assertLe(r.glamsterdamExec + r.stateGas, Bounds.GNRUS_TICKET_PURCHASE);
            assertEq(host.readEntries(4), 0);
            assertTrue(vm.revertToState(clean));
            vm.deleteStateSnapshot(clean);
        }
    }

    function test_Cold40Pattern01() public { _buy(1, 40); }
    function test_Cold40Pattern02() public { _buy(2, 40); }
    function test_Cold40Pattern03() public { _buy(3, 40); }
    function test_Cold40Pattern04() public { _buy(4, 40); }
    function test_Cold40Pattern05() public { _buy(5, 40); }
    function test_Cold40Pattern06() public { _buy(6, 40); }
    function test_Cold40Pattern07() public { _buy(7, 40); }
    function test_Cold40Pattern08() public { _buy(8, 40); }
    function test_Cold40Pattern09() public { _buy(9, 40); }
    function test_Cold40Pattern10() public { _buy(10, 40); }
    function test_Cold40Pattern11() public { _buy(11, 40); }
    function test_Cold40Pattern12() public { _buy(12, 40); }
    function test_Cold40Pattern13() public { _buy(13, 40); }
    function test_Cold40Pattern14() public { _buy(14, 40); }
    function test_Cold40Pattern15() public { _buy(15, 40); }
    function test_Cold40Pattern16() public { _buy(16, 40); }
    function test_Cold40Pattern17() public { _buy(17, 40); }
    function test_Cold40Pattern18() public { _buy(18, 40); }
    function test_Cold40Pattern19() public { _buy(19, 40); }
    function test_Cold40Pattern20() public { _buy(20, 40); }
    function test_Cold40Pattern21() public { _buy(21, 40); }
    function test_Cold40Pattern22() public { _buy(22, 40); }
    function test_Cold40Pattern23() public { _buy(23, 40); }
    function test_Cold40Pattern24() public { _buy(24, 40); }
    function test_Cold40Pattern25() public { _buy(25, 40); }
    function test_Cold40Pattern26() public { _buy(26, 40); }
    function test_Cold40Pattern27() public { _buy(27, 40); }
    function test_Cold40Pattern28() public { _buy(28, 40); }
    function test_Cold40Pattern29() public { _buy(29, 40); }
    function test_Cold40Pattern30() public { _buy(30, 40); }
    function test_Cold40Pattern31() public { _buy(31, 40); }
    function test_Cold40Pattern32() public { _buy(32, 40); }
    function test_Cold40Pattern33() public { _buy(33, 40); }
    function test_Cold40Pattern34() public { _buy(34, 40); }
    function test_Cold40Pattern35() public { _buy(35, 40); }
    function test_Cold40Pattern36() public { _buy(36, 40); }
    function test_Cold40Pattern37() public { _buy(37, 40); }
    function test_Cold40Pattern38() public { _buy(38, 40); }
    function test_Cold40Pattern39() public { _buy(39, 40); }
    function test_Cold40Pattern40() public { _buy(40, 40); }
    function test_Cold40Pattern41() public { _buy(41, 40); }
    function test_Cold40Pattern42() public { _buy(42, 40); }
    function test_Cold40Pattern43() public { _buy(43, 40); }
    function test_Cold40Pattern44() public { _buy(44, 40); }

    function seedWalletGift() external {
        require(msg.sender == address(this));
        vm.prank(address(game));
        coin.mintForGame_g152734(address(this), 2000);
        coin.transfer(ContractAddresses.GNRUS, 2000);
    }
    function test_Cold40FinalLossWithWalletGift() public { this.seedWalletGift(); _buy(2, 40); }
    function test_Cold40NearFinalLossWithWalletGift() public { this.seedWalletGift(); _buy(43, 40); }
    function test_Cold40WinsWithWalletGift() public { this.seedWalletGift(); _buy(1, 40); }

    function seedCentury(uint8 pattern) external {
        require(msg.sender == address(this));
        _seedHistory(pattern, 35, 1_000_000_000);
        host.prime(100, 0);
        host.wwxrpBoon();
        vm.prank(address(game)); wwxrp.creditPrize(3, 50);
        vm.prank(ContractAddresses.VAULT); wwxrp.vaultMintTo(ContractAddresses.GNRUS, 50);
    }
    function _century(uint8 pattern) private {
        this.seedWalletGift();
        this.seedCentury(pattern);
        (GlamsterdamReprice.Result memory r,) = _probe(address(host), address(this),
            abi.encodeCall(host.buyOnly, ()), 9_000_000);
        _report(string.concat("gnrus_x99_35_pattern_", vm.toString(pattern)), r, Bounds.GNRUS_TICKET_PURCHASE);
        assertEq(wwxrp.claimable(3), 0);
        assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), 0);
        (, uint32 count) = wwxrp.incineratorInfo(100);
        assertEq(count, 1);
        assertLe(r.osakaExec, Bounds.GNRUS_TICKET_PURCHASE);
        assertLe(r.glamsterdamExec + r.stateGas, Bounds.GNRUS_TICKET_PURCHASE);
    }
    function test_ColdCenturyPattern01() public { _century(1); }
    function test_ColdCenturyPattern02() public { _century(2); }
    function test_ColdCenturyPattern03() public { _century(3); }
    function test_ColdCenturyPattern04() public { _century(4); }
    function test_ColdCenturyPattern05() public { _century(5); }
    function test_ColdCenturyPattern06() public { _century(6); }
    function test_ColdCenturyPattern07() public { _century(7); }
    function test_ColdCenturyPattern08() public { _century(8); }
    function test_ColdCenturyPattern09() public { _century(9); }
    function test_ColdCenturyPattern10() public { _century(10); }
    function test_ColdCenturyPattern11() public { _century(11); }
    function test_ColdCenturyPattern12() public { _century(12); }
    function test_ColdCenturyPattern13() public { _century(13); }
    function test_ColdCenturyPattern14() public { _century(14); }
    function test_ColdCenturyPattern15() public { _century(15); }
    function test_ColdCenturyPattern16() public { _century(16); }
    function test_ColdCenturyPattern17() public { _century(17); }
    function test_ColdCenturyPattern18() public { _century(18); }
    function test_ColdCenturyPattern19() public { _century(19); }
    function test_ColdCenturyPattern20() public { _century(20); }
    function test_ColdCenturyPattern21() public { _century(21); }
    function test_ColdCenturyPattern22() public { _century(22); }
    function test_ColdCenturyPattern23() public { _century(23); }
    function test_ColdCenturyPattern24() public { _century(24); }
    function test_ColdCenturyPattern25() public { _century(25); }
    function test_ColdCenturyPattern26() public { _century(26); }
    function test_ColdCenturyPattern27() public { _century(27); }
    function test_ColdCenturyPattern28() public { _century(28); }
    function test_ColdCenturyPattern29() public { _century(29); }
    function test_ColdCenturyPattern30() public { _century(30); }
    function test_ColdCenturyPattern31() public { _century(31); }
    function test_ColdCenturyPattern32() public { _century(32); }
    function test_ColdCenturyPattern33() public { _century(33); }
    function test_ColdCenturyPattern34() public { _century(34); }
    function test_ColdCenturyPattern35() public { _century(35); }
    function test_ColdCenturyPattern36() public { _century(36); }
    function test_ColdCenturyPattern37() public { _century(37); }
    function test_ColdCenturyPattern38() public { _century(38); }
    function test_ColdCenturyPattern39() public { _century(39); }

    function test_Cold90WinsMaximumCarry() public { _buy(1, 90); }
    function test_Cold34DaysMaximumCarry() public { _buy(1, 34); }
    function test_Cold40DaysMaximumCarry() public { _buy(1, 40); }
    function test_Cold40DaysFinalLoss() public { _buy(2, 40); }
    function test_Cold90DaysFinalLoss() public { _buy(2, 90); }
}

contract GnrusRequestCaseHost is RequestGameSeeder {
    function wwxrpBoon() external {
        boonPacked[3].slot1 |= (uint256(3) | (uint256(dailyIdx) << 3)) << BP_WWXRP_LANE_SHIFT;
    }
    function shape(uint24 closingLevel, bool early, bool degenesis) external {
        for (uint24 lvl = 1; lvl <= 2; ++lvl) {
            _releaseTicketQueue(_tqWriteKey(lvl));
            _releaseTicketQueue(_tqReadKey(lvl));
        }
        level = closingLevel - 1;
        lastPurchaseDay = !early;
        purchaseStartDay = _afkingResetDay - (early ? 1 : 3);
        jackpotFlags = 0;
        degenesisClosed = degenesis ? 0 : 7;
    }
}

/// @notice Complete request with cold charity, affiliate, Degenesis preparation and redemption
/// close from the existing request fixture, plus GNRUS's 40-day maximum-carry purchase.
contract GnrusFullRequestGasTest is MineFlipRequestGasTest, MinerloopGasProbe {
    function seedRequestHistory(bool refill) external {
        require(msg.sender == address(this));
        bytes memory code = address(coinflip).code;
        vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
        GnrusFlipSeeder(address(coinflip)).history(DAY - 1, 40, 1_000_000_000,
            type(uint128).max, 1, 2, 0, 2);
        vm.etch(address(coinflip), code);
        vm.prank(address(game));
        quests.rollDailyQuest(DAY - 1, 123, false, false, false);
        vm.prank(address(game));
        coin.mintForGame_g152734(address(this), 2000);
        coin.transfer(ContractAddresses.GNRUS, 2000);
        if (refill) {
            // RequestCostCoordinator.balances[1]: balance/nativeBalance/reqCount.
            vm.store(address(coordinator), keccak256(abi.encode(uint256(1), uint256(2))), bytes32(uint256(100) << 192));
            vm.deal(address(game), 10_000 ether);
        }
    }

    function _fullRequest(bool refill) private {
        this.configure(Scenario.DailyRedeem);
        this.seedRequestHistory(refill);
        // A phase-ending request: the miner admission and refill tail both carry GNRUS's buy.
        uint256 admission = Bounds.RNG_DAILY_REQUEST + Bounds.GNRUS_TICKET_PURCHASE + Bounds.DEGENESIS_REQUEST_GAS
            + Bounds.RNG_REDEMPTION_CLOSE;
        uint256 bound = admission + 1_000_000;
        (GlamsterdamReprice.Result memory r,) = _probe(address(host), address(this),
            abi.encodeCall(host.requestOnly, (true)), bound);
        _report(refill ? "gnrus_full_request_refill_close" : "gnrus_full_request_close", r, bound - 1_000_000);
        assertLe(r.osakaExec, admission);
        assertLe(r.glamsterdamExec + r.stateGas, admission);
        if (refill) assertLe(r.glamsterdamExec + r.stateGas, Bounds.VRF_DAILY_REFILL_TAIL + Bounds.GNRUS_TICKET_PURCHASE);
        assertLt(bound, 10_000_000);
        assertLt(r.osakaExec, 10_000_000);
        assertLt(r.glamsterdamExec + r.stateGas, 10_000_000);
        _assertRequested();
        if (refill) {
            (,uint96 funded,,,) = coordinator.getSubscription(1);
            assertGt(funded, 0, "VRF refill must execute");
        }
    }

    function _measureShape(uint8 shapeIndex, bool refill, bool redemption, bool degenesis) private {
        this.configure(redemption ? Scenario.DailyRedeem : Scenario.Transition);
        this.seedRequestHistory(refill);
        uint24[6] memory closing = [uint24(4), 4, 5, 10, 100, 101];
        vm.etch(address(game), type(GnrusRequestCaseHost).runtimeCode);
        GnrusRequestCaseHost(payable(address(game))).shape(closing[shapeIndex], shapeIndex == 0, degenesis);
        // Keep the complete request's charity flush and affiliate award live after changing level.
        bytes memory charityCode = address(gnrus).code;
        vm.etch(address(gnrus), type(RequestCharitySeeder).runtimeCode);
        RequestCharitySeeder(payable(address(gnrus))).seed(closing[shapeIndex] - 1);
        vm.etch(address(gnrus), charityCode);
        uint24 awardLevel = closing[shapeIndex];
        vm.store(address(affiliate), bytes32(PeripheralSlots.AFF_LEVEL_SCORE + uint256(awardLevel & 3)),
            bytes32((uint256(awardLevel) << 232) | (uint256(burnerId) << 163) | (uint256(1) << 128) | 1));
        if (shapeIndex >= 4) {
            // Worst x99 walk: near-final loss, final win, wallet gift, cold WWXRP entry and live boon.
            bytes memory original = address(coinflip).code;
            vm.etch(address(coinflip), type(GnrusFlipSeeder).runtimeCode);
            GnrusFlipSeeder(address(coinflip)).history(DAY - 1, 35, 1_000_000_000,
                type(uint128).max, 1, 2, 0, 38);
            vm.etch(address(coinflip), original);
            GnrusRequestCaseHost(payable(address(game))).wwxrpBoon();
            vm.prank(address(game)); wwxrp.creditPrize(3, 50);
            vm.prank(ContractAddresses.VAULT); wwxrp.vaultMintTo(ContractAddresses.GNRUS, 50);
        }
        // Every shape closes a purchase phase, so its admission carries GNRUS's buy.
        uint256 admission = Bounds.RNG_DAILY_REQUEST + Bounds.GNRUS_TICKET_PURCHASE
            + (degenesis ? Bounds.DEGENESIS_REQUEST_GAS : 0) + (redemption ? Bounds.RNG_REDEMPTION_CLOSE : 0);
        (GlamsterdamReprice.Result memory r,) = _probe(address(host), address(this),
            abi.encodeCall(host.requestOnly, (true)), admission + 1_000_000);
        _report(string.concat("request_shape_", vm.toString(shapeIndex), "_refill_", vm.toString(refill),
            "_close_", vm.toString(redemption), "_degenesis_", vm.toString(degenesis)), r, admission);
        assertLe(r.osakaExec, admission);
        assertLe(r.glamsterdamExec + r.stateGas, admission);
        assertLt(admission + 1_000_000, 10_000_000);
        // A stronger check: the entire request, including the prefix and refill, fits the reserved tail.
        if (refill) {
            assertLe(r.glamsterdamExec + r.stateGas, Bounds.VRF_DAILY_REFILL_TAIL + Bounds.GNRUS_TICKET_PURCHASE);
            (,uint96 funded,,,) = coordinator.getSubscription(1);
            assertGt(funded, 0);
        }
        if (shapeIndex == 4) {
            assertEq(wwxrp.claimable(3), 0);
            assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), 0);
            (, uint32 count) = wwxrp.incineratorInfo(100);
            assertEq(count, 1);
        }
        if (shapeIndex == 5) {
            assertEq(wwxrp.balanceOf(ContractAddresses.GNRUS), 50);
            (, uint32 count) = wwxrp.incineratorInfo(100);
            assertEq(count, 0);
        }
        assertEq(coordinator.requests(address(game)), 1);
        assertEq(game.currentLvl(), closing[shapeIndex]);
        assertEq(gnrus.currentLevel(), closing[shapeIndex]);
        assertTrue(game.rngLocked());
    }

    function test_ColdRequestShape0Flags0() public { _measureShape(0, false, false, false); }
    function test_ColdRequestShape0Flags1() public { _measureShape(0, true, false, false); }
    function test_ColdRequestShape0Flags2() public { _measureShape(0, false, true, false); }
    function test_ColdRequestShape0Flags3() public { _measureShape(0, true, true, false); }
    function test_ColdRequestShape0Flags4() public { _measureShape(0, false, false, true); }
    function test_ColdRequestShape0Flags5() public { _measureShape(0, true, false, true); }
    function test_ColdRequestShape0Flags6() public { _measureShape(0, false, true, true); }
    function test_ColdRequestShape0Flags7() public { _measureShape(0, true, true, true); }
    function test_ColdRequestShape1Flags0() public { _measureShape(1, false, false, false); }
    function test_ColdRequestShape1Flags1() public { _measureShape(1, true, false, false); }
    function test_ColdRequestShape1Flags2() public { _measureShape(1, false, true, false); }
    function test_ColdRequestShape1Flags3() public { _measureShape(1, true, true, false); }
    function test_ColdRequestShape1Flags4() public { _measureShape(1, false, false, true); }
    function test_ColdRequestShape1Flags5() public { _measureShape(1, true, false, true); }
    function test_ColdRequestShape1Flags6() public { _measureShape(1, false, true, true); }
    function test_ColdRequestShape1Flags7() public { _measureShape(1, true, true, true); }
    function test_ColdRequestShape2Flags0() public { _measureShape(2, false, false, false); }
    function test_ColdRequestShape2Flags1() public { _measureShape(2, true, false, false); }
    function test_ColdRequestShape2Flags2() public { _measureShape(2, false, true, false); }
    function test_ColdRequestShape2Flags3() public { _measureShape(2, true, true, false); }
    function test_ColdRequestShape2Flags4() public { _measureShape(2, false, false, true); }
    function test_ColdRequestShape2Flags5() public { _measureShape(2, true, false, true); }
    function test_ColdRequestShape2Flags6() public { _measureShape(2, false, true, true); }
    function test_ColdRequestShape2Flags7() public { _measureShape(2, true, true, true); }
    function test_ColdRequestShape3Flags0() public { _measureShape(3, false, false, false); }
    function test_ColdRequestShape3Flags1() public { _measureShape(3, true, false, false); }
    function test_ColdRequestShape3Flags2() public { _measureShape(3, false, true, false); }
    function test_ColdRequestShape3Flags3() public { _measureShape(3, true, true, false); }
    function test_ColdRequestShape3Flags4() public { _measureShape(3, false, false, true); }
    function test_ColdRequestShape3Flags5() public { _measureShape(3, true, false, true); }
    function test_ColdRequestShape3Flags6() public { _measureShape(3, false, true, true); }
    function test_ColdRequestShape3Flags7() public { _measureShape(3, true, true, true); }
    function test_ColdRequestShape4Flags0() public { _measureShape(4, false, false, false); }
    function test_ColdRequestShape4Flags1() public { _measureShape(4, true, false, false); }
    function test_ColdRequestShape4Flags2() public { _measureShape(4, false, true, false); }
    function test_ColdRequestShape4Flags3() public { _measureShape(4, true, true, false); }
    function test_ColdRequestShape4Flags4() public { _measureShape(4, false, false, true); }
    function test_ColdRequestShape4Flags5() public { _measureShape(4, true, false, true); }
    function test_ColdRequestShape4Flags6() public { _measureShape(4, false, true, true); }
    function test_ColdRequestShape4Flags7() public { _measureShape(4, true, true, true); }

    function test_ColdRequestShape5Flags0() public { _measureShape(5, false, false, false); }
    function test_ColdRequestShape5Flags1() public { _measureShape(5, true, false, false); }
    function test_ColdRequestShape5Flags2() public { _measureShape(5, false, true, false); }
    function test_ColdRequestShape5Flags3() public { _measureShape(5, true, true, false); }
    function test_ColdRequestShape5Flags4() public { _measureShape(5, false, false, true); }
    function test_ColdRequestShape5Flags5() public { _measureShape(5, true, false, true); }
    function test_ColdRequestShape5Flags6() public { _measureShape(5, false, true, true); }
    function test_ColdRequestShape5Flags7() public { _measureShape(5, true, true, true); }
    function test_ColdFullRequestWithGnrus() public { _fullRequest(false); }
    function test_ColdFullRefillRequestWithGnrus() public { _fullRequest(true); }
}
