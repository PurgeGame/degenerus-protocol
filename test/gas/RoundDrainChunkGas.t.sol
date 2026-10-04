// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {MintBucketSeed} from "../helpers/MintBucketSeed.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

import {Test, Vm} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {TicketEntropy} from "../../contracts/libraries/TicketEntropy.sol";

/// @dev Extends the production mint module so the ticket worker runs in THIS contract's
///      storage, through the compatibility door or the metered `runTicketWork` entry the miner
///      uses; adds queue seeders only.
contract ChunkHarness is MintBucketSeed {
    /// @dev The mint module answers the liveness tail through the Game's view; this harness is
    ///      not deployed at the Game's address, so it evaluates the tail in place.
    function _pastDeadlineTriggered(uint24 today, uint24 idx)
        internal
        view
        override(DegenerusGameMintModule)
        returns (bool)
    {
        return DegenerusGameStorage._pastDeadlineTriggered(today, idx);
    }

    /// @dev Pin `level` so `lvl` sits inside the minted read window the drain walks: the sweep
    ///      covers [anchor-1 .. _mintCeiling()] and the measured call passes anchor = lvl + 1
    ///      (the purchase level), so level = lvl gives the window [lvl .. lvl + 1] and routes a
    ///      purchase at `lvl` (<= _mintCeiling() = level + 1) onto the double-buffer write key.
    ///      Without it the harness's default level 0 caps the window at level 1 and every chunk
    ///      measured at a higher level walks nothing.
    function _pinWindow(uint24 lvl) private {
        level = lvl;
    }

    /// @dev Warm continuation from logical index 1. The drain's checkpoint marker is the full
    ///      queue key (level plus its slot / far-future bit), and logical index 0 is the rotated
    ///      physical position `TicketEntropy.queueStart`, so that entry is the drained placeholder.
    function _pinWarm(uint24 rk) private {
        uint256 start = TicketEntropy.queueStart(rk, _ticketQueueLength(rk), _lootboxWord(_rngReadBuffer()));
        _setEntryOwed(rk, _tqPositionAt(ticketQueue[_ticketQueueStorageKey(rk)], start), 0);
        ticketLevel = rk;
        ticketCursor = 1;
    }

    /// @dev Queue `n` buyers through the production purchase sink with purchase-time owner
    ///      registration, then flip the double buffer so they sit on the read key. `lvl` is a
    ///      minted level (level pinned to `lvl`, so lvl <= _mintCeiling()) and the sink uses
    ///      the write key.
    function seedViaPurchase(uint24 lvl, uint256 n, uint32 entriesScaled, uint160 base, bool warm) external {
        _pinWindow(lvl);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        rngWordCurrent = uint256(keccak256("chunk-gas-entropy")) | 1; _setRngSessionPublished(true); _setRngComplete(false);
        if (ticketOwners.length == 0) _registerEntryOwner(address(1), lvl);
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            _queueEntriesScaled(p, lvl, entriesScaled, false);
        }
        ticketWriteSlot = !ticketWriteSlot;
        ticketLevel = 0;
        ticketCursor = 0;
        if (warm) _pinWarm(_tqReadKey(lvl));
    }

    /// @dev `n` dust entries: zero owed, a fractional remainder only, so every one resolves
    ///      to a skip or a single entry and the drain does nothing but walk them.
    function seedDust(uint24 lvl, uint256 n, uint160 base, bool warm) external {
        _pinWindow(lvl);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        rngWordCurrent = uint256(keccak256("chunk-gas-entropy")) | 1; _setRngSessionPublished(true); _setRngComplete(false);
        uint24 rk = _tqReadKey(lvl);
        if (ticketOwners.length == 0) _registerEntryOwner(address(1), lvl);
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            uint80 ownerBits = _registerEntryOwner(p, lvl);
            _tqAppend(rk, uint32(ownerBits >> OWNER_IDX_SHIFT));
            _seedOwedAt(rk, p, ownerBits | uint80(1)); // rem = 1 (1%): almost always a skip
        }
        ticketLevel = 0;
        ticketCursor = 0;
        if (warm) _pinWarm(rk);
    }

    /// @dev Queue `n` buyers through the production purchase sink onto `lvl`'s UNMINTED
    ///      (far-future) key, then put the game in the state where that queue is the frozen
    ///      pool the sweep mints: the last-purchase request has taken the RNG lock and bumped
    ///      `level` to lvl - 1, lastPurchaseDay is latched, so _mintCeiling() = level + 1 = lvl
    ///      and _frozenPoolDue() holds. The measured call passes anchor = level = lvl - 1 (the
    ///      purchase level while the last-purchase lock is held); the read window
    ///      [lvl - 2 .. lvl] is empty, so the call reaches processTicketBatch's frozen-pool
    ///      continuation. `warm` pins the FF marker and cursor 1 (logical index 0 drained) so the
    ///      chunk exercises continuation from a nonzero cursor. Requires lvl >= 2. Far-future
    ///      lanes hold whole entries only, so `entriesScaled` must be a multiple of QTY_SCALE.
    function seedFrozenPool(uint24 lvl, uint256 n, uint32 entriesScaled, uint160 base, bool warm) external {
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        rngWordCurrent = uint256(keccak256("chunk-gas-entropy")) | 1; _setRngSessionPublished(true); _setRngComplete(false);
        // Before the seal: level = lvl - 2, ceiling lvl - 1, so `lvl` routes far-future.
        level = lvl - 2;
        if (ticketOwners.length == 0) _registerEntryOwner(address(1), lvl);
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            _queueEntriesScaled(p, lvl, entriesScaled, false);
        }
        uint24 ffk = _tqFarFutureKey(lvl);
        require(_ticketQueueLength(ffk) == n, "fixture: every buyer sits on the far-future key");
        // The last-purchase request: lock taken, level bumped.
        level = lvl - 1;
        lastPurchaseDay = true;
        rngLockedFlag = true;
        require(_mintCeiling() == lvl && _frozenPoolDue(), "fixture: frozen pool due at lvl");
        ticketLevel = 0;
        ticketCursor = 0;
        if (warm) _pinWarm(ffk);
    }

    /// @dev Recycled backing: every bucket of `lvl`'s parity holds an older level's stamp and
    ///      `words` nonzero words, so the drain rewrites nonzero slots (no fresh stores).
    function recycleBacking(uint24 lvl, uint256 words) external {
        require(lvl >= 2, "older level of the same parity");
        uint256 base = _traitBufferBase(lvl);
        for (uint256 trait; trait < 256; ++trait) {
            uint256 elem = base + trait;
            uint256 stale = (words * 8);
            assembly ("memory-safe") {
                sstore(elem, stale)
                mstore(0, elem)
                let w := keccak256(0, 32)
                for { let i := 0 } lt(i, words) { i := add(i, 1) } { sstore(add(w, i), 0x0101) }
            }
        }
    }

    /// @dev A later level whose existing headers each have seven lanes but whose next
    ///      completed words are still zero: every hit can cross the backing high-water mark.
    function seedHeaderTails(uint24 lvl) external {
        _setTicketBufferLevel(lvl);
        traitBucketLive[lvl & 1] = type(uint256).max;
        uint256 base = _traitBufferBase(lvl);
        uint256 tail = 0x00000001000000010000000100000001000000010000000100000001;
        for (uint256 trait; trait < 256; ++trait) {
            uint256 elem = base + trait;
            uint256 head = 7 | (tail << 32);
            assembly ("memory-safe") { sstore(elem, head) }
        }
    }

    /// @dev Pin the global round counter so a fixture rolls a chosen round seed.
    function setRound(uint32 r) external {
        ticketRound = r;
    }

    /// @dev Buckets whose length differs from `baseLen` (seeded header tails hold seven lanes).
    function bucketsTouched(uint24 lvl, uint256 baseLen) external view returns (uint256 n) {
        for (uint256 trait; trait < 256; ++trait)
            if (_bucketLengthUnchecked(lvl, trait) != baseLen) ++n;
    }

    function seats() external view returns (uint256) {
        return ticketSeats;
    }

    function marker() external view returns (uint24) {
        return ticketLevel;
    }

    function grownTraits(uint24 lvl, uint256 oldWords) external view returns (uint256 n) {
        for (uint256 trait; trait < 256; ++trait)
            if (_bucketLengthUnchecked(lvl, trait) > oldWords * 8) ++n;
    }

    /// @dev The metered ticket worker exactly as the miner calls it: `allowance` bounds the
    ///      admitted steps and their complete checkpoint tail.
    function runTicketWork(uint24 anchor, uint256 allowance) external returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSelector(DegenerusGameTicketModule.runTicketWork.selector, anchor, allowance)
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        return abi.decode(data, (MineFlipGas.Result));
    }

    function cursor() external view returns (uint256) {
        return ticketCursor;
    }

    function round() external view returns (uint32) {
        return ticketRound;
    }

    function queueLength(uint24 key) external view returns (uint256) {
        return _ticketQueueLength(key);
    }

    function ffOwedOf(uint24 lvl, address p) external view returns (uint80) {
        return _entriesOwed(_tqFarFutureKey(lvl), p);
    }

    function owedOf(uint24 lvl, address p) external view returns (uint80) {
        return _entriesOwed(_tqReadKey(lvl), p);
    }

    function seed(uint24 lvl, uint256 n, uint32 owedEach, uint160 base, bool warm) external {
        _pinWindow(lvl);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((1) & 1) << 12);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((uint48(0) + 1) & 1) << 12);
        rngWordCurrent = uint256(keccak256("chunk-gas-entropy")) | 1; _setRngSessionPublished(true); _setRngComplete(false);
        uint24 rk = _tqReadKey(lvl);
        // Position zero stays out of the seeded set (a zero lane makes word stores no-ops).
        if (ticketOwners.length == 0) _registerEntryOwner(address(1), lvl);
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            uint80 ownerBits = _registerEntryOwner(p, lvl);
            _tqAppend(rk, uint32(ownerBits >> OWNER_IDX_SHIFT));
            _seedOwedAt(rk, p, ownerBits | (uint80(owedEach) << 8));
        }
        // warm: pin the checkpoint marker and a nonzero cursor to exercise continuation.
        ticketLevel = 0;
        ticketCursor = 0;
        if (warm) _pinWarm(rk);
    }
}

