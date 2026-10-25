// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../../helpers/OwnerTargetCall.sol";

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {AnyInputHandler, IAnyBalance} from "../handlers/AnyInputHandler.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {AnyInputSafety} from "./AnyInputSafety.inv.t.sol";

/// @title AnyInputSafetyDegenesis -- any-input safety, conservation and liveness after a real Degenesis
///        week (turbo launch)
/// @notice The base suite's fixture (actors, deities, bystander, custom battle, loans, auto-rebuy) is built
///         on the game a busy sale left at level 1; the campaign then runs every door, including the two
///         Degenesis buy doors, which refuse after the sale.
contract AnyInputSafetyDegenesis is AnyInputSafety, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    /// @dev Own counter keys, so the coverage and non-vacuity floors count this suite's runs, not the parent's.
    function _counterKey(string memory k) internal pure override returns (string memory) {
        return string.concat("DGT_", k);
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        dgvf = vm.computeCreateAddress(address(vault), 1);
        dgve = vm.computeCreateAddress(address(vault), 2);

        for (uint256 i; i < N_ACTORS; ++i) {
            address a = address(uint160(0xA11CE000 + i));
            actors.push(a);
            vm.deal(a, 1_000 ether);
        }
        vm.deal(BYSTANDER, 100 ether);

        // ---------------- actors: holdings that make the burn/transfer doors reachable ----------------
        uint256 dgveSupply = IAnyBalance(dgve).balanceOf(ContractAddresses.CREATOR);
        uint256 dgvfSupply = IAnyBalance(dgvf).balanceOf(ContractAddresses.CREATOR);
        for (uint256 i; i < N_ACTORS; ++i) {
            address a = actors[i];
            if (i < N_SEEDED) {
                vm.prank(a);
                game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0)); // seat + sDGNRS + far-future entries
            }
            // 0.5% of sDGNRS supply each, so a wrapped burn can clear the 0.01 ETH redemption floor.
            _dgnrsFromVault(a, 5_000_000_000e12);
            vm.startPrank(ContractAddresses.CREATOR);
            _erc20Transfer(dgve, a, dgveSupply / 100);
            _erc20Transfer(dgvf, a, dgvfSupply / 100);
            vm.stopPrank();
            vm.startPrank(address(game));
            coin.mintForGame_g152734(a, 1_000_000);
            wwxrp.mintPrize(a, 100_000);
            vm.stopPrank();
        }
        // Actors approve each other (never the bystander, which approves nobody): game operator
        // approval and max ERC20 allowances, so on-behalf doors and transferFrom are reachable.
        for (uint256 i; i < N_ACTORS; ++i) {
            vm.startPrank(actors[i]);
            for (uint256 j; j < N_ACTORS; ++j) {
                if (i == j) continue;
                if (i < N_SEEDED) game.setOperatorApproval(0, actors[j], true); // fresh actors hold no wallet ID yet
                coin.approve(actors[j], type(uint256).max);
                dgnrs.approve(actors[j], type(uint256).max);
                (bool ok1,) = dgve.call(abi.encodeWithSignature("approve(address,uint256)", actors[j], type(uint256).max));
                (bool ok2,) = dgvf.call(abi.encodeWithSignature("approve(address,uint256)", actors[j], type(uint256).max));
                require(ok1 && ok2, "fixture: share approvals");
            }
            vm.stopPrank();
        }
        // Deity holders (actors 0, 2, 4) so giveBoon / smite / decurse are reachable.
        vm.prank(actors[0]);
        game.purchaseDeityPass{value: 45 ether}(0, 3, bytes32(0));
        vm.prank(actors[2]);
        game.purchaseDeityPass{value: 45 ether}(0, 4, bytes32(0));
        vm.prank(actors[4]);
        game.purchaseDeityPass{value: 45 ether}(0, 7, bytes32(0));
        // Vault-owner configuration: charity slots naming actors (GNRUS vote / burn reachable) and
        // three craps battle creators (createBattle reachable).
        vm.startPrank(ContractAddresses.OWNER_GOVERNANCE);
        for (uint256 s = 3; s < 6; ++s) {
            try gnrus.setCharity(uint8(s), actors[s]) {} catch {}
        }
        for (uint256 i; i < 3; ++i) {
            (bool okC,) = address(crapsBattle).call(abi.encodeWithSignature("setBattleCreator(address,bool)", actors[i], true));
            require(okC, "fixture: battle creator");
        }
        vm.stopPrank();
        // One long-lived custom battle, so enterBattle/donate/closeBattle have a live target early.
        vm.prank(actors[0]);
        (bool okB,) = address(crapsBattle).call(abi.encodeWithSignature(
            "createBattle(uint32,uint8,uint16,uint24,uint40,bool,uint16)",
            uint32(600), uint8(5), uint16(10), uint24(2), uint40(block.timestamp + 6 days), true, uint16(10)));
        require(okB, "fixture: custom battle");

        // ---------------- bystander: normal flows only, then it never acts again ----------------
        vm.startPrank(BYSTANDER);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));
        game.depositAfkingFunding{value: 5 ether}(game.walletIdOf_g3120(BYSTANDER));
        game.purchaseDeityPass{value: 45 ether}(0, 5, bytes32(0)); // overpay lands in its own afking
        (,,,, uint256 priceWei) = game.purchaseInfo_g1027();
        game.purchaseOrderFor{value: priceWei * 10}(0, 4000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        vm.stopPrank();
        _dgnrsFromVault(BYSTANDER, 1_000_000e12);
        vm.startPrank(ContractAddresses.CREATOR);
        _erc20Transfer(dgve, BYSTANDER, dgveSupply / 200);
        _erc20Transfer(dgvf, BYSTANDER, dgvfSupply / 200);
        vm.stopPrank();
        vm.startPrank(actors[1]);
        coin.transfer(BYSTANDER, 50_000);
        wwxrp.transfer(BYSTANDER, 5_000);
        vm.stopPrank();

        // ---------------- process day 1 so dailies, words and the craps day exist ----------------
        _driveDay(1);
        // Account loans: sDGNRS lends only from its own claimable (empty this early), so the
        // vault owner enables the vault fallback and an actor funds the vault's prepaid afking
        // (permissionless depositAfkingFunding). Both are ordinary flows.
        uint32 vaultId = game.walletIdOf_g3120(address(vault));
        vm.prank(actors[5]);
        game.depositAfkingFunding{value: 20 ether}(vaultId);
        vm.prank(ContractAddresses.CREATOR);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.setLiquidationBuyFallback, (true, 0)), 0);
        _bystanderClaimable();
        // Two actors run coinflip auto-rebuy, so the carry / take-profit doors have a live subject.
        for (uint256 i = 1; i < 4; i += 2) {
            vm.prank(actors[i]);
            try coinflip.setCoinflipAutoRebuy(0, true, 0) {} catch {
                console.log("fixture: auto-rebuy refused for actor", i);
            }
        }

        for (uint256 id = 1; id < afkingSubToken.nextSerial(); ++id) {
            if (afkingSubToken.ownerOf(id) == BYSTANDER) bystanderSeat = id;
        }
        require(bystanderSeat != 0, "fixture: bystander has no seat");

        handler = new AnyInputHandler(game, mockVRF, mockStETH, actors, BYSTANDER, bystanderSeat, dgve, dgvf);
        baseline = handler.holdings();
        _buildTracked();
        startTotal = _trackedTotal();

        targetContract(address(handler));
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: _selectors()}));
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}
