// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title VaultBurnCoinClaimable — `burnCoin` must survive a vault that holds claimable coinflips
/// @notice Covers the one state `DegenerusVault.burnCoin` was never exercised in: the vault holding
///         a non-zero claimable coinflip balance at redemption time.
///
/// @dev The uncovered path. `burnCoin` values the reserve as
///      `vaultMintAllowance() + previewClaimCoinflips(vault)`. Its payout leg used to split that
///      into a claimed portion paid by `flipToken.transfer` and a remainder paid by `vaultMintTo`.
///      The transfer leg could never work: `claimCoinflips` pays through `FLIP.mintForGame` ->
///      `FLIP._mint`, which intercepts every VAULT-destined mint into `vaultAllowance` and returns
///      before touching `balanceOf`. `FLIP._transfer`'s own shortfall top-up routes through that
///      same intercept, so `balanceOf[VAULT]` is structurally zero and `balanceOf[from] = balance -
///      amount` underflowed, reverting the whole redemption.
///
///      Every prior suite reached this function with `previewClaimCoinflips(vault) == 0`, so the
///      branch never ran. `VaultHandler.burnCoin` additionally wraps its call in `try/catch {}`,
///      so an inner revert never surfaced as an invariant failure either.
///
///      State is seeded with `vm.store` against Coinflip's real layout — no contracts/*.sol
///      behaviour is mocked. `playerState` is mapping slot 2 (declaration order:
///      coinflipStakePacked=0, coinflipDayResultPacked=1, playerState=2) and `claimableStored` is
///      the low 128 bits of the struct's first slot.
contract VaultBurnCoinClaimableTest is DeployProtocol {
    /// @dev Coinflip.playerState mapping base slot.
    uint256 private constant PLAYERSTATE_SLOT = 2;

    /// @dev DGVF initial supply, minted to CREATOR in the DegenerusVaultShare constructor.
    uint256 private constant DGVF_INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @dev Claimable coinflip winnings seeded onto the VAULT for the redemption to draw against.
    uint128 private constant SEEDED_CLAIMABLE = 5_000 ether;

    function setUp() public {
        _deployProtocol();
    }

    /// @dev Seed `claimableStored` for `player` without disturbing the packed fields above it.
    function _seedClaimable(address player, uint128 amount) private {
        bytes32 base = keccak256(abi.encode(player, PLAYERSTATE_SLOT));
        uint256 word = uint256(vm.load(address(coinflip), base));
        // claimableStored occupies bits 0-127; preserve lastClaim / autoRebuyStartDay / enabled above.
        word = (word & ~uint256(type(uint128).max)) | uint256(amount);
        vm.store(address(coinflip), base, bytes32(word));
    }

    /// @notice A redemption succeeds while the vault holds claimable coinflip winnings, the payout
    ///         reaches the caller, and the claimable leg is load-bearing in the valuation.
    function test_BurnCoinSucceedsWhenVaultHoldsClaimableCoinflips() public {
        _seedClaimable(ContractAddresses.VAULT, SEEDED_CLAIMABLE);
        assertEq(
            coinflip.previewClaimCoinflips(ContractAddresses.VAULT),
            SEEDED_CLAIMABLE,
            "seed precondition: the vault previews the seeded claimable balance"
        );

        uint256 allowanceBefore = coin.vaultMintAllowance();
        uint256 reserve = allowanceBefore + SEEDED_CLAIMABLE;

        // Burn 1% of the DGVF supply — a clean pro-rata claim that avoids the full-supply REFILL branch.
        uint256 burnShares = DGVF_INITIAL_SUPPLY / 100;
        uint256 expected = (reserve * burnShares) / DGVF_INITIAL_SUPPLY;
        uint256 allowanceOnly = (allowanceBefore * burnShares) / DGVF_INITIAL_SUPPLY;
        assertGt(expected, 0, "the pro-rata entitlement under test must be nonzero");

        uint256 creatorBefore = coin.balanceOf(ContractAddresses.CREATOR);

        // Before the fix this reverted with an arithmetic panic (0x11) inside FLIP._transfer.
        vm.prank(ContractAddresses.CREATOR);
        uint256 flipOut = vault.burnCoin(burnShares);

        assertEq(flipOut, expected, "pro-rata payout values the claimable leg into the reserve");
        assertGt(
            flipOut,
            allowanceOnly,
            "the claimable leg is load-bearing: dropping it from the valuation would pay strictly less"
        );
        assertEq(
            coin.balanceOf(ContractAddresses.CREATOR),
            creatorBefore + flipOut,
            "the whole redemption reaches the caller"
        );
    }

    /// @notice The redemption draws the claimed portion from the vault's mint allowance, never from
    ///         a FLIP balance the vault structurally cannot hold.
    function test_VaultHoldsNoCirculatingFlipAcrossTheRedemption() public {
        _seedClaimable(ContractAddresses.VAULT, SEEDED_CLAIMABLE);
        assertEq(
            coin.balanceOf(ContractAddresses.VAULT),
            0,
            "precondition: the vault holds no circulating FLIP"
        );

        vm.prank(ContractAddresses.CREATOR);
        vault.burnCoin(DGVF_INITIAL_SUPPLY / 100);

        assertEq(
            coin.balanceOf(ContractAddresses.VAULT),
            0,
            "the vault still holds no circulating FLIP after the redemption"
        );
    }
}
