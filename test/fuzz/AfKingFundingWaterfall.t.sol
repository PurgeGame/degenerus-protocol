// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AfKingFundingWaterfall -- Proves the v55.0 game-resident afking per-player funding waterfall
///        (SUB-05), the two-tier pinned-identity funding-skip kill (SUB-06), the OPEN-E shared funding
///        source ETH-routing (OPENE-02/03 + LANDMINE A), and the pass-eviction-preserves-fundingSource
///        property. The funding waterfall now debits the IN-CONTEXT `afkingFunding[src]` SLOAD
///        (GameAfkingModule.sol:709, the `claimablePool -=` tandem at :710) — NOT a cross-contract
///        staticcall. Feeds TST-02's "fuzz random FUNDED well-formed slice inputs" (CONTEXT D-351-04).
///
/// @notice Funding waterfall (SUB-05), inside the process STAGE per player (GameAfkingModule._resolveBuy
///         :440-496):
///   - drainGameCreditFirst == false -> DirectEth, ethValue = cost (pays afkingFunding ETH only).
///   - drainGameCreditFirst == true:
///       * claimable cred > cost          -> Claimable, ethValue = 0 (pays from claimable only).
///       * 1 < cred <= cost               -> Combined,  ethValue = cost - (cred - 1) (afkingFunding tops up).
///       * cred <= 1                      -> DirectEth, ethValue = cost.
///   - afkingFunding[src] < ethValue       -> InsufficientPool funding skip (the kill / exempt branch).
///
/// @notice Two-tier skip-kill (SUB-06), on the InsufficientPool funding skip (GameAfkingModule.sol:661-682):
///   - a NORMAL sub is CANCELLED via swap-pop (dailyQuantity 0, SubscriptionExpired(player,1)),
///     continuing WITHOUT advancing the cursor.
///   - the VAULT and SDGNRS subs are EXEMPT -- they persist (no-op-and-retry, PlayerSkipped(player,3),
///     stay in the set), keyed on the UN-SPOOFABLE pinned ContractAddresses.VAULT / SDGNRS identity.
///   - NO settable exemption flag exists: the exemption is purely the pinned-address equality branch.
///
/// @notice OPEN-E four-protection re-attest (the per-day ETH draw routing surface):
///   - Consent-gate-at-subscribe: a non-zero non-self fundingSource MUST be operator-approved by the
///     source for the subscriber AT subscribe (GameAfkingModule.sol:259-265); no later re-check.
///   - Default-self: subscribe with fundingSource = address(0) stores `_fundingSourceOf == address(0)`
///     and the STAGE resolves `src = player` (self-pay) -- the ETH draw debits the subscriber's own
///     afkingFunding bucket.
///   - No-escalation: a revoke AFTER subscribe does NOT escalate; the STAGE keeps debiting S until S defunds.
///   - Trust-the-sub: the sub is the consent unit (revoke is moot; stop = M cancels or S defunds).
///
/// @notice PASS-EVICTION-PRESERVES-FUNDINGSOURCE: at the EVICT branch the STAGE writes only
///         `sub.dailyQuantity = 0; _removeFromSet(player)` -- the OTHER Sub fields are NOT deleted (only
///         the cancel-tombstone RECLAIM path does `delete _subOf[player]`). A sub evicted at a level
///         crossing leaves `_fundingSourceOf[player]` readable post-eviction.
///
/// @dev D-351-01 deltas applied: afKing.subscribe -> game.subscribe; afKing.autoBuy -> the advanceGame()
///      STAGE; afKing.poolOf -> afkingFundingOf; afKing.depositFor -> depositAfkingFunding; the standalone
///      afKing.setMode/setDrainGameCreditFirst setters (GONE) -> the flags are set via game.subscribe;
///      the deleted standalone-contract source-grep -> repointed to GameAfkingModule.sol. RE-DERIVED
///      every pinned slot via `forge inspect storage DegenerusGame`. Test-only: no contracts/*.sol mutated.
contract AfKingFundingWaterfall is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect storage DegenerusGame`).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 54; // _subOf mapping root
    uint256 private constant FUNDINGSOURCE_SLOT = 55; // _fundingSourceOf mapping root
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 57; // _subscriberIndex mapping root (1-indexed)
    uint256 private constant MINTPACKED_SLOT = 9; // mintPacked_ mapping root (deity bit)
    uint256 private constant GAME_CLAIMABLE_SLOT = 7; // claimableWinnings mapping root

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:1895; the v56 compute-on-read re-pack
    // narrowed validThroughLevel + the day markers to uint24).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity     (byte 0)
    uint256 private constant OFF_VALIDTHROUGH = 1; // uint24 validThroughLevel (bytes 1..3)
    uint256 private constant OFF_LASTBOUGHT = 10; // uint24 lastAutoBoughtDay (bytes 11..13)

    uint256 private constant DEITY_SHIFT = 184;

    bytes32 private constant SKIPPED_SIG = keccak256("PlayerSkipped(address,uint8)");
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(address,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    /// @dev Per-player funding-SOURCE afkingFunding snapshot — the charged ETH slice = the source delta
    ///      across the STAGE (the storage-stamp oracle, the GASOPT-04 successor to the deleted AutoBought).
    mapping(address => uint256) private _srcFundBefore;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // =========================================================================
    // Task 3a -- Funding waterfall branches (SUB-05) -- fuzz-fed funded slices (TST-02)
    // =========================================================================

    /// @notice DirectEth: a drainGameCreditFirst == FALSE sub pays the full cost from afkingFunding ETH
    ///         (ethValue == cost), independent of any claimable balance.
    function testWaterfallDirectEthWhenNotDraining() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address p = _subscribeHealthy("direct_", /*drainFirst*/ false);
        uint256 cost = _cost(1);
        _setClaimable(p, cost * 5); // ample claimable -- IGNORED because drainFirst is false
        _fundPool(p, cost); // exactly the DirectEth ethValue

        _stageCapture(p);

        assertEq(_chargedFor(p), cost, "DirectEth: ethValue == cost (full afkingFunding spend)");
        assertEq(game.afkingFundingOf(p), 0, "afkingFunding debited by the full cost");
    }

    /// @notice Claimable: a drain-first sub with claimable cred > cost pays from claimable ONLY
    ///         (ethValue == 0) -- no afkingFunding spend; an EMPTY bucket still buys.
    function testWaterfallClaimableOnlyWhenCredExceedsCost() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address p = _subscribeHealthy("claim_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        _setClaimable(p, cost + 1); // cred > cost -> Claimable, ethValue 0
        assertEq(game.afkingFundingOf(p), 0, "afkingFunding empty for the claimable-only path");

        _stageCapture(p);

        assertEq(_chargedFor(p), 0, "Claimable: ethValue == 0 (no afkingFunding spend)");
        assertEq(game.afkingFundingOf(p), 0, "claimable-only path left afkingFunding untouched");
    }

    /// @notice Combined: a drain-first sub with 1 < cred <= cost tops up from afkingFunding: ethValue ==
    ///         cost - (cred - 1).
    function testWaterfallCombinedTopsUpFromPool() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address p = _subscribeHealthy("combo_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        uint256 cred = cost / 2 + 1; // 1 < cred <= cost (cost > 2)
        _setClaimable(p, cred);
        uint256 expectedEth = cost - (cred - 1);
        _fundPool(p, expectedEth); // exactly the Combined top-up

        _stageCapture(p);

        assertEq(_chargedFor(p), expectedEth, "Combined: ethValue == cost - (cred - 1)");
        assertEq(game.afkingFundingOf(p), 0, "afkingFunding debited by exactly the Combined top-up");
    }

    /// @notice cred <= 1 sentinel: a drain-first sub whose claimable is only the 1-wei sentinel (or 0)
    ///         degrades to DirectEth (ethValue == cost).
    function testWaterfallSentinelClaimableDegradesToDirectEth() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address p = _subscribeHealthy("sentinel_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        _setClaimable(p, 1); // exactly the sentinel -> cred <= 1 -> DirectEth
        _fundPool(p, cost);

        _stageCapture(p);

        assertEq(_chargedFor(p), cost, "sentinel claimable (cred<=1) degrades to DirectEth ethValue==cost");
        assertEq(game.afkingFundingOf(p), 0, "afkingFunding fully debited on the sentinel->DirectEth degrade");
    }

    /// @notice InsufficientPool: a drain-first NORMAL sub whose claimable + afkingFunding < cost
    ///         funding-skips (and is killed); a co-resident healthy sub still buys (the STAGE never bricks).
    function testWaterfallInsufficientPoolWhenClaimablePlusPoolBelowCost() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address p = _subscribeHealthy("insuf_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        _setClaimable(p, 1); // sentinel -> DirectEth -> ethValue == cost
        _fundPool(p, cost - 1); // strictly below cost -> InsufficientPool

        address healthy = _subscribeHealthy("insuf_healthy_", false);
        _fundPool(healthy, _cost(1));

        _stageCapture(healthy);

        assertEq(_chargedFor(p), type(uint256).max, "under-funded sub NOT bought (InsufficientPool skip)");
        assertEq(_chargedFor(healthy), _cost(1), "the healthy sub still bought (STAGE not bricked)");
    }

    /// @notice TST-02 fuzz (D-351-04 funded slice): over a random claimable-mix on a FUNDED drain-first
    ///         sub, the STAGE never reverts and the charged slice equals the exact `_resolveBuy` ethValue
    ///         (cost - claimableUse, with claimableUse leaving >= 1 wei). Proves revert-free + the
    ///         waterfall identity across the slice space.
    function testFuzzFundedSliceNeverRevertsAndChargesExactEthValue(uint96 claimableRaw) public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address p = _subscribeHealthy("fuzz_slice_", /*drainFirst*/ true);
        uint256 cost = _cost(1);
        uint256 claimable = uint256(claimableRaw) % (cost * 3 + 2); // span below/around/above cost
        _setClaimable(p, claimable);
        _fundPool(p, cost); // FUNDED enough for any ethValue <= cost (the well-formed slice)

        // Expected waterfall (drainFirst): claimableUse = min(claimable, cost), but leave >= 1 wei.
        uint256 claimableUse = claimable < cost ? claimable : cost;
        if (claimable > 0 && claimableUse >= claimable) claimableUse = claimable - 1;
        uint256 expectedEth = cost - claimableUse;

        _stageCapture(p); // MUST NOT revert on any funded well-formed slice

        assertEq(_chargedFor(p), expectedEth, "funded slice charged exactly cost - claimableUse");
        assertEq(game.afkingFundingOf(p), cost - expectedEth, "afkingFunding debited exactly the ethValue");
    }

    // =========================================================================
    // Task 3b -- Two-tier pinned-identity skip-kill (SUB-06)
    // =========================================================================

    /// @notice SUB-06 NORMAL kill: a NORMAL sub hitting a funding skip is CANCELLED via swap-pop --
    ///         dailyQuantity 0, removed from the set, SubscriptionExpired(player,1).
    function testNormalSubFundingSkipCancelsViaSwapPop() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address healthy = _subscribeHealthy("kill_healthy_", false);
        _fundPool(healthy, _cost(1));

        address victim = _subscribeHealthy("kill_victim_", true);
        uint256 cost = _cost(1);
        _setClaimable(victim, 1);
        _fundPool(victim, cost - 1);
        assertGt(_subscriberIndexOf(victim), 0, "victim starts in the set");

        vm.recordLogs();
        _runStageOnce();
        _capture();

        assertEq(_countExpired(victim), 1, "NORMAL sub funding-skip -> SubscriptionExpired(.,1)");
        assertEq(_subscriberIndexOf(victim), 0, "NORMAL sub swap-popped out of the set");
        assertEq(_dailyQtyOf(victim), 0, "NORMAL sub dailyQuantity zeroed (auto-pause)");
    }

    /// @notice SUB-06 EXEMPT: the VAULT and SDGNRS subs (already in the set via SUB-09) hitting the SAME
    ///         funding skip PERSIST -- PlayerSkipped(.,3), still in the set, NOT cancelled -- keyed on
    ///         the pinned ContractAddresses.VAULT / SDGNRS identity. A NORMAL sub in the identical funding
    ///         state IS cancelled, isolating the exemption to the pinned address.
    function testVaultAndSdgnrsExemptFromFundingSkipKill() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        // Ensure VAULT/SDGNRS reach the funding-waterfall step (deity sentinel satisfies AFSUB-02 so the
        // crossing does not evict them first). VAULT already carries the deity bit; grant SDGNRS too.
        _grantDeityPass(ContractAddresses.VAULT);
        _grantDeityPass(ContractAddresses.SDGNRS);

        _prepExemptSub(ContractAddresses.VAULT);
        _prepExemptSub(ContractAddresses.SDGNRS);

        address normal = _subscribeHealthy("exempt_control_", true);
        _setClaimable(normal, 1);
        _fundPool(normal, _cost(1) - 1);

        address healthy = _subscribeHealthy("exempt_healthy_", false);
        _fundPool(healthy, _cost(1));

        vm.recordLogs();
        _runStageOnce();
        _capture();

        assertEq(_countSkipped(ContractAddresses.VAULT, 3), 1, "VAULT funding-skip -> PlayerSkipped(.,3) (exempt)");
        assertEq(_countSkipped(ContractAddresses.SDGNRS, 3), 1, "SDGNRS funding-skip -> PlayerSkipped(.,3) (exempt)");
        assertEq(_countExpired(ContractAddresses.VAULT), 0, "VAULT NOT cancelled on a funding skip");
        assertEq(_countExpired(ContractAddresses.SDGNRS), 0, "SDGNRS NOT cancelled on a funding skip");
        assertGt(_subscriberIndexOf(ContractAddresses.VAULT), 0, "VAULT stays in the set");
        assertGt(_subscriberIndexOf(ContractAddresses.SDGNRS), 0, "SDGNRS stays in the set");

        // CONTROL: the identically-starved NORMAL sub WAS cancelled -- the only difference is identity.
        assertEq(_countExpired(normal), 1, "the NORMAL control sub IS cancelled in the same funding state");
        assertEq(_subscriberIndexOf(normal), 0, "the NORMAL control sub is swap-popped out");
    }

    // =========================================================================
    // Task 3c -- No settable exemption flag (grep-clean, complements the runtime tests)
    // =========================================================================

    /// @notice SUB-06 spoof-resistance: the exemption is the pinned-address equality branch ONLY. A
    ///         source grep over the game-resident GameAfkingModule.sol finds zero settable-exemption
    ///         symbols; the ONLY exemption surface is the pinned-address equality (present).
    /// @dev    Δ: repointed from the deleted `contracts/AfKing.sol` to `contracts/modules/GameAfkingModule.sol`.
    function testNoSettableExemptionFlagSymbol() public view {
        string memory src = vm.readFile("contracts/modules/GameAfkingModule.sol");
        assertFalse(_contains(src, "isExempt"), "no isExempt symbol (no settable exemption flag)");
        assertFalse(_contains(src, "exemptFlag"), "no exemptFlag symbol");
        assertFalse(_contains(src, "skipKillExempt"), "no skipKillExempt symbol");
        assertTrue(_contains(src, "ContractAddresses.VAULT"), "the pinned-VAULT exemption branch exists");
        assertTrue(_contains(src, "ContractAddresses.SDGNRS"), "the pinned-SDGNRS exemption branch exists");
    }

    // =========================================================================
    // Task 3d -- OPEN-E shared funding source (OPENE-02 ETH routing + LANDMINE A)
    // =========================================================================

    /// @notice OPENE-02/03 default-self equivalence: a sub with fundingSource == address(0) draws ETH
    ///         from ITS OWN afkingFunding bucket, byte-equivalent to the pre-OPEN-E single-account flow.
    function testFundingSourceDefaultSelfIsByteEquivalent() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address m = makeAddr("self_m");
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, address(0));

        assertEq(_fundingSourceOf(m), address(0), "default-self: _fundingSourceOf == address(0)");

        uint256 cost = _cost(1);
        _fundPool(m, cost); // M funds its OWN bucket

        _stageCapture(m);

        assertEq(_chargedFor(m), cost, "default-self: per-day draw debits M's own bucket (DirectEth)");
        assertEq(game.afkingFundingOf(m), 0, "default-self: M's own bucket fully debited");
    }

    /// @notice OPENE-02 cross-account ETH: a funded source S approves M; M subscribes with
    ///         fundingSource = S. The per-day ETH draw debits afkingFunding[S], NOT afkingFunding[M].
    function testCrossAccountEthDrawsSourcePool() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        (address s, address m) = _approvedSourceSub("xeth_s", "xeth_m");
        uint256 cost = _cost(1);

        _fundPool(s, cost); // fund the SOURCE only; M's bucket empty so a mis-routed draw would skip
        assertEq(game.afkingFundingOf(m), 0, "M's own bucket starts empty (only S funds)");

        _stageCapture(m);

        assertEq(_chargedFor(m), cost, "cross-account: M bought (DirectEth, cost forwarded)");
        assertEq(game.afkingFundingOf(s), 0, "cross-account ETH: S's bucket debited by the full cost");
        assertEq(game.afkingFundingOf(m), 0, "cross-account ETH: M's own bucket never touched");
    }

    /// @notice OPENE-04 / trust-the-sub: S approves M, M subscribes with fundingSource = S, S REVOKES
    ///         approval AFTER subscribe. The per-day ETH draw STILL debits S's bucket -- the keeper
    ///         trusts the stored source and never re-checks approval at the per-day draw (no-escalation).
    function testRevokeDoesNotEscalatePerDayDraw() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        (address s, address m) = _approvedSourceSub("revoke_s", "revoke_m");
        uint256 cost = _cost(1);
        _fundPool(s, cost);

        vm.prank(s);
        game.setOperatorApproval(m, false);
        assertFalse(game.isOperatorApproved(s, m), "S has revoked M");

        _stageCapture(m);

        assertEq(_chargedFor(m), cost, "trust-the-sub: per-day draw still debited S after revoke");
        assertEq(game.afkingFundingOf(s), 0, "S's bucket drained by the trust-the-sub draw");
    }

    /// @notice LANDMINE A -- exemption-spoof refusal: a NORMAL sub that sets fundingSource = VAULT does
    ///         NOT inherit the VAULT never-cancel exemption. The exemption keys on the un-spoofable
    ///         SUBSCRIBER identity (player), never on the resolved source.
    function testFundingSourceVaultDoesNotInheritExemption() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        address spoofer = makeAddr("spoof_m");
        vm.prank(ContractAddresses.VAULT);
        game.setOperatorApproval(spoofer, true); // VAULT approves spoofer -> source honored at subscribe
        vm.prank(spoofer);
        game.subscribe(address(0), /*drainFirst*/ true, true, 1, ContractAddresses.VAULT);
        _setClaimable(spoofer, 1); // sentinel -> DirectEth ethValue == cost
        // Deliberately leave afkingFunding[VAULT] empty -> the resolved-source bucket read funding-skips.
        assertEq(game.afkingFundingOf(ContractAddresses.VAULT), 0, "VAULT bucket empty -> spoofer's draw funding-skips");
        assertEq(_fundingSourceOf(spoofer), ContractAddresses.VAULT, "spoofer source = VAULT");
        assertGt(_subscriberIndexOf(spoofer), 0, "spoofer starts in the set");

        address healthy = _subscribeHealthy("spoof_healthy_", false);
        _fundPool(healthy, _cost(1));

        vm.recordLogs();
        _runStageOnce();
        _capture();

        // LANDMINE A: the spoofing NORMAL sub IS cancelled (exemption keys on player, not source).
        assertEq(_countExpired(spoofer), 1, "fundingSource=VAULT spoofer STILL cancelled (LANDMINE A)");
        assertEq(_subscriberIndexOf(spoofer), 0, "spoofer swap-popped out of the set");
        assertEq(_dailyQtyOf(spoofer), 0, "spoofer dailyQuantity zeroed (auto-pause)");

        // The genuine VAULT self-sub (SUB-09) remains in the set -- only the real pinned identity is exempt.
        assertGt(_subscriberIndexOf(ContractAddresses.VAULT), 0, "genuine VAULT self-sub stays in the set");
        assertEq(_countExpired(ContractAddresses.VAULT), 0, "genuine VAULT NOT cancelled");
    }

    // =========================================================================
    // Task 3e -- pass-eviction preserves fundingSource storage
    // =========================================================================

    /// @notice At the EVICT branch the STAGE writes `sub.dailyQuantity = 0; _removeFromSet(player)`
    ///         (GameAfkingModule.sol:621-622). The Sub's OTHER fields are NOT deleted -- only the
    ///         cancel-tombstone RECLAIM path does `delete _subOf[player]`. A sub evicted at the crossing
    ///         leaves `_fundingSourceOf[player]` readable post-eviction.
    function testPassEvictionPreservesFundingSourceStorage() public {
        vm.skip(true, "357-00b D-12 supersession: the funding-waterfall harness subscribes an ungrounded sub (subscribe-before-fund / unfunded source); the grounded subscribe now buys at subscribe, perturbing the per-draw waterfall measurement; re-proven by V56SubHardening (D-12 grounding) + V56FreezeSolvency (debit equals delivered value)");
        (address s, address m) = _approvedSourceSub("eviction_s", "eviction_m");
        // No pass for M -> the EVICT branch fires at the crossing.

        assertEq(_fundingSourceOf(m), s, "pre-eviction: fundingSource = S");

        _forceCrossingDue(m);
        _fundPool(s, 1 ether); // ample S bucket so this is NOT a funding skip -- the crossing is the path

        address healthy = _subscribeHealthy("eviction_healthy_", false);
        _fundPool(healthy, _cost(1));

        vm.recordLogs();
        _runStageOnce();
        _capture();

        assertEq(_countExpired(m), 1, "pass-eviction emitted SubscriptionExpired(.,1)");
        assertEq(_subscriberIndexOf(m), 0, "M swap-popped out of the set");
        assertEq(_dailyQtyOf(m), 0, "dailyQuantity zeroed (tombstoned)");

        // POSITIVE ASSERTION: fundingSource SURVIVES the pass-eviction (eviction tombstones, not deletes).
        assertEq(
            _fundingSourceOf(m),
            s,
            "pass-eviction preserves fundingSource storage (eviction = tombstone, not delete)"
        );
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE advanceGame() (no full settle) — the
    ///      STAGE is strictly PRE-RNG so the funding waterfall / eviction completes before rngGate, and a
    ///      single advance never reaches the level-transition charity call. Subs must be pre-registered.
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
    }

    /// @dev Arm the charged-slice oracle for the single tracked sub, run the STAGE once, drain logs.
    ///      (The waterfall tests track exactly one sub for the ethValue assertion; the kill tests use
    ///      `_runStageOnce` + `_capture` directly.)
    function _stageCapture(address tracked) internal {
        _armSlice(tracked);
        vm.recordLogs();
        _runStageOnce();
        _capture();
    }

    /// @dev Settle the game to a clean state (PATTERNS §"Settle-to-clean-state VRF drain").
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

    /// @dev Set up a cross-account sub: source S approves M on the game, M self-subscribes with
    ///      fundingSource = S (ticket mode, qty 1).
    function _approvedSourceSub(string memory sLabel, string memory mLabel) internal returns (address s, address m) {
        s = makeAddr(sLabel);
        m = makeAddr(mLabel);
        vm.prank(s);
        game.setOperatorApproval(m, true); // S approves M -> fundingSource = S honored at subscribe
        vm.prank(m);
        game.subscribe(address(0), false, true, 1, s); // ticket mode, qty 1, source = S
    }

    /// @dev Per-day cost for qty `q` = mintPrice * q. Ticket mode.
    function _cost(uint256 q) internal view returns (uint256) {
        return game.mintPrice() * q;
    }

    /// @dev Subscribe a fresh player in TICKET mode (so the box-open leg never sees it), qty 1, granted
    ///      deity so it survives any crossing (the funding waterfall, not pass-gating, is the subject).
    function _subscribeHealthy(string memory prefix, bool drainFirst) internal returns (address who) {
        who = makeAddr(string(abi.encodePacked(prefix, "p")));
        _grantDeityPass(who);
        vm.prank(who);
        game.subscribe(address(0), drainFirst, true, 1, address(0)); // self, drainFirst, ticket mode, qty 1
    }

    /// @dev Prep an existing SUB-09 sub (VAULT/SDGNRS) to REACH the funding waterfall: re-subscribe it in
    ///      ticket + drain-first mode (the standalone setMode/setDrainGameCreditFirst setters are GONE —
    ///      the flags are set via subscribe), sentinel claimable so DirectEth ethValue == cost. Bucket
    ///      left empty by the caller.
    function _prepExemptSub(address who) internal {
        vm.prank(who);
        game.subscribe(address(0), /*drainFirst*/ true, /*useTickets*/ true, 1, address(0));
        _setClaimable(who, 1); // sentinel -> DirectEth
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding).
    function _fundPool(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    /// @dev Force `who`'s claimableWinnings to `amount` (RE-DERIVED slot 7) AND credit `claimablePool`
    ///      (slot 1, offset 16, uint128) in TANDEM so the SOLVENCY-01 invariant
    ///      `claimablePool == Σ claimableWinnings + Σ afkingFunding` holds — otherwise the contract's
    ///      `claimablePool -=` on a claimable-funded buy underflows (a test-fixture artifact, not a
    ///      contract bug). Mirrors the contract's own tandem credit.
    function _setClaimable(address who, uint256 amount) internal {
        bytes32 cwSlot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
        uint256 prev = uint256(vm.load(address(game), cwSlot));
        vm.store(address(game), cwSlot, bytes32(amount));
        // claimablePool += (amount - prev) in tandem (keep the master invariant balanced).
        bytes32 s1 = bytes32(uint256(1));
        uint256 p1 = uint256(vm.load(address(game), s1));
        uint128 pool = uint128(p1 >> 128); // claimablePool at offset 16 (the high 128 bits of slot 1)
        if (amount >= prev) {
            pool += uint128(amount - prev);
        } else {
            uint128 dec = uint128(prev - amount);
            pool = pool >= dec ? pool - dec : 0;
        }
        p1 = (p1 & ((uint256(1) << 128) - 1)) | (uint256(pool) << 128);
        vm.store(address(game), s1, bytes32(p1));
    }

    /// @dev Grant `who` the permanent deity bit (RE-DERIVED slot 10) so _passHorizonOf(who) == max.
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Force `who` into the crossing branch: validThroughLevel = 0, lastAutoBoughtDay = 0, bump
    ///      game.level to 1 (uint24 at slot 0 bytes 14..16).
    function _forceCrossingDue(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 mask = (uint256(0xFFFFFF) << (OFF_LASTBOUGHT * 8)) | (uint256(0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        packed &= ~mask;
        vm.store(address(game), slot, bytes32(packed));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (14 * 8);
        if (uint24((slot0 & levelMask) >> (14 * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (14 * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
    }

    // ---- Sub field reads + the source-delta charged-slice oracle ----

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

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    function _fundingSourceOf(address who) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(FUNDINGSOURCE_SLOT)))))));
    }

    /// @dev The current process-day stamp of the fixture (so "bought this STAGE" is robust). The STAGE
    ///      stamps lastAutoBoughtDay = the process day; a fresh buy advances it past the snapshot.
    mapping(address => uint32) private _baselineBoughtDay;

    /// @dev The ethValue charged for `who` this STAGE, re-expressed from the funding-SOURCE bucket delta.
    ///      Returns type(uint256).max if `who` was NOT bought this STAGE. Captures the source baseline on
    ///      first touch via `_srcFundBefore` populated in `_stageCapture` (see `_armSlice`).
    function _chargedFor(address who) internal view returns (uint256) {
        if (_lastBoughtDayOf(who) <= _baselineBoughtDay[who]) return type(uint256).max;
        address src = _fundingSourceOf(who);
        if (src == address(0)) src = who;
        return _srcFundBefore[who] - game.afkingFundingOf(src);
    }

    /// @dev Per-test arming of the charged-slice oracle: record each tracked sub's funding-source bucket
    ///      + day baseline BEFORE the STAGE. Called explicitly by tests that read `_chargedFor`.
    function _armSlice(address who) internal {
        _baselineBoughtDay[who] = _lastBoughtDayOf(who);
        address src = _fundingSourceOf(who);
        if (src == address(0)) src = who;
        _srcFundBefore[who] = game.afkingFundingOf(src);
    }

    // ---- Event drain ----

    Vm.Log[] private _capturedLogs;

    function _capture() internal {
        _capturedLogs = vm.getRecordedLogs();
    }

    function _countSkipped(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _capturedLogs.length; i++) {
            Vm.Log memory L = _capturedLogs[i];
            if (
                L.emitter == address(game) &&
                L.topics.length >= 2 &&
                L.topics[0] == SKIPPED_SIG &&
                address(uint160(uint256(L.topics[1]))) == who
            ) {
                uint8 r = abi.decode(L.data, (uint8));
                if (r == reason) count++;
            }
        }
    }

    function _countExpired(address who) internal view returns (uint256 count) {
        for (uint256 i; i < _capturedLogs.length; i++) {
            Vm.Log memory L = _capturedLogs[i];
            if (
                L.emitter == address(game) &&
                L.topics.length >= 2 &&
                L.topics[0] == SUB_EXPIRED_SIG &&
                address(uint160(uint256(L.topics[1]))) == who
            ) count++;
        }
    }

    /// @dev Substring search over the contract source (for the grep-clean exemption-flag assertion).
    function _contains(string memory haystack, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(haystack);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        for (uint256 i = 0; i <= h.length - n.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }
}
