// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title LinkDonationWalletIds -- the Admin LINK donation registers the donor and credits FLIP by ID
/// @notice A donation pays, so the Game's `creditMiddayRng` registers the donor and returns its
///         wallet ID; the Admin credits the FLIP reward to that ID. Past paid admission a new
///         donor's transfer reverts; an existing donor is still admitted and credited.
contract LinkDonationWalletIdsTest is DeployProtocol {
    bytes32 private constant WALLET_REGISTERED = keccak256("WalletRegistered(uint32,address)");
    bytes32 private constant LINK_CREDIT = keccak256("LinkCreditRecorded(address,uint256)");
    bytes32 private constant STAKE_UPDATED = keccak256("CoinflipStakeUpdated(uint32,uint24,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        require(admin.linkAmountToEth(1 ether) != 0, "harness: LINK/ETH feed not installed");
    }

    function _today() internal view returns (uint24) {
        return uint24((block.timestamp - 82_620) / 1 days) - uint24(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 1;
    }

    function _walletCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.WALLETS)));
    }

    function _lane(uint24 day, uint32 id) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(day >> 3), uint256(0)))));
        return uint32(uint256(vm.load(address(coinflip), slot)) >> ((uint256(day) & 7) * 32));
    }

    function _cachedId(address p) internal view returns (uint32) {
        return uint32(uint256(vm.load(address(coinflip), keccak256(abi.encode(p, uint256(2))))) >> 184);
    }

    /// @dev The donor's own ERC-677 transfer into the Admin.
    function _donate(address donor, uint256 amount) internal {
        mockLINK.mint(donor, amount);
        vm.prank(donor);
        mockLINK.transferAndCall(address(admin), amount, "");
    }

    function _registrations(Vm.Log[] memory logs) internal view returns (uint256 n, uint32 lastId, address lastOwner) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics[0] != WALLET_REGISTERED) continue;
            ++n;
            lastId = uint32(uint256(logs[i].topics[1]));
            lastOwner = address(uint160(uint256(logs[i].topics[2])));
        }
    }

    function _linkCredit(Vm.Log[] memory logs, address donor) internal view returns (uint256 credit) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(admin) || logs[i].topics[0] != LINK_CREDIT) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != donor) continue;
            credit = abi.decode(logs[i].data, (uint256));
        }
    }

    /// @notice A first donation registers the donor once (through creditMiddayRng), banks the
    ///         mid-day credit and stakes the FLIP reward under the returned ID; Coinflip's
    ///         address-keyed cache stays empty. A repeat donation reuses the ID.
    function test_NewDonor_RegistersThroughMiddayCredit_CreditedById() public {
        address donor = makeAddr("link_donor");
        uint32 expectedId = uint32(_walletCount());
        uint24 target = _today() + 1;

        vm.expectCall(address(game), abi.encodeCall(DegenerusGame.creditMiddayRng, (donor, 10 ether)), 1);
        vm.expectCall(address(coinflip), abi.encodeWithSelector(Coinflip.creditFlip.selector, expectedId), 2);
        vm.recordLogs();
        _donate(donor, 10 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 n, uint32 rid, address owner) = _registrations(logs);
        assertEq(n, 1, "exactly one WalletRegistered");
        assertEq(rid, expectedId);
        assertEq(owner, donor);
        assertEq(game.walletIdOf(donor), expectedId);
        assertEq(game.middayRngCredits(donor), 10 ether);
        uint256 credit = _linkCredit(logs, donor);
        assertGt(credit, 0, "the donation earned a FLIP reward");
        assertEq(_lane(target, expectedId), credit, "reward staked under the donor's ID");
        assertEq(coinflip.coinflipAmount(donor), credit);
        assertEq(_cachedId(donor), 0, "an ID credit never touches the address-keyed state");
        bool stake;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(coinflip) || logs[i].topics[0] != STAKE_UPDATED) continue;
            assertEq(uint32(uint256(logs[i].topics[1])), expectedId);
            stake = true;
        }
        assertTrue(stake);

        vm.recordLogs();
        _donate(donor, 1 ether);
        logs = vm.getRecordedLogs();
        (n,,) = _registrations(logs);
        assertEq(n, 0, "a repeat donor is not registered again");
        uint256 second = _linkCredit(logs, donor);
        assertGt(second, 0);
        assertEq(_lane(target, expectedId), credit + second);
        assertEq(game.middayRngCredits(donor), 11 ether);
    }

    /// @notice Past PAID_ADMISSION_WALLETS a new donor's ERC-677 transfer reverts (the hook bubbles
    ///         the Game's refusal) and moves no LINK; an existing donor is admitted and credited.
    function test_PastPaidAdmission_NewDonorReverts_ExistingDonorCredited() public {
        address old = makeAddr("link_donor_existing");
        _donate(old, 2 ether);
        uint32 oldId = game.walletIdOf(old);
        assertTrue(oldId != 0);
        uint24 target = _today() + 1;
        uint256 before = _lane(target, oldId);

        vm.store(address(game), bytes32(GameSlots.WALLETS), bytes32(uint256(3_000_000_001)));

        address fresh = makeAddr("link_donor_new");
        mockLINK.mint(fresh, 5 ether);
        vm.expectRevert(bytes("transferAndCall callback failed"));
        vm.prank(fresh);
        mockLINK.transferAndCall(address(admin), 5 ether, "");
        assertEq(mockLINK.balanceOf(fresh), 5 ether, "no LINK moved");
        assertEq(game.walletIdOf(fresh), 0);
        assertEq(game.middayRngCredits(fresh), 0);

        mockLINK.mint(address(admin), 5 ether);
        vm.expectRevert(abi.encodeWithSignature("E()"));
        vm.prank(address(mockLINK));
        admin.onTokenTransfer(fresh, 5 ether, "");

        _donate(old, 2 ether);
        assertGt(_lane(target, oldId), before, "existing donor credited by ID");
        assertEq(game.middayRngCredits(old), 4 ether);
    }
}
