// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";

import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

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
    uint32 internal constant CREDIT_ID = 0xBEEF;
    address internal constant STRANGER = address(0xDEAD);
    address internal constant KEEPER = address(0xC0FFEE);
    /// @dev Extra seats in the walked window (see test_mineFlipShutsAWindowAndWalksItsField).
    uint256 internal constant WALK_FIELD = 24;
    /// @dev A realistic mineFlip allowance (owner gas rule: per-call success and progress only).
    uint256 internal constant REALISTIC_CALL_GAS = 10_000_000;
    bytes32 internal constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 internal constant MINER_BOUNTY_SIG = keccak256("MinerBounty(uint8,address,uint256)");

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
        coin.mintForGame(PLAYER, 1000);

        vm.prank(ContractAddresses.CRAPS);
        coin.burnCoin(PLAYER, 400);
        assertEq(coin.balanceOf(PLAYER), 600, "craps could not burn a stake");

        vm.prank(ContractAddresses.CRAPS);
        vm.expectRevert();
        coin.mintForGame(PLAYER, 1);

        // Negative controls: the gates admit the table, not the world.
        vm.prank(STRANGER);
        vm.expectRevert();
        coin.mintForGame(PLAYER, 1);

        vm.prank(STRANGER);
        vm.expectRevert();
        coin.burnCoin(PLAYER, 1);
    }

    /// @dev Both payout lanes, with a stranger refused at each.
    function test_coinflipHonoursTheCrapsAddressForBothCreditLanes() public {
        vm.prank(ContractAddresses.CRAPS);
        coinflip.creditFlip(CREDIT_ID, 100);

        uint32[] memory players = new uint32[](1);
        uint256[] memory amounts = new uint256[](1);
        players[0] = CREDIT_ID;
        amounts[0] = 100;
        vm.prank(ContractAddresses.CRAPS);
        coinflip.creditFlipBatch(players, amounts);

        vm.prank(STRANGER);
        vm.expectRevert();
        coinflip.creditFlip(CREDIT_ID, 100);

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

    /// @dev The user flow against every shipped dependency: real mint-history read, real FLIP burn,
    ///      real game-slot word lookup, settlement by mineFlip's Craps read stage, and real coinflip
    ///      credit. The word
    ///      is written directly only to stand in for the already-covered VRF lifecycle.
    function test_realProtocolPlaceRevealAndSettleFlow() public {
        Craps.Bets memory board;
        // Seven selected chips, spread within the three-a-leg cap; the dice place the other three.
        board.passLine = 3;
        board.place8 = 3;
        board.place9 = 1;
        // Ten rounds deep. A bankroll of exactly one round is a walk absorbed at zero, which
        // never pays; ten gives the escalator room to leave a remainder the table has to settle.
        uint128 bankroll = 6000;

        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(PLAYER, uint256(bankroll) * 105 / 100);

        // A zero-bounty custom slot exercises run settlement without adding a battle claim to
        // this wiring proof. CREATOR holds the deployed vault's DGVE majority.
        //
        // A REACHABLE goal, so the run comes home paying: a bust is DELETED rather than credited
        // to anyone, so a far goal — which is decided by the dice and busts far more often than
        // not — leaves nothing for this proof to measure.
        vm.prank(ContractAddresses.CREATOR);
        uint64 slot = crapsBattle.createBattle(
            600, 10, uint16(crapsBattle.MIN_BATTLE_GOAL_MULT()), 0, uint40(block.timestamp + 1), false
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
            RecyclingState.seedWord(address(game), index, bytes32(word));
            assertEq(crapsBattle.wordAt(index), word, "the real game word slot did not resolve");
            (, paid) = crapsBattle.previewSettlement(betId);
            if (paid != 0) break;
        }
        assertGt(paid, 0, "failed to find a paying deterministic fixture");

        // The Craps read stage takes only the frontier field of a read cohort whose earlier
        // consumers (tickets, boxes, bets, Decimator) have finished: the read-cohort gate
        // (6d0e64b09). Small engine calls run those stages and stop before the first whole seat,
        // leaving the field to the read stage itself.
        for (uint256 i; i < 32 && game.rngConsumerStage() != 6; ++i) game.mineFlip{gas: 800_000}();
        assertEq(game.rngConsumerStage(), 6, "the cohort reached its Craps read stage");
        assertEq(crapsBattle.bonusCursorOf(slot), 0, "the field is still unsettled for the read stage");

        // Any caller's mineFlip runs the read stage; the money goes to the slip's owner.
        uint256 stakeBefore = coinflip.coinflipAmount(PLAYER);
        vm.prank(STRANGER);
        game.mineFlip();

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
            600, 1, uint16(crapsBattle.MIN_BATTLE_GOAL_MULT()), 0, uint40(block.timestamp + 1), false, 0
        );

        uint32 board = uint32(3 | (3 << 12) | (1 << 15));
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(address(vault), 630);
        vm.prank(ContractAddresses.CREATOR);
        uint256 betId = vault.crapsEnterBattle(slot, board, 1);

        CrapsViews.Bet memory bet = crapsBattle.betOf(betId);
        assertEq(bet.player, address(vault), "the proxy seated its owner instead of the vault");
        assertEq(bet.chips, board, "the packed board changed across the vault call");

        uint32 amended = uint32((3 << 9) | (1 << 18) | (3 << 24));
        vm.prank(ContractAddresses.CREATOR);
        vault.crapsAmendSlip(betId, amended);

        assertEq(crapsBattle.betOf(betId).chips, amended, "the amended packed board changed across the vault call");

        for (uint256 bit = 30; bit < 32; ++bit) {
            uint32 overflowing = board | uint32(1 << bit);
            vm.prank(ContractAddresses.CREATOR);
            vm.expectRevert(CrapsBattleStorage.BadRandomCount.selector);
            vault.crapsAmendSlip(betId, overflowing);

            vm.prank(ContractAddresses.CREATOR);
            vm.expectRevert(CrapsBattleStorage.BadRandomCount.selector);
            vault.crapsSetPreferredBoard(overflowing);
        }
    }

    function test_vaultPreferredBoardWrapperUsesVaultIdentityAndOwnerGate() public {
        uint32 board = uint32(3 | (3 << 12) | (1 << 15));
        vm.prank(STRANGER);
        vm.expectRevert(bytes4(keccak256("NotVaultOwner()")));
        vault.crapsSetPreferredBoard(board);
        assertEq(crapsBattle.preferredBoardOf(game.walletIdOf(address(vault))), 0);

        vm.prank(ContractAddresses.CREATOR);
        vault.crapsSetPreferredBoard(board);
        assertEq(crapsBattle.preferredBoardOf(game.walletIdOf(address(vault))), board);
        assertEq(crapsBattle.preferredBoardOf(game.walletIdOf(ContractAddresses.CREATOR)), 0);

        vm.mockCall(address(game), abi.encodeWithSignature("rngLocked()"), abi.encode(true));
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(CrapsBattleStorage.BetLocked.selector);
        vault.crapsSetPreferredBoard(0);
        assertEq(crapsBattle.preferredBoardOf(game.walletIdOf(address(vault))), board);
        vm.clearMockedCalls();

        vm.prank(ContractAddresses.CREATOR);
        vault.crapsSetPreferredBoard(0);
        assertEq(crapsBattle.preferredBoardOf(game.walletIdOf(address(vault))), 0);
    }

    /// @dev THE CRANK REACHES THE TABLE. The table's scheduled work runs only inside `mineFlip`,
    ///      so the risk is not authority — it is that a window shuts on a clock nobody is
    ///      watching. `mineFlip` arms in its Maintenance stage and settles in its Craps read stage,
    ///      in schedule order, and pays for the measured work, which is what puts a keeper on the
    ///      schedule.
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
        // More seats, so the walk measures past the miner's unpaid first MIN_REWARDED_GAS and the
        // measured-gas bounty (72fc06f6c) is observable rather than zero.
        for (uint256 i; i < WALK_FIELD; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("walkfield", i)))));
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame(who, uint256(bankroll) * 4);
            vm.prank(who);
            crapsBattle.enterBonusBattle(1, board, 1);
        }

        uint64 slot = uint64(uint256(today) * crapsBattle.BONUS_SLOTS_PER_DAY() + 2);
        assertEq(crapsBattle.slotIndexOf(slot), 0, "the window was armed before anything shut it");

        // Past period 1's close. The genesis+1 warp leaves a day's advance owed, and that is
        // fine: the crank loop below absorbs the advance arms first — craps is the LAST category,
        // exactly as production orders it — and the bounty arithmetic counts only craps cranks.
        vm.warp(vm.getBlockTimestamp() + 5 hours + 10 minutes); // period 1 shuts 6h03m in

        // ── The ARM. The cursor works OLDEST-FIRST, so period 0's window is shut and settled
        // before this one is touched. A nonzero base fee prices the miner's pay: measured gas above
        // an unpaid first MIN_REWARDED_GAS at min(basefee, cap) (72fc06f6c; Foundry's basefee is 0).
        vm.fee(1 gwei);
        uint256 armStake = coinflip.coinflipAmount(KEEPER);
        vm.recordLogs();
        (uint48 index,) = _crankUntilArmed(slot);
        // There is one miner bounty kind now (60d31f775 retired the per-leg kinds 1..4; MinerWork's
        // firstAction names the stage). Every bounty the arm walk paid is that kind, paid to the
        // keeper, and lands as coinflip stake, never liquid FLIP.
        _assertMinerPaysAsStake(vm.getRecordedLogs(), coinflip.coinflipAmount(KEEPER) - armStake);
        assertEq(coin.balanceOf(KEEPER), 0, "the craps bounty minted liquid FLIP");

        // The word cannot exist in the block that took the index, which is exactly why the walk
        // is a LATER crank's job. Stand it in the way the flow test above does.
        RecyclingState.seedWord(address(game), index - 1, bytes32(uint256(keccak256("mineflip craps table"))));

        // ── The WALK. The cursor moves, and the measured work pays for it.
        uint256 before = coinflip.coinflipAmount(KEEPER);
        assertEq(crapsBattle.bonusCursorOf(slot), 0, "the field had already been walked");
        uint256 dueAt = _minerRewardDueAt();
        bool lockedAtStart = game.rngLocked();
        vm.recordLogs();
        this.walkAtNonzeroFee();
        assertGt(crapsBattle.bonusCursorOf(slot), 0, "the crank did not walk the shut field");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 paid = _assertMinerPaysAsStake(logs, coinflip.coinflipAmount(KEEPER) - before);
        (, uint256 measured,) = _minerWork(logs);
        emit log_named_uint("walk crank measured gas", measured);
        emit log_named_uint("walk crank bounty      ", paid);
        assertGt(measured, 1_000_000, "the walk measured past the unpaid first million");
        assertEq(paid, _expectedMinerPay(measured, lockedAtStart, dueAt), "the walk is paid its measured gas");
        assertGt(paid, 0, "the walk did not pay");
        assertEq(coin.balanceOf(KEEPER), 0, "the walk bounty minted liquid FLIP");
    }

    /// @dev Keep the fee cheat and protocol call in one execution frame. Under --isolate,
    ///      a top-level protocol call rebuilds its transaction environment after vm.fee.
    function walkAtNonzeroFee() external {
        require(msg.sender == address(this));
        vm.fee(1 gwei);
        vm.prank(KEEPER);
        game.mineFlip();
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
        vm.warp(vm.getBlockTimestamp() + 5 hours + 10 minutes); // period 1 shuts 6h03m in
        // OLDEST-FIRST: the cursor settles period 0's window before this one arms.
        (uint48 index,) = _crankUntilArmed(slot);
        RecyclingState.seedWord(address(game), index - 1, bytes32(uint256(2)));

        uint256 g = gasleft();
        vm.prank(KEEPER);
        game.mineFlip{gas: REALISTIC_CALL_GAS}(); // the walk, at a realistic allowance
        uint256 used = g - gasleft();
        uint64 walked = crapsBattle.bonusCursorOf(slot);

        emit log_named_uint("seats settled in one crank", walked);
        emit log_named_uint("crank gas                 ", used);
        // THE CRANK SPENDS A WORK BUDGET, NOT A SEAT COUNT, so what is asserted here is the
        // envelope and not a head count: how many seats this particular word buys is the table's
        // business. The distribution across all nine formats is in
        // `test/fuzz/CrapsKeeperBudgetGas.t.sol`. Owner gas rule (2026-10-03): the engine admits
        // checkpoints while the supplied allowance covers the next declared bound, so a whole call
        // is never bounded here; the call is given a realistic 10M allowance and must succeed and
        // make progress. The per-chunk settle bound (96-seat cap) is pinned in test/craps/CrapsGas.t.sol.
        assertGt(walked, 1, "the crank barely moved the field");

        // And the rest follows on later cranks rather than being stranded.
        vm.prank(KEEPER);
        game.mineFlip{gas: REALISTIC_CALL_GAS}();
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
            uint32[] memory who = new uint32[](n);
            uint256[] memory amt = new uint256[](n);
            for (uint256 i = 0; i < n; ++i) {
                who[i] = uint32(0x1000 * (s + 1) + i);
                amt[i] = 1;
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
        uint32 repeat = 0x7777;
        uint32[] memory one = new uint32[](1);
        uint256[] memory oneAmt = new uint256[](1);
        one[0] = repeat;
        oneAmt[0] = 1;
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
        // No day opened, so no window exists to shut and no field to walk. A nonzero base fee
        // prices any miner pay (Foundry's default basefee of zero would price every call at zero).
        vm.fee(1 gwei);
        assertEq(game.nextMinerAction(), 0, "fixture: the engine is idle (MinerAction.Idle)");
        uint256 before = coinflip.coinflipAmount(KEEPER);
        vm.prank(KEEPER);
        vm.expectRevert(DegenerusGame.NoWork.selector);
        game.mineFlip();
        assertEq(coinflip.coinflipAmount(KEEPER), before, "an idle table still paid the crank");
    }

    /// @dev Every `MinerBounty` in `logs` is the single miner kind (1), paid to KEEPER, and the
    ///      bounties sum to the keeper's coinflip stake delta and to the MinerWork-reported pay.
    function _assertMinerPaysAsStake(Vm.Log[] memory logs, uint256 stakeDelta) internal returns (uint256 paid) {
        uint256 reported;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == MINER_BOUNTY_SIG) {
                (uint8 kind, uint256 amount) = abi.decode(logs[i].data, (uint8, uint256));
                assertEq(kind, 1, "every miner bounty is the single miner kind");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), KEEPER, "the bounty went to the keeper");
                paid += amount;
            } else if (logs[i].topics[0] == MINER_WORK_SIG && logs[i].emitter == address(game)) {
                (,, uint256 reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                reported += reward;
            }
        }
        assertEq(paid, reported, "MinerWork reports exactly the bounty paid");
        assertEq(stakeDelta, paid, "the bounty landed as coinflip stake");
    }

    /// @dev The last MinerWork(caller, firstAction, executionGas, flipReward) in `logs`.
    function _minerWork(Vm.Log[] memory logs) internal pure returns (uint8 first, uint256 measured, uint256 reward) {
        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == MINER_WORK_SIG) {
                (first, measured, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                seen = true;
            }
        }
        require(seen, "no MinerWork event");
    }

    /// @dev Mirror of the miner's one clock (DegenerusGameMinerModule._minerRewardDueAt): the later
    ///      of the latest VRF request (slot-0 rngRequestTime) and the current day reset.
    function _minerRewardDueAt() internal view returns (uint256 due) {
        due = uint48(uint256(vm.load(address(game), bytes32(0))) >> 48);
        uint256 ts = vm.getBlockTimestamp();
        uint256 reset = ts - (ts - 82_620) % 1 days;
        if (reset > due) due = reset;
    }

    /// @dev Mirror of the miner pay: (measured - 1M) * min(basefee, 0.5 gwei << steps) * 1000 FLIP
    ///      * (0.3x + 0.45x per 30 minutes, x2 under the lock) / ticket price (72fc06f6c). KEEPER holds
    ///      no pass; the test runs at a 1 gwei base fee.
    function _expectedMinerPay(uint256 measured, bool lockedAtStart, uint256 dueAt) internal view returns (uint256) {
        if (measured <= 1_000_000) return 0;
        uint256 ts = vm.getBlockTimestamp();
        uint256 steps = (ts > dueAt ? ts - dueAt : 0) / 30 minutes;
        if (steps > 4) steps = 4;
        uint256 cap = 0.5 gwei << steps;
        uint256 rate = 1 gwei < cap ? 1 gwei : cap;
        uint256 bps = (3_000 + 4_500 * steps) * (lockedAtStart ? 2 : 1);
        uint256 legacy = (measured - 1_000_000) * rate * 1000 ether * bps / (game.mintPrice() * 10_000);
        return legacy == 0 ? 0 : legacy < 1 ether ? 1 : legacy / 1 ether;
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
        RecyclingState.seedWord(address(game), index, bytes32(word));
    }

    /// @dev Land a day's committed word in the Game slot the table reads it out of.
    function _landDayWord(uint24 day, uint256 word) internal {
        RecyclingState.seedDailyWord(address(game), uint24(day), word);
        assertEq(crapsBattle.dailyWordAt(day), word, "the day word did not land where the table reads it");
    }

    // The keeper's duplicated window ladder — and the drift gate that held it to the table's —
    // are gone: the table owns the scheduled cursor now, so there is no second copy to drift.
}
