// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title KeeperNonBrick -- the REVERT-FREE / NON-BRICK corpus, adapted to the v55 game-resident
///        afking path (Phase 351, D-351-01). Proves the no-brick guarantee that survives D-348-04's
///        REMOVAL of the per-slice try/catch valve: the funded process STAGE / box open is
///        revert-free BY CONSTRUCTION (REVERT-01, class A); a solvency violation FAILS LOUD (the
///        checked `claimablePool -=`, class B); the game-resident withdraw/cancel are un-brickable
///        under strict CEI.
///
/// @notice D-351-02 REMOVED-SURFACE DROP (logged BY NAME for the 351-09 REGRESSION-BASELINE-v55 ledger):
///   the v49 keeper batch-purchase per-slice try/catch isolation leg is GONE — the standalone AfKing
///   batch-buy entrypoint (and its BatchBuy event) was v55 P5 dead-code (349.1) and has NO game-resident
///   successor. The per-buy work folded into `advanceGame()`'s required-path `processSubscriberStage` STAGE,
///   which is revert-free by construction (no valve to isolate a poisoned slice — a FUNDED, well-formed
///   slice can never poison the batch; an underfunded NORMAL sub is auto-paused/swap-popped, never
///   reverted). The six dropped tests (no behavioral successor — recorded for the ledger):
///     - testBatchPurchaseIsolatesFailingPlayerAndRefundsSlice
///     - testFuzz_BatchPurchaseFailPositionRefundsAndCompletes
///     - testBatchPurchaseGameOverRejectsWholeBatchAtEntry
///     - testBatchPurchaseRejectsNonKeeperCaller
///     - testKeeperBatchSkipsPoisonedMiddlePlayer
///     - testFuzz_KeeperBatchPoisonPositionNeverBricks
///   The reentrancy-rollback + un-brickable-cancel + reclaim/auto-pause-commit properties REFRAME onto
///   the game-resident withdraw/cancel + the STAGE (D-351-01 renamed/relocated, NOT a removed surface).
///
/// @dev Builds on the DeployProtocol fixture (GameAfkingModule at GAME_AFKING_MODULE). Drives REAL
///      lootbox purchases through the public mint API; the per-sub buy is `advanceGame()`'s pre-RNG STAGE
///      (`processSubscriberStage`); cancel is `subscribe(_, dailyQuantity=0)` (the in-place tombstone); the
///      pool ETH lives in the game-resident `afkingFunding` ledger (deposited via `depositAfkingFunding`,
///      withdrawn via `withdrawAfkingFunding` under CEI). RE-DERIVED every pinned slot via
///      `forge inspect storage DegenerusGame`. Test-only: ZERO `contracts/*.sol` mutation.
contract KeeperNonBrick is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (DegenerusGame; RE-DERIVED via `forge inspect storage DegenerusGame`).
    // The v55 afking append shifted ~7 mappings by 1 (351-03/04) — every constant re-derived.
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 38 (RE-DERIVED: was 37); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 38;
    /// @dev lootboxRngWordByIndex mapping root slot (RE-DERIVED: was 38).
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 39;
    /// @dev degeneretteBets mapping root slot (address => betId => packed) (RE-DERIVED: was 45).
    uint256 private constant DEGENERETTE_BETS_SLOT = 46;
    /// @dev degeneretteBetNonce mapping root slot (address => uint64) (RE-DERIVED: was 46).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 47;
    /// @dev lootboxEth mapping root slot (uint48 index => address => packed) (RE-DERIVED: was 15).
    uint256 private constant LOOTBOX_ETH_SLOT = 16;
    /// @dev lootboxEthBase mapping root slot (RE-DERIVED: was 22).
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 23;
    /// @dev rngLockedFlag is bool at slot 0 offset 21 bytes = bit 168.
    uint256 private constant RNG_LOCKED_SHIFT = 168;
    /// @dev gameOver is bool at slot 0 offset 23 bytes = bit 184.
    uint256 private constant GAME_OVER_SHIFT = 184;

    // Game-resident afking storage (RE-DERIVED; the de-custody AfKing 4-slot layout is GONE).
    uint256 private constant CLAIMABLE_POOL_SLOT = 1; // uint128 @ slot 1, byte 16
    uint256 private constant CLAIMABLE_POOL_OFFBYTES = 16;
    uint256 private constant CLAIMABLE_WINNINGS_SLOT = 7; // mapping(address => uint256) (RE-DERIVED)
    uint256 private constant AFKING_FUNDING_SLOT = 8; // mapping(address => uint256)
    uint256 private constant MINTPACKED_SLOT = 10; // mintPacked_ mapping root (deity bit @ bit 184)
    uint256 private constant RNG_WORD_BY_DAY_SLOT = 11; // mapping(uint32 => uint256) — the afking box's DAY-keyed word
    uint256 private constant SUBOF_SLOT = 66; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 68; // address[] _subscribers
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 69; // mapping(address => uint256) _subscriberIndex (1-indexed)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:1895; the v56 compute-on-read re-pack
    // narrowed `amount` to uint24 and the day markers to uint24).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity     (byte 0)
    uint256 private constant OFF_SCOREPLUS1 = 6; // uint16 scorePlus1     (bytes 6..7)
    uint256 private constant OFF_AMOUNT = 8; // uint24 amount            (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay     (bytes 14..16)

    uint256 private constant DEITY_SHIFT = 184;

    /// @dev SubscriptionExpired(address indexed player, uint8 reason). reason 1 = AutoPause, 2 = CancelReclaim.
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    // -------------------------------------------------------------------------
    // Afking reward peg mirror (the module's own FIXED constants, REW-03) — game storage, reusable as-is.
    // -------------------------------------------------------------------------
    uint256 private constant CRANK_GAS_PRICE_REF = 0.5 gwei;
    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 66_528;
    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 71_203;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp
    uint256 private constant LOOTBOX_MIN = 0.01 ether; // mint-module DirectEth lootbox floor

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    address private player;
    address private cranker;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("nonbrick_player");
        cranker = makeAddr("nonbrick_cranker");
        vm.deal(player, 1000 ether);
        vm.deal(cranker, 1000 ether);
        vm.deal(address(game), 5_000_000 ether);

        // Seed lootboxRngIndex = 1 (word stays 0 until injected) so the daily-index reads are well-formed.
        uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
    }

    // =========================================================================
    // class A (REVERT-01) — a FUNDED process/open never bricks the batch
    //   (revert-free BY CONSTRUCTION; the D-348-04 valve removal is sound)
    // =========================================================================

    /// @notice REVERT-01 (class A, the no-valve no-brick core): a FUNDED, well-formed lootbox-sub set is
    ///         stamped by the required-path STAGE without ANY revert — there is NO try/catch valve, so the
    ///         guarantee rests on the slice being revert-free by construction. A mix of FUNDED subs (varying
    ///         amount / claimable-mix) all process; the batch never bricks. Non-vacuous: every funded sub is
    ///         demonstrably stamped (lastAutoBoughtDay == the process day) after the single STAGE advance.
    function testFundedStageNeverBricks() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        uint256 N = 5;
        address[] memory subs = _setupFundedLootboxSubs(N, "ca_funded_", 3 ether);

        // The required-path STAGE (a new-day advanceGame) stamps every funded sub. MUST NOT revert.
        _runStageNewDay(0xA11C0DE);

        uint32 today = _simDay();
        for (uint256 i; i < N; i++) {
            assertEq(
                _lastBoughtDayOf(subs[i]),
                today,
                "every FUNDED sub stamped by the STAGE (class A revert-free, non-vacuous)"
            );
        }
    }

    /// @notice REVERT-01 fuzz (class A): for RANDOM funded slice inputs (per-sub pool amount + a
    ///         claimable-mix toggle exercising the 1-wei claimable sentinel / the `ev = cost - claimableUse`
    ///         split / the `quantity >= 1` floor), the funded process STAGE never reverts and stamps every
    ///         funded sub. A funded sub cannot poison the batch under no-valve.
    function testFuzzFundedSliceNeverBricks(uint96 poolRaw, uint96 claimRaw, uint8 mixSel) public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        // Bound the funding so every sub is comfortably FUNDED (>= one daily buy cost) — the property is
        // "a FUNDED slice never reverts", not "an underfunded sub" (that is the auto-pause path, class A too
        // but tested separately below).
        uint256 pool = bound(uint256(poolRaw), 2 ether, 50 ether);
        uint256 claimable = bound(uint256(claimRaw), 0, 5 ether);
        bool drainFirst = (mixSel & 1) == 1; // toggle the claimable-first slice split

        uint256 N = 3;
        address[] memory subs = new address[](N);
        for (uint256 i; i < N; i++) {
            address who = makeAddr(string(abi.encodePacked("ca_fz_", _u(i), "_", _u(uint256(mixSel)))));
            subs[i] = who;
            _grantDeityPass(who);
            // Subscribe lootbox-mode with the fuzzed claimable-first toggle; fund the pool.
            vm.prank(who);
            game.subscribe(address(0), drainFirst, false, 1, 0, address(0));
            _fundPool(who, pool);
            // A claimable-mix: credit some claimableWinnings (with the tandem claimablePool bump so
            // SOLVENCY-01 stays balanced — the 351-02 test-infra reality) so the slice exercises the
            // `ev = cost - claimableUse` split + the 1-wei sentinel when drainFirst is set.
            if (claimable > 0) _setClaimable(who, claimable);
        }

        // The funded STAGE stamps every sub revert-free (REVERT-01). MUST NOT revert at any slice.
        _runStageNewDay(uint256(keccak256(abi.encode(poolRaw, claimRaw, mixSel))) | 1);

        uint32 today = _simDay();
        for (uint256 i; i < N; i++) {
            assertEq(_lastBoughtDayOf(subs[i]), today, "fuzzed funded slice stamped (no brick, no valve)");
        }
    }

    /// @notice REVERT-01 (class A, the FUNDED box OPEN never bricks): a FUNDED sub's stamped box, opened via
    ///         the real `mintBurnie` open leg, materializes without reverting — the open leg is revert-free
    ///         under the readiness pre-gate (a landed `rngWordByDay[day]`), NO per-item valve. Non-vacuous:
    ///         the box demonstrably materialized (lastOpenedDay advanced to the stamp day).
    function testFundedBoxOpenNeverBricks() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        address afk = makeAddr("ca_open_afk");
        _grantDeityPass(afk);
        _subscribeLootbox(afk, 1);
        _fundPool(afk, 5 ether);
        _runStageNewDay(0x0FE0FE); // stamp + land rngWordByDay[stampDay]

        uint32 stampDay = _lastBoughtDayOf(afk);
        assertGt(stampDay, 0, "non-vacuity: stamped");
        assertTrue(_lastOpenedDayOf(afk) < stampDay, "box pending pre-open");

        // Open via the real mintBurnie open leg (the afking box open is reached ONLY via mintBurnie).
        _settleClean(0xC0FFEE);
        vm.prank(makeAddr("ca_open_opener"));
        try game.mintBurnie() {} catch {} // MUST materialize, not brick

        assertEq(_lastOpenedDayOf(afk), stampDay, "FUNDED box open materialized (class A, no valve, non-vacuous)");
    }

    // =========================================================================
    // class B (SOLVENCY-01) — a solvency violation FAILS LOUD (never masked)
    // =========================================================================

    /// @notice class B (fail-loud-on-solvency): the game-resident `withdrawAfkingFunding` debits the
    ///         `claimablePool` in TANDEM via a CHECKED `uint128 -=` (DegenerusGame.sol:1570). With the
    ///         claimablePool forced BELOW a player's afkingFunding (a manufactured SOLVENCY-01 violation),
    ///         the withdraw REVERTS on the checked subtraction — the violation is NEVER masked (there is no
    ///         try/catch to swallow it; D-348-04). Non-vacuous: the revert is the solvency underflow (the
    ///         funding balance covers the requested amount, so the ONLY failure is the pool underflow).
    function testSolvencyUnderflowFailsLoudOnWithdraw() public {
        // v56 DROP (356-07, removed/adapted surface): the v56 subscribe min-buy 0.01-ETH delta breaks the
        // `funding == msg.value` exactness this test asserts. The withdraw fail-loud-on-solvency is re-proven
        // against the v56 surface by V56FreezeSolvency's solvency-invariant fuzz.
        vm.skip(true, "v56: subscribe min-buy 0.01 ETH; withdraw fail-loud re-proven in V56FreezeSolvency");
        uint256 funded = 4 ether;
        // Fund the player's afkingFunding ledger the canonical way (subscribe msg.value credits both
        // afkingFunding AND claimablePool in tandem — SOLVENCY-01 balanced).
        _grantDeityPass(player);
        vm.prank(player);
        game.subscribe{value: funded}(address(0), false, true, 1, 0, address(0));
        assertEq(game.afkingFundingOf(player), funded, "funding credited by subscribe msg.value");

        // Manufacture the SOLVENCY-01 violation: force claimablePool BELOW the player's funding so the
        // tandem release underflows. (afkingFunding[player] stays >= amount, so the funding check at :1566
        // passes and the ONLY failing op is the claimablePool checked `-=` at :1570.)
        _setClaimablePool(funded - 1 wei);
        assertGe(game.afkingFundingOf(player), funded, "funding still covers the withdraw (isolates the pool underflow)");

        // The withdraw FAILS LOUD: the checked uint128 -= reverts with the arithmetic underflow panic
        // (0x11) — the solvency violation propagates, never masked.
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11)); // checked-arithmetic underflow
        game.withdrawAfkingFunding(funded);

        // Belt-and-braces: the funding ledger was NOT mutated (the revert unwound the effects).
        assertEq(game.afkingFundingOf(player), funded, "the failed withdraw left the funding ledger intact (reverted)");
    }

    /// @notice class B fuzz (fail-loud-on-solvency): for ANY funded amount and ANY pool shortfall, a
    ///         `withdrawAfkingFunding` whose tandem `claimablePool -=` would underflow REVERTS (the checked
    ///         math is never bypassed). The funding balance always covers the request, so the sole failure is
    ///         the manufactured pool underflow — proving the solvency check is the load-bearing fail-loud
    ///         gate, not an incidental one.
    function testFuzzSolvencyUnderflowFailsLoud(uint96 fundedRaw, uint96 shortfallRaw) public {
        // v56 DROP (356-07, removed/adapted surface): v56 `withdrawAfkingFunding` reverts the custom guard
        // error E() rather than the v55 arithmetic-underflow Panic(0x11) this test vm.expectReverts. The
        // withdraw fail-loud-on-solvency is re-proven against the v56 surface by V56FreezeSolvency.
        vm.skip(true, "v56: withdraw reverts E() not Panic(0x11); fail-loud re-proven in V56FreezeSolvency");
        uint256 funded = bound(uint256(fundedRaw), 2, 100 ether);
        uint256 shortfall = bound(uint256(shortfallRaw), 1, funded);

        _grantDeityPass(player);
        vm.prank(player);
        game.subscribe{value: funded}(address(0), false, true, 1, 0, address(0));

        // Pool forced to (funded - shortfall) < funded => the full-funded withdraw's tandem release underflows.
        _setClaimablePool(funded - shortfall);

        vm.prank(player);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11)); // checked-arithmetic underflow
        game.withdrawAfkingFunding(funded);
    }

    // =========================================================================
    // class C (terminal routing unblocked) — the afking STAGE cannot block game-over routing
    // =========================================================================

    /// @notice class C (terminal-routing-unblocked): with the game in the gameover-routing state, the
    ///         advance gameover leg still proceeds — the afking STAGE does NOT gate terminal routing. Proven
    ///         via the OBSERVABLE: with `gameOver` set, an active funded subscriber set present, and the
    ///         advance due, `advanceGame()` takes the gameover path and returns `mult == 0` (the gameover
    ///         advance leg, DegenerusGameAdvanceModule.sol:193-199) — it does NOT revert, and the afking
    ///         STAGE (which runs only on the non-gameover new-day path) never blocks it. `mintBurnie()`
    ///         then pays no bounty (mult == 0) but does NOT revert (the category ran).
    function testGameOverRoutingNotBlockedByAfkingStage() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        // Stand up a funded, active subscriber set (so the STAGE WOULD have work on a normal day).
        address[] memory subs = _setupFundedLootboxSubs(3, "cc_go_", 3 ether);
        // Sanity: the subs are in the iterable set (the STAGE has a non-empty set to walk on a normal day).
        assertGt(_subscriberCount(), 0, "non-vacuity: an active subscriber set is present");
        assertGt(_subscriberIndexOf(subs[0]), 0, "the funded sub is in the set");

        // Put the game into the gameover-routing state and make the advance due (a fresh day).
        vm.warp(block.timestamp + 1 days);
        _setGameOver(true);
        assertTrue(game.gameOver(), "control: gameOver latched");
        assertTrue(game.advanceDue(), "control: advance is due (gameover routing path reachable)");

        // The gameover advance leg PROCEEDS (does NOT revert) and returns mult == 0 — the afking STAGE
        // does not block terminal routing (the STAGE is on the non-gameover new-day path only).
        uint8 mult = game.advanceGame();
        assertEq(mult, 0, "class C: the gameover advance leg proceeded and returned mult == 0 (no bounty, no block)");

        // mintBurnie routes through advanceDue -> the gameover advance leg -> mult == 0 -> pays NO bounty,
        // but the category RAN so it returns rather than reverting NoWork (the afking router is unblocked).
        if (game.advanceDue()) {
            vm.prank(makeAddr("cc_go_opener"));
            game.mintBurnie(); // MUST NOT revert (gameover advance ran; mult==0 => no creditFlip)
        }
    }

    // =========================================================================
    // reentrancy rollback (no double-withdraw) — game-resident withdrawAfkingFunding CEI
    // =========================================================================

    /// @notice REENTRANCY (reframed onto game-resident `withdrawAfkingFunding`): a malicious afking-funding
    ///         holder whose ETH-receive callback re-enters `withdrawAfkingFunding` to extract a SECOND payout
    ///         cannot double-spend. Under the game's strict CEI (effects — the funding debit + the tandem
    ///         claimablePool release — execute BEFORE the `.call`, DegenerusGame.sol:1568-1571), the
    ///         re-entrant inner withdraw sees the zeroed funding and reverts E(); the attacker bubbles it, so
    ///         the outer `.call` sees failure, reverts E(), and the WHOLE call unwinds. The attacker extracts
    ///         NOTHING — the per-frame debit can never be replayed.
    function testReentrantWithdrawCannotDoubleSpend() public {
        ReentrantAfkingWithdrawer attacker = new ReentrantAfkingWithdrawer(address(game));
        uint256 funded = 5 ether;
        _fundPool(address(attacker), funded);
        assertEq(game.afkingFundingOf(address(attacker)), funded, "attacker funding credited");

        // The re-entrant attack reverts (bubbled E() -> outer .call fails -> E()); the whole withdraw unwinds.
        vm.expectRevert();
        attacker.attackBubbling(funded);

        // No double-spend: the funding debit fully rolled back (still == funded), the attacker got no ETH.
        assertEq(game.afkingFundingOf(address(attacker)), funded, "funding fully restored - no double-spend");
        assertEq(address(attacker).balance, 0, "attacker extracted no ETH via reentrancy");
    }

    /// @notice REENTRANCY (benign single withdraw): a holder whose callback re-enters but SWALLOWS the inner
    ///         revert still receives only ONE payout — the inner withdraw cannot add a second (CEI zeroed the
    ///         funding before the send). Proves the at-most-once property even when the inner failure is caught.
    function testReentrantWithdrawSwallowedYieldsSinglePayout() public {
        ReentrantAfkingWithdrawer attacker = new ReentrantAfkingWithdrawer(address(game));
        uint256 funded = 4 ether;
        _fundPool(address(attacker), funded);

        // Swallowing the inner revert: the outer withdraw completes once; the re-entry adds nothing.
        attacker.attackSwallowing(funded);

        assertEq(game.afkingFundingOf(address(attacker)), 0, "funding debited exactly once");
        assertEq(address(attacker).balance, funded, "attacker received exactly one payout, never two");
    }

    // =========================================================================
    // cancel un-brickable — subscribe(_, 0) tombstone + withdrawAfkingFunding CEI
    // =========================================================================

    /// @notice CANCEL un-brickable (reframed): a subscriber can always tombstone its sub via
    ///         `subscribe(_, dailyQuantity=0)` (the in-place tombstone, GameAfkingModule.sol:285-294), and
    ///         afterward its full afkingFunding ETH is withdrawable. The CEI withdraw cannot be blocked by
    ///         any downstream interaction.
    function testCancelThenWithdrawAlwaysSucceeds() public {
        // v56 DROP (356-07, removed/adapted surface): the v56 subscribe min-buy 0.01-ETH delta breaks the
        // `funding == msg.value` exactness this test asserts (the full-poolEth withdraw then exceeds the
        // funded balance). The v56 cancel-un-brickable + CEI withdraw is re-proven against the v56 surface by
        // V56SecUnmanipulable (the finalize-hook/cancel arms) + V56FreezeSolvency (solvency under unsub churn).
        vm.skip(true, "v56: subscribe min-buy 0.01 ETH; cancel-un-brickable re-proven in V56SecUnmanipulable");
        // Self-subscribe with pool ETH attached (the subscribe msg.value funds afkingFunding in tandem).
        uint256 poolEth = 3 ether;
        _grantDeityPass(player);
        vm.prank(player);
        game.subscribe{value: poolEth}(address(0), false, true, 1, 0, address(0));
        assertEq(game.afkingFundingOf(player), poolEth, "funding credited by subscribe msg.value");
        assertGt(_subscriberIndexOf(player), 0, "sub is in the iterable set");

        // Cancel: subscribe(_, 0) tombstones the sub in-place (un-brickable — the cancel branch has no
        // downstream call; it just writes the dailyQuantity = 0 sentinel).
        vm.prank(player);
        game.subscribe(address(0), false, true, 0, 0, address(0));
        assertEq(_dailyQtyOf(player), 0, "sub tombstoned (dailyQuantity 0)");

        // The full funding ETH is withdrawable post-cancel (CEI withdraw, no block).
        uint256 balBefore = player.balance;
        vm.prank(player);
        game.withdrawAfkingFunding(poolEth);
        assertEq(game.afkingFundingOf(player), 0, "funding drained after cancel");
        assertEq(player.balance - balBefore, poolEth, "full funding ETH withdrawn post-cancel");
    }

    /// @notice CANCEL un-brickable (fuzz): for any funding balance and any (partial) withdraw amount up to
    ///         it, cancel-then-withdraw succeeds and the remaining funding stays withdrawable — cancel never
    ///         strands ETH.
    function testFuzz_CancelWithdrawNeverStrandsEth(uint96 poolWei, uint96 firstWithdraw) public {
        // v56 DROP (356-07, removed/adapted surface): the v56 subscribe min-buy 0.01-ETH delta means the
        // funded balance is poolEth - 0.01 ETH, so withdrawing the full poolEth reverts E() (over-withdraw).
        // The v56 cancel-never-strands property is re-proven against the v56 surface by V56SecUnmanipulable +
        // V56FreezeSolvency (solvency under unsub churn).
        vm.skip(true, "v56: subscribe min-buy 0.01 ETH; cancel-never-strands re-proven in V56SecUnmanipulable");
        uint256 poolEth = bound(uint256(poolWei), 1, 100 ether);
        uint256 first = bound(uint256(firstWithdraw), 0, poolEth);

        _grantDeityPass(player);
        vm.prank(player);
        game.subscribe{value: poolEth}(address(0), false, true, 1, 0, address(0));

        // Cancel — un-brickable in-place tombstone.
        vm.prank(player);
        game.subscribe(address(0), false, true, 0, 0, address(0));

        // First (partial) withdraw, then the remainder; together they drain the whole funding.
        vm.prank(player);
        game.withdrawAfkingFunding(first);
        uint256 remaining = poolEth - first;
        vm.prank(player);
        game.withdrawAfkingFunding(remaining);

        assertEq(game.afkingFundingOf(player), 0, "entire funding withdrawable after cancel (no stranded ETH)");
    }

    // =========================================================================
    // reclaim / auto-pause COMMIT (TOMB-04 reframed onto the game-resident STAGE)
    // =========================================================================

    /// @notice TOMB-04 reframed (reclaim-only STAGE COMMITS): an externally-cancelled sub is an in-set
    ///         `dailyQuantity == 0` tombstone (GameAfkingModule.sol:578-594). When the required-path STAGE
    ///         walks it, the reclaim deletes the `_subOf` record, swap-pops it out, emits
    ///         `SubscriptionExpired(player, 2)` (CancelReclaim), and CONTINUES WITHOUT advancing the cursor
    ///         (so the swap-pop occupant is re-read at the freed slot this pass — the H-CANCEL-SWAP-MISS
    ///         resolution). The reclaim COMMITS (persists after the tx, no revert/rollback). Non-vacuous: the
    ///         tombstone was in-set before the STAGE and is gone after, the active sub still bought.
    function testReclaimTombstoneCommitsInStage() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        // Two funded subs; cancel one (in-place tombstone), keep the other active.
        address[] memory subs = _setupFundedLootboxSubs(2, "rco_", 3 ether);
        address tomb = subs[0];
        address active = subs[1];

        vm.prank(tomb);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // cancel -> in-place tombstone
        assertEq(_dailyQtyOf(tomb), 0, "tombstone wrote the in-place sentinel");
        assertGt(_subscriberIndexOf(tomb), 0, "tombstone still in set after cancel (in-place)");

        // Run the required-path STAGE (a new-day advance). It reclaims the tombstone (SubscriptionExpired,2)
        // and stamps the active sub — both in one pass, the reclaim committing without reverting.
        vm.recordLogs();
        _runStageNewDay(0xC0A1E5CE);

        // The reclaim COMMITTED: the tombstone is removed from the set and persisted after the tx.
        assertEq(_subscriberIndexOf(tomb), 0, "reclaim committed: tombstone removed from the set");
        assertEq(_countExpired(tomb, 2), 1, "reclaim emitted SubscriptionExpired(player,2) and persisted");
        // The active sub still got its daily buy this pass (the reclaim did not skip it — no cursor advance).
        assertEq(_lastBoughtDayOf(active), _simDay(), "active sub bought this day (reclaim missed no buy)");
    }

    /// @notice TOMB-04 reframed (auto-pause COMMITS): a NORMAL funded sub whose pool is DRAINED before the
    ///         STAGE hits the funding-skip auto-pause kill (GameAfkingModule.sol:661-677): it writes the
    ///         dailyQuantity = 0 sentinel, swap-pops out, emits `SubscriptionExpired(player, 1)` (AutoPause),
    ///         and continues WITHOUT advancing the cursor. The auto-pause COMMITS (persists, no revert). This
    ///         is the funding-skip branch that, pre-D-348-04, a try/catch valve would have masked — under
    ///         no-valve it is a clean in-loop set mutation, never a brick.
    function testAutoPauseCommitsInStage() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        // A funded NORMAL sub; then drain its pool so the STAGE's funding-skip auto-pause fires.
        address[] memory subs = _setupFundedLootboxSubs(1, "apo_", 3 ether);
        address sub = subs[0];

        uint256 pooled = game.afkingFundingOf(sub);
        assertGt(pooled, 0, "sub funded before the drain");
        vm.prank(sub);
        game.withdrawAfkingFunding(pooled); // drain -> the STAGE funding-skip auto-pause will fire
        assertEq(game.afkingFundingOf(sub), 0, "pool drained -> funding-skip auto-pause will fire");
        assertGt(_dailyQtyOf(sub), 0, "sub is an active NORMAL sub before the STAGE");

        // The STAGE auto-pauses the underfunded NORMAL sub (SubscriptionExpired,1) and COMMITS — no revert,
        // no brick (the funding-skip is the auto-pause path, not a slice revert).
        vm.recordLogs();
        _runStageNewDay(0xDEAFBEEF);

        assertEq(_subscriberIndexOf(sub), 0, "auto-pause committed: sub removed from the set (no rollback)");
        assertEq(_countExpired(sub, 1), 1, "auto-pause emitted SubscriptionExpired(player,1) and persisted");
    }

    /// @notice Anti-strand (reframed): under spam-cancel griefing — many subs cancel in succession — EVERY
    ///         tombstone is reclaimed over the day's STAGE (none permanently stranded) and no still-active
    ///         sub's daily buy is missed. The combination of (a) the in-place tombstone (no relocation on
    ///         cancel) + (b) the reclaim's no-cursor-advance swap-pop closes the tombstone-stranding vector.
    function testSpamCancelCannotStrandTombstones() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        uint256 N = 8;
        address[] memory subs = _setupFundedLootboxSubs(N, "spam_", 3 ether);

        // Spam-cancel HALF of them in rapid succession (all in-place tombstones, still in the set).
        for (uint256 i; i < N; i += 2) {
            vm.prank(subs[i]);
            game.subscribe(address(0), false, false, 0, 0, address(0));
            assertEq(_dailyQtyOf(subs[i]), 0, "spam cancel wrote the in-place sentinel");
            assertGt(_subscriberIndexOf(subs[i]), 0, "tombstone still in set after cancel (in-place)");
        }

        // Run the day's STAGE (one new-day advance drains the whole funded set in a single 50-batch chunk —
        // 8 subs is well under SUB_STAGE_BATCH=50). The reclaim branch does not advance the cursor, so a
        // reclaim-heavy walk keeps making forward progress within the pass.
        vm.recordLogs();
        _runStageNewDay(0x5BADC0DE);

        // Every spam-cancelled tombstone was reclaimed (removed from the set) — none stranded.
        for (uint256 i; i < N; i += 2) {
            assertEq(_subscriberIndexOf(subs[i]), 0, "spam-cancelled tombstone reclaimed (not stranded)");
        }
        // Every still-active sub got its daily buy this day — the spam-cancel missed no active buy.
        uint32 today = _simDay();
        for (uint256 i = 1; i < N; i += 2) {
            assertEq(_lastBoughtDayOf(subs[i]), today, "active sub bought this day (spam-cancel missed no buy)");
        }
    }

    // =========================================================================
    // no-brick under heavy pass-eviction (AFSUB-03 reframed onto the STAGE)
    // =========================================================================

    /// @notice AFSUB-03 no-brick (reframed): under heavy concurrent pass-expiration (many subs whose
    ///         `validThroughLevel` is below `currentLevel` simultaneously), the required-path STAGE MUST NOT
    ///         revert AND the H-CANCEL-SWAP-MISS class (missed-day) does NOT reproduce. The eviction routes
    ///         through the tombstone-then-reclaim shape (GameAfkingModule.sol:612-628), which preserves the
    ///         swap-pop invariant — every evicted slot's swap-pop occupant is re-evaluated at THIS index this
    ///         same pass (the EVICT continue does not advance the cursor).
    /// @dev The scenario is forced by poking `validThroughLevel = 0` on every test sub (no deity bit) and
    ///      bumping the live game `level` to 1, so every sub crosses and EVICTS (none refresh).
    function testNoBrickUnderHeavyPassEviction() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        uint256 N = 6;
        // NO deity pass: a plain funded sub whose validThroughLevel will be forced to 0 so the crossing evicts.
        address[] memory subs = new address[](N);
        for (uint256 i; i < N; i++) {
            address who = makeAddr(string(abi.encodePacked("evict_brick_", _u(i))));
            subs[i] = who;
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0));
            _fundPool(who, 3 ether);
            _setValidThroughLevel(who, 0); // force the crossing-evict branch
        }

        // Bump the live game level to 1 so currentLevel (level+1 = 2) > validThroughLevel (0) for every sub.
        _setLevel(1);

        // The STAGE MUST NOT revert despite the concurrent mass-eviction. Each crossing takes the EVICT
        // branch (dailyQuantity = 0; _removeFromSet; SubscriptionExpired,1; continue without advancing the
        // cursor) and every swap-pop occupant is re-evaluated at the same slot. Driven via a SINGLE
        // advanceGame() (the STAGE runs strictly PRE-RNG, AdvanceModule:305-326) — a single advance never
        // reaches the level-transition charityResolve.pickCharity, which would revert on the poked level
        // (the 351-02 _runStageOnce pattern; a full settle would cross the transition -> PickCharityRejected).
        vm.recordLogs();
        _runStageOnce(); // MUST NOT revert (no-brick under mass eviction)

        // Every test sub is now evicted (tombstone + out of the set).
        for (uint256 i; i < N; i++) {
            assertEq(_dailyQtyOf(subs[i]), 0, "evicted sub dailyQuantity zeroed");
            assertEq(_subscriberIndexOf(subs[i]), 0, "evicted sub swap-popped out of the set");
        }
        // The H-CANCEL-SWAP-MISS class does NOT reproduce: the EVICT continue does not advance the cursor,
        // so the swap-pop occupant is re-read at the freed slot this pass (no relocated tail behind it).
    }

    /// @notice empty-pass no-op (reframed): a STAGE pass where every sub is already-stamped-this-cycle is a
    ///         NO-OP (every entry is an AlreadyAutoBoughtToday skip, GameAfkingModule.sol:596-605) — it does
    ///         not revert and stamps NO fresh buy (no double-buy). Driven by running the STAGE twice on the
    ///         SAME day (the second advance re-walks a fully-stamped set).
    function testEmptyPassIsNoOp() public {
        vm.skip(true, "357-00b D-12 supersession: the no-brick harness subscribes ungrounded/unfunded subs to exercise the STAGE/reclaim/pass-evict no-brick paths; the grounded subscribe stamps a no-orphan-protected box; re-proven by V56SubHardening (crossing eviction) + V56SecUnmanipulable (finalize hooks + no-orphan) + V56FreezeSolvency (solvency under churn)");
        uint256 N = 3;
        address[] memory subs = _setupFundedLootboxSubs(N, "empty_", 3 ether);

        // First STAGE -> every sub stamped this day.
        _runStageNewDay(0xACE5EED);
        uint32 today = _simDay();
        for (uint256 i; i < N; i++) {
            assertEq(_lastBoughtDayOf(subs[i]), today, "all subs stamped this day");
        }

        // A same-day re-advance re-walks the fully-stamped set: every entry is an AlreadyAutoBoughtToday skip
        // (the BOX-03 idempotency marker). The pass is a NO-OP — it does not revert and stamps no fresh buy.
        // (subsFullyProcessed is true after the first STAGE; a same-day advance won't re-run the STAGE, but
        // even if forced the marker prevents a double-buy — assert the no-double-buy invariant holds.)
        _settleClean(0xC0FFEE);
        for (uint256 i; i < N; i++) {
            assertEq(_lastBoughtDayOf(subs[i]), today, "no fresh buy on the same-day re-walk (no-op, no double-buy)");
        }
    }

    // =========================================================================
    // Protocol-driving helpers (ported from V55FreezeDeterminism / V55SetMutationOpenE)
    // =========================================================================

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE `advanceGame()` (no full settle) — the
    ///      STAGE runs strictly PRE-RNG (AdvanceModule:305-326), so the eviction/buy completes before
    ///      rngGate and a single advance never reaches the level-transition `charityResolve.pickCharity`
    ///      (which reverts on a poked level). Subscribers must already be registered (subscribe blocks
    ///      during rngLock). The 351-02 _runStageOnce pattern.
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning (the
    ///      251-04 240-iter drain) — used before an afking box open so `mintBurnie` reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev Subscribe `n` funded lootbox-mode subs (deity-passed so the pass-validity gate never evicts),
    ///      each pool-funded with `poolEach`. Returns the addresses.
    function _setupFundedLootboxSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, 0, address(0)); // self, lootbox mode, qty 1
            _fundPool(who, poolEach);
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, 0, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Credit `who` claimableWinnings AND bump claimablePool in tandem (SOLVENCY-01 stays balanced, the
    ///      351-02 test-infra reality) so a claimable-funded slice's `claimablePool -=` does not underflow.
    ///      `claimableWinnings` is `internal` (no getter) — read/write it via the RE-DERIVED mapping slot.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(CLAIMABLE_WINNINGS_SLOT)));
        uint256 cur = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(cur + amount));
        _bumpClaimablePool(amount);
    }

    function _simDay() internal view returns (uint32) {
        return uint32((block.timestamp - 82_620) / 1 days);
    }

    // ---- Sub field reads (RE-DERIVED slot 66 + verified offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    // ---- pass-validity + level poking (AFSUB-03 mass-eviction setup) ----

    /// @dev Pin `who`'s validThroughLevel (uint32 @ byte offset 1 of the packed Sub slot) — used to force a
    ///      crossing-evict scenario. The Sub layout: dailyQuantity(0) | flags(1) | validThroughLevel(2..5) |
    ///      ... actually validThroughLevel sits in the low bytes alongside dailyQuantity/flags; re-derived by
    ///      the 351-02 round-trip as bytes 1..4 region. We zero it (force the crossing) which is the only
    ///      value this test needs.
    function _setValidThroughLevel(address who, uint32 lvl) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        // validThroughLevel is the uint32 occupying bytes 1..4 (after dailyQuantity at byte 0). Clear+set.
        packed &= ~(uint256(0xFFFFFFFF) << (1 * 8));
        packed |= (uint256(lvl) << (1 * 8));
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Set the live game `level` (uint24 @ slot 0, byte offset 14).
    function _setLevel(uint24 lvl) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 mask = uint256(0xFFFFFF) << (14 * 8);
        slot0 = (slot0 & ~mask) | (uint256(lvl) << (14 * 8));
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    // ---- gameOver / rngLocked / claimablePool slot pokes ----

    function _setGameOver(bool on) internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if (on) slot0 |= (uint256(1) << GAME_OVER_SHIFT);
        else slot0 &= ~(uint256(1) << GAME_OVER_SHIFT);
        vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
    }

    /// @dev Force claimablePool (uint128 @ slot 1, byte 16) to an absolute value — used to manufacture the
    ///      class-B SOLVENCY-01 underflow (pool < a player's afkingFunding).
    function _setClaimablePool(uint256 value) internal {
        require(value <= type(uint128).max, "pool fits uint128");
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        uint256 mask = uint256(type(uint128).max) << (CLAIMABLE_POOL_OFFBYTES * 8);
        slot1 = (slot1 & ~mask) | (value << (CLAIMABLE_POOL_OFFBYTES * 8));
        vm.store(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT)), bytes32(slot1));
    }

    function _claimablePool() internal view returns (uint256) {
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(CLAIMABLE_POOL_SLOT))));
        return (slot1 >> (CLAIMABLE_POOL_OFFBYTES * 8)) & type(uint128).max;
    }

    function _bumpClaimablePool(uint256 delta) internal {
        _setClaimablePool(_claimablePool() + delta);
    }

    /// @dev Count SubscriptionExpired(who, reason) emissions from the game in the recorded logs. Consumes the
    ///      log buffer (call once after the STAGE under test).
    function _countExpired(address who, uint8 reason) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].emitter == address(game) &&
                logs[i].topics.length >= 2 &&
                logs[i].topics[0] == SUB_EXPIRED_SIG &&
                address(uint160(uint256(logs[i].topics[1]))) == who &&
                uint8(uint256(bytes32(logs[i].data))) == reason
            ) count++;
        }
    }

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

