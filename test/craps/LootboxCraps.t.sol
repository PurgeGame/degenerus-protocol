// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Reads the two lootbox-RNG slot numbers straight off the audited storage declarations,
///     so the drift gate needs no build artifact and no external process.
contract SlotProbe is DegenerusGameStorage {
    function lootboxRngPackedSlot() external pure returns (uint256 s) {
        assembly { s := lootboxRngPacked.slot }
    }

    function lootboxRngWordByIndexSlot() external pure returns (uint256 s) {
        assembly { s := lootboxRngWordByIndex.slot }
    }

    function rngWordByDaySlot() external pure returns (uint256 s) {
        assembly { s := rngWordByDay.slot }
    }

}

/// @dev Adds only the replay taps the suite grades the binding with. It overrides nothing —
///      the doubles live at the pins (see CrapsPins), so every rule under test is the real one.
contract LootboxCrapsHarness is LootboxCraps {

    /// @dev The `resolveHandAt` / `resolveHandsAt` / `shooterDice` replay wrappers were cut from
    ///      production: they cost `CrapsBattle` its EIP-170 headroom and the paying path never called
    ///      one. What they existed to demonstrate is still a production property — the seed at an
    ///      index is a function of the index alone — so they are rebuilt here over the SHIPPED
    ///      `seedFor` / `handSeed`, with only the resolver behind them supplied by the oracle.
    CrapsOracle internal immutable oracle;

    constructor() {
        oracle = new CrapsOracle();
    }

    /// @dev The reader surface production keeps internal, restated for the suite. See
    ///      `test/craps/CrapsViews.sol` for why the shipped contract no longer carries it.
    bytes32 public constant CRAPS_SEED_DOMAIN = _CRAPS_SEED_DOMAIN;

    function currentIndex() external view returns (uint48) {
        return _currentIndex();
    }

    function wordAt(uint48 index) external view returns (uint256) {
        return _wordAt(index);
    }

    function seedFor(uint48 index) external view returns (bytes32) {
        return _seedFor(index);
    }

    function resolveHandAt(Craps.Bets calldata b, uint48 index)
        external
        view
        returns (CrapsOracle.Outcome memory)
    {
        return oracle.resolveHand(b, _seedFor(index));
    }

    function resolveHandsAt(Craps.Bets calldata b, uint48 index, uint256 hands)
        external
        view
        returns (CrapsOracle.Session memory)
    {
        return oracle.resolveHands(b, _seedFor(index), hands);
    }

    function shooterDice(uint48 index, uint256 handOrdinal)
        external
        view
        returns (uint8[] memory)
    {
        return oracle.handDice(handSeed(_seedFor(index), handOrdinal));
    }

}

/// @dev A FORWARDER and nothing else: it adds no state, overrides nothing, and each body is a
///      single call into the shipped internal. `currentIndex` / `wordAt` are non-virtual, so this
///      cannot stand between the test and what production runs — it only makes an internal
///      function externally observable.
contract ShippedProbe is LootboxCraps {
    function currentIndex() external view returns (uint48) {
        return _currentIndex();
    }

    function wordAt(uint48 index) external view returns (uint256) {
        return _wordAt(index);
    }
}

