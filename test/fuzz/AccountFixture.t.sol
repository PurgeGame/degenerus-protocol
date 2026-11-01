// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @dev The production Game plus test doors: a delegatecall into any module in the Game's
///      context, and storage seeders. Every production function is unchanged.
contract AccountGameHarness is DegenerusGame {
    function x_delegate(address module, bytes calldata data) external payable returns (bytes memory r) {
        bool ok;
        (ok, r) = module.delegatecall(data);
        if (!ok) assembly ("memory-safe") { revert(add(r, 32), mload(r)) }
    }

    function x_bucketAppend(uint24 lvl, uint8 trait, uint32 id, uint256 n) external {
        _setTicketBufferLevel(lvl);
        _bucketAppendRun(_traitBufferBase(lvl), trait, id, n, lvl);
    }

    function x_bucketLength(uint24 lvl, uint8 trait) external view returns (uint256) {
        return _bucketLength(lvl, trait);
    }

    function x_setLevel(uint24 lvl) external { level = lvl; }
    function x_setLevelDgnrs(uint24, uint256 allocation) external { _setLevelDgnrsAllocation(allocation); }
    function x_setFoilRecord(uint24 lvl, uint32 id, uint256 w) external { foilRecord[lvl & 3][id] = w; }
    function x_setFoilDraw(uint24 day, uint256 w) external { dailyFoilDraw[day & 1] = w; }

    function x_creditClaimable(uint32 id, uint256 amount) external {
        _creditClaimableLogged(id, amount);
        claimablePool += uint128(amount);
    }

    /// @dev Set both balance halves, keeping claimablePool equal to the backed sum.
    function x_setBalances(uint32 id, uint128 claimable, uint128 afking) external {
        uint256 old = balancesPacked[id];
        uint128 oldBacked = uint128(old) > 1 ? uint128(old) - 1 : 0;
        uint128 newBacked = claimable > 1 ? claimable - 1 : 0;
        claimablePool = claimablePool - oldBacked - uint128(old >> 128) + newBacked + afking;
        balancesPacked[id] = (uint256(afking) << 128) | claimable;
    }

    /// @dev Queue loan collateral: `entries` raw entries for `id` at `lvl`.
    function x_seedLevel(uint32 id, uint24 lvl, uint32 entries) external { _queueEntries(id, lvl, entries, false); }

    /// @dev Jump to `due` and arm its seizure exactly as the transition request does.
    function x_enterDue(uint24 due) external {
        level = due;
        if (_loansDueCount[due] != 0) {
            _setLoansDuePending(true);
            loanSeizeCursor = 0;
        }
    }

    /// @dev Run the production seizure worker for the armed due list.
    function x_runSeizure() external {
        (bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("runLoanSeizureWork(uint256)", gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }

    function x_deityCount() external view returns (uint256) { return _deityCount(); }
    function x_deityIdAt(uint256 i) external view returns (uint32) { return _deityIdAt(i); }
    function x_deityPricePaid(uint32 id) external view returns (uint256) { return deityPassPricePaid[id]; }
    function x_walletElement(uint32 id) external view returns (uint256) { return _walletElement(id); }
}

/// @title AccountFixture -- shared Game harness, wallets, balance seeding, event decoding, and
///        acquired accounts built by a real loan and production seizure
abstract contract AccountFixture is DeployProtocol {
    bytes32 internal constant POOL_TRANSFER = keccak256("PoolTransfer(uint8,address,uint256)");
    bytes32 internal constant BET_PLACED = keccak256("DegeneretteBetPlaced(uint32,uint32,uint64,uint256)");
    bytes32 internal constant BET_RESOLVED = keccak256("DegeneretteResolved(uint32,uint32,uint64,uint256,uint32,bytes)");
    bytes32 internal constant BOX_SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
    bytes32 internal constant LOAN_SEIZED = keccak256("LoanSeized(uint32,uint32)");

    uint32 internal constant VAULT_ID = 1;
    uint32 internal constant SDGNRS_ID = 2;

    /// @dev The Degenerette bet buffer the fixtures place into (its word unset at placement).
    uint48 internal constant BET_INDEX = 1;

    AccountGameHarness internal ext;
    DegenerusGameLens internal accountLens;

    function _setUpAccountFixture() internal {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.etch(address(game), address(new AccountGameHarness()).code);
        ext = AccountGameHarness(payable(address(game)));
        accountLens = new DegenerusGameLens();
        vm.deal(address(game), 1_000 ether);
    }

    // ---------------------------------------------------------------------
    // Accounts
    // ---------------------------------------------------------------------

    /// @dev An ordinary wallet with an ID and ETH.
    function _wallet(string memory name) internal returns (address a, uint32 id) {
        a = makeAddr(name);
        vm.deal(a, 1_000 ether);
        id = _giveWalletId(a);
    }

    /// @dev The lender contract for a reserved lender ID.
    function _lenderAddress(uint32 lender) internal view returns (address) {
        return lender == VAULT_ID ? address(vault) : address(sdgnrs);
    }

    /// @dev `seller` borrows against ordinary account `id` from `lender` (due level 1) and
    ///      defaults; the production seizure worker transfers the account. Balances below the full-term
    ///      amount survive the default; anything at or above it would repay instead. Leaves the
    ///      game at level 1 with the acquisition recorded.
    function _acquire(address seller, uint32 id, uint32 lender) internal returns (uint256 principal) {
        ext.x_seedLevel(id, 8, 400);
        uint256 lenderSdgnrs = _fixtureClaimable(SDGNRS_ID);
        if (lender == VAULT_ID) {
            // sDGNRS is preferred while it covers the principal; take it below that for the borrow.
            ext.x_setBalances(SDGNRS_ID, 1 ether, uint128(_fixtureAfking(SDGNRS_ID)));
            ext.x_creditClaimable(VAULT_ID, 100 ether);
            vm.prank(ContractAddresses.CREATOR);
            OwnerTargetCall.call(address(vault), abi.encodeCall(vault.setLiquidationBuyFallback, (true, 1 ether)), 0);
        } else {
            ext.x_creditClaimable(SDGNRS_ID, 500 ether);
        }
        DegenerusGameLens.LoanQuote memory q = accountLens.previewBorrow(address(game), id, 1, type(uint256).max);
        assertTrue(q.eligible, "fixture: borrow eligible");
        assertEq(q.lenderId, lender, "fixture: lender");
        principal = q.principal;
        uint256 keep = _fixtureBalances(id);
        vm.prank(seller);
        game.borrow(id, 1, type(uint256).max, principal);
        if (lender == VAULT_ID) {
            ext.x_setBalances(SDGNRS_ID, uint128(lenderSdgnrs), uint128(_fixtureAfking(SDGNRS_ID)));
        }
        // Drop what the borrow routed into the account so it defaults; earlier balances stay.
        ext.x_setBalances(id, uint128(keep), uint128(keep >> 128));
        ext.x_enterDue(1);
        vm.recordLogs();
        ext.x_runSeizure();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seized;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == LOAN_SEIZED
                && uint32(uint256(logs[i].topics[1])) == id) seized = true;
        }
        assertTrue(seized, "fixture: the seizure ran");
        assertEq(game.acquiredBuyer(id), lender, "fixture: acquired by the lender");
    }

    /// @dev The lender's FLIP position: the Vault's virtual mint allowance (FLIP minted to the
    ///      Vault becomes allowance); zero for sDGNRS, whose mints restake as redemption backing.
    function _lenderFlipMark(uint32 lender) internal view returns (uint256) {
        return lender == VAULT_ID ? coin.vaultMintAllowance() : 0;
    }

    /// @dev Expect the next FLIP mint for `lender` under its rule; call before the minting call.
    function _expectLenderFlip(uint32 lender) internal {
        if (lender == SDGNRS_ID) {
            vm.expectCall(address(coinflip), abi.encodeWithSignature("creditSdgnrsBacking(uint256)"));
        }
    }

    /// @dev After the minting call: the Vault's allowance grew by exactly `amount`.
    function _assertLenderFlip(uint32 lender, uint256 mark, uint256 amount) internal view {
        if (lender == VAULT_ID) assertEq(coin.vaultMintAllowance() - mark, amount, "FLIP to the Vault's allowance");
    }

    // ---------------------------------------------------------------------
    // Balances
    // ---------------------------------------------------------------------

    /// @dev Sum sDGNRS pool transfers to the expected payout recipient.
    function _poolTransfers(Vm.Log[] memory logs, address to) internal view returns (uint256 total) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(sdgnrs) || logs[i].topics[0] != POOL_TRANSFER) continue;
            if (address(uint160(uint256(logs[i].topics[2]))) == to) total += abi.decode(logs[i].data, (uint256));
        }
    }

    function _poolBalance(IsDGNRS.Pool pool) internal view returns (uint256) {
        return sdgnrs.poolBalance(sDGNRS.Pool(uint8(pool)));
    }

    // ---------------------------------------------------------------------
    // Degenerette bets
    // ---------------------------------------------------------------------

    /// @dev Make BET_INDEX the write buffer with its word unset, so placement is open, and give
    ///      the future pool depth for ETH wins.
    function _openBetBuffer() internal {
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED)));
        RecyclingState.seedWriteBuffer(address(game), BET_INDEX);
        vm.store(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED), bytes32(lrPacked));
        uint256 pools = uint256(vm.load(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED)));
        pools = (pools & ~(((uint256(1) << 128) - 1) << 128)) | (uint256(1_000_000 ether) << 128);
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32(pools));
    }

    /// @dev The bet id of the newest DegeneretteBetPlaced in `logs`.
    function _placedBetId(Vm.Log[] memory logs) internal view returns (uint64 betId, uint32 player) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == BET_PLACED) {
                betId = uint64(uint256(logs[i].topics[3]));
                player = uint32(uint256(logs[i].topics[1]));
            }
        }
    }

    /// @dev Publish `word` on BET_INDEX and crank until bet `betId` resolves; returns the logs.
    function _resolveBet(uint256 word, uint64 betId) internal returns (Vm.Log[] memory logs) {
        RecyclingState.seedWord(address(game), BET_INDEX, bytes32(word));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView_g542950()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        RecyclingState.seedWriteBuffer(address(game), BET_INDEX ^ 1);
        vm.recordLogs();
        for (uint256 calls; calls < 16; ++calls) {
            vm.prank(makeAddr("bet_keeper"));
            try game.mineRun(0) {} catch (bytes memory reason) {
                bytes4 sel = bytes4(reason);
                if (reason.length == 4 && (sel == bytes4(keccak256("NoWork()")) || sel == bytes4(keccak256("RngNotReady()")))) {
                    break;
                }
                assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
            }
            // The view reads zero once the bet is marked processed.
            if (game.degeneretteBetInfo(BET_INDEX, betId) == 0) break;
        }
        logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == BET_RESOLVED
                && uint64(uint256(logs[i].topics[3])) == betId) found = true;
        }
        assertTrue(found, "fixture: the bet resolved");
    }
}
