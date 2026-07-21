// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @title MutationKills — regression tests that CLOSE the GENUINE oracle gaps the v63 mutation
///        campaign surfaced (subject a8b702a7). Each test is a deterministic branch-proof: it
///        PASSES on the clean subject and FAILS when the named survivor's mutation is re-applied
///        in place. The fail-with-mutation / pass-without evidence is recorded per test in the
///        header comment AND in audit/mutation/MUTATION-FINDINGS-v63.md.
///
/// @dev Provenance — every survivor below was logged `--> UNCAUGHT` by slither-mutate under the
///      COMPREHENSIVE oracle (the union of the 12 388-02 green-baseline suites). The shared cause
///      is that the comprehensive oracle drives the LIVE-game redemption path exhaustively but
///      never drives the POST-gameOver deterministic / pool-drain / settle paths, the
///      BitPackingLib.setPacked round-trip, or the distress-mode level!=0 branch. None of these
///      survivors is a contract defect — each subject line is correct; the regression net simply
///      lacked an assertion (see SURVIVOR-TRIAGE-v63.md / MUTATION-FINDINGS-v63.md).
///
///      These tests are TEST-ONLY (no contract source is persistently edited). Validation runs
///      transiently re-applied each survivor's mutation, confirmed the test went red, then
///      `git checkout -- contracts/` restored the byte-frozen subject.
///
/// @dev Run: forge test --match-path test/mutation/MutationKills.t.sol
contract MutationKills is DeployProtocol {
    // ---------------------------------------------------------------------
    //                      BitPackingLib.setPacked (G-BPL-01)
    // ---------------------------------------------------------------------

    /// @notice KILLS BitPackingLib.sol:110 [CR] — the setPacked masked-RMW return body commented
    ///         out (returns 0). Also kills the C1 MASK_* value-change survivors (lines 33/36/39/42/45)
    ///         because it feeds an OVER-WIDE value and asserts the field is bounded to its mask width
    ///         and that sibling fields are preserved.
    /// @dev Pure-library round-trip. Pre-loads a word with two adjacent fields, writes a third via
    ///      setPacked, then asserts: (a) the new field reads back EXACTLY, (b) the over-wide bits
    ///      were masked off, (c) the two pre-existing sibling fields are untouched. A CR/return-0
    ///      mutant fails (a) and (c); a wrong-MASK mutant fails (b).
    function test_kills_BitPackingLib_110_setPacked_roundTrip() public pure {
        // Seed a word with LEVEL_COUNT (24-bit) = 0xABCDEF and DAY (32-bit) = 0x11223344 already set.
        uint256 word = 0;
        word = BitPackingLib.setPacked(
            word, BitPackingLib.LEVEL_COUNT_SHIFT, BitPackingLib.MASK_24, 0xABCDEF
        );
        word = BitPackingLib.setPacked(
            word, BitPackingLib.DAY_SHIFT, BitPackingLib.MASK_32, 0x11223344
        );

        // Write LEVEL_UNITS (16-bit) with an OVER-WIDE value (0x3FFFF > 16 bits). A correct mask
        // bounds it to its low 16 bits (0xFFFF); a value-mutated mask would let extra bits through.
        uint256 overWide = 0x3FFFF;
        word = BitPackingLib.setPacked(
            word, BitPackingLib.LEVEL_UNITS_SHIFT, BitPackingLib.MASK_16, overWide
        );

        // (a) the field reads back, (b) bounded to 16 bits (not the over-wide 0x3FFFF).
        uint256 unitsField = (word >> BitPackingLib.LEVEL_UNITS_SHIFT) & BitPackingLib.MASK_16;
        assertEq(unitsField, 0xFFFF, "LEVEL_UNITS not round-tripped / mask not enforced");
        assertTrue(unitsField != overWide, "over-wide value leaked past the mask (C1 mask mutant)");

        // (c) sibling fields preserved (a CR/return-0 mutant zeroes the whole word).
        uint256 countField = (word >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24;
        uint256 dayField = (word >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32;
        assertEq(countField, 0xABCDEF, "LEVEL_COUNT sibling clobbered (setPacked body removed)");
        assertEq(dayField, 0x11223344, "DAY sibling clobbered (setPacked body removed)");

        // Direct round-trip: a clear-then-set over a fully-populated field replaces it exactly.
        uint256 replaced = BitPackingLib.setPacked(
            word, BitPackingLib.LEVEL_UNITS_SHIFT, BitPackingLib.MASK_16, 0x1234
        );
        assertEq(
            (replaced >> BitPackingLib.LEVEL_UNITS_SHIFT) & BitPackingLib.MASK_16,
            0x1234,
            "clear-then-set did not replace the field exactly"
        );
    }

    // ---------------------------------------------------------------------
    //               sDGNRS — gameOver deterministic burn
    // ---------------------------------------------------------------------

    /// @dev Per-actor sDGNRS funding routed through the Reward pool (game is the authorized caller).
    uint256 internal constant ACTOR_FUNDING = 1_000_000 ether;

    address internal burner;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        burner = makeAddr("burner");
        vm.deal(burner, 1 ether);

        // Fund a burner with sDGNRS from the Reward pool (game is the onlyGame caller).
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, burner, ACTOR_FUNDING);
    }

    /// @dev Force game.gameOver() == true via mockCall so burn() takes the deterministic leg.
    function _mockGameOver(bool over) internal {
        vm.mockCall(
            ContractAddresses.GAME,
            abi.encodeWithSelector(bytes4(keccak256("gameOver()"))),
            abi.encode(over)
        );
        // No claimable winnings to pull (keeps _claimableWinnings == 0, ETH-only payout path).
        vm.mockCall(
            ContractAddresses.GAME,
            abi.encodeWithSelector(bytes4(keccak256("claimableWinningsOf(address)")), address(sdgnrs)),
            abi.encode(uint256(0))
        );
    }

    /// @notice KILLS sDGNRS.sol:624/625/659/666-707 [RR] — the gameOver deterministic
    ///         burn leg (burn() → _deterministicBurn → _deterministicBurnFrom). The comprehensive
    ///         oracle only drives the LIVE gambling-burn path, so the whole post-gameOver payout
    ///         (supply burn, balance debit, ETH payout, Burn event) survived.
    /// @dev Branch-proof: assert gameOver IS active (the targeted branch was taken), then burn and
    ///      assert (a) supply decreased by exactly the burned amount, (b) the burner's sDGNRS balance
    ///      decreased by exactly the burned amount, (c) a positive proportional ETH payout landed.
    ///      An RR mutant on any payout line reverts the burn; a return-mutant zeroes ethOut.
    function test_kills_StakedStonk_deterministicBurn_gameOverPayout() public {
        // Seed contract backing so the proportional payout is positive and ETH-coverable.
        vm.deal(address(sdgnrs), 100 ether);
        _mockGameOver(true);

        uint256 supplyBefore = sdgnrs.totalSupply();
        uint256 balBefore = sdgnrs.balanceOf(burner);
        uint256 ethBefore = burner.balance;
        uint256 burnAmount = balBefore / 2;
        require(burnAmount > 0, "fixture: zero burn amount");

        // The targeted branch IS taken (gameOver deterministic leg, not the live gambling leg).
        assertTrue(game.gameOver(), "branch-proof: gameOver must be active for the deterministic leg");

        vm.prank(burner);
        (uint256 ethOut, uint256 stethOut, uint256 flipOut) = sdgnrs.burn(burnAmount);

        // (a) supply burned exactly, (b) burner balance debited exactly.
        assertEq(sdgnrs.totalSupply(), supplyBefore - burnAmount, "supply not burned by exact amount");
        assertEq(sdgnrs.balanceOf(burner), balBefore - burnAmount, "burner balance not debited exactly");
        // (c) a positive ETH payout landed (gameOver burns pay no FLIP).
        assertGt(ethOut, 0, "deterministic gameOver burn paid zero ETH (payout leg removed)");
        assertEq(flipOut, 0, "gameOver burn must pay no FLIP");
        assertEq(burner.balance, ethBefore + ethOut, "ETH not delivered to burner");
        assertEq(stethOut, 0, "fixture seeds full ETH coverage; no stETH leg expected");
    }

    /// @notice KILLS sDGNRS.sol:685/686/690-693/707 [RR] — the stETH-fallback split
    ///         inside _deterministicBurnFrom (ethBal/stethBal reads + the ethOut=ethBal /
    ///         stethOut=totalValueOwed-ethOut split). Drives a partially-ETH-depleted contract so the
    ///         payout must split across ETH and the stETH fallback leg.
    /// @dev Seed the contract with a SMALL ETH balance and a LARGE stETH balance so the proportional
    ///      owed exceeds on-hand ETH, forcing the stETH leg. Assert both legs land.
    function test_kills_StakedStonk_deterministicBurn_stethFallbackSplit() public {
        // The burner owns a tiny fraction of the deploy-time supply, so its proportional owed is
        // sub-milli-ETH. To force the stETH-fallback split, seed the contract with LESS on-hand ETH
        // than the proportional owed but ample stETH backing: owed > ethBal → ethOut = ethBal and
        // stethOut = owed - ethBal (the stETH remainder leg). On-hand ETH = 1e14 wei (0.0001 ETH);
        // stETH = 1000 ETH so totalMoney (and thus owed) stays above the on-hand ETH.
        uint256 onHandEth = 1e14;
        vm.deal(address(sdgnrs), onHandEth);
        mockStETH.mint(address(sdgnrs), 1000 ether);
        _mockGameOver(true);

        uint256 balBefore = sdgnrs.balanceOf(burner);
        uint256 burnAmount = balBefore; // burn the full balance → larger owed, comfortably > on-hand ETH
        uint256 ethBefore = burner.balance;
        uint256 stethBefore = mockStETH.balanceOf(burner);

        assertTrue(game.gameOver(), "branch-proof: gameOver must be active");

        vm.prank(burner);
        (uint256 ethOut, uint256 stethOut, ) = sdgnrs.burn(burnAmount);

        // The split actually happened: ETH leg drained the on-hand ETH, stETH leg covered the rest.
        assertGt(stethOut, 0, "stETH fallback leg paid nothing (split removed)");
        assertEq(ethOut, onHandEth, "ETH leg did not drain the full on-hand ETH before stETH fallback");
        assertEq(burner.balance, ethBefore + ethOut, "ETH leg not delivered");
        assertEq(mockStETH.balanceOf(burner), stethBefore + stethOut, "stETH leg not delivered");
    }

    // ---------------------------------------------------------------------
    //                  sDGNRS — burnAtGameOver
    // ---------------------------------------------------------------------

    /// @notice KILLS sDGNRS.sol:602/603/605/606 [RR] — burnAtGameOver zeroes the
    ///         contract's own balance, decrements supply by it, deletes poolBalances, emits Transfer.
    ///         The comprehensive oracle never calls burnAtGameOver.
    /// @dev Branch-proof: assert the contract holds undistributed tokens (the targeted branch's
    ///      precondition), call burnAtGameOver as the game, then assert balance==0, supply dropped by
    ///      exactly the burned bal, and the pool balances were cleared.
    function test_kills_StakedStonk_burnAtGameOver_drainsLocalSupply() public {
        uint256 localBal = sdgnrs.balanceOf(address(sdgnrs));
        require(localBal > 0, "fixture: contract holds no undistributed tokens");
        uint256 supplyBefore = sdgnrs.totalSupply();
        uint256 rewardPoolBefore = sdgnrs.poolBalance(sDGNRS.Pool.Reward);
        assertGt(rewardPoolBefore, 0, "branch-proof: pool balances must be non-zero pre-drain");

        vm.prank(address(game));
        sdgnrs.burnAtGameOver();

        assertEq(sdgnrs.balanceOf(address(sdgnrs)), 0, "local balance not zeroed");
        assertEq(sdgnrs.totalSupply(), supplyBefore - localBal, "supply not reduced by burned local bal");
        // delete poolBalances cleared every pool slot.
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Reward), 0, "Reward pool not cleared");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Whale), 0, "Whale pool not cleared");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Lootbox), 0, "Lootbox pool not cleared");
    }

    // ---------------------------------------------------------------------
    //                  sDGNRS — transferFromPool
    // ---------------------------------------------------------------------

    /// @notice KILLS sDGNRS.sol:549/553/555/558/559/567/569/570 [RR] — the regular
    ///         (to != this) transferFromPool leg: pool debit, contract-balance debit, recipient
    ///         credit, return value. setUp already exercises this (it funds the burner), but no
    ///         assertion pinned the post-conditions; this test pins them.
    function test_kills_StakedStonk_transferFromPool_creditsRecipient() public {
        address sink = makeAddr("poolSink");
        uint256 poolBefore = sdgnrs.poolBalance(sDGNRS.Pool.Reward);
        uint256 sinkBefore = sdgnrs.balanceOf(sink);
        uint256 contractBefore = sdgnrs.balanceOf(address(sdgnrs));
        uint256 req = 10_000 ether;
        require(poolBefore >= req, "fixture: reward pool too small");

        vm.prank(address(game));
        uint256 transferred = sdgnrs.transferFromPool(sDGNRS.Pool.Reward, sink, req);

        assertEq(transferred, req, "return value wrong (return-mutant)");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Reward), poolBefore - req, "pool not debited");
        assertEq(sdgnrs.balanceOf(sink), sinkBefore + req, "recipient not credited");
        assertEq(sdgnrs.balanceOf(address(sdgnrs)), contractBefore - req, "contract balance not debited");
    }

    /// @notice KILLS sDGNRS.sol:563/564 [RR] — the SELF-WIN branch of transferFromPool
    ///         (to == address(this)): burns instead of a no-op transfer, decrementing supply and
    ///         emitting Transfer to address(0). The oracle never drives the self-win branch.
    /// @dev Branch-proof: target to == address(this) and assert supply DROPPED (the burn happened),
    ///      while the contract balance is unchanged on net (debited then NOT re-credited — burned).
    function test_kills_StakedStonk_transferFromPool_selfWinBurns() public {
        uint256 poolBefore = sdgnrs.poolBalance(sDGNRS.Pool.Reward);
        uint256 supplyBefore = sdgnrs.totalSupply();
        uint256 contractBalBefore = sdgnrs.balanceOf(address(sdgnrs));
        uint256 req = 5_000 ether;
        require(poolBefore >= req, "fixture: reward pool too small");

        vm.prank(address(game));
        uint256 transferred = sdgnrs.transferFromPool(sDGNRS.Pool.Reward, address(sdgnrs), req);

        assertEq(transferred, req, "self-win return value wrong");
        // Self-win burns: supply drops by req; contract balance net unchanged (debit then burn).
        assertEq(sdgnrs.totalSupply(), supplyBefore - req, "self-win did not burn supply (branch removed)");
        assertEq(sdgnrs.balanceOf(address(sdgnrs)), contractBalBefore - req, "contract balance not debited by burn");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Reward), poolBefore - req, "pool not debited");
    }

    // ---------------------------------------------------------------------
    //                  sDGNRS — wrapperTransferTo
    // ---------------------------------------------------------------------

    /// @notice KILLS sDGNRS.sol:456/457/459 [RR] — wrapperTransferTo moves sDGNRS from
    ///         the DGNRS wrapper to a recipient (DGNRS-only). The oracle never exercises this path.
    /// @dev Seed the DGNRS wrapper with sDGNRS (via the Reward pool), then transfer as DGNRS and
    ///      assert the wrapper debit + recipient credit (supply unchanged — pure transfer).
    function test_kills_StakedStonk_wrapperTransferTo_movesBalance() public {
        // Fund the DGNRS wrapper address with sDGNRS so wrapperTransferTo has balance to move.
        uint256 seed = 12_000 ether;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, ContractAddresses.DGNRS, seed);

        address recipient = makeAddr("wrapperRecipient");
        uint256 wrapperBefore = sdgnrs.balanceOf(ContractAddresses.DGNRS);
        uint256 recipientBefore = sdgnrs.balanceOf(recipient);
        uint256 supplyBefore = sdgnrs.totalSupply();
        uint256 amount = 4_000 ether;
        require(wrapperBefore >= amount, "fixture: wrapper underfunded");

        vm.prank(ContractAddresses.DGNRS);
        sdgnrs.wrapperTransferTo(recipient, amount);

        assertEq(sdgnrs.balanceOf(ContractAddresses.DGNRS), wrapperBefore - amount, "wrapper not debited");
        assertEq(sdgnrs.balanceOf(recipient), recipientBefore + amount, "recipient not credited");
        assertEq(sdgnrs.totalSupply(), supplyBefore, "wrapperTransferTo must not change supply");
    }

    // ---------------------------------------------------------------------
    // NOTE on DegenerusGameStorage.sol:583 (_isDistressMode live branch):
    //   The line-583 RR survivor is classified FALSE in SURVIVOR-TRIAGE-v63.md, not killed here.
    //   It is behaviorally covered OUTSIDE the comprehensive forge-oracle union (by the JS distress
    //   suites: test/unit/DistressLootbox.test.js, LootboxAutoResolveSilentColdBust.test.js, etc.),
    //   so it is a gap in the narrow forge-oracle subset, NOT a hole in the protocol's overall
    //   regression coverage. Driving the line-583 (level != 0) branch deterministically here would
    //   require advancing the game past level 0 through the full purchase/advance flow — out of
    //   proportion to closing a gap that is already covered elsewhere. Per the audit posture (do not
    //   over-invest; reachable-but-already-covered survivors are FALSE), it is recorded FALSE.
    // ---------------------------------------------------------------------
}
