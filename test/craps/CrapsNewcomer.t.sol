// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CrapsNewcomerTest is CrapsPins {
    CrapsViews private table;
    address private player = address(0xA11CE);

    function setUp() public {
        _installPins();
        table = new CrapsViews();
        game.setLevel(10);
        game.setMintHistory(player, 0);
        // An aggregate score read must never be needed, even at entry or amendment.
        vm.mockCallRevert(
            ContractAddresses.GAME, abi.encodeWithSignature("playerActivityScore(address)", player), "score read"
        );
    }

    function test_recentMintAndLifetimeBoundaries() public {
        assertEq(table.entryPrice(player, 8_000 ether), 8_400 ether);
        game.setMintHistory(player, uint256(2) << 24 | 8);
        assertEq(table.entryPrice(player, 8_000 ether), 8_400 ether);
        game.setMintHistory(player, uint256(1) << 24 | 9);
        assertEq(table.entryPrice(player, 8_000 ether), 8_000 ether);
        game.setMintHistory(player, uint256(1) << 24 | 10);
        assertEq(table.entryPrice(player, 8_000 ether), 8_000 ether);
        game.setMintHistory(player, uint256(1) << 24 | 11);
        assertEq(table.entryPrice(player, 8_000 ether), 8_000 ether);
        game.setMintHistory(player, uint256(3) << 24 | 1);
        assertEq(table.entryPrice(player, 8_000 ether), 8_000 ether);
        game.setLevel(type(uint24).max);
        assertEq(table.entryPrice(player, 8_000 ether), 8_000 ether);
    }

    function test_emptyRecordNeverQualifiesAtStartup() public {
        for (uint24 level; level < 3; ++level) {
            game.setLevel(level);
            assertEq(table.entryPrice(player, 25_000 ether), 26_250 ether);
        }
    }

    function test_deityAndCreditedPassQualifyImmediately() public {
        game.setMintHistory(player, uint256(1) << 184);
        assertEq(table.entryPrice(player, 500_000 ether), 500_000 ether);
        game.setMintHistory(player, uint256(10) << 24);
        assertEq(table.entryPrice(player, 500_000 ether), 500_000 ether);
        game.setMintHistory(player, uint256(100) << 24);
        assertEq(table.entryPrice(player, 500_000 ether), 500_000 ether);
    }

    function test_activityScoreDoesNotQualifyANewcomer() public {
        game.setScore(player, type(uint256).max);
        assertEq(table.entryPrice(player, 500_000 ether), 525_000 ether);
    }

    function test_levelIsNotReadForEstablishedDeityOrUnmintedAccounts() public {
        vm.mockCallRevert(ContractAddresses.GAME, abi.encodeWithSignature("level()"), "unnecessary level read");
        game.setMintHistory(player, uint256(3) << 24);
        assertEq(table.entryPrice(player, 25_000 ether), 25_000 ether);
        game.setMintHistory(player, uint256(1) << 184);
        assertEq(table.entryPrice(player, 25_000 ether), 25_000 ether);
        game.setMintHistory(player, 0);
        assertEq(table.entryPrice(player, 25_000 ether), 26_250 ether);
    }

    function test_futureNormalAndHighPurchasesPayFivePercent() public {
        uint24 tomorrow = table.currentDayIndex() + 1;
        vm.prank(player);
        table.buyFutureCrapsDays(tomorrow, 2, false, 0);
        assertEq(flip.burned(player), 52_500 ether);
        vm.prank(player);
        table.buyFutureCrapsDays(tomorrow + 2, 1, true, 0);
        assertEq(flip.burned(player), 577_500 ether);
        assertEq(flip.crapsBurns(), 2, "one burn and quest report per purchase");
    }

    function test_singleEntryStoresNoScoreAndAmendmentDoesNotReadIt() public {
        uint64 slot = _openBattle(table, 300, 2, 5, 3);
        vm.prank(player);
        uint256 id = table.enterBattle(slot, uint32(0), 1);
        assertEq(flip.burned(player), 945 ether);
        assertEq((table.betWordOf(id) >> 190) & 0xFFFF, 0);
        vm.prank(player);
        table.amendSlip(id, uint32(1));
        assertEq((table.betWordOf(id) >> 190) & 0xFFFF, 0);
        assertEq(flip.burned(player), 945 ether);
    }

    function test_compedEntitlementHasNoNewcomerSurcharge() public {
        vm.mockCallRevert(
            ContractAddresses.GAME, abi.encodeWithSignature("mintPackedFor(address)", player), "unnecessary history read"
        );
        uint24 tomorrow = table.currentDayIndex() + 1;
        flip.setCompLane(25_000 ether);
        uint256 code = uint160(player) | (uint256(2) << 160) | (uint256(tomorrow) << 176) | (uint256(1) << 200);
        vm.prank(ContractAddresses.VAULT);
        assertEq(table.vaultComp(code), 25_000 ether);
        assertEq(flip.compSpent(), 25_000 ether);
        assertEq(flip.burned(player), 0);
    }

    function testFuzz_recentLevelComparisonDoesNotWrap(uint24 current, uint24 last) public {
        game.setLevel(current);
        game.setMintHistory(player, uint256(last));
        bool recent = last != 0 && uint256(last) + 1 >= uint256(current);
        assertEq(table.entryPrice(player, 25_000 ether), recent ? 25_000 ether : 26_250 ether);
    }
}
