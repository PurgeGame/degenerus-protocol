// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
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
    /// @dev SETTLE EVERYTHING. `resolveSlot`'s second argument is a gas allowance, not a seat
    ///      count, so a budget no field can exhaust is what "the whole field" now means.
    uint64 internal constant WIRING_WHOLE_FIELD = type(uint64).max;

    address internal constant PLAYER = address(0xBEEF);
    address internal constant STRANGER = address(0xDEAD);
    address internal constant KEEPER = address(0xC0FFEE);

    /// @dev The afking module reached DIRECTLY, not through the Game — its remaining keeper
    ///      readers are pure, so they need no storage context.
    GameAfkingModule internal constant keeper = GameAfkingModule(ContractAddresses.GAME_AFKING_MODULE);

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
        // Seven selected chips, spread within the three-a-leg cap; the dice place the other three.
        board.passLine = 3;
        board.place8 = 3;
        board.place9 = 1;
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
        crapsBattle.resolveSlot(slot, WIRING_WHOLE_FIELD);

        // The win ships as next-day coinflip stake, not liquid FLIP: `creditFlip` against the
        // REAL Coinflip is the payout lane now, so the balance must stay at zero and the stake
        // must carry the whole award.
        assertEq(coinflip.coinflipAmount(PLAYER) - stakeBefore, paid, "the real credit missed the owner");
        assertEq(coin.balanceOf(PLAYER), 0, "a run's winnings minted liquid FLIP");
        assertTrue(crapsBattle.betOf(betId).settled, "the real slip did not settle");
    }

    /// @dev The vault forwards the same packed board the table takes. Exercise both doors against
    ///      the real contracts, including the two high bits that must never overlap standing.
    function test_theVaultForwardsThePackedCrapsBoard() public {
        vm.prank(ContractAddresses.CREATOR);
        uint64 slot = crapsBattle.createBattle(
            600, 1, uint16(crapsBattle.MIN_BATTLE_GOAL_MULT()), 0, 0, uint40(block.timestamp + 1), false, 0
        );

        uint32 board = uint32(3 | (3 << 12) | (1 << 15));
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(address(vault), 600 ether);
        vm.prank(ContractAddresses.CREATOR);
        uint256 betId = vault.crapsEnterBattle(slot, board, 1);

        CrapsBattle.Bet memory bet = crapsBattle.betOf(betId);
        assertEq(bet.player, address(vault), "the proxy seated its owner instead of the vault");
        assertEq(bet.chips, board, "the packed board changed across the vault call");

        uint32 amended = uint32((3 << 9) | (1 << 18) | (3 << 24));
        vm.prank(ContractAddresses.CREATOR);
        vault.crapsAmendSlip(betId, amended);

        assertEq(crapsBattle.betOf(betId).chips, amended, "the amended packed board changed across the vault call");

        for (uint256 bit = 30; bit < 32; ++bit) {
            uint32 overflowing = board | uint32(1 << bit);
            vm.prank(ContractAddresses.CREATOR);
            vm.expectRevert(CrapsBattle.BadRandomCount.selector);
            vault.crapsAmendSlip(betId, overflowing);

            vm.prank(ContractAddresses.CREATOR);
            vm.expectRevert(CrapsBattle.BadRandomCount.selector);
            crapsBattle.setVaultBoard(overflowing);
        }
    }

    /// @dev THE CRANK REACHES THE TABLE. `armBonusWindow` and `resolveSlot` are permissionless on
    ///      the table itself, so the risk was never authority — it was that a window shuts on a
    ///      clock nobody is watching. `mineFlip` now takes both jobs as its last leg and pays a
    ///      flat FLIP for either, which is what puts a keeper on the schedule.
    ///
    ///      Driven through the REAL Game, the REAL table and the REAL Coinflip credit lane,
    ///      because the wiring is the whole claim: the module reaches CRAPS by pin, and the
    ///      bounty lands as coinflip stake rather than liquid FLIP like every other crank's.
    function test_mineFlipShutsAWindowAndWalksItsField() public {
        // The fixture clock sits an hour into a protocol day, so period 1 is still taking bets
        // and its close is the next one to come round.
        // Genesis is a warm-up day with no windows; play from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        uint24 today = crapsBattle.currentDayIndex();
        _landDayWord(today, uint256(keccak256("mineflip craps day")));
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();

        // A real seat in the window, so the field the walk settles is not empty.
        (uint128 bankroll,,,,,) = crapsBattle.bonusTermsFor(today, 1);
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(PLAYER, uint256(bankroll) * 4);
        Craps.Bets memory board;
        board.passLine = 3;
        board.place8 = 3;
        board.place9 = 1;
        vm.prank(PLAYER);
        crapsBattle.enterBonusBattle(1, board, 1);

        uint64 slot = uint64(uint256(today) * crapsBattle.BONUS_SLOTS_PER_DAY() + 2);
        assertEq(crapsBattle.slotIndexOf(slot), 0, "the window was armed before anything shut it");

        // Past period 1's close. The genesis+1 warp leaves a day's advance owed, and that is
        // fine: the crank loop below absorbs the advance arms first — craps is the LAST category,
        // exactly as production orders it — and the bounty arithmetic counts only craps cranks.
        vm.warp(vm.getBlockTimestamp() + 4 hours);

        // ── The ARM. The cursor works OLDEST-FIRST, so period 0's window is shut and settled
        // before this one is touched — each crank does one piece and pays one flat FLIP for it.
        vm.recordLogs();
        (uint48 index,) = _crankUntilArmed(slot);
        // The CATEGORY, not just the amount: the crank has three other legs and the event is how
        // an indexer tells which one earned. The loop may have paid advance-category bounties on
        // its way — what matters here is that the LAST crank, the one that armed the window, was
        // booked as the craps leg.
        assertEq(_minerBountyKind(vm.getRecordedLogs()), 4, "the credit was not booked as the craps leg");
        assertEq(coin.balanceOf(KEEPER), 0, "the craps bounty minted liquid FLIP");

        // The word cannot exist in the block that took the index, which is exactly why the walk
        // is a LATER crank's job. Stand it in the way the flow test above does.
        bytes32 wordSlot = keccak256(abi.encode(uint256(index - 1), uint256(34)));
        vm.store(address(game), wordSlot, bytes32(uint256(keccak256("mineflip craps table"))));

        // ── The WALK. The cursor moves, and the same flat FLIP pays for it.
        uint256 before = coinflip.coinflipAmount(KEEPER);
        assertEq(crapsBattle.bonusCursorOf(slot), 0, "the field had already been walked");
        vm.prank(KEEPER);
        game.mineFlip();
        assertGt(crapsBattle.bonusCursorOf(slot), 0, "the crank did not walk the shut field");
        assertEq(coinflip.coinflipAmount(KEEPER) - before, 1 ether, "the walk did not pay the flat FLIP");
    }

    /// @dev THE ADVANCE STILL COMES FIRST. The craps leg is deliberately in the ELSE branch: an
    ///      advance is already a multi-million-gas call, and a settle batch stacked on top of it
    ///      would push the crank past the ceiling the protocol sizes every chunk against. So a
    ///      window that is owed a shutting waits for a crank that is not advancing.
    function test_theAdvanceLegStillPreemptsTheCrapsLeg() public {
        // Genesis is a warm-up day with no windows; play from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        uint24 today = crapsBattle.currentDayIndex();
        _landDayWord(today, uint256(keccak256("mineflip craps day")));
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();

        uint64 slot = uint64(uint256(today) * crapsBattle.BONUS_SLOTS_PER_DAY() + 2);
        // Far enough on that period 1 has long stopped taking bets AND a day has turned over, so
        // both legs have work and only one of them may run.
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "the fixture owes no advance, so nothing is being preempted");

        vm.prank(KEEPER);
        try game.mineFlip() {} catch {}
        assertEq(crapsBattle.slotIndexOf(slot), 0, "the craps leg ran alongside an advance");
    }

    /// @dev THE BATCH IS SIZED BY MEASURED WORK, NOT BY CAUTION AND NOT BY A HEAD COUNT. A crank
    ///      that has the call to itself hands the table whatever the box legs left of the shared
    ///      walk budget, priced at `CRAPS_GAS_PER_UNIT`; the table meters itself against it and
    ///      stops on the first seat that crosses it. So a bust-heavy field walks far more seats
    ///      than a paying one for the same gas, and the cursor carries a deeper field to the next
    ///      crank either way.
    function test_oneCrankSpendsItsWholeWorkBudgetAndStrandsNothing() public {
        // Genesis is a warm-up day with no windows; play from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        uint24 today = crapsBattle.currentDayIndex();
        _landDayWord(today, uint256(keccak256("mineflip craps day")));
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();

        // A field deeper than one batch, so the BUDGET is what stops the walk and not the field.
        (uint128 bankroll,,,,,) = crapsBattle.bonusTermsFor(today, 1);
        Craps.Bets memory board;
        board.passLine = 3;
        board.place8 = 3;
        board.place9 = 1;
        uint256 seated = 100;
        for (uint256 i = 0; i < seated; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("bigfield", i)))));
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame(who, uint256(bankroll) * 4);
            vm.prank(who);
            crapsBattle.enterBonusBattle(1, board, 1);
        }

        uint64 slot = uint64(uint256(today) * crapsBattle.BONUS_SLOTS_PER_DAY() + 2);
        vm.warp(block.timestamp + 4 hours);
        // OLDEST-FIRST: the cursor settles period 0's window before this one arms.
        (uint48 index,) = _crankUntilArmed(slot);
        vm.store(address(game), keccak256(abi.encode(uint256(index - 1), uint256(34))), bytes32(uint256(1)));

        uint256 g = gasleft();
        vm.prank(KEEPER);
        game.mineFlip(); // the walk
        uint256 used = g - gasleft();
        uint64 walked = crapsBattle.bonusCursorOf(slot);

        emit log_named_uint("seats settled in one crank", walked);
        emit log_named_uint("crank gas                 ", used);
        // THE CRANK SPENDS A WORK BUDGET, NOT A SEAT COUNT, so what is asserted here is the
        // envelope and not a head count: the old flat eighty was wrong in both directions, and
        // how many seats this particular word buys is the table's business. The distribution
        // across all nine formats is in `test/fuzz/CrapsKeeperBudgetGas.t.sol`.
        assertGt(walked, 1, "the crank barely moved the field");
        assertLt(used, 16_700_000, "the crank passed the protocol's hard per-transaction ceiling");
        assertLt(used, 9_500_000, "the crank passed the protocol's per-chunk target");

        // And the rest follows on later cranks rather than being stranded.
        vm.prank(KEEPER);
        game.mineFlip();
        assertGt(crapsBattle.bonusCursorOf(slot), walked, "the tail of the field was stranded");
    }

    /// @dev THE ONE PIECE OF A SEAT THE METER CANNOT SEE, measured against the REAL Coinflip.
    ///      Everything else a seat costs happens inside the settle loop and is already on the
    ///      meter when it is read; the batched bankroll return happens after it. So the resolver
    ///      reserves for it per RECIPIENT, and this is where the two reserve constants come from.
    ///
    ///      Measured in the conservative shape: DISTINCT recipients with no stake on the target
    ///      day, which is the dearest the lane can be — a cold slot per player.
    function test_probe_coinflipBatchCreditCost() public {
        uint256[6] memory sizes = [uint256(0), 1, 2, 4, 8, 16];
        uint256 prev;
        uint256 fixedCost;
        for (uint256 s = 0; s < 6; ++s) {
            uint256 n = sizes[s];
            address[] memory who = new address[](n);
            uint256[] memory amt = new uint256[](n);
            for (uint256 i = 0; i < n; ++i) {
                who[i] = address(uint160(uint256(keccak256(abi.encode("cold", s, i)))));
                amt[i] = 1 ether;
            }
            vm.prank(ContractAddresses.CRAPS);
            uint256 g = gasleft();
            coinflip.creditFlipBatch(who, amt);
            uint256 used = g - gasleft();
            emit log_named_uint("creditFlipBatch, cold recipients", n);
            emit log_named_uint("  gas                           ", used);
            if (n != 0) {
                emit log_named_uint("  marginal vs previous size     ", (used - prev) / (n - sizes[s - 1] == 0 ? 1 : n - sizes[s - 1]));
            } else {
                fixedCost = used;
            }
            prev = used;
        }

        // A REPEAT recipient, and a WARM day slot: both are cheaper, which is why the reserve is
        // taken from the cold distinct case and not from an average.
        address repeat = address(uint160(uint256(keccak256("repeat"))));
        address[] memory one = new address[](1);
        uint256[] memory oneAmt = new uint256[](1);
        one[0] = repeat;
        oneAmt[0] = 1 ether;
        vm.startPrank(ContractAddresses.CRAPS);
        uint256 gc = gasleft();
        coinflip.creditFlipBatch(one, oneAmt);
        uint256 cold = gc - gasleft();
        gc = gasleft();
        coinflip.creditFlipBatch(one, oneAmt);
        uint256 warm = gc - gasleft();
        vm.stopPrank();
        emit log_named_uint("one cold recipient              ", cold);
        emit log_named_uint("same recipient again (warm)     ", warm);
        emit log_named_uint("empty batch fixed cost          ", fixedCost);
    }

    /// @dev AND IT PAYS FOR WORK, NOT FOR CALLING. A table with nothing owed hands the crank
    ///      nothing — otherwise the leg is a faucet anyone can crank in a loop.
    function test_mineFlipPaysNothingWhenTheTableIsIdle() public {
        // No day opened, so no window exists to shut and no field to walk.
        uint256 before = coinflip.coinflipAmount(KEEPER);
        vm.prank(KEEPER);
        try game.mineFlip() {} catch {}
        assertEq(coinflip.coinflipAmount(KEEPER), before, "an idle table still paid the crank");
    }

    /// @dev `MinerBounty(kind, miner, flipAmount)`'s category, out of a crank's logs. Zero when
    ///      the crank paid nothing at all.
    function _minerBountyKind(Vm.Log[] memory logs) internal pure returns (uint8) {
        bytes32 sig = keccak256("MinerBounty(uint8,address,uint256)");
        // The LAST bounty in the stream: a crank loop may pay advance-category bounties on its
        // way to the craps leg, and the final crank is the one under test.
        uint8 last;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) {
                (uint8 kind, ) = abi.decode(logs[i].data, (uint8, uint256));
                last = kind;
            }
        }
        return last;
    }

    /// @dev Crank `mineFlip` until `slot` is armed, feeding the CURSOR's own pending word each
    ///      round: the scheduled keeper works oldest-first and will not pass an armed field whose
    ///      word has not landed, so a fixture that wants a later window shut walks the earlier
    ///      ones through settlement the same way the live protocol would.
    /// @return index The armed slot's table index.
    /// @return cranks How many cranks it took — each one paid the flat bounty for real progress.
    function _crankUntilArmed(uint64 slot) internal returns (uint48 index, uint256 cranks) {
        for (; cranks < 24 && index == 0; ) {
            uint64 at = crapsBattle.keeperSlot();
            uint48 pending = crapsBattle.slotIndexOf(at);
            if (pending != 0 && crapsBattle.wordAt(pending - 1) == 0) {
                _landTableWordW(pending - 1, uint256(keccak256(abi.encode("cursor-feed", at))));
            }
            vm.prank(KEEPER);
            game.mineFlip();
            ++cranks;
            index = crapsBattle.slotIndexOf(slot);
        }
        assertGt(index, 0, "the cursor never armed the window under test");
    }

    function _landTableWordW(uint48 index, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(index), uint256(34))), bytes32(word));
    }

    /// @dev Land a day's committed word in the Game slot the table reads it out of.
    function _landDayWord(uint24 day, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(day), uint256(10))), bytes32(word));
        assertEq(crapsBattle.dailyWordAt(day), word, "the day word did not land where the table reads it");
    }

    // The keeper's duplicated window ladder — and the drift gate that held it to the table's —
    // are gone: the table owns the scheduled cursor now, so there is no second copy to drift.
}
