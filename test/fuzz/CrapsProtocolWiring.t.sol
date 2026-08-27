// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";

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
///           2. The real FLIP opens the sink the table actually uses — `burnCoin` takes entries —
///              and does NOT open a liquid mint to it, because every winning ships as coinflip
///              credit and a mint the table never calls is authority nothing bounds.
///           3. The real Coinflip honours both single and batch credit lanes used by battle pots
///              and run settlement.
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
        assertEq(ContractAddresses.CRAPS, address(crapsBattle), "ContractAddresses.CRAPS != the deployed CrapsBattle");
        assertGt(ContractAddresses.CRAPS.code.length, 0, "the CRAPS pin points at an address with no code");
    }

    /// @dev The burn sink is open to the table; the MINT is not, and that is the assertion. The
    ///      table is burn-only — winnings ship as coinflip credit — so a liquid mint would be a
    ///      standing authority with no call site to bound it.
    function test_flipOpensTheBurnSinkToCrapsAndNotTheMint() public {
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(PLAYER, 1000 ether);

        vm.prank(ContractAddresses.CRAPS);
        coin.burnCoin(PLAYER, 400 ether);
        assertEq(coin.balanceOf(PLAYER), 600 ether, "craps could not burn a stake");

        vm.prank(ContractAddresses.CRAPS);
        vm.expectRevert();
        coin.mintForGame(PLAYER, 1 ether);

        // Negative controls: the gates admit the table, not the world.
        vm.prank(STRANGER);
        vm.expectRevert();
        coin.mintForGame(PLAYER, 1 ether);

        vm.prank(STRANGER);
        vm.expectRevert();
        coin.burnCoin(PLAYER, 1 ether);
    }

    /// @dev Both payout lanes, with a stranger refused at each.
    function test_coinflipHonoursTheCrapsAddressForBothCreditLanes() public {
        vm.prank(ContractAddresses.CRAPS);
        coinflip.creditFlip(PLAYER, 100 ether);

        address[] memory players = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        players[0] = PLAYER;
        amounts[0] = 100 ether;
        vm.prank(ContractAddresses.CRAPS);
        coinflip.creditFlipBatch(players, amounts);

        vm.prank(STRANGER);
        vm.expectRevert();
        coinflip.creditFlip(PLAYER, 100 ether);

        vm.prank(STRANGER);
        vm.expectRevert();
        coinflip.creditFlipBatch(players, amounts);
    }

    /// @dev The table reads the game's lootbox-RNG index straight out of storage by slot number
    ///      (there is no typed getter). Against the real game that read must resolve and decode —
    ///      the craps suite's mock cannot show this, because the mock IS the assumption.
    function test_crapsReadsTheRealGamesLootboxIndex() public view {
        assertEq(crapsBattle.GAME(), address(game), "craps is not pointed at the deployed game");
        // Must not revert: a wrong slot or an unpinned GAME fails here, not in production.
        uint48 index = crapsBattle.currentIndex();
        assertEq(uint256(index), uint256(crapsBattle.currentIndex()), "index read is unstable");
    }

    /// @dev The user flow against every shipped dependency: real activity read, real FLIP burn,
    ///      real game-slot word lookup, permissionless settlement, and real coinflip credit. The word
    ///      is written directly only to stand in for the already-covered VRF lifecycle.
    function test_realProtocolPlaceRevealAndSettleFlow() public {
        Craps.Bets memory board;
        // Seven selected chips, spread within the four-a-leg cap; the dice place the other three.
        board.passLine = 4;
        board.place8 = 3;
        // Ten rounds deep. A bankroll of exactly one round is a walk absorbed at zero, which
        // never pays; ten gives the escalator room to leave a remainder the table has to settle.
        uint128 bankroll = 6000 ether;

        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(PLAYER, bankroll);

        // A zero-bounty custom slot exercises run settlement without adding a battle claim to
        // this wiring proof. CREATOR holds the deployed vault's DGVE majority.
        //
        // A REACHABLE goal, so the run comes home paying: a bust is DELETED rather than credited
        // to anyone, so a far goal — which is decided by the dice and busts far more often than
        // not — leaves nothing for this proof to measure.
        vm.prank(ContractAddresses.CREATOR);
        uint64 slot = crapsBattle.createBattle(
            600, 10, uint16(crapsBattle.MIN_BATTLE_GOAL_MULT()), 0, 0, uint40(block.timestamp + 1), false
        , 0);
        vm.prank(PLAYER);
        uint256 betId = crapsBattle.enterBattle(slot, board, 1);

        assertEq(coin.balanceOf(PLAYER), 0, "the real table did not burn the bankroll");
        assertEq(crapsBattle.betOf(betId).slot, slot, "the slip bound to the wrong slot");

        vm.warp(block.timestamp + 1);
        uint48 index = crapsBattle.closeBattle(slot);

        uint256 paid;
        for (uint256 nonce = 1; nonce <= 64; ++nonce) {
            uint256 word = uint256(keccak256(abi.encode("real craps flow", nonce)));
            bytes32 wordSlot = keccak256(abi.encode(uint256(index), uint256(34)));
            vm.store(address(game), wordSlot, bytes32(word));
            assertEq(crapsBattle.wordAt(index), word, "the real game word slot did not resolve");
            (, paid) = crapsBattle.previewSettlement(betId);
            if (paid != 0) break;
        }
        assertGt(paid, 0, "failed to find a paying deterministic fixture");

        uint256 stakeBefore = coinflip.coinflipAmount(PLAYER);
        vm.prank(STRANGER);
        crapsBattle.resolveSlot(slot, 1);

        // The win ships as next-day coinflip stake, not liquid FLIP: `creditFlip` against the
        // REAL Coinflip is the payout lane now, so the balance must stay at zero and the stake
        // must carry the whole award.
        assertEq(coinflip.coinflipAmount(PLAYER) - stakeBefore, paid, "the real credit missed the owner");
        assertEq(coin.balanceOf(PLAYER), 0, "a run's winnings minted liquid FLIP");
        assertTrue(crapsBattle.betOf(betId).settled, "the real slip did not settle");
    }
}
