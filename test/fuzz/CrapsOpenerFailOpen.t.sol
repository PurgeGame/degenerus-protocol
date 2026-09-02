// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CrapsOpenerFailOpen — the daily crank's bare call into the craps table cannot revert.
///
/// @notice `DegenerusGameAdvanceModule.rngGate` calls `CrapsBattle.openBonusDay()` bare and
///         unwrapped on the crank that applied the day's word. The liveness argument is that the
///         callee is revert-free past its `OnlyGame` gate: a missing word returns, a repeat call
///         returns, the seven-window draw is pure over constants, and the two protocol seats are
///         funded by a banked pass or by a FLIP burn wrapped in try/catch — the house is seated
///         even unfunded, the vault is skipped. These pins drive each of those branches against
///         the REAL table, the REAL FLIP burn gate and the REAL crank, with the burns forced to
///         revert, and assert the crank still completes and the day still opens.
///
/// @dev Test-only. The revert injection uses `vm.mockCallRevert` on the FLIP burn selectors —
///      the exact failure the try/catch exists for — and is cleared after each test.
contract CrapsOpenerFailOpen is DeployProtocol {
    address internal keeper = address(0xBEEF);
    bytes internal constant BURN_SEL = abi.encodeWithSignature("burnCoin(address,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
        vm.deal(keeper, 1_000 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    // ------------------------------------------------------------------------------------
    // The real heartbeat: warp a day, buy the daily gate, request, fulfil, apply.
    // ------------------------------------------------------------------------------------

    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }

    function _fulfilPending(uint256 seed) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("opener", seed, reqId))) | 1);
    }

    /// @dev Drive one full day through `advanceGame` and return whether the craps day opened on
    ///      it. Only the crank's two "nothing to do" gates (`NotTimeYet`, `RngNotReady`) are
    ///      tolerated; any other revert is bubbled — that revert IS the failure these pins exist
    ///      to catch.
    function _driveDay(uint256 seed) internal returns (bool opened) {
        vm.warp(_dayStart() + 1 days + 5 minutes);
        (,,,, uint256 priceWei) = game.purchaseInfo();
        vm.prank(keeper);
        game.purchase{value: priceWei}(keeper, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        for (uint256 i; i < 6; i++) {
            _crank();
            if (game.rngLocked()) break;
        }
        for (uint256 i; i < 6; i++) {
            _fulfilPending(seed + i);
            _crank();
            if (!game.rngLocked() && _crapsDayOpen()) break;
        }
        opened = _crapsDayOpen();
    }

    function _crank() internal {
        vm.prank(keeper);
        try game.advanceGame() {}
        catch (bytes memory err) {
            bytes4 sel = bytes4(err);
            if (sel == bytes4(keccak256("NotTimeYet()")) || sel == bytes4(keccak256("RngNotReady()"))) return;
            assembly {
                revert(add(err, 0x20), mload(err))
            }
        }
    }

    function _crapsDayOpen() internal view returns (bool) {
        (uint24 opened,) = crapsBattle.bonusDayOf();
        return opened == crapsBattle.currentDayIndex() && crapsBattle.dailyWordAt(opened) != 0;
    }

    // ------------------------------------------------------------------------------------
    // Pins
    // ------------------------------------------------------------------------------------

    /// @notice No word for today: the opener returns and opens nothing. It never reverts.
    function test_openerReturnsWithoutAWordAndOpensNothing() public {
        uint24 today = crapsBattle.currentDayIndex();
        assertEq(crapsBattle.dailyWordAt(today), 0, "fixture: today must have no word");
        (uint24 before,) = crapsBattle.bonusDayOf();
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();
        (uint24 after_,) = crapsBattle.bonusDayOf();
        assertEq(after_, before, "a wordless day must not open");
        assertEq(crapsBattle.dayTicketsOf(today), 0, "a wordless day seats nobody");
    }

    /// @notice The crank opens the day once; a second call on the same day is a no-op.
    function test_openerIsIdempotentWithinADay() public {
        assertTrue(_driveDay(1), "the crank must open the craps day");
        uint24 today = crapsBattle.currentDayIndex();
        uint256 seatsBefore = crapsBattle.dayTicketsOf(today);
        uint256 houseSeat = crapsBattle.daySeatNumberOf(today, ContractAddresses.SDGNRS);
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();
        assertEq(crapsBattle.dayTicketsOf(today), seatsBefore, "a repeat open must seat nobody new");
        assertEq(crapsBattle.daySeatNumberOf(today, ContractAddresses.SDGNRS), houseSeat, "the house seat must not move");
    }

    /// @notice Both protocol bodies hold no pass and their FLIP burns REVERT: the crank still
    ///         completes, the day still opens, the house is seated unfunded, the vault is skipped.
    function test_crankSurvivesBothProtocolBurnsReverting() public {
        crapsBattle.setPassCredits(ContractAddresses.SDGNRS, 0, 0);
        crapsBattle.setPassCredits(ContractAddresses.VAULT, 0, 0);
        vm.mockCallRevert(address(coin), BURN_SEL, "burn refused");

        assertTrue(_driveDay(2), "the crank must open the craps day with every protocol burn reverting");
        uint24 today = crapsBattle.currentDayIndex();
        assertGt(crapsBattle.daySeatNumberOf(today, ContractAddresses.SDGNRS), 0, "the house is seated even unfunded");
        assertEq(crapsBattle.daySeatNumberOf(today, ContractAddresses.VAULT), 0, "an unfunded vault is skipped, not reverted");
        (uint256 hn, uint256 hh) = crapsBattle.passCreditsOf(ContractAddresses.SDGNRS);
        assertEq(hn + hh, 0, "no pass was conjured for the house");

        vm.clearMockedCalls();
    }

    /// @notice The banked-pass branch: with one normal pass each, both bodies seat by pass and
    ///         the burn gate is never reached — proven by leaving the burn reverting.
    function test_openerSeatsBothBodiesByPassWithTheBurnReverting() public {
        crapsBattle.setPassCredits(ContractAddresses.SDGNRS, 1, 0);
        crapsBattle.setPassCredits(ContractAddresses.VAULT, 1, 0);
        vm.mockCallRevert(address(coin), BURN_SEL, "burn refused");

        assertTrue(_driveDay(3), "the crank must open the craps day");
        uint24 today = crapsBattle.currentDayIndex();
        assertGt(crapsBattle.daySeatNumberOf(today, ContractAddresses.SDGNRS), 0, "the house seats by pass");
        assertGt(crapsBattle.daySeatNumberOf(today, ContractAddresses.VAULT), 0, "the vault seats by pass");
        (uint256 hn,) = crapsBattle.passCreditsOf(ContractAddresses.SDGNRS);
        (uint256 vn,) = crapsBattle.passCreditsOf(ContractAddresses.VAULT);
        assertEq(hn, 0, "the house pass was spent");
        assertEq(vn, 0, "the vault pass was spent");

        vm.clearMockedCalls();
    }

    /// @notice Two consecutive days with the burn gate dead the whole time: the crank never
    ///         stalls and each day opens exactly once.
    function test_twoDaysWithTheBurnGateDead() public {
        crapsBattle.setPassCredits(ContractAddresses.SDGNRS, 0, 0);
        crapsBattle.setPassCredits(ContractAddresses.VAULT, 0, 0);
        vm.mockCallRevert(address(coin), BURN_SEL, "burn refused");

        assertTrue(_driveDay(4), "day one opens");
        uint24 d1 = crapsBattle.currentDayIndex();
        assertTrue(_driveDay(5), "day two opens");
        uint24 d2 = crapsBattle.currentDayIndex();
        assertEq(d2, d1 + 1, "the crank advanced a full day");
        assertGt(crapsBattle.daySeatNumberOf(d2, ContractAddresses.SDGNRS), 0, "the house is seated on day two");

        vm.clearMockedCalls();
    }
}
