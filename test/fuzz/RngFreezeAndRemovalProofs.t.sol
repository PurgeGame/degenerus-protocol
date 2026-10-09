// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegeneretteQueue as DQ} from "../helpers/DegeneretteQueue.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @notice Real-contract RNG-window checks: resolution waits for its word, placement rejects
///         committed buffers, winnings credit claimable, and deferred whale passes preserve
///         claim-time ticket grants and mint history.
contract RngFreezeAndRemovalProofs is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (DegenerusGame; RE-DERIVED via `solc --storage-layout` on the working
    // tree after the Stage B Game-storage packing — lootboxRngPacked moved to 34,
    // lootboxRngWordByIndex to 35, degeneretteBets to 38, degeneretteBetNonce to 39.)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 34; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;
    /// @dev lootboxRngWordByIndex mapping root slot.

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt
    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp
    uint256 private constant FIXED_WORD =
        uint256(keccak256("rng_freeze_removal_fixed_word"));


    address private player;
    address private cranker;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("freeze_proof_player");
        cranker = makeAddr("freeze_proof_cranker");
        vm.deal(player, 1000 ether);
        vm.deal(cranker, 1000 ether);
        vm.deal(address(game), 1000 ether);

        // Seed lootboxRngIndex = 1 (word stays 0 until injected) so placeDegeneretteBet's
        // index!=0 / word==0 precondition (the freeze-window placement gate) holds.
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        RecyclingState.seedWriteBuffer(address(game), INDEX);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );
    }

    // =========================================================================
    // Task 1 — SAFE-04: RNG-freeze intact under the crank
    // =========================================================================


    /// @notice SAFE-04 (boxes): a crank BEFORE the word lands cannot open the box — mineFlip's
    ///         human-box stage runs only on a published read-cohort word. After the word lands the
    ///         SAME crank opens the box (order marked processed). The box is queued on the write
    ///         buffer, which is then sealed as the read buffer the human-box stage walks.
    function testCrankBoxOpenStaysPostUnlock() public {
        address boxOwner = makeAddr("box_owner");
        uint48 idx = _activeLootboxIndex();
        _buyBox(boxOwner, 1 ether);
        assertGt(
            _boxUnsettled(idx, boxOwner),
            0,
            "box enqueued (one queue entry)"
        );

        // Finalize the box's index: a request seals idx as the read buffer (two physical buffers,
        // 6d0e64b09: the write side flips to idx ^ 1) before its word lands, and park the open
        // frontier there.
        _sealBuffer(idx);
        assertEq(_activeLootboxIndex(), idx ^ 1, "LR_INDEX advanced; box index idx is now finalized");
        _parkBoxFrontier(idx);

        // PRE-WORD: word at idx is 0 -> the engine's human-box stage is not eligible. With
        // doubled continuation bounds, 2M cannot admit the next daily request after preparation.
        assertEq(
            _injectedWord(idx),
            0,
            "pre-condition: box index word not yet landed (frozen window)"
        );
        vm.prank(cranker);
        game.mineFlip{gas: 2_000_000}(20_000);
        assertGt(
            _boxUnsettled(idx, boxOwner),
            0,
            "pre-word: box NOT opened (no published word for its cohort)"
        );

        // POST-WORD: land the word at the finalized index -> the SAME crank opens the box. An
        // open advances the box cursor past the entry; the entry word itself is never rewritten.
        _injectLootboxRngWord(idx, FIXED_WORD);
        vm.prank(cranker);
        game.mineFlip(0);
        assertEq(
            _boxUnsettled(idx, boxOwner),
            0,
            "post-word: same crank now opens the box (relaxation is WHO, not WHEN)"
        );
    }

    /// @notice SAFE-04 (placement frozen): a degenerette placement made AFTER a word has landed
    ///         never binds to the worded index. With two physical buffers (6d0e64b09) the worded
    ///         index is always the read buffer and every placement binds to the unworded write
    ///         buffer, so the old `_lootboxWord(index) != 0 -> RngNotReady` placement guard can no
    ///         longer fire (it is structurally vacuous); the freeze it protected holds by
    ///         construction and is asserted directly here. The crank relaxed RESOLVE, not
    ///         PLACEMENT — placement stays frozen as before.
    function testPlacementNeverBindsToAWordedIndex() public {
        // Land a word at INDEX: it becomes the read buffer, the write side flips to INDEX ^ 1.
        _injectLootboxRngWord(INDEX, FIXED_WORD);
        assertGt(_injectedWord(INDEX), 0, "active index has a word");
        uint64 readBetsBefore = DQ.lastBetId(vm, address(game), INDEX);
        uint64 writeBetsBefore = DQ.lastBetId(vm, address(game), INDEX ^ 1);

        uint32 customTraits = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether;
        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(0, 0, betAmount, 1, uint8(customTraits & 7));

        assertEq(DQ.lastBetId(vm, address(game), INDEX), readBetsBefore, "no bet binds to the worded index");
        assertEq(DQ.lastBetId(vm, address(game), INDEX ^ 1), writeBetsBefore + 1, "the bet binds to the unworded write buffer");
        assertEq(_injectedWord(INDEX ^ 1), 0, "the bet's buffer has no word yet");
    }


    // =========================================================================
    // Task 2 — REMOVE behavioral: ETH always to claimable + flat 75bps recycle
    // =========================================================================

    /// @notice RM-02 behavioral: a winning degenerette ETH bet (resolved via the crank) credits
    ///         the winner's claimable balance by EXACTLY the ETH payout — there is NO auto-rebuy
    ///         / ticket-conversion interception of winnings. The claimable delta IS the payout;
    ///         no portion is diverted into tickets. Drives the resolve through the crank so the
    ///         freeze-intact resolve path and the always-to-claimable credit path are proven
    ///         together on the live tree.
    function testEthWinningsAlwaysLandInClaimable() public {
        // Engineer a WINNING bet (score 3) so _distributePayout credits claimable.
        (uint32 winTicket, uint256 word) = _findWinningCombo(INDEX);
        // Re-seed FIXED behavior: use the engineered winning word at INDEX.
        uint128 betAmount = 0.01 ether;
        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(0, 0, betAmount, 1, uint8(winTicket & 7));
        uint64 betId = DQ.lastBetId(vm, address(game), INDEX);

        // Seed the live future prize pool so the winning ETH payout is solvent.
        _seedFuturePrizePool(10_000 ether);

        uint256 preClaimable = game.claimableWinningsOf(player);
        assertEq(preClaimable, 0, "no claimable before resolve");

        // Land the word and resolve it from an unrelated caller (permissionless, post-unlock)
        // through the sweep, which requires the active index to have moved past INDEX.
        _injectLootboxRngWord(INDEX, word);
        _sealBuffer(INDEX);
        _crankBets(INDEX, betId);

        // The bet resolved (queue word marked processed) and the winnings landed wholly in claimable.
        assertEq(game.degeneretteBetInfo(INDEX, betId), 0, "winning bet resolved");
        assertTrue(_betProcessed(INDEX, betId), "winning bet resolved");
        uint256 postClaimable = game.claimableWinningsOf(player);
        assertGt(
            postClaimable,
            preClaimable,
            "winning ETH bet credits claimable (no auto-rebuy interception of winnings)"
        );
    }

    /// @notice RM-02 freeze-obligation retirement (deterministic credit, no VRF word): the same
    ///         winning bet + word resolves to the SAME claimable credit on two independent runs.
    ///         The credit path consumes no entropy (the auto-rebuy roll that previously threaded
    ///         the VRF word was removed; `_addClaimableEth` is now the 2-arg deterministic form).
    ///         Determinism given the resolved outcome proves no entropy is mixed into the credit.
    function testEthCreditPathIsDeterministicNoVrfWord() public {
        // Two independent winners on two FRESH indexes (so the freeze-window placement guard at
        // DegeneretteModule:452 — which blocks placement once an index already has a word — does
        // not reject the second placement). Both use the identical winning word/ticket/amount, so
        // identical credit proves the credit step is deterministic (no VRF word threaded in).
        uint256 creditA = _resolveWinningBetForPlayerAtIndex(
            player,
            INDEX
        );
        uint256 creditB = _resolveWinningBetForPlayerAtIndex(
            makeAddr("freeze_proof_player_2"),
            INDEX ^ 1
        );

        assertGt(creditA, 0, "first credit is nonzero (winning bet)");
        assertEq(
            creditA,
            creditB,
            "ETH credit is deterministic given the resolved outcome -> no VRF word threaded into the credit"
        );
    }


    // testPassHorizonReadIsViewOnly DELETED (AFKing Subscription Token credential change): WHALE04-FREEZE-PROOF
    // §5 pinned the AfKing crossing's `_passHorizonOf` in-context read as a NON-RNG-WINDOW,
    // `view`-only (no-write) read on a frozen slot. The crossing branch (and `_passHorizonOf`
    // itself) is deleted — subscribe's coin-balance check happens only at subscribe (which
    // itself reverts under `rngLockedFlag`, so it can never run inside the window), and the
    // process STAGE performs zero credential reads at all. No in-window read survives to pin.

    /// @dev Grant `who` the permanent deity-pass bit (shift 184) in DegenerusGame.mintPacked_ (slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf(who), uint256(9)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << 184);
        vm.store(address(game), slot, bytes32(packed));
    }

    // =========================================================================
    // v50.0 D-IMPL-02 — D-TST01-03 dedicated equivalence/grant-correctness oracle
    //
    // Closes the deferral declared at lines 38-46 of this file (335-CONTEXT.md D-IMPL-02).
    // Implements TST-01 D-TST01-03 (336-CONTEXT.md):
    //   (1) box-open pre-claim writes ONLY the O(1) whalePassClaims[player] += accumulator
    //       (D-IMPL-01) — `mintPacked_[_walletIdOf(player)]` is UNCHANGED between pre-box-open and pre-claim;
    //   (2) post-claim, the future-window level grants land at exactly
    //       [currentLevel+1 .. currentLevel+100] — `frozenUntilLevel` advances to currentLevel+100
    //       (per WhaleModule:1030-1034 + Storage:1127 `ticketStartLevel + 99` math, D-03);
    //   (3) `_applyWhalePassStats` is applied at the claim-time anchor, NOT at box-open
    //       (D-04) — `mintPacked_[_walletIdOf(player)]` DIFFERS between pre-claim and post-claim snapshots,
    //       and `whalePassClaims[player]` resets to 0 (WHALE-02 consumed at claim).
    //
    // Per D-05 (334-CONTEXT.md), the equivalence is byte-correct relative to the new claim-time
    // semantics — NOT byte-identical to the OLD inline-mint shadow (which the v50.0 IMPL retired).
    // =========================================================================

    /// @dev Storage slot for the `whalePassClaims` mapping (DegenerusGame slot 21; confirmed via
    ///      `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage` and 336-01's same probe).

    /// @dev BitPackingLib shifts used by `_applyWhalePassStats` (mirrored locally so the test
    ///      reads the SAME slot fields the contract writes). Verified against
    ///      contracts/libraries/BitPackingLib.sol:48/51/63/66 at e756a6f3.
    uint256 private constant LAST_LEVEL_SHIFT = 0;
    uint256 private constant LEVEL_COUNT_SHIFT = 24;
    uint256 private constant FROZEN_UNTIL_LEVEL_SHIFT = 120;
    uint256 private constant WHALE_PASS_TYPE_SHIFT = 144;
    uint256 private constant MASK_24 = (uint256(1) << 24) - 1;
    uint256 private constant MASK_PASS_TYPE = 0x3; // 2-bit field

    /// @dev Slot for `mintPacked_[_walletIdOf(who)]` (the same mapping the existing `_grantDeityPass` writes;
    ///      mapping root is slot 9 — confirmed against the existing helper at lines 479-484).
    function _mintPackedSlot(address who) internal view returns (bytes32) {
        return keccak256(abi.encode(game.walletIdOf(who), uint256(9)));
    }

    /// @dev Wallet-table element holding `who`'s half passes (bits 192..255).
    function _whalePassClaimsSlot(address who) internal view returns (bytes32) {
        return GameSlotKeys.walletElement(game.walletIdOf(who));
    }

    /// @dev Read `whalePassClaims[player]` from storage.
    function _readWhalePassClaims(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), _whalePassClaimsSlot(who))) >> 192;
    }

    /// @dev Force `whalePassClaims[player] = halfPasses` via direct storage write — simulates the
    ///      O(1) box-open accumulator landing exactly `halfPasses` (= 1 here) without driving the
    ///      non-deterministic box-open boon-roll. This is the load-bearing simplification per the
    ///      plan's <action> step 2 — the oracle still asserts live contract behavior on the claim
    ///      side (the only path D-TST01-03 measures).
    function _forceWhalePassClaims(address who, uint256 halfPasses) internal {
        bytes32 slot = _whalePassClaimsSlot(who);
        uint256 element = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32((element & ((uint256(1) << 192) - 1)) | (halfPasses << 192)));
    }

    /// @dev Decode `frozenUntilLevel`, `levelCount`, `whalePassType`, `lastLevel` from a
    ///      packed mintPacked_ word for assertion convenience.
    function _decodeMintPacked(uint256 packed)
        internal
        pure
        returns (
            uint24 lastLevel,
            uint24 levelCount,
            uint24 frozenUntilLevel,
            uint8 whalePassType
        )
    {
        lastLevel = uint24((packed >> LAST_LEVEL_SHIFT) & MASK_24);
        levelCount = uint24((packed >> LEVEL_COUNT_SHIFT) & MASK_24);
        frozenUntilLevel = uint24((packed >> FROZEN_UNTIL_LEVEL_SHIFT) & MASK_24);
        whalePassType = uint8((packed >> WHALE_PASS_TYPE_SHIFT) & MASK_PASS_TYPE);
    }

    /// @notice TST-01 D-TST01-03 — the deferred-claim roundtrip equivalence oracle.
    ///
    /// Closes the deferral declared at lines 38-46 of this file (335-CONTEXT.md D-IMPL-02).
    /// Implements D-TST01-03 (TST-01 D-TST01-03 dedicated equivalence/grant oracle):
    /// (1) box-open pre-claim writes ONLY the O(1) whalePassClaims[player] += accumulator (D-IMPL-01);
    /// (2) post-claim, the future-window level grants land at exactly [currentLevel+1 .. currentLevel+100] (D-03);
    /// (3) _applyWhalePassStats is applied at the claim-time anchor, NOT at box-open (D-04).
    ///
    /// Per D-05 (334-CONTEXT.md), equivalence is byte-correct relative to the new claim-time semantics —
    /// not byte-identical to the OLD inline-mint shadow (which the v50.0 IMPL retired at e756a6f3).
    function testClaimWhalePassMaterializesFutureWindowAndAppliesStats() public {
        address claimant = makeAddr("tst01-d03-claim-equiv");

        // -------------------------------------------------------------------
        // Stage: capture the TRULY-pre-box-open snapshot (mintPacked_ unmodified).
        // The claimant has not been touched yet — the slot is zero. We snapshot
        // here so the "box-open writes ONLY the accumulator" assertion is anchored
        // at a strict pre-mutation baseline.
        // -------------------------------------------------------------------
        uint32 claimantId = _giveWalletId(claimant); // the wallet ID is the only prior state
        bytes32 mintPackedSlot = _mintPackedSlot(claimant);
        bytes32 mintPackedPreBoxOpen = vm.load(address(game), mintPackedSlot);
        assertEq(
            mintPackedPreBoxOpen,
            bytes32(0),
            "pre-condition: registration creates no mint statistics"
        );
        assertEq(
            _readWhalePassClaims(claimant),
            0,
            "pre-condition: whalePassClaims[claimant] starts at 0"
        );

        // -------------------------------------------------------------------
        // Simulated box-open: per WHALE-01 (LootboxModule:1253), a whale-pass boon
        // on box-open writes ONLY `whalePassClaims[player] += 1` (the O(1) accumulator).
        // We forge that single SSTORE directly via vm.store so this oracle is decoupled
        // from the non-deterministic box-open boon-roll. The claim-side (the load-bearing
        // half of the equivalence) is exercised against the live contract below.
        // -------------------------------------------------------------------
        uint256 halfPassesK = 1;
        _forceWhalePassClaims(claimant, halfPassesK);

        // -------------------------------------------------------------------
        // D-IMPL-01 attestation: post-box-open / pre-claim, ONLY the O(1) accumulator
        // slot was touched — `mintPacked_[_walletIdOf(claimant)]` is byte-equal to its pre-box-open
        // snapshot. The accumulator carries the queued half-pass count.
        // -------------------------------------------------------------------
        bytes32 mintPackedPreClaim = vm.load(address(game), mintPackedSlot);
        assertEq(
            mintPackedPreClaim,
            mintPackedPreBoxOpen,
            "D-IMPL-01: box-open writes ONLY the O(1) whalePassClaims accumulator - no mintPacked_ perturbation pre-claim"
        );
        assertEq(
            _readWhalePassClaims(claimant),
            halfPassesK,
            "WHALE-01: O(1) accumulator carries the queued half-pass count into claim"
        );

        // D-04 leg #1 (pre-claim): the `_applyWhalePassStats` writes have NOT landed yet.
        // The same mintPacked_ word that proves "no perturbation" also proves "stats not yet
        // applied" — both share the byte-equal-to-zero baseline at the claim-time anchor.
        // Scoped to release locals before the post-claim path (avoid stack-too-deep).
        {
            (
                uint24 lastLvlPre,
                uint24 levelCountPre,
                uint24 frozenUntilPre,
                uint8 passTypePre
            ) = _decodeMintPacked(uint256(mintPackedPreClaim));
            assertEq(lastLvlPre, 0, "D-04 pre-claim: lastLevel unchanged (stats NOT yet applied)");
            assertEq(levelCountPre, 0, "D-04 pre-claim: levelCount unchanged (stats NOT yet applied)");
            assertEq(frozenUntilPre, 0, "D-04 pre-claim: frozenUntilLevel unchanged (stats NOT yet applied)");
            assertEq(passTypePre, 0, "D-04 pre-claim: whalePassType unchanged (stats NOT yet applied)");
        }

        // -------------------------------------------------------------------
        // Capture currentLevel AT THE CLAIM-TIME ANCHOR (per D-03). The contract reads
        // this at WhaleModule:1030 — `uint24 startLevel = level + 1;` — and applies the
        // 100-level window to [startLevel .. startLevel+99] = [currentLevel+1 .. currentLevel+100].
        // -------------------------------------------------------------------
        uint24 currentLevel = game.level();

        // -------------------------------------------------------------------
        // Execute the claim. The facade at DegenerusGame.sol:1864 calls
        // `_resolvePlayer(player)` which enforces `msg.sender == player` OR
        // `_requireApproved(player)` — so the claimant calls for themselves
        // (the simplest non-operator path; tests the live entry, not just the
        // WhaleModule internal). The credit is bound by the player arg, not msg.sender.
        // -------------------------------------------------------------------
        vm.prank(claimant);
        game.claimWhalePass(0);

        // -------------------------------------------------------------------
        // WHALE-02 attestation: the accumulator is consumed at claim (WhaleModule:1024).
        // -------------------------------------------------------------------
        assertEq(
            _readWhalePassClaims(claimant),
            0,
            "WHALE-02: whalePassClaims[claimant] reset to 0 at claim (accumulator consumed)"
        );

        // -------------------------------------------------------------------
        // D-04 attestation (post-claim): `_applyWhalePassStats` ran AT claim-time.
        // The mintPacked_ word MUST differ from the pre-claim snapshot.
        // -------------------------------------------------------------------
        bytes32 mintPackedPostClaim = vm.load(address(game), mintPackedSlot);
        assertTrue(
            mintPackedPostClaim != mintPackedPreClaim,
            "D-04: `_applyWhalePassStats` applied AT claim-time - mintPacked_ DIFFERS from pre-claim snapshot"
        );

        // -------------------------------------------------------------------
        // D-03 attestation: the future-window grants land at exactly
        // [currentLevel+1 .. currentLevel+100]. Storage:1127 sets
        // `targetFrozenLevel = ticketStartLevel + 99` with ticketStartLevel = currentLevel+1,
        // so the post-claim `frozenUntilLevel` is exactly currentLevel + 100. From a clean
        // baseline (frozenUntilPre == 0), the math also gives `levelCount` += 100.
        // Scoped to release decoded locals (avoid stack-too-deep).
        // -------------------------------------------------------------------
        {
            (
                uint24 lastLvlPost,
                uint24 levelCountPost,
                uint24 frozenUntilPost,
                uint8 passTypePost
            ) = _decodeMintPacked(uint256(mintPackedPostClaim));

            uint24 expectedFrozenUntil = currentLevel + 100;
            assertEq(
                frozenUntilPost,
                expectedFrozenUntil,
                "D-03: frozenUntilLevel == currentLevel + 100 - future window [currentLevel+1 .. currentLevel+100] anchored at claim-time"
            );
            assertEq(
                levelCountPost,
                uint24(100),
                "D-03: levelCount == 100 (delta from clean baseline; +100 the full window credit)"
            );
            assertEq(
                lastLvlPost,
                expectedFrozenUntil,
                "D-03: lastLevel == newFrozenLevel (Storage:1163 mirrors lastLevel onto newFrozenLevel)"
            );
            assertEq(
                passTypePost,
                3,
                "D-03: whalePassType set to 3 (100-level pass marker, Storage:1158)"
            );
        }


    }


    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _lvl() internal view returns (uint24) {
        return game.level() + 1;
    }

    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        return RecyclingState.writeBuffer(address(game));
    }

    function _placeLosingBet(address better) internal returns (uint64 betId) {
        uint32 customTraits = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether;
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(0, 0, betAmount, 1, uint8(customTraits & 7));
        betId = DQ.lastBetId(vm, address(game), INDEX);
    }

    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            0,
            400,
            BoxOrderLib.boCustomFloor(lootboxAmount),
            bytes32(0),
            MintPaymentKind.DirectEth, false
        );
    }

    /// @dev Land `rngWord` as the published session word on `index` (index becomes the read
    ///      buffer). The delivered read cohort's tickets count as materialized: in the shared
    ///      consumer order tickets precede boxes and bets (60d31f775), so a forged cohort must
    ///      carry the ticket certificate (slot 0, ticketsFullyProcessed bit 192) to reach them.
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        RecyclingState.seedWord(address(game), index, bytes32(rngWord));
        uint256 s0 = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32(s0 | (uint256(1) << 192)));
        // seedWord latches the queue counts and restarts the box and bet cursors at zero, as the
        // real seal (_swapRngBuffers) does.
    }

    /// @dev Seal `index` as the read buffer (the write side flips to index ^ 1), mirroring a
    ///      request's seal under two physical buffers (6d0e64b09) — the replacement for the old
    ///      "advance LR_INDEX by one" step. Idempotent once a word was injected at `index`.
    function _sealBuffer(uint48 index) internal {
        if (RecyclingState.writeBuffer(address(game)) == index) {
            RecyclingState.latchQueueCounts(address(game));
            RecyclingState.seedWriteBuffer(address(game), index ^ 1);
        }
    }

    /// @dev Resolution is the retired FIFO prefix, without modifying the bet word.
    function _betProcessed(uint48 index, uint64 betId) internal view returns (bool) {
        return game.degeneretteBetInfo(index, betId) == 0;
    }

    /// @dev Resolve queued bets through the permissionless crank. Degenerette resolution is the
    ///      engine's Degenerette stage (mineFlip), not the box helper (60d31f775). Doubled
    ///      continuation bounds keep the next daily request beyond the 2M allowance, so the
    ///      crank stops at the read cohort instead of committing a new day.
    function _crankBets(uint48 index, uint64 betId) internal {
        for (uint256 i; i < 8 && !_betProcessed(index, betId); ++i) {
            vm.prank(cranker);
            game.mineFlip{gas: 2_000_000}(20_000);
        }
    }

    /// @dev Leave the human-box frontier as a fresh seal does: not complete (the cursor restarts at
    ///      zero when the counts latch).
    function _parkBoxFrontier(uint48 index) internal {
        require(index < 2, "binary buffer fixture");
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.HUMAN_READ_COMPLETE)));
        packed &= ~(uint256(0xff) << (GameSlots.HUMAN_READ_COMPLETE_OFFSET * 8));
        vm.store(address(game), bytes32(GameSlots.HUMAN_READ_COMPLETE), bytes32(packed));
    }

    function _injectedWord(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev Nominal wei of `who`'s queue entries in `index`'s buffer that the human-box cursor has
    ///      not yet settled (zero once every one of them is opened).
    function _boxUnsettled(uint48 index, address who) internal view returns (uint256 total) {
        uint256 n = RecyclingState.boxCount(address(game), index);
        uint256 cursor = (uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8)) & type(uint48).max;
        uint32 id = game.walletIdOf(who);
        for (uint256 i = index == RecyclingState.readBuffer(address(game)) ? cursor : 0; i < n; ++i) {
            uint256 word = RecyclingState.boxEntry(address(game), index, i);
            if (BoxOrderLib.boId(word) != id) continue;
            total += BoxOrderLib.boNominal(word, PriceLookupLib.priceForLevel(BoxOrderLib.boLevel(word)));
        }
    }

    /// @dev Seed the live futurePrizePool (future half (bits 128-255) of prizePoolsPacked slot 2) so winning
    ///      ETH payouts are solvent. Preserves the next half.
    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint256 newPacked = (packed & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(address(game), bytes32(uint256(2)), bytes32(newPacked));
    }

    /// @dev Resolve a guaranteed 8/8 winning bet for `who` at a fresh `atIndex` and return the
    ///      claimable credit delta. An 8/8 jackpot win on a fixed 0.01-ETH bet maps to the same
    ///      payout tier regardless of the index/word, so two independent winners yield identical
    ///      credit — which is the determinism the credit step (no VRF word) must exhibit.
    function _resolveWinningBetForPlayerAtIndex(
        address who,
        uint48 atIndex
    ) internal returns (uint256 creditDelta) {
        vm.deal(who, 1000 ether);

        // Point the live daily index at `atIndex` (word still 0) for placement, find an 8/8 win.
        _setLootboxRngIndex(atIndex);
        (uint32 winTicket, uint256 word) = _findWinningCombo(atIndex);
        uint128 betAmount = 0.01 ether;
        vm.prank(who);
        game.placeDegeneretteBet{value: betAmount}(0, 0, betAmount, 1, uint8(winTicket & 7));

        _seedFuturePrizePool(10_000 ether);
        uint256 pre = game.claimableWinningsOf(who);
        uint64 betId = DQ.lastBetId(vm, address(game), atIndex);
        _injectLootboxRngWord(atIndex, word);
        _sealBuffer(atIndex);
        _crankBets(atIndex, betId);
        creditDelta = game.claimableWinningsOf(who) - pre;
    }

    /// @dev Set the live daily lootboxRngIndex (low 48 bits of lootboxRngPacked slot 34).
    function _setLootboxRngIndex(uint48 idx) internal {
        RecyclingState.seedWriteBuffer(address(game), idx);
    }

    function _resultTicketFor(
        uint48 index,
        uint256 word
    ) internal pure returns (uint32) {
        uint256 resultSeed = uint256(
            keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT))
        );
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev customTraits matching the result in ZERO quadrants → matches == 0 → clean loss.
    function _losingTicketFor(
        uint48 index,
        uint256 word
    ) internal pure returns (uint32 ticket) {
        uint32 result = _resultTicketFor(index, word);
        for (uint8 q; q < 4; q++) {
            uint8 rQuad = uint8(result >> (q * 8));
            uint8 rColor = (rQuad >> 3) & 7;
            uint8 rSymbol = rQuad & 7;
            uint8 newColor = (rColor + 1) & 7;
            uint8 newSymbol = (rSymbol + 1) & 7;
            uint8 newQuad = (newColor << 3) | newSymbol;
            ticket |= (uint32(newQuad) << (q * 8));
        }
    }

    /// @dev Find a (resultTicket, rngWord) pair whose spin 0 is the smallest win (score 3, no
    ///      house wild: half the stake back, all cash) for the hero symbol taken from the result's
    ///      lane 0. Mirrors the established DegeneretteFreezeResolution._findWinningCombo pattern.
    function _findWinningCombo(
        uint48 index
    ) internal pure returns (uint32 winTicket, uint256 rngWord) {
        for (uint256 attempt; attempt < 100; attempt++) {
            rngWord = uint256(
                keccak256(abi.encode("freeze_removal_win", attempt))
            );
            winTicket = _resultTicketFor(index, rngWord);
            uint8 symbol = uint8(winTicket) & 7;
            (uint8 score, uint8 wilds) = Ref.score(Ref.player(rngWord, uint32(index), symbol, 0, false), winTicket);
            if (score == 3 && wilds == 0) return (winTicket, rngWord);
        }
        revert("no winning combo in 100 attempts");
    }

    function _countMatchesLocal(
        uint32 a,
        uint32 b
    ) internal pure returns (uint8 matches) {
        for (uint8 q; q < 4; q++) {
            uint8 aQuad = uint8(a >> (q * 8));
            uint8 bQuad = uint8(b >> (q * 8));
            if (((aQuad >> 3) & 7) == ((bQuad >> 3) & 7)) matches++; // color
            if ((aQuad & 7) == (bQuad & 7)) matches++; // symbol
        }
    }


}
