// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {WalletTableLib} from "../../contracts/libraries/WalletTableLib.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";

/// @dev The wallet table root as the Game storage declares it.
contract WalletTableSlotHarness is DegenerusGameStorage {
    function walletsSlot() external pure returns (uint256 s) {
        assembly {
            s := wallets.slot
        }
    }
}

/// @dev Minimal stand-in for the Game's `extsload`, etched at the Game address.
contract WalletTableExtsloadHost {
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }
}

/// @notice `WalletTableLib.ownerOf` against a bare table.
contract WalletTableLibTest is Test {
    function setUp() public {
        vm.etch(ContractAddresses.GAME, type(WalletTableExtsloadHost).runtimeCode);
    }

    function _element(uint32 id, uint256 value) private {
        vm.store(ContractAddresses.GAME, GameSlotKeys.walletElement(id), bytes32(value));
    }

    function test_OwnersSlotIsTheWalletTableRoot() public {
        assertEq(WalletTableLib.OWNERS_SLOT, new WalletTableSlotHarness().walletsSlot());
    }

    function test_ElementZeroAndUnallocatedElementsReadZero() public {
        _element(1, uint160(address(0xA1)));
        _element(2, uint160(address(0xA2)));
        assertEq(WalletTableLib.ownerOf(0), address(0), "element 0 is never written");
        assertEq(WalletTableLib.ownerOf(1), address(0xA1));
        assertEq(WalletTableLib.ownerOf(3), address(0), "unallocated");
        assertEq(WalletTableLib.ownerOf(type(uint32).max), address(0), "unallocated");
    }

    function testFuzz_DecodesOnlyTheAccountKey(uint32 id, uint160 key, uint32 smurfOwner, uint64 halfPasses) public {
        uint256 element = uint256(key) | (uint256(smurfOwner) << 160) | (uint256(halfPasses) << 192);
        _element(id, element);
        assertEq(WalletTableLib.ownerOf(id), address(key), "low 160 bits only");
    }
}

/// @notice The same reads against the deployed Game's table.
contract WalletTableLibGameTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }

    function test_ProtocolIdsAndFreshRegistrations() public {
        assertEq(WalletTableLib.ownerOf(0), address(0));
        assertEq(WalletTableLib.ownerOf(1), ContractAddresses.VAULT);
        assertEq(WalletTableLib.ownerOf(2), ContractAddresses.SDGNRS);
        assertEq(WalletTableLib.ownerOf(3), ContractAddresses.GNRUS);
        address who = makeAddr("tableFresh");
        uint32 id = _giveWalletId(who);
        assertEq(WalletTableLib.ownerOf(id), who);
        assertEq(WalletTableLib.ownerOf(id + 1), address(0), "next element is unallocated");
    }

    function test_SmurfAndHalfPassBitsDoNotLeakIntoTheKey() public {
        address who = makeAddr("tableBits");
        uint32 id = _giveWalletId(who);
        bytes32 slot = GameSlotKeys.walletElement(id);
        uint256 element = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(element | (uint256(7) << 160) | (uint256(123) << 192)));
        assertEq(WalletTableLib.ownerOf(id), who);
    }
}
