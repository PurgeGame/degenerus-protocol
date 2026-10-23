// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {BoundedDeployProtocol} from "../helpers/BoundedDeployProtocol.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {LoanSeizureGasBase, SeizureGasSeeder} from "./LoanSeizureGas.t.sol";

contract BoundedDeityPurchaseGasTest is BoundedDeployProtocol, BoundedGasProbe {
    address private constant BUYER = address(0xDE17);
    address private constant PRIOR = address(0xDE18);
    function setUp() public { _deployBounded(true); vm.deal(BUYER, 1000 ether); vm.deal(PRIOR, 1000 ether); }
    function _purchase(string memory label, uint8 symbol, uint256 price) private {
        _measureBounded(label, address(game), BUYER, price,
            abi.encodeCall(game.purchaseDeityPass, (uint32(0), symbol, bytes32(0))), false);
    }
    function test_G4_FirstOccupiedWord() public { _purchase("G4_genesis_word", 1, 24 ether); }
    function test_G4_FirstEmptyWord() public { _purchase("G4_empty_word", 8, 24 ether); }
    function test_G4_LastSymbol() public { _purchase("G4_last_symbol", 31, 24 ether); }
    function test_G4_SecondSymbolInWord() public {
        vm.prank(PRIOR); game.purchaseDeityPass{value: 24 ether}(0, 8, bytes32(0));
        _purchase("G4_second_in_word", 9, 25 ether);
    }
}

contract BoundedDeitySeizureGasTest is LoanSeizureGasBase, BoundedGasProbe {
    function setUp() public { _setUpCase(5, true, true, true); }
    function test_G4_LastSymbolSeizure() public {
        _etch();
        _measureBounded("G4_seize_symbol31", address(game), address(this), 0,
            abi.encodeCall(SeizureGasSeeder.seize, ()), false);
        _unetch();
        (, address payee,) = game.resolveAccount_g502(root, address(0));
        assertEq(payee, address(sdgnrs));
    }
}