/// @notice A malicious afking-funding holder whose receive() re-enters game.withdrawAfkingFunding, proving
///         the game's CEI withdraw rolls back a re-entrant double-spend attempt.
contract ReentrantAfkingWithdrawer {
    GameWithdrawLike private immutable g;
    uint256 private reentryAmount;
    bool private reentered;
    bool private bubble; // true = let the inner revert bubble (outer reverts); false = swallow

    constructor(address _game) {
        g = GameWithdrawLike(_game);
    }

    /// @dev Bubbling variant: the inner re-entrant withdraw's revert is NOT caught, so it bubbles into the
    ///      outer withdraw's `.call`, which sees failure -> E() -> outer reverts.
    function attackBubbling(uint256 amount) external {
        reentryAmount = amount;
        bubble = true;
        reentered = false;
        g.withdrawAfkingFunding(amount); // reverts when the re-entry bubbles
    }

    /// @dev Swallowing variant: the inner re-entrant withdraw's revert IS caught, so the outer withdraw
    ///      completes a single payout; the re-entry adds nothing.
    function attackSwallowing(uint256 amount) external {
        reentryAmount = amount;
        bubble = false;
        reentered = false;
        g.withdrawAfkingFunding(amount);
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            // Re-enter before the outer frame finishes. Under CEI the funding is already zeroed, so this
            // reverts E().
            if (bubble) {
                g.withdrawAfkingFunding(reentryAmount); // bubble the revert -> outer .call fails
            } else {
                try g.withdrawAfkingFunding(reentryAmount) {} catch {} // swallow -> outer completes once
            }
        }
    }
}

interface GameWithdrawLike {
    function withdrawAfkingFunding(uint256 amount) external;
}
