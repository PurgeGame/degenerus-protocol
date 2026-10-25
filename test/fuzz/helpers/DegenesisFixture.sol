// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol, DegenesisDeployProtocol} from "./DeployProtocol.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";
import {GameTimeLib} from "../../../contracts/libraries/GameTimeLib.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../../contracts/sDGNRS.sol";

/// @title DegenesisFixtureBase -- shared driver and readers for the Degenesis integration suites
/// @notice Drives real purchases and real days: the miner engine plus mock VRF fulfilment, never
///         a forged stage. Readers decode the Degenesis state straight from Game storage
///         (GameSlots), since the module exposes only `degenesisCreditOf`. Deploy time is the
///         inheriting fixture's (`DegenesisFixture` deploys on the Degenesis timeline).
abstract contract DegenesisFixtureBase is DeployProtocol {
    uint32 internal constant VAULT_ID = 1;
    uint32 internal constant SDGNRS_ID = 2;
    uint256 internal constant UNIT = 0.0001 ether;
    uint8 internal constant ACTION_IDLE = 0;
    uint8 internal constant ACTION_WAIT = 2;
    uint8 internal constant ACTION_DEGENESIS_SETTLE = 20;

    bytes32 internal constant SPLIT_SIG = keccak256("DegenesisCohortSplit(uint8,uint256)");
    bytes32 internal constant PRICED_SIG = keccak256("DegenesisCohortPriced(uint8,uint256,uint256,uint24)");
    bytes32 internal constant CLOSED_SIG = keccak256("DegenesisCohortClosed(uint8,uint256)");
    bytes32 internal constant RELEASED_SIG = keccak256("DegenesisFundsReleased(uint256,uint256)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    bytes32 internal constant AFKING_FUNDED_SIG = keccak256("AfkingFunded(uint32,uint256)");

    uint256 internal wordSalt = 0xD15E;

    function setUp() public virtual {
        _deployProtocol();
        vm.deal(address(this), 0);
    }

    // ------------------------------------------------------------------ clock

    /// @dev First second of day index `d` (boundary 0 under patchForFoundry).
    function _dayStart(uint256 d) internal pure returns (uint256) {
        return (d - 1) * 1 days + GameTimeLib.JACKPOT_RESET_TIME;
    }

    /// @dev Warp to `offset` seconds into day index `d`.
    function _warpDay(uint256 d, uint256 offset) internal {
        vm.warp(_dayStart(d) + offset);
        // Calendar movement alone does not accept a logical commitment.
    }

    // ------------------------------------------------------------------ engine

    function _fulfillPending() internal returns (bool fulfilled) {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return false;
        (,, bool done) = mockVRF.pendingRequests(id);
        if (done) return false;
        mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(wordSalt, id))));
        return true;
    }

    /// @dev Run the engine until it has nothing to do, answering every VRF request.
    function _drain() internal {
        _drain(true, 400);
    }

    /// @dev Run the engine until idle (or waiting on an unanswered request when `answer` is off).
    function _drain(bool answer, uint256 maxCalls) internal {
        for (uint256 i; i < maxCalls; ++i) {
            if (answer) _fulfillPending();
            uint8 action = game.nextMinerAction();
            if (action == ACTION_IDLE) return;
            if (action == ACTION_WAIT) {
                if (!answer || !_fulfillPending()) return;
                continue;
            }
            game.mineFlip(0);
        }
        revert("fixture: engine did not go idle");
    }

    uint8 internal constant ACTION_REQUEST_DAILY = 16;

    /// @dev The maximum multiplier admits one mandatory action with ample gas and
    ///      prevents optional work from hiding the action the test wants to observe.
    function _stepTo(uint8 action) internal {
        for (uint256 i; i < 400; ++i) {
            if (game.nextMinerAction() == action) return;
            _fulfillPending();
            if (game.nextMinerAction() == action) return;
            game.mineFlip{gas: 16_700_000}(type(uint32).max);
        }
        revert("fixture: action never came up");
    }

    function _mineWithGas(uint256 gas_) internal returns (bool ok) {
        (ok,) = address(game).call{gas: gas_}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
    }

    /// @dev Warp to day index `d` (one hour in) and process it completely.
    function _driveDay(uint256 d) internal {
        _warpDay(d, 1 hours);
        _drain();
    }

    /// @dev Process every day from the current one through `d`, one at a time.
    function _driveThrough(uint256 d) internal {
        for (uint256 day = game.currentDayView_g542950() + 1; day <= d; ++day) _driveDay(day);
    }

    // ------------------------------------------------------------------ actors

    function _player(string memory name, uint256 eth) internal returns (address p) {
        p = makeAddr(name);
        vm.deal(p, eth);
        _giveWalletId(p);
    }

    /// @dev Buy `tickets` whole tickets with fresh ETH at the current price.
    function _buyTickets(address p, uint256 tickets) internal returns (uint256 cost) {
        cost = game.mintPrice() * tickets;
        vm.prank(p);
        game.purchase{value: cost}(0, tickets * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @dev Earn `credit` of Degenesis credit with fresh-ETH ticket buys (4x spend).
    function _earnCredit(address p, uint256 credit) internal {
        uint256 price = game.mintPrice();
        uint256 tickets = (credit * 4 + price - 1) / price;
        vm.deal(p, p.balance + tickets * price);
        _buyTickets(p, tickets);
    }

    function _buyDegenesis(address p, uint256 amount) internal {
        vm.deal(p, p.balance + amount);
        vm.prank(p);
        game.buyDegenesisBox{value: amount}(0, amount);
    }

    // ------------------------------------------------------------------ readers

    function _slot(uint256 s) internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(s)));
    }

    function _claimablePool() internal view returns (uint256) {
        return game.claimablePoolView();
    }

    function _vaultBudget() internal view returns (uint256) {
        return uint128(_slot(GameSlots.DEGENESIS_VAULT_BUDGET));
    }

    function _degenesisClosed() internal view returns (uint256) {
        return uint8(_slot(0) >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8));
    }

    function _active() internal view returns (uint256) {
        return _slot(GameSlots.DEGENESIS_ACTIVE);
    }

    function _degenesisWord() internal view returns (uint256) {
        return _slot(GameSlots.DEGENESIS_WORD);
    }

    function _dayHeader(uint256 c) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(c, GameSlots.DEGENESIS_DAYS))));
    }

    /// @dev Cohort `c`'s volume in wei.
    function _cohortVolume(uint256 c) internal view returns (uint256) {
        return uint256(uint48(_dayHeader(c))) * UNIT;
    }

    function _cohortCount(uint256 c) internal view returns (uint256) {
        return uint32(_dayHeader(c) >> 48);
    }

    function _cohortSplit(uint256 c) internal view returns (bool) {
        return (_dayHeader(c) >> 80) & 1 == 1;
    }

    /// @dev Volume still held unsplit in claimablePool.
    function _unsplitVolume() internal view returns (uint256 v) {
        for (uint256 c = 1; c <= 7; ++c) if (!_cohortSplit(c)) v += _cohortVolume(c);
    }

    function _packed(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(id), GameSlots.BALANCES_PACKED))));
    }

    function _claimableOf(uint32 id) internal view returns (uint256) {
        return uint128(_packed(id));
    }

    function _afkingOf(uint32 id) internal view returns (uint256) {
        return _packed(id) >> 128;
    }

    function _nextPool() internal view returns (uint256) {
        return uint128(_slot(GameSlots.PRIZE_POOLS_PACKED));
    }

    function _futurePool() internal view returns (uint256) {
        return _slot(GameSlots.PRIZE_POOLS_PACKED) >> 128;
    }

    function _frozen() internal view returns (bool) {
        return uint8(_slot(0) >> (GameSlots.PRIZE_POOL_FROZEN_OFFSET * 8)) != 0;
    }

    function _pendingNext() internal view returns (uint256) {
        return uint128(_slot(GameSlots.PRIZE_POOL_PENDING_PACKED));
    }

    /// @dev Bit 255 is the pending slot's sentinel, not pool value.
    function _pendingFuture() internal view returns (uint256) {
        return (_slot(GameSlots.PRIZE_POOL_PENDING_PACKED) >> 128) & (type(uint128).max >> 1);
    }

    /// @dev Live future pool plus the pending buffer when frozen.
    function _futureTotal() internal view returns (uint256) {
        return _futurePool() + (_frozen() ? _pendingFuture() : 0);
    }

    function _nextTotal() internal view returns (uint256) {
        return _nextPool() + (_frozen() ? _pendingNext() : 0);
    }

    function _level() internal view returns (uint24) {
        return uint24(_slot(0) >> (GameSlots.LEVEL_OFFSET * 8));
    }

    function _lastPurchaseDay() internal view returns (bool) {
        return uint8(_slot(0) >> (GameSlots.LAST_PURCHASE_DAY_OFFSET * 8)) != 0;
    }

    function _jackpotPhase() internal view returns (bool) {
        return uint8(_slot(0) >> (GameSlots.JACKPOT_PHASE_FLAG_OFFSET * 8)) != 0;
    }

    function _jackpotFlags() internal view returns (uint8) {
        return uint8(_slot(0) >> (GameSlots.JACKPOT_FLAGS_OFFSET * 8));
    }

    function _dailyIdx() internal view returns (uint24) {
        return uint24(_slot(0) >> (GameSlots.DAILY_IDX_OFFSET * 8));
    }

    function _gameBalance() internal view returns (uint256) {
        return address(game).balance + mockStETH.balanceOf(address(game));
    }

    function _degenesisPool() internal view returns (uint256) {
        return sdgnrs.poolBalance(sDGNRS.Pool.Degenesis);
    }

    // ------------------------------------------------------------------ writers (fixture only)

    /// @dev Set the live next pool (low half of prizePoolsPacked), keeping the future half, and
    ///      back any increase with ETH so the Game stays solvent.
    function _setNextPool(uint256 next) internal {
        uint256 packed = _slot(GameSlots.PRIZE_POOLS_PACKED);
        uint256 old = uint128(packed);
        if (next > old) vm.deal(address(game), address(game).balance + (next - old));
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED),
            bytes32((packed & ~uint256(type(uint128).max)) | next));
    }

    /// @dev Credit `amount` of claimable winnings to `id` as a payout would: the ledger and
    ///      claimablePool in tandem, backed by the same ETH.
    function _seedClaimable(uint32 id, uint256 amount) internal {
        bytes32 key = keccak256(abi.encode(uint256(id), GameSlots.BALANCES_PACKED));
        vm.store(address(game), key, bytes32(uint256(vm.load(address(game), key)) + amount));
        _bumpClaimablePool(amount);
        vm.deal(address(game), address(game).balance + amount);
    }

    function _bumpClaimablePool(uint256 amount) internal {
        uint256 s1 = _slot(GameSlots.CLAIMABLE_POOL);
        uint256 pool = (s1 >> 128) + amount;
        vm.store(address(game), bytes32(GameSlots.CLAIMABLE_POOL),
            bytes32((s1 & type(uint128).max) | (pool << 128)));
    }

    /// @dev Write `id`'s Degenesis credit directly (for gates that must be isolated from it).
    function _seedCredit(uint32 id, uint256 credit) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(id), GameSlots.DEGENESIS_CREDIT)), bytes32(credit));
    }

    function _creditOfId(uint32 id) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(id), GameSlots.DEGENESIS_CREDIT))));
    }

    /// @dev One engine call that may find nothing to do (or only a request to wait on).
    function _tryMine() internal returns (bool ok) {
        (ok,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
    }

    // ------------------------------------------------------------------ logs

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == sig) ++n;
        }
    }

    function _sawStage(Vm.Log[] memory logs, uint8 stage) internal view returns (bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 1 && logs[i].topics[0] == ADVANCE_SIG) {
                (uint8 s,) = abi.decode(logs[i].data, (uint8, uint24));
                if (s == stage) return true;
            }
        }
        return false;
    }
}

/// @title DegenesisFixture -- DegenesisFixtureBase on the Degenesis timeline (deploy on day index 1)
abstract contract DegenesisFixture is DegenesisFixtureBase, DegenesisDeployProtocol {
    function _deployTimestamp() internal pure virtual override(DeployProtocol, DegenesisDeployProtocol) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }
}
