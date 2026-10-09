// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IDegenerusGameAdvanceModule, IDegenerusGameRngModule, IDegenerusGameTicketModule, IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Test-only checkpoint driver: executes exactly the currently selected
/// production worker before AFK, or the AFK open worker alone. The composed miner
/// ordinarily opens the boxes within the same transaction, so it cannot expose these
/// intermediate checkpoints. Every production worker keeps its own guards; no
/// obligation/word is fabricated.
contract RingSingleStepFixture is DegenerusGame {
    function stepBeforeAfk() external {
        MinerAction action = _nextMinerAction(address(0));
        address target;
        bytes memory input;
        if (action == MinerAction.Publish) {
            target = ContractAddresses.GAME_RNG_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameRngModule.publishRng.selector);
        } else if (action == MinerAction.Tickets) {
            target = ContractAddresses.GAME_TICKET_MODULE;
            uint24 anchor = !jackpotPhaseFlag && lastPurchaseDay && rngLockedFlag ? level : level + 1;
            input = abi.encodeWithSelector(IDegenerusGameTicketModule.runTicketWork.selector, anchor, uint256(10_000_000));
        } else if (action == MinerAction.DailyGap) {
            target = ContractAddresses.GAME_ADVANCE_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameAdvanceModule.applyDailyGap.selector);
        } else if (action == MinerAction.DailyApply) {
            target = ContractAddresses.GAME_ADVANCE_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameAdvanceModule.applyDailyWord.selector);
        } else if (action == MinerAction.DailyPhase) {
            target = ContractAddresses.GAME_ADVANCE_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameAdvanceModule.runDailyPhase.selector, uint256(10_000_000));
        } else revert("unexpected pre-AFK checkpoint");
        (bool ok, bytes memory reason) = target.delegatecall(input);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        if (action == MinerAction.Tickets) {
            (, bool done,) = abi.decode(reason, (bool, bool, uint256));
            // Exactly the miner's successful-ticket completion transition.
            if (done) {
                ticketsFullyProcessed = true;
                _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
            }
        }
    }

    /// @dev One call of the AFK open worker mineFlip dispatches for the Afking stage, with the
    ///      same allowance shape. Returns the boxes it opened (its reward basis).
    function runAfkOnce(uint32 factor) external returns (uint256 opened) {
        (bool ok, bytes memory ret) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSelector(IGameAfkingModule.runAfkingWork.selector, MineFlipGas.budget(10_000_000, MineFlipGas.normalize(factor), true)));
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        opened = abi.decode(ret, (MineFlipGas.Result)).rewardBasis;
    }
}

