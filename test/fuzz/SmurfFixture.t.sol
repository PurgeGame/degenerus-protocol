// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @dev The production Game plus test doors: a delegatecall into any module in the Game's
///      context, and storage seeders. Every production function is unchanged.
contract SmurfGameHarness is DegenerusGame {
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
    function x_setLevelDgnrs(uint24 lvl, uint256 allocation) external { _setLevelDgnrsAllocation(lvl, allocation); }
    function x_setFoilRecord(uint24 lvl, uint32 id, uint256 w) external { foilRecord[lvl & 3][id] = w; }
    function x_setFoilDraw(uint24 day, uint256 w) external { dailyFoilDraw[day & 1] = w; }

    function x_creditClaimable(uint32 id, uint256 amount) external {
        _creditClaimableLogged(id, amount);
        claimablePool += uint128(amount);
    }

    function x_deityCount() external view returns (uint256) { return _deityCount(); }
    function x_deityIdAt(uint256 i) external view returns (uint32) { return _deityIdAt(i); }
    function x_deityPricePaid(uint32 id) external view returns (uint256) { return deityPassPricePaid[id]; }
    function x_walletElement(uint32 id) external view returns (uint256) { return _walletElement(id); }
}

/// @title SmurfFixture -- shared setup for the smurf payout, Degenerette gift and deity-group suites
/// @notice Deploys the protocol, etches the harness over the Game, and builds owners, smurfs
///         (`createSmurf` by an owner that already holds an ID) and ordinary wallets.
abstract contract SmurfFixture is DeployProtocol {
    bytes32 internal constant POOL_TRANSFER = keccak256("PoolTransfer(uint8,address,uint256)");
    bytes32 internal constant BET_PLACED = keccak256("DegeneretteBetPlaced(uint32,uint32,uint64,uint256)");
    bytes32 internal constant BET_RESOLVED = keccak256("DegeneretteResolved(uint32,uint32,uint64,uint256,uint32,bytes)");
    bytes32 internal constant BOX_SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");

    /// @dev The Degenerette bet buffer the fixtures place into (its word unset at placement).
    uint48 internal constant BET_INDEX = 1;

    SmurfGameHarness internal ext;

    function _setUpSmurfFixture() internal {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.etch(address(game), address(new SmurfGameHarness()).code);
        ext = SmurfGameHarness(payable(address(game)));
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

    /// @dev `owner` creates a smurf, paying its admission ticket with fresh ETH.
    function _createSmurf(address owner) internal returns (uint32 smurfId) {
        uint256 price = game.mintPrice();
        vm.prank(owner);
        smurfId = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);

        assertEq((_fixtureMint(smurfId) >> BitPackingLib.SMURF_FLAG_SHIFT) & 1, 1, "fixture: smurf flag");
        assertEq((ext.x_walletElement(smurfId) >> 160) & 0xffffffff, game.walletIdOf(owner), "fixture: owner lane");
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
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        RecyclingState.seedWriteBuffer(address(game), BET_INDEX ^ 1);
        vm.recordLogs();
        for (uint256 calls; calls < 16; ++calls) {
            vm.prank(makeAddr("bet_keeper"));
            try game.mineFlip() {} catch (bytes memory reason) {
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