/// @dev Per-chunk gas probes shared by the drain-shape suites. The ticket worker spends what
///      it is given ("if you give it 600m gas it will spend it"), so no probe bounds a whole
///      call. The properties measured are: a call given a realistic gas limit does not run out
///      of gas and makes progress, and the smallest allowance admitting a shape's largest
///      indivisible step (a round, or a full-size solo run) stays below the 10M chunk target
///      while the call at exactly that allowance completes inside it (an overrun of a declared
///      MineFlipGasBounds step would revert WorkGasBound or run out of gas).
abstract contract TicketChunkProbe is Test {
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    uint256 internal constant GAS_TARGET = 10_000_000;
    /// @dev Gas a probe call spends outside the worker's meter: the external call into the
    ///      harness, the delegatecall into the ticket module (both cold) and ABI coding.
    uint256 internal constant UNMETERED_OVERHEAD = 50_000;
    bytes32 internal constant TRAITS_GENERATED = keccak256("TraitsGenerated(address,uint256,uint32)");

    /// @dev The admitted step a shape's chunk probe isolates.
    enum Step {
        Round, // one seated round (bound TICKET_ROUND_MAX)
        Solo, // one solo trait run at its full size (bound SOLO_BASE + n * ENTRY_MAX, n <= 160)
        Seat // one seat or skip (bound TICKET_SEAT_MAX)
    }

    ChunkHarness internal h;

    function _cool() internal {
        vm.cool(address(h));
        vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
    }

    /// @dev One cold metered call. `hit` reports whether it admitted the step: a round for
    ///      Round, any progress for Seat, and for Solo a first solo run identical to `first`
    ///      (the reference call's first run; pass zero to accept any run and learn it).
    function _probe(uint24 anchor, uint256 allowance, Step step, bytes32 first)
        internal
        returns (bool hit, bytes32 sig, uint256 used)
    {
        _cool();
        uint32 roundBefore = h.round();
        vm.recordLogs();
        uint256 g0 = gasleft();
        MineFlipGas.Result memory r = h.runTicketWork{gas: allowance + 1_000_000}(anchor, allowance);
        used = g0 - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(h) || logs[i].topics.length == 0 || logs[i].topics[0] != TRAITS_GENERATED) {
                continue;
            }
            (, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
            // Larger supplied gas resumes more aligned runs, never one larger chunk.
            assertLe(take, GasBounds.TICKET_SOLO_MAX_ENTRIES, "a solo run exceeds its declared entry cap");
            if (sig == bytes32(0)) sig = keccak256(abi.encode(logs[i].topics, logs[i].data));
        }
        if (step == Step.Round) hit = h.round() != roundBefore;
        else if (step == Step.Seat) hit = r.progressed;
        else hit = sig != bytes32(0) && (first == bytes32(0) || sig == first);
    }

    /// @dev Smallest allowance (to 1k) whose cold call admits the step, then the call at exactly
    ///      that allowance measured cold. That allowance is the step's declared reservation plus
    ///      the measured prefix and tail. For Round the call runs exactly one round; for Solo the
    ///      unused part of the full-size run's 160 x ENTRY_MAX reservation may admit further,
    ///      smaller runs, each against its own declared bound. Reverts to the entry state.
    function _oneChunk(uint24 anchor, string memory tag, Step step)
        internal
        returns (uint256 allowance, uint256 used)
    {
        uint256 snap = vm.snapshotState();
        (bool refHit, bytes32 first,) = _probe(anchor, EIP7825_TX_GAS_CAP, step, bytes32(0));
        assertTrue(refHit, string.concat(tag, ": fixture never reaches the probed step"));
        assertTrue(vm.revertToState(snap));
        // Below SELECT + TAIL the worker admits nothing.
        uint256 lo = GasBounds.TICKET_SELECT_MAX + GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE;
        uint256 hi = EIP7825_TX_GAS_CAP;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            (bool ok,,) = _probe(anchor, mid, step, first);
            assertTrue(vm.revertToState(snap));
            if (ok) hi = mid;
            else lo = mid;
        }
        bool admitted;
        (admitted,, used) = _probe(anchor, hi, step, first);
        allowance = hi;
        assertTrue(vm.revertToStateAndDelete(snap));
        emit log_named_uint(string.concat(tag, "_step_allowance"), allowance);
        emit log_named_uint(string.concat(tag, "_step_call_gas"), used);
        assertTrue(admitted, string.concat(tag, ": minimal allowance no longer admits the step"));
        assertLt(allowance, GAS_TARGET, string.concat(tag, ": the step is admitted only above 10M"));
        assertLt(used, GAS_TARGET, string.concat(tag, ": one chunk over the 10M ceiling"));
        assertLe(used, allowance + UNMETERED_OVERHEAD, string.concat(tag, ": chunk overran its declared reservation"));
    }

    /// @dev Cold call gas at exactly `allowance`, state restored afterwards.
    function _usedAt(uint24 anchor, uint256 allowance, Step step) internal returns (uint256 used) {
        uint256 snap = vm.snapshotState();
        (, , used) = _probe(anchor, allowance, step, bytes32(0));
        assertTrue(vm.revertToStateAndDelete(snap));
    }

    /// @dev Cold gas of one admitted step in isolation: the call at the smallest admitting
    ///      allowance minus the call 100 gas below it, which runs the same prefix and stops.
    ///      The difference also carries the tail writes the admitted step adds.
    function _stepGas(uint24 anchor, Step step) internal returns (uint256 item, uint256 lo) {
        uint256 snap = vm.snapshotState();
        (bool refHit, bytes32 first,) = _probe(anchor, EIP7825_TX_GAS_CAP, step, bytes32(0));
        assertTrue(refHit, "fixture never reaches the probed step");
        assertTrue(vm.revertToState(snap));
        lo = GasBounds.TICKET_SELECT_MAX + GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE;
        uint256 hi = EIP7825_TX_GAS_CAP;
        while (hi - lo > 100) {
            uint256 mid = (lo + hi) / 2;
            (bool ok,,) = _probe(anchor, mid, step, first);
            assertTrue(vm.revertToState(snap));
            if (ok) hi = mid;
            else lo = mid;
        }
        (, , item) = _probe(anchor, hi, step, first);
        assertTrue(vm.revertToState(snap));
        (, , uint256 below) = _probe(anchor, lo, step, first);
        assertTrue(vm.revertToStateAndDelete(snap));
        item -= below;
    }

    /// @dev One cold call with ample gas; returns its gas and the entries it generated.
    function _whole(uint24 anchor) internal returns (uint256 used, uint256 take) {
        uint256 snap = vm.snapshotState();
        _cool();
        vm.recordLogs();
        uint256 g0 = gasleft();
        MineFlipGas.Result memory r = h.runTicketWork(anchor, EIP7825_TX_GAS_CAP);
        used = g0 - gasleft();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != TRAITS_GENERATED) continue;
            (, uint32 t) = abi.decode(logs[i].data, (uint256, uint32));
            take += t;
        }
        assertTrue(r.done, "the fixture drains in one call");
        assertTrue(vm.revertToStateAndDelete(snap));
    }
}

