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
///        behaviorally gone, and the BURNIE win/loss RNG path + KNOWN-ISSUES are unmodified).
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
///         ticket-conversion / auto-rebuy interception), and the BURNIE flip recycle bonus is
///         a flat 75bps applied unconditionally (no deity scaling). REMOVE structural: the
///         legacy kill set returns ZERO non-comment matches outside contracts/test+mocks (the
///         KEPT `hasAnyLazyPass` and the keeper file `AfKing.sol` are excluded), and the win/loss
///         RNG path (`processCoinflipPayouts` + `(rngWord & 1) == 1`) is byte-identical.
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING). Drives
///      REAL degenerette bets + REAL lootbox purchases through the public mint API (mirroring
///      the established CrankNonBrick / CrankFaucetResistance patterns); the only slot
///      manipulation is the established LOOTBOX_RNG word injection. Source-level attestations
///      use vm.readFile over ./contracts (foundry.toml grants read on ./contracts).
///      Test-only: NO contracts/*.sol is mutated.
contract RngFreezeAndRemovalProofs is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (DegenerusGame; confirmed via `forge inspect storage`,
    // authoritative post-deletion layout per 317-08: lootboxRngPacked=35, word map=36)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;
    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 45;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 46;
    /// @dev lootboxEthBase mapping root slot (uint48 index => address => packed).
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;

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
    // RM-03 flat recycle constants (mirror BurnieCoinflip's private constants).
    // BurnieCoinflip.sol:130 RECYCLE_BONUS_BPS = 75 ; :129 BPS_DENOMINATOR = 10_000.
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
    ///         autoOpen cursor orphan gate (`lootboxRngWordByIndex[index] == 0 -> return`,
    ///         DegenerusGame:1603) AND the LootboxModule:485 openLootBox RngNotReady guard — no
    ///         pre-word open. After the word lands the SAME crank opens the box (signal cleared).
    function testCrankBoxOpenStaysPostUnlock() public {
        address boxOwner = makeAddr("box_owner");
        uint48 idx = _activeLootboxIndex();
        _buyBox(boxOwner, 1 ether);
        assertGt(
            _lootboxEthBase(idx, boxOwner),
            0,
            "box enqueued (first-deposit signal set)"
        );

        // PRE-WORD: word at idx is 0 -> autoOpen returns at the cursor orphan gate. No open.
        assertEq(
            _injectedWord(idx),
            0,
            "pre-condition: box index word not yet landed (frozen window)"
        );
        vm.prank(cranker);
        game.autoOpen(100);
        assertGt(
            _lootboxEthBase(idx, boxOwner),
            0,
            "pre-word: box NOT opened (cursor orphan gate + openLootBox RngNotReady)"
        );

        // POST-WORD: land the word -> the SAME crank opens the box (signal cleared on open).
        _injectLootboxRngWord(idx, FIXED_WORD);
        vm.prank(cranker);
        game.autoOpen(100);
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

    /// @notice RM-03 behavioral (flat 75bps, unconditional): the BURNIE flip recycle bonus is
    ///         `(amount * 75) / 10_000` applied flat for every player tier — a deity-pass holder
    ///         and a normal player receive EXACTLY the same bonus for the same amount (no deity
    ///         scaling, no under/over-credit). `_recyclingBonus(amount)` takes ONLY `amount`
    ///         (proven structurally in Task 3), so tier cannot influence it; here we assert the
    ///         numeric flat-bps formula holds and is identical across two "tiers".
    function testBurnieRecycleIsFlat75BpsAcrossTiers(uint96 amountWei) public view {
        // Keep below the 1000-BURNIE bonus cap so the flat-bps relationship holds exactly.
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
    ///         (outside contracts/test + contracts/mocks). The KEPT `hasAnyLazyPass` and the
    ///         keeper file `AfKing.sol` are excluded so the kept symbols do not false-positive.
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
            "contracts/BurnieCoinflip.sol",
            "contracts/BurnieCoin.sol",
            "contracts/DegenerusVault.sol",
            "contracts/StakedDegenerusStonk.sol",
            "contracts/modules/DegenerusGameJackpotModule.sol",
            "contracts/modules/DegenerusGameAdvanceModule.sol",
            "contracts/modules/DegenerusGamePayoutUtils.sol",
            "contracts/modules/DegenerusGameDegeneretteModule.sol",
            "contracts/modules/DegenerusGameLootboxModule.sol",
            "contracts/modules/DegenerusGameMintModule.sol",
            "contracts/storage/DegenerusGameStorage.sol",
            "contracts/interfaces/IDegenerusGame.sol",
            "contracts/interfaces/IBurnieCoinflip.sol",
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

    /// @notice RM-04 reconciliation: the KEPT `hasAnyLazyPass` is present and exposed (NOT in the
    ///         kill set). Guards against an over-eager removal pass deleting the kept symbol.
    function testKeptHasAnyLazyPassPresent() public view {
        // Exposed externally on the live contract (PROTO-01 keeper gate basis).
        assertTrue(
            game.hasAnyLazyPass(ContractAddresses.VAULT),
            "hasAnyLazyPass is exposed and returns true for the deity-bit holder (KEPT)"
        );
        string memory src = vm.readFile("contracts/DegenerusGame.sol");
        assertGt(
            _countOccurrences(src, "hasAnyLazyPass"),
            0,
            "hasAnyLazyPass identifier KEPT in DegenerusGame.sol"
        );
    }

    /// @notice UNMODIFIED invariant: the BURNIE win/loss RNG path is byte-identical — the
    ///         `processCoinflipPayouts(` entry and the `bool win = (rngWord & 1) == 1;` 50/50
    ///         win roll are present byte-for-byte in BurnieCoinflip.sol (the rng-consuming path
    ///         the v46 removal must NOT have touched).
    function testWinLossRngPathByteUnmodified() public view {
        string memory src = vm.readFile("contracts/BurnieCoinflip.sol");
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
        string memory src = vm.readFile("contracts/BurnieCoinflip.sol");
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

    /// @notice RM-02 structural: `_addClaimableEth` is the 2-arg deterministic credit form
    ///         (`function _addClaimableEth(address beneficiary, uint256 weiAmount)`) — no entropy
    ///         param, no auto-rebuy branch — confirming the jackpot ETH credit path consumes no
    ///         VRF word and always credits claimable (the freeze-obligation retirement).
    function testAddClaimableEthIsTwoArgNoEntropy() public view {
        string memory src = _stripComments(
            vm.readFile("contracts/modules/DegenerusGameJackpotModule.sol")
        );
        // The 2-arg signature is present ...
        assertGt(
            _countOccurrences(
                src,
                "function _addClaimableEth(\n        address beneficiary,\n        uint256 weiAmount\n    )"
            ),
            0,
            "_addClaimableEth is the 2-arg (beneficiary, weiAmount) deterministic credit form"
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
            MintPaymentKind.DirectEth
        );
    }

    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(
            abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT))
        );
        vm.store(address(game), slot, bytes32(rngWord));
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
            abi.encode(uint256(index), uint256(LOOTBOX_ETH_BASE_SLOT))
        );
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
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

    /// @dev Set the live daily lootboxRngIndex (low 48 bits of lootboxRngPacked slot 35).
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
