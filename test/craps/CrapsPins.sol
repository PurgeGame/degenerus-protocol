// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";

/// @dev The two things craps reads out of the live game: the raw lootbox-RNG slots and the
///      player's activity score. One double serves both because production reads both from the
///      single `ContractAddresses.GAME` pin.
contract MockGame {
    mapping(bytes32 => bytes32) public slots;
    mapping(address => uint256) public score;

    function set(bytes32 slot, bytes32 value) external {
        slots[slot] = value;
    }

    function setScore(address player, uint256 s) external {
        score[player] = s;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return slots[slot];
    }

    function playerActivityScore(address player) external view returns (uint256) {
        return score[player];
    }

    /// @dev The lootbox draw the table asks for when a window shuts. Counted rather than acted on:
    ///      what a suite needs to know is that the ask HAPPENED, since that one request carries
    ///      both the table's dice and the day's pending boxes.
    uint256 public lootboxRngCalls;

    function requestLootboxRng() external {
        ++lootboxRngCalls;
    }
}

/// @dev Stands in for FLIP's two authorized sinks, recording what the table burns and mints.
contract MockFlip {
    mapping(address => uint256) public burned;
    mapping(address => uint256) public minted;
    uint256 public totalMinted;
    uint256 public totalBurned;
    /// @dev Standing in for a reserve that cannot cover a burn: the real `burnCoin` reverts when
    ///      the target's balance and coinflip backing together fall short.
    mapping(address => bool) public burnRefused;

    error MockBurnRefused();

    function setBurnRefused(address target, bool refused) external {
        burnRefused[target] = refused;
    }

    function burnCoin(address target, uint256 amount) external {
        if (burnRefused[target]) revert MockBurnRefused();
        burned[target] += amount;
        totalBurned += amount;
    }

    function mintForGame(address to, uint256 amount) external {
        minted[to] += amount;
        totalMinted += amount;
    }

    /// @dev The paid-craps lane. The price arrives with its action flags in the LOW BYTE, so the
    ///      untagged gross is what gets recorded — burn totals stay comparable with `burnCoin`.
    ///      Returns the boon mask a test armed, and clears it: the real lane spends the Game's
    ///      boon lane on the first burn, so a second burn in the same transaction comes back empty.
    uint8 public nextBoonMask;
    uint8 public lastCrapsFlags;
    uint256 public crapsBurns;

    function setNextBoonMask(uint8 mask) external {
        nextBoonMask = mask;
    }

    function burnCoinForCraps(address target, uint256 grossAndFlags) external returns (uint8 mask) {
        if (burnRefused[target]) revert MockBurnRefused();
        uint256 gross = grossAndFlags & ~uint256(0xFF);
        lastCrapsFlags = uint8(grossAndFlags);
        burned[target] += gross;
        totalBurned += gross;
        ++crapsBurns;
        mask = nextBoonMask;
        nextBoonMask = 0;
        // The table no longer writes to the quest ledger itself: the burn lane reports the action,
        // so the mock forwards it the same way real FLIP does.
        if (lastCrapsFlags != 0) MockQuests(ContractAddresses.QUESTS).recordCrapsAction(target, lastCrapsFlags);
    }
}

/// @dev Records rakeback comps arriving through the flip-creditors lane.
contract MockCoinflip {
    mapping(address => uint256) public staked;
    uint256 public credits;
    uint256 public totalCredited;

    function creditFlip(address player, uint256 amount) external {
        _credit(player, amount);
    }

    /// @dev The batched lane a settle walk pays through: one call for a whole field. Mirrors the
    ///      real Coinflip, address(0) and zero-amount legs skipped.
    function creditFlipBatch(address[] calldata players, uint256[] calldata amounts) external {
        for (uint256 i = 0; i < players.length; ++i) {
            if (players[i] != address(0) && amounts[i] != 0) _credit(players[i], amounts[i]);
        }
        ++batches;
    }

    uint256 public batches;

    function _credit(address player, uint256 amount) private {
        staked[player] += amount;
        totalCredited += amount;
        ++credits;
    }
}

