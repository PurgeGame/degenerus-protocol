// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Local mirror of the coinflip player surface for vm.mockCall selectors. The submit BURNIE
///         settle leg (redeemBurnieShare) and its backing read (previewClaimCoinflips) are mocked to
///         no-ops so the focus stays on the ETH/stETH reserve identity.
interface IBurnieCoinflipPlayerMock {
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function redeemBurnieShare(address redeemer, uint256 base) external;
}

/// @notice Selector mirror for the MODULE-side resolveRedemptionLootbox (the delegatecall target
///         inside the Game-side resolveRedemptionLootbox 5-ETH-chunk loop). Mocked to a no-op so the
///         lootbox materialization loop returns without seeded game lootbox state, while the
///         Game-side body (the stETH pull that drains the lootbox half out of sDGNRS) runs for real.
interface IGameLootboxModuleRRL {
    function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external;
}

/// @title V62RedemptionReentrancy -- regression for finding V62-03 (now verifies the FIX: the
///        stETH-before-ETH reorder in _payEth holds SOLVENCY-01 through a reentrant claim). The
///        vuln description below is retained as context for what the fix prevents.
///
/// @notice V62-03 (adjudicated vs frozen c4d48008): StakedDegenerusStonk.sol has NO reentrancy
///         guard. `claimRedemption(day)` decrements `pendingRedemptionEthValue -= totalRolledEth`
///         and deletes the per-(player,day) claim slot BEFORE the payout (sStonk:728/:731). The
///         payout's `_payEth(player, ethDirect)` MIXED branch (ethDirect > liquid ETH) sends
///         `ethOut = ethBal` to the player via `player.call{value:ethOut}` FIRST (sStonk:954), THEN
///         `steth.transfer(player, stethOut)` (sStonk:957). The ETH `.call` re-enters the attacker's
///         receive() hook while `stethOut` is STILL custodied in the sDGNRS contract.
///
///         Inside the hook the attacker re-enters `burn()` (the gambling-redemption submit path,
///         reachable while !gameOver && !rngLocked && !livenessTriggered). The reentrant backing
///         calc (`_submitGamblingClaimFrom`, sStonk:866-870) reads
///           ethBal     = address(this).balance        (sStonk:866)
///           stethBal   = steth.balanceOf(address(this))(sStonk:867)  <- STILL holds the in-flight stethOut
///           totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue (sStonk:869)
///         The owed-but-not-yet-transferred `stethOut` is counted as FREE backing because
///         pendingRedemptionEthValue no longer reserves it (it was decremented at :728 before the
///         hook fired). The reentrant submit then reserves a NEW redemption via
///         `game.pullRedemptionReserve(maxIncrement)` at the 175% MAX (sStonk:904-911), incrementing
///         pendingRedemptionEthValue. The OUTER claim then transfers `stethOut` OUT of the contract
///         (sStonk:957). Net: pendingRedemptionEthValue is reserved against stETH the contract has
///         already promised away -> the redemption reserve / SOLVENCY-01 identity
///           pendingRedemptionEthValue <= ETH held + stETH held
///         is broken.
///
/// @dev TEST-ONLY. No contracts/*.sol are touched. Subject is the working-tree contracts, verified
///      byte-identical to c4d48008 for StakedDegenerusStonk.sol and DegenerusGame.sol.
///      Run: forge test --match-path test/repro/V62RedemptionReentrancy.t.sol -vv
contract V62RedemptionReentrancy is DeployProtocol {
    // =====================================================================
    //                          CONSTANTS / SLOTS
    // =====================================================================

    /// @dev balancesPacked (DegenerusGame) at slot 7 (v61 PACK fold). Low 128 bits = claimable.
    uint256 internal constant GAME_CLAIMABLE_SLOT = 7;
    /// @dev claimablePool in the upper 128 bits of slot 1.
    uint256 internal constant GAME_SLOT1 = 1;

    /// @dev MAX_ROLL mirror (private literal `175` in sStonk).
    uint256 internal constant MAX_ROLL = 175;

    /// @dev sDGNRS funding for the attacker. Drawn from the Reward pool (10% of INITIAL_SUPPLY =
    ///      1e11 tokens = 1e29 wei). Sized large so reentrant burns produce reservations comparable
    ///      to the in-flight stETH (overcoming the design's 175% over-collateralization cushion).
    uint256 internal constant ATTACKER_FUNDING = 80_000_000_000 ether;

    /// @dev First (outer) burn amount.
    uint256 internal constant BURN_AMOUNT = 10_000_000_000 ether;

    Attacker internal attacker;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        attacker = new Attacker(address(sdgnrs), address(mockStETH));

        // Fund the game with ETH backing and credit claimable[SDGNRS] so the submit-time
        // pullRedemptionReserve ETH leg can physically segregate the 175% MAX into sDGNRS's balance.
        vm.deal(address(game), 1000 ether);
        _setGameClaimableSdgnrs(1000 ether);
        _setGameClaimablePool(uint128(1000 ether));

        // Fund the attacker contract with sDGNRS via the Reward pool (game is the authorized caller).
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, address(attacker), ATTACKER_FUNDING);
        vm.stopPrank();

        // Mock the coinflip surface so the BURNIE settle leg (redeemBurnieShare) and the
        // previewClaimCoinflips backing read are no-ops, keeping the focus on the ETH/stETH reserve
        // identity. previewClaimCoinflips returns 0 so BURNIE never inflates totalMoney.
        // The lootbox forward (game.resolveRedemptionLootbox) is left REAL so the claim's 50%
        // lootbox half physically LEAVES sDGNRS (pulled by the game as stETH when ETH is short),
        // exactly as in production — this removes the artificial over-collateral residual a no-op
        // mock would leave behind. The MODULE-side delegatecall target is mocked to a no-op so the
        // lootbox materialization loop returns without seeded game lootbox state, while the Game-side
        // body (the stETH pull that drains the lootbox half out of sDGNRS) runs for real.
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.previewClaimCoinflips.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.redeemBurnieShare.selector),
            abi.encode()
        );
        vm.mockCall(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeWithSelector(IGameLootboxModuleRRL.resolveRedemptionLootbox.selector),
            abi.encode()
        );
    }

    // =====================================================================
    //                       SEEDING / READER HELPERS
    // =====================================================================

    function _setGameClaimableSdgnrs(uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), GAME_CLAIMABLE_SLOT));
        uint256 word = uint256(vm.load(address(game), slot));
        word = (word & (type(uint256).max << 128)) | uint128(amount);
        vm.store(address(game), slot, bytes32(word));
    }

    function _setGameClaimablePool(uint128 amount) internal {
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(GAME_SLOT1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(amount) << 128);
        vm.store(address(game), bytes32(uint256(GAME_SLOT1)), bytes32(slot1Val));
    }

    /// @dev Resolve a day by pranking the game (deterministic roll; bypasses the VRF cycle so the
    ///      gambling-burn gates (gameOver/rngLocked/livenessTriggered) stay clean for the reentrant
    ///      burn inside the claim hook).
    function _resolveDay(uint32 dayToResolve, uint16 roll) internal {
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, uint24(dayToResolve));
    }

    /// @dev The reserve identity under audit (SOLVENCY-01): the contract's own backing (ETH + stETH)
    ///      must cover the segregated reservation tracker.
    function _reserveIdentityHolds() internal view returns (bool) {
        uint256 backing = address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs));
        return backing >= sdgnrs.pendingRedemptionEthValue();
    }

    // =====================================================================
    //                          THE REPRO
    // =====================================================================

    /// @notice End-to-end: a single attacker contract burns, the day resolves, and on claim the
    ///         attacker re-enters burn() during the mixed _payEth ETH .call. The reentrant submit
    ///         double-counts the in-flight stETH as free backing and reserves a NEW redemption; the
    ///         outer claim then ships the stETH out, leaving pendingRedemptionEthValue unbacked.
    function test_V62_03_RedemptionReentrancyHoldsReserveIdentity() public {
        // ---- 1. Outer gambling burn on day D. Reserves 175% MAX into pendingRedemptionEthValue;
        //         the ETH leg of pullRedemptionReserve segregates that ETH into sDGNRS's balance. ----
        uint24 dayD = game.currentDayView();
        attacker.outerBurn(BURN_AMOUNT);

        (uint96 owedBase, ) = sdgnrs.pendingRedemptions(address(attacker), uint24(dayD));
        assertGt(uint256(owedBase), 0, "precondition: outer burn must record a positive claim base");
        uint256 pendingAfterSubmit = sdgnrs.pendingRedemptionEthValue();
        assertGt(pendingAfterSubmit, 0, "precondition: submit must reserve the 175% MAX");
        assertTrue(_reserveIdentityHolds(), "precondition: reserve identity holds right after submit");

        // ---- 2. Advance the wall day and resolve day D at the MAX roll (175%) so the rolled payout
        //         is large. Still !gameOver/!rngLocked/!livenessTriggered (no VRF cycle ran). ----
        vm.warp(block.timestamp + 1 days);
        _resolveDay(dayD, 175);

        // Rolled ETH the claim will release; direct half is what _payEth pays the attacker.
        uint256 totalRolledEth = (uint256(owedBase) * 175) / 100;
        uint256 ethDirect = totalRolledEth / 2;

        // ---- 3. Engineer the MIXED _payEth branch at claim time: liquid ETH strictly between 0 and
        //         ethDirect, with stETH custodied to cover the remainder. We move all but `seedEth`
        //         of sDGNRS's ETH balance into stETH custody (mint stETH to sDGNRS, drain its ETH).
        //         seedEth (the .call value that fires the hook) is set to a small positive fraction
        //         of ethDirect so 0 < ethBal < ethDirect. ----
        uint256 seedEth = ethDirect / 4; // strictly between 0 and ethDirect
        assertGt(seedEth, 0, "precondition: seedEth must be > 0 so the ETH .call hook fires");

        // Re-shape sDGNRS custody so liquid ETH is below ethDirect (forces the mixed _payEth branch)
        // while total backing (ETH + stETH) EXACTLY covers pendingRedemptionEthValue (reserve identity
        // holds going in, at equality — no masking headroom). This models a fully-reserved contract
        // whose backing is partly held as stETH (a normal state: the submit reserve can take the stETH
        // leg, or stETH arrives as yield). Set ETH to seedEth and stETH to the exact remainder.
        uint256 pendingNow = sdgnrs.pendingRedemptionEthValue();
        vm.deal(address(sdgnrs), seedEth);
        // stETH custody = pendingNow - seedEth, so (ETH + stETH) == pendingNow exactly (no headroom).
        mockStETH.mint(address(sdgnrs), pendingNow - seedEth);

        // Snapshot the reserve identity BEFORE the claim.
        uint256 pendingBeforeClaim = sdgnrs.pendingRedemptionEthValue();
        uint256 backingBeforeClaim = address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs));
        emit log_named_uint("pendingRedemptionEthValue BEFORE claim", pendingBeforeClaim);
        emit log_named_uint("ETH+stETH held       BEFORE claim", backingBeforeClaim);
        emit log_named_uint("sDGNRS ETH           BEFORE claim", address(sdgnrs).balance);
        emit log_named_uint("sDGNRS stETH         BEFORE claim", mockStETH.balanceOf(address(sdgnrs)));
        assertTrue(_reserveIdentityHolds(), "precondition: reserve identity holds right before claim");
        assertLt(address(sdgnrs).balance, ethDirect, "precondition: ETH < ethDirect (forces _payEth mixed branch)");
        assertGt(address(sdgnrs).balance, 0, "precondition: ETH > 0 (mixed branch fires the .call hook)");

        // Deplete the GAME's liquid ETH and claimable[SDGNRS] so the reentrant submit's
        // pullRedemptionReserve CANNOT take the ETH leg (which would pull fresh ETH in to back the
        // new reservation, shifting the harm to an over-debit of the game's claimable instead). With
        // the ETH leg unavailable, pullRedemptionReserve takes the stETH leg: a pure no-op that only
        // INCREMENTS pendingRedemptionEthValue (via the caller) and brings NO new asset in — it
        // relies on the in-flight stETH still sitting in sDGNRS. The outer claim then ships that
        // stETH out, so the reservation ends up unbacked. (Mid-game ETH depletion is the documented
        // stETH-leg precondition; see RedemptionStethFallback test (b).)
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);

        // Arm the attacker to reentrantly submit fresh gambling burns inside its receive() hook.
        // Loop up to 64× so accumulated unbacked reservations overcome the 175% over-collateral
        // cushion left as residual free backing after the outer claim. Each iteration reserves a new
        // 175% MAX against the (double-counted) in-flight stETH via the pullRedemptionReserve stETH
        // leg, which brings NO asset in. Per-iteration amount is small enough to stay under the
        // 160 ETH per-(wallet,day) EV cap and the 50% per-day supply cap.
        attacker.arm(BURN_AMOUNT / 4, 64);

        // ---- 4. Fire the claim. The mixed _payEth .call re-enters the attacker; it submits new
        //         gambling burns while the stethOut is still custodied. ----
        attacker.claim(dayD);

        // Capture the backing the reentrant submit observed.
        bool reentrantBurnSucceeded = attacker.reentered();
        uint256 reentrantStethBacking = attacker.reentrantStethBalanceSeen();
        uint256 inFlightSteth = attacker.inFlightStethAtHook();
        uint256 reentrantCount = attacker.reentrantBurnCount();
        uint256 pendingAtHook = attacker.pendingSeenAtHook();
        uint256 pendingAfterReentrant = attacker.pendingSeenAfterReentrantBurns();

        emit log_named_string("reentrant burn succeeded", reentrantBurnSucceeded ? "YES" : "NO");
        emit log_named_uint("reentrant burns landed (count)     ", reentrantCount);
        emit log_named_uint("stETH balance reentrant submit saw", reentrantStethBacking);
        emit log_named_uint("in-flight stETH owed at hook       ", inFlightSteth);
        emit log_named_uint("pending at hook (post outer release)", pendingAtHook);
        emit log_named_uint("pending after reentrant burns       ", pendingAfterReentrant);

        // ---- 5. Reserve identity AFTER the full sequence. ----
        uint256 pendingAfterClaim = sdgnrs.pendingRedemptionEthValue();
        uint256 backingAfterClaim = address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs));
        emit log_named_uint("pendingRedemptionEthValue AFTER  claim", pendingAfterClaim);
        emit log_named_uint("ETH+stETH held       AFTER  claim", backingAfterClaim);
        emit log_named_uint("sDGNRS ETH           AFTER  claim", address(sdgnrs).balance);
        emit log_named_uint("sDGNRS stETH         AFTER  claim", mockStETH.balanceOf(address(sdgnrs)));
        emit log_named_uint("game claimable[SDGNRS] AFTER claim", uint128(uint256(vm.load(address(game), keccak256(abi.encode(address(sdgnrs), GAME_CLAIMABLE_SLOT))))));
        emit log_named_uint("game ETH balance       AFTER claim", address(game).balance);

        if (pendingAfterClaim > backingAfterClaim) {
            emit log_named_uint("UNBACKED reservation deficit (pending - held)", pendingAfterClaim - backingAfterClaim);
        }

        // ---- HEADLINE (FIXED): the stETH-before-ETH reorder in _payEth holds SOLVENCY-01 through
        //      the reentrant claim. The owed stETH ships BEFORE the untrusted ETH .call, so the
        //      reservation tracker never exceeds the ETH+stETH the contract holds. ----
        assertTrue(reentrantBurnSucceeded, "V62-03: reentry is still reachable (no guard) -- the fix neutralizes its EFFECT, not the reentry");
        assertGt(reentrantCount, 0, "V62-03: the reentrant gambling burns still land in the hook");
        assertLe(
            pendingAfterClaim,
            backingAfterClaim,
            "V62-03 FIXED: reserve identity holds (pendingRedemptionEthValue <= ETH+stETH held)"
        );
        assertTrue(_reserveIdentityHolds(), "V62-03 FIXED: SOLVENCY-01 holds after the reentrant claim");

        // ---- MECHANISM (FIXED): CEI. The outer claim decremented pending (pending == 0 at hook),
        //      AND the fix already shipped the owed stETH out before the ETH .call fired — so at the
        //      hook the in-flight owed stETH is GONE. The reentrant submit reads zero free stETH
        //      backing and reserves NOTHING against phantom backing. ----
        assertEq(pendingAtHook, 0, "V62-03: outer claim releases the reservation before the hook (pending == 0 at hook)");
        assertEq(inFlightSteth, 0, "V62-03 FIXED: owed stETH already shipped before the ETH hook (stETH-before-ETH CEI)");
        assertEq(
            reentrantStethBacking,
            0,
            "V62-03 FIXED: reentrant submit saw no free stETH backing (the owed stETH was already sent)"
        );
        assertEq(
            pendingAfterReentrant,
            pendingAtHook,
            "V62-03 FIXED: reentrant burns reserved nothing extra (no phantom backing to double-count)"
        );
    }
}

