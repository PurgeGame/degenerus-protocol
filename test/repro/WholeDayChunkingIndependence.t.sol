// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MultiLevelHandler} from "../fuzz/handlers/MultiLevelHandler.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameFunding} from "../helpers/GameFunding.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title WholeDayChunkingIndependence -- caller gas and calibration never change a day's outcome
/// @notice From one snapshot of a mature game (level 10+, real opening), the same staged days are
///         processed twice through `mineRun` by a miner with no wallet ID (unpaid, so no bounty
///         state):
///         - BIG: each call carries 1e9 gas at the minimum calibration (2,500 bps), so a call
///           runs every unit it can reach before a request or the 32-transition cap;
///         - SMALL: each call carries the smallest gas from a ladder that succeeds at the maximum
///           calibration (type(uint32).max bps), so every call runs only its mandatory first unit.
///         VRF answers are a pure function of the request ID, so both runs see the same words.
///         The compared set is every storage slot either run wrote, in every account, plus the
///         ETH balance of every account either run touched: a slot only one run wrote must end at
///         its snapshot value in that run. One between-calls scratch field is excluded (sDGNRS
///         `_settlingReserveLeft`, see `_differs`). Named views (level, pools, claimables, AFKing, tickets,
///         sDGNRS balances, redemption reserve, the day's coinflip result and word) are compared
///         first for readable failures.
contract WholeDayChunkingIndependenceTest is DeployProtocol {
    address private constant MINER = address(0x3141);
    address private constant DRIVER = address(0xC011D);
    address private constant HOLDER = address(0xC011C);
    address private constant SAVER = address(0xC011E);
    uint256 private constant BIG_GAS = 1_000_000_000;
    uint32 private constant BIG_MULTIPLIER = 2_500;
    uint32 private constant SMALL_MULTIPLIER = type(uint32).max;
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    /// @dev Distinct written slots one run may record (a power of two; hash tables are twice it).
    uint256 private constant CAPACITY = 16_384;

    struct Key {
        address account;
        bytes32 slot;
    }

    struct Outcome {
        Key[] keys;
        bytes32[] initial;
        bytes32[] finals;
        bytes32[] keyTable;
        uint256 keyCount;
        address[] accounts;
        uint256[] initialBalances;
        uint256[] balances;
        bytes32[] accountTable;
        uint256 accountCount;
        uint256[] views;
        uint256 calls;
    }

    uint256 private seed;
    uint32[3] private ids;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        MultiLevelHandler opening = new MultiLevelHandler(game, mockVRF, 1);
        opening.scriptedOpening();
        assertGe(game.currentLvl(), 10, "fixture: real mature opening");
        vm.deal(DRIVER, 1_000_000 ether);
        vm.deal(SAVER, 100 ether);
        vm.deal(address(this), 100 ether);
        mockVRF.fundSubscriptionWithNative{value: 100 ether}(1);
        GameFunding.credit(2, 100 ether);
        _giveWalletId(HOLDER);
        uint256 allocation = sdgnrs.totalSupply() / 100;
        vm.prank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, HOLDER, allocation);
        _drain();
        ids[0] = game.walletIdOf_g3120(DRIVER);
        ids[1] = game.walletIdOf_g3120(HOLDER);
        ids[2] = _giveWalletId(SAVER);
    }

    // ---------------------------------------------------------------------
    // Fixture driving (outside the compared runs)
    // ---------------------------------------------------------------------

    function _fulfill() private returns (bool) {
        uint256 request = mockVRF.lastRequestId();
        if (request == 0) return false;
        (,, bool done) = mockVRF.pendingRequests(request);
        if (done) return false;
        mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode(seed, request))) | 2);
        return true;
    }

    function _drain() private {
        for (uint256 i; i < 2_000; ++i) {
            _fulfill();
            if (game.nextMinerAction() == 0) return;
            vm.prank(MINER);
            game.mineRun{gas: 30_000_000}(0);
        }
        fail("fixture: engine did not drain");
    }

    /// @dev One day's player actions, identical in both runs: a ticket and box purchase sized by
    ///      the seed, a redemption burn and an AFKing deposit, then the day boundary.
    function _stageDay(uint256 day) private {
        (, , , bool locked, uint256 price) = game.purchaseInfo_g1027();
        assertFalse(locked, "staged on an unlocked day");
        uint256 box = (20 + uint256(keccak256(abi.encode(seed, day, "box"))) % 101) * 1 ether;
        uint256 qty = 400 * (1 + uint256(keccak256(abi.encode(seed, day, "qty"))) % 40);
        vm.prank(DRIVER);
        game.purchaseOrderFor{value: price * qty / 400 + box}(0, qty, BoxOrderLib.boCustomFloor(box), bytes32(0),
            MintPaymentKind.DirectEth, false);
        vm.prank(DRIVER);
        game.purchaseOrderFor{value: 25 * price * 3}(0, 0, BoxOrderLib.boLarges(3), bytes32(0),
            MintPaymentKind.DirectEth, false);
        uint256 holding = sdgnrs.balanceOf(HOLDER);
        if (holding > 8) {
            vm.prank(HOLDER);
            sdgnrs.burn(holding / 8);
        }
        vm.prank(SAVER);
        game.depositAfkingFunding{value: 1 ether}(ids[2]);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
    }

    // ---------------------------------------------------------------------
    // The compared runs
    // ---------------------------------------------------------------------

    function _mine(bool big) private returns (bool worked) {
        uint256[12] memory ladder = [uint256(250_000), 400_000, 600_000, 900_000, 1_300_000, 1_900_000,
            2_800_000, 4_000_000, 6_000_000, 9_000_000, 13_000_000, 16_777_216];
        bytes memory last;
        for (uint256 r; r < (big ? 1 : ladder.length); ++r) {
            vm.prank(MINER);
            (bool ok, bytes memory err) = address(game).call{gas: big ? BIG_GAS : ladder[r]}(
                abi.encodeWithSignature("mineRun(uint32)", big ? BIG_MULTIPLIER : SMALL_MULTIPLIER));
            if (ok) return true;
            last = err;
        }
        bytes4 sel = bytes4(last);
        assertTrue(last.length == 4 && (sel == NO_WORK || sel == RNG_NOT_READY), "a mining call failed with work left");
        return false;
    }

    /// @dev One recorded step, run as an external self-call so its state-diff memory is freed on
    ///      return: op 0 stages day `day`; op 1 answers any pending request and makes one mining
    ///      call. Returns the step's distinct writes and touched accounts with their prior values.
    ///      status: 1 = a mining call succeeded, 2 = no work but a request was answered, 0 = idle.
    function recordedStep(uint8 op, bool big, uint256 day)
        external
        returns (uint8 status, Key[] memory keys, bytes32[] memory prevs, address[] memory accounts, uint256[] memory oldBalances)
    {
        require(msg.sender == address(this), "self only");
        vm.startStateDiffRecording();
        if (op == 0) {
            _stageDay(day);
        } else {
            _fulfill();
            if (_mine(big)) status = 1;
            else if (_fulfill()) status = 2;
        }
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        uint256 writes;
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                if (accesses[i].storageAccesses[j].isWrite) ++writes;
            }
        }
        keys = new Key[](writes);
        prevs = new bytes32[](writes);
        accounts = new address[](accesses.length);
        oldBalances = new uint256[](accesses.length);
        uint256 k;
        for (uint256 i; i < accesses.length; ++i) {
            accounts[i] = accesses[i].account;
            oldBalances[i] = accesses[i].oldBalance;
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory st = accesses[i].storageAccesses[j];
                if (!st.isWrite) continue;
                keys[k] = Key(st.account, st.slot);
                prevs[k] = st.previousValue;
                ++k;
            }
        }
    }

    function _fold(Outcome memory o, Key[] memory keys, bytes32[] memory prevs, address[] memory accounts,
        uint256[] memory oldBalances) private pure
    {
        for (uint256 i; i < keys.length; ++i) {
            if (!_insert(o.keyTable, _hash(keys[i].account, keys[i].slot))) continue;
            require(o.keyCount < o.keys.length, "harness: raise CAPACITY");
            o.keys[o.keyCount] = keys[i];
            o.initial[o.keyCount] = prevs[i];
            ++o.keyCount;
        }
        for (uint256 i; i < accounts.length; ++i) {
            if (!_insert(o.accountTable, _hash(accounts[i], bytes32(0)))) continue;
            require(o.accountCount < o.accounts.length, "harness: raise CAPACITY");
            o.accounts[o.accountCount] = accounts[i];
            o.initialBalances[o.accountCount] = oldBalances[i];
            ++o.accountCount;
        }
    }

    function _views() private view returns (uint256[] memory v) {
        v = new uint256[](24);
        uint256 n;
        v[n++] = game.currentLvl();
        v[n++] = game.currentPrizePoolView();
        v[n++] = game.nextPrizePoolView();
        v[n++] = game.futurePrizePoolView();
        v[n++] = game.claimablePoolView();
        v[n++] = game.yieldAccumulatorView();
        v[n++] = game.redemptionReserve();
        v[n++] = address(game).balance;
        v[n++] = mockStETH.balanceOf(address(game));
        for (uint256 i; i < 3; ++i) {
            address who = i == 0 ? DRIVER : (i == 1 ? HOLDER : SAVER);
            v[n++] = game.claimableWinningsOf(who);
            v[n++] = _fixtureAfking(ids[i]);
            v[n++] = game.entriesOwedView(game.currentLvl() + 1, who);
            v[n++] = sdgnrs.balanceOf(who);
        }
        uint24 day = game.currentDayView_g542950();
        (uint16 reward, bool win) = coinflip.getCoinflipDayResult(day);
        v[n++] = reward;
        v[n++] = win ? 1 : 0;
        v[n++] = game.rngWordForDay(day);
    }

    // ---- memory hash set of (account, slot) keys; zero marks an empty bucket ----

    function _hash(address account, bytes32 slot) private pure returns (bytes32 h) {
        h = keccak256(abi.encode(account, slot));
        if (h == bytes32(0)) h = bytes32(uint256(1));
    }

    /// @return added True when `h` was not yet in the table.
    function _insert(bytes32[] memory table, bytes32 h) private pure returns (bool added) {
        uint256 mask = table.length - 1;
        for (uint256 i = uint256(h) & mask; ; i = (i + 1) & mask) {
            if (table[i] == h) return false;
            if (table[i] == bytes32(0)) {
                table[i] = h;
                return true;
            }
        }
    }

    function _contains(bytes32[] memory table, bytes32 h) private pure returns (bool) {
        uint256 mask = table.length - 1;
        for (uint256 i = uint256(h) & mask; ; i = (i + 1) & mask) {
            if (table[i] == h) return true;
            if (table[i] == bytes32(0)) return false;
        }
    }

    /// @dev Runs the days step by step, folding every distinct written slot (with its value at the
    ///      snapshot, the first write's previous value) and every distinct touched account (with
    ///      its balance at the snapshot), then reads their final values.
    function _outcome(bool big, uint256 dayCount) private returns (Outcome memory o) {
        o.keys = new Key[](CAPACITY);
        o.initial = new bytes32[](CAPACITY);
        o.finals = new bytes32[](CAPACITY);
        o.keyTable = new bytes32[](CAPACITY * 2);
        o.accounts = new address[](CAPACITY / 8);
        o.initialBalances = new uint256[](CAPACITY / 8);
        o.balances = new uint256[](CAPACITY / 8);
        o.accountTable = new bytes32[](CAPACITY / 4);
        for (uint256 d; d < dayCount; ++d) {
            for (uint256 i; ; ++i) {
                require(i < 50_000, "harness: day did not drain");
                (uint8 status, Key[] memory keys, bytes32[] memory prevs, address[] memory accounts,
                    uint256[] memory oldBalances) = this.recordedStep(i == 0 ? 0 : 1, big, d);
                _fold(o, keys, prevs, accounts, oldBalances);
                if (i == 0) continue;
                if (status == 1) ++o.calls;
                else if (status == 0) break;
            }
        }
        for (uint256 k; k < o.keyCount; ++k) o.finals[k] = vm.load(o.keys[k].account, o.keys[k].slot);
        for (uint256 a; a < o.accountCount; ++a) o.balances[a] = o.accounts[a].balance;
        o.views = _views();
    }

    /// @dev `small` is a finished run whose state has been replaced by `big`'s (the live state).
    ///      A slot written by either run must end equal: a slot only one run wrote must end at its
    ///      snapshot value in that run. The same for account balances.
    function _assertSameEnd(Outcome memory small, Outcome memory big) private {
        for (uint256 i; i < small.views.length; ++i) {
            assertEq(big.views[i], small.views[i], string.concat("view differs: ", vm.toString(i)));
        }
        uint256 diffs;
        for (uint256 i; i < small.keyCount; ++i) {
            Key memory key = small.keys[i];
            bytes32 live = vm.load(key.account, key.slot);
            if (_differs(key, live, small.finals[i])) diffs = _report(diffs, key, small.finals[i], live);
        }
        for (uint256 i; i < big.keyCount; ++i) {
            Key memory key = big.keys[i];
            if (_contains(small.keyTable, _hash(key.account, key.slot))) continue;
            // The chunked run never wrote it: it ended at the snapshot value.
            if (_differs(key, big.finals[i], big.initial[i])) diffs = _report(diffs, key, big.initial[i], big.finals[i]);
        }
        for (uint256 i; i < small.accountCount; ++i) {
            if (small.accounts[i].balance != small.balances[i]) {
                ++diffs;
                emit log_named_address("ETH balance differs", small.accounts[i]);
            }
        }
        for (uint256 i; i < big.accountCount; ++i) {
            if (_contains(small.accountTable, _hash(big.accounts[i], bytes32(0)))) continue;
            if (big.balances[i] != big.initialBalances[i]) {
                ++diffs;
                emit log_named_address("ETH balance differs (large run only)", big.accounts[i]);
            }
        }
        assertEq(diffs, 0, "the chunked run diverged from the large-call run");
    }

    /// @dev The one excluded field: sDGNRS `_settlingReserveLeft` (slot 7, bytes 20..31), the
    ///      settling batch's unassigned rolled total carried between settlement calls only. A
    ///      settlement that spans calls writes it before each break; the call that finishes the
    ///      batch reads it and leaves it stale; a one-call settlement never writes it. It is read
    ///      only while the same batch is mid-settlement (`batch.roll != 0`), so a stale value is
    ///      dead. The batch's outcome fields (`_pendingRedemptionEthValue`, roll, payouts, claims)
    ///      share no bits with it and stay compared.
    function _differs(Key memory key, bytes32 a, bytes32 b) private pure returns (bool) {
        uint256 ignored = key.account == ContractAddresses.SDGNRS && key.slot == bytes32(uint256(7))
            ? ~uint256(0) << 160 : 0;
        return (uint256(a) & ~ignored) != (uint256(b) & ~ignored);
    }

    function _report(uint256 diffs, Key memory key, bytes32 small, bytes32 big) private returns (uint256) {
        if (diffs < 20) {
            emit log_named_address("slot differs: account", key.account);
            emit log_named_bytes32("  slot", key.slot);
            emit log_named_bytes32("  chunked run", small);
            emit log_named_bytes32("  large-call run", big);
        }
        return diffs + 1;
    }

    function _compare(uint256 dayCount) private {
        uint256 levelBefore = game.currentLvl();
        uint256 snap = vm.snapshotState();
        Outcome memory small = _outcome(false, dayCount);
        vm.revertToState(snap);
        Outcome memory big = _outcome(true, dayCount);
        _assertSameEnd(small, big);
        emit log_named_uint("large-run calls", big.calls);
        emit log_named_uint("chunked-run calls", small.calls);
        emit log_named_uint("distinct slots written (chunked run)", small.keyCount);
        emit log_named_uint("distinct slots written (large run)", big.keyCount);
        emit log_named_uint("levels gained", game.currentLvl() - levelBefore);
        assertGt(small.calls, big.calls * 4, "the chunked run really split the work");
        assertGt(small.keyCount, 0, "the runs wrote state");
    }

    /// forge-config: default.fuzz.runs = 3
    /// forge-config: deep.fuzz.runs = 16
    function testFuzz_OneDayChunkedEqualsLargeCalls(uint256 entropy) public {
        seed = entropy;
        _compare(1);
    }

    /// forge-config: default.fuzz.runs = 2
    /// forge-config: deep.fuzz.runs = 8
    function testFuzz_ThreeDaysChunkedEqualLargeCalls(uint256 entropy) public {
        seed = entropy;
        _compare(3);
    }
}
