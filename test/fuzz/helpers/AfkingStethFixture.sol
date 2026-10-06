// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {MineFlipGas} from "../../../contracts/libraries/MineFlipGas.sol";
import {BitPackingLib} from "../../../contracts/libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";
import {WalletSeed} from "../../helpers/WalletSeed.sol";

/// @dev Only setup/read helpers are synthetic; subscription, pull, delivery and eviction
///      all use the production facade and delegatecalled AFKing worker.
contract AfkingStethHost is DegenerusGame, WalletSeed {
    function prepare() external {
        uint24 day = _simulatedDayIndex();
        level = 4;
        dailyIdx = day - 1;
        _afkingResetDay = day;
        _subCursor = 0;
        _subOpenCursor = 0;
        _pendingBoxCount = 0;
        delete _subscribers;
        subsFullyProcessed = false;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngLockedFlag = false;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        _setRngComplete(true);
        _sdgnrsBonusLevel = level;
        // Jumping to level 4 skips the drains: release the retired levels' far-future roots and
        // both slot sides of their near queues, whose level-parity physical roots the current
        // level's queues recycle (a still-occupied root refuses a new level with E()).
        for (uint24 oldLevel = 1; oldLevel <= 4; ++oldLevel) {
            uint24[3] memory keys = [_tqFarFutureKey(oldLevel), oldLevel, oldLevel | TICKET_SLOT_BIT];
            for (uint256 k; k < 3; ++k) {
                uint256[] storage q = ticketQueue[_ticketQueueStorageKey(keys[k])];
                assembly ("memory-safe") { sstore(q.slot, 0) }
            }
        }
    }

    function add(
        address player,
        address source,
        bool drainFirst,
        bool tickets,
        uint8 quantity,
        uint256 prepaid,
        uint256 claimable
    ) external {
        (uint32 id, ) = _registerWallet(player, 0);
        _subscribers.push(uint256(uint160(player)) | (uint256(id) << 160));
        Sub storage sub = _subOf[id];
        sub.setPosition = uint32(_subscribers.length);
        sub.dailyQuantity = quantity;
        sub.flags = (source == address(0) ? 0 : 1) | (drainFirst ? 2 : 0) | (tickets ? 4 : 0);
        uint32 sourceId;
        if (source != address(0)) {
            (sourceId, ) = _registerWallet(source, 0);
            _fundingSourceOf[id] = uint256(uint160(source)) | (uint256(sourceId) << 160);
        }
        sub.lastAutoBoughtDay = _afkingResetDay - 1;
        sub.lastOpenedDay = _afkingResetDay - 1;
        sub.afkingStartDay = _afkingResetDay - 1;
        sub.afkCoveredThroughDay = _afkingResetDay - 1;
        sub.affiliateBase = 31;
        sub.pendingFlip = 17;
        sub.subStreakLatch = 9;
        mintPacked_[player] |= uint256(1) << BitPackingLib.SEAT_ENCUMBERED_SHIFT;
        if (prepaid != 0) _creditAfkingValue(source == address(0) ? id : sourceId, prepaid);
        if (claimable != 0) {
            _creditClaimable(id, claimable);
            claimablePool += uint128(claimable);
        }
    }

    function subWork(uint256 allowance_) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory result) = ContractAddresses.GAME_AFKING_MODULE
            .delegatecall(abi.encodeWithSignature("runSubscriberWork(uint24,uint256)", _afkingResetDay, allowance_));
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        return abi.decode(result, (MineFlipGas.Result));
    }

    function nextDay() external {
        _afkingResetDay = _simulatedDayIndex();
        dailyIdx = _afkingResetDay - 1;
        _subCursor = 0;
        subsFullyProcessed = false;
    }

    function stateOf(address player) external view returns (Sub memory) {
        return _subOf[_walletIdOf(player)];
    }

    function sourceOf(address player) external view returns (address) {
        return address(uint160(_fundingSourceOf[_walletIdOf(player)]));
    }

    function memberOf(address player) external view returns (uint256) {
        return _subOf[_walletIdOf(player)].setPosition;
    }

    function pendingBoxes() external view returns (uint256) {
        return _pendingBoxCount;
    }

    function price() external view returns (uint256) {
        return PriceLookupLib.priceForLevel(_activeTicketLevel());
    }

    function claimableOf(address player) external view returns (uint256) {
        return _claimableOf(_walletIdOf(player));
    }

    function entries(address player) external view returns (uint256) {
        return _entriesOwedTotal(level + 1, _walletIdOf(player));
    }

    function setMarkers(address player, uint24 bought, uint24 opened) external {
        _subOf[_seedWallet(player)].lastAutoBoughtDay = bought;
        _subOf[_seedWallet(player)].lastOpenedDay = opened;
    }

    function setQuantity(address player, uint8 quantity) external {
        _subOf[_seedWallet(player)].dailyQuantity = quantity;
    }

    function setSource(address player, address source) external {
        _fundingSourceOf[_seedWallet(player)] =
            source == address(0) ? 0 : uint256(uint160(source)) | (uint256(_seedWallet(source)) << 160);
        if (source == address(0)) _subOf[_seedWallet(player)].flags &= ~uint8(1);
        else _subOf[_seedWallet(player)].flags |= 1;
    }

    function setLock(bool locked) external {
        rngLockedFlag = locked;
    }

    function setClosed(bool closed) external {
        gameOver = closed;
    }

    function setBalances(address player, uint128 prepaid, uint128 claimable) external {
        balancesPacked[_seedWallet(player)] = (uint256(prepaid) << 128) | claimable;
    }

    function setPool(uint128 value) external {
        claimablePool = value;
    }
}

