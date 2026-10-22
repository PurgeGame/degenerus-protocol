// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {TerminalLoanBase, TerminalLoanSeeder} from "./TerminalLoanSettlement.t.sol";
import {MineFlipAdmission} from "./helpers/MineFlipAdmission.sol";

/// @title TerminalLoanAdmissionWalk -- a crowded loan book settled at game over, at minimum gas
/// @notice A VRF-alive ending owes settlement of every open loan before its terminal request. The
///         book here is crowded: thirty loans due at one level (the scan's longest list) plus
///         loans spread over the borrow horizon, families of one to six accounts, each borrower
///         either covering the current repayment price exactly or one wei short. Every engine
///         call gets exactly the loan checkpoint's admission (the phase pre-check, one worst-family
///         loan, one due-level step and the loan tail, through the engine), or a random amount
///         above it: each call must progress, no terminal request may go out while a loan is
///         open, and every loan settles exactly once. The ending then runs to its paid jackpot
///         at the terminal minimum.
contract TerminalLoanAdmissionWalk is TerminalLoanBase {
    uint256 internal constant CROWDED = 30;
    uint256 internal gasSeed;
    uint256 internal loanCalls;
    uint256 internal peakLoanCall;
    /// @dev LoanSeized + LoanRepaid events per account, from successful calls only.
    mapping(uint32 => uint256) internal settlements;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        vm.deal(address(game), 200_000 ether);
        gameRuntime = address(game).code;
        lens = new DegenerusGameLens();
        _seeder().livePurchase(5);
        _restore();
        _fund(SDGNRS_ID, 50_000 ether);
    }

    function _account(address who) internal returns (uint32 id) {
        vm.deal(who, 1_000 ether);
        id = _giveWalletId(who);
        _seedLevel(id, 60, 4_000);
        _seedLevel(id, 102, 4_000);
    }

    function _child(address owner) internal returns (uint32 id) {
        uint256 price = game.mintPrice();
        vm.prank(owner);
        id = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        _seedLevel(id, 60, 4_000);
    }

    function _book(uint256 seed) internal returns (uint256 n) {
        n = CROWDED + 10;
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            address owner = makeAddr(string(abi.encode("crowded-borrower", i)));
            uint32 id = _account(owner);
            _grantSmurfBase(owner, 8);
            uint256 children = i % 6 == 0 ? 5 : (r >> 8) % 3;
            for (uint256 k; k < children; ++k) _child(owner);
            uint24 due = i < CROWDED ? 2 : uint24(3 + (r >> 16) % 98);
            _borrow(owner, id, due);
            uint256 owed = _owedNow(id);
            bool covers = (r >> 32) & 1 == 1;
            uint256 total = covers ? owed : owed - 1;
            uint256 split = (r >> 40) % (total + 1);
            _setBalances(id, split + 1, total - split);
        }
    }

    function _decideEnding() internal {
        _seeder().pastDeadline();
        _restore();
        assertTrue(game.livenessTriggered(), "the deadline ending fires");
        requestAtDecision = mockVRF.lastRequestId();
    }

    /// @dev One judged engine call. The loan checkpoint's admission while settlement is owed,
    ///      the terminal minimum otherwise.
    function _call(uint256 i) internal returns (bool) {
        uint8 a = game.nextMinerAction();
        bool owed = _loanStep() != 0;
        uint256 floor_ = owed ? MineFlipAdmission.gross(MineFlipAdmission.terminalLoanFirstUnit())
            : MineFlipAdmission.minGas(a, false);
        uint256 g = floor_;
        if (gasSeed != 0) {
            uint256 r = uint256(keccak256(abi.encode(gasSeed, i)));
            if (r % 3 != 0) g = floor_ + (r >> 8) % (30_000_000 - floor_);
        }
        vm.cool(address(game));
        vm.cool(ContractAddresses.GAME_MINER_MODULE);
        vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_GAMEOVER_MODULE);
        vm.cool(ContractAddresses.SDGNRS);
        vm.cool(ContractAddresses.QUESTS);
        vm.cool(ContractAddresses.DEITY_PASS);
        vm.recordLogs();
        uint256 before = gasleft();
        (bool ok, bytes memory ret) =
            address(game).call{gas: g}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        uint256 used = before - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // A reverted call has no effect; forge still records the logs it emitted.
        if (ok) {
            for (uint256 k; k < logs.length; ++k) {
                if (logs[k].emitter != address(game) || logs[k].topics.length < 2) continue;
                bytes32 t = logs[k].topics[0];
                if (t == LOAN_SEIZED_SIG || t == LOAN_REPAID_SIG) ++settlements[uint32(uint256(logs[k].topics[1]))];
            }
        }
        if (!ok) {
            if (a == MineFlipAdmission.WAIT && ret.length == 4 && bytes4(ret) == bytes4(keccak256("RngNotReady()"))) {
                return false;
            }
            console2.log("action", uint256(a));
            console2.log("loan settlement owed", owed);
            console2.log("gas given", g);
            console2.log("minimum", floor_);
            console2.logBytes(ret);
            fail("an engine call at or above its admission must progress");
        }
        if (owed) {
            ++loanCalls;
            if (used > peakLoanCall) peakLoanCall = used;
        }
        return true;
    }

    function _walk(uint256 seed) internal {
        uint256 n = _book(seed);
        _decideEnding();
        uint256 i;
        for (; i < 400 && _anyOpen(); ++i) {
            _call(i);
            _assertNothingAheadOfLoans();
        }
        assertFalse(_anyOpen(), "every loan settled");
        for (uint256 k; k < tracked.length; ++k) {
            assertEq(settlements[tracked[k]], 1, "each loan settles exactly once");
        }
        assertGe(loanCalls, 1, "the loan stage ran");
        console2.log("loans", n);
        console2.log("loan-stage calls", loanCalls);
        console2.log("peak loan-stage call gas", peakLoanCall);
        console2.log("loan checkpoint minimum", MineFlipAdmission.gross(MineFlipAdmission.terminalLoanFirstUnit()));
        for (uint256 k; k < 200; ++k) {
            if (game.gameOver() && _jackpotPaid()) {
                for (uint256 j; j < tracked.length; ++j) {
                    assertEq(settlements[tracked[j]], 1, "no loan settles again during the ending");
                }
                return;
            }
            _fulfillLatest();
            _call(i + k);
        }
        fail("the ending did not finish");
    }

    function test_CrowdedBookAtMinimumGas() public {
        _walk(1);
    }

    /// forge-config: default.fuzz.runs = 6
    function testFuzz_CrowdedBookRandomGas(uint256 seed) public {
        gasSeed = seed | 1;
        _walk(seed);
    }
}
