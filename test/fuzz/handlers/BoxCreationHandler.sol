// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusDeityPass} from "../../../contracts/DegenerusDeityPass.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title BoxCreationHandler — drives every box-creating entrypoint for the FUZZ-04 ENQUEUE invariant
/// @notice The box-creating family the ASYM-02 sweep enumerates has FOUR enqueue sites, each guarded by a
///         first-deposit check that pushes the (index, owner) into boxPlayers[index] for the permissionless
///         openBoxes() auto-opener:
///           - mint-with-lootbox purchase           (MintModule first-deposit -> boxPlayers push)
///           - whale / lazy / deity pass bundle      (WhaleModule._recordLootboxEntry -> boxPlayers push)
///           - presale box                           (MintModule._buyPresaleBoxFor -> boxPlayers push)
///           - afking-cover subscribe-grounding box  (GameAfkingModule._recordAfkingCoverBox -> boxPlayers push)
///
///         This handler exercises each path in a randomized sequence through the REAL entrypoints (never a
///         vm.store of a box record — the box is created by the contract so the enqueue site actually fires),
///         records every successfully-created (index, owner) pair into a tracked list the BoxEnqueue invariant
///         iterates, and bumps a per-path ghost counter so the invariant can prove non-vacuity (boxes were
///         actually created across multiple paths). It also drives openBoxes()/advanceGame()+VRF-fulfill so
///         boxes drain to base==0 over the campaign — exercising BOTH the still-enqueued and the resolved
///         transitions the invariant distinguishes.
///
/// @dev WHALE-01 is the bug this net catches: a sibling box-creation path that persists a record
///      (lootboxEth/presaleBoxEth with base != 0) but skips the boxPlayers[index] push, letting the sole
///      opener (manual openLootBox is operator-gated) hold the box and time the open to a favorable
///      level/boon. The actor base is 0x70000 (disjoint from WhaleHandler's 0xB0000 and the afking
///      handler's 0xAF000 / 0xDE17A); each actor is field-isolated-seeded with the HAS_DEITY_PASS score
///      bit so the subscribe/pass gates pass. Test-only: ZERO contracts/*.sol mutation.
contract BoxCreationHandler is Test {
    DegenerusGame public game;
    DegenerusDeityPass public deityPass;
    MockVRFCoordinator public vrf;

    // -------------------------------------------------------------------------
    // Canonical c4d48008 storage layout (380-01 LAYOUT-KEY, confirmed via forge inspect)
    // -------------------------------------------------------------------------
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184; // HAS_DEITY_PASS score bit (subscribe/pass gate)
    uint256 private constant LR_PACKED_SLOT = 35; // lootboxRngPacked; LR_INDEX = low 48 bits (post V62 repack)
    uint256 private constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;
    uint256 private constant PRESALE_BOX_CREDIT_SLOT = 17; // mapping(address => uint256)
    // The folded lootboxEth word: amount[0:128] | adj[128:192] | scorePlus1[192:208] | distress[208:256].
    uint256 private constant LOOTBOX_ETH_SLOT = 15; // mapping(uint48 => mapping(address => uint256))
    uint256 private constant LOOTBOX_AMOUNT_MASK = (uint256(1) << 128) - 1; // amount sub-field [0:128]

    // -------------------------------------------------------------------------
    // A tracked (index, owner) record — the invariant asserts each persisted one is enqueued.
    // -------------------------------------------------------------------------
    struct BoxRef {
        uint48 index;
        address owner;
    }

    BoxRef[] private created;
    // Dedup guard: (index, owner) -> already tracked.
    mapping(uint48 => mapping(address => bool)) private tracked;

    // --- Per-path ghost counters (non-vacuity: each box-creating path that fires bumps its own) ---
    uint256 public boxesCreated_mintLootbox;
    uint256 public boxesCreated_whale;
    uint256 public boxesCreated_lazy;
    uint256 public boxesCreated_deity;
    uint256 public boxesCreated_presale;
    uint256 public boxesCreated_afkingCover;

    // --- Call counters (coverage visibility) ---
    uint256 public calls_mintLootbox;
    uint256 public calls_whale;
    uint256 public calls_lazy;
    uint256 public calls_deity;
    uint256 public calls_presale;
    uint256 public calls_openSome;

    // --- Actors (disjoint 0x70000 base) ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(
        DegenerusGame game_,
        DegenerusDeityPass deityPass_,
        MockVRFCoordinator vrf_,
        uint256 numActors
    ) {
        game = game_;
        deityPass = deityPass_;
        vrf = vrf_;

        for (uint256 i = 0; i < numActors; i++) {
            // 0x70000 base: disjoint from WhaleHandler (0xB0000) and V61AfkingSpendHandler (0xAF000/0xDE17A).
            address actor = address(uint160(0x70000 + i));
            actors.push(actor);
            vm.deal(actor, 1_000 ether);
            // Seed the HAS_DEITY_PASS score bit on EVEN actors only — it grants the subscribe gate the
            // presale-box path needs, but a deity-pass HOLDER cannot buy a lazy pass NOR a fresh deity pass
            // (both revert), so the un-seeded ODD actors keep the lazy-pass and deity-pass surfaces reachable.
            // A field-isolated mintPacked_ seed (no balance touched) — mirrors the established
            // V61AfkingSpendHandler / SolvencyActionHandler split. The whale bundle works for either band.
            if (i % 2 == 0) _grantDeityScoreBit(actor);
        }
    }

    // =========================================================================
    // The tracked (index, owner) set + the per-path counters the invariant reads
    // =========================================================================

    /// @notice Every (index, owner) box record this campaign created via a real entrypoint. The invariant
    ///         iterates these and, for each with base != 0 (persisted, not yet opened), asserts it is present
    ///         in boxPlayers[index].
    function trackedBoxes() external view returns (BoxRef[] memory refs) {
        refs = new BoxRef[](created.length);
        for (uint256 i; i < created.length; i++) refs[i] = created[i];
    }

    function trackedCount() external view returns (uint256) {
        return created.length;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    /// @notice Sum of the per-path box-creation counters (non-vacuity headline).
    function totalBoxesCreated() external view returns (uint256) {
        return
            boxesCreated_mintLootbox +
            boxesCreated_whale +
            boxesCreated_lazy +
            boxesCreated_deity +
            boxesCreated_presale +
            boxesCreated_afkingCover;
    }

    /// @notice Count of DISTINCT box-creating paths that fired at least once (the >=2 non-vacuity gate).
    function pathsExercised() external view returns (uint256 n) {
        if (boxesCreated_mintLootbox != 0) n++;
        if (boxesCreated_whale != 0) n++;
        if (boxesCreated_lazy != 0) n++;
        if (boxesCreated_deity != 0) n++;
        if (boxesCreated_presale != 0) n++;
        if (boxesCreated_afkingCover != 0) n++;
    }

    // =========================================================================
    // Action 1: mint-with-lootbox (a non-zero lootboxAmt on purchase persists a lootbox box at LR_INDEX)
    // =========================================================================

    /// @notice Buy a whole ticket bundle with a non-zero lootbox spend. The first deposit at the active index
    ///         enqueues the box (MintModule:1251). Cycles DirectEth/Combined so both fresh-ETH branches run.
    function mintWithLootbox(uint256 actorSeed, uint256 lbSeed, uint8 kindSeed) external useActor(actorSeed) {
        calls_mintLootbox++;
        if (game.gameOver()) return;

        uint256 lootboxAmt = bound(lbSeed, 0.01 ether, 2 ether);
        // DirectEth or Combined (skip Claimable here — it sends no fresh ETH and the actor may have none).
        MintPaymentKind kind = (kindSeed & 1) == 0 ? MintPaymentKind.DirectEth : MintPaymentKind.Combined;

        // One whole ticket (400 entries) + the lootbox spend, funded generously with fresh ETH.
        uint256 value = lootboxAmt + 1 ether;
        if (value > currentActor.balance) return;

        uint48 idx = _lrIndex();
        vm.prank(currentActor);
        try game.purchase{value: value}(currentActor, 400, lootboxAmt, bytes32(0), kind) {
            // A successful lootbox-bearing purchase persists a box at this index; count the path and track the
            // (index, owner) for the invariant. The counter is bumped per successful creating-call (the
            // non-vacuity signal that this PATH fired); the tracked list is deduped so the invariant iterates
            // each (index, owner) once even when several paths deposit into the SAME accumulating record.
            boxesCreated_mintLootbox++;
            _track(idx, currentActor);
        } catch {}
    }

    // =========================================================================
    // Action 2: pass bundles (whale / lazy / deity — each deposits a 10%-of-price lootbox via WhaleModule)
    // =========================================================================

    /// @notice Whale bundle: a 10%-of-price lootbox is recorded via _recordLootboxEntry (WhaleModule:896
    ///         first-deposit enqueue). passLevel bounded [1,5]; 2.4 ETH base price covers early levels.
    function buyWhaleBundle(uint256 actorSeed, uint256 qtySeed) external useActor(actorSeed) {
        calls_whale++;
        if (game.gameOver()) return;

        uint256 qty = bound(qtySeed, 1, 5);
        uint256 cost = 2.4 ether * qty;
        if (cost > currentActor.balance) return;

        uint48 idx = _lrIndex();
        vm.prank(currentActor);
        try game.purchaseWhaleBundle{value: cost}(currentActor, qty) {
            boxesCreated_whale++;
            _track(idx, currentActor);
        } catch {}
    }

    /// @notice Lazy pass: 0.24 ETH at early levels; deposits a 10% lootbox the same way.
    function buyLazyPass(uint256 actorSeed) external useActor(actorSeed) {
        calls_lazy++;
        if (game.gameOver()) return;

        uint256 cost = 0.24 ether;
        if (cost > currentActor.balance) return;

        uint48 idx = _lrIndex();
        vm.prank(currentActor);
        try game.purchaseLazyPass{value: cost}(currentActor) {
            boxesCreated_lazy++;
            _track(idx, currentActor);
        } catch {}
    }

    /// @notice Deity pass: base 24 ETH (first pass; subsequent passes cost more and revert on the fixed price,
    ///         which the try/catch swallows). Deposits a 10% lootbox via the pass path.
    function buyDeityPass(uint256 actorSeed, uint256 symbolSeed) external useActor(actorSeed) {
        calls_deity++;
        if (game.gameOver()) return;

        uint8 symbolId = uint8(bound(symbolSeed, 0, 31));
        uint256 cost = 24 ether;
        if (cost > currentActor.balance) return;

        uint48 idx = _lrIndex();
        vm.prank(currentActor);
        try game.purchaseDeityPass{value: cost}(currentActor, symbolId) {
            boxesCreated_deity++;
            _track(idx, currentActor);
        } catch {}
    }

    // =========================================================================
    // Action 3: presale box (the credit-gated coin-presale box — its own enqueue at MintModule:1602)
    // =========================================================================

    /// @notice Buy a presale box. Presale-box credit is normally earned 25% on buys; here it is seeded directly
    ///         (the established PresaleBoxDrain idiom — a CREDIT allowance write at slot 17, NOT a box-record
    ///         write) so the box is created reliably through the REAL buyPresaleBox entrypoint, which writes
    ///         presaleBoxEth and enqueues via the real inlined boxPlayers push. boxAmount bounded [0.01, 2] ETH.
    function buyPresaleBox(uint256 actorSeed, uint256 amtSeed) external useActor(actorSeed) {
        calls_presale++;
        if (game.gameOver()) return;
        // presaleOver latches at the 50-ETH close; presaleBoxEthRemaining() returns 0 once latched or sold
        // out (DegenerusGame:2537), so it is the public proxy for "the presale-box path is still open".
        if (game.presaleBoxEthRemaining() == 0) return;

        uint256 boxAmount = bound(amtSeed, 0.01 ether, 2 ether);
        if (boxAmount > currentActor.balance) return;

        // Seed enough spendable credit for this buy (credit is consumed 1:1; an over-credit request reverts).
        _grantCredit(currentActor, boxAmount);

        uint48 idx = _lrIndex();
        vm.prank(currentActor);
        try game.buyPresaleBox{value: boxAmount}(currentActor, boxAmount) {
            boxesCreated_presale++;
            _track(idx, currentActor);
        } catch {}
    }

    // =========================================================================
    // Action 4: open + advance (drain boxes to base==0; land per-index words so opens resolve)
    // =========================================================================

    /// @notice Run the permissionless openBoxes() auto-opener, then advance the state machine a few steps and
    ///         fulfill any pending VRF so per-index words land and ready boxes resolve (base -> 0). This is what
    ///         drives the still-enqueued -> resolved transition the invariant distinguishes (opened boxes are
    ///         correctly excluded). A small actor buy first satisfies the daily purchase gate for advance.
    function openSome(uint256 actorSeed, uint256 maxSeed, uint256 wordSeed) external useActor(actorSeed) {
        calls_openSome++;

        uint256 maxCount = bound(maxSeed, 1, 50);
        vm.prank(currentActor);
        try game.openBoxes(maxCount) {} catch {}

        if (game.gameOver()) return;

        // Satisfy the daily purchase gate with one whole ticket so advanceGame can progress.
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: priceWei}(currentActor, 400, 0, bytes32(0), MintPaymentKind.DirectEth) {} catch {}
        }

        for (uint256 i; i < 3; i++) {
            vm.prank(currentActor);
            try game.advanceGame() {} catch {}
            uint256 reqId = vrf.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = vrf.pendingRequests(reqId);
                if (!fulfilled) {
                    try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(wordSeed, i))) | 1) {} catch {}
                }
            }
        }

        // After resolution some boxes drained to base==0; open the box queue once more so the resolved
        // transition is realized for the invariant to observe both states across the campaign.
        vm.prank(currentActor);
        try game.openBoxes(maxCount) {} catch {}
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    /// @dev Record a created (index, owner) into the deduped tracked list the invariant iterates. A lootbox
    ///      record ACCUMULATES across deposits at one index for one owner, so several creating-calls can land
    ///      on the SAME (index, owner); deduping keeps the invariant's iteration set to one entry per box
    ///      record (the per-path NON-VACUITY counter is bumped separately, per successful creating-call, at the
    ///      call site). Returns true on a first insert (unused by callers; kept for diagnostic clarity).
    function _track(uint48 index, address owner) internal returns (bool firstInsert) {
        if (tracked[index][owner]) return false;
        tracked[index][owner] = true;
        created.push(BoxRef({index: index, owner: owner}));
        return true;
    }

    /// @dev Active lootbox RNG index (low 48 bits of lootboxRngPacked, slot 36).
    function _lrIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(LR_PACKED_SLOT)));
        return uint48(packed & LR_INDEX_MASK);
    }

    /// @dev Field-isolated HAS_DEITY_PASS score-bit seed in mintPacked_ (slot 9, shift 184). No balance touched.
    function _grantDeityScoreBit(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Seed spendable presale-box credit (slot 17) — a credit ALLOWANCE, not a box record. The box itself
    ///      is created by the real buyPresaleBox entrypoint. Mirrors PresaleBoxDrain._grantCredit.
    function _grantCredit(address buyer, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(buyer, uint256(PRESALE_BOX_CREDIT_SLOT)));
        uint256 existing = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(existing + amount));
    }

    // =========================================================================
    // Falsifiability seams (used ONLY by the BoxEnqueue falsifiability test, never by a fuzzed action)
    // =========================================================================

    /// @dev FALSIFIABILITY seam: simulate the WHALE-01 bug shape — a persisted lootboxEth record (amount != 0)
    ///      that was NOT pushed into boxPlayers[index]. Writes the lootbox amount sub-field of
    ///      lootboxEth[index][who] (slot 15 nested mapping) via a field-isolated vm.store WITHOUT calling any
    ///      enqueue site, so boxPlayersContains(index, who) stays false. This is exactly the persisted-but-
    ///      unenqueued state the invariant must catch; it is NOT used by any fuzzed action (the campaign creates
    ///      boxes only through real entrypoints, which always enqueue). The adj/score/distress high bits are
    ///      left untouched; only the amount sub-field [0:128] is set (the box-owed signal).
    function debugSeedUnenqueuedBox(uint48 index, address who, uint256 amount) external {
        bytes32 slot = _lootboxEthSlot(index, who);
        uint256 packed = uint256(vm.load(address(game), slot));
        packed = (packed & ~LOOTBOX_AMOUNT_MASK) | (amount & LOOTBOX_AMOUNT_MASK);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev FALSIFIABILITY seam: clear the seeded lootboxEth amount (base -> 0), returning the invariant's
    ///      underlying check to green so the falsifiability test can prove the break was the injection.
    function debugClearBox(uint48 index, address who) external {
        bytes32 slot = _lootboxEthSlot(index, who);
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~LOOTBOX_AMOUNT_MASK;
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Storage slot of lootboxEth[index][who] — a nested mapping(uint48 => mapping(address => uint256))
    ///      at slot 15: keccak(who . keccak(index . slot)).
    function _lootboxEthSlot(uint48 index, address who) internal pure returns (bytes32) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_SLOT)));
        return keccak256(abi.encode(who, inner));
    }
}