/// @notice Attacker contract: holds sDGNRS, drives an outer gambling burn + claim, and re-enters
///         burn() inside its receive() hook (fired by the mixed _payEth ETH .call).
contract Attacker {
    StakedDegenerusStonk private immutable sdgnrs;
    IMockStETHReader private immutable steth;

    bool private armed;
    uint256 private reentrantAmount;
    uint256 private maxIterations;

    bool public reentered;
    uint256 public reentrantBurnCount;
    uint256 public reentrantStethBalanceSeen;
    uint256 public inFlightStethAtHook;
    uint256 public pendingSeenAtHook;
    uint256 public pendingSeenAfterReentrantBurns;

    constructor(address _sdgnrs, address _steth) {
        sdgnrs = StakedDegenerusStonk(payable(_sdgnrs));
        steth = IMockStETHReader(_steth);
    }

    function outerBurn(uint256 amount) external {
        sdgnrs.burn(amount);
    }

    function arm(uint256 amount, uint256 iterations) external {
        armed = true;
        reentrantAmount = amount;
        maxIterations = iterations;
    }

    function claim(uint24 day) external {
        sdgnrs.claimRedemption(day);
    }

    /// @dev Fired by the mixed _payEth ETH .call. While this runs the outer claim has NOT yet
    ///      transferred the stethOut leg, so steth.balanceOf(sdgnrs) still includes the owed stETH
    ///      and pendingRedemptionEthValue has already been decremented for the rolled amount. We
    ///      re-enter burn() repeatedly: each submit reads stethBal = steth.balanceOf(this) (still
    ///      includes the in-flight owed stETH) and reserves a NEW 175% MAX redemption via the
    ///      pullRedemptionReserve stETH leg (which brings NO new asset in), accumulating unbacked
    ///      reservation in pendingRedemptionEthValue.
    receive() external payable {
        if (!armed) return;
        armed = false; // single-shot (only the OUTER claim's .call re-enters)

        // Observe the state the reentrant backing calc will read.
        inFlightStethAtHook = steth.balanceOf(address(sdgnrs));
        pendingSeenAtHook = sdgnrs.pendingRedemptionEthValue();

        for (uint256 i = 0; i < maxIterations; i++) {
            try sdgnrs.burn(reentrantAmount) {
                reentrantBurnCount++;
                reentered = true;
                reentrantStethBalanceSeen = steth.balanceOf(address(sdgnrs));
            } catch {
                break; // stop on the first revert (cap hit / coverage exhausted)
            }
        }
        pendingSeenAfterReentrantBurns = sdgnrs.pendingRedemptionEthValue();
    }
}

interface IMockStETHReader {
    function balanceOf(address account) external view returns (uint256);
}
