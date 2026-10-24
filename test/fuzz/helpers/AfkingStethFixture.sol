// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MockStETH} from "../../../contracts/mocks/MockStETH.sol";
import {MineFlipGas} from "../../../contracts/libraries/MineFlipGas.sol";
import {PriceLookupLib} from "../../../contracts/libraries/PriceLookupLib.sol";
import {WalletSeed} from "../../helpers/WalletSeed.sol";

/// @dev Only setup/read helpers are synthetic; subscription, pull, delivery and eviction
///      all use the production facade and delegatecalled AFKing worker.
contract AfkingStethHost is DegenerusGame, WalletSeed {
    /// @dev A member's decoded lane plus its set position.
    struct SubView {
        uint256 position1;
        uint256 quantity;
        bool tickets;
        uint256 scoreCode;
        uint24 checkpointDay;
        uint256 checkpointStreak;
        bool removalPending;
    }

    function prepare() external {
        uint24 day = _wallDay();
        level = 4;
        dailyIdx = day - 1;
        _afkingResetDay = day;
        _afkingEndpointDay = day - 1;
        _afkingProtocolFlags = 0;
        _subCursor = 0;
        _subOpenCursor = 0;
        _pendingBoxCount = 0;
        _clearSubscriberSet();
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

    /// @dev Seed a member checkpointed at the last completed pass, streak 9.
    function add(
        address player,
        bool tickets,
        uint8 quantity,
        uint256 prepaid,
        uint256 claimable
    ) external returns (uint32 id) {
        (id, ) = _registerWallet(player, 0);
        _seedSubscriber(id, tickets);
        uint256 position = _subPosition1(id) - 1;
        _setSubLaneAt(position, _withSubCheckpoint(
            _subLaneAt(position) | ((uint256(quantity) - 1) << SUB_QTY_SHIFT), _afkingEndpointDay, 9));
        _setSubRunStart(id, _afkingEndpointDay);
        if (prepaid != 0) _creditAfkingValue(id, prepaid);
        if (claimable != 0) {
            // The argument includes the unbacked 1-wei sentinel seeded at registration.
            _creditClaimable(id, claimable - 1);
            claimablePool += uint128(claimable - 1);
        }
    }

    function subWork(uint256 allowance_) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory result) = ContractAddresses.GAME_AFKING_MODULE
            .delegatecall(abi.encodeWithSignature("runSubscriberWork_g6352(uint24,uint256)", _afkingResetDay, allowance_));
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        return abi.decode(result, (MineFlipGas.Result));
    }

    function nextDay() external {
        _afkingResetDay = _wallDay();
        dailyIdx = _afkingResetDay - 1;
        _subCursor = 0;
        subsFullyProcessed = false;
    }

    /// @dev Seed a completed empty/ticket-only day for subscribe-path fixtures.
    function subscriptionWindow() external {
        require(_pendingBoxCount == 0);
        dailyIdx = _wallDay();
        _afkingResetDay = dailyIdx;
        _afkingEndpointDay = dailyIdx;
        subsFullyProcessed = true;
    }
    function closeReadForTest() external { _setRngComplete(false); }

    function stateOf(address player) external view returns (SubView memory v) {
        (uint256 lane, uint256 position1) = _subLaneOf(_walletIdOf(player));
        v.position1 = position1;
        if (position1 == 0) return v;
        v.quantity = _subQuantity(lane);
        v.tickets = lane & SUB_TICKETS_BIT != 0;
        v.scoreCode = (lane >> SUB_SCORE_SHIFT) & SUB_SCORE_MASK;
        v.checkpointDay = _subDay(lane);
        v.checkpointStreak = _subCheckpointStreak(lane);
        v.removalPending = lane & SUB_REMOVAL_BIT != 0;
    }

    function memberOf(address player) external view returns (uint256) {
        return _subPosition1(_walletIdOf(player));
    }

    function endpoint() external view returns (uint24) {
        return _afkingEndpoint();
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

    function setQuantity(address player, uint8 quantity) external {
        uint256 position = _subPosition1(_seedWallet(player)) - 1;
        uint256 lane = _subLaneAt(position);
        _setSubLaneAt(position, (lane & ~(uint256(7) << SUB_QTY_SHIFT)) | ((uint256(quantity) - 1) << SUB_QTY_SHIFT));
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
        Underdeliver,
        SpoofMeter,
        EmptyRevert
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
        if (fault == Fault.SpoofMeter) revert MineFlipGas.InsufficientExecutionGas();
        if (fault == Fault.EmptyRevert) assembly ("memory-safe") { revert(0, 0) }
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
