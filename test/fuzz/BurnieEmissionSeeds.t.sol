// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title BurnieEmissionSeeds — initial BURNIE emission as coinflip seed stakes
/// @notice Proves the emission scheme end to end:
///         1. SEEDS    — BurnieCoinflip's constructor stakes 200k for days 1-20, each
///                       to VAULT and sDGNRS; nothing is minted up front (totalSupply
///                       and vaultMintAllowance both start at 0).
///         2. SURVIVAL — a seeded day's BURNIE only ever mints if it wins that day's
///                       flip; sDGNRS wins are claimed-and-minted straight to its
///                       wallet balance by the daily resolution (redemption backing),
///                       with no claimable residue left behind.
///         3. LATCH    — sDGNRS auto-rebuy (0 take-profit) stays OFF through the whole
///                       seed window and arms exactly when the final seeded day (20)
///                       settles; the latch is one-shot.
///         4. VAULT    — vault seed wins accumulate as claimable; a vault claim mints
///                       them into the VAULT mint allowance (the uncirculated leg).
///
/// @dev Drives `processCoinflipPayouts` directly as the GAME (the AdvanceModule call
///      shape) so each day's win/loss is chosen via the word's bit 0.
contract BurnieEmissionSeeds is DeployProtocol {
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant SDGNRS = ContractAddresses.SDGNRS;

    uint256 internal constant SEED = 200_000 ether;
    uint24 internal constant SEED_DAYS = 20;

    function setUp() public {
        _deployProtocol();
    }

    /// @dev coinflipBalance is internal; read mapping(uint24 => mapping(address => uint256))
    ///      at root slot 0 directly.
    function _stakeOf(uint24 day, address player) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(day), uint256(0)));
        bytes32 slot = keccak256(abi.encode(player, uint256(inner)));
        return uint256(vm.load(address(coinflip), slot));
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

    function test_SeedStakesPlacedForDays1Through20_NothingMinted() public view {
        for (uint24 d = 1; d <= SEED_DAYS; ++d) {
            assertEq(_stakeOf(d, VAULT), SEED, "vault day seed = 200k");
            assertEq(_stakeOf(d, SDGNRS), SEED, "sdgnrs day seed = 200k");
        }
        assertEq(_stakeOf(SEED_DAYS + 1, VAULT), 0, "no vault seed past day 20");
        assertEq(_stakeOf(SEED_DAYS + 1, SDGNRS), 0, "no sdgnrs seed past day 20");

        // Nothing mints up front — the whole emission must survive its day's flip.
        assertEq(coin.totalSupply(), 0, "zero circulating supply at deploy");
        assertEq(coin.vaultMintAllowance(), 0, "zero vault allowance at deploy");
    }

    // =====================================================================
    //          2 + 3. SURVIVAL mint-to-wallet + auto-rebuy LATCH
    // =====================================================================

    function test_SdgnrsSeedWinsMintToWalletDaily_LatchArmsAtDay20() public {
        uint256 expectedWallet;

        for (uint24 d = 1; d <= SEED_DAYS; ++d) {
            // Alternate win/loss so both settle branches run inside the window.
            bool win = (d % 2 == 1);
            uint256 balBefore = coin.balanceOf(SDGNRS);
            _resolveDay(d, win);

            if (win) {
                (uint16 r, bool won) = coinflip.getCoinflipDayResult(d);
                assertTrue(won, "win word must resolve as a win");
                uint256 payout = SEED + (SEED * uint256(r)) / 100;
                expectedWallet += payout;
                assertEq(
                    coin.balanceOf(SDGNRS) - balBefore,
                    payout,
                    "win day claims-and-mints the survived seed to sDGNRS's wallet"
                );
            } else {
                assertEq(
                    coin.balanceOf(SDGNRS),
                    balBefore,
                    "loss day mints nothing (the seed died on its flip)"
                );
            }

            (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
            if (d < SEED_DAYS) {
                assertFalse(enabled, "auto-rebuy stays OFF through the seed window");
            }
        }

        // The latch armed exactly when day 20 settled, with 0 take-profit.
        (bool enabledAfter, uint256 stop, uint256 carry, ) =
            coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(enabledAfter, "auto-rebuy arms when the final seeded day settles");
        assertEq(stop, 0, "0 take-profit (roll everything)");
        assertEq(carry, 0, "no carry from the seed window (wins were minted, not rolled)");

        // Wallet holds exactly the survived seed payouts; no claimable residue.
        assertEq(
            coin.balanceOf(SDGNRS),
            expectedWallet,
            "sDGNRS wallet == sum of survived seed payouts"
        );
        assertEq(
            coinflip.previewClaimCoinflips(SDGNRS),
            0,
            "no claimable residue - every settle claimed-and-minted"
        );
        assertEq(coin.totalSupply(), expectedWallet, "supply == survived sDGNRS emission");
    }

    function test_PostArmingWinsStayInFlips_NeverClaimed() public {
        // Burn through the seed window (all losses keep the wallet at 0 for clean deltas).
        for (uint24 d = 1; d <= SEED_DAYS; ++d) {
            _resolveDay(d, false);
        }
        (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(enabled, "armed after the seed window");
        assertEq(coin.balanceOf(SDGNRS), 0, "all seeds died - wallet empty");

        // Warp to day 20's wall clock so a flip credit targets day 21, then credit a
        // post-window stake as the GAME (the affiliate-drain shape).
        vm.warp(
            (uint256(SEED_DAYS - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                1
        );
        uint256 credit = 100_000 ether;
        vm.prank(GAME);
        coinflip.creditFlip(SDGNRS, credit);

        // Day 21 WIN: the payout settles into the rolling carry (plus the capped
        // recycle bonus on the roll) - nothing mints, nothing becomes claimable.
        _resolveDay(SEED_DAYS + 1, true);
        (uint16 r, ) = coinflip.getCoinflipDayResult(SEED_DAYS + 1);
        uint256 payout = credit + (credit * uint256(r)) / 100;
        uint256 bonus = (payout * 75) / 10_000;
        if (bonus > 1000 ether) bonus = 1000 ether;
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertEq(carry, payout + bonus, "win rolls into carry (with recycle bonus)");
        assertEq(coin.balanceOf(SDGNRS), 0, "post-arming win never mints to the wallet");
        assertEq(coinflip.previewClaimCoinflips(SDGNRS), 0, "nothing claimable post-arming");
        assertEq(coin.totalSupply(), 0, "no BURNIE entered existence");

        // Day 22 LOSS: the whole carry gambles again and dies - rebuy forever.
        _resolveDay(SEED_DAYS + 2, false);
        (, , uint256 carryAfter, ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertEq(carryAfter, 0, "loss wipes the rolling carry");
        assertEq(coin.balanceOf(SDGNRS), 0, "wallet untouched by the flip lifecycle");
    }

    function test_LatchIsOneShot_AndSurvivesEpochJump() public {
        // A jumped first epoch past the window (a >120-day-stall shape) still arms once.
        _resolveDay(SEED_DAYS + 5, true);
        (bool enabled, , , ) = coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(enabled, "latch arms on any epoch >= 20");

        // A later resolution does not re-toggle or reset the rebuy state.
        _resolveDay(SEED_DAYS + 6, false);
        (bool stillEnabled, uint256 stop, , uint24 startDay) =
            coinflip.coinflipAutoRebuyInfo(SDGNRS);
        assertTrue(stillEnabled, "latch is one-shot - stays armed");
        assertEq(stop, 0, "take-profit stays 0");
        assertEq(startDay, SEED_DAYS + 5, "startDay anchored at the arming claim cursor");
    }

    // =====================================================================
    //                  4. VAULT — claimable wins → allowance
    // =====================================================================

    function test_VaultSeedWinsClaimIntoMintAllowance() public {
        // Resolve the first 5 seeded days: 3 wins, 2 losses.
        for (uint24 d = 1; d <= 5; ++d) {
            _resolveDay(d, d != 2 && d != 4);
        }

        uint256 expected;
        for (uint24 d = 1; d <= 5; ++d) {
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
        uint256 claimed = coinflip.claimCoinflips(address(0), type(uint256).max);

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
