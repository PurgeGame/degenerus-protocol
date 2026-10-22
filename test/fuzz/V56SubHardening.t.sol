// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title V56SubHardening -- the subscribe-hardening gates and the drain stub reachability.
///
/// @notice The gates as built (GameAfkingModule.subscribe):
///   - Seat burn: a new non-exempt run calls the token's `consumeSeat(payee, seatId)`, which reverts
///     `InvalidToken` unless the payee holds `seatId`; checked at subscribe ONLY. Deity confers nothing
///     for afking gating; any payee holding a seat clears it regardless of level.
///   - Completed-pass signup: a new ordinary run needs today's subscriber pass to be complete (`RngLocked`
///     otherwise), buys nothing, needs no funding, and checkpoints today; its first purchase and first
///     credited day are the next day's.
///   - Protocol exemption: VAULT / sDGNRS subscribed in their own constructors (before the token exists),
///     keyed on the resolved wallet ID, and later changes to their runs never call the token.
///   - Membership ends only via cancel or an unfunded pass (SubscriptionExpired reason 1); a level change
///     never evicts.
///   - Same-day churn credits nothing: rewards derive from the checkpoint, so subscribe / cancel /
///     subscribe on one day neither buys nor pays.
///
/// @notice drainAffiliateBases Game dispatch stub: the guard-less delegatecall to the AFKing module whose
///   AFFILIATE-only gate sees the Game stub's caller. The affiliate path settles the sub (pays its own
///   share, moves the checkpoint) and returns the settled affiliate base; any other caller reverts
///   NotApproved().
contract V56SubHardening is DeployProtocol {

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

    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED; // mintPacked_ mapping root (deity bit)

    /// @dev Whole FLIP a box-mode member earns per credited day.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT;       // HAS_DEITY_PASS_SHIFT in mintPacked_ (confers nothing for afking credentials or mining participation)

    /// @dev The game `level` lives in slot 0 at byte 12 (uint24) — poked up to drive the level-crossing
    ///      membership-survival proof (the fixture level does not advance organically).
    uint256 private constant LEVEL_OFF = 12;

    /// @dev SubscriptionExpired(player indexed, uint8 reason): reason 1 = unfunded; reason 2 = seized.
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(uint32,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)

    function setUp() public {
        _deployProtocol();
        // The unified miner also requests midday RNG after the read consumers finish.
        // Fund the mock so a clean-state fixture cannot stall on InsufficientLink.
        mockVRF.fundSubscription(admin.subscriptionId(), 1_000 ether);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // D-11 — seat-required subscribe (InvalidToken on the new-run branch)
    // =========================================================================

    /// @notice D-11 NEGATIVE: an EOA holding NO AFKing Subscription Token reverts InvalidToken() on a new-run subscribe
    ///         (dailyQuantity >= 1) — a seat the payee holds is the sole afking credential, burned by the
    ///         token's consumeSeat at subscribe. That burn precedes the D-12 grounding gate, so the
    ///         EOA is funded to isolate the credential failure.
    function testD11SeatlessEoaRevertsInvalidToken() public {
        address p = makeAddr("d11_nocoin");
        _fundPool(p, 50 ether);       // funded, so the revert can ONLY be InvalidToken (not a funding revert)
        uint256 seat = _grantSeat(makeAddr("d11_other_holder")); // a seat p does not hold
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        game.subscribe(0, false, 1, seat);
        assertEq(_subscriberIndexOf(p), 0, "D-11: the coinless sub was never created");
    }

    /// @notice D-11 POSITIVE: an EOA holding >= 1 AFKing Subscription Token (granted via `_grantSeat`, no pass anywhere
    ///         — the pass/horizon machinery is deleted) clears D-11 and subscribes successfully (funded so
    ///         D-12 is also satisfied). The successor of the old finite-pass-covers-the-level proof: the
    ///         coin gate has no level dependence at all.
    function testD11SeatedEoaSubscribes() public {
        address p = makeAddr("d11_seated");
        uint256 seat = _grantSeat(p);
        _fundPool(p, 50 ether);
        vm.prank(p);
        game.subscribe(0, false, 1, seat); // MUST NOT revert
        assertGt(_subscriberIndexOf(p), 0, "D-11: seated sub created");
    }

    /// @notice D-11 (deity confers nothing for afking gating): a deity holder WITHOUT an AFKing Subscription Token still
    ///         reverts InvalidToken(). Deity ownership has no bearing on the afking credential.
    function testD11DeityHolderWithoutSeatRevertsInvalidToken() public {
        address p = makeAddr("d11_deity_nocoin");
        _grantDeityPass(p);           // deity bit set — confers nothing for the coin gate
        _fundPool(p, 50 ether);       // funded, so the revert can ONLY be InvalidToken (not a funding revert)
        uint256 seat = _grantSeat(makeAddr("d11_other_holder")); // a seat p does not hold
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        game.subscribe(0, false, 1, seat);
        assertEq(_subscriberIndexOf(p), 0, "D-11: a deity holder without a coin is still rejected (InvalidToken)");
    }

    // =========================================================================
    // Signup — completed pass, no purchase, no funding requirement
    // =========================================================================

    /// @notice A seated but UNFUNDED EOA starts a run: signup buys nothing, so it needs no funds.
    ///         The run checkpoints today and the next daily pass expires it for lack of funding.
    function testSignupNeedsNoFundingAndBuysNothing() public {
        address p = makeAddr("sig_unfunded");
        uint256 seat = _grantSeat(p);
        _aid(p);
        vm.prank(p);
        game.subscribe(0, false, 1, seat); // MUST NOT revert
        assertGt(_subscriberIndexOf(p), 0, "unfunded run created");
        assertEq(_checkpointDayOf(p), uint32(game.currentDayView()), "checkpointed today");
        assertEq(game.afkingFundingOf(p), 0);
        assertFalse(GameSlotKeys.afkingBoxPending(address(game), game.walletIdOf(p)), "no box at signup");

        vm.recordLogs();
        _deliverDay(_singleton(p), 0x51671);
        assertEq(_countExpired(p, 1), 1, "the next pass expires the unfunded run");
        assertEq(_subscriberIndexOf(p), 0);
    }

    /// @notice A funded signup debits nothing, and the first purchase is the next day's.
    function testFundedSignupDebitsNothingFirstBuyNextDay() public {
        address p = makeAddr("sig_funded");
        uint256 seat = _grantSeat(p);
        _fundPool(p, 50 ether);
        uint256 poolBefore = game.afkingFundingOf(p);
        vm.prank(p);
        game.subscribe(0, false, 1, seat);
        assertEq(game.afkingFundingOf(p), poolBefore, "signup debits nothing");
        _deliverDay(_singleton(p), 0x51672);
        assertLt(game.afkingFundingOf(p), poolBefore, "the next day's pass bought");
    }

    /// @notice A new run needs today's subscriber pass to be complete: after the day rolls and before
    ///         the pass runs, signup reverts RngLocked.
    function testNewRunBeforeTodaysPassReverts() public {
        address p = makeAddr("sig_early");
        uint256 seat = _grantSeat(p);
        _fundPool(p, 50 ether);
        _t += 1 days;
        vm.warp(_t);
        vm.prank(p);
        vm.expectRevert(abi.encodeWithSignature("RngLocked()"));
        game.subscribe(0, false, 1, seat);
        assertEq(_subscriberIndexOf(p), 0);
        _finishSubscriptionWindow();
        vm.prank(p);
        game.subscribe(0, false, 1, seat); // the completed pass opens signup
        assertGt(_subscriberIndexOf(p), 0);
    }

    /// @notice An active run changed after a delivered day keeps its run; the change buys nothing.
    function testActiveResubAfterDeliveredDayBuysNothing() public {
        address p = makeAddr("sig_resub");
        _grantSeat(p);
        _fundPool(p, 80 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xD12E50);
        assertGt(_subscriberIndexOf(p), 0, "non-vacuity: the sub is active");
        uint256 poolBefore = game.afkingFundingOf(p);
        vm.prank(p);
        game.subscribe(0, false, 2, 0); // a live run burns no seat
        assertGt(_subscriberIndexOf(p), 0, "re-sub stays active");
        assertEq(_dailyQtyOf(p), 2);
        assertEq(game.afkingFundingOf(p), poolBefore, "the change buys nothing");
    }

    // =========================================================================
    // D-13 — VAULT / sDGNRS bootstrap exemption (no coin + unfunded still subscribes)
    // =========================================================================

    /// @notice The protocol seats subscribed in their own constructors, seatless and unfunded, at box
    ///         positions 0 (Vault) and 1 (sDGNRS) with quantity 1 — load-bearing because the token
    ///         does not exist yet at construction.
    function testD13ProtocolSeatsBootstrapSeatlessAtBoxPositions() public view {
        (uint256 vaultLane, uint256 vaultPos) = GameSlotKeys.subLane(address(game), 1);
        (uint256 sdgnrsLane, uint256 sdgnrsPos) = GameSlotKeys.subLane(address(game), 2);
        assertEq(vaultPos, 1, "Vault at box position 0");
        assertEq(sdgnrsPos, 2, "sDGNRS at box position 1");
        assertEq(((vaultLane >> 32) & 7) + 1, 1, "Vault quantity 1");
        assertEq(((sdgnrsLane >> 32) & 7) + 1, 1, "sDGNRS quantity 1");
        assertEq(vaultLane & (uint256(1) << 35), 0, "Vault lootbox mode");
    }

    /// @notice The exempt Vault changes its own run with no seat: no consumeSeat call.
    function testD13VaultChangeNeverCallsTheToken() public {
        vm.expectCall(address(afkingSubToken), abi.encodeWithSignature("consumeSeat(address,uint256)"), 0);
        vm.prank(ContractAddresses.VAULT);
        game.subscribe(0, false, 2, 0); // no seat, unfunded
        assertEq(_dailyQtyOf(ContractAddresses.VAULT), 2, "VAULT change succeeded without a seat");
    }

    /// @notice The exempt sDGNRS changes its own run with no seat, and cannot cancel.
    function testD13SdgnrsChangeNeverCallsTheTokenAndCannotCancel() public {
        vm.expectCall(address(afkingSubToken), abi.encodeWithSignature("consumeSeat(address,uint256)"), 0);
        vm.prank(ContractAddresses.SDGNRS);
        game.subscribe(0, false, 2, 0);
        assertEq(_dailyQtyOf(ContractAddresses.SDGNRS), 2, "sDGNRS change succeeded without a seat");
        vm.prank(ContractAddresses.SDGNRS);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        game.subscribe(0, false, 0, 0);
    }

    // =========================================================================
    // Crossing eviction SUPERSEDED — a seated sub survives level changes / STAGE
    // processing without eviction. The pass/horizon crossing gate (the per-iter
    // `currentLevel > sub.validThroughLevel` re-read that used to refresh-or-evict)
    // is DELETED along with `Sub.validThroughLevel` / `_passHorizonOf`. Membership
    // is no longer level-dependent at all: it ends only via cancel, funding-skip
    // kill (SubscriptionExpired reason 1); the coin's seat lock blocks an active sub's last-coin transfer.
    // =========================================================================

    /// @notice A seated (coin-holding) sub is carried through an arbitrary level change across the STAGE
    ///         with NO eviction: still in the set, dailyQuantity intact, no SubscriptionExpired of any
    ///         reason. Successor of the old outgrown-pass eviction proof — a level crossing is now a
    ///         non-event for subscription membership.
    function testSeatedSubSurvivesLevelCrossingNoEviction() public {
        address p = makeAddr("crossing_survives");
        _grantSeat(p);                 // the coin is the sole credential; no pass anywhere
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xC10551); // an active afking run; box opened (no pending-box skip)
        assertGt(_subscriberIndexOf(p), 0, "non-vacuity: sub active before the crossing");

        vm.recordLogs();
        _settleGame(uint256(keccak256("cross_pre")) | 1);
        _t += 1 days;
        vm.warp(_t);
        _setLevel(10);                 // poke the level up across a fresh-day STAGE pass
        _settleGame(uint256(keccak256("cross_go")) | 1); // STAGE runs -> no eviction branch exists anymore

        assertEq(_countExpired(p, 1), 0, "crossing: no unfunded expiry fired (the sub stayed funded)");
        assertEq(_countExpired(p, 2), 0, "crossing: no seizure removal fired (never seized)");
        assertGt(_subscriberIndexOf(p), 0, "crossing: the seated sub was NOT evicted by the level change");
        assertGt(_dailyQtyOf(p), 0, "crossing: dailyQuantity preserved across the crossing");
    }

    // =========================================================================
    // CHURN-IDEMPOTENCY — rewards derive from the checkpoint, never accumulate per cycle
    // =========================================================================

    /// @notice A seated + funded EOA subscribes, then churns cancel -> subscribe N times in the SAME
    ///         day. Signup buys nothing and checkpoints today, and a cancel settles nothing (no elapsed
    ///         day), so the churn pays no FLIP, debits no funding and leaves no stranded record. The
    ///         next completed pass credits the single day exactly once.
    function testChurnSameDayCreditsNothingThenOneDayOnce() public {
        address p = makeAddr("churn_idempotency");
        _grantSeat(p);
        _fundPool(p, 200 ether);
        uint256 fundingBefore = game.afkingFundingOf(p);
        uint32 id = game.walletIdOf(p);

        _subscribeLootbox(p, 1);
        uint32 today = uint32(game.currentDayView());
        assertEq(_checkpointDayOf(p), today, "signup checkpoints today");
        uint256 setLen = game.subscriberSetLength();

        for (uint256 i; i < 5; i++) {
            _subscribeLootbox(p, 0);   // cancel: settles both sides (nothing elapsed) and removes the record
            assertEq(_subscriberIndexOf(p), 0, "cancel removed the record at once");
            assertEq(game.subscriberSetLength(), setLen - 1, "no tombstone stays in the set");
            _subscribeLootbox(p, 1);   // a new run: burns another seat
            assertEq(_dailyQtyOf(p), 1, "re-subscribe restored the run");
            assertEq(_checkpointDayOf(p), today, "the new run checkpoints today");
            assertEq(coinflip.coinflipAmount(p), 0, "churn paid no FLIP");
            assertEq(game.afkingFundingOf(p), fundingBefore, "churn bought nothing");
        }

        _deliverDay(_singleton(p), 0xC4012);
        assertLt(game.afkingFundingOf(p), fundingBefore, "the next day bought once");
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        vm.recordLogs();
        game.claimAfkingFlip(ids);
        assertEq(_flipClaimed(p), SLOT0_FLIP_PER_BUY, "one day credited exactly once");
        vm.recordLogs();
        game.claimAfkingFlip(ids);
        assertEq(_flipClaimed(p), 0, "a repeat claim credits nothing");
    }

    // =========================================================================
    // LEVEL-0 PASS GATE — SUPERSEDED. The old `(validThroughLevel == 0 ||
    // validThroughLevel < level)` boundary was specific to the deleted pass/horizon
    // gate; the AFKing Subscription Token credential (D-11, above) has no level dependence
    // whatsoever, so there is no level-0 boundary left to exercise. The D-11 /
    // D-13 sections above already cover coinless/seated/deity-without-coin/
    // VAULT-SDGNRS-exempt subscribe, and none of those outcomes vary with level.
    // =========================================================================

    // =========================================================================
    // F-356-01 — the drainAffiliateBases Game dispatch stub is reachable + AFFILIATE-only
    // =========================================================================

    /// @notice F-356-01 reachability: the DegenerusGame.drainAffiliateBases dispatch stub is reachable
    ///         from the affiliate path. Pranked as ContractAddresses.AFFILIATE (the caller the
    ///         DegenerusAffiliate.claim() loop routes through), the stub delegatecalls the module past
    ///         its AFFILIATE-only gate, settles the sub and returns the elapsed affiliate base
    ///         (70 per unit per day); a second drain finds nothing.
    function testDrainAffiliateBaseReachableFromAffiliatePath() public {
        address p = makeAddr("drain_reach");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xD4A10B); // one completed pass after signup
        uint32 subscriberId = game.walletIdOf(p);
        uint256 cpBefore = _checkpointDayOf(p);

        vm.recordLogs();
        vm.prank(ContractAddresses.AFFILIATE);
        (uint256 drained,,) = game.drainAffiliateBases(subscriberId, 0);
        assertEq(drained, 70, "F-356-01: the stub returned the one elapsed day's base");
        assertEq(_checkpointDayOf(p), cpBefore + 1, "the drain settled the sub to the endpoint");
        assertEq(_flipClaimed(p), SLOT0_FLIP_PER_BUY, "the drain paid the sub's own share");

        vm.recordLogs();
        vm.prank(ContractAddresses.AFFILIATE);
        (drained,,) = game.drainAffiliateBases(subscriberId, 0);
        assertEq(drained, 0, "a second drain finds nothing");
        assertEq(_flipClaimed(p), 0, "and pays nothing");
    }

    /// @notice F-356-01 AFFILIATE-only: a NON-affiliate caller routed through the SAME Game dispatch stub
    ///         reverts NotApproved(), leaving the checkpoint (and so the owed base) intact.
    function testDrainAffiliateBaseStubAffiliateOnly() public {
        address p = makeAddr("drain_gate");
        _grantSeat(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xD4A106);
        uint256 cpBefore = _checkpointDayOf(p);

        uint32 subscriberId = game.walletIdOf(p);
        vm.prank(makeAddr("not_affiliate"));
        vm.expectRevert(abi.encodeWithSignature("NotApproved()"));
        game.drainAffiliateBases(subscriberId, 0);
        assertEq(_checkpointDayOf(p), cpBefore, "the rejected non-affiliate drain left the checkpoint intact");
    }

    // =========================================================================
    // Mining participation is open to every address. The compatibility view does
    // not promise payment: successful work must independently clear the gas floor.
    // Subscription credentials and RNG lifecycle controls still apply.
    // =========================================================================

    function testAdvanceGameLivenessFreshNonMinterNotGated() public {
        _settleClean(uint256(keccak256("live_settle")) | 1);
        _warpToDayBoundary(5);
        assertTrue(game.advanceDue(), "fixture: fresh day has work");
        address miner = makeAddr("fresh_miner");
        assertTrue(game.bountyEligible(miner), "mining has no participant gate");
        vm.recordLogs();
        vm.prank(miner);
        game.mineFlip(0);
        _assertMinerProgress(miner);
    }

    function testBountyEligibleIsOpenAcrossRolesAndDayWindows() public {
        _settleClean(uint256(keccak256("be_settle")) | 1);
        _warpToDayBoundary(5);
        _finishSubscriptionWindow();
        address fresh = makeAddr("be_fresh");
        address deity = makeAddr("be_deity");
        address sub = makeAddr("be_sub");
        assertTrue(game.bountyEligible(fresh), "fresh address needs no purchase or pass");
        assertTrue(game.bountyEligible(deity), "open before receiving a deity pass");
        assertTrue(game.bountyEligible(sub), "open before subscribing");
        assertTrue(game.bountyEligible(address(0)), "compatibility view is unconditional");
        _grantDeityPass(deity);
        _grantSeat(sub);
        _fundPool(sub, 50 ether);
        _subscribeLootbox(sub, 1);
        assertGt(_dailyQtyOf(sub), 0, "fixture: subscription exists");
        assertTrue(game.bountyEligible(deity), "deity status does not change participation");
        assertTrue(game.bountyEligible(sub), "subscription does not change participation");
        assertTrue(game.bountyEligible(ContractAddresses.CREATOR), "vault ownership is irrelevant to mining");
        _t += 16 minutes;
        vm.warp(_t);
        assertTrue(game.bountyEligible(fresh), "no fifteen-minute participation window");
        _t += 15 minutes;
        vm.warp(_t);
        assertTrue(game.bountyEligible(fresh), "no thirty-minute participation window");
    }

    function testDeityPassDoesNotBypassPendingRng() public {
        _settleClean(uint256(keccak256("deity_rng_settle")) | 1);
        _warpToDayBoundary(5);
        address miner = makeAddr("deity_miner");
        _grantDeityPass(miner);
        assertTrue(game.bountyEligible(miner));
        // Maintenance may checkpoint before the request. The same unrestricted miner
        // runs each necessary step, without supplying a VRF response.
        for (uint256 i; i < 16 && !game.rngLocked(); ++i) {
            vm.prank(miner);
            game.mineFlip(0);
        }
        assertTrue(game.rngLocked(), "fixture: request is waiting for fulfillment");
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSignature("RngNotReady()"));
        game.mineFlip(0);
    }

    function testOpenMiningDoesNotBypassSubscriptionCoinRequirement() public {
        _settleClean(uint256(keccak256("subscription_gate_settle")) | 1);
        _warpToDayBoundary(5);
        _finishSubscriptionWindow();
        address miner = makeAddr("coinless_miner");
        _fundPool(miner, 50 ether);
        assertTrue(game.bountyEligible(miner));
        uint256 seat = _grantSeat(makeAddr("miner_other_holder")); // a seat the miner does not hold
        vm.prank(miner);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        game.subscribe(0, false, 1, seat);
        assertEq(_subscriberIndexOf(miner), 0, "subscription credential still required");
        _warpToDayBoundary(6);
        vm.recordLogs();
        vm.prank(miner);
        game.mineFlip(0);
        _assertMinerProgress(miner);
    }

    /// @notice Vault keeper routing: Vault.playerAction routes mineFlip with its gas multiplier unchanged
    ///         (subject to the successful-work reward floor); it performs the crank when work is due and reverts NoWork() when
    ///         idle. The vault is owner-gated (onlyVaultOwner) — prank as CREATOR (the DGVE majority
    ///         owner). Mining participation itself has no ownership requirement. Both arms asserted.
    function test_WrappersForwardCallerCalibration() public {
        bytes memory callData = abi.encodeWithSignature("mineFlip(uint32)", uint32(50_000));
        vm.mockCall(address(game), callData, bytes(""));
        vm.expectCall(address(game), callData, 2);
        vm.prank(ContractAddresses.CREATOR);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("mineFlip(uint32)", 50_000), 0)), 0), (bytes));
        sdgnrs.gameAdvance(50_000);
    }

    function testVaultGameAdvanceRoutesThroughMintFlip() public {
        // Idle arm first: settle clean, do NOT roll the day -> nothing due -> NoWork().
        _settleClean(uint256(keccak256("vault_idle")) | 1);
        // Mine any remaining read-cohort housekeeping first; the wrapper's idle assertion is
        // about a genuinely stationary router.
        _mineAll(64);
        require(!game.advanceDue(), "fixture: clean so the idle arm is genuine");
        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up.
        _quietCrapsTable();
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (ContractAddresses.GAME, abi.encodeWithSignature("mineFlip(uint32)", 0), 0)), 0), (bytes));

        // Work-due arm: roll a fresh day -> advance due -> gameAdvance cranks via mineFlip (no revert).
        _warpToDayBoundary(5);
        assertTrue(game.advanceDue(), "fixture: advance due for the vault crank");
        vm.recordLogs();
        vm.prank(ContractAddresses.CREATOR);
        abi.decode(OwnerTargetCall.call(address(vault), abi.encodeCall(vault.playerAction, (
            ContractAddresses.GAME,
            abi.encodeWithSignature("mineFlip(uint32)", 50_000),
            0
        )), 0), (bytes));           // MUST NOT revert — routes through mineFlip and does the work
        _assertMinerProgress(address(vault));
    }

    /// @notice sDGNRS keeper routing: sDGNRS.gameAdvance(0) routes through game.mineFlip(0)
    ///         and is PERMISSIONLESS (no owner gate). It performs the crank when work is due and reverts
    ///         NoWork() when idle. These assertions cover routing, without assuming that a small
    ///         call earns compensation.
    function testSdgnrsGameAdvanceRoutesThroughMintFlip() public {
        // Idle arm: clean, no day-roll -> NoWork().
        _settleClean(uint256(keccak256("sdgnrs_idle")) | 1);
        // Mine any remaining read-cohort housekeeping first; the wrapper's idle assertion is
        // about a genuinely stationary router.
        _mineAll(64);
        require(!game.advanceDue(), "fixture: clean so the idle arm is genuine");
        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up.
        _quietCrapsTable();
        vm.prank(makeAddr("anyone_sdgnrs")); // permissionless — any caller
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        sdgnrs.gameAdvance(0);

        // Work-due arm: roll a fresh day -> advance due -> gameAdvance cranks via mineFlip (no revert).
        _warpToDayBoundary(5);
        assertTrue(game.advanceDue(), "fixture: advance due for the sDGNRS crank");
        vm.recordLogs();
        vm.prank(makeAddr("anyone_sdgnrs2"));
        sdgnrs.gameAdvance(50_000);          // MUST NOT revert — routes through mineFlip and does the work
        _assertMinerProgress(address(sdgnrs));
    }

    /// @dev MinerWork is emitted only after committed progress. A checkpoint can leave
    ///      more work due without locking RNG, and a small successful step may be unpaid.
    function _assertMinerProgress(address miner) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 signature = keccak256("MinerWork(address,uint8,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2
                || logs[i].topics[0] != signature
                || logs[i].topics[1] != bytes32(uint256(uint160(miner)))) continue;
            (, uint256 executionGas,) = abi.decode(logs[i].data, (uint8, uint256, uint256));
            assertGt(executionGas, 0, "committed work has a positive measured gas delta");
            return;
        }
        fail("miner did not commit progress");
    }

    // =========================================================================
    // Protocol-driving helpers (ported VERBATIM from V56SecUnmanipulable, minus the deleted
    // pass/horizon pokes — the credential poke is `_grantSeat` from DeployProtocol)
    // =========================================================================

    /// @dev Warp to a fresh day boundary + `offsetSeconds` (the daily reset is 82620s past midnight).
    ///      Lands deterministically in the first seconds of a NEW day so advanceDue() is true and the
    ///      removed participation windows cannot be hidden by a late-day timestamp. Mirrors the v56 gas-marginal
    ///      `_warpToBoundary` day-roll, threaded through the accumulating-timestamp workaround.
    function _warpToDayBoundary(uint256 offsetSeconds) internal {
        uint256 dayLen = 1 days;
        uint256 reset = 82620;
        uint256 cur = block.timestamp;
        uint256 idx = (cur - reset) / dayLen;
        uint256 nextBoundary = (idx + 1) * dayLen + reset + offsetSeconds;
        _t = nextBoundary;
        vm.warp(_t);
    }

    uint256 private _deliverNonce;

    /// @dev Deliver ONE funded day to `who`: a new-day STAGE buy (stamps each pending box + accrues), then
    ///      settle clean and OPEN every pending box (so the no-orphan guard does not skip the next buy).
    function _deliverDay(address[] memory who, uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
        who;
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (the accumulating-timestamp warp).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
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

    function _settleClean(uint256 vrfWord) internal {
        _finishReadConsumers();
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineFlip(0);
            _fulfillPending(vrfWord);
        }
        fail("fixture: miner consumers did not settle");
    }

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

    function _subscribeLootbox(address who, uint8 q) internal {
        uint256 seat = _grantSeat(who);
        vm.prank(who);
        game.subscribe(0, false, q, seat); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev Deity bit only; it confers nothing for the afking coin gate or mining participation.
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf(who), uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Poke the game `level` (slot 0, byte 12, uint24) to drive the level-crossing
    ///      membership-survival proof (the fixture level does not advance organically over the harness loop).
    function _setLevel(uint24 lvl) internal {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFF * 8));
        s0 |= (uint256(lvl) & 0xFFFFFF) << (LEVEL_OFF * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    function _countExpired(address who, uint8 reason) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != SUB_EXPIRED_SIG) continue;
            if (uint32(uint256(logs[i].topics[1])) != game.walletIdOf(who)) continue;
            if (uint8(uint256(bytes32(logs[i].data))) == reason) count++;
        }
    }

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    /// @dev Whole FLIP the AfkingFlipClaimed events recorded since the last vm.recordLogs() paid `who`.
    function _flipClaimed(address who) internal returns (uint256 total) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("AfkingFlipClaimed(uint32,uint256)");
        uint32 id = game.walletIdOf(who);
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            total += abi.decode(logs[i].data, (uint256));
        }
    }

    // ---- Lane reads ----

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(GameSlotKeys.subQuantity(address(game), game.walletIdOf(who)));
    }

    /// @dev `who`'s set position + 1; 0 = not in the set.
    function _subscriberIndexOf(address who) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), game.walletIdOf(who));
    }

    function _checkpointDayOf(address who) internal view returns (uint32) {
        (uint256 lane,) = GameSlotKeys.subLane(address(game), game.walletIdOf(who));
        return uint32((lane >> 46) & ((uint256(1) << 22) - 1));
    }
}
