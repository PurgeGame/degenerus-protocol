// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @notice Check the cost of a NoWork revert after draining subscriber rings of different sizes.
/// @dev The empty-work probe should stay small as the ring grows. These measurements do not
///      establish admission bounds for paid work. Run with --isolate for committed SSTORE state;
///      vm.cool alone resets access warmth, not original storage values.
contract OpenWalkCompositionGas is DeployProtocol {
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

    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF; // mapping(uint32 => Sub)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS; // packed uint32[]
    uint256 private constant OFF_LASTBOUGHT = 7;
    uint256 private constant OFF_LASTOPENED = 10;
    uint256 internal constant INTRINSIC_TX_GAS = 21_192;
    uint256 internal constant RING_1000_NEW_SUBS = 998;
    uint256 internal constant RING_500_NEW_SUBS = 500;
    uint256 internal constant RING_100_NEW_SUBS = 100;
    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // NoWork cost across ring sizes (102 / 502 / 1000)
    // =========================================================================

    /// @notice Builds THREE independent fully-drained rings (100, 500, 998 new subs => ring
    ///         sizes 102/502/1000 incl. the 2 deploy subs) from the SAME clean baseline
    ///         (snapshot/revert between each), and at each size probes the ring-scan cost via a
    ///         reverting `mineFlip()` (NoWork — the ring is fully drained and no human backlog
    ///         exists). The 1000-subscriber probe must stay below 200k gas and within 25k
    ///         of the 102-subscriber probe.
    function testPerSkipMarginalAcrossRingSizes() public {
        uint256 snap = vm.snapshotState();

        uint256 g100 = _buildDrainedRingAndProbeNoWork(RING_100_NEW_SUBS, "sk100_");
        vm.revertToState(snap);
        uint256 g500 = _buildDrainedRingAndProbeNoWork(RING_500_NEW_SUBS, "sk500_");
        vm.revertToState(snap);
        uint256 g1000 = _buildDrainedRingAndProbeNoWork(RING_1000_NEW_SUBS, "sk1000_");

        emit log_named_uint("nowork_probe_gas_at_ring_size_102", g100);
        emit log_named_uint("nowork_probe_gas_at_ring_size_502", g500);
        emit log_named_uint("nowork_probe_gas_at_ring_size_1000", g1000);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        // The `_pendingBoxCount` O(1) drained gate: a fully-drained ring's NoWork probe never
        // walks the ring, so the probe cost is (a) small and (b) INDEPENDENT of ring size —
        // pre-gate this scaled ~4.7k gas per subscriber (≈4.9M at the 1000 cap, cold).
        assertLt(g1000, 200_000, "drained-ring NoWork probe is O(1), not a ring scan");
        uint256 spread = g1000 > g100 ? g1000 - g100 : g100 - g1000;
        assertLt(spread, 25_000, "drained-ring NoWork probe cost is ring-size independent (the counter gate, not a scan)");
    }

    // =========================================================================
    // NoWork cost at a 1000-subscriber drained ring, zero human work
    // =========================================================================

    /// @notice The caller-paid cost of a `mineFlip()` call that discovers there is NOTHING to do:
    ///         1000 fully-drained subscribers (998 new + 2 deploy), zero human backlog. The
    ///         `_pendingBoxCount` gate answers "any afking work?" in O(1) (no ring scan), and the
    ///         human-sweep leg's zero-work no-frontier-advance short-circuits into
    ///         `revert NoWork()` — measured via a low-level call bracketing gasleft before/after.
    function testNoWorkProbeCostAtThousandSubscribers() public {
        uint256 gasUsed = _buildDrainedRingAndProbeNoWork(RING_1000_NEW_SUBS, "nowork1k_");

        emit log_named_uint("nowork_probe_gas_at_1000_subscribers", gasUsed);
        emit log_named_uint("intrinsic_tx_gas_context", INTRINSIC_TX_GAS);

        // Pre-gate this probe cost ~4.9M cold (a full 1000-subscriber scan just to revert).
        assertLt(gasUsed, 200_000, "the drained-ring NoWork probe is O(1) (the counter gate, not a ring scan)");
    }


    // =========================================================================
    // Fixture and ID-keyed storage readers
    // =========================================================================

    /// @dev Re-cool every storage-bearing account on the measured path plus the module code
    ///      accounts the delegatecalls touch, so a bracketed measurement inside this test tx
    ///      pays COLD access costs — what a fresh keeper transaction pays on mainnet. The
    ///      fixture's own drain/setup calls run in the SAME test transaction and pre-warm
    ///      every subscriber slot; without this reset the measurement understates the real
    ///      per-visit cost ~5-9x (warm 100-gas vs cold 2,100-gas SLOADs).
    function _coolProtocol() internal {
        vm.cool(address(game));
        vm.cool(ContractAddresses.COINFLIP);
        vm.cool(ContractAddresses.COIN);
        vm.cool(ContractAddresses.QUESTS);
        vm.cool(ContractAddresses.AFFILIATE);
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
    }

    /// @dev Builds `n` fresh GROUNDED lootbox-mode subs (+ the 2 permanent deploy subs already in
    ///      the ring), stamps + lands their first day's word, settles clean, then fully drains
    ///      every pending afking box (no human backlog exists in this fixture, so the drain call's
    ///      leftover budget is harmless). Returns the gas of the immediately-following `mineFlip()`
    ///      probe call, which must revert `NoWork()` (fully-drained ring, zero human work) —
    ///      measured via a low-level call bracketing gasleft before/after.
    function _buildDrainedRingAndProbeNoWork(uint256 n, string memory prefix) internal returns (uint256 gasUsed) {
        _setupFundedSubs(n, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "w"))) | 1);
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean before the drain");

        uint256 ringSize = _subscriberCount();
        assertEq(ringSize, n + 2, "fixture contains every seeded subscriber and both protocol accounts");
        // Each lootbox-mode sub carries BOTH an afking-cover box AND a real human lootbox box
        // after the STAGE, so the drain must clear the afking stage AND open every one of those
        // ~ringSize human boxes — otherwise the probe below finds real, non-reverting work and
        // `mineFlip()` does not revert NoWork. mineFlip opens them in its own stage order until it
        // reports no work (or waits on a word it requested).
        _mineAll(ringSize + 256);
        require(_countPendingAfking() == 0, "fixture: ring fully drained pre-probe");

        _coolProtocol();
        // The crank has a craps arm now, so a drained RING is not a drained CRANK until the table
        // is quiet too — otherwise this probe measures the craps leg finding a window to shut.
        // Quieting a scheduled table can itself request another word. Fulfill and
        // publish that request, then finish its consumers before measuring NoWork.
        for (uint256 i; i < 64; ++i) {
            _quietCrapsTable();
            _fulfillPending(uint256(keccak256(abi.encode(prefix, "quiet", i))) | 1);
            _settleClean(uint256(keccak256(abi.encode(prefix, "quiet-clean", i))) | 1);
            _finishReadConsumers();
            if (!game.advanceDue() && !game.isRngFulfilled() && !game.rngLocked()) {
                // Whatever the engine still finds (read-cohort settlement, maintenance, a mid-day
                // request) runs here; a NoWork revert means the crank is quiet.
                try game.mineFlip(0) {} catch { break; }
            }
        }
        _coolProtocol();
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "probe"))));
        uint256 gasBefore = gasleft();
        (bool ok, bytes memory reason) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        gasUsed = gasBefore - gasleft();
        require(!ok, "fixture: the NoWork probe reverted as expected (drained ring, zero human work)");
        assertEq(reason, abi.encodeWithSignature("NoWork()"), "measure NoWork, not another refusal");
    }

    /// @dev Subscribe `n` fresh players as funded lootbox-mode subs (ported from
    ///      V56AfkingGasMarginal._setupFundedSubs — GROUNDED: funded BEFORE subscribe so the D-12
    ///      mandatory NEW-run cover-buy is funded, matching the shipped grounded-subscribe
    ///      behavior the superseded KeeperOpenBoxWorstCaseGas fixture got wrong).
    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach, bool isTicket)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            uint256 seat = _grantSeat(who); // the AFKing Subscription Token is the subscribe credential (a new run burns one seat)
            _fundPool(who, poolEach);
            vm.prank(who);
            game.subscribe(0, false, isTicket, 1, 0, seat);
        }
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev Drive a fresh new-day STAGE then land the day's word (the per-sub stamp becomes a
    ///      ready box). Ported verbatim from V56AfkingGasMarginal.
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before
    ///      returning — used before a mineFlip open so it reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
    }

    /// @dev Fulfill the latest pending mock-VRF request (idempotent — no-op if already
    ///      fulfilled / none).
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

    // ---- ID-keyed subscription reads ----

    function _subField(uint32 id, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(uint256(id), uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(uint32 id) internal view returns (uint32) {
        return uint32(_subField(id, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(uint32 id) internal view returns (uint32) {
        return uint32(_subField(id, OFF_LASTOPENED, 24));
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev Eight subscriber IDs occupy each array element word.
    function _subscriberAt(uint256 i) internal view returns (uint32 id) {
        bytes32 base = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        uint256 word = uint256(vm.load(address(game), bytes32(uint256(base) + i / 8)));
        id = uint32(word >> ((i % 8) * 32));
        require(id != 0, "fixture: subscriber has an allocated ID");
    }

    /// @dev Walk the WHOLE live `_subscribers` set (not just a caller-known subset — the ring
    ///      also carries the 2 permanent deploy subs) and count subs with a pending
    ///      (un-opened) afking box. This verifies the measured ring was fully drained.
    function _countPendingAfking() internal view returns (uint256 pending) {
        uint256 len = _subscriberCount();
        for (uint256 i; i < len; ++i) {
            uint32 id = _subscriberAt(i);
            if (_lastOpenedDayOf(id) < _lastBoughtDayOf(id)) {
                unchecked {
                    ++pending;
                }
            }
        }
    }

    /// @dev Minimal uint -> decimal string for makeAddr label uniqueness.
    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