/// @notice Public lifecycle regressions for the linear AFKing cursor and subscription lock.
///         A guarded worker driver exposes partial checkpoints without fabricating paid boxes.
contract AutoOpenCursorRing is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    // -------------------------------------------------------------------------
    // Game-resident storage slots + the post-PACK Sub-slot offset block
    // (forge inspect DegenerusGame storage: _subOf@52, _subscribers@54, _subscriberIndex@55, cursors@56)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS;      // address[] _subscribers (length @ slot; elements @ keccak256(slot)+i)
    uint256 private constant CURSOR_SLOT = GameSlots.SUB_CURSOR;           // packed: _subCursor u16 @byte0 · _subOpenCursor u16 @byte2 · _afkingResetDay u24 @byte4
    uint256 private constant OPEN_CURSOR_BYTE = 2;       // byte offset of _subOpenCursor within CURSOR_SLOT
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED;        // mintPacked_ mapping root (deity bit @ 184)

    //   dailyQuantity u8 @0 · flags u8 @1 · score u16 @2 · amount u24 @4
    //   lastAutoBoughtDay u24 @7 · lastOpenedDay u24 @10 · afkCoveredThroughDay u24 @13 · afkingStartDay u24 @16
    //   affiliateBase u32 @19 · pendingFlip u24 @23 · subStreakLatch u16 @26
    uint256 private constant OFF_LASTBOUGHT = 7;      // uint24 lastAutoBoughtDay (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10;     // uint24 lastOpenedDay     (bytes 10..12)

    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(admin.subscriptionId(), uint96(100 ether));
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
    }

    function test_SubscribeAndModeChangesWaitUntilPaidBoxesOpen() public {
        address[] memory subs = _stampSealedOpenableSubs(5);
        assertEq(_openCursor(), 0, "daily reset starts at the first box");
        address joiner = makeAddr("locked-joiner");
        uint256 seat = _grantSeat(joiner);
        _fundPool(joiner, 80 ether);
        vm.prank(joiner);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        game.subscribe(0, false, false, 1, 0, seat);
        vm.prank(subs[0]);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        game.subscribe(0, false, true, 1, 0, 0);
        vm.prank(subs[0]);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        game.subscribe(0, false, false, 0, 0, 0);
        assertGe(_openAfkRing(), subs.length);
        for (uint256 i; i < subs.length; ++i) assertFalse(_isOpenable(subs[i]));
        assertEq(_openAfkRing(), 0, "completed cohort never replays");
        vm.prank(joiner);
        game.subscribe(0, false, false, 1, 0, seat);
        assertFalse(_isOpenable(joiner), "signup box is only in the human queue");
        _stampSealedBoxOn(joiner);
        assertEq(_openCursor(), 0, "next day resets before its new cohort");
        assertTrue(_isOpenable(joiner), "signup is an ordinary due sub the next day");
        assertGe(_openAfkRing(), subs.length + 1);
        assertFalse(_isOpenable(joiner));
    }

    function test_PartialOpensAdvanceWithoutWrapOrRepeatedPayout() public {
        address[] memory subs = _stampSealedOpenableSubs(5);
        for (uint256 i; i < 8 && uint8(game.nextMinerAction()) == 9; ++i) {
            uint16 beforeCursor = _openCursor();
            bytes memory code = address(game).code;
            vm.etch(address(game), address(new RingSingleStepFixture()).code);
            uint256 opened = RingSingleStepFixture(payable(address(game))).runAfkOnce(type(uint32).max);
            vm.etch(address(game), code);
            assertGt(_openCursor(), beforeCursor, "one durable visit per mandatory call");
            assertLe(opened, 1);
        }
        for (uint256 i; i < subs.length; ++i) assertFalse(_isOpenable(subs[i]));
        assertEq(_openAfkRing(), 0);
    }

    function test_PublicMinerResumesTheLinearOpenCursor() public {
        address[] memory subs = _stampSealedOpenableSubs(5);
        for (uint256 i; i < 8 && uint8(game.nextMinerAction()) == 9; ++i) {
            uint16 beforeCursor = _openCursor();
            game.mineFlip(type(uint32).max);
            assertGt(_openCursor(), beforeCursor);
        }
        for (uint256 i; i < subs.length; ++i) assertEq(_lastOpenedDayOf(subs[i]), _lastBoughtDayOf(subs[i]));
        _finishReadConsumers();
        assertEq(_openAfkRing(), 0);
    }

    // =========================================================================
    // Box-drive helpers
    // =========================================================================

    uint256 private _deliverNonce;

    /// @dev Create `n` seated, funded subs and stamp ONE sealed openable box on each: a new-day STAGE
    ///      buy that stamps the box + lands its stamp-day word, with NO subsequent open. Each sub ends up
    ///      with lastOpenedDay < lastAutoBoughtDay and _recordedDailyWord(lastAutoBoughtDay) != 0 (openable).
    function _stampSealedOpenableSubs(uint256 n) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address p = makeAddr(string(abi.encodePacked("ring_sub_", vm.toString(i))));
            _grantSeat(p);          // the AFKing Subscription Token is the sole subscribe credential
            _fundPool(p, 80 ether); // grounds the NEW-run cover-buy
            _subscribeLootbox(p, 1);
            subs[i] = p;
        }
        // ONE new-day STAGE buy stamps a pending box on every in-set sub + lands the stamp-day word; NO open.
        _runStageNewDay(uint256(keccak256(abi.encode("ring_stamp", _deliverNonce++))) | 1);
        for (uint256 i; i < n; i++) {
            require(_isOpenable(subs[i]), "fixture: each sub carries a sealed openable box (pending + landed word)");
        }
    }

    /// @dev Stamp a fresh sealed openable box on an existing in-set sub via a real new-day STAGE buy (no open).
    function _stampSealedBoxOn(address p) internal {
        _runStageNewDay(uint256(keccak256(abi.encode("ring_restamp", _deliverNonce++))) | 1);
        require(_isOpenable(p), "fixture: a fresh sealed openable box was stamped");
    }

    /// @dev Create a fresh seated/funded subscriber at the tail. Its inline cover
    /// purchase is indexed separately, so its AFK Sub has no pending stamped box.
    function _freshNonPendingSub(string memory tag) internal returns (address p) {
        p = makeAddr(tag);
        _grantSeat(p);
        _fundPool(p, 80 ether);
        _subscribeLootbox(p, 1);
        require(_subscriberIndexOf(p) > 0, "fixture: the fresh sub joined the set");
    }

    /// @dev One call of the production AFK open worker (GameAfkingModule.runAfkingWork, the worker
    ///      mineFlip dispatches for the Afking stage), run in the Game's context through the checkpoint
    ///      fixture. Returns the afking ring boxes it opened.
    function _openAfkRing() internal returns (uint256 opened) {
        bytes memory productionCode = address(game).code;
        vm.etch(address(game), address(new RingSingleStepFixture()).code);
        opened = RingSingleStepFixture(payable(address(game))).runAfkOnce(0);
        vm.etch(address(game), productionCode);
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (the accumulating-timestamp warp).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        // Reach a real commitment with the normal keeper, then use guarded
        // production worker checkpoints to stop immediately before AFK opens.
        for (uint256 i; i < 128 && !game.rngLocked(); ++i) game.mineFlip(0);
        require(game.rngLocked(), "fixture: new daily request");
        _fulfillPending(vrfWord);
        bytes memory productionCode = address(game).code;
        bytes memory checkpointCode = address(new RingSingleStepFixture()).code;
        for (uint256 i; i < 256; ++i) {
            if (uint8(game.nextMinerAction()) == 9) return;
            vm.etch(address(game), checkpointCode);
            RingSingleStepFixture(payable(address(game))).stepBeforeAfk();
            vm.etch(address(game), productionCode);
        }
        revert(string.concat("fixture: AFK checkpoint not reached, action=", vm.toString(uint8(game.nextMinerAction()))));
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (_daySealed()) break;
            _fulfillPending(vrfWord);
            if (_daySealed()) break;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (_daySealed()) return;
            _fulfillPending(vrfWord);
            if (_daySealed()) return;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A false advance hint can mean the read cohort must drain first.
    function _daySealed() internal view returns (bool) {
        uint24 sealedDay = uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24);
        return game.currentDayView() == sealedDay && !game.advanceDue() && !game.rngLocked();
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, false, q, 0, seat); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf(who), uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    // =========================================================================
    // Storage reads / pokes — the subscriber set + the open cursor + the Sub markers
    // =========================================================================

    /// @dev `_subscribers.length` (the dynamic-array length lives directly in its slot).
    function _subscribersLength() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev Read the current `_subOpenCursor` (byte 2..3 of the packed CURSOR_SLOT).
    function _openCursor() internal view returns (uint16) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT))));
        return uint16(packed >> (OPEN_CURSOR_BYTE * 8));
    }

    /// @dev Poke `_subOpenCursor` to `idx` (the wedged mid-array index), preserving the other packed fields.
    function _setOpenCursor(uint16 idx) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT))));
        packed &= ~(uint256(0xFFFF) << (OPEN_CURSOR_BYTE * 8));
        packed |= uint256(idx) << (OPEN_CURSOR_BYTE * 8);
        vm.store(address(game), bytes32(uint256(CURSOR_SLOT)), bytes32(packed));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF)))) >> 224; // Sub.setPosition (1-based)
    }

    /// @dev Openable under the entry-gate: pending box (lastOpenedDay < lastAutoBoughtDay) AND the frozen
    ///      stamp-day word has landed (_recordedDailyWord(lastAutoBoughtDay) != 0). Mirrors the _runAfkingWork predicate.
    function _isOpenable(address who) internal view returns (bool) {
        uint32 bought = _lastBoughtDayOf(who);
        if (_lastOpenedDayOf(who) >= bought) return false;
        return game.rngWordForDay(uint24(bought)) != 0;
    }

    /// @dev Non-pending: no pending box (lastOpenedDay >= lastAutoBoughtDay) — a suffix-only scan landing
    ///      here finds no work.
    function _isNonPending(address who) internal view returns (bool) {
        return _lastOpenedDayOf(who) >= _lastBoughtDayOf(who);
    }
}
