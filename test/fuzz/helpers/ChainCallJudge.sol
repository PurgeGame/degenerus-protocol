// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";
import {MineFlipAdmission} from "./MineFlipAdmission.sol";
import {TicketQueueStorage as TQ} from "./TicketQueueStorage.sol";

/// @notice Whether one recorded mineRun committed work. Progress is a storage slot whose value
///         after the call differs from its value before it, outside the caller's reward credit
///         (Coinflip.creditFlip_g317 and everything it calls): a call that only pays its caller
///         left the engine where it was, so the next call would repeat it. Nothing committed with
///         a reverted inner call is a refusal; nothing committed and nothing refused is no work.
/// @dev Commitment is read from the final state, not from the recorder's per-access revert
///      flags: a reverted subcall can mark accesses of frames that went on to succeed, while a
///      write that really rolled back leaves its slot at the value it had before the call.
///      Only calls carrying at most a transaction's gas are recorded: their access list fits the
///      EVM memory that decodes it. A larger call is UNCHECKED.
///      Once a run starts a recording, Foundry records every storage access until the run ends:
///      `stopAndReturnStateDiff` only empties the record, and only the mapping-slot recording that
///      `startStateDiffRecording` turns on can be switched off. `stop` and `discard` empty the
///      record and switch that one off, so each call's record is released after it.
library ChainProgress {
    Vm private constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint8 internal constant PROGRESSED = 0;
    uint8 internal constant REFUSED = 1;
    uint8 internal constant NONE = 2;
    uint8 internal constant UNCHECKED = 3;
    /// @dev Osaka per-transaction gas cap (2^24) less the intrinsic 21,000.
    uint256 internal constant TX_GAS_CAP = (uint256(1) << 24) - 21_000;
    bytes4 private constant SEL_CREDIT_FLIP = bytes4(keccak256("creditFlip_g317(uint32,uint256)"));

    function start() internal {
        _vm.startStateDiffRecording();
    }

    /// @dev Stops the recording and classifies it, releasing the access list's memory.
    function stop() internal returns (uint8 progress) {
        uint256 free;
        assembly ("memory-safe") { free := mload(0x40) }
        progress = classify(_vm.stopAndReturnStateDiff());
        _vm.stopMappingRecording();
        assembly ("memory-safe") { mstore(0x40, free) }
    }

    /// @dev Drops what was recorded since the last `start`, `stop` or `discard` without decoding it.
    function discard() internal {
        _vm.startStateDiffRecording();
        _vm.stopMappingRecording();
    }

    function classify(Vm.AccountAccess[] memory acc) internal view returns (uint8) {
        bool refused;
        bool inReward;
        uint64 rewardDepth;
        for (uint256 i; i < acc.length; ++i) {
            Vm.AccountAccess memory a = acc[i];
            if (inReward) {
                if (a.depth >= rewardDepth) continue;
                inReward = false;
            }
            if (a.kind == VmSafe.AccountAccessKind.Call && a.account == ContractAddresses.COINFLIP
                && a.data.length >= 4 && bytes4(a.data) == SEL_CREDIT_FLIP) {
                (inReward, rewardDepth) = (true, a.depth);
                continue;
            }
            if (a.reverted && a.kind != VmSafe.AccountAccessKind.StaticCall) refused = true;
            Vm.StorageAccess[] memory ss = a.storageAccesses;
            for (uint256 j; j < ss.length; ++j) {
                if (!ss[j].isWrite || ss[j].previousValue == ss[j].newValue) continue;
                if (_vm.load(ss[j].account, ss[j].slot) != _original(acc, i, j)) return PROGRESSED;
            }
        }
        return refused ? REFUSED : NONE;
    }

    /// @dev The slot's value before the call: the prior value its first write saw.
    function _original(Vm.AccountAccess[] memory acc, uint256 i, uint256 j) private pure returns (bytes32) {
        Vm.StorageAccess memory w = acc[i].storageAccesses[j];
        for (uint256 k; k <= i; ++k) {
            Vm.StorageAccess[] memory ss = acc[k].storageAccesses;
            uint256 end = k == i ? j : ss.length;
            for (uint256 m; m < end; ++m) {
                if (ss[m].isWrite && ss[m].account == w.account && ss[m].slot == w.slot) return ss[m].previousValue;
            }
        }
        return w.previousValue;
    }

    /// @dev The one documented success that commits nothing: a refused request or terminal attempt.
    function refusalAllowed(uint8 progress, uint8 action) internal pure returns (bool) {
        return progress == REFUSED && (action == MineFlipAdmission.TERMINAL
            || action == MineFlipAdmission.REQUEST_DAILY || action == MineFlipAdmission.REQUEST_MIDDAY);
    }
}

