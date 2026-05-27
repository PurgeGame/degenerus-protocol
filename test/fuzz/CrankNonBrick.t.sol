// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title CrankNonBrick -- Proves SAFE-02: the permissionless do-work cranks
///        (degeneretteResolve / autoOpen) and the keeper-gated batchPurchase are NON-BRICK.
///
/// @notice One reverting / stale / not-ready item is isolated via the onlySelf +
///         try/catch shell and SKIPPED — the batch completes, rewarding / buying only
///         the successful items, and a single failing entry can never deny progress to
///         the rest. Concretely this suite asserts:
///
///   Task 1 — skip-and-continue + slice-refund + batch-level pre-check:
///     - degeneretteResolve over a list whose middle item is poisoned (not-ready, RNG word absent)
///       still resolves the healthy items; the poisoned item is caught by
///       `try this._degeneretteResolveBet catch {}` and the reward sums over SUCCESSES only.
///     - autoOpen whose cursor walk hits a poisoned entry (lootboxEthBase != 0 so it is
///       NOT the `continue`-skip, but lootboxEth == 0 so the module open reverts E()) skips
///       that entry via the per-item try/catch and opens the rest, rewarding successes only.
///     - batchPurchase where ONE player's _batchPurchaseUnit reverts (a sub-LOOTBOX_MIN
///       slice → mint module reverts E()) isolates that player via the per-slice try/catch,
///       lands the other players' lootboxes, refunds the failed slice to the keeper in the
///       single post-loop refund, and the call returns WITHOUT reverting.
///     - batchPurchase pre-checks rngLocked / gameOver ONCE at entry: when rngLocked is true
///       the WHOLE batch is rejected at entry (single revert, not a partial per-player run).
///
///   Task 2 — reentrancy rollback + cancel un-brickable:
///     - A re-entrant frame (a malicious player whose withdraw-recipient callback tries to
///       re-enter withdraw / setDailyQuantity) cannot double-spend: the inner withdraw
///       reverts InsufficientBalance under strict CEI (effects-before-interaction) and
///       unwinds, so the pool is debited at most once.
///     - Cancel (setDailyQuantity(0)) is un-brickable: a subscriber can always tombstone its
///       sub, and afterward its full _poolOf ETH is withdrawable — the CEI withdraw cannot be
///       blocked by any downstream interaction.
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING). Drives
///      REAL degenerette bets (mirroring the 318-02 CrankFaucetResistance pattern) and REAL
///      lootbox purchases through the public mint API; the only slot manipulation is the
///      established LOOTBOX_RNG word injection and a single targeted lootboxEth-zeroing to
///      forge the caught-revert poison entry. batchPurchase is called as the pinned AF_KING
///      keeper (vm.prank(ContractAddresses.AF_KING)). Test-only: no contracts/*.sol mutated.
contract CrankNonBrick is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (DegenerusGame; confirmed via `forge inspect storage`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;
    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;
    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 45;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 46;
    /// @dev lootboxEth mapping root slot (uint48 index => address => packed).
    uint256 private constant LOOTBOX_ETH_SLOT = 15;
    /// @dev rngLockedFlag is bool at slot 0 offset 21 bytes = bit 168.
    uint256 private constant RNG_LOCKED_SHIFT = 168;
    /// @dev gameOver is bool at slot 0 offset 23 bytes = bit 184.
    uint256 private constant GAME_OVER_SHIFT = 184;

    // -------------------------------------------------------------------------
    // Crank reward peg mirror (the contract's own FIXED constants, REW-03)
    // -------------------------------------------------------------------------
    uint256 private constant CRANK_GAS_PRICE_REF = 0.5 gwei;
    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 71_203;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — emitted once
    ///      per creditFlip via _addDailyFlip; used to count crank-reward credits.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    // -------------------------------------------------------------------------
    // AfKing pinned slot layout + Sub packed-field offsets (for the TOMB-04 didWork autoBuy tests)
    // -------------------------------------------------------------------------
    uint256 private constant AFK_SUBOF_SLOT = 1;            // _subOf mapping root (address => Sub)
    uint256 private constant AFK_SUBSCRIBER_INDEX_SLOT = 3; // _subscriberIndex mapping root (1-indexed)
    uint256 private constant AFK_SWEEP_PACKED_SLOT = 4;     // _autoBuyDay (uint32) + _autoBuyCursor (uint224)
    uint256 private constant AFK_OFF_DAILY = 0;             // uint8  dailyQuantity  (byte 0)
    uint256 private constant AFK_OFF_LASTSWEPT = 1;         // uint32 lastAutoBoughtDay    (bytes 1..4)
    /// @dev SubscriptionExpired(address indexed player, uint8 reason). reason 1 = AutoPause, 2 = CancelReclaim.
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt
    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp
    uint256 private constant FIXED_WORD = uint256(keccak256("crank_nonbrick_fixed_word"));
    uint256 private constant LOOTBOX_MIN = 0.01 ether; // mint-module DirectEth lootbox floor

    address private player;
    address private cranker;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("nonbrick_player");
        cranker = makeAddr("nonbrick_cranker");
        vm.deal(player, 1000 ether);
        vm.deal(cranker, 1000 ether);
        vm.deal(address(game), 1000 ether);

        // Seed lootboxRngIndex = 1 (word stays 0 until injected) so placeDegeneretteBet's
        // index!=0 / word==0 precondition holds.
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));

        // The crank resolve sub-call delegatecalls resolveBets with msg.sender == game,
        // so the game must be the bet owner's approved operator (the documented relaxation).
        vm.prank(player);
        game.setOperatorApproval(address(game), true);
    }

    // =========================================================================
    // Task 1 — degeneretteResolve skip-and-continue (poisoned middle item)
    // =========================================================================

    /// @notice SAFE-02 / T-318-03-01 (bets): degeneretteResolve over [healthy, POISONED, healthy] resolves
    ///         the two healthy bets and SKIPS the poisoned middle one (its RNG word never landed →
    ///         the onlySelf resolve hits RngNotReady, caught by try/catch). The batch does NOT
    ///         revert, and the reward sums over the SUCCESSES only (exactly 2 item-pegs), proving
    ///         a single not-ready item cannot brick the rest.
    function testCrankBetsSkipsPoisonedMiddleItem() public {
        // Two healthy bets at INDEX (word will be injected) ...
        uint64 healthyA = _placeLosingBet(player);
        uint64 healthyB = _placeLosingBet(player);

        // ... and one poisoned bet at a DIFFERENT index whose word never lands.
        uint48 poisonIndex = 2;
        uint64 poisoned = _placeLosingBetAtIndex(player, poisonIndex);

        // Inject the word for INDEX only; poisonIndex stays word-less → not-ready.
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        // item 0 (the probe) must be a LIVE bet so the batch proceeds past the BatchAlreadyTaken
        // short-circuit. Order: [healthyA(probe), poisoned(skip), healthyB].
        address[] memory players = new address[](3);
        uint64[] memory betIds = new uint64[](3);
        players[0] = player; betIds[0] = healthyA;
        players[1] = player; betIds[1] = poisoned;
        players[2] = player; betIds[2] = healthyB;

        // The crank reward is credited to the CALLER (cranker), not the bet owner.
        uint256 preStake = coinflip.coinflipAmount(cranker);

        vm.recordLogs();
        vm.prank(cranker);
        game.degeneretteResolve(players, betIds); // MUST NOT revert

        // The two healthy bets resolved (slots deleted = work done) ...
        assertEq(_readBetPacked(player, healthyA), 0, "healthy A resolved");
        assertEq(_readBetPacked(player, healthyB), 0, "healthy B resolved");
        // ... the poisoned not-ready bet was SKIPPED (slot intact, re-crankable later).
        assertGt(_readBetPacked(player, poisoned), 0, "poisoned not-ready bet skipped, slot intact");

        // Exactly ONE creditFlip for the whole batch, summed over the 2 successes (REW-02).
        // (Losing bets pay no winnings, so the only creditFlip is the post-loop crank reward.)
        assertEq(_countCoinflipStakeUpdated(), 1, "one crank-reward creditFlip for the batch");
        uint256 rewardEthAtPeg =
            ((coinflip.coinflipAmount(cranker) - preStake) * _priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertEq(
            rewardEthAtPeg,
            2 * CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF,
            "reward sums over the 2 successful resolves only, not the skipped item"
        );
    }

    /// @notice SAFE-02 fuzz (bets): wherever the single poisoned (not-ready) item sits in a length-3
    ///         batch whose item 0 is always a live probe, the batch completes and rewards exactly the
    ///         two healthy resolves — the poison position never bricks the crank.
    function testFuzz_CrankBetsPoisonPositionNeverBricks(uint8 poisonSlotSel) public {
        // Poison occupies slot 1 or 2 (slot 0 is the live probe, by construction).
        uint256 poisonSlot = (poisonSlotSel % 2) + 1;

        uint64 probe = _placeLosingBet(player);
        uint64 otherHealthy = _placeLosingBet(player);
        uint48 poisonIndex = 2;
        uint64 poisoned = _placeLosingBetAtIndex(player, poisonIndex);
        _injectLootboxRngWord(INDEX, FIXED_WORD); // poisonIndex stays word-less

        address[] memory players = new address[](3);
        uint64[] memory betIds = new uint64[](3);
        players[0] = player; betIds[0] = probe; // always live probe
        if (poisonSlot == 1) {
            players[1] = player; betIds[1] = poisoned;
            players[2] = player; betIds[2] = otherHealthy;
        } else {
            players[1] = player; betIds[1] = otherHealthy;
            players[2] = player; betIds[2] = poisoned;
        }

        uint256 preStake = coinflip.coinflipAmount(cranker);
        vm.prank(cranker);
        game.degeneretteResolve(players, betIds); // MUST NOT revert at any poison position

        assertGt(_readBetPacked(player, poisoned), 0, "poison skipped regardless of position");
        uint256 rewardEthAtPeg =
            ((coinflip.coinflipAmount(cranker) - preStake) * _priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertEq(
            rewardEthAtPeg,
            2 * CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF,
            "exactly the 2 healthy resolves rewarded at every poison position"
        );
    }

    // =========================================================================
    // Task 1 — autoOpen skip-and-continue (poisoned entry caught by try/catch)
    // =========================================================================

    /// @notice SAFE-02 / T-318-03-01 (boxes): autoOpen walks a queue of three real lootboxes at
    ///         one index whose word HAS landed; ONE entry is poisoned so its onlySelf open reverts
    ///         (lootboxEthBase != 0 so it is not the cheap continue-skip, but lootboxEth == 0 so the
    ///         module's `amount == 0` guard reverts E()). The per-item try/catch isolates it and the
    ///         walk opens the other two, rewarding over the successes only — never bricking.
    function testCrankBoxesSkipsPoisonedEntryViaTryCatch() public {
        address a = makeAddr("box_a");
        address b = makeAddr("box_b"); // poisoned
        address c = makeAddr("box_c");

        // Enqueue three real boxes at the same fresh index, then land that index's word.
        uint48 idx = _enqueueBoxes(a, b, c);
        _injectLootboxRngWord(idx, FIXED_WORD);

        // Poison b: keep its first-deposit signal (lootboxEthBase != 0 so the walk does NOT
        // continue-skip it) but zero its lootboxEth so openLootBox reverts E() (amount == 0) →
        // caught by the per-item try/catch.
        _zeroLootboxEth(idx, b);
        assertGt(_lootboxEthBase(idx, b), 0, "poisoned entry still has the first-deposit signal");
        assertEq(_lootboxEth(idx, b), 0, "poisoned entry has zero openable amount (forces caught revert)");

        // The crank reward credits the CALLER (cranker), who owns no boxes — so its stake delta is
        // purely the post-loop crank reward, isolated from any box-winnings credits to a / c.
        uint256 preStake = coinflip.coinflipAmount(cranker);

        vm.prank(cranker);
        game.autoOpen(100); // MUST NOT revert

        // a and c opened (boxes zeroed on open); b skipped via the caught revert (signal intact).
        assertEq(_lootboxEthBase(idx, a), 0, "box a opened");
        assertEq(_lootboxEthBase(idx, c), 0, "box c opened");
        assertGt(_lootboxEthBase(idx, b), 0, "poisoned box b skipped, not opened");

        // The cranker's crank reward sums over the 2 successful opens only (the poisoned entry,
        // caught by the per-item try/catch, contributes nothing).
        uint256 rewardEthAtPeg =
            ((coinflip.coinflipAmount(cranker) - preStake) * _priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertEq(
            rewardEthAtPeg,
            2 * CRANK_OPEN_BOX_GAS_UNITS * CRANK_GAS_PRICE_REF,
            "box reward sums over the 2 successful opens only"
        );
    }

    // =========================================================================
    // Task 1 — batchPurchase per-player isolation + slice-refund
    // =========================================================================

    /// @notice SAFE-02 / T-318-03-01 (batchPurchase): a batch of three players where the MIDDLE
    ///         player's slice is below LOOTBOX_MIN (the mint module reverts E()) isolates that player
    ///         via the per-slice try/catch, lands the two healthy players' lootboxes, refunds the
    ///         failed slice to the keeper in the single post-loop refund, and returns WITHOUT
    ///         reverting. Proves one failing per-player unit cannot brick the keeper batch.
    function testBatchPurchaseIsolatesFailingPlayerAndRefundsSlice() public {
        address p1 = makeAddr("bp_p1");
        address p2 = makeAddr("bp_p2"); // failing slice
        address p3 = makeAddr("bp_p3");

        uint256 goodSlice = 1 ether; // >= LOOTBOX_MIN
        uint256 badSlice = LOOTBOX_MIN - 1; // < LOOTBOX_MIN → mint module reverts E()
        uint256 totalValue = goodSlice + badSlice + goodSlice;

        address[] memory players = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint8[] memory modes = new uint8[](3);
        players[0] = p1; amounts[0] = goodSlice; modes[0] = uint8(MintPaymentKind.DirectEth);
        players[1] = p2; amounts[1] = badSlice;  modes[1] = uint8(MintPaymentKind.DirectEth);
        players[2] = p3; amounts[2] = goodSlice; modes[2] = uint8(MintPaymentKind.DirectEth);

        // Fund the keeper with the full batch value and call AS the keeper.
        address keeper = ContractAddresses.AF_KING;
        vm.deal(keeper, totalValue);
        uint256 keeperBalBefore = keeper.balance;

        vm.prank(keeper);
        game.batchPurchase{value: totalValue}(players, amounts, modes); // MUST NOT revert

        // The two healthy players got their lootboxes queued (lootboxEthBase credited at the
        // current daily index); the failing player got nothing.
        uint48 dailyIndex = _activeLootboxIndex();
        assertGt(_lootboxEthBase(dailyIndex, p1), 0, "healthy p1 lootbox landed");
        assertGt(_lootboxEthBase(dailyIndex, p3), 0, "healthy p3 lootbox landed");
        assertEq(_lootboxEthBase(dailyIndex, p2), 0, "failing p2 bought nothing");

        // SLICE-REFUND: exactly the failed slice was refunded to the keeper (one batch value in,
        // unspent value refunded once after the loop). Net keeper outflow == the two good slices.
        uint256 keeperBalAfter = keeper.balance;
        assertEq(
            keeperBalBefore - keeperBalAfter,
            goodSlice * 2,
            "only the two successful slices left the keeper; the failed slice was refunded"
        );
    }

    /// @notice SAFE-02 fuzz (batchPurchase): for any single failing-player position in a length-3
    ///         batch, the batch completes, the other two purchases land, and exactly the failed
    ///         slice is refunded — the failure position never bricks the keeper batch.
    function testFuzz_BatchPurchaseFailPositionRefundsAndCompletes(uint8 failSel) public {
        uint256 failPos = failSel % 3;
        uint256 goodSlice = 0.5 ether;
        uint256 badSlice = LOOTBOX_MIN - 1;

        address[] memory players = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint8[] memory modes = new uint8[](3);
        uint256 totalValue;
        for (uint256 i; i < 3; i++) {
            players[i] = makeAddr(string(abi.encodePacked("bpf_", vm.toString(i), "_", vm.toString(failPos))));
            amounts[i] = (i == failPos) ? badSlice : goodSlice;
            modes[i] = uint8(MintPaymentKind.DirectEth);
            totalValue += amounts[i];
        }

        address keeper = ContractAddresses.AF_KING;
        vm.deal(keeper, totalValue);
        uint256 before = keeper.balance;

        vm.prank(keeper);
        game.batchPurchase{value: totalValue}(players, amounts, modes); // MUST NOT revert

        uint48 dailyIndex = _activeLootboxIndex();
        uint256 landed;
        for (uint256 i; i < 3; i++) {
            if (i == failPos) {
                assertEq(_lootboxEthBase(dailyIndex, players[i]), 0, "failing slice bought nothing");
            } else {
                assertGt(_lootboxEthBase(dailyIndex, players[i]), 0, "healthy slice landed");
                landed += goodSlice;
            }
        }
        assertEq(before - keeper.balance, landed, "exactly the failed slice refunded, regardless of position");
    }

    // =========================================================================
    // Task 1 — batchPurchase batch-level rngLocked / gameOver pre-check
    // =========================================================================

    /// @notice SAFE-02 (batchPurchase batch-level pre-check): when rngLocked is true the WHOLE batch
    ///         is rejected ONCE at entry (single RngLocked revert), NOT a per-player partial run — no
    ///         slice is consumed and no player is purchased for.
    function testBatchPurchaseRngLockedRejectsWholeBatchAtEntry() public {
        address p1 = makeAddr("rl_p1");
        address p2 = makeAddr("rl_p2");
        address[] memory players = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint8[] memory modes = new uint8[](2);
        players[0] = p1; amounts[0] = 1 ether; modes[0] = uint8(MintPaymentKind.DirectEth);
        players[1] = p2; amounts[1] = 1 ether; modes[1] = uint8(MintPaymentKind.DirectEth);
        uint256 totalValue = 2 ether;

        _setRngLocked(true);
        assertTrue(game.rngLocked(), "rngLocked set for the pre-check");

        address keeper = ContractAddresses.AF_KING;
        vm.deal(keeper, totalValue);

        // Single whole-batch revert at entry (RngLocked()), before any per-player loop.
        vm.prank(keeper);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        game.batchPurchase{value: totalValue}(players, amounts, modes);

        // Nothing was purchased (the batch never entered the per-player loop).
        uint48 dailyIndex = _activeLootboxIndex();
        assertEq(_lootboxEthBase(dailyIndex, p1), 0, "no purchase under rngLocked (batch-level abort)");
        assertEq(_lootboxEthBase(dailyIndex, p2), 0, "no purchase under rngLocked (batch-level abort)");
    }

    /// @notice SAFE-02 (batchPurchase batch-level pre-check): when gameOver is true the whole batch
    ///         is rejected ONCE at entry (E()), confirming the second batch-level gate fires before
    ///         any per-player work.
    function testBatchPurchaseGameOverRejectsWholeBatchAtEntry() public {
        address p1 = makeAddr("go_p1");
        address[] memory players = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint8[] memory modes = new uint8[](1);
        players[0] = p1; amounts[0] = 1 ether; modes[0] = uint8(MintPaymentKind.DirectEth);

        _setGameOver(true);

        address keeper = ContractAddresses.AF_KING;
        vm.deal(keeper, 1 ether);
        vm.prank(keeper);
        vm.expectRevert(bytes4(keccak256("E()")));
        game.batchPurchase{value: 1 ether}(players, amounts, modes);
    }

    /// @notice Keeper gate: a non-AF_KING caller cannot reach batchPurchase at all (E()), so the
    ///         non-brick isolation surface is keeper-only — confirming the trust boundary the
    ///         per-player relaxation rests on.
    function testBatchPurchaseRejectsNonKeeperCaller() public {
        address[] memory players = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint8[] memory modes = new uint8[](1);
        players[0] = player; amounts[0] = 1 ether; modes[0] = uint8(MintPaymentKind.DirectEth);

        vm.deal(cranker, 1 ether);
        vm.prank(cranker); // not AF_KING
        vm.expectRevert(bytes4(keccak256("E()")));
        game.batchPurchase{value: 1 ether}(players, amounts, modes);
    }

    // =========================================================================
    // Seed 2 (331) — keeper-batch no-brick under the pre-validated path (HARD CONSTRAINT)
    // =========================================================================
    //
    // CONTEXT D-07 + the `feedback_security_over_gas` HARD CONSTRAINT: Seed 2 replaces
    // batchPurchase's per-player `this._batchPurchaseUnit{value}` try/catch isolation with a
    // pre-validated keeper-specialized path (`batchPurchaseForKeeper`, the gated 331-05 diff). The
    // per-player isolation is a SECURITY property — a single reverting / funding-skipped / poisoned
    // player must NEVER brick the whole keeper batch. The mechanism may change (try/catch ->
    // pre-validation / cheap-skip per 331-SEEDS-DESIGN.md R3/R5/R6/R7), but the LIVENESS must survive.
    //
    // These tests run against the CURRENT path now (GREEN baseline) and are parameterized via the
    // SAME `_driveKeeperBatch(useKeeperPath)` toggle as KeeperBatchAffiliateDeltaAudit, so the SAME
    // no-brick proof re-runs against `batchPurchaseForKeeper` once KEEPER_PATH_LANDED flips at 331-05.

    /// @dev TODO-331-05: flip to `true` once `batchPurchaseForKeeper` lands in the gated 331-05 diff.
    ///      While false, the keeper-path branch of `_driveKeeperBatch` is unreachable and only the
    ///      CURRENT `batchPurchase` no-brick baseline runs.
    bool internal constant KEEPER_PATH_LANDED = false;

    /// @notice Seed 2 / T-331-06 (no-brick, HARD CONSTRAINT): a keeper batch whose MIDDLE player is
    ///         poisoned (a sub-LOOTBOX_MIN slice — the R3 cheap-skip revert source) still purchases for
    ///         the healthy players, skips the poisoned one, refunds its slice to the keeper, and the
    ///         batch does NOT revert. This is the per-player isolation liveness the try/catch ->
    ///         pre-validation swap MUST preserve.
    function testKeeperBatchSkipsPoisonedMiddlePlayer() public {
        address[] memory players = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint8[] memory modes = new uint8[](3);
        address healthyA = makeAddr("kb_healthyA");
        address poisoned = makeAddr("kb_poisoned"); // sub-LOOTBOX_MIN -> mint module reverts E() / cheap-skip
        address healthyB = makeAddr("kb_healthyB");
        players[0] = healthyA; amounts[0] = 1 ether;          modes[0] = uint8(MintPaymentKind.DirectEth);
        players[1] = poisoned; amounts[1] = LOOTBOX_MIN - 1;  modes[1] = uint8(MintPaymentKind.DirectEth);
        players[2] = healthyB; amounts[2] = 1 ether;          modes[2] = uint8(MintPaymentKind.DirectEth);

        uint256 keeperBefore;
        _driveKeeperBatch(KEEPER_PATH_LANDED, players, amounts, modes); // MUST NOT revert
        keeperBefore = _lastKeeperBefore;

        uint48 idx = _activeLootboxIndex();
        // (1) healthyA + healthyB purchased.
        assertGt(_lootboxEthBase(idx, healthyA), 0, "healthy A purchased");
        assertGt(_lootboxEthBase(idx, healthyB), 0, "healthy B purchased");
        // (2) the poisoned player did NOT purchase + its slice was refunded.
        assertEq(_lootboxEthBase(idx, poisoned), 0, "poisoned player bought nothing");
        assertEq(
            keeperBefore - ContractAddresses.AF_KING.balance,
            2 ether,
            "only the two healthy slices spent; the poisoned slice refunded (no drain)"
        );
        // (3) implicit: the batch did NOT revert (the drive call above would have reverted otherwise).
    }

    /// @notice Seed 2 / T-331-06 fuzz: wherever the single poisoned player sits in a length-3 keeper
    ///         batch, the batch completes, the two healthy players purchase, the poisoned one is skipped
    ///         + refunded, and the call never reverts — the poison position never bricks the keeper
    ///         batch under the pre-validated path.
    function testFuzz_KeeperBatchPoisonPositionNeverBricks(uint8 poisonSel) public {
        uint256 poisonPos = poisonSel % 3;
        address[] memory players = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint8[] memory modes = new uint8[](3);
        uint256 healthySpend;
        for (uint256 i; i < 3; i++) {
            players[i] = makeAddr(string(abi.encodePacked("kbf_", vm.toString(i), "_", vm.toString(poisonPos))));
            amounts[i] = (i == poisonPos) ? (LOOTBOX_MIN - 1) : 1 ether;
            modes[i] = uint8(MintPaymentKind.DirectEth);
            if (i != poisonPos) healthySpend += amounts[i];
        }

        _driveKeeperBatch(KEEPER_PATH_LANDED, players, amounts, modes); // MUST NOT revert at any position

        uint48 idx = _activeLootboxIndex();
        for (uint256 i; i < 3; i++) {
            if (i == poisonPos) {
                assertEq(_lootboxEthBase(idx, players[i]), 0, "poisoned player skipped regardless of position");
            } else {
                assertGt(_lootboxEthBase(idx, players[i]), 0, "healthy player purchased regardless of position");
            }
        }
        assertEq(
            _lastKeeperBefore - ContractAddresses.AF_KING.balance,
            healthySpend,
            "exactly the poisoned slice refunded at every position (no drain, no brick)"
        );
    }

    /// @dev The keeper-batch no-brick path toggle (mirrors KeeperBatchAffiliateDeltaAudit._drive).
    ///      Funds the keeper, records its pre-balance, then drives EITHER the current `batchPurchase`
    ///      try/catch path or — once KEEPER_PATH_LANDED — the proposed pre-validated
    ///      `batchPurchaseForKeeper`. The SAME no-brick assertions run against whichever path.
    uint256 private _lastKeeperBefore;

    function _driveKeeperBatch(
        bool useKeeperPath,
        address[] memory players,
        uint256[] memory amounts,
        uint8[] memory modes
    ) internal {
        uint256 totalValue;
        for (uint256 i; i < amounts.length; i++) totalValue += amounts[i];
        address keeper = ContractAddresses.AF_KING;
        vm.deal(keeper, totalValue);
        _lastKeeperBefore = keeper.balance;
        if (!useKeeperPath) {
            vm.prank(keeper);
            game.batchPurchase{value: totalValue}(players, amounts, modes); // CURRENT path
        } else {
            // TODO-331-05: call the proposed pre-validated aggregated path here, e.g.
            //   vm.prank(keeper);
            //   game.batchPurchaseForKeeper{value: totalValue}(players, amounts, modes);
            // KEEPER_PATH_LANDED is false until 331-05, so this branch is unreachable today.
            revert("TODO-331-05: batchPurchaseForKeeper not yet landed");
        }
    }

    // =========================================================================
    // Task 2 — reentrancy rollback (no double-buy) + cancel un-brickable
    // =========================================================================

    /// @notice SAFE-02 / T-318-03-02 (reentrancy): a malicious pool holder whose ETH-receive callback
    ///         re-enters withdraw to extract a SECOND payout cannot double-spend. Under the keeper's
    ///         strict CEI (effects-before-interaction) the outer withdraw debits the pool to zero
    ///         BEFORE sending ETH; the re-entrant inner withdraw sees the zeroed pool and reverts
    ///         InsufficientBalance, which the attacker bubbles up, so the outer `.call` sees failure,
    ///         reverts EthSendFailed, and the WHOLE call unwinds. The attacker extracts NOTHING — the
    ///         per-frame debit can never be replayed for a double payout.
    function testReentrantWithdrawCannotDoubleSpend() public {
        ReentrantWithdrawer attacker = new ReentrantWithdrawer(address(afKing));
        uint256 funded = 5 ether;
        vm.deal(address(this), funded);
        afKing.depositFor{value: funded}(address(attacker));
        assertEq(afKing.poolOf(address(attacker)), funded, "attacker pool funded");

        // The re-entrant attack reverts (bubbled InsufficientBalance -> EthSendFailed); the whole
        // outer withdraw unwinds. We assert the outer call reverted.
        vm.expectRevert();
        attacker.attackBubbling(funded);

        // No double-spend: the pool debit fully rolled back (still == funded), and the attacker
        // extracted no ETH — the second (re-entrant) payout was structurally impossible.
        assertEq(afKing.poolOf(address(attacker)), funded, "pool fully restored - no double-spend");
        assertEq(address(attacker).balance, 0, "attacker extracted no ETH via reentrancy");
    }

    /// @notice SAFE-02 (reentrancy, benign single withdraw): a holder whose callback re-enters but
    ///         SWALLOWS the inner revert still receives only ONE payout — the inner withdraw cannot
    ///         add a second. Proves the at-most-once property even when the inner failure is caught.
    function testReentrantWithdrawSwallowedYieldsSinglePayout() public {
        ReentrantWithdrawer attacker = new ReentrantWithdrawer(address(afKing));
        uint256 funded = 4 ether;
        vm.deal(address(this), funded);
        afKing.depositFor{value: funded}(address(attacker));

        // Swallowing the inner revert: the outer withdraw completes once; the re-entry adds nothing.
        attacker.attackSwallowing(funded);

        assertEq(afKing.poolOf(address(attacker)), 0, "pool debited exactly once");
        assertEq(address(attacker).balance, funded, "attacker received exactly one payout, never two");
    }

    /// @notice SAFE-02 / T-318-03-04 (cancel un-brickable): a subscriber can always tombstone its sub
    ///         via setDailyQuantity(0), and afterward its full keeper pool ETH is withdrawable. The
    ///         CEI withdraw cannot be blocked by any downstream interaction.
    function testCancelThenWithdrawAlwaysSucceeds() public {
        // Self-subscribe (player == msg.sender, hasAnyLazyPass(player) is false → paid path, but we
        // fund BURNIE so subscribe succeeds), then deposit pool ETH.
        uint256 poolEth = 3 ether;
        _fundBurnieForSubscribe(player);
        vm.prank(player);
        afKing.subscribe{value: poolEth}(address(0), false, true, 1, 0, address(0));
        assertEq(afKing.poolOf(player), poolEth, "pool credited by subscribe msg.value");

        // Cancel: setDailyQuantity(0) tombstones the sub (un-brickable — no downstream call).
        vm.prank(player);
        afKing.setDailyQuantity(0);
        // Daily quantity is now 0 (paused/tombstoned).
        assertEq(afKing.subscriptionOf(player).dailyQuantity, 0, "sub tombstoned (dailyQuantity 0)");

        // The full pool ETH is withdrawable post-cancel (CEI withdraw, no block).
        uint256 balBefore = player.balance;
        vm.prank(player);
        afKing.withdraw(poolEth);
        assertEq(afKing.poolOf(player), 0, "pool drained after cancel");
        assertEq(player.balance - balBefore, poolEth, "full pool ETH withdrawn post-cancel");
    }

    /// @notice SAFE-02 (cancel un-brickable, fuzz): for any pool balance and any (partial) withdraw
    ///         amount up to it, cancel-then-withdraw succeeds and the remaining pool stays
    ///         withdrawable — cancel never strands ETH.
    function testFuzz_CancelWithdrawNeverStrandsEth(uint96 poolWei, uint96 firstWithdraw) public {
        uint256 poolEth = bound(uint256(poolWei), 1, 100 ether);
        uint256 first = bound(uint256(firstWithdraw), 0, poolEth);

        _fundBurnieForSubscribe(player);
        vm.prank(player);
        afKing.subscribe{value: poolEth}(address(0), false, true, 1, 0, address(0));

        vm.prank(player);
        afKing.setDailyQuantity(0); // cancel — un-brickable

        // First (partial) withdraw, then the remainder; together they drain the whole pool.
        vm.prank(player);
        afKing.withdraw(first);
        uint256 remaining = poolEth - first;
        vm.prank(player);
        afKing.withdraw(remaining);

        assertEq(afKing.poolOf(player), 0, "entire pool withdrawable after cancel (no stranded ETH)");
    }

    // =========================================================================
    // TOMB-04 -- a reclaim/auto-pause/renewal-only chunk COMMITS (didWork)
    // =========================================================================
    //
    // `didWork` (AfKing.sol) tracks whether a buy-less chunk performed in-loop set work (a
    // cancel-tombstone reclaim, an auto-pause, or a window renewal). A chunk that did such work but
    // produced no buy COMMITS the work (0 bounty, no revert) -- reverting would roll the set work back
    // and re-strand the tombstone for griefing across autoBuys. A buy-less chunk returns 0 and never
    // reverts either way, so the unified doWork router can make progress.

    /// @notice TOMB-04 (didWork): an autoBuy chunk that does ONLY a cancel-tombstone reclaim (no
    ///         successful buy -> bounty 0) COMMITS the reclaim and returns 0 without reverting (reverting
    ///         would roll the reclaim back and re-strand the tombstone).
    ///         Here: full-autoBuy the day so every sub is already-autoBought, cancel one (in-place tombstone),
    ///         reset the cursor so the next same-day chunk walks [already-autoBought..., TOMBSTONE,
    ///         already-autoBought...] -> reclaim fires (didWork), no buy. Assert it does NOT revert and the
    ///         tombstone removal PERSISTS after the tx.
    function testReclaimOnlyChunkCommitsNotReverts() public {
        uint256 N = 4;
        address[] memory subs = _setupAutoBuySubs(N, "rco_");

        // Full autoBuy today -> every sub (ours + the 2 deploy subs) is stamped lastAutoBoughtDay = today.
        vm.prank(makeAddr("rco_keeperFull"));
        afKing.autoBuy(afKing.subscriberCount() + 5);

        // Cancel one sub -> in-place tombstone (stays in set, dailyQuantity 0).
        address tomb = subs[2];
        uint256 setLenBefore = afKing.subscriberCount();
        vm.prank(tomb);
        afKing.setDailyQuantity(0);
        assertGt(_afkSubscriberIndexOf(tomb), 0, "tombstone still in set after cancel (in-place)");

        // Reset the cursor to 0 (same day) so the next chunk RE-walks the set: all already-autoBought skips +
        // the one tombstone reclaim. No buyable sub -> batchLen == 0, but didWork (the reclaim) == true.
        _afkResetCursorToZeroForToday();

        vm.recordLogs();
        vm.prank(makeAddr("rco_keeperReclaim"));
        // MUST NOT revert despite 0 buys -- the reclaim's in-loop set work commits (the buy-less chunk
        // no longer reverts; GASOPT-04 / RD-2). The standalone autoBuy is UNREWARDED (no return / no
        // creditFlip — only doWork credits), so there is no bounty to assert here.
        afKing.autoBuy(afKing.subscriberCount() + 5);

        // The reclaim COMMITTED: the tombstone is removed from the set and the SubscriptionExpired(.,2)
        // is in the recorded logs -- state persists after the tx (no rollback).
        assertEq(_afkSubscriberIndexOf(tomb), 0, "reclaim committed: tombstone removed from set");
        assertEq(afKing.subscriberCount(), setLenBefore - 1, "set shrank by the reclaimed tombstone (committed)");
        assertEq(_afkCountExpired(tomb, 2), 1, "reclaim emitted SubscriptionExpired(player,2) and persisted");
    }

    /// @notice TOMB-04 didWork revert-fix: a chunk that does ONLY an auto-pause (a NORMAL sub funding-
    ///         skip kill -> sentinel write + swap-pop + SubscriptionExpired(.,1), AfKing.sol:753-761)
    ///         likewise COMMITS -- no buy, 0 bounty, but the auto-pause state change persists with no
    ///         revert. The two deploy subs in the set are NotApproved-skipped (reason 5, no didWork), so
    ///         this autoBuy's ONLY didWork is the auto-pause: pre-fix it would have hit batchLen==0 ->
    ///         revert and rolled the auto-pause back; the fix commits it. Both the auto-pause and the
    ///         window-renewal branches set didWork identically, so this also covers the renewal-only case.
    function testRenewalOrAutoPauseOnlyChunkCommits() public {
        // A NORMAL sub: approved, ticket mode (no lootbox floor), NOT renewal-due (paidThroughDay >
        // today so the day-31 branch is skipped), but pool EMPTY so the funding-skip kills it.
        address[] memory subs = _setupAutoBuySubs(1, "apo_");
        address sub = subs[0];

        // Drain the pool so msgValue > _poolOf[src] -> the funding-skip auto-pause fires (NORMAL sub).
        uint256 pooled = afKing.poolOf(sub);
        if (pooled > 0) {
            vm.prank(sub);
            afKing.withdraw(pooled);
        }
        assertEq(afKing.poolOf(sub), 0, "pool drained -> funding-skip auto-pause will fire");
        assertGt(_afkDailyQtyOf(sub), 0, "sub is an active NORMAL sub before the autoBuy");

        // This single autoBuy is an auto-pause-only chunk: our pool-empty NORMAL sub funding-skip
        // auto-pauses (didWork, no buy) -> batchLen == 0 but didWork == true -> COMMITS the auto-pause
        // and returns 0 without reverting (reverting would roll the auto-pause back). MUST NOT revert.
        vm.recordLogs();
        vm.prank(makeAddr("apo_keeper"));
        // MUST NOT revert -- the auto-pause set work commits (the buy-less chunk no longer reverts;
        // GASOPT-04 / RD-2). The standalone autoBuy is UNREWARDED (no return / no creditFlip).
        afKing.autoBuy(afKing.subscriberCount() + 5);

        // The auto-pause state change PERSISTED (committed, not rolled back): the sub was swap-popped out
        // of the set and a SubscriptionExpired(sub, 1 = AutoPause) was emitted.
        assertEq(_afkSubscriberIndexOf(sub), 0, "auto-pause committed: sub removed from set (no rollback)");
        assertEq(_afkCountExpired(sub, 1), 1, "auto-pause emitted SubscriptionExpired(player,1) and persisted");
    }

    /// @notice TOMB-04 didWork revert-fix anti-strand: under a spam-cancel griefing scenario -- many
    ///         subs cancel in succession with chunk boundaries landing on reclaim-only work -- EVERY
    ///         tombstone is eventually reclaimed over a full day's autoBuys (none permanently stranded) and
    ///         no still-active sub's daily buy is missed. The combination of (a) the in-place tombstone
    ///         (no relocation) + (b) the didWork commit (reclaim-only chunks persist their removals)
    ///         closes the tombstone-stranding griefing vector.
    function testSpamCancelCannotStrandTombstones() public {
        uint256 N = 8;
        address[] memory subs = _setupAutoBuySubs(N, "spam_");

        // Spam-cancel HALF of them in rapid succession (all in-place tombstones, still in the set, all
        // AHEAD of the cursor since no autoBuy has run yet today).
        for (uint256 i; i < N; i += 2) {
            vm.prank(subs[i]);
            afKing.setDailyQuantity(0);
            assertEq(_afkDailyQtyOf(subs[i]), 0, "spam cancel wrote the in-place sentinel");
            assertGt(_afkSubscriberIndexOf(subs[i]), 0, "tombstone still in set after cancel (in-place)");
        }

        // Drive a full day's autoBuys in moderate chunks. Chunk size 4 always reaches do-work entries past
        // the two front deploy subs (which are NotApproved-skipped), so every chunk that has unprocessed
        // tombstones / buyable subs DOES work and COMMITS (the didWork revert-fix); only a final
        // all-processed chunk legitimately reverts (anti-spam) and is caught. The reclaim branch does not
        // advance the cursor, so a reclaim-heavy chunk keeps making forward progress within the chunk.
        vm.recordLogs();
        for (uint256 round; round < N + 4; round++) {
            vm.prank(makeAddr(string(abi.encodePacked("spam_keeper_", vm.toString(round)))));
            try afKing.autoBuy(4) {} catch {} // a final all-processed chunk may revert (anti-spam); caught
        }

        // Every spam-cancelled tombstone was reclaimed (removed from the set) -- none permanently
        // stranded by the spam-cancel + reclaim-only-chunk commit combination.
        for (uint256 i; i < N; i += 2) {
            assertEq(_afkSubscriberIndexOf(subs[i]), 0, "spam-cancelled tombstone reclaimed (not stranded)");
        }
        // Every still-active sub got its daily buy this day -- the spam-cancel missed no active buy.
        uint32 today = _afkToday();
        for (uint256 i = 1; i < N; i += 2) {
            assertEq(_afkLastAutoBoughtDayOf(subs[i]), today, "active sub bought this day (spam-cancel missed no buy)");
        }
    }

    /// @notice empty-chunk no-op: a genuinely-empty chunk -- no buy, no reclaim, no auto-pause, no
    ///         renewal -- is a NO-OP (a no-buy chunk returns 0, never reverts) so the unified doWork
    ///         router can make progress through an all-already-bought buy leg. Here: full-autoBuy
    ///         so all subs are already-autoBought, then reset the cursor and re-autoBuy with NO tombstone
    ///         present -> every entry is an already-autoBought skip -> the autoBuy succeeds as
    ///         a no-op and stamps NO fresh buy (no double-buy).
    /// @dev    Phase 332: re-prove the no-double-buy / router-progress disposition under doWork.
    function testEmptyChunkIsNoOp() public {
        uint256 N = 3;
        address[] memory subs = _setupAutoBuySubs(N, "empty_");

        // Full autoBuy -> every sub stamped already-autoBought-today.
        vm.prank(makeAddr("empty_keeperFull"));
        afKing.autoBuy(afKing.subscriberCount() + 5);
        uint32 today = _afkToday();
        for (uint256 i; i < N; i++) {
            assertEq(_afkLastAutoBoughtDayOf(subs[i]), today, "all subs stamped already-autoBought-today");
        }

        // Reset the cursor (same day) with NO tombstone in the set -> the re-walk hits only already-
        // autoBought skips (our subs) + NotApproved skips (the deploy subs): no buy, no reclaim, no auto-
        // pause, no renewal. The buy-less chunk is a NO-OP (it no longer reverts) and stamps no fresh buy.
        _afkResetCursorToZeroForToday();
        vm.prank(makeAddr("empty_keeperNoOp"));
        afKing.autoBuy(afKing.subscriberCount() + 5); // MUST NOT revert (empty-chunk no-op)
        for (uint256 i; i < N; i++) {
            assertEq(_afkLastAutoBoughtDayOf(subs[i]), today, "no fresh buy on the empty re-walk (no-op, no double-buy)");
        }
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    function _lvl() internal view returns (uint24) {
        return game.level() + 1;
    }

    /// @dev Prices at the exact same level the crank reward uses (_activeTicketLevel() == level+1),
    ///      via the same library the contract imports — so the reward-peg assertions match.
    function _priceForLevel(uint24 lvl) internal pure returns (uint256) {
        return PriceLookupLib.priceForLevel(lvl);
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions)).
    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    /// @dev Place a degenerette ETH bet engineered to LOSE against FIXED_WORD spin-0 at INDEX.
    function _placeLosingBet(address better) internal returns (uint64 betId) {
        return _placeLosingBetAtIndex(better, INDEX);
    }

    /// @dev Place a LOSING degenerette ETH bet whose resolution keys off `atIndex` (the live daily
    ///      index at placement time). We temporarily point lootboxRngIndex at `atIndex`, place, then
    ///      restore INDEX so subsequent placements land at INDEX. The bet's resolve derivation pins
    ///      to the index recorded in the bet packing, so a bet placed under `atIndex` needs the word
    ///      at `atIndex` to resolve.
    function _placeLosingBetAtIndex(address better, uint48 atIndex) internal returns (uint64 betId) {
        _setLootboxRngIndex(atIndex);
        uint32 customTicket = _losingTicketFor(atIndex, FIXED_WORD);
        uint128 betAmount = 0.01 ether; // >= MIN_BET_ETH
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(address(0), 0, betAmount, 1, customTicket, 0);
        betId = _betNonce(better);
        _setLootboxRngIndex(INDEX); // restore default
    }

    /// @dev Enqueue three REAL lootboxes for (a,b,c) at one fresh daily index via the public mint
    ///      API. Returns the index they share. Each buys a 1-ETH lootbox (>= LOOTBOX_MIN).
    function _enqueueBoxes(address a, address b, address c) internal returns (uint48 idx) {
        idx = _activeLootboxIndex();
        _buyBox(a, 1 ether);
        _buyBox(b, 1 ether);
        _buyBox(c, 1 ether);
    }

    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Set the live daily lootboxRngIndex (low 48 bits of slot 35).
    function _setLootboxRngIndex(uint48 idx) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        packed = (packed & ~uint256(0xFFFFFFFFFFFF)) | uint256(idx);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(packed));
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 36).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Zero lootboxEth[index][player] (slot 15) — leaves lootboxEthBase intact, forcing a
    ///      caught E() revert in openLootBox (amount == 0) without the cheap continue-skip.
    function _zeroLootboxEth(uint48 index, address who) internal {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        vm.store(address(game), leaf, bytes32(uint256(0)));
    }

    function _lootboxEth(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(22))); // lootboxEthBase slot 22 (v47: +3)
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    function _readBetPacked(address owner, uint64 id) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(owner, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 leaf = keccak256(abi.encode(uint256(id), uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    /// @dev Set rngLockedFlag (slot 0 bit 168).
    function _setRngLocked(bool on) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if (on) slot0 |= (uint256(1) << RNG_LOCKED_SHIFT);
        else slot0 &= ~(uint256(1) << RNG_LOCKED_SHIFT);
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    /// @dev Set gameOver (slot 0 bit 184).
    function _setGameOver(bool on) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if (on) slot0 |= (uint256(1) << GAME_OVER_SHIFT);
        else slot0 &= ~(uint256(1) << GAME_OVER_SHIFT);
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    /// @dev Mint enough liquid BURNIE to `who` (via the GAME-gated mintForGame path) to cover one
    ///      all-or-nothing subscribe charge: cost = SUB_COST_ETH_TARGET * PRICE_COIN_UNIT / mintPrice.
    function _fundBurnieForSubscribe(address who) internal {
        uint256 cost = (afKing.SUB_COST_ETH_TARGET() * PRICE_COIN_UNIT) / game.mintPrice();
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, cost + 1 ether);
    }

    function _resultTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        uint256 resultSeed = uint256(keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT)));
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev customTicket matching the result in ZERO quadrants → matches == 0 → clean loss.
    function _losingTicketFor(uint48 index, uint256 word) internal pure returns (uint32 ticket) {
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

    function _countCoinflipStakeUpdated() internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(coinflip) &&
                logs[i].topics.length > 0 &&
                logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG
            ) count++;
        }
    }

    // -------------------------------------------------------------------------
    // AfKing autoBuy helpers (TOMB-04 didWork revert-fix tests)
    // -------------------------------------------------------------------------

    function _afkToday() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Subscribe `n` fully-healthy buying subs to AfKing (ticket mode so no lootbox floor skip,
    ///      operator-approved, pool-funded, NOT renewal-due). Mirrors AfKingConcurrency._setupHealthyBuyingSubs.
    function _setupAutoBuySubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        uint256 cost = (afKing.SUB_COST_ETH_TARGET() * PRICE_COIN_UNIT) / game.mintPrice();
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            subs[i] = who;
            // Liquid BURNIE for the subscribe-time all-or-nothing charge (no lazy pass).
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame(who, cost);
            vm.prank(who);
            afKing.subscribe(address(0), false, true, 1, 0, address(0)); // self, ticket mode, qty 1
            vm.prank(who);
            game.setOperatorApproval(address(afKing), true);
            vm.deal(address(this), 1 ether);
            afKing.depositFor{value: 1 ether}(who);
        }
    }

    function _afkSubscriberIndexOf(address who) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(who, uint256(AFK_SUBSCRIBER_INDEX_SLOT)));
        return uint256(vm.load(address(afKing), slot));
    }

    function _afkDailyQtyOf(address who) internal view returns (uint8) {
        bytes32 slot = keccak256(abi.encode(who, uint256(AFK_SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint8(packed >> (AFK_OFF_DAILY * 8));
    }

    function _afkLastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(AFK_SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> (AFK_OFF_LASTSWEPT * 8));
    }

    /// @dev Force the AfKing autoBuy cursor to 0 while keeping _autoBuyDay == today, so the next autoBuy
    ///      re-walks the set from index 0 this same day. Slot 4: _autoBuyDay (low 4 bytes) + cursor (high).
    function _afkResetCursorToZeroForToday() internal {
        uint256 packed = uint256(vm.load(address(afKing), bytes32(uint256(AFK_SWEEP_PACKED_SLOT))));
        packed &= uint256(0xFFFFFFFF); // keep _autoBuyDay, zero the cursor
        packed |= (uint256(_afkToday()) & 0xFFFFFFFF); // ensure the day-stamp is today
        vm.store(address(afKing), bytes32(uint256(AFK_SWEEP_PACKED_SLOT)), bytes32(packed));
    }

    /// @dev Count SubscriptionExpired(who, reason) emissions from AfKing in the recorded logs. Consumes
    ///      the log buffer (call once after the autoBuy under test).
    function _afkCountExpired(address who, uint8 reason) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(afKing) &&
                logs[i].topics.length >= 2 &&
                logs[i].topics[0] == SUB_EXPIRED_SIG &&
                address(uint160(uint256(logs[i].topics[1]))) == who &&
                uint8(uint256(bytes32(logs[i].data))) == reason
            ) count++;
        }
    }

}

