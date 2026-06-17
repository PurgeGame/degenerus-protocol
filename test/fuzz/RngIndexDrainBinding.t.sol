// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RngIndexDrainBinding -- Phase 232.1 SPEC AC-3 (binding consistency)
/// @notice For a ticket frozen at lootbox RNG index X, the entropy parameter
///         consumed by `_raritySymbolBatch` (captured via the TraitsGenerated
///         event) equals `lootboxRngWordByIndex[X]` and is non-zero at drain time.
/// @dev    Instrumentation: Option A (event-capture via existing TraitsGenerated
///         event at DegenerusGameStorage.sol:479, emitted inside processTicketBatch
///         at DegenerusGameMintModule.sol:470 immediately after _raritySymbolBatch).
///         No contract changes needed.
contract RngIndexDrainBindingTest is DeployProtocol {
    /// @dev Storage slot for `lootboxRngWordByIndex` mapping. Authoritative at the
    ///      working tree via `solc --storage-layout` (post Stage B Game pack:
    ///      lootboxRngWordByIndex = slot 35, was 36).
    uint256 internal constant SLOT_LOOTBOX_MAPPING = 35;
    /// @dev Storage slot for `lootboxRngPacked` (LR_INDEX at low 48 bits).
    ///      Authoritative slot 34 (post Stage B Game pack: was 35).
    uint256 internal constant SLOT_LR_INDEX = 34;
    /// @dev Base slot for `boxPlayers` mapping(uint48 => address[]). Authoritative
    ///      at the working tree (confirmed at runtime: boxPlayers[idx][0] == buyer).
    uint256 internal constant SLOT_BOX_PLAYERS_MAPPING = 59;
    /// @dev Base slot for `presaleBoxEth` mapping(uint48 => mapping(address => uint256)).
    ///      Authoritative at the working tree (confirmed at runtime: low-96 cell == applied box ETH).
    uint256 internal constant SLOT_PRESALE_BOX_ETH_MAPPING = 15;

    /// @dev Keccak topic-0 for the frozen slimmed TraitsGenerated(address,uint256,uint32)
    ///      (DegenerusGameStorage:501). The pre-slim 6-arg form
    ///      `TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)` (and its `entropy`
    ///      field) no longer exists, which is the DEF-380-04-FC5 observability cause that skips
    ///      both binding tests below.
    bytes32 internal constant TOPIC_TRAITS_GENERATED =
        keccak256("TraitsGenerated(address,uint256,uint32)");

    address internal buyer;
    uint256 internal lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("drainBindingBuyer");
        vm.deal(buyer, 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Read the player recorded at boxPlayers[index][0]. boxPlayers is the
    ///      `mapping(uint48 => address[])` queued by a presale-box purchase
    ///      (DegenerusGameMintModule:1965 `boxPlayers[index].push(buyer)`), so element
    ///      [0] is the FIRST buyer keyed at `index`. Authoritative mapping base = slot 59.
    function _boxPlayerAt0(uint48 index) internal view returns (address) {
        bytes32 arrSlot = keccak256(abi.encode(uint256(index), SLOT_BOX_PLAYERS_MAPPING));
        bytes32 elem0 = keccak256(abi.encode(arrSlot));
        return address(uint160(uint256(vm.load(address(game), elem0))));
    }

    /// @dev Read presaleBoxEth[index][player] (low 96 bits = applied box ETH). A box buy
    ///      records itself at the LIVE LR_INDEX (DegenerusGameMintModule:1949/1960), so a
    ///      nonzero cell at (index, player) proves the box bound to that exact index.
    ///      Authoritative nested-mapping base = slot 15.
    function _presaleBoxEth(uint48 index, address player) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), SLOT_PRESALE_BOX_ETH_MAPPING));
        bytes32 cell = keccak256(abi.encode(player, inner));
        return uint256(vm.load(address(game), cell));
    }

    /// @dev Read lootboxRngWordByIndex[index] directly from storage.
    function _lootboxWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), SLOT_LOOTBOX_MAPPING));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Read LR_INDEX from `lootboxRngPacked` (slot 34, low 48 bits).
    function _lrIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT_LR_INDEX))));
    }

    /// @dev Purchase tickets for buyer at current level.
    function _purchase(uint256 qty, uint256 lootboxWei) internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        uint256 total = ticketCost + lootboxWei;
        vm.prank(buyer);
        game.purchase{value: total}(
            buyer,
            qty,
            lootboxWei,
            bytes32(0),
            MintPaymentKind.DirectEth
        );
    }

    /// @dev Advance + fulfill VRF + advance-until-unlock. Captures all logs
    ///      emitted during the entire advance sequence (including the drain).
    function _completeDayWithLogs(uint256 vrfWord)
        internal
        returns (Vm.Log[] memory logs)
    {
        vm.recordLogs();
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
        logs = vm.getRecordedLogs();
    }

    /// @dev Scan logs for all TraitsGenerated events and extract the trailing word.
    ///      INERT at the frozen subject c4d48008: the slimmed event
    ///      `TraitsGenerated(address indexed player, uint256 baseKey, uint32 take)` carries NO
    ///      `entropy` field, and TOPIC_TRAITS_GENERATED is the 3-arg topic, so this never matches
    ///      a real log that carries the old entropy payload. Retained only for the two
    ///      DEF-380-04-FC5-skipped binding tests; both vm.skip before reaching it.
    function _capturedEntropies(Vm.Log[] memory logs)
        internal
        pure
        returns (uint256[] memory entropies)
    {
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == TOPIC_TRAITS_GENERATED) {
                count++;
            }
        }
        entropies = new uint256[](count);
        uint256 j;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == TOPIC_TRAITS_GENERATED) {
                // data = (uint32 queueIdx, uint32 startIndex, uint32 count, uint256 entropy)
                // last 32 bytes of data is the entropy field.
                bytes memory d = logs[i].data;
                uint256 entropy;
                assembly {
                    entropy := mload(add(d, mload(d)))
                }
                entropies[j++] = entropy;
            }
        }
    }

    // =========================================================================
    // AC-3: Binding consistency on the normal end-of-day daily drain path
    // =========================================================================

    /// @notice For every ticket-batch processed by the daily-drain, the entropy
    ///         consumed by _raritySymbolBatch equals the lootbox RNG word at the
    ///         corresponding index AND is non-zero.
    /// @dev DEF-380-04-FC5 (finding-candidate routed to the council, 382+ PRIME / 385 VRF-path sweep).
    ///      SKIPPED against the frozen subject c4d48008: this test observes the per-batch
    ///      entropy by decoding it out of the TraitsGenerated event, but the frozen event was
    ///      slimmed to `TraitsGenerated(address indexed player, uint256 baseKey, uint32 take)`
    ///      (DegenerusGameStorage:501) — it NO LONGER carries the `entropy` field. The drain
    ///      STILL consumes `entropy` internally (`_raritySymbolBatch(player, baseKey, processed,
    ///      take, entropy)` at DegenerusGameMintModule:473), but it is not emitted, so the
    ///      RNG-binding invariant ("the entropy consumed == lootboxRngWordByIndex[boundIdx]")
    ///      is no longer observable from the event. `baseKey` is a structured ticket key
    ///      (`(lvl<<224)|(idx<<192)|(player<<32)|owed`, MintModule:429), NOT the entropy, so
    ///      re-pointing the assertion at `baseKey` would assert nothing about the RNG binding
    ///      and would MASK the lost observability. Whether the daily-drain entropy is still
    ///      correctly index-bound (and whether the event-slimming should keep an observability
    ///      hook for it) is an RNG-window judgment for the council — NOT a stale topic/slot the
    ///      test can re-derive without changing what it proves. Recorded in
    ///      REGRESSION-BASELINE-v62.md "Known behavior-divergence — finding-candidates". The
    ///      sibling testBindingConsistencyMidDayCrossDay passes only because it vacuously
    ///      returns when entropies.length == 0 (same removed-field cause). The contract is NOT
    ///      modified.
    function testBindingConsistencyDailyDrain() public {
        vm.skip(true); // DEF-380-04-FC5 — see @dev above; council adjudicates (382+/385)
        _purchase(400, 0);

        uint48 idxBeforeAdvance = _lrIndex();

        uint256 vrfWord = uint256(keccak256("binding-daily-drain-word"));
        Vm.Log[] memory logs = _completeDayWithLogs(vrfWord);

        uint256[] memory entropies = _capturedEntropies(logs);
        assertGt(entropies.length, 0, "AC-3: no TraitsGenerated emitted during drain");

        // The drain reads lootboxRngWordByIndex[LR_INDEX - 1] where LR_INDEX was
        // bumped to idxBeforeAdvance + 1 by the daily VRF request. So the binding
        // target is index (idxBeforeAdvance + 1) - 1 = idxBeforeAdvance ... but
        // only if the VRF request actually landed. Tolerate the case where index
        // bumped by zero (no-ticket day) — entropies.length will be 0 in that case
        // and we already asserted >0 above.
        uint48 idxAfterAdvance = _lrIndex();
        assertGe(idxAfterAdvance, idxBeforeAdvance + 1, "VRF request did not bump LR_INDEX");

        uint48 boundIdx = idxAfterAdvance - 1;
        uint256 slotWord = _lootboxWord(boundIdx);

        assertTrue(slotWord != 0, "AC-3: lootboxRngWordByIndex[X] is zero at drain time");

        for (uint256 i = 0; i < entropies.length; i++) {
            assertTrue(entropies[i] != 0, "AC-3: captured entropy is zero");
            assertEq(
                entropies[i],
                slotWord,
                "AC-3: captured entropy != lootboxRngWordByIndex[X]"
            );
        }
    }

    // =========================================================================
    // AC-3 / R2: Binding consistency on the mid-day -> cross-day edge
    // =========================================================================

    /// @notice A box purchased AFTER a mid-day VRF request binds to the LIVE LR_INDEX,
    ///         NOT to the in-flight LR_INDEX-1 word being delivered. The mid-day request
    ///         (`requestLootboxRng`) advances the lootbox index by exactly 1
    ///         (DegenerusGameAdvanceModule._lrAdvanceIndexClearPending at :1140) and reserves
    ///         the in-flight word at the just-vacated index (LR_INDEX-1). A subsequent box buy
    ///         records itself at the NEW LR_INDEX (DegenerusGameMintModule:1949/1960 — and the
    ///         :1951 `lootboxRngWordByIndex[index] != 0` guard rejects binding to a worded
    ///         index), so when the in-flight word lands at LR_INDEX-1 the post-request box at
    ///         LR_INDEX is still un-worded and CANNOT be resolved by that word. This is the
    ///         load-bearing RNG-freeze property: a buyer cannot be resolved by a word already
    ///         requested at buy time.
    /// @dev    Replaces the prior event-decode form (DEF-380-04-FC5): the slimmed
    ///         `TraitsGenerated(address,uint256,uint32)` event (DegenerusGameStorage:501) dropped
    ///         the `entropy` field, so the old `_capturedEntropies` path always returned empty and
    ///         the test passed vacuously. This rewrite reads `lootboxRngWordByIndex` AND the
    ///         box-binding records (`boxPlayers` / `presaleBoxEth`) directly from storage, pinning
    ///         the exact index each artifact binds to — no removed event field, no vacuous return.
    ///         The contract is NOT modified.
    function testBindingConsistencyMidDayCrossDay() public {
        // ── Mid-day prerequisite: today's daily RNG must already be consumed
        //    (requestLootboxRng reverts while rngWordByDay[today] == 0). Complete a
        //    day, then sit on the new day so today's word is committed.
        _completeDayWithLogs(uint256(keccak256("midday-binding-setup-word")));
        vm.warp(block.timestamp + 1 days);
        _completeDayWithLogs(uint256(keccak256("midday-binding-setup-word-2")));

        // ── Box A: a pre-request box buy creates pending lootbox ETH (clears the
        //    1-ether mid-day threshold) and keys itself at the LIVE index N.
        _purchase(400, 1 ether);
        uint48 idxN = _lrIndex();
        assertEq(_boxPlayerAt0(idxN), buyer, "box A not keyed at live LR_INDEX");
        assertEq(uint96(_presaleBoxEth(idxN, buyer)), 1 ether, "box A applied-ETH mis-keyed");
        assertEq(_lootboxWord(idxN), 0, "live index already worded before request");

        // ── Mid-day VRF request: bumps LR_INDEX N -> N+1 and reserves the in-flight
        //    word at index N (= the new LR_INDEX - 1). The word is NOT yet delivered.
        game.requestLootboxRng();
        uint48 idxLive = _lrIndex();
        assertEq(idxLive, idxN + 1, "mid-day request did not advance LR_INDEX by exactly 1");
        assertEq(
            _lootboxWord(idxLive - 1),
            0,
            "in-flight LR_INDEX-1 word delivered before VRF fulfillment"
        );

        // ── Box B: a SECOND box bought AFTER the request must bind to the LIVE index
        //    (N+1), never to the in-flight index N being drained. The contract's
        //    :1951 worded-index guard would revert if it tried to key at a worded slot.
        address buyerB = makeAddr("drainBindingBuyerB");
        vm.deal(buyerB, 100 ether);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * 400) / 400;
        vm.prank(buyerB);
        game.purchase{value: ticketCost + 1 ether}(
            buyerB, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
        );
        assertEq(_boxPlayerAt0(idxLive), buyerB, "box B not keyed at the LIVE post-request index");
        assertEq(uint96(_presaleBoxEth(idxLive, buyerB)), 1 ether, "box B applied-ETH not at live index");
        assertEq(_presaleBoxEth(idxN, buyerB), 0, "box B leaked onto the in-flight index N");

        // ── Deliver the in-flight mid-day word. It lands ONLY at index N (LR_INDEX-1).
        uint256 midWord = uint256(keccak256("midday-binding-inflight-word"));
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, midWord);

        // Binding result: index N is now worded; the post-request index N+1 is STILL
        // un-worded — box B cannot be resolved by the word requested before it was bought.
        assertTrue(_lootboxWord(idxN) != 0, "in-flight word did not land at index N");
        assertEq(
            _lootboxWord(idxLive),
            0,
            "post-request live index N+1 became worded by the in-flight request"
        );
    }
}
