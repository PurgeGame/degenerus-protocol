// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
// v55.0 D-351-02: the `AfKing` import is DROPPED — the standalone de-custody contract
// (contracts/AfKing.sol) was DELETED (ARCH-03; funding is game-resident afkingFunding).
// The redemption ETH-vs-stETH core does not need the AfKing type; the POOL-04 receive()
// tests reframe onto the GAME-only receive() gate (StakedDegenerusStonk.sol:433-434).

/// @notice Local mirror of the coinflip player surface for vm.mockCall selectors. Mirrors the
///         interface in StakedStonkRedemption.t.sol / RedemptionGas.t.sol; redeclared locally so
///         this file does not depend on the coinflip contract import.
interface IBurnieCoinflipPlayerMock {
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win);
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);
}

/// @title RedemptionStethFallback — F-47-02 stETH-fallback path (RFALL-05) + POOL-04 receive() safety
/// @notice Deterministic scenario tests against the APPLIED Phase-326 diff that DRIVE each branch of
///         `DegenerusGame.pullRedemptionReserve` (ETH leg / stETH fallback / fail-closed revert) and
///         re-assert the v47 REDEEM-08 invariants under stETH coverage. Also proves the sDGNRS
///         `receive()` credit path is accounting-safe (POOL-04).
///
///         v55.0 D-351-02 adaptation: the v54 de-custody machinery dissolved (AfKing removed,
///         funding is game-resident `afkingFunding`). Two changes vs the v54 baseline:
///           (1) the POOL-04 receive() tests are REFRAMED onto the v55 GAME-only `receive()` gate
///               (StakedDegenerusStonk.sol:433-434 now `if (msg.sender != GAME) revert Unauthorized`);
///               the v54 AF_KING relaxation is GONE (the afking-funding withdraw send-back routes
///               through GAME — the Game's `.call` has `msg.sender == GAME`). The live-balance /
///               counted-once / arbitrary-vector properties are UNCHANGED — only the authorized
///               sender moved from AF_KING to GAME.
///           (2) the v54 `burnAtGameOver`-recovers-the-AfKing-prepaid-pool leg is DROPPED BY NAME
///               (no behavioral successor — `burnAtGameOver` is now a pure local-token burn,
///               StakedDegenerusStonk.sol:526-535, and `depositFor`/`poolOf`/`withdraw` no longer
///               exist). See 351-06-SUMMARY for the BY-NAME drop ledger entry.
///
///         The fix is the pure-ETH-OR-pure-stETH coverage branch in `pullRedemptionReserve`
///         (DegenerusGame.sol ~:1895): the ETH leg moves the at-risk claim-on-game ETH into sDGNRS
///         custody (CHECKED claimable[SDGNRS]/claimablePool debit + CEI ETH call); the stETH leg is a
///         no-op on the game (sDGNRS's own stETH already backs the reservation in safe custody); the
///         submit reverts fail-closed only when NEITHER pure leg covers `maxIncrement`. The single
///         `pendingRedemptionEthValue` (D-06) records the reservation either way; `_payEth` selects the
///         payout asset at claim (ETH-first, stETH-fallback).
///
///         False-confidence guard (threat T-327-02-FC1/FC2/FC3): each stETH-leg test EXPLICITLY
///         asserts the branch it intends to take was actually taken — for the stETH leg, game ETH
///         (or claimable[SDGNRS]) < maxIncrement BEFORE the pull AND claimable[SDGNRS]/claimablePool
///         UNCHANGED AFTER, proving the stETH leg ran rather than the ETH leg.
///
/// @dev Run:
///        forge test --match-path test/fuzz/RedemptionStethFallback.t.sol -vv
///      Subject FROZEN at the Phase-326 diff (HEAD); ZERO contracts/*.sol edits.
contract RedemptionStethFallback is DeployProtocol {
    // =====================================================================
    //                          CONSTANTS / SLOTS
    // =====================================================================

    /// @dev DegenerusGame.balancesPacked (internal mapping) at slot 7 (v61 PACK fold). The
    ///      low 128 bits = claimable (the old claimableWinnings semantics, _claimableOf); the
    ///      high 128 bits = afking funding (_afkingOf). A claimable seed writes the LOW half only.
    uint256 internal constant GAME_CLAIMABLE_SLOT = 7;

    /// @dev DegenerusGame.claimablePool lives in the upper 128 bits of slot 1 (RedemptionGas /
    ///      StakedStonkRedemption seed it there).
    uint256 internal constant GAME_SLOT1 = 1;

    /// @dev Per-actor sDGNRS funding (Reward pool draw). 1M tokens → ample for repeated burns.
    uint256 internal constant ACTOR_FUNDING = 1_000_000 ether;

    /// @dev Burn amount that produces a positive (post-gwei-snap) ethValueOwed under the seeded
    ///      backing. At INITIAL_SUPPLY ≈ 1e30 and totalMoney = 100 ether, ethValueOwed ≈ amount/1e10,
    ///      so 1_000_000 ether (1e24) → ethValueOwed ≈ 1e14 wei (0.0001 ETH); maxIncrement ≈ 1.75e14.
    uint256 internal constant BURN_AMOUNT = 1_000_000 ether;

    /// @dev MAX_ROLL mirror (private literal `175` in sStonk): the 175% reservation multiplier.
    uint256 internal constant MAX_ROLL = 175;

    // =====================================================================
    //                          ACTORS
    // =====================================================================

    address internal playerA;
    address internal playerB;

    function setUp() public {
        _deployProtocol();
        // Warp 1 day past the deploy-pinned timestamp so currentDayView() is off day 0
        // (RedemptionGas.t.sol / StakedStonkRedemption.t.sol setUp precedent).
        vm.warp(block.timestamp + 1 days);

        playerA = makeAddr("playerA");
        playerB = makeAddr("playerB");
        vm.deal(playerA, 10 ether);
        vm.deal(playerB, 10 ether);

        // Fund actors with sDGNRS via the Reward pool (game is the authorized caller).
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, playerA, ACTOR_FUNDING);
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, playerB, ACTOR_FUNDING);
        vm.stopPrank();

        // Mock coinflip player surface so the claim full-payout branch resolves without seeded
        // coinflip state (StakedStonkRedemption.t.sol precedent).
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.getCoinflipDayResult.selector),
            abi.encode(uint16(100), true)
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.claimCoinflipsForRedemption.selector),
            abi.encode(uint256(0))
        );
        // Mock the lootbox materialization (the 50% lootbox routing in claim) to a no-op so the
        // sStonk-surface assertions don't depend on seeded game-side lootbox slots.
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(game.resolveRedemptionLootbox.selector),
            abi.encode()
        );
    }

    // =====================================================================
    //                       SEEDING / READER HELPERS
    // =====================================================================

    /// @dev Seed the game's claimable[SDGNRS] (low 128 bits of balancesPacked[SDGNRS], slot 7).
    ///      Preserves the afking high half so a claimable-only seed cannot corrupt _afkingOf.
    function _setGameClaimableSdgnrs(uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), GAME_CLAIMABLE_SLOT));
        uint256 word = uint256(vm.load(address(game), slot));
        word = (word & (type(uint256).max << 128)) | uint128(amount);
        vm.store(address(game), slot, bytes32(word));
    }

    /// @dev Seed the game's claimablePool (upper 128 bits of slot 1).
    function _setGameClaimablePool(uint128 amount) internal {
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(GAME_SLOT1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(amount) << 128);
        vm.store(address(game), bytes32(uint256(GAME_SLOT1)), bytes32(slot1Val));
    }

    /// @dev Read claimable[SDGNRS] = low 128 bits of balancesPacked[SDGNRS] (so a hypothetical
    ///      wrap/underflow of the claimable half is observable; the afking high half is masked off).
    function _claimableSdgnrs() internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), GAME_CLAIMABLE_SLOT));
        return uint128(uint256(vm.load(address(game), slot)));
    }

    /// @dev Resolve a day's pool by pranking the game (bypass the full advance + VRF cycle for a
    ///      deterministic roll). StakedStonkRedemption.t.sol :_resolveDay precedent.
    function _resolveDay(uint32 dayToResolve, uint16 roll) internal {
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, uint24(dayToResolve));
    }

    /// @dev THE load-bearing v47 REDEEM-08 solvency invariant under the fallback: sDGNRS's own
    ///      backing (its ETH balance + its stETH balance) covers both the segregated reservation
    ///      (pendingRedemptionEthValue) and the global claimable pool's sDGNRS slice. The segregated
    ///      redemption ETH/stETH physically lives in the sDGNRS contract.
    function _assertSolvency(string memory tag) internal view {
        uint256 backing = address(sdgnrs).balance + mockStETH.balanceOf(address(sdgnrs));
        assertGe(
            backing,
            sdgnrs.pendingRedemptionEthValue(),
            string.concat(tag, ": balance+stETH < pendingRedemptionEthValue (reservation under-backed)")
        );
        // claimablePool (global) must cover claimableWinnings[SDGNRS] (its slice) — a paired-debit
        // drift / wrap would break it.
        assertGe(
            game.claimablePoolView(),
            _claimableSdgnrs(),
            string.concat(tag, ": claimablePool < claimableWinnings[SDGNRS] (paired debit drifted)")
        );
    }

    // =====================================================================
    //   (a) test_RFALL05_EthLeg_HappyPath
    // =====================================================================

    /// @notice ETH leg: claimable[SDGNRS] AND game ETH both cover the 175% MAX → the ETH leg runs.
    ///         claimable[SDGNRS] and claimablePool both decrement by maxIncrement; the ETH lands at
    ///         sDGNRS; submit succeeds. Solvency holds after submit.
    function test_RFALL05_EthLeg_HappyPath() public {
        // Seed: game ETH = 100, claimable[SDGNRS] = 100, claimablePool = 100. No stETH on sDGNRS.
        vm.deal(address(game), 100 ether);
        _setGameClaimableSdgnrs(100 ether);
        _setGameClaimablePool(uint128(100 ether));

        uint256 claimableBefore = _claimableSdgnrs();
        uint256 poolBefore = game.claimablePoolView();
        uint256 sdgnrsBalBefore = address(sdgnrs).balance;
        uint256 pendingBefore = sdgnrs.pendingRedemptionEthValue();

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(BURN_AMOUNT);

        uint256 maxIncrement = sdgnrs.pendingRedemptionEthValue() - pendingBefore;
        assertGt(maxIncrement, 0, "(a) reservation must be non-zero for this burn size");

        // ETH leg PROOF: claimable[SDGNRS] and claimablePool both decremented by EXACTLY maxIncrement,
        // and the ETH physically moved into sDGNRS's balance.
        assertEq(
            _claimableSdgnrs(),
            claimableBefore - maxIncrement,
            "(a) ETH leg: claimable[SDGNRS] not debited by maxIncrement"
        );
        assertEq(
            game.claimablePoolView(),
            poolBefore - maxIncrement,
            "(a) ETH leg: claimablePool not debited by maxIncrement"
        );
        assertEq(
            address(sdgnrs).balance,
            sdgnrsBalBefore + maxIncrement,
            "(a) ETH leg: maxIncrement ETH did not land in sDGNRS balance"
        );

        _assertSolvency("(a)");
    }

    // =====================================================================
    //   (b) test_RFALL05_StethFallback_MidGameEthDepletion
    // =====================================================================

    /// @notice stETH fallback: game ETH < maxIncrement (mid-game depletion) but sDGNRS holds enough
    ///         stETH → the stETH leg runs. Submit does NOT revert, NO game-side ETH move, NO ledger
    ///         debit (claimable[SDGNRS]/claimablePool UNCHANGED), and pendingRedemptionEthValue still
    ///         increments by maxIncrement. The claim then pays stETH (asset selection matches the
    ///         reserved asset, RFALL-03) and value is conserved. Solvency holds throughout.
    function test_RFALL05_StethFallback_MidGameEthDepletion() public {
        // Mid-game ETH depletion: starve the game of liquid ETH AND of claimable[SDGNRS], so the ETH
        // leg cannot run. Back the reservation entirely with sDGNRS's OWN stETH.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);
        // sDGNRS holds plenty of stETH (its own custody) — covers any plausible maxIncrement.
        mockStETH.mint(address(sdgnrs), 100 ether);

        uint256 claimableBefore = _claimableSdgnrs(); // == 0
        uint256 poolBefore = game.claimablePoolView(); // == 0
        uint256 gameEthBefore = address(game).balance; // == 0
        uint256 sdgnrsEthBefore = address(sdgnrs).balance;
        uint256 sdgnrsStethBefore = mockStETH.balanceOf(address(sdgnrs));
        uint256 pendingBefore = sdgnrs.pendingRedemptionEthValue();

        uint32 burnDay = game.currentDayView();

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(BURN_AMOUNT);

        uint256 maxIncrement = sdgnrs.pendingRedemptionEthValue() - pendingBefore;
        assertGt(maxIncrement, 0, "(b) reservation must be non-zero for this burn size");

        // BRANCH PROOF (T-327-02-FC1): the ETH leg could NOT have run — game ETH was 0 < maxIncrement
        // BEFORE the pull, so the only way submit succeeded is the stETH leg.
        assertEq(gameEthBefore, 0, "(b) precondition: game ETH must be depleted below maxIncrement");
        assertLt(gameEthBefore, maxIncrement, "(b) precondition: game ETH < maxIncrement");
        // ... and the stETH side DID cover it.
        assertGe(sdgnrsStethBefore, maxIncrement, "(b) precondition: sDGNRS stETH must cover maxIncrement");

        // stETH leg = NO game-side move, NO ledger debit.
        assertEq(_claimableSdgnrs(), claimableBefore, "(b) stETH leg: claimable[SDGNRS] must be UNCHANGED");
        assertEq(game.claimablePoolView(), poolBefore, "(b) stETH leg: claimablePool must be UNCHANGED");
        assertEq(address(game).balance, gameEthBefore, "(b) stETH leg: game ETH balance must be UNCHANGED");
        assertEq(address(sdgnrs).balance, sdgnrsEthBefore, "(b) stETH leg: sDGNRS ETH balance must be UNCHANGED");
        assertEq(
            mockStETH.balanceOf(address(sdgnrs)),
            sdgnrsStethBefore,
            "(b) stETH leg: sDGNRS stETH balance must be UNCHANGED at submit (no move)"
        );

        // ... but the single tracker DID record the reservation (D-06).
        assertEq(
            sdgnrs.pendingRedemptionEthValue(),
            pendingBefore + maxIncrement,
            "(b) stETH leg: pendingRedemptionEthValue must still increment by maxIncrement"
        );

        _assertSolvency("(b) post-submit");

        // === Claim moves the direct half in stETH (RFALL-03 claim-asset selection matches the
        //     reserved asset; the medium lands at the GAME, backing the player's claimable credit) ===
        // Resolve at roll=100 (1:1) and claim. With game.gameOver()==false the claim splits 50/50
        // (direct/lootbox); the lootbox leg is mocked to a no-op, so only the direct half moves.
        _advanceWallDayAndResolve(burnDay, 100);

        uint256 playerEthBefore = playerA.balance;
        uint256 playerStethBefore = mockStETH.balanceOf(playerA);
        uint256 playerClaimableBefore = game.claimableWinningsOf(playerA);
        uint256 gameStethBefore = mockStETH.balanceOf(address(game));

        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(burnDay));

        // Live game: nothing is pushed at the claimant — the direct half is a game-claimable credit.
        assertEq(playerA.balance - playerEthBefore, 0, "(b) claim: no ETH pushed at the claimant (live game)");
        assertEq(
            mockStETH.balanceOf(playerA) - playerStethBefore,
            0,
            "(b) claim: no stETH pushed at the claimant (live game)"
        );
        uint256 credited = game.claimableWinningsOf(playerA) - playerClaimableBefore;
        assertGt(credited, 0, "(b) claim: direct half must credit the player's game claimable");

        // sDGNRS held ZERO ETH (game depleted, ETH leg never ran), so the direct half MUST move
        // into the GAME as stETH (msg.value == 0 → the full amount arrives via the stETH pull).
        assertEq(
            mockStETH.balanceOf(address(game)) - gameStethBefore,
            credited,
            "(b) claim: direct half must arrive at the game in stETH (RFALL-03)"
        );

        // Conservation: the credited amount equals the segregated value leaving sDGNRS's stETH balance.
        assertEq(
            mockStETH.balanceOf(address(sdgnrs)),
            sdgnrsStethBefore - credited,
            "(b) conservation: sDGNRS stETH decreased by exactly the direct credit"
        );

        _assertSolvency("(b) post-claim");
    }

    // =====================================================================
    //   (b2) test_RFALL_C2_StethOnlyClaim_RealForward_NoStrand
    // =====================================================================

    /// @notice C-2 strand regression. With sDGNRS mid-game ETH-depleted (0 ETH, stETH-only) AND the
    ///         REAL lootbox forward un-mocked, claimRedemption must NOT strand. Pre-fix the claim
    ///         forwarded the lootbox half as `{value: lootboxEth}` ETH, which reverts when liquid ETH
    ///         < lootboxEth, reverting the whole claim despite stETH fully backing it (the suite's
    ///         setUp no-op mock was MASKING this). The fix funds the leg as a mix: msg.value carries
    ///         whatever ETH is free, the GAME pulls the remainder as stETH (here the full half, since
    ///         ETH is 0). So the claim succeeds — the game's stETH balance rises by the lootbox half,
    ///         and the player is paid the direct half in stETH.
    function test_RFALL_C2_StethOnlyClaim_RealForward_NoStrand() public {
        // Drop the setUp lootbox no-op so the REAL funding path runs; re-establish only the coinflip
        // mocks the burn/claim still need (the lootbox resolution itself is left real).
        vm.clearMockedCalls();
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.getCoinflipDayResult.selector),
            abi.encode(uint16(100), true)
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.claimCoinflipsForRedemption.selector),
            abi.encode(uint256(0))
        );

        // Mid-game ETH depletion: zero ETH anywhere the claim could draw on; stETH-only backing.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);
        mockStETH.mint(address(sdgnrs), 100 ether);

        uint32 burnDay = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(BURN_AMOUNT);

        _advanceWallDayAndResolve(burnDay, 100);

        assertEq(address(sdgnrs).balance, 0, "(b2) precondition: sDGNRS must hold ZERO ETH (depleted)");
        uint256 gameStethBefore = mockStETH.balanceOf(address(game));
        uint256 playerStethBefore = mockStETH.balanceOf(playerA);
        uint256 playerClaimableBefore = game.claimableWinningsOf(playerA);

        // THE PoC: pre-fix this reverts (ETH-only {value: lootboxEth} forward against a 0 balance);
        // post-fix it succeeds via the stETH pull.
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(burnDay));

        // Both halves were funded by stETH pulls into the game (msg.value was 0 on each leg).
        assertGt(
            mockStETH.balanceOf(address(game)),
            gameStethBefore,
            "(b2) both legs must have pulled stETH into the game (mixed-fund path)"
        );
        // The player's direct half landed as a game-claimable credit (nothing pushed at the claimant).
        assertEq(
            mockStETH.balanceOf(playerA),
            playerStethBefore,
            "(b2) no stETH pushed at the claimant (live game)"
        );
        assertGt(
            game.claimableWinningsOf(playerA),
            playerClaimableBefore,
            "(b2) direct half must credit the player's game claimable"
        );
        _assertSolvency("(b2) post-claim");
    }

    // =====================================================================
    //   (c) test_RFALL05_DonationRobust_StethForceFeed
    // =====================================================================

    /// @notice Donation-robust (T-327-02-FC2): force-feed sDGNRS extra stETH (a donation that inflates
    ///         totalMoney's stETH term beyond claimable[SDGNRS]). Submit MUST NOT brick — coverage is
    ///         checked against steth.balanceOf(SDGNRS), the SAME basis the donation inflated. Submit
    ///         succeeds and solvency holds.
    function test_RFALL05_DonationRobust_StethForceFeed() public {
        // Game ETH depleted + claimable[SDGNRS] = 0 so the ETH leg can't run. The submit base
        // (totalMoney = balance + stETH + claimable - pending) is inflated entirely by the stETH
        // DONATION below; without the stETH leg's check-against-stETH-balance the reservation would
        // brick (claimable can't cover, ETH can't cover) — this proves it does not.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);

        // FORCE-FEED: a large stETH donation directly into sDGNRS (the donation that inflates the base).
        uint256 donation = 500 ether;
        mockStETH.mint(address(sdgnrs), donation);

        uint256 claimableBefore = _claimableSdgnrs();
        uint256 poolBefore = game.claimablePoolView();
        uint256 sdgnrsStethBefore = mockStETH.balanceOf(address(sdgnrs));
        uint256 pendingBefore = sdgnrs.pendingRedemptionEthValue();

        // MUST NOT REVERT despite claimable[SDGNRS] == 0 and game ETH == 0 — the donated stETH covers.
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(BURN_AMOUNT);

        uint256 maxIncrement = sdgnrs.pendingRedemptionEthValue() - pendingBefore;
        assertGt(maxIncrement, 0, "(c) reservation must be non-zero");

        // stETH leg ran on the donated basis: no ledger debit, donation backs the reservation.
        assertEq(_claimableSdgnrs(), claimableBefore, "(c) claimable[SDGNRS] must be UNCHANGED");
        assertEq(game.claimablePoolView(), poolBefore, "(c) claimablePool must be UNCHANGED");
        assertGe(sdgnrsStethBefore, maxIncrement, "(c) donation must cover maxIncrement (same basis)");

        _assertSolvency("(c)");
    }

    // =====================================================================
    //   (d) test_RFALL05_FailClosed_NeitherLegCovers
    // =====================================================================

    /// @notice Fail-closed (T-327-02-FC3): neither game ETH/claimable nor sDGNRS stETH covers the 175%
    ///         MAX → submit REVERTS, with NO partial state mutation leaked (claimablePool and
    ///         pendingRedemptionEthValue unchanged).
    function test_RFALL05_FailClosed_NeitherLegCovers() public {
        // To DRIVE a non-zero maxIncrement that NEITHER leg can cover, the submit base
        // (totalMoney = ethBal + stethBal + claimable - pending) must be positive WHILE both the
        // game's segregation sources are too small to cover the resulting 175% reservation.
        //
        // Seed the base ENTIRELY from claimable[SDGNRS] (the view _claimableWinnings reads
        // game.claimableWinningsOf(sdgnrs)), so totalMoney > 0 and maxIncrement > 0, but then make
        // BOTH segregation legs fail: game's LIQUID ETH = 0 (ETH leg fails on the balance check) and
        // sDGNRS holds ZERO stETH (stETH leg fails). claimable[SDGNRS] alone is NOT a coverage leg in
        // pullRedemptionReserve — the ETH leg ALSO requires address(game).balance >= amount.
        vm.deal(address(game), 0); // game liquid ETH = 0 → ETH-leg balance check fails
        _setGameClaimableSdgnrs(100 ether); // inflates the base so maxIncrement > 0
        _setGameClaimablePool(uint128(100 ether));
        // sDGNRS stETH = 0 (no mint) → stETH leg fails.
        assertEq(mockStETH.balanceOf(address(sdgnrs)), 0, "(d) precondition: sDGNRS stETH must be 0");

        uint256 poolBefore = game.claimablePoolView();
        uint256 claimableBefore = _claimableSdgnrs();
        uint256 pendingBefore = sdgnrs.pendingRedemptionEthValue();
        uint256 supplyBefore = sdgnrs.totalSupply();

        // The burn must revert fail-closed (the game's pullRedemptionReserve reverts E() when neither
        // pure leg covers; that propagates out of burn()). Prime the current day's RNG FIRST so the
        // burn passes the admission gate and reaches the INTENDED coverage revert rather than tripping
        // BurnsBlockedBeforeDailyRng (which would mask the fail-closed property under test).
        _primeCurrentDayRng();
        vm.prank(playerA);
        vm.expectRevert();
        sdgnrs.burn(BURN_AMOUNT);

        // No partial state leaked: every redemption scalar is byte-identical to pre-call.
        assertEq(game.claimablePoolView(), poolBefore, "(d) leaked: claimablePool mutated on revert");
        assertEq(_claimableSdgnrs(), claimableBefore, "(d) leaked: claimable[SDGNRS] mutated on revert");
        assertEq(
            sdgnrs.pendingRedemptionEthValue(),
            pendingBefore,
            "(d) leaked: pendingRedemptionEthValue mutated on revert"
        );
        assertEq(sdgnrs.totalSupply(), supplyBefore, "(d) leaked: sDGNRS supply mutated on revert (burn not unwound)");

        _assertSolvency("(d)");
    }

    // =====================================================================
    //   (e) test_RFALL05_TwoSamePeriodClaimants_BothPaid
    // =====================================================================

    /// @notice Two same-period claimants both paid: playerA submits on the ETH leg, playerB submits in
    ///         the SAME period forced onto the stETH leg (game ETH drained between the two submits).
    ///         Both resolve + claim; assert BOTH are paid the rolled amount, no underflow / no
    ///         double-spend of claimable[SDGNRS], and solvency holds after each claim.
    function test_RFALL05_TwoSamePeriodClaimants_BothPaid() public {
        // Seed enough for playerA's ETH leg.
        vm.deal(address(game), 100 ether);
        _setGameClaimableSdgnrs(100 ether);
        _setGameClaimablePool(uint128(100 ether));

        uint32 day = game.currentDayView();

        // --- Claimant A: ETH leg ---
        uint256 pendingBeforeA = sdgnrs.pendingRedemptionEthValue();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(BURN_AMOUNT);
        uint256 maxIncrA = sdgnrs.pendingRedemptionEthValue() - pendingBeforeA;
        assertGt(maxIncrA, 0, "(e) A reservation non-zero");
        // A took the ETH leg (claimable debited).
        assertEq(_claimableSdgnrs(), 100 ether - maxIncrA, "(e) A: ETH leg should debit claimable");

        // --- Drain game ETH + claimable so claimant B is forced onto the stETH leg ---
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);
        mockStETH.mint(address(sdgnrs), 100 ether);

        uint256 claimableBeforeB = _claimableSdgnrs(); // 0
        uint256 poolBeforeB = game.claimablePoolView(); // 0
        uint256 pendingBeforeB = sdgnrs.pendingRedemptionEthValue();

        // Same period as A (no warp since A's burn) — day already drawn, so this is a no-op, but
        // primed explicitly to keep B's burn self-sufficient under the admission gate.
        _primeCurrentDayRng();
        vm.prank(playerB);
        sdgnrs.burn(BURN_AMOUNT);
        uint256 maxIncrB = sdgnrs.pendingRedemptionEthValue() - pendingBeforeB;
        assertGt(maxIncrB, 0, "(e) B reservation non-zero");
        // B took the stETH leg (no ledger debit — claimable/pool stayed at 0, no underflow).
        assertEq(_claimableSdgnrs(), claimableBeforeB, "(e) B: stETH leg must NOT debit claimable (no underflow)");
        assertEq(game.claimablePoolView(), poolBeforeB, "(e) B: stETH leg must NOT touch claimablePool");

        _assertSolvency("(e) post-two-submits");

        // --- Resolve the shared period (roll=100 = 1:1) and claim both ---
        _advanceWallDayAndResolve(day, 100);

        // Claimant A — the live-game direct half lands as a game-claimable credit.
        uint256 aClaimableBefore = game.claimableWinningsOf(playerA);
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(day));
        assertGt(
            game.claimableWinningsOf(playerA) - aClaimableBefore,
            0,
            "(e) A must be credited the rolled (direct) amount"
        );
        _assertSolvency("(e) post-A-claim");

        // Claimant B
        uint256 bClaimableBefore = game.claimableWinningsOf(playerB);
        vm.prank(playerB);
        sdgnrs.claimRedemption(playerB, uint24(day));
        assertGt(
            game.claimableWinningsOf(playerB) - bClaimableBefore,
            0,
            "(e) B must be credited the rolled (direct) amount"
        );
        _assertSolvency("(e) post-B-claim");

        // No double-spend: claimable[SDGNRS] never went below its post-A value via B's path; the raw
        // value is nowhere near a wrap ceiling (a pre-fix unchecked debit would wrap toward 2^256).
        assertLt(_claimableSdgnrs(), uint256(type(uint96).max), "(e) claimable[SDGNRS] wrapped (unchecked debit?)");
        assertLt(game.claimablePoolView(), uint256(type(uint96).max), "(e) claimablePool wrapped (unchecked debit?)");
    }

    // =====================================================================
    //   (f) test_RFALL05_BurnieCannotBlockEth
    // =====================================================================

    /// @notice BURNIE-can't-block-ETH (v47 REDEEM-08 property preserved under the fallback): the
    ///         ETH/stETH redemption path settles independently of any BURNIE state. BURNIE is settled
    ///         at submit (redeemBurnieShare → conserved flip credit; claim is ETH-only), so even with
    ///         a depleted coinflip pool the ETH claim still pays. We drive the stETH leg (worst case)
    ///         and confirm the claim still delivers ETH-value to the player.
    function test_RFALL05_BurnieCannotBlockEth() public {
        // stETH-leg setup (ETH side starved); coinflip claim mocked to return 0 (depleted pool),
        // mirroring the v47 REDEEM-08 assertion that a BURNIE shortfall cannot block the ETH leg.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);
        mockStETH.mint(address(sdgnrs), 100 ether);

        uint32 day = game.currentDayView();

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(BURN_AMOUNT);

        _advanceWallDayAndResolve(day, 100);

        // The coinflip claimCoinflipsForRedemption mock returns 0 (BURNIE side delivers nothing), yet
        // the ETH-value (stETH here) claim path completes and credits the player's game claimable.
        uint256 claimableBefore = game.claimableWinningsOf(playerA);
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(day));
        assertGt(
            game.claimableWinningsOf(playerA) - claimableBefore,
            0,
            "(f) BURNIE shortfall must NOT block the ETH/stETH redemption credit"
        );

        _assertSolvency("(f)");
    }

    // =====================================================================
    //                          POOL-04 (Task 3)
    // =====================================================================

    /// @notice (a) The sDGNRS receive() reads reserves LIVE via address(this).balance — no running
    ///         counter. A GAME-sourced credit (v55 gate: receive() accepts msg.sender == GAME) IS
    ///         reflected in the submit base (proven by previewBurn moving up by the credited amount's
    ///         share), and there is no separate counter that could disagree with the balance.
    ///         v55.0 D-351-02 reframe: the credit sender moved from AF_KING to GAME (the v54 AF_KING
    ///         receive() relaxation dissolved; the afking-funding withdraw send-back now routes through
    ///         GAME). The live-read property is unchanged — only the authorized sender differs.
    function test_POOL04_ReceiveReadsLiveBalance_NoRunningCounter() public {
        // Keep claimable/game-ETH at 0 so the ETH-balance term of the submit base comes ONLY from
        // sDGNRS's own ETH balance (the GAME credit), isolating the live-read.
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);

        uint256 balBefore = address(sdgnrs).balance;
        // previewBurn reads the SAME 4-term base (balance + stETH + claimable - pending). With
        // claimable/stETH/pending all 0, the ETH term == address(sdgnrs).balance.
        (uint256 ethOutBefore, , ) = sdgnrs.previewBurn(BURN_AMOUNT);

        // Send ETH in via the GAME-gated receive() (the afking-funding withdraw send-back path —
        // the Game's `.call` carries msg.sender == GAME, StakedDegenerusStonk.sol:433-434).
        uint256 credit = 10 ether;
        vm.deal(ContractAddresses.GAME, credit);
        vm.prank(ContractAddresses.GAME);
        (bool ok, ) = address(sdgnrs).call{value: credit}("");
        assertTrue(ok, "(POOL04a) GAME receive() must accept the credit");

        // The credit is reflected LIVE in the balance...
        assertEq(address(sdgnrs).balance, balBefore + credit, "(POOL04a) GAME credit not reflected in live balance");

        // ... and therefore in the submit base read by previewBurn. ethValueOwed scales linearly with
        // the balance term, so the preview output must INCREASE after the credit (live read, not stale
        // counter). A running counter that ignored receive() would leave previewBurn unchanged.
        (uint256 ethOutAfter, , ) = sdgnrs.previewBurn(BURN_AMOUNT);
        assertGt(ethOutAfter, ethOutBefore, "(POOL04a) submit base did not move with the GAME credit (stale counter?)");
    }

    /// @notice (b) The GAME-sourced ETH is counted EXACTLY ONCE in the redemption base: the
    ///         previewBurn delta equals the credit's proportional share, NOT 2× (no double-count from a
    ///         counter + balance both being read). v55.0 D-351-02 reframe: credit sender AF_KING → GAME
    ///         (the GAME-only receive() gate); the counted-once invariant is unchanged.
    function test_POOL04_GameCreditNotDoubleCounted() public {
        vm.deal(address(game), 0);
        _setGameClaimableSdgnrs(0);
        _setGameClaimablePool(0);

        uint256 supply = sdgnrs.totalSupply();
        (uint256 ethOutBefore, , ) = sdgnrs.previewBurn(BURN_AMOUNT);

        uint256 credit = 10 ether;
        vm.deal(ContractAddresses.GAME, credit);
        vm.prank(ContractAddresses.GAME);
        (bool ok, ) = address(sdgnrs).call{value: credit}("");
        assertTrue(ok, "(POOL04b) GAME receive() must accept the credit");

        (uint256 ethOutAfter, , ) = sdgnrs.previewBurn(BURN_AMOUNT);

        // The submit base term increased by EXACTLY `credit`; its proportional share of the burn is
        // floor(credit * BURN_AMOUNT / supply). The previewBurn ethOut delta must equal that single
        // share — a double-count (credit counted twice) would yield ~2× this delta.
        uint256 expectedDelta = (credit * BURN_AMOUNT) / supply;
        uint256 actualDelta = ethOutAfter - ethOutBefore;
        assertEq(actualDelta, expectedDelta, "(POOL04b) GAME credit not counted exactly once in the base");
    }

    /// @notice (c) A receive() from any sender != GAME reverts Unauthorized — the receive() path did
    ///         NOT open an arbitrary deposit vector. v55.0 D-351-02: under the GAME-only gate
    ///         (StakedDegenerusStonk.sol:433-434) this is STRICTLY TIGHTER than the v54 GAME||AF_KING
    ///         relaxation — only GAME is authorized now, so a stranger (and, implicitly, the old
    ///         AF_KING sender) reverts.
    function test_POOL04_NonGameReceiveReverts() public {
        address stranger = makeAddr("stranger");
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(StakedDegenerusStonk.Unauthorized.selector);
        (bool ok, ) = address(sdgnrs).call{value: 1 ether}("");
        // Foundry: with expectRevert on a low-level call, the call returns ok==false on revert; the
        // expectRevert cheatcode asserts the revert reason. Reference ok to silence the warning.
        ok;
    }

    // =====================================================================
    //   (d) DROPPED — D-351-02 removed-surface (AfKing custody-recovery leg)
    // =====================================================================
    //
    // The v54 test `test_POOL04_BurnAtGameOverRecoversPool_ZeroPoolTokenSafe` is DROPPED BY NAME.
    //
    // Reason: it proved that `sDGNRS.burnAtGameOver()` folded `afKing.withdraw(afKing.poolOf(this))`
    // to recover a PREPAID AfKing pool BEFORE its bal==0 early-return — v54 de-custody machinery the
    // v55 redesign REMOVED with NO behavioral successor:
    //   - the standalone `AfKing` de-custody contract (contracts/AfKing.sol) is DELETED; its
    //     `depositFor` / `poolOf` / `withdraw` external API no longer exists (funding is game-resident
    //     `afkingFunding`, recovered per-player via DegenerusGame.withdrawAfkingFunding — there is NO
    //     game-resident recovery of a PREPAID third-party pool keyed to sDGNRS).
    //   - `sDGNRS.burnAtGameOver()` is now a pure local-token burn (StakedDegenerusStonk.sol:526-535:
    //     `bal = balanceOf[this]; if (bal==0) return; balanceOf[this]=0; totalSupply-=bal; delete
    //     poolBalances;`) — it no longer folds any AfKing withdraw, so the property under test is gone.
    // Per D-351-02 (bias=adapt; removal is the exception only when the entire subject is a fully-removed
    // surface with NO successor). The POOL-04 receive()-safety properties (a/b/c) SURVIVE and are kept
    // (reframed onto the GAME-only gate). Recorded BY NAME in 351-06-SUMMARY for the 351-09 ledger.

    // =====================================================================
    //                          INTERNAL HELPER
    // =====================================================================

    /// @dev Advance the wall day (so we are off the burn day) then resolve `day` at `roll`.
    ///      After the warp the current view day is `day + 1`; prime its RNG word so the subsequent
    ///      claimRedemption(day) lootbox leg (which reads rngWordForDay(day + 1)) resolves on a drawn
    ///      day rather than a not-yet-drawn zero word (window-(b) flow under the burn-side gate).
    function _advanceWallDayAndResolve(uint32 day, uint16 roll) internal {
        vm.warp(block.timestamp + 1 days);
        _primeCurrentDayRng();
        _resolveDay(day, roll);
    }

    /// @dev Accept ETH so the redemption-claim payout plumbing (claimRedemption ETH legs) and any
    ///      test value transfers don't revert.
    receive() external payable {}
}
