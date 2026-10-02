// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../../helpers/RecyclingState.sol";

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusAdmin} from "../../../contracts/DegenerusAdmin.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Independent receipt-to-storage oracle for the ordinary, per-entry ticket consumer.
/// It reconstructs traits from the committed lootbox word; the event supplies only its
/// public batch key/count. It never interprets event data as an emitted entropy word.
/// Seated rounds and foil packs have different derivations and are excluded by this
/// campaign's ticket-only, one-buyer fixture. Encountering either fails the oracle.
abstract contract RngIndexDrainOracle is Test {
    uint256 internal constant SLOT_LOOTBOX_MAPPING = 34;
    uint256 internal constant SLOT_LR_INDEX = 33;
    uint256 private constant SLOT_BUCKETS = 8;
    uint256 private constant SLOT_OWNERS = 67;
    uint256 private constant SLOT_TICKET_CURSOR = 14;
    bytes32 internal constant TOPIC_TRAITS_GENERATED = keccak256("TraitsGenerated(address,uint256,uint32)");

    struct DrainSnapshot {
        uint24 firstLevel;
        uint48 index;
        uint32 round;
        uint256[1024] lengths;
    }

    struct DrainResult {
        uint256 batches;
        uint256 entries;
        uint256 trackedEntries;
        uint256 mismatches;
        uint256 unsupported;
    }

    function _lrIndexOf(DegenerusGame subject) internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(subject));
    }

    function _wordAt(DegenerusGame subject, uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(subject), index);
    }

    function _roundOf(DegenerusGame subject) private view returns (uint32) {
        return uint32(uint256(vm.load(address(subject), bytes32(SLOT_TICKET_CURSOR))) >> 96);
    }

    function _bucketSlot(uint24 lvl, uint256 trait) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(uint256(lvl & 1), SLOT_BUCKETS))) + trait);
    }

    function _bucketLengthOf(DegenerusGame subject, uint24 lvl, uint256 trait) private view returns (uint256) {
        uint256 header = uint256(vm.load(address(subject), _bucketSlot(lvl, trait)));
        uint24 stamp = uint24(uint256(vm.load(address(subject), bytes32(uint256(5)))) >> (112 + (lvl & 1) * 24));
        uint256 bits = uint256(vm.load(address(subject), bytes32(uint256(76) + (lvl & 1))));
        return stamp == lvl && ((bits >> trait) & 1) != 0 ? uint32(header) : 0;
    }

    function _snapshotDrain(DegenerusGame subject) internal view returns (DrainSnapshot memory snap) {
        uint24 lvl = subject.level();
        snap.firstLevel = lvl == 0 ? 0 : lvl - 1;
        snap.index = _lrIndexOf(subject);
        snap.round = _roundOf(subject);
        // One advance cannot move the active window beyond level+2. Include its trailing
        // level as well, so the same oracle sees current and frozen future-pool batches.
        for (uint256 n; n < 1024; ++n) {
            snap.lengths[n] = _bucketLengthOf(subject, snap.firstLevel + uint24(n / 256), n % 256);
        }
    }

    function _ownerAt(DegenerusGame subject, uint24 lvl, uint8 trait, uint256 occurrence)
        private view returns (address)
    {
        bytes32 slot = _bucketSlot(lvl, trait);
        uint256 len = _bucketLengthOf(subject, lvl, trait);
        if (occurrence >= len) return address(0);
        // The final partial word lives in header bits32..255. Completed words
        // remain in the payload, including the last word of an exact multiple of8.
        uint256 lanes = occurrence / 8 == len / 8
            ? uint256(vm.load(address(subject), slot)) >> 32
            : uint256(vm.load(address(subject), bytes32(uint256(keccak256(abi.encode(slot))) + occurrence / 8)));
        uint32 ownerIndex = uint32(lanes >> (32 * (occurrence % 8)));
        // Bucket lanes hold zero-based indices into the append-only global array.
        bytes32 owners = bytes32(SLOT_OWNERS);
        if (ownerIndex >= uint256(vm.load(address(subject), owners))) return address(0);
        return address(uint160(uint256(vm.load(address(subject), bytes32(uint256(keccak256(abi.encode(owners))) + ownerIndex)))));
    }

    /// @dev Reimplement the published 64-bit generator and color thresholds without
    /// calling the production trait helper. Each returned byte includes its quadrant.
    function _referenceTraits(uint256 key, uint256 word, uint32 start, uint32 take)
        private pure returns (uint8[] memory traits)
    {
        traits = new uint8[](take);
        uint256 end = uint256(start) + take;
        uint256 i = start;
        while (i < end) {
            uint64 state = uint64(uint256(keccak256(abi.encode(key, word, uint32(i / 16))))) | 1;
            uint64 offset = uint64(i % 16);
            unchecked { state = state * (6364136223846793005 + offset) + offset; }
            for (uint256 j = offset; j < 16 && i < end; ++j) {
                unchecked { state = state * 6364136223846793005 + 1; }
                uint8 quantile = uint8(state >> 24);
                uint8 color = quantile < 64 ? 0 : quantile < 128 ? 1 : quantile < 192 ? 2
                    : quantile < 224 ? 3 : quantile < 240 ? 4 : quantile < 248 ? 5 : quantile < 254 ? 6 : 7;
                traits[i - start] = uint8((i % 4) * 64) | (color << 3) | (uint8(state >> 32) & 7);
                ++i;
            }
        }
    }

    function _checkDrain(DegenerusGame subject, DrainSnapshot memory snap, Vm.Log[] memory logs, uint256 committedWord, address trackedPlayer)
        internal view returns (DrainResult memory result)
    {
        uint256[1024] memory added;
        uint256 previousKey = type(uint256).max;
        uint32 processed;
        if (_roundOf(subject) != snap.round) ++result.unsupported;
        for (uint256 k; k < logs.length; ++k) {
            Vm.Log memory entry = logs[k];
            if (entry.emitter != address(subject) || entry.topics.length != 2 || entry.topics[0] != TOPIC_TRAITS_GENERATED) continue;
            (uint256 key, uint32 take) = abi.decode(entry.data, (uint256, uint32));
            uint24 lvl = uint24(key >> 224);
            address player = address(uint160(uint256(entry.topics[1])));
            if (lvl < snap.firstLevel || uint256(lvl - snap.firstLevel) >= 4 || take == 0
                || (uint32(key) == 0 && take != 1)) {
                // A zero-owed normal entry may win one fractional entry; a foil's
                // sixteen-entry TraitsGenerated receipt is not an LCG batch.
                ++result.unsupported;
                continue;
            }
            if (address(uint160(key >> 32)) != player) ++result.mismatches;
            uint256 identity = key >> 32;
            if (identity != previousKey) processed = 0;
            previousKey = identity;
            uint8[] memory traits = _referenceTraits(key, committedWord, processed, take);
            for (uint256 i; i < traits.length; ++i) {
                uint256 n = uint256(lvl - snap.firstLevel) * 256 + traits[i];
                uint256 pos = snap.lengths[n] + added[n]++;
                if (_ownerAt(subject, lvl, traits[i], pos) != player) ++result.mismatches;
            }
            processed += take;
            ++result.batches;
            result.entries += take;
            if (player == trackedPlayer) result.trackedEntries += take;
        }
        if (result.batches == 0) return result;
        // Compare every bucket, including zero-expected buckets: a wrong word cannot
        // escape merely by placing entries outside the traits predicted above.
        for (uint256 n; n < 1024; ++n) {
            uint256 afterLength = _bucketLengthOf(subject, snap.firstLevel + uint24(n / 256), n % 256);
            if (afterLength != snap.lengths[n] + added[n]) ++result.mismatches;
        }
    }
}

