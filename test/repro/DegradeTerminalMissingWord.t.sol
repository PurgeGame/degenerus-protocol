// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @dev Etch overlay for the full-protocol flow: a caught-up past-deadline ending at level 10
///      with a populated terminal cohort, plus a view of the ending's latches.
contract MissingWordSeeder is DegenerusGame, BucketSeed {
    function seedEnding(address holder) external {
        uint24 day = _simulatedDayIndex();
        level = 10;
        purchaseStartDay = day - 31;
        dailyIdx = day - 1;
        levelPrizePool[10] = 1000 ether;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        for (uint256 t; t < 256; ++t) _seedBucket(11, uint8(t), holder, t == 253 ? 1 : 4); // one gold six
    }

    /// @dev The applied terminal word vanishes while its applied/published flags stay.
    function dropTerminalWord() external {
        rngWordCurrent = RNG_WORD_WAITING;
    }

    function endingState() external view returns (uint256 dead, uint256 paid, uint256 pot, uint256 total, uint256 created) {
        return (_lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK), _goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK), deadPot, deadTotal, deadCreated);
    }
}

contract TerminalSinkStub {
    uint256 public burns;
    function burnAtGameOver() external { ++burns; }
    function tombstoneAtGameOver() external { ++burns; }
    function closeRedemptionBatch(uint256) external pure returns (uint256) { return 0; }
    function resolveTerminalRedemptions() external pure {}
}

/// @dev Module harness: the normal ending with its terminal word applied and published, except
///      that the word itself is missing. Seeds the state no chain path produces.
contract MissingWordDrainHarness is DegenerusGameGameOverModule, BucketSeed {
    function seed(uint24 lvl, address affiliateWinner) external returns (uint24 day) {
        day = _simulatedDayIndex();
        level = lvl;
        jackpotPhaseFlag = true;
        dailyIdx = day - 31;
        rngRequestDay = day;
        rngRequestTime = uint48(block.timestamp);
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
        _setRngTerminal();
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        rngLockedFlag = true;
        rngWordCurrent = RNG_WORD_WAITING;
        terminalAffiliate = affiliateWinner;
        for (uint8 q; q < 4; ++q) _seedBucketDistinct(lvl, uint8(q * 64 + 7), 512, uint160(0x10000 + uint256(q) * 0x10000));
    }

    function endingState()
        external view
        returns (bool ended, uint256 dead, uint256 paid, bool active, bool published, uint256 liabilities)
    {
        return (
            gameOver,
            _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK),
            _goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK),
            _rngRequestActive(),
            _rngSessionPublished(),
            claimablePool
        );
    }

    function deadState() external view returns (uint256 pot, uint256 total, uint256 created, uint256 traits) {
        return (deadPot, deadTotal, deadCreated, deadTraitCount);
    }

    function claimed(address who) external view returns (uint256) { return _claimableOf(who); }
}

