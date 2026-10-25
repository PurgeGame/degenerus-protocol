// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {DegenesisDeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FlipEmissionSeeds — initial FLIP emission as coinflip seed stakes
/// @notice Proves the emission scheme end to end:
///         1. SEEDS    — Coinflip's constructor opens the seed window for rounds 2-21:
///                       200k of stake per day, each to VAULT and sDGNRS, held as the
///                       window rather than in stake lanes; nothing is minted up front
///                       (totalSupply and vaultMintAllowance both start at 0).
///         2. SURVIVAL — a seeded day's FLIP only survives if it wins that day's flip;
///                       sDGNRS wins fold into its claimable coinflip backing by the
///                       daily resolution (uncirculated — no mint, no wallet balance),
///                       where redemptions read them.
///         3. LATCH    — sDGNRS auto-rebuy (0 take-profit) stays OFF through the whole
///                       seed window and arms exactly when the final seeded round (21)
///                       settles; the latch is one-shot.
///         4. VAULT    — vault seed wins accumulate as claimable; a vault claim mints
///                       them into the VAULT mint allowance (the uncirculated leg).
///
/// @dev Drives `processCoinflipPayouts` directly as the GAME (the AdvanceModule call
///      shape) so each day's win/loss is chosen via the word's bit 0.
contract FlipEmissionSeeds is DegenesisDeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;

    uint256 internal constant SEED = 200_000;
    uint24 internal constant SEED_DAYS = 20;
    /// @dev The window is rounds 2..21: the first stake targets requestedDailyIdx + 1 = 2.
    uint24 internal constant FIRST_SEED_ROUND = 2;
    uint24 internal constant LAST_SEED_ROUND = FIRST_SEED_ROUND + SEED_DAYS - 1;

    function setUp() public {
        _deployProtocol();
    }

    /// @dev coinflipStakeRing is internal at root slot 0 and banks 7 days per slot
    ///      (tagged seven-day pages, 32-bit whole-FLIP lanes). Read the packed word
    ///      and decode `day`'s lane back to wei.
    function _stakeOf(uint24 day, address player) internal view returns (uint256) {
        return CoinflipStorage.read(address(coinflip), game.walletIdOf_g3120(player), day);
    }

    /// @dev Resolve day `epoch` as the GAME with a win (bit 0 = 1) or loss (bit 0 = 0) word.
    function _resolveDay(uint24 epoch, bool win) internal {
        uint256 word = uint256(keccak256(abi.encodePacked("emission_seed_word", epoch)));
        word = win ? (word | 1) : (word & ~uint256(1));
        vm.prank(GAME);
        coinflip.processCoinflipPayouts(0, word, epoch);
    }

    // =====================================================================
    //                       1. SEEDS — placement
    // =====================================================================

    function test_SeedStakesPlacedForRounds2Through21_NothingMinted() public {
        // The window is rounds 2..21 by construction; no stake lane is written.
        for (uint24 d = 1; d <= LAST_SEED_ROUND + 1; ++d) {
            assertEq(_stakeOf(d, VAULT), 0, "no vault lane written");
            assertEq(_stakeOf(d, SDGNRS), 0, "no sdgnrs lane written");
        }
        // Requested round r stakes round r + 1: r = 1..20 read the seed, r = 21 does not.
        for (uint24 r = 1; r <= LAST_SEED_ROUND; ++r) {
            _setRequestedFixtureDay(r);
            uint256 expected = r < LAST_SEED_ROUND ? SEED : 0;
            assertEq(coinflip.coinflipAmount(VAULT), expected, "vault round seed = 200k through round 21");
            assertEq(coinflip.coinflipAmount(SDGNRS), expected, "sdgnrs round seed = 200k through round 21");
        }

        // Nothing mints up front — the whole emission must survive its day's flip.
        assertEq(coin.totalSupply(), 0, "zero circulating supply at deploy");
        assertEq(coin.vaultMintAllowance(), 0, "zero vault allowance at deploy");
    }

    // =====================================================================
    //          2 + 3. SURVIVAL mint-to-wallet + auto-rebuy LATCH
    // =====================================================================

    function test_SdgnrsSeedWinsFoldIntoClaimable_LatchArmsAtRound21() public {
        uint256 expectedClaimable;

        for (uint24 d = FIRST_SEED_ROUND; d <= LAST_SEED_ROUND; ++d) {
            // Alternate win/loss so both settle branches run inside the window.
            bool win = (d % 2 == 0);
            uint256 claimableBefore = coinflip.previewClaimCoinflips(SDGNRS);
            _resolveDay(d, win);

            // sDGNRS never mints to a wallet balance — its FLIP stays uncirculated.
            assertEq(coin.balanceOf(SDGNRS), 0, "sDGNRS holds no wallet balance");

            if (win) {
                (uint16 r, bool won) = coinflip.getCoinflipDayResult(d);
                assertTrue(won, "win word must resolve as a win");
                uint256 payout = SEED + (SEED * uint256(r)) / 100;
                expectedClaimable += payout;
                assertEq(
                    coinflip.previewClaimCoinflips(SDGNRS) - claimableBefore,
                    payout,
                    "win day folds the survived seed into sDGNRS's claimable backing (no mint)"
                );
            } else {
                assertEq(
                    coinflip.previewClaimCoinflips(SDGNRS),
                    claimableBefore,
                    "loss day adds nothing (the seed died on its flip)"
                );
            }

            (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
            if (d < LAST_SEED_ROUND) {
                assertFalse(enabled, "auto-rebuy stays OFF through the seed window");
            }
        }

        // The latch armed exactly when round 21 settled, with 0 take-profit.
        (bool enabledAfter, uint256 stop, uint256 carry, ) =
            coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(enabledAfter, "auto-rebuy arms when the final seeded day settles");
        assertEq(stop, 0, "0 take-profit (roll everything)");
        assertEq(carry, 0, "seed wins folded into claimable, not the carry");

        // Backing holds exactly the survived seed payouts as uncirculated claimable;
        // nothing entered circulating supply and sDGNRS holds no wallet balance.
        assertEq(coin.balanceOf(SDGNRS), 0, "sDGNRS holds no wallet balance");
        assertEq(
            coinflip.previewClaimCoinflips(SDGNRS),
            expectedClaimable,
            "sDGNRS claimable == sum of survived seed payouts"
        );
        assertEq(coin.totalSupply(), 0, "survived sDGNRS emission stays uncirculated (no mint)");
    }

    function test_PostArmingWinsStayInFlips_NeverClaimed() public {
        // Burn through the seed window (all losses keep the wallet at 0 for clean deltas).
        for (uint24 d = FIRST_SEED_ROUND; d <= LAST_SEED_ROUND; ++d) {
            _resolveDay(d, false);
        }
        (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(enabled, "armed after the seed window");
        assertEq(coin.balanceOf(SDGNRS), 0, "all seeds died - wallet empty");

        // Request round 21 so a flip credit targets round 22, then credit a
        // post-window stake as the GAME (the affiliate-drain shape).
        _setRequestedFixtureDay(LAST_SEED_ROUND);
        uint256 credit = 100_000;
        vm.prank(GAME);
        coinflip.creditFlip_g317(2, credit);

        // Round 22 WIN: the payout settles into the rolling carry (plus the flat
        // recycle bonus on the roll) - nothing mints, nothing becomes claimable.
        _resolveDay(LAST_SEED_ROUND + 1, true);
        (uint16 r, ) = coinflip.getCoinflipDayResult(LAST_SEED_ROUND + 1);
        uint256 payout = credit + (credit * uint256(r)) / 100;
        uint256 bonus = (payout * 75) / 10_000;
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertEq(carry, payout + bonus, "win rolls into carry (with recycle bonus)");
        assertEq(coin.balanceOf(SDGNRS), 0, "post-arming win never mints to the wallet");
        assertEq(coinflip.previewClaimCoinflips(SDGNRS), 0, "nothing claimable post-arming");
        assertEq(coin.totalSupply(), 0, "no FLIP entered existence");

        // Round 23 LOSS: the whole carry gambles again and dies - rebuy forever.
        _resolveDay(LAST_SEED_ROUND + 2, false);
        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertEq(carryAfter, 0, "loss wipes the rolling carry");
        assertEq(coin.balanceOf(SDGNRS), 0, "wallet untouched by the flip lifecycle");
    }

    function test_LatchIsOneShot_AndSurvivesEpochJump() public {
        // A jumped first epoch past the window (a >120-day-stall shape) still arms once.
        _resolveDay(LAST_SEED_ROUND + 5, true);
        (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(enabled, "latch arms on any epoch >= 21");

        // A later resolution does not re-toggle or reset the rebuy state.
        _resolveDay(LAST_SEED_ROUND + 6, false);
        (bool stillEnabled, uint256 stop, , uint24 startDay) =
            coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(stillEnabled, "latch is one-shot - stays armed");
        assertEq(stop, 0, "take-profit stays 0");
        assertEq(startDay, LAST_SEED_ROUND + 5, "startDay anchored at the arming claim cursor");
    }

    // =====================================================================
    //                  4. VAULT — claimable wins → allowance
    // =====================================================================

    function test_VaultSeedWinsClaimIntoMintAllowance() public {
        // Resolve the first 5 seeded rounds (2..6): 3 wins, 2 losses.
        for (uint24 d = 2; d <= 6; ++d) {
            _resolveDay(d, d != 3 && d != 5);
        }

        uint256 expected;
        for (uint24 d = 2; d <= 6; ++d) {
            (uint16 r, bool won) = coinflip.getCoinflipDayResult(d);
            if (won) expected += SEED + (SEED * uint256(r)) / 100;
        }
        assertGt(expected, 0, "non-vacuity: some vault seeds survived");

        assertEq(
            coinflip.previewClaimCoinflips(VAULT),
            expected,
            "vault's survived seeds sit as claimable until claimed"
        );

        uint256 allowanceBefore = coin.vaultMintAllowance();
        vm.prank(VAULT);
        uint256 claimed = coinflip.claimCoinflips(0, type(uint256).max);

        assertEq(claimed, expected, "vault claim settles every survived seed payout");
        // VAULT mints redirect to the uncirculated allowance leg.
        assertEq(
            coin.vaultMintAllowance() - allowanceBefore,
            expected,
            "vault wins land in vaultMintAllowance"
        );
        assertEq(coin.balanceOf(VAULT), 0, "no circulating balance for the VAULT");
    }
}