/// @notice Stateful daily-drain binding checks over real ticket-only purchases, requests,
/// fulfillments and time advances. A single buyer plus protocol recipients stays below
/// the seated-round threshold; this suite makes no claim about foil/round RNG derivations.
contract RngIndexDrainHandler is RngIndexDrainOracle {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    DegenerusAdmin public admin;
    address public immutable actor = address(0xD10A0);

    uint256 public ghost_drainBeforeSwapViolations;
    uint256 public ghost_zeroEntropyConsumptions;
    uint256 public ghost_bindingMismatches;
    uint256 public ghost_unsupportedConsumers;
    uint256 public ghost_dailyDrainBranchEntered;
    uint256 public ghost_entriesChecked;
    uint256 public ghost_buyerEntriesChecked;
    uint256 public ghost_gameOverBranchEntered;
    uint256 public calls_advance;
    uint256 public calls_purchase;
    uint256 public calls_fulfillVrf;
    uint256 public calls_warp;

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, DegenerusAdmin admin_) {
        game = game_;
        vrf = vrf_;
        admin = admin_;
        vm.deal(actor, 1000 ether);
        vrf.fundSubscription(1, 1000e18);
    }

    function purchase(uint256 qty) external {
        ++calls_purchase;
        if (game.gameOver()) return;
        // Small paid buys keep this campaign below the genesis prize target and
        // avoid unrelated level transitions; quantity remains fuzzed, including dust.
        qty = bound(qty, 100, 2000);
        (,,,, uint256 priceWei) = game.purchaseInfo();
        uint256 cost = priceWei * qty / 400;
        vm.prank(actor);
        try game.purchase{value: cost}(actor, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function advance() external {
        ++calls_advance;
        if (game.gameOver()) { ++ghost_gameOverBranchEntered; return; }
        DrainSnapshot memory snap = _snapshotDrain(game);
        vm.recordLogs();
        try game.mineFlip() {} catch {
            // Reverted logs are not committed state and must not be scored.
            vm.getRecordedLogs();
            return;
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 committedWord = _wordAt(game, snap.index ^ 1);
        DrainResult memory result = _checkDrain(game, snap, logs, committedWord, actor);
        ghost_bindingMismatches += result.mismatches;
        ghost_unsupportedConsumers += result.unsupported;
        if (result.batches != 0) {
            ++ghost_dailyDrainBranchEntered;
            ghost_entriesChecked += result.entries;
            ghost_buyerEntriesChecked += result.trackedEntries;
            if (committedWord == 0) ++ghost_zeroEntropyConsumptions;
            if (_lrIndexOf(game) != snap.index) ++ghost_drainBeforeSwapViolations;
        }
    }

    function fulfillVrf(uint256 randomWord) external {
        ++calls_fulfillVrf;
        uint256 id = vrf.lastRequestId();
        if (id == 0) return;
        (,, bool fulfilled) = vrf.pendingRequests(id);
        if (fulfilled) return;
        try vrf.fulfillRandomWords(id, randomWord) {} catch {}
    }

    function warpTime(uint256 delta) external {
        ++calls_warp;
        vm.warp(block.timestamp + bound(delta, 1 hours, 2 days));
    }
}
