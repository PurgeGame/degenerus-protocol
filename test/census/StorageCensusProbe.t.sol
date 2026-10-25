// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {StorageCensus} from "./StorageCensus.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title StorageCensusProbe -- smoke test of the census collector on a few real transactions
contract StorageCensusProbeTest is StorageCensus {
    function setUp() public {
        _deployProtocol();
    }

    function testProbeCensusMechanics() public {
        _censusBegin("probe");
        address p = address(0xB0B);
        vm.deal(p, 1000 ether);
        uint256 t = vm.getBlockTimestamp();
        for (uint256 day; day < 3; ++day) {
            t += 1 days + 1;
            vm.warp(t);
            (,,,, uint256 priceWei) = game.purchaseInfo_g1027();
            uint256 cost = priceWei * 10 + 1 ether;
            (bool ok,) = _ctx("purchase", false, p, address(game), cost, abi.encodeCall(
                game.purchaseOrderFor, (uint32(0), 4000, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false)
            ));
            assertTrue(ok, "purchase");
            _cMineAll(80, day);
        }
        _censusEnd();
        assertGt(censusCreates, 0, "no creations recorded");
    }
}
