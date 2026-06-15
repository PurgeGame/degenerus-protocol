// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @notice Local mirror of the coinflip player surface for vm.mockCall selectors. The submit BURNIE
///         leg (the settled backing read redeemableCoinBacking and the backing withdraw
///         withdrawRedeemedBurnie) is mocked to no-ops so the focus stays on the ETH/stETH reserve
///         identity; with redeemableCoinBacking forced to 0 the escrowed slice is 0, so the
///         claim-time BURNIE leg is skipped entirely.
interface IBurnieCoinflipPlayerMock {
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    function redeemableCoinBacking() external returns (uint256 backing);
    function withdrawRedeemedBurnie(uint256 base) external;
}

/// @title V62RedemptionReentrancy -- regression for finding V62-03 (verifies the layered FIX).
///        The vuln description below is retained as context for what the fixes prevent.
///
/// @notice V62-03 (adjudicated vs frozen c4d48008): StakedDegenerusStonk.sol has NO reentrancy
///         guard. `claimRedemption` decrements `pendingRedemptionEthValue -= totalRolledEth`
///         and deletes the per-(player,day) claim slot BEFORE the payout. The payout's
///         `_payEth(player, ethDirect)` MIXED branch (ethDirect > liquid ETH) originally sent
///         `ethOut = ethBal` to the player via `player.call{value:ethOut}` FIRST, THEN
///         `steth.transfer(player, stethOut)`. The ETH `.call` re-enters the attacker's
///         receive() hook while `stethOut` is STILL custodied in the sDGNRS contract, letting a
///         reentrant burn() count the in-flight stETH as free backing — breaking the redemption
///         reserve / SOLVENCY-01 identity
///           pendingRedemptionEthValue <= ETH held + stETH held.
///
///         TWO independent layers now close the class, pinned by one test each:
///
///         1. test_V62_03_LiveClaim_RunsNoClaimantCode — the live-game claim routes BOTH halves
///            to the GAME (direct half = game-claimable credit, lootbox half = lootbox funding)
///            and pushes NOTHING at the claimant, so no claimant-controlled code runs at all:
///            the re-entry surface is gone by construction mid-game.
///
///         2. test_V62_03_GameOverClaim_PayEthCEIHoldsReserveIdentity — _payEth survives only on
///            the post-gameOver path (100% direct, self-claim). Its stETH-before-ETH order
///            (CEI) ships the owed stETH BEFORE the untrusted ETH .call, so a reentrant
///            gameOver deterministic burn() inside the hook reads backing that EXCLUDES the
///            in-flight stETH and extracts nothing extra.
///
/// @dev TEST-ONLY. No contracts/*.sol are touched.
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

        // Mock the coinflip surface so the submit BURNIE leg is a no-op, keeping the focus on the
        // ETH/stETH reserve identity. redeemableCoinBacking returns 0 so the escrowed slice is 0 (the
        // claim-time BURNIE leg is then skipped); withdrawRedeemedBurnie is a no-op belt-and-suspenders.
        // The lootbox forward (game.resolveRedemptionLootbox) runs fully UNMOCKED: the module body
        // (auth, msg.value bound, stETH pull, pool credit, chunked materialization) executes for
        // real, so the claim's 50% lootbox half physically LEAVES sDGNRS exactly as in production
        // and the no-claimant-code / value-arrival assertions cover the end-to-end path.
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.previewClaimCoinflips.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.redeemableCoinBacking.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.withdrawRedeemedBurnie.selector),
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

    /// @notice Layer 1 — the LIVE-GAME claim runs no claimant-controlled code at all. Both
    ///         halves of the rolled ETH route to the GAME (direct half = game-claimable credit,
    ///         lootbox half = lootbox funding); nothing is pushed at the claimant, so an armed
    ///         attacker's receive() hook never fires and the re-entry surface does not exist.
    function test_V62_03_LiveClaim_RunsNoClaimantCode() public {
        // ---- 1. Outer gambling burn on day D. Reserves 175% MAX into pendingRedemptionEthValue;
        //         the ETH leg of pullRedemptionReserve segregates that ETH into sDGNRS's balance. ----
        uint24 dayD = game.currentDayView();
        // Land day D's daily RNG so the gambling-burn admission gate (rngWordForDay(D) != 0) admits
        // this burn; under the gate the pool resolves on the NEXT day's draw (window-(b)).
        _primeCurrentDayRng();
        attacker.outerBurn(BURN_AMOUNT);

        (uint96 owedBase, , ) = sdgnrs.pendingRedemptions(address(attacker), uint24(dayD));
        assertGt(uint256(owedBase), 0, "precondition: outer burn must record a positive claim base");
        assertTrue(_reserveIdentityHolds(), "precondition: reserve identity holds right after submit");

        // ---- 2. Advance the wall day and resolve day D at the MAX roll (175%) so the rolled payout
        //         is large. Still !gameOver/!rngLocked/!livenessTriggered (no VRF cycle ran). ----
        vm.warp(block.timestamp + 1 days);
        _resolveDay(dayD, 175);

        uint256 totalRolledEth = (uint256(owedBase) * 175) / 100;
        uint256 ethDirect = totalRolledEth / 2;
        uint256 lootboxEth = totalRolledEth - ethDirect;

        // ---- 3. Custody shaping: liquid ETH strictly between 0 and the rolled amount with stETH
        //         covering the exact remainder (no headroom), so BOTH game legs exercise the
        //         msg.value + stETH-remainder funding mix. ----
        uint256 seedEth = ethDirect / 4;
        assertGt(seedEth, 0, "precondition: seedEth must be > 0");
        uint256 pendingNow = sdgnrs.pendingRedemptionEthValue();
        vm.deal(address(sdgnrs), seedEth);
        mockStETH.mint(address(sdgnrs), pendingNow - seedEth);
        assertTrue(_reserveIdentityHolds(), "precondition: reserve identity holds right before claim");

        // Deplete the GAME's liquid ETH and claimable[SDGNRS]: the claim must succeed with the
        // value arriving from sDGNRS custody alone (stETH pulls), not from any game-side reserve.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);

        // Arm the attacker exactly as the pre-fix exploit would — the hook must never fire.
        attacker.arm(BURN_AMOUNT / 4, 64);

        // ---- 4. Fire the claim (sets rngWordForDay(D+1), the word the lootbox leg keys to). ----
        _primeCurrentDayRng();
        uint256 attackerEthBefore = address(attacker).balance;
        uint256 attackerStethBefore = mockStETH.balanceOf(address(attacker));
        uint256 gameValueBefore = address(game).balance + mockStETH.balanceOf(address(game));
        attacker.claim(dayD);

        // ---- HEADLINE: no claimant code ran — the re-entry surface is gone by construction. ----
        assertFalse(attacker.reentered(), "V62-03 L1: claimant hook fired during a live-game claim");
        assertEq(attacker.reentrantBurnCount(), 0, "V62-03 L1: reentrant burns landed in the hook");
        assertEq(address(attacker).balance, attackerEthBefore, "V62-03 L1: live-game claim pushed ETH at the claimant");
        assertEq(
            mockStETH.balanceOf(address(attacker)),
            attackerStethBefore,
            "V62-03 L1: live-game claim pushed stETH at the claimant"
        );

        // The direct half landed as a game-claimable credit; the full rolled value moved to the
        // GAME (seedEth as msg.value, the remainder as stETH pulls across the two legs).
        assertEq(
            game.claimableWinningsOf(address(attacker)),
            ethDirect,
            "V62-03 L1: direct half must credit the claimant's game claimable"
        );
        assertEq(
            address(game).balance + mockStETH.balanceOf(address(game)) - gameValueBefore,
            ethDirect + lootboxEth,
            "V62-03 L1: full rolled value must arrive at the game"
        );

        // Reservation fully released and the reserve identity holds.
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "V62-03 L1: reservation not fully released");
        assertTrue(_reserveIdentityHolds(), "V62-03 L1: SOLVENCY-01 holds after the claim");
    }

    /// @notice Layer 2 — the POST-GAMEOVER claim still pays via _payEth (100% direct, self-claim,
    ///         no lootbox leg). Its stETH-before-ETH order (CEI) ships the owed stETH BEFORE the
    ///         untrusted ETH .call, so the attacker's hook re-enters a gameOver deterministic
    ///         burn() against backing that EXCLUDES the in-flight stETH and extracts nothing.
    function test_V62_03_GameOverClaim_PayEthCEIHoldsReserveIdentity() public {
        // ---- 1. Outer gambling burn + resolve at the MAX roll, exactly as in Layer 1. ----
        uint24 dayD = game.currentDayView();
        _primeCurrentDayRng();
        attacker.outerBurn(BURN_AMOUNT);

        (uint96 owedBase, , ) = sdgnrs.pendingRedemptions(address(attacker), uint24(dayD));
        assertGt(uint256(owedBase), 0, "precondition: outer burn must record a positive claim base");

        vm.warp(block.timestamp + 1 days);
        _resolveDay(dayD, 175);

        // gameOver latches AFTER the resolve: the claim now pays 100% direct via _payEth.
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(true));

        uint256 totalRolledEth = (uint256(owedBase) * 175) / 100;
        uint256 ethDirect = totalRolledEth; // gameOver: no lootbox leg

        // ---- 2. Engineer the MIXED _payEth branch: liquid ETH strictly between 0 and ethDirect,
        //         stETH covering the exact remainder (no masking headroom). ----
        uint256 seedEth = ethDirect / 4;
        assertGt(seedEth, 0, "precondition: seedEth must be > 0 so the ETH .call hook fires");
        uint256 pendingNow = sdgnrs.pendingRedemptionEthValue();
        vm.deal(address(sdgnrs), seedEth);
        mockStETH.mint(address(sdgnrs), pendingNow - seedEth);
        assertLt(address(sdgnrs).balance, ethDirect, "precondition: ETH < ethDirect (forces _payEth mixed branch)");

        // Zero the game-side claimable so the reentrant deterministic burn's backing read has no
        // claimable term — its only possible phantom source is the in-flight stETH itself.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);

        // Arm the attacker: the hook re-enters burn(), which under gameOver is the DETERMINISTIC
        // path — it would pay out immediately against any backing it can see.
        attacker.arm(BURN_AMOUNT / 4, 64);

        // ---- 3. Fire the self-claim. The mixed _payEth ships stETH first, then the ETH .call
        //         fires the hook. ----
        uint256 attackerEthBefore = address(attacker).balance;
        uint256 attackerStethBefore = mockStETH.balanceOf(address(attacker));
        attacker.claim(dayD);

        bool reentrantBurnSucceeded = attacker.reentered();
        uint256 reentrantCount = attacker.reentrantBurnCount();
        uint256 inFlightSteth = attacker.inFlightStethAtHook();
        uint256 reentrantStethBacking = attacker.reentrantStethBalanceSeen();
        uint256 pendingAtHook = attacker.pendingSeenAtHook();

        emit log_named_string("reentrant burn succeeded", reentrantBurnSucceeded ? "YES" : "NO");
        emit log_named_uint("reentrant burns landed (count)      ", reentrantCount);
        emit log_named_uint("in-flight stETH owed at hook        ", inFlightSteth);
        emit log_named_uint("stETH balance reentrant burn saw    ", reentrantStethBacking);
        emit log_named_uint("pending at hook (post outer release)", pendingAtHook);

        // ---- HEADLINE: the re-entry is reachable (no guard) but extracts NOTHING — the owed
        //      stETH shipped before the hook, so the deterministic burns see zero backing. ----
        assertTrue(reentrantBurnSucceeded, "V62-03 L2: reentry is still reachable (no guard) -- the fix neutralizes its EFFECT");
        assertGt(reentrantCount, 0, "V62-03 L2: the reentrant gameOver burns still land in the hook");
        assertEq(pendingAtHook, 0, "V62-03 L2: outer claim releases the reservation before the hook");
        assertEq(inFlightSteth, 0, "V62-03 L2: owed stETH already shipped before the ETH hook (stETH-before-ETH CEI)");
        assertEq(reentrantStethBacking, 0, "V62-03 L2: reentrant burn saw no free stETH backing");

        // The attacker's TOTAL receipts equal exactly the one entitled payout (ethDirect): seedEth
        // arrived as the .call value, the remainder as the pre-hook stETH ship. The reentrant
        // deterministic burns inside the hook burned tokens against zero backing and added nothing.
        assertEq(
            (address(attacker).balance - attackerEthBefore) +
                (mockStETH.balanceOf(address(attacker)) - attackerStethBefore),
            ethDirect,
            "V62-03 L2: attacker receipts != the single entitled payout (reentry extracted value)"
        );

        assertTrue(_reserveIdentityHolds(), "V62-03 L2: SOLVENCY-01 holds after the reentrant claim");
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
        sdgnrs.claimRedemption(address(this), day);
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