/// @notice A malicious keeper-pool holder whose receive() re-enters AfKing.withdraw, proving the
///         CEI withdraw rolls back a re-entrant double-spend attempt.
contract ReentrantWithdrawer {
    AfKingLike private immutable afk;
    uint256 private reentryAmount;
    bool private reentered;
    bool private bubble; // true = let the inner revert bubble (outer reverts); false = swallow

    constructor(address _afk) {
        afk = AfKingLike(_afk);
    }

    /// @dev Bubbling variant: the inner re-entrant withdraw's revert is NOT caught, so it bubbles
    ///      into the outer withdraw's `.call`, which sees failure -> EthSendFailed -> outer reverts.
    function attackBubbling(uint256 amount) external {
        reentryAmount = amount;
        bubble = true;
        reentered = false;
        afk.withdraw(amount); // reverts (EthSendFailed) when the re-entry bubbles
    }

    /// @dev Swallowing variant: the inner re-entrant withdraw's revert IS caught, so the outer
    ///      withdraw completes a single payout; the re-entry adds nothing.
    function attackSwallowing(uint256 amount) external {
        reentryAmount = amount;
        bubble = false;
        reentered = false;
        afk.withdraw(amount);
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            // Re-enter before the outer frame finishes. Under CEI the pool is already zeroed, so
            // this reverts InsufficientBalance.
            if (bubble) {
                afk.withdraw(reentryAmount); // bubble the revert -> outer .call fails
            } else {
                try afk.withdraw(reentryAmount) {} catch {} // swallow -> outer completes once
            }
        }
    }
}

interface AfKingLike {
    function withdraw(uint256 amount) external;
}