/// @title CrapsPins
/// @notice Installs the three protocol doubles AT the addresses production actually reads.
///
/// @dev The craps contracts resolve `ContractAddresses.GAME` / `.COIN` / `.COINFLIP` as
///      compile-time constants and call them directly — there is no virtual seam to override,
///      because a seam that exists only so a test can subclass it is production bytecode paid for
///      by every player. So the doubles are moved TO the pins instead of the pins being pointed at
///      the doubles.
///
///      `vm.etch` copies runtime code only, never storage. That is exactly the shape we want: each
///      double starts with empty storage at the pinned address, and because every setter and getter
///      below is invoked THROUGH that address, its writes and reads land in that address's storage.
///      (Immutables would not survive the copy — none of these doubles has any.)
/// @dev The vault, reduced to the one thing craps asks of it: whether an account holds the
///      majority. That answer is the whole authority behind the battle-creator roll.
contract MockVault {
    mapping(address => bool) internal _owners;

    function setOwner(address account, bool ok) external {
        _owners[account] = ok;
    }

    function isVaultOwner(address account) external view returns (bool) {
        return _owners[account];
    }
}

/// @dev The quest ledger, reduced to the one thing craps writes into it: the whole-day ticket's
///      streak credit. Records the calls so a suite can prove the cadence rather than the amount.
contract MockQuests {
    mapping(address => uint256) public streakAwarded;
    mapping(address => uint256) public streakCalls;
    uint24 public lastDay;

    function awardQuestStreakBonus(address player, uint16 amount, uint24 currentDay) external {
        streakAwarded[player] += amount;
        ++streakCalls[player];
        lastDay = currentDay;
    }

    /// @dev The combined craps report FLIP now makes. Bit 2 is the normal day-kept credit and bit 3
    ///      the high one, carrying the same +1/+5 the real ledger applies, so a suite still proves
    ///      the streak cadence through the path the table actually drives.
    uint256 public crapsActions;
    uint8 public lastCrapsFlags;

    function recordCrapsAction(address player, uint8 actionFlags) external {
        ++crapsActions;
        lastCrapsFlags = actionFlags;
        if (actionFlags & 0xC != 0) {
            streakAwarded[player] += (actionFlags & 0x8) != 0 ? 5 : 1;
            ++streakCalls[player];
            // The real ledger reads the clock itself rather than being told the day, so the mock
            // does too — same library, same boundary.
            lastDay = GameTimeLib.currentDayIndex();
        }
    }
}

