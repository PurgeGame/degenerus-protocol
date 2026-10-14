// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusDeityPass} from "../../contracts/DegenerusDeityPass.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @dev Etched over the Game: fund lenders, seed collateral, end the game, or jump to a due level
///      and arm its seizure exactly as `prepareRequestBoundary` does.
contract SeizureSeeder is DegenerusGameStorage {
    function fund(uint32 id, uint128 claimable) external {
        balancesPacked[id] += claimable;
        claimablePool += claimable;
    }
    function setClaimable(uint32 id, uint128 claimable) external {
        uint256 old = balancesPacked[id];
        claimablePool = claimablePool - uint128(old) + claimable;
        balancesPacked[id] = (old >> 128 << 128) | claimable;
    }
    function seedLevel(uint32 id, uint24 level_, uint32 entries) external { _queueEntries(id, level_, entries, false); }
    function end() external { gameOver = true; }
    function enterDue(uint24 due) external {
        level = due;
        if (_loansDueCount[due] != 0) {
            _setLoansDuePending(true);
            loanSeizeCursor = 0;
        }
    }
    function pending() external view returns (bool, uint32) { return (_loansDuePending(), loanSeizeCursor); }
    function seize() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

/// @notice Loan seizure runs on schedule inside the mining engine: the transition request that
///         enters the due level arms it, and it runs before anything uses that level's word.
///         Pins for the advance-call manifest: IsDGNRS.burnForLiquidation and IDeityPassSeize.seize.
contract LoanSeizureTest is DeployProtocol {
    uint256 private constant POOL_HALF_MASK = (uint256(1) << 128) - 1;
    uint8 private constant ACTION_WAIT = 2;
    uint8 private constant ACTION_SEIZE_LOANS = 20;
    bytes32 private constant LOAN_SEIZED_SIG = keccak256("LoanSeized(uint32,uint32)");

    address private borrower;
    uint32 private root;
    address private buyer;
    bytes private gameRuntime;
    address private seeder;
    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        borrower = makeAddr("seizure-borrower");
        buyer = makeAddr("seizure-ticket-buyer");
        vm.deal(borrower, 1_000 ether);
        vm.deal(buyer, 50_000 ether);
        vm.deal(address(game), 100_000 ether);
        root = _giveWalletId(borrower);
        _grantSmurfBase(borrower, 8);
        gameRuntime = address(game).code;
        seeder = address(new SeizureSeeder());
        lens = new DegenerusGameLens();
        _fund(2, 500 ether);
        _seedLevel(root, 8, 400);
    }

    // ---------------------------------------------------------------- helpers

    function _etch() private { vm.etch(address(game), seeder.code); }
    function _unetch() private { vm.etch(address(game), gameRuntime); }
    function _fund(uint32 id, uint128 amount) private { _etch(); SeizureSeeder(address(game)).fund(id, amount); _unetch(); }
    function _seedLevel(uint32 id, uint24 lvl, uint32 entries) private {
        _etch(); SeizureSeeder(address(game)).seedLevel(id, lvl, entries); _unetch();
    }
    function _enterDue(uint24 due) private { _etch(); SeizureSeeder(address(game)).enterDue(due); _unetch(); }
    function _pending() private returns (bool on, uint32 cursor) {
        _etch(); (on, cursor) = SeizureSeeder(address(game)).pending(); _unetch();
    }

    function _payee(uint32 id) private view returns (address payee) {
        (, payee, ) = game.resolveAccount(id, address(0));
    }

    function _borrow(address who, uint32 id, uint24 due) private returns (uint256 principal) {
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, due);
        assertTrue(q.eligible, "borrow eligible");
        principal = q.principal;
        vm.prank(who);
        game.borrow(id, due, principal);
    }

    function _child(address owner) private returns (uint32 id) {
        uint256 price = game.mintPrice();
        vm.prank(owner);
        id = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
    }

    function _buyDeity(address owner, uint32 id, uint8 symbol) private {
        vm.prank(owner);
        game.purchaseDeityPass{value: 200 ether}(id, symbol, bytes32(0));
    }

    function _seedNextPrizePool(uint256 targetNext) private {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(GameSlots.PRIZE_POOLS_PACKED))));
        if ((packed & POOL_HALF_MASK) >= targetNext) return;
        vm.store(address(game), bytes32(uint256(GameSlots.PRIZE_POOLS_PACKED)),
            bytes32((packed & ~POOL_HALF_MASK) | targetNext));
    }

    function _buyTickets(address who, uint256 qty) private {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        vm.prank(who);
        try game.purchase{value: cost}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _fulfillVrfIfPending() private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(keccak256(abi.encode(block.timestamp, game.level(), reqId)));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    /// @dev Drive the real engine until the transition request that enters `target` has run, and
    ///      stop BEFORE that request's word is fulfilled.
    function _driveToTransition(uint24 target) private {
        uint256 simTime = block.timestamp;
        for (uint256 day; day < 60; ++day) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(500 ether);
            _buyTickets(buyer, 4000);
            for (uint256 j; j < 80; ++j) {
                if (game.level() >= target) return;
                _fulfillVrfIfPending();
                if (game.level() >= target) return;
                (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
                if (game.level() >= target) return;
                if (!ok) break;
            }
        }
        fail("transition not reached");
    }

    function _seizedCount(Vm.Log[] memory logs) private pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == LOAN_SEIZED_SIG) ++n;
        }
    }

    // ---------------------------------------------------------------- schedule

    function test_RealTransitionSeizesBeforeTheWordIsUsed() public {
        _giveSdgnrsTo(borrower, 5e12);
        uint256 principal = _borrow(borrower, root, 1);
        assertGt(principal, 0);
        _driveToTransition(1);

        assertEq(game.level(), 1, "the transition request entered the due level");
        assertTrue(game.rngLocked(), "inside the transition's RNG lock");
        (bool on, ) = _pending();
        assertTrue(on, "the request armed the seizure");
        assertEq(game.nextMinerAction(), ACTION_SEIZE_LOANS, "seizure outranks the wait for the word");
        assertEq(_payee(root), borrower, "not seized yet");
        vm.prank(borrower); vm.expectRevert(bytes4(keccak256("E()"))); game.repay{value: 10 ether}(root);

        uint256 reqId = mockVRF.lastRequestId();
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        assertFalse(fulfilled, "the word has not arrived");
        vm.recordLogs();
        game.mineFlip(0);
        assertEq(_seizedCount(vm.getRecordedLogs()), 1);
        assertEq(_payee(root), address(sdgnrs), "the lender took the account");
        assertEq(game.acquiredBuyer(root), 2);
        assertEq(sdgnrs.balanceOf(borrower), 0, "burnForLiquidation burned the borrower wallet's sDGNRS");
        assertEq(game.walletIdOf(borrower), 0);
        (on, ) = _pending();
        assertFalse(on);
        assertEq(game.nextMinerAction(), ACTION_WAIT, "back to waiting for the word");
        assertEq(lens.loanOf(address(game), root).principal, 0);

        // The level continues normally afterwards.
        _fulfillVrfIfPending();
        _mineAll(200);
        assertEq(game.level(), 1);
    }

    function test_SeizureOrderAheadOfPublishAndTickets() public {
        _borrow(borrower, root, 1);
        _driveToTransition(1);
        _fulfillVrfIfPending();
        assertEq(game.nextMinerAction(), ACTION_SEIZE_LOANS, "still first once the word has landed");
        game.mineFlip(0);
        assertEq(_payee(root), address(sdgnrs));
    }

    function _giveSdgnrsTo(address player, uint256 amount) private {
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, player, amount);
    }

    // ---------------------------------------------------------------- chunking

    function test_ManyLoansSeizeAcrossBoundedChunks() public {
        uint256 n = 90;
        uint32[] memory ids = new uint32[](n);
        address[] memory owners = new address[](n);
        _fund(2, 5_000 ether);
        for (uint256 i; i < n; ++i) {
            owners[i] = makeAddr(string(abi.encode("chunk-borrower", i)));
            vm.deal(owners[i], 10 ether);
            ids[i] = _giveWalletId(owners[i]);
            _seedLevel(ids[i], 8, 400);
            _borrow(owners[i], ids[i], 1);
        }
        _enterDue(1);
        uint256 calls;
        vm.recordLogs();
        for (; calls < 20; ++calls) {
            (bool on, ) = _pending();
            if (!on) break;
            // A seizure admits only while the worst-case bound still fits, so a capped call stops
            // short and the next call resumes from the stored cursor.
            game.mineFlip{gas: 1_000_000}(0);
        }
        assertGt(calls, 1, "a capped call cannot take every loan: the stage resumes from its cursor");
        assertEq(_seizedCount(vm.getRecordedLogs()), n, "each loan seized exactly once");
        for (uint256 i; i < n; ++i) assertEq(_payee(ids[i]), address(sdgnrs));
        assertTrue(game.nextMinerAction() != ACTION_SEIZE_LOANS);
    }

    function test_PartialChunkKeepsCursorAndPending() public {
        uint256 n = 70;
        _fund(2, 5_000 ether);
        uint32[] memory ids = new uint32[](n);
        for (uint256 i; i < n; ++i) {
            address owner = makeAddr(string(abi.encode("cursor-borrower", i)));
            ids[i] = _giveWalletId(owner);
            _seedLevel(ids[i], 8, 400);
            _borrow(owner, ids[i], 1);
        }
        _enterDue(1);
        game.mineFlip{gas: 1_000_000}(0);
        (bool on, uint32 cursor) = _pending();
        assertTrue(on);
        assertGt(cursor, 0);
        assertLt(cursor, n);
        assertEq(_payee(ids[cursor - 1]), address(sdgnrs));
        assertEq(_payee(ids[cursor]), makeAddr(string(abi.encode("cursor-borrower", uint256(cursor)))));
        _mineAll(50);
        for (uint256 i; i < n; ++i) assertEq(_payee(ids[i]), address(sdgnrs));
    }

    // ---------------------------------------------------------------- terminal precedence

    function test_GameOverWhilePendingLeavesBorrowerTheAccount() public {
        uint256 principal = _borrow(borrower, root, 1);
        _enterDue(1);
        _etch(); SeizureSeeder(address(game)).end(); _unetch();
        assertTrue(game.nextMinerAction() != ACTION_SEIZE_LOANS, "terminal handling outranks seizure");
        _mineAll(50);
        assertEq(_payee(root), borrower, "the borrower wins at game over");
        assertGt(principal, 0);
    }

    // ---------------------------------------------------------------- deity passes

    function test_DeityMainDefaultMovesPassToLender() public {
        _buyDeity(borrower, root, 3);
        assertEq(deityPass.ownerOf(3), borrower);
        _borrow(borrower, root, 1);
        _enterDue(1);
        game.mineFlip(0);
        assertEq(deityPass.ownerOf(3), address(sdgnrs), "the pass follows its account");
        assertEq(deityPass.balanceOf(borrower), 0);
        assertEq(game.acquiredBuyer(root), 2);
        vm.prank(borrower); vm.expectRevert(); game.smite(3, root);
        vm.prank(borrower); vm.expectRevert(); game.issueDeityBoon(root, 2, 0);
    }

    function test_DeitySmurfDefaultAloneMovesOnlyItsPass() public {
        uint32 child = _child(borrower);
        _buyDeity(borrower, child, 4);
        assertEq(deityPass.ownerOf(4), borrower, "minted to the main wallet");
        _seedLevel(child, 8, 400);
        _borrow(borrower, child, 1);
        _enterDue(1);
        game.mineFlip(0);
        assertEq(deityPass.ownerOf(4), address(sdgnrs));
        assertEq(_payee(root), borrower, "the main stays with its owner");
        assertEq(game.walletIdOf(borrower), root);
    }

    function test_DeityBoughtDuringLoanStillMoves() public {
        _borrow(borrower, root, 1);
        _buyDeity(borrower, root, 10);
        _enterDue(1);
        game.mineFlip(0);
        assertEq(deityPass.ownerOf(10), address(sdgnrs));
    }

    function test_DeityPassFollowsAccountToItsFinalLender() public {
        uint32 child = _child(borrower);
        _buyDeity(borrower, child, 5);
        _seedLevel(child, 8, 400);
        // The smurf borrows from sDGNRS, due second; the main from the Vault, due first.
        _borrow(borrower, child, 2);
        _etch(); SeizureSeeder(address(game)).setClaimable(2, 1 ether); _unetch();
        _fund(1, 100 ether);
        vm.prank(ContractAddresses.CREATOR); vault.setLiquidationBuyFallback(true, 1 ether);
        _borrow(borrower, root, 1);
        _enterDue(1);
        game.mineFlip(0);
        assertEq(deityPass.ownerOf(5), address(vault), "the family and its pass went to the Vault");
        _fund(2, 500 ether);
        _enterDue(2);
        game.mineFlip(0);
        assertEq(deityPass.ownerOf(5), address(sdgnrs), "the smurf's own default moves it on");
        assertEq(game.acquiredBuyer(child), 2);
        vm.prank(ContractAddresses.CREATOR); vm.expectRevert();
        vault.sweepNft(address(deityPass), ContractAddresses.CREATOR, 5);
    }

    function test_SellerCanBuyANewDeityAfterSeizure() public {
        _buyDeity(borrower, root, 7);
        _borrow(borrower, root, 1);
        _enterDue(1);
        _etch(); SeizureSeeder(address(game)).seize(); _unetch();
        uint32 replacement = _giveWalletId(borrower);
        _buyDeity(borrower, replacement, 8);
        assertEq(deityPass.ownerOf(8), borrower);
    }

    function test_SeizeAndBurnHooksAreGameOnly() public {
        _buyDeity(borrower, root, 9);
        vm.expectRevert(DegenerusDeityPass.NotAuthorized.selector);
        deityPass.seize(9, address(this));
        vm.prank(borrower); vm.expectRevert(DegenerusDeityPass.Soulbound.selector);
        deityPass.transferFrom(borrower, address(this), 9);
        _giveSdgnrsTo(borrower, 1);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.burnForLiquidation(borrower);
    }
}
