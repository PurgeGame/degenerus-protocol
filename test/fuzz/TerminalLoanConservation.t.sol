// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {SolvencyObligations} from "./helpers/SolvencyObligations.sol";
import {TerminalLoanBase} from "./TerminalLoanSettlement.t.sol";

/// @title TerminalLoanConservation -- the VRF-alive game-over loan settlement creates and loses no ETH
/// @notice A random book of loans (due levels across the horizon, each borrower either exactly
///         covered at the current repayment price or one wei short) settles at a deadline ending.
///         Across the whole settlement: Game ETH + stETH and claimablePool do not move; each
///         repaid borrower's claimable (above its sentinel) plus AFKing falls by exactly its owed
///         amount; the lenders' claimable rises by exactly the sum owed to each; a seized
///         account's balances stay where they were; every loan settles exactly once; and the
///         ending then pays out with the Game still covering every obligation.
contract TerminalLoanConservationTest is TerminalLoanBase {
    uint32 internal constant VAULT_ID = 1;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        vm.deal(address(game), 100_000 ether);
        gameRuntime = address(game).code;
        lens = new DegenerusGameLens();
        _seeder().livePurchase(5);
        _restore();
        _fund(SDGNRS_ID, 5_000 ether);
        _fund(VAULT_ID, 5_000 ether);
    }

    function _account(address who) private returns (uint32 id) {
        vm.deal(who, 1_000 ether);
        id = _giveWalletId(who);
        _seedLevel(id, 60, 4_000);
        _seedLevel(id, 102, 4_000);
    }

    function _decide() private {
        _seeder().pastDeadline();
        _restore();
        assertTrue(game.livenessTriggered(), "the deadline ending fires");
        requestAtDecision = mockVRF.lastRequestId();
    }

    function _held(uint32 id) private view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), GameSlotKeys.balances(id)));
        uint256 claimable = uint128(packed);
        return (claimable > 1 ? claimable - 1 : 0) + (packed >> 128);
    }

    function _claimableOf(uint32 id) private view returns (uint256) {
        return uint128(uint256(vm.load(address(game), GameSlotKeys.balances(id))));
    }

    struct Book {
        uint32[] ids;
        uint32[] lenders;
        bool[] covers;
        uint256[] owed;
        uint256[] heldBefore;
    }

    function testFuzz_SettlementMovesNoEth(uint256 seed) public {
        uint256 n = 6;
        Book memory b;
        b.ids = new uint32[](n);
        b.lenders = new uint32[](n);
        b.covers = new bool[](n);
        b.owed = new uint256[](n);
        b.heldBefore = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            address owner = makeAddr(string(abi.encode("conservation-borrower", i)));
            b.ids[i] = _account(owner);
            _borrow(owner, b.ids[i], uint24(2 + r % 99));
            b.owed[i] = _owedNow(b.ids[i]);
            b.lenders[i] = lens.loanOf(address(game), b.ids[i]).lenderId;
            b.covers[i] = (r >> 32) & 1 == 1;
            uint256 total = b.covers[i] ? b.owed[i] : b.owed[i] - 1;
            uint256 split = (r >> 40) % (total + 1);
            _setBalances(b.ids[i], split + 1, total - split);
        }
        _decide();
        for (uint256 i; i < n; ++i) b.heldBefore[i] = _held(b.ids[i]);
        uint256 vaultBefore = _claimableOf(VAULT_ID);
        uint256 sdgnrsBefore = _claimableOf(SDGNRS_ID);
        uint256 backingBefore = SolvencyObligations.backing(game);
        uint256 poolBefore = game.claimablePoolView();

        vm.recordLogs();
        uint256 gasCap = 800_000 + (seed % 2_000_000);
        for (uint256 calls; calls < 200 && _anyOpen(); ++calls) {
            _mine(calls == 0 ? 30_000_000 : gasCap);
            _assertNothingAheadOfLoans();
            assertEq(game.claimablePoolView(), poolBefore, "settlement never moves claimablePool");
            assertEq(SolvencyObligations.backing(game), backingBefore, "settlement never moves Game ETH");
        }
        assertFalse(_anyOpen(), "every loan settled");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 toVault;
        uint256 toSdgnrs;
        for (uint256 i; i < n; ++i) {
            (uint256 seized, uint256 repaid) = _countSettlements(logs, b.ids[i]);
            assertEq(seized + repaid, 1, "each loan settles exactly once");
            if (b.covers[i]) {
                assertEq(repaid, 1, "covered: repaid");
                assertEq(_repaidOwed(logs, b.ids[i]), b.owed[i], "at the current repayment price");
                assertEq(b.heldBefore[i] - _held(b.ids[i]), b.owed[i], "the borrower paid exactly the price");
                if (b.lenders[i] == VAULT_ID) toVault += b.owed[i];
                else toSdgnrs += b.owed[i];
            } else {
                assertEq(seized, 1, "one wei short: seized");
                assertEq(_held(b.ids[i]), b.heldBefore[i], "a seized account's balances stay put");
            }
        }
        assertEq(_claimableOf(VAULT_ID) - vaultBefore, toVault, "the Vault received exactly what it was owed");
        assertEq(_claimableOf(SDGNRS_ID) - sdgnrsBefore, toSdgnrs, "sDGNRS received exactly what it was owed");

        _driveEnding(30_000_000, true, 200);
        assertTrue(game.gameOver(), "the ending paid out");
        assertGe(SolvencyObligations.backing(game), game.claimablePoolView(), "solvent after the payout");
    }
}