abstract contract CrapsPins is Test {
    /// @dev SETTLE EVERYTHING. `resolveSlot`'s second argument is a GAS ALLOWANCE, not a seat
    ///      count, so "the whole field" is now a budget no field can exhaust rather than a head
    ///      count above the biggest fixture. The internal seat ceiling still bounds one call.
    uint64 internal constant WHOLE_FIELD = type(uint64).max;

    MockGame internal game;
    MockFlip internal flip;
    MockCoinflip internal coinflip;
    MockVault internal vault;
    MockQuests internal quests;
    address internal vaultOwner = makeAddr("vaultOwner");

    uint256 internal constant PACKED_SLOT = 33;
    uint256 internal constant WORD_SLOT = 34;
    uint256 internal constant DAY_WORD_SLOT = 10;

    function _installPins() internal {
        vm.etch(ContractAddresses.GAME, address(new MockGame()).code);
        vm.etch(ContractAddresses.COIN, address(new MockFlip()).code);
        vm.etch(ContractAddresses.COINFLIP, address(new MockCoinflip()).code);
        vm.etch(ContractAddresses.VAULT, address(new MockVault()).code);
        vm.etch(ContractAddresses.QUESTS, address(new MockQuests()).code);
        quests = MockQuests(ContractAddresses.QUESTS);
        game = MockGame(ContractAddresses.GAME);
        flip = MockFlip(ContractAddresses.COIN);
        coinflip = MockCoinflip(ContractAddresses.COINFLIP);
        vault = MockVault(ContractAddresses.VAULT);
        vault.setOwner(vaultOwner, true);
    }

    /// @dev Writes the packed slot the way the protocol lays it out: index in bits 0..47, with
    ///      unrelated fields above it that the decode must ignore.
    function _setIndex(uint48 index) internal {
        game.set(bytes32(PACKED_SLOT), bytes32(uint256(index)));
    }

    function _setIndexNoisy(uint48 index, uint256 noiseAbove) internal {
        game.set(bytes32(PACKED_SLOT), bytes32(uint256(index) | (noiseAbove << 48)));
    }

    function _setWord(uint48 index, uint256 word) internal {
        game.set(keccak256(abi.encode(uint256(index), WORD_SLOT)), bytes32(word));
    }

    /// @dev `CrapsBattle.MAX_GOAL_MULT`, restated so the shared base needs no live table. A target
    ///      this far out is not reachable in practice, which is what a fixture with nothing to
    ///      prove about the goal wants: the run is decided by the dice, not by a take-profit.
    uint256 internal constant GOAL_FAR_MULT = 1000;

    /// @dev A battle's terms. Every slip is a battle slip now, so this is what every placement
    ///      in these suites is built from. `randomChips` defaults to THREE — the ordinary entry,
    ///      where the board carries SEVEN whole chips and the dice place the other three. The
    ///      only other legal value is ten, where the board carries nothing but the round's total.
    /// @dev The one door a fixture has now: open a battle on these terms as the authorized
    ///      creator and hand back its slot. `played` is the round in whole FLIP (ten chips),
    ///      `bankMult` how many of those rounds deep the bankroll runs, `goalMult` the target as
    ///      a multiple of that bankroll.
    function _openBattle(CrapsViews c, uint32 played, uint8 bankMult, uint16 goalMult, uint24 su, uint16 bar)
        internal
        returns (uint64 slot)
    {
        // The optimizer may cache the TIMESTAMP opcode across `vm.warp` calls in one test. The
        // cheatcode getter observes the actual warped clock for every loop iteration.
        uint40 closeTime = uint40(vm.getBlockTimestamp() + 1 hours);
        vm.prank(vaultOwner);
        // MULTI-ENTRY: the general fixture, so a suite can seat one address more than once when
        // it wants twin slips on one table. The single-entry default is exercised directly by
        // `test_aCustomBattleChoosesWhetherOneAddressMayTakeSeveralSeats`.
        slot = c.createBattle(played, bankMult, goalMult, su, bar, closeTime, true, 0);
    }

    function _openBattle(CrapsViews c, uint32 played, uint8 bankMult, uint16 goalMult, uint24 su)
        internal
        returns (uint64 slot)
    {
        return _openBattle(c, played, bankMult, goalMult, su, 0);
    }

    /// @dev A battle carrying a HIGH-ROLLER lane at `h`. Everything else matches `_openBattle`,
    ///      so a suite can put the two side by side and attribute any difference to the lane.
    function _openHigh(CrapsViews c, uint32 played, uint8 bankMult, uint16 goalMult, uint24 su, uint16 h)
        internal
        returns (uint64 slot)
    {
        uint40 closeTime = uint40(vm.getBlockTimestamp() + 1 hours);
        vm.prank(vaultOwner);
        slot = c.createBattle(played, bankMult, goalMult, su, 0, closeTime, true, h);
    }

    /// @dev A battle whose target the dice will never reach — the goal-agnostic fixture, for
    ///      anything that wants the run decided by the shooter rather than by a take-profit.
    function _openFar(CrapsViews c, uint32 played, uint8 bankMult, uint24 su) internal returns (uint64 slot) {
        return _openBattle(c, played, bankMult, uint16(GOAL_FAR_MULT), su, 0);
    }

    /// @dev Shut a battle onto `index` and land `word` on it. The index is chosen BY the close,
    ///      so it is pinned here first and handed back for the caller to assert against.
    function _closeOn(CrapsViews c, uint64 slot, uint48 index, uint256 word) internal returns (uint48) {
        // A close takes `currentIndex() + 1`, so the live index is set one BELOW the table the
        // caller wants it to land on.
        _setIndex(index - 1);
        // Warp to the slot's OWN close time rather than by a relative amount: a sweeping fixture
        // opens each battle at whatever `block.timestamp` its last iteration left behind, so a
        // fixed step drifts and eventually opens a battle that is already past its close.
        (,, uint256 terms) = c.customBattleOf(slot);
        uint256 closeAt = (terms >> 73) & 0xFFFFFFFFFF;
        if (block.timestamp < closeAt) vm.warp(closeAt);
        uint48 taken = c.closeBattle(slot);
        _setWord(taken, word);
        return taken;
    }

    /// @dev The protocol's DAILY word lane — a different mapping from the per-index lootbox words
    ///      above, and the one the bonus battle paces itself on.
    /// @dev An empty claim list — the id-range lane takes one on every call, and most fixtures
    ///      are only settling.
    uint64[] internal _noIds;

    // ── What a settlement handed over ───────────────────────────────────────

    /// @dev One payment a settlement made.
    struct PaidOut {
        uint256 betId;
        address player;
        uint256 amount;
    }

    /// @dev Settle a field and report the POT it paid, separately from everything else that call
    ///      credited.
    ///
    ///      A battle pays the instant its last seat scores, inside `resolveSlot`, so a BALANCE
    ///      taken across that call holds the winner's own run credit and the pot added together.
    ///      Any fixture that subtracts one balance from another is therefore measuring the sum,
    ///      and a pot assertion written that way is asserting against the wrong number. The log is
    ///      where the two are still separate, so a pot is read through here.
    function _resolveForPots(CrapsViews c, uint64 slot, uint64 budget) internal returns (PaidOut[] memory) {
        vm.recordLogs();
        c.resolveSlot(slot, budget);
        return _potsIn(vm.getRecordedLogs());
    }

    /// @dev Every pot payment in a log stream, in the order the fields finished.
    function _potsIn(Vm.Log[] memory logs) internal pure returns (PaidOut[] memory out) {
        bytes32 sig = keccak256("CrapsBattlePaid(uint256,bytes32,address,uint256)");
        out = new PaidOut[](logs.length);
        uint256 n;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 4 || logs[i].topics[0] != sig) continue;
            out[n++] = PaidOut(
                uint256(logs[i].topics[1]),
                address(uint160(uint256(logs[i].topics[3]))),
                abi.decode(logs[i].data, (uint256))
            );
        }
        assembly {
            mstore(out, n)
        }
    }

    /// @dev Every LANE payment in a stream, of one kind. `rider` picks a sole high roller's
    ///      return, which rides home on that seat's own run; clearing it picks the one payment a
    ///      CONTESTED lane makes to the best of its seats.
    function _lanePaymentsIn(Vm.Log[] memory logs, bool rider) internal pure returns (PaidOut[] memory out) {
        bytes32 sig = keccak256("CrapsHighRollerPaid(uint256,bytes32,address,uint256,bool)");
        out = new PaidOut[](logs.length);
        uint256 n;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 4 || logs[i].topics[0] != sig) continue;
            (uint256 amount, bool bankrollRider) = abi.decode(logs[i].data, (uint256, bool));
            if (bankrollRider != rider) continue;
            out[n++] = PaidOut(uint256(logs[i].topics[1]), address(uint160(uint256(logs[i].topics[3]))), amount);
        }
        assembly {
            mstore(out, n)
        }
    }

    /// @dev Settle a field and report the ONE pot it paid. Fails the fixture where the settlement
    ///      paid none or more than one, so a test can never quietly assert against a payment that
    ///      did not happen.
    function _onlyPot(CrapsViews c, uint64 slot, uint64 budget) internal returns (PaidOut memory) {
        PaidOut[] memory pots = _resolveForPots(c, slot, budget);
        assertEq(pots.length, 1, "the settlement did not pay exactly one pot");
        return pots[0];
    }

    /// @dev Settle a field and report every LANE payment of one kind that it made.
    function _resolveForLane(CrapsViews c, uint64 slot, uint64 budget, bool rider)
        internal
        returns (PaidOut[] memory)
    {
        vm.recordLogs();
        c.resolveSlot(slot, budget);
        return _lanePaymentsIn(vm.getRecordedLogs(), rider);
    }

    /// @dev Settle a field and report BOTH payments it can make: the main pot, and a contested
    ///      lane's. One call finishes the field and pays the two together, so they are separated
    ///      by which event carried them rather than by which transaction did.
    function _resolveForBoth(CrapsViews c, uint64 slot, uint64 budget)
        internal
        returns (PaidOut[] memory pots, PaidOut[] memory lane)
    {
        vm.recordLogs();
        c.resolveSlot(slot, budget);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        pots = _potsIn(logs);
        lane = _lanePaymentsIn(logs, false);
    }

    function _setDailyWord(uint24 day, uint256 word) internal {
        game.set(keccak256(abi.encode(uint256(day), DAY_WORD_SLOT)), bytes32(word));
    }
}
