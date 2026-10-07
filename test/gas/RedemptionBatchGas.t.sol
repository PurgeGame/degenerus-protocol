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

    /// @dev Forward pricing may grow a claim far beyond the submit-time wallet cap.
    /// The full custom order stays bounded by twenty boxes even at aggregate ETH scale.
    function testFuzz_ColdLargeLootboxFitsOrderBound(uint256 seed, uint128 size, bool stethOnly) public {
        uint256 amount = bound(size, 20 ether, 120_000_000 ether);
        if (stethOnly) {
            vm.deal(address(sdgnrs), 0);
            mockStETH.mint(address(sdgnrs), amount);
        } else vm.deal(address(sdgnrs), amount);
        _coolSettlementState();
        uint256 word = uint256(keccak256(abi.encode(seed))) | 2;
        uint32 aliceId = game.walletIdOf(alice);
        uint256 before = gasleft();
        vm.prank(address(sdgnrs));
        game.resolveRedemptionLootbox{value: stethOnly ? 0 : amount}(alice, aliceId, amount, word, 3000, 1);
        uint256 used = before - gasleft() + 21_000;
        assertLe(used, GasBounds.HUMAN_ENTRY_GAS + 20 * GasBounds.HUMAN_BOX_GAS);
    }

    function testFuzz_ColdWholeClaimFitsItsReservation(uint256 word, uint16 rollSeed, uint8 fundingMode) public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        uint16 roll = uint16(21 + uint256(rollSeed) % 155);
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
        bool done = sdgnrs.runRedemptionWork(settlementWord, 9_000_000).done;
        uint256 used = beforeGas - gasleft() + 21_000;
        assertTrue(done);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        uint256 chunks = _boxes((uint256(160 ether) * uint256(roll) / 100) / 2);
        assertLe(used, _declared(chunks), "whole beneficiary fits admission bound");
    }

    function _boxes(uint256 lootbox) private pure returns (uint256 count) {
        if (lootbox < 0.01 ether) return 0;
        count = (lootbox - 1) / 1 ether + 1;
        if (count > 20) count = 20;
    }
    function _declared(uint256 boxes) private pure returns (uint256) {
        return GasBounds.REDEMPTION_BASE_GAS + GasBounds.REDEMPTION_TAIL_GAS
            + (boxes == 0 ? 0 : GasBounds.HUMAN_ENTRY_GAS + boxes * GasBounds.HUMAN_BOX_GAS);
    }
    function _coldSingleClaim(uint256 base, uint16 roll, uint256 word, uint8 fundingMode, bool withEscrow)
        private returns (uint256 used, uint256 boxes)
    {
        uint32 day = _openBatchId();
        uint256 supply = sdgnrs.totalSupply();
        if (withEscrow) {
            _seedFlipBacking(1_000_000);
        }
        _burn(alice, base * supply / 10_000 ether);
        _resolve(day, roll, word);
        if (withEscrow) {
            (,,,uint96 escrow,,) = sdgnrs.redemptionBatches(day);
            assertGt(escrow, 0);
        }
        uint256 rolled = _claimBase(alice, day) * roll / 100;
        boxes = _boxes(rolled - rolled / 2);
        if (fundingMode != 0) {
            uint256 reserve = sdgnrs.pendingRedemptionEthValue();
            uint256 ethPart = fundingMode == 1 ? 0 : reserve / 7;
            vm.deal(address(sdgnrs), ethPart);
            mockStETH.mint(address(sdgnrs), reserve - ethPart);
        }
        _coolSettlementState();
        vm.prank(address(game));
        uint256 beforeGas = gasleft();
        assertTrue(sdgnrs.runRedemptionWork(settlementWord, 9_000_000).done);
        used = beforeGas - gasleft() + 21_000;
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    /// @dev Per-order calibration: the cold maximum over words, funding modes and the won-escrow
    ///      leg for beneficiaries with 0, 5, 10 and 20 custom boxes. Each stays inside its
    ///      admission, and the largest beneficiary's admission stays inside one 10M chunk.
    function test_ColdSingleBeneficiaryOrderShapes() public {
        uint256[5] memory bases = [uint256(0.01 ether), 5.7 ether, 11.4 ether, 28.5 ether, 160 ether];
        uint256[5] memory expect = [uint256(0), 5, 10, 20, 20];
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
                        assertEq(chunks, expect[s], "shape box count");
                        assertLe(used, _declared(chunks), "cold beneficiary fits its admission");
                        if (used > worst) worst = used;
                        vm.revertToState(snap);
                    }
                }
            }
            emit log_named_uint(string.concat("REDEEM cold max, boxes=", vm.toString(expect[s])), worst);
            emit log_named_uint(string.concat("REDEEM declared, boxes=", vm.toString(expect[s])), _declared(expect[s]));
        }
        // The admitted self-call keeps its whole bound after EIP-150 retention.
        uint256 head = GasBounds.REDEMPTION_BASE_GAS + GasBounds.HUMAN_ENTRY_GAS + 20 * GasBounds.HUMAN_BOX_GAS;
        assertLe(head + head / 63 + 12_000 + GasBounds.REDEMPTION_TAIL_GAS + 2_000, 10_000_000,
            "maximum beneficiary admission is one realistic chunk");
    }

    function test_ColdMaxBeneficiaryThroughRouter() public {
        uint32 day = _openBatchId();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        assertEq(_claimBase(alice, day), 160 ether);
        uint256 used = _coldRouterGas();
        emit log_named_uint("cold_maximum_redemption_router_gas", used);
        // Per-chunk: the maximum beneficiary is one indivisible chunk whose declared admission
        // bound stays inside the 10M realistic chunk limit (its actual cost is pinned against the
        // bound by testFuzz_ColdWholeClaimFitsItsReservation).
        assertLe(
            GasBounds.REDEMPTION_BASE_GAS + GasBounds.HUMAN_ENTRY_GAS + 20 * GasBounds.HUMAN_BOX_GAS + GasBounds.REDEMPTION_TAIL_GAS,
            uint256(10_000_000),
            "maximum beneficiary chunk bound"
        );
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "real maximum claim settled");
    }
    uint256 private cohortSize;

    function _queueBurners(uint256 n, uint256 amount) private returns (address[] memory players) {
        cohortSize = n;
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
        uint32 day = _openBatchId();
        address[] memory players = _queueBurners(3, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        // A 4M allowance admits two maximum beneficiaries; the third's admission no longer fits.
        emit log_named_uint("cold_two_maximum_router_gas", _coldRouterGasWith(4_000_000));
        (uint128 base,) = sdgnrs.pendingRedemptions(game.walletIdOf(players[2]), day);
        assertGt(base, 0, "next beneficiary remains whole");
        assertTrue(sdgnrs.redemptionSettlementPending());
        emit log_named_uint("cold_maximum_continuation_router_gas", _coldRouterGas());
        if (sdgnrs.redemptionSettlementPending()) _coldRouterGas();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_ColdManyMinimumBeneficiaries() public {
        uint32 day = _openBatchId();
        _queueBurners(45, 1 ether);
        _resolve(day, 175, 99);
        emit log_named_uint("cold_45_dust_router_gas", _coldRouterGas());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

    function test_ColdMaximumMiddleOfMixedBatch() public {
        uint32 day = _openBatchId();
        address[] memory players = _queueBurners(3, 1 ether);
        uint256 topup = (sdgnrs.totalSupply() + _escrow()) * 16 / 1000 - 1 ether;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, players[1], topup), topup);
        _burn(players[1], topup);
        _resolve(day, 175, 99);
        assertEq(_claimBase(players[1], day), 160 ether);
        emit log_named_uint("cold_mixed_batch_maximum_middle_gas", _coldRouterGas());
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    /// @dev The fixture records the cohort size; the public cursor measures progress.
    ///      No dependency on the alternating player lists' physical storage slots.
    function _left() private view returns (uint256) {
        return sdgnrs.redemptionSettlementPending() ? cohortSize - _redemptionCursor() : 0;
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
        uint32 day = _openBatchId();
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
