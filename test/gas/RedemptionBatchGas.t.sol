// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {AutomaticRedemptionSettlementTest} from "../fuzz/AutomaticRedemptionSettlement.t.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract RedemptionBatchGasTest is AutomaticRedemptionSettlementTest {
    function _coolSettlementState() internal {
        vm.cool(address(game));
        vm.cool(address(sdgnrs));
        vm.cool(address(coinflip));
        vm.cool(address(mockStETH));
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
    }

    function testFuzz_ColdWholeClaimFitsItsReservation(uint256 word, uint16 rollSeed, uint8 fundingMode) public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        uint16 roll = uint16(25 + uint256(rollSeed) % 151);
        _resolve(day, roll, word > 1 ? word : 99);
        if (fundingMode % 3 != 0) {
            uint256 reserve = sdgnrs.pendingRedemptionEthValue();
            uint256 ethPart = fundingMode % 3 == 1 ? 0 : reserve / 7;
            vm.deal(address(sdgnrs), ethPart);
            mockStETH.mint(address(sdgnrs), reserve - ethPart);
        }
        _coolSettlementState();
        vm.prank(address(game));
        uint256 beforeGas = gasleft();
        bool done = sdgnrs.runRedemptionWork(9_000_000).done;
        uint256 used = beforeGas - gasleft() + 21_000;
        assertTrue(done);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        uint256 chunks = ((uint256(160 ether) * uint256(roll) / 100) / 2 + 5 ether - 1) / 5 ether;
        assertLe(used, _declared(chunks), "whole beneficiary fits admission bound");
    }

    /// @dev The admission a beneficiary with `chunks` lootbox chunks is charged, plus the tail.
    function _declared(uint256 chunks) private pure returns (uint256) {
        return GasBounds.REDEMPTION_BASE_GAS + chunks * GasBounds.REDEMPTION_CHUNK_GAS + GasBounds.REDEMPTION_TAIL_GAS;
    }

    /// @dev One cold beneficiary of `base` ETH at `roll`, settled alone. `fundingMode` 1 funds the
    ///      reserve all in stETH, 2 mixes 1/7 ETH; `escrowWin` gives the claim a won FLIP escrow.
    function _coldSingleClaim(uint256 base, uint16 roll, uint256 word, uint8 fundingMode, bool escrowWin)
        private returns (uint256 used, uint256 chunks)
    {
        uint24 day = game.currentDayView();
        uint256 supply = sdgnrs.totalSupply();
        (uint256 freeBacking,) = sdgnrs.previewBurnValue(supply);
        if (escrowWin) {
            vm.mockCall(address(coinflip), abi.encodeWithSignature("redeemableFlipBacking()"), abi.encode(uint256(1e33)));
            vm.mockCall(address(coinflip), abi.encodeWithSignature("withdrawRedeemedFlip(uint256)"), "");
        }
        _burn(alice, (base * supply + freeBacking - 1) / freeBacking);
        vm.clearMockedCalls();
        if (escrowWin) {
            (,, uint96 escrow) = sdgnrs.pendingRedemptions(alice, day);
            assertGt(escrow, 0, "escrow variant carries FLIP escrow");
            vm.mockCall(address(coinflip), abi.encodeWithSignature("getCoinflipDayResult(uint24)", day + 1),
                abi.encode(uint16(150), true));
        }
        (uint96 owed,,) = sdgnrs.pendingRedemptions(alice, day);
        uint256 rolled = uint256(owed) * roll / 100;
        uint256 lootbox = rolled - rolled / 2;
        chunks = lootbox < 0.01 ether ? 0 : (lootbox - 1) / 5 ether + 1;
        _resolve(day, roll, word);
        if (fundingMode != 0) {
            uint256 reserve = sdgnrs.pendingRedemptionEthValue();
            uint256 ethPart = fundingMode == 1 ? 0 : reserve / 7;
            vm.deal(address(sdgnrs), ethPart);
            mockStETH.mint(address(sdgnrs), reserve - ethPart);
        }
        _coolSettlementState();
        vm.prank(address(game));
        uint256 beforeGas = gasleft();
        assertTrue(sdgnrs.runRedemptionWork(9_000_000).done);
        used = beforeGas - gasleft() + 21_000;
        vm.clearMockedCalls();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "claim settled");
    }

    /// @dev Per-chunk calibration: the cold maximum over words, funding modes and the won-escrow
    ///      leg for beneficiaries with 0, 1, 2 and 28 lootbox chunks. Each stays inside its
    ///      admission, and the largest beneficiary's admission stays inside one 10M chunk.
    function test_ColdSingleBeneficiaryChunkShapes() public {
        uint256[5] memory bases = [uint256(0.01 ether), 5.7 ether, 11.4 ether, 28.5 ether, 160 ether];
        uint256[5] memory expect = [uint256(0), 1, 2, 5, 28];
        for (uint256 s; s < 5; ++s) {
            uint256 worst;
            uint256 words = s == 4 ? 12 : s == 3 ? 24 : 48;
            for (uint256 w; w < words; ++w) {
                for (uint8 mode; mode < 3; ++mode) {
                    for (uint256 e; e < 2; ++e) {
                        uint256 snap = vm.snapshotState();
                        (uint256 used, uint256 chunks) = _coldSingleClaim(
                            bases[s], 175, uint256(keccak256(abi.encode("chunk shape", s, w))), mode, e == 1
                        );
                        assertEq(chunks, expect[s], "shape chunk count");
                        assertLe(used, _declared(chunks), "cold beneficiary fits its admission");
                        if (used > worst) worst = used;
                        vm.revertToState(snap);
                    }
                }
            }
            emit log_named_uint(string.concat("REDEEM cold max, chunks=", vm.toString(expect[s])), worst);
            emit log_named_uint(string.concat("REDEEM declared, chunks=", vm.toString(expect[s])), _declared(expect[s]));
        }
        // The admitted self-call keeps its whole bound after EIP-150 retention.
        uint256 head = GasBounds.REDEMPTION_BASE_GAS + 28 * GasBounds.REDEMPTION_CHUNK_GAS;
        assertLe(head + head / 63 + 12_000 + GasBounds.REDEMPTION_TAIL_GAS + 2_000, 10_000_000,
            "maximum beneficiary admission is one realistic chunk");
    }

    function test_ColdMaxBeneficiaryThroughRouter() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        (uint96 base,,) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(base, 160 ether);
        _resolve(day, 175, 99);
        uint256 used = _coldRouterGas();
        emit log_named_uint("cold_maximum_redemption_router_gas", used);
        // Per-chunk: the maximum beneficiary is one indivisible chunk whose declared admission
        // bound stays inside the 10M realistic chunk limit (its actual cost is pinned against the
        // bound by testFuzz_ColdWholeClaimFitsItsReservation).
        assertLe(
            GasBounds.REDEMPTION_BASE_GAS + 28 * GasBounds.REDEMPTION_CHUNK_GAS + GasBounds.REDEMPTION_TAIL_GAS,
            uint256(10_000_000),
            "maximum beneficiary chunk bound"
        );
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "real maximum claim settled");
    }
    function _queueBurners(uint256 n, uint256 amount) private returns (address[] memory players) {
        players = new address[](n);
        for (uint256 i; i < n; ++i) {
            players[i] = address(uint160(0xC01000 + i));
            vm.prank(address(game));
            assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, players[i], amount), amount);
            _burn(players[i], amount);
        }
    }

    /// @dev One cold keeper call with a realistic 10M allowance: it must succeed and make progress.
    ///      The engine keeps admitting chunks while the allowance covers the next declared bound, so
    ///      the whole call's gas is reported, not bounded; per-chunk bounds are asserted separately.
    function _coldRouterGas() private returns (uint256 used) {
        used = _coldRouterGasWith(10_000_000);
    }

    function _coldRouterGasWith(uint256 allowance) private returns (uint256 used) {
        _coolSettlementState();
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: allowance}();
        used = beforeGas - gasleft() + 21_000;
    }

    function test_ColdMultipleMaximumBeneficiariesAndContinuation() public {
        uint24 day = game.currentDayView();
        address[] memory players = _queueBurners(3, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        // A 4M allowance admits two maximum beneficiaries; the third's admission no longer fits.
        emit log_named_uint("cold_two_maximum_router_gas", _coldRouterGasWith(4_000_000));
        (uint96 base,,) = sdgnrs.pendingRedemptions(players[2], day);
        assertGt(base, 0, "next beneficiary remains whole");
        assertTrue(sdgnrs.redemptionSettlementPending());
        emit log_named_uint("cold_maximum_continuation_router_gas", _coldRouterGas());
        if (sdgnrs.redemptionSettlementPending()) _coldRouterGas();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_ColdManyMinimumBeneficiaries() public {
        uint24 day = game.currentDayView();
        _queueBurners(45, 1 ether);
        _resolve(day, 175, 99);
        emit log_named_uint("cold_45_dust_router_gas", _coldRouterGas());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

    function test_ColdMaximumMiddleOfMixedBatch() public {
        uint24 day = game.currentDayView();
        address[] memory players = _queueBurners(3, 1 ether);
        (uint96 prior,,) = sdgnrs.pendingRedemptions(players[1], day);
        uint256 supply = sdgnrs.totalSupply();
        (uint256 freeBacking,) = sdgnrs.previewBurnValue(supply);
        uint256 topup = ((160 ether - prior) * supply + freeBacking - 1) / freeBacking;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, players[1], topup), topup);
        _burn(players[1], topup);
        (uint96 base,,) = sdgnrs.pendingRedemptions(players[1], day);
        assertEq(base, 160 ether);
        _resolve(day, 175, 99);
        emit log_named_uint("cold_mixed_batch_maximum_middle_gas", _coldRouterGas());
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    /// @dev Beneficiaries still queued in the live cohort (`_redemptionPlayers.length` at slot 9
    ///      minus the cursor); zero once the cohort is cleared.
    function _left() private view returns (uint256) {
        return uint256(vm.load(address(sdgnrs), bytes32(uint256(9)))) - _redemptionCursor();
    }

    /// @dev Settle the cohort through Redemption-stage steps until exactly one beneficiary is left:
    ///      large steps while they keep one claim queued, then single-claim steps.
    function _drainToLastClaim() private {
        uint256 allowance = 9_000_000;
        while (_left() > 1) {
            uint256 before = _left();
            uint256 snap = vm.snapshotState();
            vm.prank(address(game));
            _process(allowance);
            if (sdgnrs.redemptionSettlementPending() && _left() >= 1 && _left() < before) continue;
            assertTrue(vm.revertToState(snap));
            if (allowance > 1_000_000) allowance /= 2;
            else _settleOneClaim();
        }
        assertEq(_left(), 1, "harness: one beneficiary left");
    }

    /// @dev The call that settles a cohort's last beneficiary also clears the cohort. That clear
    ///      must not rescan the beneficiaries already consumed: the finishing router call for a
    ///      2,000-claim cohort costs what it costs for a 2-claim cohort.
    function test_ColdLongCohortFinishClearsInConstantTime() public {
        uint24 day = game.currentDayView();
        uint256 snap = vm.snapshotState();
        _queueBurners(2, 1 ether);
        _resolve(day, 100, 99);
        _drainToLastClaim();
        uint256 shortFinish = _coldRouterGas();
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertTrue(vm.revertToState(snap));

        _queueBurners(2000, 1 ether);
        _resolve(day, 100, 99);
        _drainToLastClaim();
        uint256 used = _coldRouterGas();
        emit log_named_uint("cold_2_claim_cohort_finish_router_gas", shortFinish);
        emit log_named_uint("cold_2000_claim_cohort_finish_router_gas", used);
        assertLe(used, 500_000, "the finishing call stays small");
        assertLe(used, shortFinish + 5_000, "cleanup must not rescan already-consumed beneficiaries");
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

}
