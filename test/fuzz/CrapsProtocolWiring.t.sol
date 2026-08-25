// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Craps} from "../../contracts/Craps.sol";

/// @title Craps protocol wiring
/// @notice The craps suite proper runs against mocks — a mock slot reader, a mock FLIP, a mock
///         coinflip — because that is the only way to drive the RNG index and the dice
///         deterministically. That leaves exactly one thing unproven, and it is the thing a
///         testnet deploy actually depends on: that the craps table is WIRED to the real protocol.
///
///         Three facts make or break the deploy, and all three are compile-time constants that no
///         mock can vouch for:
///
///           1. `ContractAddresses.CRAPS` resolves to the deployed table. FLIP and Coinflip bake
///              that address in to authorize the sinks, so if the deploy order and the pin ever
///              disagree the table is authorized at an address that holds no code, and every
///              stake and payout reverts.
///           2. The real FLIP honours it for BOTH sinks — `burnCoin` takes the stake,
///              `mintForGame` pays the win. Authorizing one and not the other strands players
///              mid-game rather than failing loudly at placement.
///           3. The real Coinflip honours it for `creditFlip`, the rakeback lane.
///
///         Each is asserted with a negative control, because "the call did not revert" proves
///         nothing if the gate admits everyone.
contract CrapsProtocolWiringTest is DeployProtocol {
    address internal constant PLAYER = address(0xBEEF);
    address internal constant STRANGER = address(0xDEAD);

    function setUp() public {
        _deployProtocol();
    }

    /// @dev The pin and the deploy order agreeing is the whole ballgame: FLIP authorizes an
    ///      ADDRESS, not a contract, so a stale pin authorizes empty space.
    function test_crapsPinResolvesToTheDeployedTable() public view {
        assertEq(
            ContractAddresses.CRAPS,
            address(flipCraps),
            "ContractAddresses.CRAPS != the deployed FlipCraps"
        );
        assertGt(
            ContractAddresses.CRAPS.code.length,
            0,
            "the CRAPS pin points at an address with no code"
        );
    }

    /// @dev Both FLIP sinks, and a stranger refused at each. A table that can burn but not mint
    ///      takes stakes it can never pay.
    function test_flipHonoursTheCrapsAddressForBothSinks() public {
        vm.prank(ContractAddresses.CRAPS);
        coin.mintForGame(PLAYER, 1_000 ether);
        assertEq(coin.balanceOf(PLAYER), 1_000 ether, "craps could not mint a payout");

        vm.prank(ContractAddresses.CRAPS);
        coin.burnCoin(PLAYER, 400 ether);
        assertEq(coin.balanceOf(PLAYER), 600 ether, "craps could not burn a stake");

        // Negative controls: the gates admit the table, not the world.
        vm.prank(STRANGER);
        vm.expectRevert();
        coin.mintForGame(PLAYER, 1 ether);

        vm.prank(STRANGER);
        vm.expectRevert();
        coin.burnCoin(PLAYER, 1 ether);
    }

    /// @dev The rakeback lane. The comp ships as next-day coinflip stake, so a craps settlement
    ///      that cannot reach `creditFlip` reverts AFTER the payout mint.
    function test_coinflipHonoursTheCrapsAddressForTheRakebackLane() public {
        vm.prank(ContractAddresses.CRAPS);
        coinflip.creditFlip(PLAYER, 100 ether);

        vm.prank(STRANGER);
        vm.expectRevert();
        coinflip.creditFlip(PLAYER, 100 ether);
    }

    /// @dev The table reads the game's lootbox-RNG index straight out of storage by slot number
    ///      (there is no typed getter). Against the real game that read must resolve and decode —
    ///      the craps suite's mock cannot show this, because the mock IS the assumption.
    function test_crapsReadsTheRealGamesLootboxIndex() public view {
        assertEq(flipCraps.GAME(), address(game), "craps is not pointed at the deployed game");
        // Must not revert: a wrong slot or an unpinned GAME fails here, not in production.
        uint48 index = flipCraps.currentIndex();
        assertEq(uint256(index), uint256(flipCraps.currentIndex()), "index read is unstable");
    }

    /// @dev The user flow against every shipped dependency: real activity read, real FLIP burn,
    ///      real game-slot word lookup, permissionless settlement, and real FLIP payout. The word
    ///      is written directly only to stand in for the already-covered VRF lifecycle.
    function test_realProtocolPlaceRevealAndSettleFlow() public {
        Craps.Bets memory board;
        board.passLine = 600;
        uint128 bankroll = 600 ether;

        vm.prank(ContractAddresses.CRAPS);
        coin.mintForGame(PLAYER, bankroll);

        uint48 index = flipCraps.currentIndex();
        vm.prank(PLAYER);
        uint64 betId = flipCraps.placeSlip(board, bankroll, 0);

        assertEq(coin.balanceOf(PLAYER), 0, "the real table did not burn the bankroll");
        assertEq(flipCraps.betOf(betId).index, index, "the slip bound to the wrong table");

        uint256 paid;
        for (uint256 nonce = 1; nonce <= 64; ++nonce) {
            uint256 word = uint256(keccak256(abi.encode("real craps flow", nonce)));
            bytes32 wordSlot = keccak256(abi.encode(uint256(index), uint256(34)));
            vm.store(address(game), wordSlot, bytes32(word));
            assertEq(flipCraps.wordAt(index), word, "the real game word slot did not resolve");
            (,, paid) = flipCraps.previewSettlement(betId);
            if (paid != 0) break;
        }
        assertGt(paid, 0, "failed to find a paying deterministic fixture");

        uint64[] memory ids = new uint64[](1);
        ids[0] = betId;
        vm.prank(STRANGER);
        flipCraps.resolveBets(ids);

        assertEq(coin.balanceOf(PLAYER), paid, "the real FLIP payout missed the owner");
        assertTrue(flipCraps.betOf(betId).settled, "the real slip did not settle");
    }
}