/// @title ChainCallJudge -- classifies every `game.mineRun` result a stateful-fuzz handler swallows
/// @notice `mineRun` is the permissionless daily chain (the protocol's liveness spine). Handlers call
///         it inside try/catch and ignore the revert, and `fail_on_revert = false`, so a chain brick in
///         a deep state would pass silently. A handler inherits this contract, routes the call through
///         `_mine`, and the suite asserts `judgeCheck` (which reverts when any unexpected revert was seen).
/// @dev ALLOWED CLASSES (chosen per call site; everything else is unexpected and recorded):
///      OK_IDLE  NoWork()            -- the engine has nothing to do in this state.
///      OK_WAIT  RngNotReady()       -- the engine is waiting for a VRF word the handler has not delivered.
///      OK_GAS   InsufficientExecutionGas / WorkGasBound / EmptyRevert / empty data
///               -- caller gas below the first-unit bound. Allow ONLY at a site that deliberately
///               supplies a capped gas amount; with ample gas the engine reaching this is a no-progress
///               state (the worker neither progressed nor reported done), which is a brick.
///      Anything else (Panic, Error(string), any other custom error from a worker) is unexpected.
///      ADMISSION: at an ample site the judge first reads `minerAction()` as the same caller and
///      makes the call with gas drawn from [minGas, TX_GAS_CAP], minGas being MineFlipAdmission's
///      first-unit bound for that action (a quarter of the calls at the minimum, a quarter within
///      300k above it, the rest anywhere up to the cap), with the protocol's storage slots cooled as at
///      the start of a transaction. The result must match the selection: Idle answers NoWork, Wait answers
///      RngNotReady, and any other action makes progress. A gas refusal at or above the minimum, or
///      any revert of a selected action, is unexpected. TX_GAS_CAP is the Osaka transaction cap less
///      the intrinsic 21,000; an action whose declared minimum exceeds it (HUMAN_BOXES' 100-box bound)
///      is drawn at the cap, so work that only fits above the cap is flagged. While work remains
///      after a successful judged call, an ample call (AMPLE_GAS) follows, so the handler keeps its
///      pace.
///      PROGRESS: every successful call carrying at most TX_GAS_CAP (every admission-judged call and
///      every capped site) is recorded and must commit work (see ChainProgress). The one exception
///      is a refused request or terminal attempt, which commits nothing by design: the selected
///      action is a request or Terminal and an inner call reverted. A success with no readable
///      selection is judged by the selection read after it (nothing changed, so it is the one the
///      call saw). The ample follow-up call, a pacing device carrying 256 transactions' gas, is
///      counted but not judged; ChainStallProbe judges every end state.
///      Set CHAIN_JUDGE_TALLY=1 to print every selector seen (see `judgeTally`).
abstract contract ChainCallJudge {
    Vm private constant _jvm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Osaka per-transaction gas cap (2^24) less the intrinsic 21,000.
    uint256 public constant TX_GAS_CAP = ChainProgress.TX_GAS_CAP;
    /// @dev Gas of an ample call: 256 transactions' worth. The run's recorder sees every call (see
    ///      ChainProgress), so an ample call is bounded and its record dropped after it.
    uint256 public constant AMPLE_GAS = uint256(1) << 32;
    uint8 private constant ACTION_IDLE = 0;
    uint8 private constant ACTION_WAIT = 2;
    uint8 internal constant ACTION_UNREAD = type(uint8).max;

    uint8 internal constant OK_IDLE = 1;
    uint8 internal constant OK_WAIT = 2;
    uint8 internal constant OK_GAS = 4;
    uint8 internal constant OK_IDLE_WAIT = 3;
    uint8 internal constant OK_ALL = 7;

    bytes4 internal constant SEL_NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 internal constant SEL_RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 internal constant SEL_INSUFFICIENT_GAS = bytes4(keccak256("InsufficientExecutionGas()"));
    bytes4 internal constant SEL_WORK_GAS_BOUND = bytes4(keccak256("WorkGasBound()"));
    bytes4 internal constant SEL_EMPTY_REVERT = bytes4(keccak256("EmptyRevert()"));
    bytes4 internal constant SEL_PANIC = 0x4e487b71;
    bytes4 internal constant SEL_MINE_RUN = bytes4(keccak256("mineRun(uint32)"));
    /// @dev Test-local marker recorded for a success that committed no work.
    bytes4 internal constant SEL_NO_PROGRESS = bytes4(keccak256("JudgeNoProgress()"));

    /// @dev Calls, successes and every revert selector seen (empty returndata keys as bytes4(0)).
    uint256 public judgeCalls;
    uint256 public judgeSucceeded;
    /// @dev Successes that committed work, refused requests or terminal attempts that did not, and
    ///      successes too large to record.
    uint256 public judgeProgressed;
    uint256 public judgeRefusals;
    uint256 public judgeUnchecked;
    uint256 public judgeUnexpected;
    /// @dev Revert counts keyed by (selector << 16 | site).
    mapping(uint256 => uint256) public judgeKeyCount;
    uint256[] internal _judgeSeen;

    /// @dev The first unexpected revert: selector, call site, level, gas supplied, state flags, data.
    bytes4 public judgeFirstSel;
    uint16 public judgeFirstSite;
    uint24 public judgeFirstLevel;
    uint256 public judgeFirstGas;
    bool public judgeFirstGameOver;
    bool public judgeFirstRngLocked;
    bytes public judgeFirstData;
    /// @dev The first unexpected call's selected action (ACTION_UNREAD at a capped site).
    uint8 public judgeFirstAction = ACTION_UNREAD;

    /// @dev Admission-judged calls: per action, at exactly the minimum, at the cap because the
    ///      declared minimum exceeds it, and ample sites whose selection could not be read.
    uint256 public judgeDrawnCalls;
    /// @dev Judged calls at a drawn non-default calibration, and those below 1x that refused for gas.
    uint256 public judgeCalibratedCalls;
    uint256 public judgeLowCalibrationRefusals;
    uint256 public judgeAtMinimum;
    uint256 public judgeAboveCap;
    uint256 public judgeUnread;
    mapping(uint8 => uint256) public judgeActionCalls;
    uint256 private _judgeNonce;

    /// @dev One mineRun through the judge. `gasLimit == 0` is an ample site; `site` is a
    ///      handler-local label for the call site. Must be the first external call after any vm.prank.
    function _mine(address game, uint256 gasLimit, uint8 allowed, uint16 site) internal returns (bool ok, bytes4 sel) {
        return _mineMul(game, 0, gasLimit, allowed, site);
    }

    function _mineMul(address game, uint32 multiplier, uint256 gasLimit, uint8 allowed, uint16 site)
        internal
        returns (bool ok, bytes4 sel)
    {
        bytes memory ret;
        bytes memory cd = abi.encodeWithSelector(SEL_MINE_RUN, multiplier);
        // A one-shot prank is spent by the selection read below; re-apply it to every later call.
        (VmSafe.CallerMode mode, address sender, address origin) = _jvm.readCallers();
        bool once = mode == VmSafe.CallerMode.Prank;
        uint8 progress;
        if (gasLimit != 0) {
            (ok, ret, progress) = _recordedCall(game, gasLimit, cd, once, sender, origin);
            return _settle(ok, ret, game, gasLimit, allowed, site, _after(game, ok, progress, once, sender, origin), progress);
        }
        uint8 action = _selected(game);
        if (action == ACTION_UNREAD) {
            ++judgeUnread;
            (ok, ret, progress) = _recordedCall(game, 0, cd, once, sender, origin);
            return _settle(ok, ret, game, 0, allowed, site, _after(game, ok, progress, once, sender, origin), progress);
        }
        uint256 g = _admissionGas(game, action);
        uint32 drawn = multiplier == 0 ? _drawMultiplier() : multiplier;
        _coolProtocol(game);
        (ok, ret, progress) = _recordedCall(game, g, abi.encodeWithSelector(SEL_MINE_RUN, drawn), once, sender, origin);
        if (!ok && drawn != 0 && drawn < DEFAULT_MULTIPLIER && _isGasRefusal(ret)) {
            // Below 1x a continuation admitted on a scaled estimate may overrun and roll back its
            // worker, taking the first unit with it: a keeper's own loss, never a commit. The
            // ample call below still has to progress.
            ++judgeLowCalibrationRefusals;
            ++judgeCalls;
        } else {
            (ok, sel) = _settle(ok, ret, game, g, allowed, site, action, progress);
            if (!ok || action == ACTION_IDLE || action == ACTION_WAIT) return (ok, sel);
            // A refusal leaves the same selection; the ample call below would only repeat it.
            if (progress == ChainProgress.NONE || progress == ChainProgress.REFUSED) return (ok, sel);
        }
        _reprank(once, sender, origin);
        action = _selected(game);
        if (action == ACTION_IDLE || action == ACTION_WAIT || action == ACTION_UNREAD) return (true, bytes4(0));
        (ok, ret, progress) = _recordedCall(game, 0, cd, once, sender, origin);
        return _settle(ok, ret, game, 0, allowed, site, action, progress);
    }

    /// @dev One mineRun, under state-diff recording when it carries at most a transaction's gas, the
    ///      one-shot prank (if any) in force last. `g == 0` is an ample call (AMPLE_GAS).
    function _recordedCall(address game, uint256 g, bytes memory cd, bool once, address sender, address origin)
        private
        returns (bool ok, bytes memory ret, uint8 progress)
    {
        if (g == 0 || g > TX_GAS_CAP) {
            _reprank(once, sender, origin);
            (ok, ret) = game.call{gas: g == 0 ? AMPLE_GAS : g}(cd);
            ChainProgress.discard();
            return (ok, ret, ChainProgress.UNCHECKED);
        }
        ChainProgress.start();
        _reprank(once, sender, origin);
        (ok, ret) = game.call{gas: g}(cd);
        progress = ChainProgress.stop();
    }

    /// @dev Re-applies a one-shot prank once a call has spent it; a prank still pending stands
    ///      (Foundry refuses to overwrite an unspent prank).
    function _reprank(bool once, address sender, address origin) private {
        if (!once) return;
        (VmSafe.CallerMode mode,,) = _jvm.readCallers();
        if (mode != VmSafe.CallerMode.Prank) _jvm.prank(sender, origin);
    }

    /// @dev The selection after a call that committed nothing is the one the call saw (ACTION_UNREAD
    ///      when the call progressed or reverted, or when the selection cannot be read).
    function _after(address game, bool ok, uint8 progress, bool once, address sender, address origin)
        private
        returns (uint8)
    {
        if (!ok || progress == ChainProgress.PROGRESSED || progress == ChainProgress.UNCHECKED) return ACTION_UNREAD;
        _reprank(once, sender, origin);
        return _selected(game);
    }

    uint32 private constant DEFAULT_MULTIPLIER = 10_000;

    /// @dev Half the judged calls run at the default calibration; the rest at the lowest (0.25x), below
    ///      1x, or above it. Calibration only moves where work splits, so every invariant and the
    ///      starved-dependency oracle must hold at each.
    function _drawMultiplier() private returns (uint32) {
        uint256 seed = uint256(keccak256(abi.encode("judge multiplier", ++_judgeNonce, block.timestamp)));
        uint256 mode = seed % 8;
        if (mode < 4) return 0;
        ++judgeCalibratedCalls;
        if (mode == 4) return 2_500;
        if (mode == 5) return uint32(2_500 + (seed >> 8) % 7_500);
        if (mode == 6) return uint32(10_001 + (seed >> 8) % 30_000);
        return 40_000;
    }

    function _isGasRefusal(bytes memory ret) private pure returns (bool) {
        return ret.length == 0 || _is(ret, SEL_INSUFFICIENT_GAS) || _is(ret, SEL_WORK_GAS_BOUND)
            || _is(ret, SEL_EMPTY_REVERT);
    }

    /// @dev Calls the dependency mocks counted as arriving below the protocol's admission for their
    ///      entry point (zero when a mock is absent or replaced).
    function judgeStarvedDependencyCalls() public view returns (uint256 n, bytes4 first) {
        address[2] memory deps = [ContractAddresses.VRF_COORDINATOR, ContractAddresses.STETH_TOKEN];
        for (uint256 i; i < 2; ++i) {
            (bool ok, bytes memory ret) = deps[i].staticcall(abi.encodeWithSignature("starvedCalls()"));
            if (!ok || ret.length != 32) continue;
            uint256 c = abi.decode(ret, (uint256));
            if (c == 0) continue;
            if (n == 0) {
                (ok, ret) = deps[i].staticcall(abi.encodeWithSignature("firstStarvedSelector()"));
                if (ok && ret.length == 32) first = abi.decode(ret, (bytes4));
            }
            n += c;
        }
    }

    /// @dev `minerAction()` as the current caller, or ACTION_UNREAD when it cannot be read.
    function _selected(address game) private view returns (uint8) {
        (bool ok, bytes memory ret) = game.staticcall(abi.encodeWithSignature("minerAction()"));
        if (!ok || ret.length != 32) return ACTION_UNREAD;
        uint256 a = abi.decode(ret, (uint256));
        return a < ACTION_UNREAD ? uint8(a) : ACTION_UNREAD;
    }

    function _admissionGas(address game, uint8 action) private returns (uint256 g) {
        bool sale = uint8(uint256(_jvm.load(game, bytes32(GameSlots.DEGENESIS_CLOSED)))
            >> (GameSlots.DEGENESIS_CLOSED_OFFSET * 8)) < 7;
        uint256 minimum = MineFlipAdmission.minGas(action, sale);
        if (minimum > TX_GAS_CAP) ++judgeAboveCap;
        g = drawAdmissionGas(minimum, uint256(keccak256(abi.encode(++_judgeNonce, block.timestamp, block.number))));
        if (g == minimum) ++judgeAtMinimum;
        ++judgeDrawnCalls;
        ++judgeActionCalls[action];
    }

    /// @notice Gas for one judged call: the minimum, within 300k above it, or anywhere up to
    ///         TX_GAS_CAP; exactly TX_GAS_CAP when the minimum exceeds it.
    function drawAdmissionGas(uint256 minimum, uint256 seed) public pure returns (uint256) {
        if (minimum >= TX_GAS_CAP) return TX_GAS_CAP;
        uint256 mode = seed % 4;
        if (mode == 0) return minimum;
        if (mode == 1) {
            uint256 g = minimum + (seed >> 8) % 300_000;
            return g > TX_GAS_CAP ? TX_GAS_CAP : g;
        }
        return minimum + (seed >> 8) % (TX_GAS_CAP - minimum + 1);
    }

    /// @dev A keeper's transaction starts with every protocol storage slot cold. `cool` resets slot
    ///      warmth only (account access stays warm, at most 2,500 gas per account under a keeper's
    ///      cost) and clears the account's touched mark, which would discard every change to that
    ///      account when the current call's transaction commits, so each account is re-touched.
    function _coolProtocol(address game) private {
        _cool(game);
        address[45] memory a = [
            ContractAddresses.CRAPS_LIFECYCLE_MODULE, ContractAddresses.GAME_ACTIONS_MODULE,
            ContractAddresses.GAME_PURCHASE_MODULE, ContractAddresses.ICONS_32, ContractAddresses.GAME_MINT_MODULE,
            ContractAddresses.GAME_ADVANCE_MODULE, ContractAddresses.GAME_WHALE_MODULE,
            ContractAddresses.GAME_JACKPOT_MODULE, ContractAddresses.GAME_DECIMATOR_MODULE,
            ContractAddresses.GAME_GAMEOVER_MODULE, ContractAddresses.GAME_LOOTBOX_MODULE,
            ContractAddresses.GAME_BOON_MODULE, ContractAddresses.GAME_DEGENERETTE_MODULE,
            ContractAddresses.GAME_BINGO_MODULE, ContractAddresses.GAME_AFKING_MODULE, ContractAddresses.COIN,
            ContractAddresses.COINFLIP, ContractAddresses.VAULT, ContractAddresses.AFFILIATE,
            ContractAddresses.JACKPOTS, ContractAddresses.QUESTS, ContractAddresses.GAME, ContractAddresses.SDGNRS,
            ContractAddresses.DGNRS, ContractAddresses.ADMIN, ContractAddresses.DEITY_PASS, ContractAddresses.WWXRP,
            ContractAddresses.STETH_TOKEN, ContractAddresses.GNRUS, ContractAddresses.GAME_FOILPACK_MODULE,
            ContractAddresses.AFKING_SUB_TOKEN, ContractAddresses.PARIMUTUEL, ContractAddresses.RECORD_BOUNTY,
            ContractAddresses.CREATOR, ContractAddresses.VRF_COORDINATOR, ContractAddresses.ENS_REVERSE_REGISTRAR,
            ContractAddresses.CRAPS, ContractAddresses.CRAPS_ENGINE, ContractAddresses.JACKPOT_BATTLE,
            ContractAddresses.GAME_TICKET_MODULE, ContractAddresses.GAME_MINER_MODULE,
            ContractAddresses.GAME_RNG_MODULE, ContractAddresses.GAME_JACKPOT_DRAW_MODULE,
            ContractAddresses.GAME_DEGENESIS_MODULE, ContractAddresses.OWNER_GOVERNANCE
        ];
        for (uint256 i; i < a.length; ++i) _cool(a[i]);
    }

    function _cool(address account) private {
        _jvm.cool(account);
        _jvm.deal(account, account.balance);
    }

    /// @dev Count one call and judge its result. With a read selection the result must match it:
    ///      Idle answers NoWork, Wait answers RngNotReady (each still subject to the site's classes),
    ///      and any other action must succeed.
    function _settle(
        bool ok,
        bytes memory ret,
        address game,
        uint256 g,
        uint8 allowed,
        uint16 site,
        uint8 action,
        uint8 progress
    ) private returns (bool, bytes4 sel) {
        ++judgeCalls;
        if (ok) return (true, _success(ret, game, g, site, action, progress));
        if (action == ACTION_UNREAD) return (false, _classify(ret, game, g, allowed, site, action));
        if (action == ACTION_IDLE) {
            if (!_is(ret, SEL_NO_WORK)) allowed = 0;
            allowed &= OK_IDLE;
        } else if (action == ACTION_WAIT) {
            if (!_is(ret, SEL_RNG_NOT_READY)) allowed = 0;
            allowed &= OK_WAIT;
        } else {
            allowed = 0;
        }
        return (false, _classify(ret, game, g, allowed, site, action));
    }

    /// @dev A success must follow work the selection reported, and commit it (or be a refusal).
    function _success(bytes memory ret, address game, uint256 g, uint16 site, uint8 action, uint8 progress)
        private
        returns (bytes4)
    {
        ++judgeSucceeded;
        if (action == ACTION_IDLE || action == ACTION_WAIT) {
            _record(ret, game, g, site, bytes4(0), action);
            return bytes4(0);
        }
        if (progress == ChainProgress.PROGRESSED) {
            ++judgeProgressed;
            return bytes4(0);
        }
        if (progress == ChainProgress.UNCHECKED) {
            ++judgeUnchecked;
            return bytes4(0);
        }
        if (ChainProgress.refusalAllowed(progress, action)) {
            ++judgeRefusals;
            return bytes4(0);
        }
        _record(ret, game, g, site, SEL_NO_PROGRESS, action);
        return SEL_NO_PROGRESS;
    }

    function _is(bytes memory ret, bytes4 want) private pure returns (bool) {
        return ret.length == 4 && bytes4(ret) == want;
    }

    /// @dev Judge a revert already captured by a handler that issues the call itself (low-level
    ///      `call` sites with their own gas ladders). Counts the call; success is counted by the caller via
    ///      `_judgeSuccess`.
    function _judgeRevert(address game, bytes memory ret, uint256 gasLimit, uint8 allowed, uint16 site)
        internal
        returns (bytes4)
    {
        ++judgeCalls;
        return _classify(ret, game, gasLimit, allowed, site, ACTION_UNREAD);
    }

    /// @dev A success the handler issued with all its gas: counted, not recorded.
    function _judgeSuccess() internal {
        ++judgeCalls;
        ++judgeSucceeded;
        ++judgeUnchecked;
    }

    function _classify(bytes memory ret, address game, uint256 gasLimit, uint8 allowed, uint16 site, uint8 action)
        private
        returns (bytes4 sel)
    {
        if (ret.length >= 4) {
            assembly ("memory-safe") { sel := mload(add(ret, 32)) }
        }
        uint256 key = (uint256(uint32(sel)) << 16) | site;
        if (judgeKeyCount[key]++ == 0) _judgeSeen.push(key);
        bool legit;
        if (ret.length == 0) {
            legit = allowed & OK_GAS != 0;
        } else if (ret.length == 4) {
            if (sel == SEL_NO_WORK) legit = allowed & OK_IDLE != 0;
            else if (sel == SEL_RNG_NOT_READY) legit = allowed & OK_WAIT != 0;
            else if (sel == SEL_INSUFFICIENT_GAS || sel == SEL_WORK_GAS_BOUND || sel == SEL_EMPTY_REVERT) {
                legit = allowed & OK_GAS != 0;
            }
        }
        if (legit) return sel;
        _record(ret, game, gasLimit, site, sel, action);
    }

    function _record(bytes memory ret, address game, uint256 gasLimit, uint16 site, bytes4 sel, uint8 action) private {
        if (judgeUnexpected++ == 0) {
            judgeFirstSel = sel;
            judgeFirstSite = site;
            judgeFirstGas = gasLimit;
            judgeFirstAction = action;
            uint256 n = ret.length > 100 ? 100 : ret.length;
            bytes memory head = new bytes(n);
            for (uint256 i; i < n; ++i) head[i] = ret[i];
            judgeFirstData = head;
            (bool a, bytes memory lv) = game.staticcall(abi.encodeWithSignature("currentLvl()"));
            if (a && lv.length == 32) judgeFirstLevel = uint24(abi.decode(lv, (uint256)));
            (a, lv) = game.staticcall(abi.encodeWithSignature("gameOver()"));
            if (a && lv.length == 32) judgeFirstGameOver = abi.decode(lv, (uint256)) != 0;
            (a, lv) = game.staticcall(abi.encodeWithSignature("rngLocked()"));
            if (a && lv.length == 32) judgeFirstRngLocked = abi.decode(lv, (uint256)) != 0;
        }
    }

    /// @notice Reverts when any unexpected mineRun revert was recorded; the message names the first.
    function judgeCheck(string memory suite) public view {
        (uint256 starved, bytes4 firstStarved) = judgeStarvedDependencyCalls();
        if (starved != 0) {
            revert(string.concat(suite, ": dependency reached below its admission x", _u(starved),
                " first selector ", _hex4(firstStarved)));
        }
        if (judgeUnexpected == 0) return;
        revert(
            string.concat(
                suite,
                ": unexpected mineRun revert x",
                _u(judgeUnexpected),
                " first selector ",
                _hex4(judgeFirstSel),
                " site ",
                _u(judgeFirstSite),
                " level ",
                _u(judgeFirstLevel),
                " gas ",
                _u(judgeFirstGas),
                judgeFirstAction == ACTION_UNREAD ? "" : string.concat(" action ", _u(judgeFirstAction)),
                judgeFirstGameOver ? " gameOver" : "",
                judgeFirstRngLocked ? " rngLocked" : ""
            )
        );
    }

    /// @notice Number of distinct revert selectors seen and the selector at `i` (for tally printing).
    function judgeSeenCount() external view returns (uint256) {
        return _judgeSeen.length;
    }

    function judgeSeenAt(uint256 i) external view returns (uint256) {
        return _judgeSeen[i];
    }

    function _u(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v;
        uint256 d;
        while (t != 0) {
            ++d;
            t /= 10;
        }
        bytes memory b = new bytes(d);
        while (v != 0) {
            b[--d] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }

    function _hex4(bytes4 s) private pure returns (string memory) {
        bytes memory h = "0123456789abcdef";
        bytes memory o = new bytes(10);
        o[0] = "0";
        o[1] = "x";
        for (uint256 i; i < 4; ++i) {
            o[2 + 2 * i] = h[uint8(s[i]) >> 4];
            o[3 + 2 * i] = h[uint8(s[i]) & 15];
        }
        return string(o);
    }
}

/// @notice Campaign tally for a suite's `afterInvariant`: accumulates the handler's per-site revert
///         selectors into process-global env totals (suite-unique `CJ_<suite>_` keys) and prints the
///         running totals, when CHAIN_JUDGE_TALLY=1. Forge prints the logs of one run only, so the env
///         totals are what make the last printed line the whole campaign's. Runs in the suite, not the
///         handler, so no state-changing function is added to the fuzzed handler.
library ChainCallTally {
    Vm private constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function tally(string memory suite, ChainCallJudge j) internal {
        if (!_vm.envOr("CHAIN_JUDGE_TALLY", false)) return;
        string memory base = string.concat("CJ_", suite, "_");
        uint256 calls = _bump(string.concat(base, "calls"), j.judgeCalls());
        uint256 ok = _bump(string.concat(base, "ok"), j.judgeSucceeded());
        console2.log(string.concat("JUDGE|", suite, "|calls|", _vm.toString(calls), "|ok|", _vm.toString(ok),
            "|progressed|", _vm.toString(_bump(string.concat(base, "progressed"), j.judgeProgressed())),
            "|refusals|", _vm.toString(_bump(string.concat(base, "refusals"), j.judgeRefusals())),
            "|unchecked|", _vm.toString(_bump(string.concat(base, "unchecked"), j.judgeUnchecked()))));
        uint256 n = j.judgeSeenCount();
        string memory listKey = string.concat(base, "keys");
        string memory list = _vm.envOr(listKey, string(""));
        for (uint256 i; i < n; ++i) {
            uint256 key = j.judgeSeenAt(i);
            string memory k = string.concat(
                "site", _vm.toString(key & 0xffff), "_", _vm.toString(abi.encodePacked(bytes4(uint32(key >> 16))))
            );
            if (!_vm.envExists(string.concat(base, k))) list = bytes(list).length == 0 ? k : string.concat(list, ",", k);
            _bump(string.concat(base, k), j.judgeKeyCount(key));
        }
        if (bytes(list).length != 0) _vm.setEnv(listKey, list);
        // Every selector seen so far in the campaign, not only this run's: the totals are cumulative.
        if (bytes(list).length == 0) return;
        string[] memory ks = _vm.split(list, ",");
        for (uint256 i; i < ks.length; ++i) {
            console2.log(string.concat("JUDGE|", suite, "|", ks[i], "|", _vm.toString(_vm.envOr(string.concat(base, ks[i]), uint256(0)))));
        }
    }

    function _bump(string memory key, uint256 add) private returns (uint256 total) {
        total = _vm.envOr(key, uint256(0)) + add;
        _vm.setEnv(key, _vm.toString(total));
    }
}

/// @notice End-of-run stall probe for a suite's `afterInvariant`. On a snapshot it drives the engine
///         to quiescence in keeper-sized calls (TX_GAS_CAP each): before each call it delivers the
///         outstanding VRF word (if any),
///         and every successful call must commit work (see ChainProgress). It stops healthy on NoWork
///         with `advanceDue()` false, on RngNotReady when the request was already answered (raw 0/1
///         leave it pending for the admin retry or the dead-VRF path, by design), or on a refused
///         request or terminal attempt (the engine waits on its dependency). RngNotReady after the
///         probe itself delivered a word, NoWork while work is owed, any other revert with a full
///         transaction's gas, or a success that committed nothing is a stall.
///         Completion is a ranking, not a guess: a Tickets call that strictly lowers the active read
///         queue's owed total is ranked (owed is a natural number, so ranked calls cannot go on
///         forever), and every other call spends UNRANKED_BUDGET, so work that commits state without
///         finishing is flagged. A ranked drain runs to its end unless it has spent RANKED_GAS or the
///         test's own gas would run short first; then the probe stops, still ranked. The drain is one
///         transaction, whose every write Foundry holds until it ends, so RANKED_GAS bounds its
///         memory; AdvanceLiveness's deep replays drain the largest known backlog in full. The
///         snapshot is restored, so the suite's own end-of-run checks are unaffected.
library ChainStallProbe {
    Vm private constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant UNRANKED_BUDGET = 1_000;
    uint256 internal constant RANKED_GAS = 100_000_000_000;
    uint256 internal constant GAS_RESERVE = 2_000_000_000;
    bytes4 private constant SEL_NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 private constant SEL_RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));

    function check(string memory suite, address game, MockVRFCoordinator vrf) internal {
        uint256 snap = _vm.snapshotState();
        (string memory why, uint256 calls, uint256 unranked) = _drain(game, vrf);
        _vm.revertToStateAndDelete(snap);
        if (_vm.envOr("CHAIN_JUDGE_TALLY", false)) {
            console2.log(string.concat("PROBE|", suite, "|calls|", _vm.toString(calls), "|unranked|", _vm.toString(unranked)));
        }
        if (bytes(why).length != 0) revert(string.concat(suite, ": ", why));
    }

    function _drain(address game, MockVRFCoordinator vrf)
        private
        returns (string memory why, uint256 calls, uint256 unranked)
    {
        uint256 gasStart = gasleft();
        for (; ; ++calls) {
            bool delivered = _deliver(vrf);
            uint8 action = _selected(game);
            uint24 key;
            uint256 owedBefore;
            if (action == MineFlipAdmission.TICKETS) {
                key = _activeTicketKey(game);
                if (key != 0) owedBefore = _queueOwed(game, key);
            }
            ChainProgress.start();
            (bool ok, bytes memory ret) = game.call{gas: ChainProgress.TX_GAS_CAP}(
                abi.encodeWithSelector(bytes4(keccak256("mineRun(uint32)")), uint32(0)));
            uint8 progress = ChainProgress.stop();
            if (!ok) return (_stopped(game, ret, delivered), calls, unranked);
            if (progress != ChainProgress.PROGRESSED) {
                if (ChainProgress.refusalAllowed(progress, action)) return ("", calls + 1, unranked);
                why = string.concat("stalled: mineRun succeeded without committing work, action ",
                    _vm.toString(action), ", after ", _vm.toString(calls), " calls");
                return (why, calls + 1, unranked);
            }
            if (key != 0 && _queueOwed(game, key) < owedBefore) {
                if (gasleft() < GAS_RESERVE || gasStart - gasleft() > RANKED_GAS) return ("", calls + 1, unranked);
            } else if (++unranked > UNRANKED_BUDGET) {
                why = string.concat("stalled: no quiescence within ", _vm.toString(UNRANKED_BUDGET),
                    " unranked calls (", _vm.toString(calls + 1), " in all)");
                return (why, calls + 1, unranked);
            }
        }
    }

    function _deliver(MockVRFCoordinator vrf) private returns (bool delivered) {
        uint256 req = vrf.lastRequestId();
        if (req == 0) return false;
        (,, bool done) = vrf.pendingRequests(req);
        if (done) return false;
        try vrf.fulfillRandomWords(req, uint256(keccak256(abi.encode("chain-stall-probe", req))) | 2) {
            delivered = true;
        } catch {}
    }

    function _stopped(address game, bytes memory ret, bool delivered) private view returns (string memory) {
        bytes4 sel = ret.length >= 4 ? bytes4(ret) : bytes4(0);
        if (ret.length == 4 && sel == SEL_RNG_NOT_READY) {
            if (delivered) return "stalled: mineRun answers RngNotReady after the outstanding VRF word was delivered";
            return "";
        }
        if (ret.length == 4 && sel == SEL_NO_WORK) {
            (bool a, bytes memory due) = game.staticcall(abi.encodeWithSignature("advanceDue()"));
            if (a && due.length == 32 && abi.decode(due, (uint256)) != 0) {
                return "stalled: mineRun answers NoWork while advanceDue() is true";
            }
            return "";
        }
        return string.concat("stalled: mineRun reverts with a full transaction's gas, selector ",
            _vm.toString(abi.encodePacked(sel)));
    }

    function _selected(address game) private view returns (uint8) {
        (bool ok, bytes memory ret) = game.staticcall(abi.encodeWithSignature("minerAction()"));
        if (!ok || ret.length != 32) return type(uint8).max;
        uint256 a = abi.decode(ret, (uint256));
        return a < type(uint8).max ? uint8(a) : type(uint8).max;
    }

    /// @dev The read queue the ticket drain is working (zero between drains).
    function _activeTicketKey(address game) private view returns (uint24) {
        uint256 word = uint256(_vm.load(game, bytes32(GameSlots.TICKET_LEVEL)));
        return uint24(word >> (GameSlots.TICKET_LEVEL_OFFSET * 8));
    }

    /// @dev Owed balance of one read queue in 1/256 entries, so a final fractional draw still lowers it.
    function _queueOwed(address game, uint24 key) private view returns (uint256 total) {
        uint256 n = TQ.length(game, key);
        for (uint256 i; i < n; ++i) {
            total += uint256(TQ.owedById(game, key, TQ.ownerIdAt(game, key, i))) & ((uint256(1) << 40) - 1);
        }
    }
}