/// @dev Share-based token with faults at each operation used by the fallback. Etching
///      its code over MockStETH preserves the mock's existing backing and share storage.
contract AdversarialAfkingSteth is MockStETH {
    enum Operation {
        None,
        BalanceBefore,
        SharesQuote,
        PooledQuote,
        Transfer,
        BalanceAfter
    }
    enum Fault {
        None,
        RevertCall,
        Malformed,
        BurnGas,
        Oversized,
        Zero,
        Lie,
        Underdeliver
    }

    Operation public faultOperation;
    Fault public fault;
    bool public didTransfer;
    uint256 public transferCalls;

    function configureFault(Operation op, Fault fault_) external {
        faultOperation = op;
        fault = fault_;
        didTransfer = false;
    }

    function configureRatio(uint256 pooled, uint256 shares) external {
        totalPooledEther = pooled;
        totalShares = shares;
    }

    function configureShares(address holder, uint256 shares) external {
        sharesOf[holder] = shares;
    }

    function approveGameFromToken(uint256 amount) external {
        allowance[address(this)][ContractAddresses.GAME] = amount;
    }

    function balanceOf(address holder) public view override returns (uint256) {
        _fault(didTransfer ? Operation.BalanceAfter : Operation.BalanceBefore);
        return totalShares == 0 ? 0 : sharesOf[holder] * totalPooledEther / totalShares;
    }

    function getSharesByPooledEth(uint256 amount) public view override returns (uint256) {
        _fault(Operation.SharesQuote);
        return super.getSharesByPooledEth(amount);
    }

    function getPooledEthByShares(uint256 shares) public view override returns (uint256) {
        _fault(Operation.PooledQuote);
        return super.getPooledEthByShares(shares);
    }

    function transferSharesFrom(address source, address target, uint256 shares)
        public
        override
        returns (uint256 transferred)
    {
        _fault(Operation.Transfer);
        if (faultOperation == Operation.Transfer && fault == Fault.Underdeliver) --shares;
        transferred = super.transferSharesFrom(source, target, shares);
        didTransfer = true;
        ++transferCalls;
        if (faultOperation == Operation.Transfer && fault == Fault.Zero) return 0;
        if (faultOperation == Operation.Transfer && fault == Fault.Lie) return transferred + 2;
    }

    function _fault(Operation op) private view {
        if (op != faultOperation) return;
        if (fault == Fault.RevertCall) revert("stETH unavailable");
        if (fault == Fault.Malformed) {
            assembly ("memory-safe") {
                mstore(0, 1)
                return(31, 1)
            }
        }
        if (fault == Fault.BurnGas) assembly ("memory-safe") { for {} 1 {} {} }
        // Large revert payload exercises the catch boundary without copying token reasons.
        if (fault == Fault.Oversized) assembly ("memory-safe") { revert(0, 0x10000) }
    }
}