/// @notice The normal ending's drain needs the terminal word. With distributable funds and no
///         word it latches the deterministic ending and pays nothing; the next terminal call
///         tallies the cohort and fixes the pot once. On the mineFlip chain the same state is a
///         Wait (request active, no word) that the 14-day dead window already resolves.
contract DegradeTerminalMissingWordTest is DeployProtocol {
    uint256 private constant WORD = 0x987654321;
    address private constant HOLDER = address(0x715E7);
    address private constant TOP = address(0xAFF1);
    bytes32 private constant AFFILIATE_PAID = keccak256("TerminalAffiliatePaid(address,uint24,uint256)");
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");

    bytes private realCode;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 500 days);
        realCode = address(game).code;
    }

    function _fixture(bytes memory data) private returns (bytes memory result) {
        vm.etch(address(game), type(MissingWordSeeder).runtimeCode);
        bool ok;
        (ok, result) = address(game).call(data);
        vm.etch(address(game), realCode);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    function _endingState() private returns (uint256 dead, uint256 paid, uint256 pot, uint256 total, uint256 created) {
        bytes memory data = _fixture(abi.encodeCall(MissingWordSeeder.endingState, ()));
        (dead, paid, pot, total, created) = abi.decode(data, (uint256, uint256, uint256, uint256, uint256));
    }

    function _reachPayout() private {
        _fixture(abi.encodeCall(MissingWordSeeder.seedEnding, (HOLDER)));
        vm.deal(address(game), 100 ether);
        vm.prank(address(game));
        affiliate.payAffiliate(1000 ether, bytes32(uint256(uint160(TOP))), address(0xB001), 11, true, 0);
        assertTrue(game.livenessTriggered(), "caught up past the deadline");
        game.mineFlip(); // latch + terminal request
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), WORD);
        game.mineFlip(); // apply the word
        assertFalse(game.gameOver(), "applying the word does not pay out");
    }

    /// @dev Chain route: the seeded state is a Wait, and the dead window ends the game without a word.
    function test_ChainWaitsThenTakesTheDeadEndingWithoutAWord() public {
        _reachPayout();
        _fixture(abi.encodeCall(MissingWordSeeder.dropTerminalWord, ()));
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
        vm.warp(block.timestamp + 14 days);
        vm.recordLogs();
        for (uint256 i; i < 20 && !game.gameOver(); ++i) game.mineFlip();
        assertTrue(game.gameOver(), "dead ending reached game over");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != AFFILIATE_PAID && logs[i].topics[0] != ETH_WIN, "no drawn award");
        }
        (uint256 dead, uint256 paid, uint256 pot, uint256 total, uint256 created) = _endingState();
        assertEq(dead, 1);
        assertEq(paid, 1);
        assertEq(pot, 100 ether, "the whole balance is the pot");
        assertEq(created, 255 * 4 + 1, "the applied cohort is tallied as created");
        assertGe(total, created * 100, "the pot divides over created plus queued weight");
        assertEq(game.claimableWinningsOf(TOP), 0, "the dead ending pays no affiliate");
        assertEq(address(game).balance, 100 ether, "nothing moved at the payout");

        uint256[] memory refs = new uint256[](1);
        refs[0] = uint256(5) << 64; // HOLDER's first ticket of trait 5
        game.claimDeadVrf(HOLDER, refs);
        uint256 perTrait = (pot * created * 100) / total / 256;
        assertEq(game.claimableWinningsOf(HOLDER), perTrait / 4, "one of trait 5's four equal shares");
    }

    /// @dev Drain route: the degraded branch itself, in the state no chain path produces.
    function test_DrainWithoutAWordLatchesTheDeadEndingAndPaysOnce() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 100 days);
        vm.etch(ContractAddresses.GAME, type(MissingWordDrainHarness).runtimeCode);
        MissingWordDrainHarness h = MissingWordDrainHarness(ContractAddresses.GAME);
        vm.etch(ContractAddresses.GNRUS, type(TerminalSinkStub).runtimeCode);
        vm.etch(ContractAddresses.SDGNRS, type(TerminalSinkStub).runtimeCode);
        vm.etch(ContractAddresses.COIN, type(TerminalSinkStub).runtimeCode);
        vm.mockCall(ContractAddresses.STETH_TOKEN, abi.encodeWithSignature("balanceOf(address)", address(h)), abi.encode(uint256(0)));
        uint24 day = h.seed(110, TOP);
        vm.deal(address(h), 1000 ether);
        // The stubs sit over deployed contracts whose slot 0 is live state: compare deltas.
        uint256 gnrusBurns = TerminalSinkStub(ContractAddresses.GNRUS).burns();
        uint256 sdgnrsBurns = TerminalSinkStub(ContractAddresses.SDGNRS).burns();
        uint256 coinBurns = TerminalSinkStub(ContractAddresses.COIN).burns();

        // The live terminal worker (mineFlip's Terminal stage) reaches the drain: the word is
        // marked applied and no cohort is queued.
        h.runGameOverAdvance(day, 110, gasleft());
        (bool ended, uint256 dead, uint256 paid, bool active, bool published, uint256 liabilities) = h.endingState();
        assertFalse(ended, "no payout without a word");
        assertEq(dead, 1, "deterministic ending latched");
        assertEq(paid, 0);
        assertFalse(active, "callback authority revoked");
        assertFalse(published, "stale publication cleared");
        assertEq(liabilities, 0, "nothing credited");
        assertEq(h.claimed(TOP), 0, "no affiliate share without a draw");
        assertEq(TerminalSinkStub(ContractAddresses.GNRUS).burns(), gnrusBurns, "no side effect before the latch");

        uint256 calls;
        while (paid == 0 && calls++ < 8) {
            h.runGameOverAdvance{gas: 10_000_000}(day, 110, 6_700_000);
            (ended, dead, paid,,, liabilities) = h.endingState();
        }
        assertTrue(ended, "dead ending completed");
        assertEq(paid, 1);
        (uint256 pot, uint256 total, uint256 created, uint256 traits) = h.deadState();
        assertEq(pot, 1000 ether, "the whole balance is the dead pot");
        assertEq(created, 2048, "every seeded ticket counted once");
        assertEq(traits, 4);
        assertEq(total, 2048 * 100);
        assertEq(liabilities, 0, "the pot is claimed, never pushed");
        assertEq(h.claimed(TOP), 0, "the dead ending pays no affiliate");
        assertEq(TerminalSinkStub(ContractAddresses.GNRUS).burns(), gnrusBurns + 1);
        assertEq(TerminalSinkStub(ContractAddresses.SDGNRS).burns(), sdgnrsBurns + 1);
        assertEq(TerminalSinkStub(ContractAddresses.COIN).burns(), coinBurns + 1);

        // Settled: a further terminal call leaves the fixed pot alone.
        h.runGameOverAdvance{gas: 10_000_000}(day, 110, 6_700_000);
        (uint256 potAgain,,,) = h.deadState();
        (,, paid,,, liabilities) = h.endingState();
        assertEq(potAgain, 1000 ether, "pot fixed once");
        assertEq(paid, 1);
        assertEq(liabilities, 0);
        assertEq(TerminalSinkStub(ContractAddresses.GNRUS).burns(), gnrusBurns + 1, "one-shot hooks run once");
    }
}
