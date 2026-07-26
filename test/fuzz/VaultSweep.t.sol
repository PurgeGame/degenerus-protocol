// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Minimal ERC721 standing in for "some random shit sent to the vault" — an outside NFT
///      with no protocol relationship, which is exactly the case sweepNft exists to rescue.
contract StrayNft {
    mapping(uint256 => address) public ownerOf;

    function mint(address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, "not owner");
        ownerOf[tokenId] = to;
    }
}

/// @title VaultSweep — foreign-asset rescue out of DegenerusVault.
/// @notice The vault can receive assets it has no other handling for: LINK recovered from a
///         retired VRF subscription, and any NFT an outside party sends it. Both would be
///         stranded without a sweep. What must NOT be sweepable is anything backing holder
///         accounting — for ERC20 that is stETH, and nothing else.
contract VaultSweepTest is DeployProtocol {
    event TokenSwept(address indexed token, address indexed to, uint256 amount);
    event NftSwept(address indexed token, address indexed to, uint256 tokenId);

    /// @dev DegenerusVaultShare mints INITIAL_SUPPLY of DGVE to CREATOR, so CREATOR clears the
    ///      >50.1% test in the vault's private _isVaultOwner. vm.mockCall cannot help here: the
    ///      modifier reads the private function, not the external getter.
    address private vaultOwner;
    address private outsider;
    StrayNft private nft;

    uint256 private constant PARKED = 500 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        vaultOwner = ContractAddresses.CREATOR;
        outsider = makeAddr("sweep_outsider");
        require(vault.isVaultOwner(vaultOwner), "harness: CREATOR is not the vault owner");

        // LINK parked in the vault, as shutdownVrf / retrySubCancel would leave it.
        mockLINK.mint(address(vault), PARKED);

        nft = new StrayNft();
        nft.mint(address(vault), 7);
    }

    // ──────────────────────────────────────────────────────────────────────
    // sweepToken
    // ──────────────────────────────────────────────────────────────────────

    function test_sweepToken_rejectsNonVaultOwner() public {
        vm.prank(outsider);
        vm.expectRevert(bytes4(keccak256("NotVaultOwner()")));
        vault.sweepToken(address(mockLINK), outsider, 0);
    }

    function test_sweepToken_rejectsZeroRecipient() public {
        vm.prank(vaultOwner);
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        vault.sweepToken(address(mockLINK), address(0), 0);
    }

    /// @notice stETH sits here as a real balance backing DGVE and can never be swept.
    function test_sweepToken_rejectsProtectedSteth() public {
        vm.prank(vaultOwner);
        vm.expectRevert(bytes4(keccak256("ProtectedToken()")));
        vault.sweepToken(ContractAddresses.STETH_TOKEN, vaultOwner, 0);
    }

    /// @notice FLIP is deliberately NOT protected: FLIP redirects VAULT-destined transfers and
    ///         mints into vaultMintAllowance, so the vault never holds a FLIP balance. It fails
    ///         on having nothing to send, not on being excluded — pinning why the guard was
    ///         dropped rather than kept as dead code.
    function test_sweepToken_flipIsUnprotectedButUnholdable() public {
        assertEq(coin.balanceOf(address(vault)), 0, "vault holds a FLIP balance");

        vm.prank(vaultOwner);
        vm.expectRevert(bytes4(keccak256("Insufficient()")));
        vault.sweepToken(ContractAddresses.COIN, vaultOwner, 0);
    }

    /// @notice A FLIP transfer aimed at the vault lands in allowance, never in balanceOf.
    function test_flipTransferToVaultBecomesAllowance() public {
        uint256 allowanceBefore = coin.vaultMintAllowance();

        vm.prank(address(game));
        coin.mintForGame(address(vault), 1_000 ether);

        assertEq(coin.balanceOf(address(vault)), 0, "FLIP landed as a vault balance");
        assertEq(
            coin.vaultMintAllowance() - allowanceBefore,
            1_000 ether,
            "FLIP did not land in vaultMintAllowance"
        );
    }

    function test_sweepToken_zeroAmountSweepsFullBalance() public {
        vm.expectEmit(true, true, false, true, address(vault));
        emit TokenSwept(address(mockLINK), vaultOwner, PARKED);

        vm.prank(vaultOwner);
        vault.sweepToken(address(mockLINK), vaultOwner, 0);

        assertEq(mockLINK.balanceOf(address(vault)), 0, "LINK left in the vault");
        assertEq(mockLINK.balanceOf(vaultOwner), PARKED, "LINK did not reach the recipient");
    }

    function test_sweepToken_partialAmount() public {
        vm.prank(vaultOwner);
        vault.sweepToken(address(mockLINK), vaultOwner, 200 ether);

        assertEq(mockLINK.balanceOf(address(vault)), PARKED - 200 ether, "wrong remainder");
        assertEq(mockLINK.balanceOf(vaultOwner), 200 ether, "wrong amount sent");
    }

    function test_sweepToken_revertsOverBalance() public {
        vm.prank(vaultOwner);
        vm.expectRevert(bytes4(keccak256("Insufficient()")));
        vault.sweepToken(address(mockLINK), vaultOwner, PARKED + 1);
    }

    // ──────────────────────────────────────────────────────────────────────
    // sweepNft
    // ──────────────────────────────────────────────────────────────────────

    function test_sweepNft_rejectsNonVaultOwner() public {
        vm.prank(outsider);
        vm.expectRevert(bytes4(keccak256("NotVaultOwner()")));
        vault.sweepNft(address(nft), outsider, 7);
    }

    function test_sweepNft_rejectsZeroRecipient() public {
        vm.prank(vaultOwner);
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        vault.sweepNft(address(nft), address(0), 7);
    }

    /// @notice The case this exists for: an unrelated NFT sent to the vault gets out.
    function test_sweepNft_rescuesStrayNft() public {
        assertEq(nft.ownerOf(7), address(vault), "fixture did not park the NFT");

        vm.expectEmit(true, true, false, true, address(vault));
        emit NftSwept(address(nft), vaultOwner, 7);

        vm.prank(vaultOwner);
        vault.sweepNft(address(nft), vaultOwner, 7);

        assertEq(nft.ownerOf(7), vaultOwner, "stray NFT not rescued");
    }

    /// @notice Deity passes are soulbound, so the sweep cannot move them and needs no
    ///         exclusion for them — the token reverts on its own.
    function test_sweepNft_soulboundSelfExcludes() public {
        vm.prank(vaultOwner);
        vm.expectRevert();
        vault.sweepNft(address(deityPass), vaultOwner, 1);
    }
}
