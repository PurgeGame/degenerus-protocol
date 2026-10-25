// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {BoundedDeployProtocol} from "../helpers/BoundedDeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

contract BoundedIssuerViewSeed is DegenerusGameStorage {
    function seedPools(uint24 day) external {
        for (uint32 issuer = VAULT_WALLET_ID; issuer <= SDGNRS_WALLET_ID; ++issuer) {
            uint256 index = _protocolBoonIndex(issuer);
            protocolBoonPools[index][day & 1] = ProtocolBoonPool(123, 456, 1, 0, day);
            protocolBoonEntries[index][day & 1][0] = ProtocolBoonEntry(1000 + issuer, 456, 1200);
        }
    }
}

contract BoundedPublicViewBoundsTest is BoundedDeployProtocol {
    function setUp() public { _deployBounded(true); }

    function test_AllInvalidGovernanceSlotsStillReturnZero() public view {
        for (uint256 slot = 20; slot <= type(uint8).max; ++slot) {
            assertEq(gnrus.slotApproveWeight(gnrus.currentLevel(), uint8(slot)), 0);
        }
    }

    function test_AllInvalidDrawBucketsStillReturnZero() public view {
        uint24 day = game.currentDayView_g542950();
        for (uint256 bucket = 10; bucket <= type(uint8).max; ++bucket) {
            (uint256 raw, uint256 total, uint32 count) = wwxrp.bucketInfo(day, uint8(bucket));
            assertEq(raw, 0); assertEq(total, 0); assertEq(count, 0);
            (uint32 id, uint256 cumulative) = wwxrp.entryAt(day, uint8(bucket), 0);
            assertEq(id, 0); assertEq(cumulative, 0);
        }
    }

    function test_InvalidIssuerDoesNotAliasEitherFundedPool() public {
        uint24 day = game.currentDayView_g542950();
        bytes memory original = address(game).code;
        vm.etch(address(game), vm.getDeployedCode("BoundedPublicViewBounds.t.sol:BoundedIssuerViewSeed"));
        BoundedIssuerViewSeed(address(game)).seedPools(day);
        vm.etch(address(game), original);
        DegenerusGameLens lens = DegenerusGameLens(deployCode("DegenerusGameLens.sol:DegenerusGameLens"));
        assertEq(lens.protocolBoonPool(address(game), address(vault), day).entryCount, 1);
        assertEq(lens.protocolBoonPool(address(game), address(sdgnrs), day).entryCount, 1);
        assertEq(lens.protocolBoonEntryAt(address(game), address(vault), day, 0).playerId, 1001);
        assertEq(lens.protocolBoonEntryAt(address(game), address(sdgnrs), day, 0).playerId, 1002);
        address[3] memory invalid = [address(0), address(0xA11CE), address(game)];
        for (uint256 i; i < invalid.length; ++i) {
            assertEq(lens.protocolBoonPool(address(game), invalid[i], day).entryCount, 0);
            assertEq(lens.protocolBoonPool(address(game), invalid[i], day).totalWeight, 0);
            assertEq(lens.protocolBoonEntryAt(address(game), invalid[i], day, 0).playerId, 0);
        }
    }

    function test_IneligibleHeroQuadrantsRemainZero() public view {
        for (uint256 quadrant = 3; quadrant <= type(uint8).max; ++quadrant) {
            assertEq(game.getDailyHeroWager(game.currentDayView_g542950(), uint8(quadrant), 7), 0);
        }
        assertEq(game.getDailyHeroWager(game.currentDayView_g542950(), 0, 8), 0);
        assertEq(game.getDailyHeroWager(game.currentDayView_g542950(), 0, 255), 0);
    }
}
