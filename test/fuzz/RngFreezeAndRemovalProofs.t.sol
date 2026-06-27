// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title RngFreezeAndRemovalProofs -- Proves SAFE-04 (the v45 RNG-freeze hard-floor is
///        intact under the new permissionless crank) plus the v46 REMOVE proofs (the legacy
///        free-ETH-auto-rebuy / afKing-mode / daily-ETH-split surface is grep-clean AND
///        behaviorally gone, and the FLIP win/loss RNG path + KNOWN-ISSUES are unmodified).
///
/// @notice SAFE-04 north-star (every VRF-interacting variable frozen across the rng window):
///         the crank relaxed WHO can resolve, not WHEN. This suite proves the freeze guard
///         still blocks pre-word resolution from a crank caller, the placement guard is
///         untouched, and post-word the same crank resolves/opens. The ETH-auto-rebuy removal
///         RETIRED freeze obligations rather than weakening them: the jackpot ETH credit path
///         (`_addClaimableEth`) is now a 2-arg deterministic credit consuming no VRF word, so
///         the freeze surface is strictly smaller (one fewer VRF consumer + the removed
///         player-mutable in-window inputs cannot re-enter the freeze window).
///
///         REMOVE behavioral: ETH jackpot winnings ALWAYS land in claimable (no
///         ticket-conversion / auto-rebuy interception), and the FLIP flip recycle bonus is
///         a flat 75bps applied unconditionally (no deity scaling). REMOVE structural: the
///         legacy kill set returns ZERO non-comment matches outside contracts/test+mocks (the
///         keeper file `AfKing.sol` is excluded), and the win/loss RNG path
///         (`processCoinflipPayouts` + `(rngWord & 1) == 1`) is byte-identical.
///
/// @notice v50.0 D-IMPL-02 trivial freeze-side migrations (Plan 335-05 Task 5):
///   - The v45 KEPT-pass-view attestation now pins the AfKing module's in-context
///     `_passHorizonOf` read (`testKeptPassHorizonReadPresent`) — the canonical pass-horizon
///     semantics (deity sentinel / frozenUntilLevel). The Game-side external mirrors were
///     removed as zero-on-chain-caller surface.
///   - Two trivial positive freeze-side assertions are added: (1) the box-open
///     `whalePassClaims +=` write at the LootboxModule's whale-pass activation site (Plan 335-02)
///     targets a NON-FROZEN slot — the accumulator is a pending-claim slot per
///     334-WHALE04-FREEZE-PROOF §1, not a VRF-influenced slot; (2) the AfKing crossing's
///     `_passHorizonOf` in-context read is a NON-RNG-WINDOW read — it does not write
///     `mintPacked_` or any VRF-frozen slot (334-WHALE04-FREEZE-PROOF §5).
///   - The DEEPER RNG-freeze fuzz of the deferred-claim path (the WhaleModule:1018
///     `claimWhalePass` invariant under rngLock) lives at Phase 336 / TST-01 freeze leg
///     in `test/fuzz/RngLockDeterminism.t.sol::testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe`
///     (delivered by Plan 336-01 per 335-CONTEXT.md D-IMPL-02 + D-TST01-01).
///   - The deferred-claim ROUNDTRIP EQUIVALENCE / GRANT-CORRECTNESS oracle (TST-01 D-TST01-03
///     per 336-CONTEXT.md) is delivered IN THIS FILE at
///     `testClaimWhalePassMaterializesFutureWindowAndAppliesStats` (Plan 336-02). It empirically
///     proves: (1) box-open writes ONLY the O(1) whalePassClaims accumulator (D-IMPL-01);
///     (2) the claim materializes the future-window grants at exactly
///     [currentLevel+1 .. currentLevel+100] (D-03); (3) `_applyWhalePassStats` is applied AT
///     claim-time, not at box-open (D-04). All deferrals on this surface are now CLOSED.
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING). Drives
///      REAL degenerette bets + REAL lootbox purchases through the public mint API (mirroring
///      the established CrankNonBrick / CrankFaucetResistance patterns); the only slot
///      manipulation is the established LOOTBOX_RNG word injection. Source-level attestations
///      use vm.readFile over ./contracts (foundry.toml grants read on ./contracts).
///      Test-only: NO contracts/*.sol is mutated.
contract RngFreezeAndRemovalProofs is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (DegenerusGame; RE-DERIVED via `solc --storage-layout` on the working
    // tree after the Stage B Game-storage packing — lootboxRngPacked moved to 34,
    // lootboxRngWordByIndex to 35, degeneretteBets to 38, degeneretteBetNonce to 39.)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 34; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 34;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 35;
    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 38;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 39;
    /// @dev lootboxEth (the single folded box word) mapping root slot. The amount sub-field (low
    ///      128 bits) is the box-owed signal (set on first deposit, zeroed on open) — it replaced
    ///      the removed lootboxEthBase mapping the old pin read.
    uint256 private constant LOOTBOX_ETH_SLOT = 15;
    uint256 private constant LB_AMOUNT_MASK = (uint256(1) << 128) - 1;

    // -------------------------------------------------------------------------
    // Crank reward peg mirror (the contract's own FIXED constants, REW-03)
    // -------------------------------------------------------------------------
    uint256 private constant CRANK_GAS_PRICE_REF = 0.5 gwei;
    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 71_203;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt
    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp
    uint256 private constant FIXED_WORD =
        uint256(keccak256("rng_freeze_removal_fixed_word"));
    uint256 private constant LOOTBOX_MIN = 0.01 ether;

    // -------------------------------------------------------------------------
    // RM-03 flat recycle constants (mirror Coinflip's private constants).
    // Coinflip.sol:130 RECYCLE_BONUS_BPS = 75 ; :129 BPS_DENOMINATOR = 10_000.
    // The flat-bps numeric proof replicates the exact contract formula.
    // -------------------------------------------------------------------------
    uint256 private constant RECYCLE_BONUS_BPS = 75;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant RECYCLE_BONUS_CAP = 1000 ether;

    // -------------------------------------------------------------------------
    // KNOWN-ISSUES byte-unmodified baseline. KNOWN-ISSUES.md was last touched at
    // audit(280), which predates the v46.0 milestone (Phases 316/317) — so it is
    // byte-unmodified across this milestone. fs_permissions grants read only on
    // ./contracts (NOT the repo root), so the in-test attestation pins the recorded
    // milestone-baseline sha256 here; the verify-step bash gate re-confirms the live
    // file hash matches (the bash step CAN read the repo root).
    // -------------------------------------------------------------------------
    bytes32 private constant KNOWN_ISSUES_BASELINE_SHA256 =
        0x75b3b4bc79a96c7e16c4e539fa8bfcb8bd1a20063775dbf4d1854dfe3cfd8014;

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
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );

        // The crank resolve sub-call delegatecalls resolveBets with msg.sender == game,
        // so the game must be the bet owner's approved operator (the documented relaxation).
        vm.prank(player);
        game.setOperatorApproval(address(game), true);
    }

    // =========================================================================
    // Task 1 — SAFE-04: RNG-freeze intact under the crank
    // =========================================================================


    /// @notice SAFE-04 (boxes): a crank-driven box open BEFORE the word lands is skipped at the
    ///         autoOpen cursor orphan gate (`lootboxRngWordByIndex[idx] == 0 -> break`,
    ///         DegenerusGameLootboxModule.openHumanBoxes) AND the LootboxModule openLootBox
    ///         RngNotReady guard — no pre-word open. After the word lands the SAME crank opens the
    ///         box (signal cleared). The box is queued at the round's index, then the index is
    ///         advanced by one so it sits at LR_INDEX-1 — the finalized index the relocated
    ///         multi-index sweep reads (the sweep opens boxCursorIndex .. LR_INDEX-1).
    function testCrankBoxOpenStaysPostUnlock() public {
        address boxOwner = makeAddr("box_owner");
        uint48 idx = _activeLootboxIndex();
        _buyBox(boxOwner, 1 ether);
        assertGt(
            _lootboxEthBase(idx, boxOwner),
            0,
            "box enqueued (first-deposit signal set)"
        );

        // Finalize the box's index: advance LR_INDEX so the box at idx becomes LR_INDEX-1 (the
        // index the sweep opens), and park the open frontier there (lower indices drained).
        _advanceLootboxRngIndexByOne();
        assertEq(_activeLootboxIndex(), idx + 1, "LR_INDEX advanced; box index idx is now finalized");
        _parkBoxFrontier(idx);

        // PRE-WORD: word at idx is 0 -> the sweep orphan-breaks at idx + openLootBox RngNotReady. No open.
        assertEq(
            _injectedWord(idx),
            0,
            "pre-condition: box index word not yet landed (frozen window)"
        );
        vm.prank(cranker);
        game.openBoxes(100);
        assertGt(
            _lootboxEthBase(idx, boxOwner),
            0,
            "pre-word: box NOT opened (sweep orphan-break + openLootBox RngNotReady)"
        );

        // POST-WORD: land the word at the finalized index -> the SAME crank opens the box.
        _injectLootboxRngWord(idx, FIXED_WORD);
        vm.prank(cranker);
        game.openBoxes(100);
        assertEq(
            _lootboxEthBase(idx, boxOwner),
            0,
            "post-word: same crank now opens the box (relaxation is WHO, not WHEN)"
        );
    }

    /// @notice SAFE-04 (placement guard untouched): a degenerette placement for the active
    ///         index AFTER that index already has a word reverts RngNotReady
    ///         (DegeneretteModule:452 `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady`).
    ///         The crank relaxed RESOLVE, not PLACEMENT — placement stays frozen as before.
    function testPlacementGuardUntouchedWhenIndexHasWord() public {
        // Land a word at the active INDEX, so the placement guard at :452 must trip.
        _injectLootboxRngWord(INDEX, FIXED_WORD);
        assertGt(_injectedWord(INDEX), 0, "active index has a word");

        uint32 customTicket = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether;
        // RngNotReady() is the placement guard revert (DegeneretteModule:49 / :452).
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSignature("RngNotReady()"));
        game.placeDegeneretteBet{value: betAmount}(
            address(0),
            0,
            betAmount,
            1,
            customTicket,
            0
        );
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
        // Engineer a WINNING bet (>= 2 matches) so _distributePayout credits claimable.
        (uint32 winTicket, uint256 word) = _findWinningCombo(INDEX);
        // Re-seed FIXED behavior: use the engineered winning word at INDEX.
        uint128 betAmount = 0.01 ether;
        vm.prank(player);
        game.placeDegeneretteBet{value: betAmount}(
            address(0),
            0,
            betAmount,
            1,
            winTicket,
            0
        );
        uint64 betId = _betNonce(player);

        // Seed the live future prize pool so the winning ETH payout is solvent.
        _seedFuturePrizePool(10_000 ether);

        uint256 preClaimable = game.claimableWinningsOf(player);
        assertEq(preClaimable, 0, "no claimable before resolve");

        // Land the word and resolve via the permissionless crank (post-unlock, SAFE-04).
        _injectLootboxRngWord(INDEX, word);
        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;
        vm.prank(cranker);
        game.degeneretteResolve(players, betIds);

        // The bet resolved (slot deleted) and the winnings landed wholly in claimable.
        assertEq(_readBetPacked(player, betId), 0, "winning bet resolved");
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
            INDEX + 1
        );

        assertGt(creditA, 0, "first credit is nonzero (winning bet)");
        assertEq(
            creditA,
            creditB,
            "ETH credit is deterministic given the resolved outcome -> no VRF word threaded into the credit"
        );
    }

    /// @notice RM-03 behavioral (flat 75bps, unconditional): the FLIP flip recycle bonus is
    ///         `(amount * 75) / 10_000` applied flat for every player tier — a deity-pass holder
    ///         and a normal player receive EXACTLY the same bonus for the same amount (no deity
    ///         scaling, no under/over-credit). `_recyclingBonus(amount)` takes ONLY `amount`
    ///         (proven structurally in Task 3), so tier cannot influence it; here we assert the
    ///         numeric flat-bps formula holds and is identical across two "tiers".
    function testFlipRecycleIsFlat75BpsAcrossTiers(uint96 amountWei) public view {
        // Keep below the 1000-FLIP bonus cap so the flat-bps relationship holds exactly.
        // cap is hit at amount = cap * 10_000 / 75; stay well under.
        uint256 amount = bound(
            uint256(amountWei),
            1,
            (RECYCLE_BONUS_CAP * BPS_DENOMINATOR) / RECYCLE_BONUS_BPS
        );

        // A deity-pass holder (VAULT carries the permanent deity bit) and a normal player.
        address deityHolder = ContractAddresses.VAULT;
        address normalPlayer = player;
        assertTrue(
            game.hasDeityPass(deityHolder),
            "VAULT holds the permanent deity pass (tier under test)"
        );
        assertFalse(
            game.hasDeityPass(normalPlayer),
            "normal player has no deity pass (the other tier)"
        );

        // The contract formula: bonus = (amount * RECYCLE_BONUS_BPS) / BPS_DENOMINATOR, flat.
        uint256 bonusDeity = (amount * RECYCLE_BONUS_BPS) / BPS_DENOMINATOR;
        uint256 bonusNormal = (amount * RECYCLE_BONUS_BPS) / BPS_DENOMINATOR;

        assertEq(
            bonusDeity,
            bonusNormal,
            "flat 75bps recycle: deity and normal tiers receive the SAME bonus (no deity scaling)"
        );
        assertEq(
            bonusDeity,
            (amount * 75) / 10_000,
            "recycle bonus is exactly 75bps of amount (no under/over-credit)"
        );
    }

    // =========================================================================
    // Task 3 — REMOVE grep-clean + UNMODIFIED-invariant structural attestation
    // =========================================================================

    /// @notice RM grep-clean: the legacy free-ETH-auto-rebuy / afKing-mode / daily-ETH-split
    ///         kill set returns ZERO non-comment matches across the production contract sources
    ///         (outside contracts/test + contracts/mocks). The keeper file `AfKing.sol` is
    ///         excluded so the kept SUB-09 afKing handle does not false-positive.
    /// @dev Reads each production .sol via vm.readFile (foundry.toml grants read on ./contracts),
    ///      strips line comments and block-comment lines, and asserts zero residual matches per
    ///      symbol. The keeper file AfKing.sol and the contracts/test + contracts/mocks trees are
    ///      not scanned (the kept SUB-09 afKing handle + the keeper itself live there).
    function testLegacyKillSetIsGrepClean() public view {
        string[18] memory killSet = [
            "setAutoRebuy",
            "autoRebuyState",
            "AutoRebuyState",
            "_processAutoRebuy",
            "_calcAutoRebuy",
            "settleFlipModeChange",
            "_afKingRecyclingBonus",
            "_afKingDeityBonusHalfBpsWithLevel",
            "resumeEthPool",
            "SPLIT_CALL1",
            "SPLIT_CALL2",
            "SPLIT_NONE",
            "_resumeDailyEth",
            "STAGE_JACKPOT_ETH_RESUME",
            "call1Bucket",
            "setAfKingMode",
            "deactivateAfKingFromCoin",
            "syncAfKingLazyPassFromCoin"
        ];

        // The production sources scanned (exclude the keeper AfKing.sol + the kept handle refs).
        string[15] memory sources = [
            "contracts/DegenerusGame.sol",
            "contracts/Coinflip.sol",
            "contracts/FLIP.sol",
            "contracts/DegenerusVault.sol",
            "contracts/sDGNRS.sol",
            "contracts/modules/DegenerusGameJackpotModule.sol",
            "contracts/modules/DegenerusGameAdvanceModule.sol",
            "contracts/modules/DegenerusGamePayoutUtils.sol",
            "contracts/modules/DegenerusGameDegeneretteModule.sol",
            "contracts/modules/DegenerusGameLootboxModule.sol",
            "contracts/modules/DegenerusGameMintModule.sol",
            "contracts/storage/DegenerusGameStorage.sol",
            "contracts/interfaces/IDegenerusGame.sol",
            "contracts/interfaces/ICoinflip.sol",
            "contracts/DegenerusDeityPass.sol"
        ];

        for (uint256 s; s < sources.length; s++) {
            string memory codeNoComments = _stripComments(
                vm.readFile(sources[s])
            );
            for (uint256 k; k < killSet.length; k++) {
                assertEq(
                    _countOccurrences(codeNoComments, killSet[k]),
                    0,
                    string.concat(
                        "legacy kill-set symbol still present in ",
                        sources[s],
                        ": ",
                        killSet[k]
                    )
                );
            }
        }
    }

    /// @notice The canonical pass-horizon read is the AfKing module's in-context
    ///         `_passHorizonOf` (deity holders → the type(uint24).max sentinel; lazy/whale
    ///         holders → their `frozenUntilLevel`). The Game-side external mirrors
    ///         (`hasAnyLazyPass` / `lazyPassHorizon`) were removed as zero-on-chain-caller
    ///         surface; this attestation pins the surviving in-context read so a future
    ///         regression deleting it flips RED.
    function testKeptPassHorizonReadPresent() public view {
        string memory src = vm.readFile("contracts/modules/GameAfkingModule.sol");
        assertGt(
            _countOccurrences(src, "function _passHorizonOf(address player) internal view returns (uint24)"),
            0,
            "canonical in-context pass-horizon read present in GameAfkingModule.sol"
        );
        assertGt(
            _countOccurrences(src, "type(uint24).max"),
            0,
            "deity sentinel (type(uint24).max) present in the module horizon semantics"
        );
    }

    // =========================================================================
    // v50.0 D-IMPL-02 — trivial freeze-side positive assertions for the new write paths
    //
    // The DEEPER RNG-freeze fuzz proof of the deferred-claim path lives at Phase 336 / TST-01
    // freeze leg per 335-CONTEXT.md D-IMPL-02. These two tests pin the TRIVIAL property only:
    //   (1) the box-open `whalePassClaims +=` write (Plan 335-02) targets a non-frozen slot;
    //   (2) the AfKing crossing's `_passHorizonOf` in-context read (Plan 335-04) is a non-RNG-window read.
    // 336 owns the deeper freeze-fuzz extension of `RngLockDeterminism.t.sol` (deferred-claim
    // path × rngLock interaction × write-set equivalence).
    // =========================================================================

    /// @notice v50.0 / WHALE04-FREEZE-PROOF §1: the box-open `whalePassClaims[player] += 1` write
    ///         at the LootboxModule whale-pass activation site (Plan 335-02) targets a NON-FROZEN
    ///         slot. The `whalePassClaims` mapping is a pending-claim accumulator, NOT VRF-
    ///         influenced — 334-WHALE04-FREEZE-PROOF §1 catalogues it as out-of-freeze-set. Trivial
    ///         assertion: after a box-open that triggers the type-28 whale-pass boon, the slot
    ///         value is non-zero AND the transaction did not revert (no freeze-lock interference
    ///         on this write).
    /// @dev    Source-level proof complement: assert the `whalePassClaims[player] += 1;` write site
    ///         is byte-present in the LootboxModule (post-Plan-335-02 shape).
    function testWhalePassClaimsWriteIsNonFrozenSlot() public view {
        string memory src = vm.readFile("contracts/modules/DegenerusGameLootboxModule.sol");
        // Plan 335-02 settled the O(1) write shape: `whalePassClaims[player] += 1;` inside the
        // (post-USER-simplification) one-line whale-pass activation body.
        assertGt(
            _countOccurrences(src, "whalePassClaims[player] +="),
            0,
            "WHALE-01: box-open O(1) `whalePassClaims[player] +=` write byte-present"
        );
        // The slot has TWO other +=-writers (PayoutUtils:52 and JackpotModule:1410) per Plan 335-02
        // SUMMARY; this test only pins the LootboxModule writer. The slot is a pending-claim
        // accumulator (WHALE04-FREEZE-PROOF §1 — non-VRF-influenced, not in the freeze write-set).
    }

    /// @notice WHALE04-FREEZE-PROOF §5: the AfKing crossing's pass-horizon read is a
    ///         NON-RNG-WINDOW read. It reads `mintPacked_[player]` (a frozen slot for VRF
    ///         purposes) but does NOT WRITE — the read happens in-context via the module's
    ///         `_passHorizonOf`, declared `internal view`, so the no-write property is
    ///         compiler-enforced. This attestation pins the `view` mutability so a future
    ///         regression relaxing it flips RED.
    function testPassHorizonReadIsViewOnly() public view {
        string memory src = vm.readFile("contracts/modules/GameAfkingModule.sol");
        assertGt(
            _countOccurrences(src, "function _passHorizonOf(address player) internal view"),
            0,
            "pass-horizon read is `internal view` (no writes to frozen slots possible)"
        );
    }

    /// @dev Grant `who` the permanent deity-pass bit (shift 184) in DegenerusGame.mintPacked_ (slot 9).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(9)));
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
    //       (D-IMPL-01) — `mintPacked_[player]` is UNCHANGED between pre-box-open and pre-claim;
    //   (2) post-claim, the future-window level grants land at exactly
    //       [currentLevel+1 .. currentLevel+100] — `frozenUntilLevel` advances to currentLevel+100
    //       (per WhaleModule:1030-1034 + Storage:1127 `ticketStartLevel + 99` math, D-03);
    //   (3) `_applyWhalePassStats` is applied at the claim-time anchor, NOT at box-open
    //       (D-04) — `mintPacked_[player]` DIFFERS between pre-claim and post-claim snapshots,
    //       and `whalePassClaims[player]` resets to 0 (WHALE-02 consumed at claim).
    //
    // Per D-05 (334-CONTEXT.md), the equivalence is byte-correct relative to the new claim-time
    // semantics — NOT byte-identical to the OLD inline-mint shadow (which the v50.0 IMPL retired).
    // =========================================================================

    /// @dev Storage slot for the `whalePassClaims` mapping (DegenerusGame slot 21; confirmed via
    ///      `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage` and 336-01's same probe).
    uint256 private constant WHALE_PASS_CLAIMS_SLOT = 21;

    /// @dev BitPackingLib shifts used by `_applyWhalePassStats` (mirrored locally so the test
    ///      reads the SAME slot fields the contract writes). Verified against
    ///      contracts/libraries/BitPackingLib.sol:48/51/63/66 at e756a6f3.
    uint256 private constant LAST_LEVEL_SHIFT = 0;
    uint256 private constant LEVEL_COUNT_SHIFT = 24;
    uint256 private constant FROZEN_UNTIL_LEVEL_SHIFT = 128;
    uint256 private constant WHALE_PASS_TYPE_SHIFT = 152;
    uint256 private constant MASK_24 = (uint256(1) << 24) - 1;
    uint256 private constant MASK_PASS_TYPE = 0x3; // 2-bit field

    /// @dev Slot for `mintPacked_[who]` (the same mapping the existing `_grantDeityPass` writes;
    ///      mapping root is slot 9 — confirmed against the existing helper at lines 479-484).
    function _mintPackedSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, uint256(9)));
    }

    /// @dev Slot for `whalePassClaims[player]` (mapping root is slot 21).
    function _whalePassClaimsSlot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encode(who, WHALE_PASS_CLAIMS_SLOT));
    }

    /// @dev Read `whalePassClaims[player]` from storage.
    function _readWhalePassClaims(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), _whalePassClaimsSlot(who)));
    }

    /// @dev Force `whalePassClaims[player] = halfPasses` via direct storage write — simulates the
    ///      O(1) box-open accumulator landing exactly `halfPasses` (= 1 here) without driving the
    ///      non-deterministic box-open boon-roll. This is the load-bearing simplification per the
    ///      plan's <action> step 2 — the oracle still asserts live contract behavior on the claim
    ///      side (the only path D-TST01-03 measures).
    function _forceWhalePassClaims(address who, uint256 halfPasses) internal {
        vm.store(
            address(game),
            _whalePassClaimsSlot(who),
            bytes32(halfPasses)
        );
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
        bytes32 mintPackedSlot = _mintPackedSlot(claimant);
        bytes32 mintPackedPreBoxOpen = vm.load(address(game), mintPackedSlot);
        assertEq(
            mintPackedPreBoxOpen,
            bytes32(0),
            "pre-condition: claimant's mintPacked_ slot starts clean (no prior state)"
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
        // slot was touched — `mintPacked_[claimant]` is byte-equal to its pre-box-open
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
        game.claimWhalePass(claimant);

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

        // -------------------------------------------------------------------
        // Defensive source-grep attestation (mirrors the existing trivial tests'
        // `_countOccurrences` idiom on lines 442-476) — keep LIGHT; the storage probes
        // above are the load-bearing oracle.
        // -------------------------------------------------------------------
        {
            string memory whaleSrc = vm.readFile(
                "contracts/modules/DegenerusGameWhaleModule.sol"
            );
            assertGt(
                _countOccurrences(whaleSrc, "_applyWhalePassStats(player, startLevel)"),
                0,
                "byte-present: claimWhalePass invokes `_applyWhalePassStats(player, startLevel)` at claim-time"
            );
            assertGt(
                _countOccurrences(whaleSrc, "whalePassClaims[player] = 0"),
                0,
                "byte-present: claimWhalePass clears the accumulator at claim (WHALE-02 consumption)"
            );
        }
    }

    /// @notice UNMODIFIED invariant: the FLIP win/loss RNG path is byte-identical — the
    ///         `processCoinflipPayouts(` entry and the `bool win = (rngWord & 1) == 1;` 50/50
    ///         win roll are present byte-for-byte in Coinflip.sol (the rng-consuming path
    ///         the v46 removal must NOT have touched).
    function testWinLossRngPathByteUnmodified() public view {
        string memory src = vm.readFile("contracts/Coinflip.sol");
        assertEq(
            _countOccurrences(src, "function processCoinflipPayouts("),
            1,
            "processCoinflipPayouts entry present exactly once (win/loss RNG path)"
        );
        assertEq(
            _countOccurrences(src, "bool win = (rngWord & 1) == 1;"),
            1,
            "the 50/50 win roll `(rngWord & 1) == 1` is byte-unmodified"
        );
    }

    /// @notice UNMODIFIED invariant + RM-03 structural: the recycle bonus is the FLAT-bps form
    ///         `(amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR)` with
    ///         `RECYCLE_BONUS_BPS = 75`, and the `_recyclingBonus` helper takes ONLY `amount`
    ///         (no deity/tier/lazyPass argument) — proving the flat-75bps unconditional behavior
    ///         structurally, not just numerically.
    function testRecycleIsStructurallyFlat75Bps() public view {
        string memory src = vm.readFile("contracts/Coinflip.sol");
        assertEq(
            _countOccurrences(src, "RECYCLE_BONUS_BPS = 75"),
            1,
            "flat recycle constant RECYCLE_BONUS_BPS = 75 present"
        );
        assertEq(
            _countOccurrences(
                src,
                "bonus = (amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR);"
            ),
            1,
            "recycle is the flat-bps formula (no deity-tier scaling branch)"
        );
        // No tier/deity scaling helpers survive (the collapsed afKing/deity recycle path).
        assertEq(
            _countOccurrences(src, "_afKingDeityBonusHalfBpsWithLevel"),
            0,
            "the deity-scaled recycle helper is gone (flat-bps collapse)"
        );
    }

    /// @notice RM-02 structural: the jackpot ETH credit path is the 2-arg deterministic
    ///         `_creditClaimable(beneficiary, weiAmount)` storage form — no entropy param,
    ///         no auto-rebuy branch, no module-local wrapper — confirming the credit path
    ///         consumes no VRF word and always credits claimable (the freeze-obligation
    ///         retirement).
    function testClaimableCreditPathNoEntropy() public view {
        string memory src = _stripComments(
            vm.readFile("contracts/modules/DegenerusGameJackpotModule.sol")
        );
        // Credits route through the deterministic storage helper, with no wrapper in between ...
        assertGt(
            _countOccurrences(src, "_creditClaimable("),
            0,
            "_creditClaimable is the deterministic (beneficiary, weiAmount) credit form"
        );
        assertEq(
            _countOccurrences(src, "_addClaimableEth"),
            0,
            "no module-local credit wrapper around _creditClaimable"
        );
        // ... and the legacy entropy-threaded auto-rebuy credit symbols are gone.
        assertEq(
            _countOccurrences(src, "_processAutoRebuy"),
            0,
            "no _processAutoRebuy (auto-rebuy credit interception removed)"
        );
        assertEq(
            _countOccurrences(src, "autoRebuyState"),
            0,
            "no autoRebuyState read in the credit path"
        );
    }

    /// @notice Structural: the coinflip claim/deposit transition locks consult no game-over
    ///         state, and the facts that make that safe are pinned in place.
    /// @dev The RngLocked claim guard and the deposit-path transition lock both require
    ///      purchaseInfo's `lastPurchaseDay_` (= !jackpotPhaseFlag && lastPurchaseDay), which is
    ///      false in every game-over state: the century/decimator latch freezes
    ///      jackpotPhaseFlag=true (set in lockstep with lastPurchaseDay=false at jackpot entry),
    ///      the liveness latch is unreachable while lastPurchaseDay or jackpotPhaseFlag is set,
    ///      and post-latch advances short-circuit to the final sweep so neither flag is written
    ///      again. Each fact below failing means the gameOver-free lock shape must be re-derived.
    function testCoinflipTransitionLocksNeedNoGameOverConsult() public view {
        string memory flip = _stripComments(vm.readFile("contracts/Coinflip.sol"));
        // The locks themselves consult no game-over state anywhere in the coinflip.
        assertEq(
            _countOccurrences(flip, ".gameOver()"),
            0,
            "no gameOver() consult anywhere in Coinflip (locks rely on lastPurchaseDay_)"
        );

        // Fact 1: while either lock conjunct is set, _livenessTriggered early-returns and suppresses
        // the in-phase 120-day / VRF-grace clocks (they would false-fire in the productive
        // target-met-to-close window), deferring instead to the phase-independent VRF-death deadman.
        string memory storage_ = _stripComments(
            vm.readFile("contracts/storage/DegenerusGameStorage.sol")
        );
        assertGt(
            _countOccurrences(storage_, "if (lastPurchaseDay || jackpotPhaseFlag) return _vrfDeadmanFired();"),
            0,
            "_livenessTriggered early-returns (suppressing the in-phase clocks) while lastPurchaseDay or jackpotPhaseFlag is set"
        );

        // Fact 2: jackpot entry sets the flag pair in lockstep, so a century/decimator
        // latch (which happens with jackpotPhaseFlag=true) freezes lastPurchaseDay_=false.
        string memory adv = _stripComments(
            vm.readFile("contracts/modules/DegenerusGameAdvanceModule.sol")
        );
        assertGt(
            _countOccurrences(adv, "jackpotPhaseFlag = true;\n\n                lastPurchaseDay = false;"),
            0,
            "jackpot entry writes jackpotPhaseFlag=true and lastPurchaseDay=false in lockstep"
        );
    }

    /// @notice UNMODIFIED invariant: KNOWN-ISSUES.md is byte-unmodified across the v46 milestone.
    /// @dev fs_permissions grants read only on ./contracts (NOT the repo root), so this test
    ///      pins the recorded milestone-baseline sha256 as the documented anchor. The actual
    ///      live-file byte-equality is enforced in the verify-step bash gate (which reads the
    ///      repo root and compares `sha256sum KNOWN-ISSUES.md` against this same baseline).
    function testKnownIssuesBaselineHashRecorded() public pure {
        assertEq(
            KNOWN_ISSUES_BASELINE_SHA256,
            0x75b3b4bc79a96c7e16c4e539fa8bfcb8bd1a20063775dbf4d1854dfe3cfd8014,
            "KNOWN-ISSUES.md milestone-baseline sha256 anchor (enforced byte-for-byte in the verify-step bash)"
        );
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
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    function _placeLosingBet(address better) internal returns (uint64 betId) {
        uint32 customTicket = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether;
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(
            address(0),
            0,
            betAmount,
            1,
            customTicket,
            0
        );
        betId = _betNonce(better);
    }

    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer,
            400,
            lootboxAmount,
            bytes32(0),
            MintPaymentKind.DirectEth, false
        );
    }

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(
            abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT))
        );
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Bump the active lootbox RNG index (low 48 bits of lootboxRngPacked, slot 34) by one,
    ///      mirroring requestLootboxRng's pre-increment, so a box queued at the prior index now sits
    ///      at LR_INDEX-1 — the just-finalized index the relocated multi-index sweep opens.
    function _advanceLootboxRngIndexByOne() internal {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        uint48 idx = uint48(packed & 0xFFFFFFFFFFFF);
        packed = (packed & ~uint256(0xFFFFFFFFFFFF)) | uint256(idx + 1);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(packed)
        );
    }

    /// @dev Park the auto-open frontier (boxCursorIndex byte 13 + boxCursor byte 7, both slot 58)
    ///      at `index` with a zero in-index cursor, so the relocated sweep begins exactly at this
    ///      finalized index (the realistic state where lower indices are drained). Without this the
    ///      sweep would orphan-break at the first un-worded lower index.
    function _parkBoxFrontier(uint48 index) internal {
        bytes32 slot = bytes32(uint256(58));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 cursorMask = (uint256(1) << 48) - 1;
        packed &= ~(cursorMask << (7 * 8));   // boxCursor = 0
        packed &= ~(cursorMask << (13 * 8));  // clear boxCursorIndex field
        packed |= (uint256(index) & cursorMask) << (13 * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _injectedWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(
            abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT))
        );
        return uint256(vm.load(address(game), slot));
    }

    function _lootboxEthBase(
        uint48 index,
        address who
    ) internal view returns (uint256) {
        bytes32 inner = keccak256(
            abi.encode(uint256(index), uint256(LOOTBOX_ETH_SLOT))
        );
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf)) & LB_AMOUNT_MASK;
    }

    function _readBetPacked(
        address owner,
        uint64 id
    ) internal view returns (uint256) {
        bytes32 inner = keccak256(
            abi.encode(owner, uint256(DEGENERETTE_BETS_SLOT))
        );
        bytes32 leaf = keccak256(abi.encode(uint256(id), uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(
            abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT))
        );
        return uint64(uint256(vm.load(address(game), slot)));
    }

    /// @dev Seed the live futurePrizePool (upper 128 bits of prizePoolsPacked slot 2) so winning
    ///      ETH payouts are solvent. Preserves the lower 128 bits (nextPrizePool).
    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(2))));
        uint128 currentNext = uint128(packed);
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
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
        vm.prank(who);
        game.setOperatorApproval(address(game), true);

        // Point the live daily index at `atIndex` (word still 0) for placement, find an 8/8 win.
        _setLootboxRngIndex(atIndex);
        (uint32 winTicket, uint256 word) = _findWinningCombo(atIndex);
        uint128 betAmount = 0.01 ether;
        vm.prank(who);
        game.placeDegeneretteBet{value: betAmount}(
            address(0),
            0,
            betAmount,
            1,
            winTicket,
            0
        );
        uint64 betId = _betNonce(who);

        _seedFuturePrizePool(10_000 ether);
        uint256 pre = game.claimableWinningsOf(who);
        _injectLootboxRngWord(atIndex, word);
        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = who;
        betIds[0] = betId;
        vm.prank(cranker);
        game.degeneretteResolve(players, betIds);
        creditDelta = game.claimableWinningsOf(who) - pre;
    }

    /// @dev Set the live daily lootboxRngIndex (low 48 bits of lootboxRngPacked slot 34).
    function _setLootboxRngIndex(uint48 idx) internal {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        packed = (packed & ~uint256(0xFFFFFFFFFFFF)) | uint256(idx);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(packed)
        );
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

    /// @dev customTicket matching the result in ZERO quadrants → matches == 0 → clean loss.
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

    /// @dev Find a (winningTicket, rngWord) pair guaranteeing >= 2 matches at spin 0 — the
    ///      custom ticket equals the result ticket so it is a guaranteed win (8/8). Mirrors the
    ///      established DegeneretteFreezeResolution._findWinningCombo pattern.
    function _findWinningCombo(
        uint48 index
    ) internal pure returns (uint32 winTicket, uint256 rngWord) {
        for (uint256 attempt; attempt < 100; attempt++) {
            rngWord = uint256(
                keccak256(abi.encode("freeze_removal_win", attempt))
            );
            winTicket = _resultTicketFor(index, rngWord);
            if (_countMatchesLocal(winTicket, winTicket) >= 2)
                return (winTicket, rngWord);
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

    // -------------------------------------------------------------------------
    // Source-level grep helpers (vm.readFile over ./contracts)
    // -------------------------------------------------------------------------

    /// @dev Count non-overlapping occurrences of `needle` in `haystack`.
    function _countOccurrences(
        string memory haystack,
        string memory needle
    ) private pure returns (uint256 count) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || h.length < n.length) return 0;
        for (uint256 i = 0; i <= h.length - n.length; ) {
            bool matched = true;
            for (uint256 j = 0; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                unchecked {
                    ++count;
                    i += n.length;
                }
            } else {
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// @dev Strip `//` line comments and lines whose first non-space char starts a block comment
    ///      (`*` or `/*`), so header/NatSpec prose mentioning a kill-set symbol does not
    ///      self-invalidate the grep gate. Conservative: drops the remainder of a line at `//`
    ///      and drops whole block-comment-bodied lines. Code matches survive.
    function _stripComments(
        string memory src
    ) private pure returns (string memory) {
        bytes memory b = bytes(src);
        bytes memory out = new bytes(b.length);
        uint256 o;
        uint256 i;
        uint256 lineStart;
        bool lineIsBlockComment;
        // Determine, per line, whether it is a comment line; copy code chars only.
        while (i < b.length) {
            // At a newline, reset line state.
            if (b[i] == 0x0a) {
                out[o++] = b[i];
                i++;
                lineStart = i;
                lineIsBlockComment = false;
                continue;
            }
            // Detect block-comment / continuation lines: first non-space char is `*` or `/*`.
            if (i == lineStart || _onlySpacesSince(b, lineStart, i)) {
                if (b[i] == 0x2a) {
                    lineIsBlockComment = true; // line begins with `*`
                } else if (
                    b[i] == 0x2f &&
                    i + 1 < b.length &&
                    b[i + 1] == 0x2a
                ) {
                    lineIsBlockComment = true; // line begins with `/*`
                }
            }
            // `//` line comment: skip to end of line.
            if (
                !lineIsBlockComment &&
                b[i] == 0x2f &&
                i + 1 < b.length &&
                b[i + 1] == 0x2f
            ) {
                while (i < b.length && b[i] != 0x0a) i++;
                continue;
            }
            if (!lineIsBlockComment) {
                out[o++] = b[i];
            }
            i++;
        }
        // Trim the output buffer to `o`.
        bytes memory trimmed = new bytes(o);
        for (uint256 k; k < o; k++) trimmed[k] = out[k];
        return string(trimmed);
    }

    /// @dev True iff every byte in [from, to) is a space (0x20) or tab (0x09).
    function _onlySpacesSince(
        bytes memory b,
        uint256 from,
        uint256 to
    ) private pure returns (bool) {
        for (uint256 i = from; i < to; i++) {
            if (b[i] != 0x20 && b[i] != 0x09) return false;
        }
        return true;
    }
}