/// @title LootboxCraps binding suite
/// @notice The resolver's own rules are covered in Craps.t.sol. What matters here is the seam to
///         the protocol: that the slot decode matches the real storage layout, that a bet can only
///         ever be bound to an index whose word is still undrawn, and that every player at an index
///         settles against one and the same shooter.
contract LootboxCrapsTest is CrapsPins {
    LootboxCrapsHarness internal craps;

    uint24 internal constant U = 30;
    uint256 internal constant UW = 30e18;


    function setUp() public {
        _installPins();
        craps = new LootboxCrapsHarness();
    }



    // ---------------------------------------------------------------------------------------
    // Slot decode
    // ---------------------------------------------------------------------------------------

    /// @dev The index shares its slot with pending ETH, the threshold, a basefee ceiling and
    ///      several latches. Masking to 48 bits is the whole decode, and getting it wrong would
    ///      read a plausible-looking but wrong index rather than failing loudly.
    function test_indexDecodeIgnoresTheRestOfThePackedSlot() public {
        // Every bit above 47 set: pending value, threshold, basefee cap, latches, all noise here.
        _setIndexNoisy(1234, type(uint256).max >> 48);
        assertEq(craps.currentIndex(), 1234, "index must ignore the co-packed fields");

        _setIndexNoisy(type(uint48).max, 0);
        assertEq(craps.currentIndex(), type(uint48).max, "full-width index");
    }

    function test_wordLookupMatchesSolidityMappingSlot() public {
        _setWord(7, 0xABCDEF);
        assertEq(craps.wordAt(7), 0xABCDEF, "word at 7");
        assertEq(craps.wordAt(8), 0, "unset index reads zero");
        assertEq(craps.wordAt(8), 0, "unset index reads unresolved");
        assertTrue(craps.wordAt(7) != 0, "set index reads resolved");
    }




    function test_cannotResolveBeforeTheWordLands() public {
        _setIndexNoisy(5, 0);

        Craps.Bets memory b;
        b.passLine = U;

        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        craps.resolveHandAt(b, 5);
    }

    // ---------------------------------------------------------------------------------------
    // One table, one shooter
    // ---------------------------------------------------------------------------------------

    /// @dev The point of the design: friends who buy in at the same index are at the same table.
    ///      The dice belong to the index, so every player bound to it settles against the identical
    ///      shooter — same come-out, same point, same seven-out.
    function test_everyPlayerAtAnIndexGetsTheSameShooter() public {
        _setIndexNoisy(4, 0);
        _setWord(4, uint256(keccak256("vrf")));

        Craps.Bets memory b;
        b.passLine = U;
        b.place6 = U;

        uint8[] memory shooter = craps.shooterDice(4, 0);
        assertGt(shooter.length, 0, "no dice");

        // Whoever asks, whenever they ask, the table is the table.
        CrapsOracle.Outcome memory first = craps.resolveHandAt(b, 4);
        vm.prank(makeAddr("alice"));
        CrapsOracle.Outcome memory alice = craps.resolveHandAt(b, 4);
        vm.prank(makeAddr("bob"));
        CrapsOracle.Outcome memory bob = craps.resolveHandAt(b, 4);

        assertEq(alice.rolls, first.rolls, "alice saw a different shooter");
        assertEq(bob.rolls, first.rolls, "bob saw a different shooter");
        assertEq(alice.net, first.net, "alice settled differently on identical bets");
        assertEq(bob.net, first.net, "bob settled differently on identical bets");
        assertEq(shooter.length / 2, first.rolls, "published dice are not the settled hand");
    }

    /// @dev Load-bearing once the table is shared: the dice must not depend on what anyone bet, or
    ///      two friends at one table would disagree about what the shooter rolled.
    function test_theShooterDoesNotDependOnWhatWasBet() public {
        _setIndexNoisy(4, 0);
        _setWord(4, uint256(keccak256("vrf")));

        Craps.Bets memory lineOnly;
        lineOnly.passLine = U;

        Craps.Bets memory loadedUp;
        loadedUp.place5 = U;
        loadedUp.hard8 = U;

        CrapsOracle.Outcome memory thin = craps.resolveHandAt(lineOnly, 4);
        CrapsOracle.Outcome memory fat = craps.resolveHandAt(loadedUp, 4);

        assertEq(thin.rolls, fat.rolls, "the bets moved the dice");
        assertEq(thin.pointsMade, fat.pointsMade, "the bets moved the points");
    }

    /// @dev A group betting different session lengths still shares one run of shooters: they agree
    ///      hand for hand and differ only in where they stop.
    function test_sessionsAtOneIndexShareTheirShooters() public {
        _setIndexNoisy(4, 0);
        _setWord(4, uint256(keccak256("vrf")));

        Craps.Bets memory b;
        b.passLine = U;

        CrapsOracle.Session memory shortRun = craps.resolveHandsAt(b, 4, 3);
        CrapsOracle.Session memory longRun = craps.resolveHandsAt(b, 4, 10);

        assertEq(shortRun.hands, 3, "short run");
        assertEq(longRun.hands, 10, "long run");
        for (uint256 i = 0; i < 3; ++i) {
            assertEq(shortRun.ledger[i].rolls, longRun.ledger[i].rolls, "hand diverged");
            assertEq(shortRun.ledger[i].net, longRun.ledger[i].net, "settlement diverged");
        }
        assertEq(longRun.staked, UW * 10, "upfront charge");
        assertGe(longRun.net, -int256(longRun.staked), "lost more than the session stake");
    }

    function test_seedIsTheIndexAloneAndDomainSeparatedFromTheWord() public {
        uint256 word = uint256(keccak256("vrf"));
        _setIndexNoisy(4, 0);
        _setWord(4, word);

        bytes32 seed = craps.seedFor(4);
        assertTrue(seed != bytes32(word), "seed is the raw word");
        assertEq(
            seed,
            keccak256(abi.encode(craps.CRAPS_SEED_DOMAIN(), word, uint48(4))),
            "seed derivation"
        );

        // A different index is a different table, even under the same word.
        _setWord(5, word);
        assertTrue(craps.seedFor(5) != seed, "two indices collapsed to one table");
    }

    // ---------------------------------------------------------------------------------------
    // Drift gate
    // ---------------------------------------------------------------------------------------

    /// @dev The two slot constants are hand-pinned, so nothing in the compiler would notice if the
    ///      protocol re-laid out its storage — a re-layout would not break the build, it would
    ///      silently read some other field as the RNG index.
    ///
    ///      In-repo this is settled at COMPILE TIME rather than by inspecting a build artifact:
    ///      `SlotProbe` inherits the audited storage contract itself and reads `.slot` off the two
    ///      variables, so the figures below come from the same declarations `DegenerusGame` uses.
    ///      Moving either variable changes this test's answer, and renaming one fails to compile.
    ///      No `vm.ffi` — this repo keeps it disabled, and `FarFutureSalvageSwap` leans on that
    ///      being true as part of its own security argument.
    function test_lootboxRngSlotsMatchTheAuditedStorageLayout() public {
        SlotProbe probe = new SlotProbe();
        assertEq(
            probe.lootboxRngPackedSlot(),
            PACKED_SLOT,
            "lootboxRngPacked moved - update LOOTBOX_RNG_PACKED_SLOT"
        );
        assertEq(
            probe.lootboxRngWordByIndexSlot(),
            WORD_SLOT,
            "lootboxRngWordByIndex moved - update LOOTBOX_RNG_WORD_SLOT"
        );
        assertEq(probe.rngWordByDaySlot(), DAY_WORD_SLOT, "rngWordByDay moved - update RNG_WORD_BY_DAY_SLOT");

    }

    /// @dev With the seams gone there are no harness overrides left to bypass: `_currentIndex`
    ///      and `_wordAt` are the shipped, non-virtual functions, and they resolve through the
    ///      `ContractAddresses.GAME` pin. Production keeps them internal, so observing them takes
    ///      a subclass — but `ShippedProbe` only forwards, and neither function is virtual, so
    ///      what runs here is the shipped body against the etched double.
    function test_shippedPathReadsThroughThePinnedGame() public {
        assertTrue(ContractAddresses.GAME != address(0), "GAME is unpinned in this tree");

        _setIndex(77);
        _setWord(77, 0xBEEF);

        ShippedProbe shipped = new ShippedProbe();
        assertEq(shipped.GAME(), ContractAddresses.GAME, "GAME pin");
        assertEq(shipped.currentIndex(), 77, "shipped currentIndex did not read the pinned game");
        assertEq(shipped.wordAt(77), 0xBEEF, "shipped wordAt did not read the pinned game");
    }
}