/// @title RoundDrainChunkGas — per-chunk gas of the ticket worker on each drain path
/// @notice For every drain shape: the compatibility door given a realistic 10M and, separately,
///         the 16.7M EIP-7825 cap does not run out of gas and makes progress, and the shape's
///         largest admitted step is admitted below the 10M chunk target and completes inside
///         its allowance. The worker spends whatever gas it is given, so call totals are logged,
///         never bounded.
contract RoundDrainChunkGas is TicketChunkProbe {
    uint24 internal constant LVL = 11;

    function setUp() public {
        h = new ChunkHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        vm.etch(
            ContractAddresses.GAME_FOILPACK_MODULE,
            address(new DegenerusGameFoilPackModule()).code
        );
    }

    function _measure(string memory tag, Step step) internal returns (uint256 g) {
        return _measureAt(LVL, tag, step);
    }

    function _measureAt(uint24 lvl, string memory tag, Step step) internal returns (uint256 g) {
        uint256 snap = vm.snapshotState();
        g = _doorCall(lvl, GAS_TARGET, tag);
        assertTrue(vm.revertToState(snap));
        _doorCall(lvl, EIP7825_TX_GAS_CAP, string.concat(tag, "_16p7m"));
        assertTrue(vm.revertToStateAndDelete(snap));
        _oneChunk(lvl + 1, tag, step);
    }

    /// @dev The caller-sized door with a bounded gas limit: it must not run out of gas and must
    ///      make progress. Its total is whatever it was given, so it is logged only.
    function _doorCall(uint24 lvl, uint256 gasLimit, string memory tag) internal returns (uint256 g) {
        _cool();
        uint256 g0 = gasleft();
        (, bool worked) = h.processTicketBatch{gas: gasLimit}(lvl + 1);
        g = g0 - gasleft();
        emit log_named_uint(tag, g);
        // Non-vacuity: the call must drain the seeded queue, not walk an empty window.
        assertTrue(worked, string.concat(tag, ": call did no work (seeded level outside the window)"));
    }

    function test_Chunk_HeaderTailFlushes_ZeroBacking() public {
        h.seed(LVL, 8, 20000, uint160(0xD0000), true);
        h.seedHeaderTails(LVL);
        _measure("chunk_header_tail_flushes_zero_backing_gas", Step.Round);
    }

    function test_Chunk_PerEntry_GrowsBeyondRecycledBacking() public {
        h.recycleBacking(LVL, 1);
        h.seed(LVL, 3, 5000, uint160(0xE0000), true);
        _measure("chunk_per_entry_backing_growth_gas", Step.Solo);
    }

    function test_Chunk_Rounds_GrowsBeyondRecycledBacking() public {
        h.recycleBacking(LVL, 1);
        h.seed(LVL, 8, 20000, uint160(0xF0000), true);
        h.seedHeaderTails(LVL);
        _measure("chunk_rounds_backing_growth_gas", Step.Round);
    }

    /// @dev Measure late record-level chunks after real earlier chunks have exhausted
    ///      the previous same-parity backing, rather than measuring only its first chunk.
    ///      Each prefix chunk is a realistic 10M call: the worker spends the gas it is given,
    ///      so an unbounded call would drain the whole record level in one chunk.
    function test_Chunk_LateRecord_PerEntry() public {
        h.recycleBacking(LVL, 1);
        h.seed(LVL, 3, 50000, uint160(0x110000), true);
        for (uint256 i; i < 32; ++i) {
            (, bool worked) = h.processTicketBatch{gas: GAS_TARGET}(LVL + 1);
            assertTrue(worked, "record prefix must still drain paid entries");
        }
        assertGt(h.grownTraits(LVL, 1), 96, "prefix must grow beyond old words across common traits");
        _measure("chunk_late_record_per_entry_gas", Step.Solo);
    }

    function test_Chunk_LateRecord_Rounds() public {
        h.recycleBacking(LVL, 1);
        h.seed(LVL, 8, 20000, uint160(0x120000), true);
        for (uint256 i; i < 32; ++i) {
            (, bool worked) = h.processTicketBatch{gas: GAS_TARGET}(LVL + 1);
            assertTrue(worked, "record prefix must still drain paid entries");
        }
        assertGt(h.grownTraits(LVL, 1), 96, "prefix must grow beyond old words across common traits");
        _measure("chunk_late_record_rounds_gas", Step.Round);
    }

    /// @dev All rounds: many buyers each owing a few whole tickets, cold level.
    function test_Chunk_AllRounds_Cold() public {
        h.seed(LVL, 600, 8, uint160(0x10000), false);
        _measure("chunk_all_rounds_cold_gas", Step.Round);
    }

    /// @dev All rounds from a warm continuation.
    function test_Chunk_AllRounds_Warm() public {
        h.seed(LVL, 600, 8, uint160(0x20000), true);
        _measure("chunk_all_rounds_warm_gas", Step.Round);
    }

    /// @dev Rounds with single-ticket buyers: every round seats eight fresh entries (max seat
    ///      joins per round, the registry-heavy shape).
    function test_Chunk_Rounds_SingleTicketBuyers_Warm() public {
        h.seed(LVL, 2000, 4, uint160(0x30000), true);
        _measure("chunk_rounds_single_ticket_buyers_warm_gas", Step.Round);
    }

    /// @dev Rounds of single-ticket buyers registered at purchase: the production shape for a
    ///      crowd of small buyers, where the drain pays no registry slot per seat.
    function test_Chunk_Rounds_SingleTicketBuyers_Registered_Warm() public {
        h.seedViaPurchase(3, 2000, 400, uint160(0x60000), true);
        _measureAt(3, "chunk_rounds_single_ticket_buyers_registered_warm_gas", Step.Round);
    }

    /// @dev Rounds of two-ticket buyers registered at purchase.
    function test_Chunk_Rounds_TwoTicketBuyers_Registered_Warm() public {
        h.seedViaPurchase(3, 1200, 800, uint160(0x70000), true);
        _measureAt(3, "chunk_rounds_two_ticket_buyers_registered_warm_gas", Step.Round);
    }

    /// @dev A queue of nothing but dust entries: the budget bounds the walk.
    function test_Chunk_DustSkips_Warm() public {
        h.seedDust(LVL, 3000, uint160(0x80000), true);
        uint256 snap = vm.snapshotState();
        _cool();
        (, bool worked) = h.processTicketBatch{gas: GAS_TARGET}(LVL + 1);
        assertTrue(worked, "dust walk makes progress");
        emit log_named_uint("chunk_dust_skips_cursor_after_10m", h.cursor());
        assertGt(h.cursor(), 1, "dust walk advances the cursor");
        assertLt(h.cursor(), 3000, "the supplied gas, not the queue end, bounds the dust walk");
        assertTrue(vm.revertToStateAndDelete(snap));
        _measure("chunk_dust_skips_warm_gas", Step.Seat);
    }

    /// @dev Per-entry path below the seat floor with mid-size entries (a few hundred
    ///      occurrences each): the shape where coalescing helps least.
    function test_Chunk_PerEntry_MidWhales_600_Warm() public {
        h.seed(LVL, 3, 600, uint160(0x90000), true);
        _measure("chunk_per_entry_mid_whales_600_warm_gas", Step.Solo);
    }

    function test_Chunk_PerEntry_MidWhales_250_Warm() public {
        h.seed(LVL, 3, 250, uint160(0xA0000), true);
        _measure("chunk_per_entry_mid_whales_250_warm_gas", Step.Solo);
    }

    function test_Chunk_PerEntry_MidWhales_120_Warm() public {
        h.seed(LVL, 3, 120, uint160(0xB0000), true);
        _measure("chunk_per_entry_mid_whales_120_warm_gas", Step.Solo);
    }

    /// @dev Eight whales seated together: rounds with no seat turnover, the densest round
    ///      shape (every unit is a round unit).
    function test_Chunk_EightWhales_Rounds_Warm() public {
        h.seed(LVL, 8, 20000, uint160(0xC0000), true);
        _measure("chunk_eight_whales_rounds_warm_gas", Step.Round);
    }

    /// @dev Per-entry path: three whales (below the seat floor), coalesced runs.
    /// @dev Whale and round chunks over recycled backing: every write rewrites a nonzero slot.
    function test_Chunk_PerEntry_Whales_Recycled() public {
        h.recycleBacking(LVL, 64);
        h.seed(LVL, 3, 5000, uint160(0x40000), true);
        _measure("chunk_per_entry_whales_recycled_gas", Step.Solo);
    }

    function test_Chunk_PerEntry_MidWhales_600_Recycled() public {
        h.recycleBacking(LVL, 64);
        h.seed(LVL, 3, 600, uint160(0x41000), true);
        _measure("chunk_per_entry_mid_whales_600_recycled_gas", Step.Solo);
    }

    function test_Chunk_AllRounds_Recycled() public {
        h.recycleBacking(LVL, 64);
        h.seed(LVL, 600, 8, uint160(0x42000), true);
        _measure("chunk_all_rounds_recycled_gas", Step.Round);
    }

    function test_Chunk_PerEntry_Whales_Warm() public {
        h.seed(LVL, 3, 5000, uint160(0x40000), true);
        _measure("chunk_per_entry_whales_warm_gas", Step.Solo);
    }

    /// @dev Per-entry path: one whale, cold level.
    function test_Chunk_PerEntry_Whale_Cold() public {
        h.seed(LVL, 1, 5000, uint160(0x50000), false);
        _measure("chunk_per_entry_whale_cold_gas", Step.Solo);
    }

    /// @dev The largest solo chunk in isolation: one cold owner owing exactly
    ///      TICKET_SOLO_MAX_ENTRIES, so the minimal admitting call runs that single full-size run,
    ///      releases the queue and stops. Its measured cost is compared with the declared bound.
    function test_Chunk_PerEntry_MaxSoloRun_Cold() public {
        uint256 entries = GasBounds.TICKET_SOLO_MAX_ENTRIES;
        h.seed(LVL, 1, uint32(entries), uint160(0x51000), false);
        (, uint256 used) = _oneChunk(LVL + 1, "chunk_per_entry_max_solo_run_cold", Step.Solo);
        // One solo trait run: SOLO_BASE + 160 x ENTRY_MAX + TAIL stays below 10M (MineFlipGasBounds).
        uint256 declared = GasBounds.TICKET_SOLO_BASE + entries * GasBounds.TICKET_ENTRY_MAX + GasBounds.TICKET_TAIL;
        emit log_named_uint("chunk_per_entry_max_solo_run_declared_bound", declared);
        assertLe(declared + MineFlipGas.CHECK_RESERVE, GAS_TARGET, "declared full-size solo chunk exceeds 10M");
        // The measured call is the selection step plus that one run, release and tail.
        assertLe(used, GasBounds.TICKET_SELECT_MAX + declared, "measured full-size solo chunk exceeds its declared bound");
        assertEq(uint32(h.owedOf(LVL, address(uint160(0x51001))) >> 8), entries, "probe left the fixture untouched");
    }

    /// @dev Round index whose seed (level 11, the fixture entropy) rolls colour 6 in all four
    ///      quadrants: every seat splits into its own symbol bucket, 32 single appends.
    uint32 internal constant ALL_RARE_ROUND = 8_244_874;

    function _assertAllRareRound() internal pure {
        uint256 entropy = uint256(keccak256("chunk-gas-entropy")) | 1;
        uint256 seed = uint256(keccak256(abi.encode(LVL, ALL_RARE_ROUND, entropy)));
        for (uint256 q; q < 4; ++q) {
            uint256 scaled = (uint64(seed >> (64 * q)) & 0xffffffff) >> 24;
            assertTrue(scaled >= 248 && scaled < 254, "fixture: colour 6 in every quadrant");
        }
    }

    /// @dev The solo cold worst: one owner owing the full 160-entry run, every bucket header
    ///      holding seven lanes over a zero next word, so each distinct trait completes a fresh
    ///      word (cold header read, cold word read, fresh word store, header rewrite).
    function test_Chunk_PerEntry_MaxSoloRun_HeaderTails_Cold() public {
        uint256 entries = GasBounds.TICKET_SOLO_MAX_ENTRIES;
        h.seed(LVL, 1, uint32(entries), uint160(0x52000), false);
        h.seedHeaderTails(LVL);
        (uint256 item,) = _stepGas(LVL + 1, Step.Solo);
        (, uint256 used) = _oneChunk(LVL + 1, "chunk_per_entry_max_solo_run_header_tails_cold", Step.Solo);
        uint256 declared = GasBounds.TICKET_SOLO_BASE + entries * GasBounds.TICKET_ENTRY_MAX;
        emit log_named_uint("solo_160_header_tails_step_gas", item);
        emit log_named_uint("solo_160_declared_step_bound", declared);
        assertLe(item, declared, "the cold 160-entry run exceeds SOLO_BASE + 160 x ENTRY_MAX");
        assertLe(used, GasBounds.TICKET_SELECT_MAX + declared + GasBounds.TICKET_TAIL, "call overran its declared steps");
        assertLe(declared + GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE, GAS_TARGET);
    }

    /// @dev Per-entry and fixed solo costs. With header tails, an owner whose sixteen entries
    ///      land on sixteen distinct traits pays one completed fresh word per entry: the marginal
    ///      entry is the per-entry cold worst. A fresh level's first run also initializes the
    ///      live bitmap, the heaviest fixed part of a run.
    function test_Solo_EntryAndBaseCoverColdWorst() public {
        uint256 snap = vm.snapshotState();
        h.seed(LVL, 1, 1, uint160(0x51000), false);
        h.seedHeaderTails(LVL);
        (uint256 one,) = _whole(LVL + 1);
        assertTrue(vm.revertToState(snap));
        h.seed(LVL, 1, 16, uint160(0x51000), false);
        h.seedHeaderTails(LVL);
        (uint256 sixteen, uint256 take) = _whole(LVL + 1);
        h.runTicketWork(LVL + 1, EIP7825_TX_GAS_CAP);
        assertEq(h.bucketsTouched(LVL, 7), 16, "fixture: sixteen distinct traits");
        assertEq(take, 16);
        assertTrue(vm.revertToState(snap));
        h.seed(LVL, 1, 1, uint160(0x51000), false);
        (uint256 freshRun,) = _stepGas(LVL + 1, Step.Solo);
        assertTrue(vm.revertToStateAndDelete(snap));
        uint256 perEntry = (sixteen - one) / 15;
        emit log_named_uint("solo_per_entry_cold_worst", perEntry);
        emit log_named_uint("solo_one_entry_fresh_level_step_gas", freshRun);
        assertLe(perEntry, GasBounds.TICKET_ENTRY_MAX, "per-entry cold worst exceeds ENTRY_MAX");
        assertLe(GasBounds.TICKET_ENTRY_MAX, 2 * perEntry, "ENTRY_MAX is padded beyond 2x");
        assertLe(freshRun, GasBounds.TICKET_SOLO_BASE + GasBounds.TICKET_ENTRY_MAX, "one-entry run exceeds its bound");
    }

    /// @dev The round cold worst: eight seats, all four quadrants split across their colour's
    ///      eight symbols, each of the 32 single appends completing a fresh word. The whale
    ///      variant keeps every seat (its owed rewrites land in the tail, priced into the
    ///      difference); the exit variant writes eight seat exits inside the round.
    function test_Round_AllRareQuadrantsColdWorst() public {
        _assertAllRareRound();
        uint256 snap = vm.snapshotState();
        h.seed(LVL, 8, 20000, uint160(0xC0000), false);
        h.seedHeaderTails(LVL);
        h.setRound(ALL_RARE_ROUND);
        (uint256 whales,) = _stepGas(LVL + 1, Step.Round);
        assertTrue(vm.revertToState(snap));
        h.seed(LVL, 8, 4, uint160(0xC0000), false);
        h.seedHeaderTails(LVL);
        h.setRound(ALL_RARE_ROUND);
        (uint256 exits,) = _stepGas(LVL + 1, Step.Round);
        assertTrue(vm.revertToState(snap));
        h.seed(LVL, 8, 4, uint160(0xC0000), false);
        h.setRound(ALL_RARE_ROUND);
        (uint256 freshRare,) = _stepGas(LVL + 1, Step.Round);
        assertTrue(vm.revertToStateAndDelete(snap));
        emit log_named_uint("round_all_rare_header_tails_whales_step_gas", whales);
        emit log_named_uint("round_all_rare_header_tails_exits_step_gas", exits);
        emit log_named_uint("round_all_rare_fresh_headers_exits_step_gas", freshRare);
        uint256 worst = whales > exits ? whales : exits;
        assertLe(worst, GasBounds.TICKET_ROUND_MAX, "cold worst round exceeds ROUND_MAX");
        assertLe(GasBounds.TICKET_ROUND_MAX, 2 * worst, "ROUND_MAX is padded beyond 2x");
        h.seed(LVL, 8, 4, uint160(0xC0000), false);
        h.seedHeaderTails(LVL);
        h.setRound(ALL_RARE_ROUND);
        _oneChunk(LVL + 1, "chunk_round_all_rare_header_tails", Step.Round);
    }

    /// @dev Seats that skip with an owed write, the heaviest seat: queue lane, owner registry
    ///      and pending word reads plus the write. The worst single seat also opens a cold
    ///      queue word and the registry length.
    function test_Seat_ColdWorstFitsSeatMax() public {
        uint256 snap = vm.snapshotState();
        h.seed(LVL, 8, 0, uint160(0xC0000), false);
        (uint256 eight,) = _whole(LVL + 1);
        assertTrue(vm.revertToState(snap));
        h.seed(LVL, 16, 0, uint160(0xC0000), false);
        (uint256 sixteen,) = _whole(LVL + 1);
        assertTrue(vm.revertToStateAndDelete(snap));
        uint256 perSeat = (sixteen - eight) / 8;
        uint256 worst = perSeat + 2 * 2_100;
        emit log_named_uint("seat_skip_with_write_average", perSeat);
        emit log_named_uint("seat_cold_worst", worst);
        assertLe(worst, GasBounds.TICKET_SEAT_MAX, "cold worst seat exceeds SEAT_MAX");
    }

    /// @dev Admits the selection step (SELECT_MAX + TAIL plus the entry reads) but neither a
    ///      reload nor a solo run after it.
    function _selectOnlyAllowance() internal pure returns (uint256) {
        return GasBounds.TICKET_SELECT_MAX + GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE + 10_000;
    }

    /// @dev Reload of eight persisted seats on a cold resumed call, against the same call
    ///      stopped before the round phase admits.
    function test_Reload_EightSeatsColdFitsReloadMax() public {
        h.seed(LVL, 8, 20000, uint160(0xC0000), false);
        h.seedHeaderTails(LVL);
        h.setRound(ALL_RARE_ROUND);
        h.runTicketWork(LVL + 1, 1_000_000);
        assertTrue(h.seats() != 0, "fixture: eight seats persisted");
        (, uint256 lo) = _stepGas(LVL + 1, Step.Round);
        uint256 withReload = _usedAt(LVL + 1, lo, Step.Round);
        uint256 selectOnly = _usedAt(LVL + 1, _selectOnlyAllowance(), Step.Round);
        emit log_named_uint("reload_eight_seats_cold", withReload - selectOnly);
        assertLe(withReload - selectOnly, GasBounds.TICKET_RELOAD_MAX, "cold reload exceeds RELOAD_MAX");
    }

    /// @dev Selection on a fresh level: a first buffer preparation and a fresh control-slot
    ///      marker, against an admitted-nothing call.
    function test_Select_ColdFitsSelectMax() public {
        h.seed(LVL, 1, 1, uint160(0x51000), false);
        uint256 snap = vm.snapshotState();
        (bool generated,, uint256 selected) = _probe(LVL + 1, _selectOnlyAllowance(), Step.Solo, bytes32(0));
        assertFalse(generated, "the probe admits the selection step only");
        assertTrue(h.marker() != 0, "fixture: the selection step ran and wrote its marker");
        assertTrue(vm.revertToStateAndDelete(snap));
        uint256 empty = _usedAt(LVL + 1, 60_000, Step.Solo);
        emit log_named_uint("select_fresh_level_cold", selected - empty);
        assertLe(selected - empty, GasBounds.TICKET_SELECT_MAX, "cold selection exceeds SELECT_MAX");
    }
}
